import JellyfinKit
import SwiftUI

struct HomeView: View {
    let client: JellyfinClient

    @Environment(AppNavigator.self) private var navigator
    @State private var resume: [BaseItemDto] = []
    @State private var nextUp: [BaseItemDto] = []
    /// "Recently Added in <library>" shelves, in sidebar order.
    @State private var recent: [(library: BaseItemDto, items: [BaseItemDto])] = []
    @State private var errorMessage: String?
    @State private var hasLoaded = false

    var body: some View {
        ScrollView {
            PageHeading(title: "Home")
            VStack(alignment: .leading, spacing: 32) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                        .padding(.horizontal, 24)
                }
                if !resume.isEmpty {
                    Shelf(title: "Continue Watching", items: resume, style: .landscape, client: client, playsDirectly: true)
                }
                if !nextUp.isEmpty {
                    Shelf(title: "Next Up", items: nextUp, style: .landscape, client: client, playsDirectly: true)
                }
                ForEach(recent, id: \.library.id) { entry in
                    Shelf(title: "Recently Added in \(entry.library.name ?? "Library")", items: entry.items,
                          style: .poster, client: client)
                }
                if hasLoaded && resume.isEmpty && nextUp.isEmpty && recent.isEmpty && errorMessage == nil {
                    ContentUnavailableView(
                        "Nothing in progress",
                        systemImage: "play.circle",
                        description: Text("Start something from one of your libraries.")
                    )
                    .padding(.top, 80)
                }
            }
            .padding(.bottom, 24)
        }
        .pageTitle("Home")
        .onReceive(NotificationCenter.default.publisher(for: .luminaryLibraryChanged)) { _ in
            Task { await load() }
        }
        .task { await load() }
        .task(id: navigator.libraries.map(\.id)) { await loadRecent() }
    }

    @MainActor
    private func loadRecent() async {
        let libraries = navigator.libraries
        guard !libraries.isEmpty else { return }
        let client = client
        // All libraries at once; a failure in one just leaves its shelf out.
        let results = await withTaskGroup(of: (Int, [BaseItemDto]).self) { group in
            for (index, library) in libraries.enumerated() {
                group.addTask { (index, (try? await client.latestItems(parentId: library.id)) ?? []) }
            }
            var all: [Int: [BaseItemDto]] = [:]
            for await (index, items) in group { all[index] = items }
            return all
        }
        let shelves = libraries.enumerated().compactMap { index, library -> (library: BaseItemDto, items: [BaseItemDto])? in
            guard let items = results[index], !items.isEmpty else { return nil }
            return (library, items)
        }
        if shelves.map(\.library.id) != recent.map(\.library.id) || shelves.map(\.items) != recent.map(\.items) {
            recent = shelves
        }
    }

    @MainActor
    private func load() async {
        do {
            async let resumeTask = client.resumeItems(limit: 24)
            async let nextUpTask = client.nextUp(limit: 24, includeResumable: false)
            let (r, n) = try await (resumeTask, nextUpTask)
            // Only touch the shelves when something actually changed, so revisiting Home doesn't redraw them.
            if r != resume { resume = r }
            if n != nextUp { nextUp = n }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }
}

struct NextUpView: View {
    let client: JellyfinClient

    @State private var items: [BaseItemDto] = []
    @State private var errorMessage: String?


