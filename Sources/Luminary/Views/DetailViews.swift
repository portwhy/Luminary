import JellyfinKit
import SwiftUI

/// Backdrop hero with title, metadata, overview and action buttons.
struct DetailHeader<Actions: View>: View {
    let client: JellyfinClient
    let item: BaseItemDto?
    var showsPoster = false
    @ViewBuilder let actions: () -> Actions
    @Environment(\.interfaceScale) private var scale

    private var backdropURL: URL? {
        guard let item else { return nil }
        if let tag = item.backdropImageTags?.first {
            return client.imageURL(itemId: item.id, type: .backdrop, tag: tag, index: 0, maxWidth: 1920)
        }
        if let parent = item.parentBackdropItemId, let tag = item.parentBackdropImageTags?.first {
            return client.imageURL(itemId: parent, type: .backdrop, tag: tag, index: 0, maxWidth: 1920)
        }
        return nil
    }

    private var metadata: String {
        guard let item else { return "" }
        var year = item.productionYear.map(String.init)
        if item.type == .series, let start = item.productionYear {
            // "2019 – Present" / "2019 – 2023"
            let end = item.status == "Continuing" ? "Present" : item.endDate.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
            year = end.map { "\(start) – \($0)" } ?? String(start)
        }
        let parts: [String?] = [
            year,
            item.type == .series ? nil : item.runtimeSeconds.map(TimeFormat.runtime),
            item.officialRating,
            item.communityRating.map { String(format: "★ %.1f", $0) },
            item.criticRating.map { "🍅 \(Int($0))%" },
            endsAt,
        ]
        return parts.compactMap { $0 }.joined(separator: "   ")
    }

    /// "Ends at 4:03 PM" for movies/episodes, counting from the resume point.
    private var endsAt: String? {
        guard let item, item.type != .series, let runtime = item.runtimeSeconds, runtime > 0 else { return nil }
        let remaining = runtime - (item.resumeSeconds ?? 0)
        return "Ends at " + Date().addingTimeInterval(remaining).formatted(date: .omitted, time: .shortened)
    }

    @Environment(AppNavigator.self) private var navigator
    private var sidebarInset: CGFloat { navigator.isSidebarVisible ? LibraryShellView.reservedWidth : 0 }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // The picture is shown at its natural 16:9 shape (so a wide window shows much more of it, not just a
            // 440 pt strip) and runs down behind the info sections below, fading out. The hero itself stays 440 pt
            // tall; the picture overflows it. Fades are applied before the negative leading padding so they
            // also cover the part under the sidebar's glass.
            Color.clear
                .frame(height: 440)
                .overlay(alignment: .top) {
                    GeometryReader { geo in
                        let height = max(440, geo.size.width * 9 / 16)
                        ZStack {
                            if let backdropURL {
                                Artwork(url: backdropURL, aspectRatio: nil, maxPixelSize: 2400)
                            }
                            // Left edge into the app's own color, so under the glass it matches the window.
                            LinearGradient(
                                stops: [
                                    .init(color: AppTheme.background, location: 0.0),
                                    .init(color: AppTheme.background, location: 0.5),
                                    .init(color: AppTheme.background.opacity(0), location: 1.0),
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(width: LibraryShellView.reservedWidth + 120)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Top edge, so pulling the page down past the top shows no hard line.
                            LinearGradient(
                                colors: [AppTheme.background, AppTheme.background.opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 140)
                            .frame(maxHeight: .infinity, alignment: .top)
                            // Bottom: dark enough behind the title, then out to the app color.
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: AppTheme.background.opacity(0.6), location: 0.5),
                                    .init(color: AppTheme.background, location: 1.0),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        }
                        .frame(width: geo.size.width, height: height)
                        .mask {
                            // Glass mode: the app color above is see-through, so painting it over the picture can't
                            // hide its edges. Fade the picture itself out at the same places instead.
                            if AppTheme.shared.glass {
                                let left = LibraryShellView.reservedWidth + 120
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .black, location: 140 / height),
                                        .init(color: .black, location: 0.55),
                                        .init(color: .clear, location: 1),
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                                .mask {
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: left * 0.5 / geo.size.width),
                                            .init(color: .black, location: left / geo.size.width),
                                        ],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                }
                            } else {
                                Color.black
                            }
                        }
                        .clipped()
                        .allowsHitTesting(false)
                    }
                }
                .padding(.leading, -sidebarInset)

            HStack(alignment: .bottom, spacing: 24) {
                if showsPoster, let item {
                    Artwork(url: client.posterURL(for: item, maxWidth: 400), aspectRatio: 2.0 / 3.0)
                        .frame(width: 170 * scale)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(item?.name ?? " ")
                        .scaledFont(size: 34, weight: .bold)
                        .lineLimit(2)
                    if !metadata.isEmpty {
                        Text(metadata).foregroundStyle(.secondary)
                    }
                    if let tagline = item?.taglines?.first, !tagline.isEmpty {
                        Text(tagline)
                            .scaledFont(.title3, weight: .medium)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    if let overview = item?.overview {
                        Text(overview)
                            .lineLimit(4)
                            .frame(maxWidth: 720, alignment: .leading)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    HStack(spacing: 12) { actions() }
                        .padding(.top, 4)
                }
            }
            .padding(28)
        }
    }
}

