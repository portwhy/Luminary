import JellyfinKit
import SwiftUI

extension BaseItemDto {
    /// Episodes and loose videos play on click; movies/series open a detail page.
    var playsOnClick: Bool { type == .episode || type == .video }
}

/// Wraps a card: either opens the player window or pushes a detail page.
struct ItemLink<Content: View>: View {
    let item: BaseItemDto
    var playsDirectly = false
    @ViewBuilder let content: () -> Content

    @Environment(\.openWindow) private var openWindow
    @Environment(SessionManager.self) private var session
    @State private var hoverTask: Task<Void, Never>?

    private var isPlayable: Bool {
        playsDirectly || item.playsOnClick || item.type == .movie
    }

    var body: some View {
        Group {
            if playsDirectly || item.playsOnClick {
                Button {
                    openWindow(value: PlaybackRequest(itemId: item.id))
                } label: {
                    content()
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: item) {
                    content()
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu { ItemActionsMenu(item: item) }
        .onHover { hovering in
            hoverTask?.cancel()
            guard hovering, isPlayable, case .signedIn(let authenticated) = session.state else { return }
            // Brief dwell so sweeping the pointer across a grid doesn't fire dozens of requests.
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                PlaybackPrefetcher.shared.prefetch(itemId: item.id, client: authenticated.client)
            }
        }
    }
}

/// Right-click actions shared by every card and row. Every action maps to a Jellyfin server feature,
/// so the result shows up the same in Jellyfin web and on your other devices.
struct ItemActionsMenu: View {
    let item: BaseItemDto
    @Environment(SessionManager.self) private var session
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.openWindow) private var openWindow

    private var isPlayable: Bool { item.type == .movie || item.type == .episode || item.type == .video }
    private var isPlayed: Bool { item.userData?.played == true }
    private var isFavorite: Bool { item.userData?.isFavorite == true }

    var body: some View {
        if isPlayable {
            if let resume = item.resumeSeconds {
                Button("Resume from \(TimeFormat.string(resume))") { openWindow(value: PlaybackRequest(itemId: item.id)) }
                Button("Play from Beginning") { openWindow(value: PlaybackRequest(itemId: item.id, fromBeginning: true)) }
            } else {
                Button("Play") { openWindow(value: PlaybackRequest(itemId: item.id)) }
            }
            Divider()
        }

        Button(isPlayed ? "Mark as Unwatched" : "Mark as Watched") {
            perform { try await $0.setPlayed(!isPlayed, itemId: item.id) }
        }
        if isPlayable, item.resumeSeconds != nil {
            Button("Remove from Continue Watching") {
                perform { try await $0.clearResumePosition(itemId: item.id) }
            }
        }
        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            perform { try await $0.setFavorite(!isFavorite, itemId: item.id) }
        }

        if item.type == .episode, let seriesId = item.seriesId {
            Divider()
            if let seasonId = item.seasonId {
                Menu(item.parentIndexNumber.map { "Season \($0)" } ?? "Season") {
                    Button("Go to Season") { navigator.open(.series(id: seriesId, seasonId: seasonId)) }
                    Divider()
                    Button("Mark Season Watched") { perform { try await $0.setPlayed(true, itemId: seasonId) } }
                    Button("Mark Season Unwatched") { perform { try await $0.setPlayed(false, itemId: seasonId) } }
                }
            }
            Menu("Series") {
                Button("Go to Series") { navigator.open(.series(id: seriesId, seasonId: nil)) }
                Divider()
                Button("Mark Series Watched") { perform { try await $0.setPlayed(true, itemId: seriesId) } }
                Button("Mark Series Unwatched") { perform { try await $0.setPlayed(false, itemId: seriesId) } }
            }
        }
    }

    private func perform(_ action: @escaping (JellyfinClient) async throws -> Void) {
        guard case .signedIn(let authenticated) = session.state else { return }
        let client = authenticated.client
        Task {
            try? await action(client)
            NotificationCenter.default.post(name: .luminaryLibraryChanged, object: nil)
        }
    }
}

/// Destination for a pushed item.
struct ItemDestination: View {
    let item: BaseItemDto
    let client: JellyfinClient

    var body: some View {
        if item.type == .series {
            SeriesDetailView(client: client, seriesId: item.id, initialSeasonId: nil)
        } else if item.type == .season, let seriesId = item.seriesId {
            SeriesDetailView(client: client, seriesId: seriesId, initialSeasonId: item.id)
        } else if item.type == .movie {
            MovieDetailView(client: client, itemId: item.id)
        } else {
            LibraryGridView(client: client, libraryId: item.id, title: item.name ?? "", collectionType: item.collectionType)
        }
    }
}