    var body: some View {
        ScrollView {
            PageHeading(title: "Next Up")
            if let errorMessage {
                ErrorBanner(message: errorMessage) { Task { await load() } }.padding(24)
            }
            SettledGrid(minimumCellWidth: 280) {
                ForEach(items) { item in
                    ItemLink(item: item, playsDirectly: true) {
                        ItemCard(item: item, style: .landscape, client: client)
                    }
                }
            }
            .padding(24)
        }
        .pageTitle("Next Up")
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .luminaryLibraryChanged)) { _ in
            Task { await load() }
        }
    }

    @MainActor
    private func load() async {
        do {
            items = try await client.nextUp(limit: 100, includeResumable: false)
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LibraryGridView: View {
    let client: JellyfinClient
    let libraryId: String
    let title: String
    let collectionType: CollectionType?

    @Environment(AppNavigator.self) private var navigator
    @State private var items: [BaseItemDto] = []
    @State private var total: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var options: FilterOptions?
    /// Bumped whenever the filter changes, so a page still loading for the old filter is thrown away.
    @State private var generation = 0

    private let pageSize = 120

    private var filter: Binding<LibraryFilter> {
        Binding(
            get: { navigator.libraryFilters[libraryId] ?? LibraryFilter() },
            set: { navigator.libraryFilters[libraryId] = $0 }
        )
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top) {
                PageHeading(title: title, subtitle: total.map { "\($0) items" })
                LibraryFilterButton(options: options, filter: filter)
                    .padding(.top, 16)
                    .padding(.trailing, 24)
            }
            if !filter.wrappedValue.isEmpty {
                ActiveFilterRow(filter: filter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
            }
            SettledGrid(minimumCellWidth: 160) {
                ForEach(items) { item in
                    ItemLink(item: item) {
                        ItemCard(item: item, style: .poster, client: client)
                    }
                        .onAppear {
                            if item.id == items.last?.id { Task { await loadNextPage() } }
                        }
                }
            }
            .padding(24)

            if isLoading {
                ProgressView().padding(.bottom, 24)
            }
            if !isLoading && items.isEmpty && total == 0 {
                ContentUnavailableView("Nothing matches", systemImage: "line.3.horizontal.decrease",
                                       description: Text("Try removing a filter."))
                    .padding(.top, 40)
            }
            if let errorMessage {
                ErrorBanner(message: errorMessage) { Task { await loadNextPage() } }.padding(24)
            }
        }
        .pageTitle(title, subtitle: total.map { "\($0) items" })
        .task { await loadNextPage() }
        .task { options = try? await client.filterOptions(parentId: libraryId, includeItemTypes: includeTypes) }
        .onChange(of: filter.wrappedValue) {
            generation += 1
            items = []
            total = nil
            errorMessage = nil
            isLoading = false
            Task { await loadNextPage() }
        }
    }

    /// Movies → movies, shows (incl. anime) → series; anything else → direct children.
    private var includeTypes: [BaseItemKind] {
        if collectionType == .movies { return [.movie] }
        if collectionType == .tvshows { return [.series] }
        if collectionType == .boxsets { return [.boxSet] }
        return []
    }

    @MainActor
    private func loadNextPage() async {
        guard !isLoading else { return }
        if let total, items.count >= total { return }
        isLoading = true
        let token = generation
        defer { if token == generation { isLoading = false } }

        let types = includeTypes
        let active = filter.wrappedValue
        let query = ItemQuery(
            parentId: libraryId,
            includeItemTypes: types,
            recursive: !types.isEmpty,
            startIndex: items.count,
            limit: pageSize,
            tags: active.tags.sorted(),
            genres: active.genres.sorted(),
            years: active.years.sorted()
        )
        do {
            let page = try await client.items(query)
            guard token == generation else { return } // the filter changed while this was loading
            items.append(contentsOf: page.items)
            total = page.totalRecordCount ?? items.count
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SearchResultsView: View {
    let client: JellyfinClient
    let query: String

    @State private var results: [BaseItemDto] = []
    @State private var isSearching = false
    @State private var errorMessage: String?


    var body: some View {
        ScrollView {
            PageHeading(title: "Search", subtitle: "Results for “\(query)”")
            if let errorMessage {
                ErrorBanner(message: errorMessage) {}.padding(24)
            }
            if !isSearching && results.isEmpty && errorMessage == nil {
                ContentUnavailableView.search(text: query).padding(.top, 60)
            }
            SettledGrid(minimumCellWidth: 160) {
                ForEach(results) { item in
                    ItemLink(item: item) {
                        ItemCard(item: item, style: .poster, client: client)
                    }
                }
            }
            .padding(24)
        }
        .pageTitle("Search", subtitle: "Results for “\(query)”")
        .task(id: query) {
            // Debounce typing.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let page = try await client.items(ItemQuery(
                    includeItemTypes: [.movie, .series, .episode],
                    recursive: true,
                    sortBy: ["SortName"],
                    limit: 80,
                    searchTerm: query
                ))
                results = page.items
                errorMessage = nil
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Everything you've hearted, grouped like Jellyfin's Favorites tab. One request for all types.
struct FavoritesView: View {
    let client: JellyfinClient

    @State private var items: [BaseItemDto] = []
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var movies: [BaseItemDto] { items.filter { $0.type == .movie } }
    private var shows: [BaseItemDto] { items.filter { $0.type == .series } }
    private var episodes: [BaseItemDto] { items.filter { $0.type == .episode || $0.type == .video } }
    private var collections: [BaseItemDto] { items.filter { $0.type == .boxSet } }

    var body: some View {
        ScrollView {
            PageHeading(title: "Favorites")
            VStack(alignment: .leading, spacing: 32) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                        .padding(.horizontal, 24)
                }
                if !shows.isEmpty {
                    Shelf(title: "Shows", items: shows, style: .poster, client: client)
                }
                if !movies.isEmpty {
                    Shelf(title: "Movies", items: movies, style: .poster, client: client)
                }
                if !collections.isEmpty {
                    Shelf(title: "Collections", items: collections, style: .poster, client: client)
                }
                if !episodes.isEmpty {
                    Shelf(title: "Episodes", items: episodes, style: .landscape, client: client)
                }
                if hasLoaded && items.isEmpty && errorMessage == nil {
                    ContentUnavailableView(
                        "No favorites yet",
                        systemImage: "heart",
                        description: Text("Use the ♥ button on a movie or show, or right-click any poster.")
                    )
                    .padding(.top, 80)
                }
            }
            .padding(.bottom, 24)
        }
        .pageTitle("Favorites")
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .luminaryLibraryChanged)) { _ in
            Task { await load() }
        }
    }

    @MainActor
    private func load() async {
        do {
            let page = try await client.items(ItemQuery(
                includeItemTypes: [.series, .movie, .boxSet, .episode, .video],
                recursive: true,
                limit: 500,
                filters: ["IsFavorite"]
            ))
            items = page.items
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }
}