struct SeriesDetailView: View {
    let client: JellyfinClient
    let seriesId: String
    let initialSeasonId: String?

    @Environment(\.openWindow) private var openWindow
    @State private var series: BaseItemDto?
    @State private var seasons: [BaseItemDto] = []
    @State private var selectedSeasonId: String?
    @State private var episodes: [BaseItemDto] = []
    @State private var nextUp: BaseItemDto?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailHeader(client: client, item: series) {
                    if let nextUp {
                        Button {
                            openWindow(value: PlaybackRequest(itemId: nextUp.id))
                        } label: {
                            Label(nextUp.resumeSeconds != nil ? "Resume \(nextUp.episodeLabel ?? "")" : "Play \(nextUp.episodeLabel ?? "")",
                                  systemImage: "play.fill")
                                .padding(.horizontal, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .scaledControlSize(.large)
                    }
                    if let series {
                        WatchStateButtons(item: series)
                    }
                }

                if let errorMessage {
                    ErrorBanner(message: errorMessage) { Task { await load() } }
                        .padding(.horizontal, 28)
                }

                if seasons.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(seasons) { season in
                                let selected = season.id == selectedSeasonId
                                Button(season.name ?? "Season") { selectedSeasonId = season.id }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Capsule())
                                    .foregroundStyle(selected ? .white : .primary)
                            }
                        }
                        .padding(.horizontal, 28)
                    }
                }

                LazyVStack(spacing: 4) {
                    ForEach(episodes) { episode in
                        EpisodeRow(episode: episode, client: client)
                    }
                }
                .padding(.horizontal, 18)

                if let series {
                    ItemInfoSections(item: series, client: client)
                        .padding(.bottom, 28)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .pageTitle(series?.name ?? "")
        .task { await load() }
        .task(id: selectedSeasonId) { await loadEpisodes() }
        .onReceive(NotificationCenter.default.publisher(for: .luminaryLibraryChanged)) { _ in
            Task {
                await load()
                await loadEpisodes()
            }
        }
    }

    @MainActor
    private func load() async {
        do {
            async let seriesTask = client.item(id: seriesId)
            async let seasonsTask = client.seasons(seriesId: seriesId)
            async let nextUpTask = client.nextUp(limit: 1, seriesId: seriesId)
            series = try await seriesTask
            seasons = try await seasonsTask
            nextUp = (try? await nextUpTask)?.first
            if let nextUp { PlaybackPrefetcher.shared.prefetch(itemId: nextUp.id, client: client) }
            if selectedSeasonId == nil {
                selectedSeasonId = initialSeasonId ?? nextUp?.seasonId ?? seasons.first?.id
            }
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadEpisodes() async {
        guard let selectedSeasonId else { return }
        do {
            episodes = try await client.episodes(seriesId: seriesId, seasonId: selectedSeasonId)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EpisodeRow: View {
    let episode: BaseItemDto
    let client: JellyfinClient

    @State private var isHovering = false
    @Environment(\.interfaceScale) private var scale

    var body: some View {
        ItemLink(item: episode, playsDirectly: true) {
            HStack(alignment: .top, spacing: 16) {
                Artwork(url: client.episodeThumbURL(for: episode, maxWidth: 480), aspectRatio: 16.0 / 9.0)
                    .frame(width: 220 * scale)
                    .overlay(alignment: .bottom) {
                        if let progress = episode.progress {
                            ProgressBar(value: progress).padding(6)
                        }
                    }
                    .overlay {
                        if isHovering {
                            Image(systemName: "play.circle.fill")
                                .scaledFont(size: 38)
                                .foregroundStyle(.white)
                                .shadow(radius: 6)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text([episode.indexNumber.map { "\($0)." }, episode.name].compactMap { $0 }.joined(separator: " "))
                            .scaledFont(.headline)
                            .lineLimit(1)
                        if episode.userData?.played == true {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    HStack(spacing: 10) {
                        if let runtime = episode.runtimeSeconds {
                            Text(TimeFormat.runtime(runtime))
                        }
                        if let rating = episode.communityRating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    if let overview = episode.overview {
                        Text(overview)
                            .scaledFont(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(isHovering ? Color.white.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}

struct MovieDetailView: View {
    let client: JellyfinClient
    let itemId: String

    @Environment(\.openWindow) private var openWindow
    @State private var item: BaseItemDto?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DetailHeader(client: client, item: item, showsPoster: true) {
                    if let item {
                        if let resume = item.resumeSeconds {
                            Button {
                                openWindow(value: PlaybackRequest(itemId: item.id))
                            } label: {
                                Label("Resume from \(TimeFormat.string(resume))", systemImage: "play.fill").padding(.horizontal, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Play from Beginning") {
                                openWindow(value: PlaybackRequest(itemId: item.id, fromBeginning: true))
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                openWindow(value: PlaybackRequest(itemId: item.id))
                            } label: {
                                Label("Play", systemImage: "play.fill").padding(.horizontal, 10)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        TrailerButton(item: item)
                        WatchStateButtons(item: item)
                    }
                }
                .scaledControlSize(.large)

                if let errorMessage {
                    ErrorBanner(message: errorMessage) { Task { await load() } }.padding(.horizontal, 28)
                }

                if let item {
                    ItemInfoSections(item: item, client: client)
                }
            }
            .padding(.bottom, 28)
        }
        .ignoresSafeArea(edges: .top)
        .pageTitle(item?.name ?? "")
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .luminaryLibraryChanged)) { _ in
            Task { await load() }
        }
    }

    /// e.g. "Direct Play · MKV · HEVC 1080p 10-bit HDR · 2 audio · 3 subtitles"
    private var mediaInfo: String? {
        guard let source = item?.mediaSources?.first else { return nil }
        let streams = source.mediaStreams ?? []
        var parts = ["Direct Play"]
        if let container = source.container { parts.append(container.uppercased()) }
        if let video = streams.first(where: { $0.type == "Video" }) {
            var desc = (video.codec ?? "").uppercased()
            if let height = video.height { desc += " \(height)p" }
            if let bitDepth = video.bitDepth, bitDepth > 8 { desc += " \(bitDepth)-bit" }
            if let range = video.videoRange, range != "SDR" { desc += " \(range)" }
            parts.append(desc.trimmingCharacters(in: .whitespaces))
        }
        let audio = streams.filter { $0.type == "Audio" }.count
        let subs = streams.filter { $0.type == "Subtitle" }.count
        if audio > 0 { parts.append("\(audio) audio") }
        if subs > 0 { parts.append("\(subs) subtitle\(subs == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func load() async {
        do {
            item = try await client.item(id: itemId)
            PlaybackPrefetcher.shared.prefetch(itemId: itemId, client: client)
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Watched ✓ and Favorite ♥ toggles for detail headers.
struct WatchStateButtons: View {
    let item: BaseItemDto
    @Environment(SessionManager.self) private var session

    var body: some View {
        let played = item.userData?.played == true
        let favorite = item.userData?.isFavorite == true
        Button {
            perform { try await $0.setPlayed(!played, itemId: item.id) }
        } label: {
            Image(systemName: played ? "checkmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(played ? Color.green : Color.primary)
        }
        .buttonStyle(.bordered)
        .help(played ? "Mark as unwatched" : "Mark as watched")

        Button {
            perform { try await $0.setFavorite(!favorite, itemId: item.id) }
        } label: {
            Image(systemName: favorite ? "heart.fill" : "heart")
                .foregroundStyle(favorite ? Color.pink : Color.primary)
        }
        .buttonStyle(.bordered)
        .help(favorite ? "Remove from favorites" : "Add to favorites")
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

struct TrailerButton: View {
    let item: BaseItemDto
    @Environment(\.openURL) private var openURL

    var body: some View {
        // Web pages only: the address comes from the server, so never open other kinds of links (files, other apps).
        if let link = item.remoteTrailers?.first?.url, let url = URL(string: link),
           let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            Button { openURL(url) } label: {
                Label("Trailer", systemImage: "film")
            }
            .buttonStyle(.bordered)
            .help("Opens the trailer in your browser")
        }
    }
}

/// Everything below the hero: media summary, credits, genres, studios, tags, external links, cast & crew.
/// All of it arrives with the single item request the page already makes; cast photos load lazily
/// through the shared image pipeline, so this adds no meaningful cost.
struct ItemInfoSections: View {
    let item: BaseItemDto
    let client: JellyfinClient

    @Environment(\.openURL) private var openURL
    @Environment(\.interfaceScale) private var scale

    private var people: [BaseItemPerson] { item.people ?? [] }

    private func names(_ types: Set<String>) -> String? {
        let list = people.filter { types.contains($0.type ?? "") }.compactMap(\.name)
        return list.isEmpty ? nil : list.joined(separator: ", ")
    }

    private var mediaRows: [(String, String)] {
        guard let streams = item.mediaSources?.first?.mediaStreams else { return [] }
        var rows: [(String, String)] = []
        if let video = streams.first(where: \.isVideo) {
            var parts: [String] = []
            if let width = video.width {
                parts.append(width >= 3200 ? "4K" : width >= 1800 ? "1080p" : width >= 1200 ? "720p" : width >= 700 ? "480p" : "SD")
            }
            if let codec = video.codec { parts.append(codec.uppercased()) }
            if let bitDepth = video.bitDepth, bitDepth > 8 { parts.append("\(bitDepth)-bit") }
            if let range = video.videoRange { parts.append(range) }
            rows.append(("Video", parts.joined(separator: " ")))
        }
        let audio = streams.filter(\.isAudio)
        if let first = audio.first(where: { $0.isDefault == true }) ?? audio.first {
            rows.append(("Audio", first.label + (audio.count > 1 ? "  (+\(audio.count - 1) more)" : "")))
        }
        let subtitles = streams.filter(\.isSubtitle)
        if !subtitles.isEmpty {
            let languages = Array(Set(subtitles.compactMap(\.language))).sorted().prefix(6).joined(separator: ", ")
            rows.append(("Subtitles", "\(subtitles.count)" + (languages.isEmpty ? "" : " · \(languages)")))
        }
        return rows
    }

    private var creditRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let genres = item.genres, !genres.isEmpty { rows.append(("Genres", genres.joined(separator: ", "))) }
        if let directors = names(["Director"]) { rows.append(("Director", directors)) }
        if let writers = names(["Writer"]) { rows.append(("Writers", writers)) }
        if let studios = item.studios?.compactMap(\.name), !studios.isEmpty { rows.append(("Studios", studios.joined(separator: ", "))) }
        return rows
    }

    private var externalLinks: [(String, URL)] {
        guard let ids = item.providerIds else { return [] }
        let kind = item.type == .series ? "tv" : "movie"
        var links: [(String, URL)] = []
        if let imdb = ids["Imdb"], let url = URL(string: "https://www.imdb.com/title/\(imdb)") { links.append(("IMDb", url)) }
        if let tmdb = ids["Tmdb"], let url = URL(string: "https://www.themoviedb.org/\(kind)/\(tmdb)") { links.append(("TMDB", url)) }
        if let tvdb = ids["Tvdb"], item.type == .series, let url = URL(string: "https://thetvdb.com/dereferrer/series/\(tvdb)") { links.append(("TheTVDB", url)) }
        if let anilist = ids["AniList"], let url = URL(string: "https://anilist.co/anime/\(anilist)") { links.append(("AniList", url)) }
        return links
    }

    private var cast: [BaseItemPerson] {
        // Actors first (in billing order), then the rest of the crew.
        let actors = people.filter { $0.type == "Actor" || $0.type == "GuestStar" }
        let crew = people.filter { $0.type != "Actor" && $0.type != "GuestStar" }
        return actors + crew
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            let rows = mediaRows + creditRows
            if !rows.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 28, verticalSpacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            Text(row.0).foregroundStyle(.secondary)
                            Text(row.1).fontWeight(.medium).textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 28)
            }

            if let tags = item.tags, !tags.isEmpty {
                (Text("Tags: ").fontWeight(.semibold) + Text(tags.joined(separator: ", ")))
                    .scaledFont(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 28)
            }

            if !externalLinks.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(externalLinks.enumerated()), id: \.offset) { _, link in
                        Button(link.0) { openURL(link.1) }
                            .buttonStyle(.link)
                    }
                }
                .padding(.horizontal, 28)
            }

            if !cast.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cast & Crew")
                        .scaledFont(.title2, weight: .semibold)
                        .padding(.horizontal, 28)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 16 * scale) {
                            ForEach(Array(cast.prefix(40).enumerated()), id: \.offset) { _, person in
                                PersonCard(person: person, client: client)
                            }
                        }
                        .padding(.horizontal, 28)
                    }
                }
            }
        }
        .scaledFont(.body)
    }
}

struct PersonCard: View {
    let person: BaseItemPerson
    let client: JellyfinClient
    @Environment(\.interfaceScale) private var scale

    private var initials: String {
        let words = (person.name ?? "").split(separator: " ")
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var photoURL: URL? {
        guard let id = person.id, let tag = person.primaryImageTag else { return nil }
        return client.imageURL(itemId: id, type: .primary, tag: tag, maxWidth: 300)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if photoURL != nil {
                    Artwork(url: photoURL, aspectRatio: 2.0 / 3.0, maxPixelSize: 300)
                } else {
                    // The server has no photo for this person: show initials rather than a "broken image".
                    Color.clear
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .background(
                            LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.12)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay {
                            Text(initials)
                                .scaledFont(size: 34, weight: .semibold, design: .rounded)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                }
            }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(person.name ?? "")
                .scaledFont(.callout, weight: .medium)
                .lineLimit(1)
            Text(person.role.flatMap { $0.isEmpty ? nil : "as \($0)" } ?? person.type ?? "")
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 120 * scale)
    }
}
