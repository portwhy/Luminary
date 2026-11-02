import AppKit
import JellyfinKit
import Observation
import SwiftUI

/// What a player window is asked to play. Value type so it can drive `WindowGroup(for:)`.
struct PlaybackRequest: Codable, Hashable {
    var itemId: String
    var fromBeginning: Bool = false
}

extension Notification.Name {
    /// Posted when watch state may have changed (playback stopped, marked watched, favorited).
    static let luminaryLibraryChanged = Notification.Name("app.luminary.libraryChanged")
}

struct QualityOption: Identifiable, Hashable {
    let label: String
    let bitrate: Int
    var id: Int { bitrate }

    static let all: [QualityOption] = [
        QualityOption(label: "Original (Direct Play)", bitrate: JellyfinClient.unlimitedBitrate),
        QualityOption(label: "120 Mbps", bitrate: 120_000_000),
        QualityOption(label: "80 Mbps", bitrate: 80_000_000),
        QualityOption(label: "60 Mbps", bitrate: 60_000_000),
        QualityOption(label: "40 Mbps", bitrate: 40_000_000),
        QualityOption(label: "20 Mbps", bitrate: 20_000_000),
        QualityOption(label: "15 Mbps", bitrate: 15_000_000),
        QualityOption(label: "10 Mbps", bitrate: 10_000_000),
        QualityOption(label: "8 Mbps", bitrate: 8_000_000),
        QualityOption(label: "6 Mbps", bitrate: 6_000_000),
        QualityOption(label: "4 Mbps", bitrate: 4_000_000),
        QualityOption(label: "3 Mbps", bitrate: 3_000_000),
        QualityOption(label: "1.5 Mbps", bitrate: 1_500_000),
        QualityOption(label: "720 kbps", bitrate: 720_000),
        QualityOption(label: "420 kbps", bitrate: 420_000),
    ]

    static func label(for bitrate: Int) -> String {
        all.first { $0.bitrate == bitrate }?.label ?? "\(bitrate / 1_000_000) Mbps"
    }

    /// Resolution tiers. `width` is sent to the server as MaxWidth, so the label is exactly what you get.
    private static let tiers: [(name: String, friendly: String, width: Int, minWidth: Int, minBitrate: Int)] = [
        ("4K", "Ultra HD", 3840, 3200, 40_000_000),
        ("1080p", "Full HD", 1920, 1800, 8_000_000),
        ("720p", "HD", 1280, 1200, 3_000_000),
        ("480p", "SD", 854, 700, 720_000),
        ("360p", "Low", 640, 0, 0),
    ]

    /// Output width for a transcode at this bitrate, or nil if that would be the source's own width.
    static func maxWidth(forBitrate bitrate: Int, sourceWidth: Int?) -> Int? {
        let sourceTier = sourceWidth.map(tierIndex(width:)) ?? 0
        let width = tiers[max(tierIndex(bitrate: bitrate), sourceTier)].width
        if let sourceWidth, width >= sourceWidth { return nil }
        return width
    }

    private static func tierIndex(width: Int) -> Int {
        tiers.firstIndex { width >= $0.minWidth } ?? tiers.count - 1
    }

    private static func tierIndex(bitrate: Int) -> Int {
        tiers.firstIndex { bitrate >= $0.minBitrate } ?? tiers.count - 1
    }

    /// "3 Mbps", "1.5 Mbps", "720 kbps"; `precise` gives one decimal ("3.0 Mbps") for the original.
    static func formatBitrate(_ bitrate: Int, precise: Bool = false) -> String {
        guard bitrate >= 1_000_000 else { return "\(bitrate / 1000) kbps" }
        let mbps = Double(bitrate) / 1_000_000
        if precise { return String(format: "%.1f Mbps", mbps) }
        return String(format: "%g Mbps", (mbps * 10).rounded() / 10)
    }

    /// Options that make sense for this file:
    ///   Original · Full HD 1080p · 3.0 Mbps
    ///   SD 480p · 1.5 Mbps
    ///   …
    /// Only bitrates clearly below the source (under 85% of it) are offered: anything closer would cost a
    /// transcode for no visible saving. Labels name the resolution the server is told to scale to.
    static func options(sourceBitrate: Int?, sourceWidth: Int?, sourceHeight: Int?) -> [QualityOption] {
        let sourceTier = sourceWidth.map(tierIndex(width:)) ?? 0
        var parts = ["Original"]
        if sourceWidth != nil { parts.append("\(tiers[sourceTier].friendly) \(tiers[sourceTier].name)") }
        if let sourceBitrate { parts.append(formatBitrate(sourceBitrate, precise: true)) }

        var result = [QualityOption(label: parts.joined(separator: " · "), bitrate: JellyfinClient.unlimitedBitrate)]
        for option in all.dropFirst() {
            if let sourceBitrate, Double(option.bitrate) >= Double(sourceBitrate) * 0.85 { continue }
            let tier = max(tierIndex(bitrate: option.bitrate), sourceTier) // never "upscale" the label
            result.append(QualityOption(
                label: "\(tiers[tier].friendly) \(tiers[tier].name) · \(formatBitrate(option.bitrate))",
                bitrate: option.bitrate
            ))
        }
        return result
    }
}

/// Warms up metadata + PlaybackInfo when you hover something playable, so clicking Play skips
/// two round trips to the server.
@MainActor
final class PlaybackPrefetcher {
    static let shared = PlaybackPrefetcher()

    struct Prefetched: Sendable {
        let item: BaseItemDto
        let playback: ResolvedPlayback
    }

    private var entries: [String: (created: Date, task: Task<Prefetched, Error>)] = [:]

    private func key(_ itemId: String, _ bitrate: Int) -> String { "\(itemId)@\(bitrate)" }

    func prefetch(itemId: String, client: JellyfinClient) {
        let bitrate = PlaybackController.savedMaxBitrate
        let key = key(itemId, bitrate)
        if let existing = entries[key], Date().timeIntervalSince(existing.created) < 45 { return }
        entries = entries.filter { Date().timeIntervalSince($0.value.created) < 45 }
        let task = Task { () throws -> Prefetched in
            async let item = client.item(id: itemId)
            async let playback = client.resolvePlayback(itemId: itemId, maxBitrate: bitrate)
            return try await Prefetched(item: item, playback: playback)
        }
        entries[key] = (Date(), task)
    }

    func take(itemId: String, maxBitrate: Int) -> Task<Prefetched, Error>? {
        let key = key(itemId, maxBitrate)
        guard let entry = entries.removeValue(forKey: key), Date().timeIntervalSince(entry.created) < 45 else { return nil }
        return entry.task
    }
}

/// Live numbers for the stats panel.
struct PlaybackStats {
    var mpv: [String: String] = [:]
    var transcoding: TranscodingInfo?

    static let mpvProperties = [
        "hwdec-current", "video-codec", "video-params/w", "video-params/h", "video-params/pixelformat",
        "video-params/gamma", "container-fps", "estimated-vf-fps", "frame-drop-count", "decoder-frame-drop-count",
        "video-bitrate", "audio-codec-name", "audio-params/channel-count", "audio-params/samplerate", "audio-bitrate",
        "demuxer-cache-duration", "cache-speed", "avsync", "file-format",
    ]
}

private enum SubtitleDelivery {
    case embedded            // inside the file mpv is reading
    case external(URL)       // separate file we sub-add
    case burnedIn            // server renders it into the video (needs a new transcode to change)
}

/// One playback session: negotiates direct play vs transcode with the server, loads mpv, maps the
/// user's audio/subtitle choices (Jellyfin stream indexes) onto mpv tracks or new transcodes, reports
/// progress, handles next/previous episode, and owns overlay and input behavior.
@MainActor
@Observable
final class PlaybackController {
    let player = MPVPlayer()
    let client: JellyfinClient
    let request: PlaybackRequest
    @ObservationIgnored var onNavigate: ((PlaybackRequest) -> Void)?

    private(set) var item: BaseItemDto?
    private(set) var playback: ResolvedPlayback?
    private(set) var segments: [MediaSegmentDto] = []
    private(set) var loadError: String?
    private(set) var controlsVisible = true
    private(set) var isHoveringControls = false
    private(set) var scrubPreview: Double?
    private(set) var isFullScreen = false
    private(set) var previousEpisode: BaseItemDto?
    private(set) var nextEpisode: BaseItemDto?
    private(set) var upNextDismissed = false
    private(set) var showsStats = false
    private(set) var isMenuOpen = false
    /// Where you were before a big jump (number keys, chapters, seek-bar click…). Shown as "Back to …".
    private(set) var jumpBackPosition: Double?
    private(set) var stats = PlaybackStats()
    private(set) var selectedAudioIndex: Int?
    private(set) var selectedSubtitleIndex = -1
    private(set) var maxBitrate: Int

    @ObservationIgnored weak var hostView: MPVHostView?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var didReportStart = false
    @ObservationIgnored private var didStop = false
    @ObservationIgnored private var isTrackpadScrubbing = false
    @ObservationIgnored private var lastScrubSeek: Double = -10
    @ObservationIgnored private var scrubOrigin: Double?
    @ObservationIgnored private var jumpBackTask: Task<Void, Never>?
    @ObservationIgnored private static let bitrateKey = "app.luminary.maxBitrate"
    @ObservationIgnored private let startedAt = Date()

    static var savedMaxBitrate: Int {
        let saved = UserDefaults.standard.integer(forKey: bitrateKey)
        return saved > 0 ? saved : JellyfinClient.unlimitedBitrate
    }

    @ObservationIgnored private var nowPlaying: NowPlayingBridge?

    init(client: JellyfinClient, request: PlaybackRequest) {
        self.client = client
        self.request = request
        maxBitrate = Self.savedMaxBitrate
    }

    /// Startup timing in the terminal, so slow starts can be pinned to network, server or player.
    private func mark(_ step: String) {
        print(String(format: "[Luminary] +%4.0f ms  %@", Date().timeIntervalSince(startedAt) * 1000, step))
    }

    // MARK: Quality

    var sourceBitrate: Int? {
        playback?.source.bitrate ?? item?.mediaSources?.first?.bitrate
    }

    var qualityOptions: [QualityOption] {
        QualityOption.options(sourceBitrate: sourceBitrate, sourceWidth: videoStream?.width, sourceHeight: videoStream?.height)
    }

    /// The menu's checkmark: a cap at or above the file's bitrate *is* original quality.
    var qualitySelection: Int {
        if let sourceBitrate, maxBitrate >= sourceBitrate { return JellyfinClient.unlimitedBitrate }
        return maxBitrate
    }

    var qualityLabel: String {
        qualityOptions.first { $0.bitrate == qualitySelection }?.label ?? QualityOption.label(for: maxBitrate)
    }

    // MARK: Derived state

    var title: String {
        guard let item else { return "" }
        if item.type == .episode, let series = item.seriesName { return series }
        return item.name ?? ""
    }

    var subtitle: String? {
        guard let item, item.type == .episode else { return nil }
        return [item.episodeLabel, item.name].compactMap { $0 }.joined(separator: " · ")
    }

    var streams: [MediaStream] { playback?.source.mediaStreams ?? item?.mediaSources?.first?.mediaStreams ?? [] }
    var audioStreams: [MediaStream] { streams.filter(\.isAudio) }
    var subtitleStreams: [MediaStream] { streams.filter(\.isSubtitle) }
    var videoStream: MediaStream? { streams.first(where: \.isVideo) }
    var chapters: [ChapterInfo] { item?.chapters ?? [] }
    var isTranscoding: Bool { playback?.method == .transcode }

    var activeSegment: MediaSegmentDto? {
        let t = player.timePos
        return segments.first { $0.skipLabel != nil && t >= $0.start && t < $0.end - 1 }
    }

    var showsUpNext: Bool {
        guard nextEpisode != nil, !upNextDismissed, player.duration > 60 else { return false }
        let remaining = player.duration - player.timePos
        let inCredits = activeSegment?.type == "Outro"
        return remaining <= 30 || inCredits
    }

    var secondsRemaining: Int { max(0, Int(player.duration - player.timePos)) }

    // MARK: Lifecycle

    func start() async {
        guard item == nil, !didStop else { return }
        do {
            // Metadata and PlaybackInfo in parallel (or already warmed up by hovering the card).
            let item: BaseItemDto
            let resolved: ResolvedPlayback
            if let warm = PlaybackPrefetcher.shared.take(itemId: request.itemId, maxBitrate: maxBitrate),
               let value = try? await warm.value {
                item = value.item
                resolved = value.playback
                mark("metadata + playback info (prefetched)")
            } else {
                async let itemTask = client.item(id: request.itemId)
                async let resolvedTask = client.resolvePlayback(itemId: request.itemId, maxBitrate: maxBitrate)
                item = try await itemTask
                resolved = try await resolvedTask
                mark("metadata + playback info")
            }
            self.item = item

            player.onFirstFrame = { [weak self] in self?.mark("first frame on screen") }
            player.onFileLoaded = { [weak self] in self?.fileDidLoad() }
            player.onPauseChanged = { [weak self] _ in
                self?.sendProgress()
                self?.pokeControls()
            }
            player.onEndOfFile = { [weak self] in self?.finish() }

            let startAt = request.fromBeginning ? 0 : (item.resumeSeconds ?? 0)
            let playable = apply(resolved, audio: nil, subtitle: nil)
            player.load(url: playable.url, startAt: startAt)
            mark("loadfile sent")
            pokeControls()

            if item.type == .episode, let seriesId = item.seriesId {
                await loadAdjacent(seriesId: seriesId, episodeId: item.id)
            }
            segments = (try? await client.mediaSegments(itemId: item.id)) ?? []
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Ask the server how to play at the current quality/track choice, then (re)load mpv.
    private func resolveAndLoad(startAt: Double, audio: Int?, subtitle: Int?) async throws {
        guard let item else { return }
        let resolved = try await client.resolvePlayback(
            itemId: item.id,
            mediaSourceId: playback?.source.id,
            maxBitrate: maxBitrate,
            audioStreamIndex: audio,
            subtitleStreamIndex: subtitle
        )
        let playable = apply(resolved, audio: audio, subtitle: subtitle)
        player.load(url: playable.url, startAt: startAt)
    }

    @discardableResult
    private func apply(_ resolved: ResolvedPlayback, audio: Int?, subtitle: Int?) -> ResolvedPlayback {
        let sourceWidth = resolved.source.mediaStreams?.first(where: \.isVideo)?.width
        let playable = resolved.limitingWidth(QualityOption.maxWidth(forBitrate: maxBitrate, sourceWidth: sourceWidth))
        playback = playable
        selectedAudioIndex = audio ?? playable.source.defaultAudioStreamIndex
        selectedSubtitleIndex = subtitle ?? playable.source.defaultSubtitleStreamIndex ?? -1
        print("[Luminary] \(playable.method.rawValue) at \(QualityOption.label(for: maxBitrate)) (session \(playable.playSessionId))")
        return playable
    }

    /// Restart playback at the current position with a new negotiation (quality or burned-in track change).
    private func reload(audio: Int?, subtitle: Int?) async {
        guard !didStop, playback != nil else { return }
        let position = player.timePos
        endServerSession()
        didReportStart = false
        do {
            try await resolveAndLoad(startAt: position, audio: audio, subtitle: subtitle)
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
        }
    }

    func stop() {
        guard !didStop else { return }
        didStop = true
        nowPlaying?.deactivate()
        nowPlaying = nil
        progressTask?.cancel()
        hideTask?.cancel()
        statsTask?.cancel()
        endServerSession()
        player.shutdown()
        // Let Home / detail pages refresh resume points once the server has the final position.
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            NotificationCenter.default.post(name: .luminaryLibraryChanged, object: nil)
        }
    }

    /// Report "stopped" for the current play session and kill its transcode if there is one.
    private func endServerSession() {
        guard let playback else { return }
        let client = self.client
        if didReportStart, let report = makeReport() {
            Task.detached { try? await client.reportPlaybackStopped(report) }
        }
        if playback.method == .transcode {
            let sessionId = playback.playSessionId
            Task.detached { try? await client.stopTranscoding(playSessionId: sessionId) }
        }
    }

    private func finish() {
        if nextEpisode != nil {
            playNext()
        } else {
            stop()
            close()
        }
    }

    func close() {
        hostView?.window?.performClose(nil)
    }

    private func fileDidLoad() {
        mark("file opened by mpv")
        if nowPlaying == nil { nowPlaying = NowPlayingBridge(controller: self) }
        nowPlaying?.activate() // AirPods / media keys / Control Center control this player
        applyAudioSelection()
        applySubtitleSelection()
        player.setSpeed(player.speed)
        guard !didReportStart else { return }
        didReportStart = true
        if let report = makeReport() {
            let client = self.client
            Task { try? await client.reportPlaybackStart(report) }
        }
        if progressTask == nil {
            progressTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    self?.sendProgress()
                }
            }
        }
    }

    // MARK: Episodes

    private func loadAdjacent(seriesId: String, episodeId: String) async {
        guard let list = try? await client.adjacentEpisodes(seriesId: seriesId, episodeId: episodeId),
              let index = list.firstIndex(where: { $0.id == episodeId })
        else { return }
        previousEpisode = index > 0 ? list[index - 1] : nil
        nextEpisode = index + 1 < list.count ? list[index + 1] : nil
    }

    func playNext() {
        guard let nextEpisode else { return }
        navigate(to: PlaybackRequest(itemId: nextEpisode.id))
    }

    func playPrevious() {
        guard let previousEpisode else { return }
        navigate(to: PlaybackRequest(itemId: previousEpisode.id))
    }

    private func navigate(to request: PlaybackRequest) {
        if let onNavigate {
            onNavigate(request) // the window swaps in a new PlayerScreen; ours stops in onDisappear
        } else {
            stop()
            close()
        }
    }

    // MARK: Jumps (with a way back)

    /// Seek somewhere far away and offer a way back to where you were.
    func jump(to target: Double, exact: Bool = true) {
        let origin = player.timePos
        player.seek(to: target, exact: exact)
        offerJumpBack(from: origin, to: target)
    }

    /// Small nudges (arrow keys, ±10 s) don't count; anything 15 s or more does. If you jump again while
    /// the button is still up, it keeps pointing at your *original* spot.
    func offerJumpBack(from origin: Double, to target: Double) {
        guard abs(target - origin) >= 15, origin > 1, player.duration > 0 else { return }
        if jumpBackPosition == nil {
            withAnimation(.easeOut(duration: 0.2)) { jumpBackPosition = origin }
        }
        jumpBackTask?.cancel()
        jumpBackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { self.jumpBackPosition = nil }
        }
    }

    func returnFromJump() {
        guard let position = jumpBackPosition else { return }
        jumpBackTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { jumpBackPosition = nil }
        player.seek(to: position)
    }

    func dismissJumpBack() {
        jumpBackTask?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { jumpBackPosition = nil }
    }

    // MARK: Chapters

    var hasChapters: Bool { chapters.count > 1 }

    func nextChapter() {
        let now = player.timePos
        guard let next = chapters.first(where: { $0.start > now + 1 }) else { return }
        jump(to: next.start)
    }

    /// Like a CD player: more than 3 s into a chapter goes back to its start; otherwise to the one before.
    func previousChapter() {
        let now = player.timePos
        guard let currentIndex = chapters.lastIndex(where: { $0.start <= now + 0.5 }) else { return }
        let current = chapters[currentIndex]
        if now - current.start > 3 || currentIndex == 0 {
            jump(to: current.start)
        } else {
            jump(to: chapters[currentIndex - 1].start)
        }
    }

    func dismissUpNext() {
        upNextDismissed = true
    }

    // MARK: Audio & subtitles (Jellyfin stream indexes)

    func selectAudio(_ index: Int) {
        guard index != selectedAudioIndex else { return }
        selectedAudioIndex = index
        if isTranscoding {
            // The transcode carries exactly one audio track; switching means a new transcode.
            Task { await reload(audio: index, subtitle: selectedSubtitleIndex) }
        } else {
            applyAudioSelection()
            sendProgress()
        }
    }

    func selectSubtitle(_ index: Int) {
        let previous = selectedSubtitleIndex
        guard index != previous else { return }
        selectedSubtitleIndex = index
        let needsNewTranscode = isTranscoding && (isBurnedIn(previous) || isBurnedIn(index))
        if needsNewTranscode {
            Task { await reload(audio: selectedAudioIndex, subtitle: index) }
        } else {
            applySubtitleSelection()
            sendProgress()
        }
    }

    func cycleAudio() {
        let options = audioStreams.map(\.index)
        guard !options.isEmpty else { return }
        let position = options.firstIndex(of: selectedAudioIndex ?? -1) ?? -1
        selectAudio(options[(position + 1) % options.count])
    }

    func cycleSubtitles() {
        let options = [-1] + subtitleStreams.map(\.index)
        let position = options.firstIndex(of: selectedSubtitleIndex) ?? 0
        selectSubtitle(options[(position + 1) % options.count])
    }

    private func applyAudioSelection() {
        guard !isTranscoding, let index = selectedAudioIndex,
              let track = player.audioTracks.first(where: { !$0.isExternal && $0.ffIndex == index })
        else { return }
        player.selectAudio(track.id)
    }

    private func applySubtitleSelection() {
        let index = selectedSubtitleIndex
        guard index >= 0, let stream = subtitleStreams.first(where: { $0.index == index }) else {
            player.selectSubtitle(nil)
            return
        }
        // Already loaded as an external track earlier?
        if let track = player.subtitleTracks.first(where: { $0.title == Self.externalTitle(index) }) {
            player.selectSubtitle(track.id)
            return
        }
        switch delivery(for: stream) {
        case .embedded:
            if let track = player.subtitleTracks.first(where: { !$0.isExternal && $0.ffIndex == stream.index }) {
                player.selectSubtitle(track.id)
            }
        case .external(let url):
            player.addSubtitle(url: url, title: Self.externalTitle(index), language: stream.language, select: true)
        case .burnedIn:
            player.selectSubtitle(nil) // it's in the picture
        }
    }

    private func delivery(for stream: MediaStream) -> SubtitleDelivery {
        guard let playback, let item else { return .burnedIn }
        let isDirect = playback.method == .directPlay
        if stream.deliveryMethod == "External" || (isDirect && stream.isExternal == true) {
            if let path = stream.deliveryUrl, let url = client.absoluteURL(serverRelative: path) {
                return .external(url)
            }
            if let url = try? client.subtitleURL(
                itemId: item.id,
                mediaSourceId: playback.source.id,
                streamIndex: stream.index,
                format: Self.subtitleFormat(for: stream.codec)
            ) {
                return .external(url)
            }
        }
        return isDirect ? .embedded : .burnedIn
    }

    private func isBurnedIn(_ index: Int) -> Bool {
        guard index >= 0, let stream = subtitleStreams.first(where: { $0.index == index }) else { return false }
        if case .burnedIn = delivery(for: stream) { return true }
        return false
    }

    /// Whether choosing this subtitle while transcoding will restart the stream (shown in the menu).
    func subtitleNeedsRestart(_ stream: MediaStream) -> Bool {
        isTranscoding && isBurnedIn(stream.index)
    }

    private static func externalTitle(_ index: Int) -> String { "jf-\(index)" }

    private static func subtitleFormat(for codec: String?) -> String {
        switch codec?.lowercased() {
        case "subrip", "srt": "srt"
        case "ass": "ass"
        case "ssa": "ssa"
        case "webvtt", "vtt": "vtt"
        case let other?: other
        case nil: "srt"
        }
    }

    // MARK: Quality

    func setMaxBitrate(_ bitrate: Int) {
        guard bitrate != qualitySelection else { return }
        maxBitrate = bitrate
        UserDefaults.standard.set(bitrate, forKey: Self.bitrateKey)
        Task { await reload(audio: selectedAudioIndex, subtitle: selectedSubtitleIndex) }
    }

    // MARK: Reporting

    private func makeReport() -> PlaybackReport? {
        guard let item, let playback else { return nil }
        return PlaybackReport(
            itemId: item.id,
            mediaSourceId: playback.source.id,
            playSessionId: playback.playSessionId,
            positionTicks: Ticks.ticks(player.timePos),
            isPaused: player.isPaused,
            isMuted: player.isMuted,
            volumeLevel: Int(min(player.volume, 100).rounded()),
            audioStreamIndex: selectedAudioIndex,
            subtitleStreamIndex: selectedSubtitleIndex,
            playMethod: playback.method.rawValue
        )
    }

    private func sendProgress() {
        guard didReportStart, !didStop, let report = makeReport() else { return }
        let client = self.client
        Task { try? await client.reportPlaybackProgress(report) }
    }

    // MARK: Stats

    func toggleStats() {
        showsStats.toggle()
        statsTask?.cancel()
        guard showsStats else { return }
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStats()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refreshStats() async {
        player.query(PlaybackStats.mpvProperties) { [weak self] values in
            self?.stats.mpv = values
        }
        if isTranscoding {
            let sessions = try? await client.currentSessions()
            stats.transcoding = sessions?.first(where: { $0.transcodingInfo != nil })?.transcodingInfo
        } else {
            stats.transcoding = nil
        }
    }

    // MARK: Overlay visibility

    func pokeControls() {
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.18)) { controlsVisible = true }
        }
        scheduleHide()
    }

    /// A menu (quality, audio, subtitles…) is being shown: never auto-hide underneath it.
    func setMenuOpen(_ open: Bool) {
        isMenuOpen = open
        if open {
            hideTask?.cancel()
            if !controlsVisible { controlsVisible = true }
        } else {
            scheduleHide()
        }
    }

    func setHoveringControls(_ hovering: Bool) {
        isHoveringControls = hovering
        if hovering { pokeControls() } else { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard !player.isPaused, !isHoveringControls, !isMenuOpen else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled, !self.player.isPaused, !self.isHoveringControls, !self.isMenuOpen else { return }
            withAnimation(.easeInOut(duration: 0.35)) { self.controlsVisible = false }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    // MARK: Window

    func toggleFullScreen() {
        hostView?.window?.toggleFullScreen(nil)
    }

    func updateFullScreenState() {
        isFullScreen = hostView?.window?.styleMask.contains(.fullScreen) ?? false
    }

    // MARK: Keyboard

    /// Keys come from the user's Shortcuts settings (HotkeyStore); 0–9 (jump to 0–90 %) is built in.
    func handleKey(_ event: NSEvent) -> Bool {
        if let action = HotkeyStore.shared.playerAction(for: event) {
            perform(action)
            if action != .exitPlayer { pokeControls() }
            return true
        }
        let modifiers = event.modifierFlags.intersection(KeyBinding.relevant)
        if modifiers.isEmpty, let key = event.charactersIgnoringModifiers, key.count == 1,
           let digit = Double(key), player.duration > 0 {
            jump(to: player.duration * digit / 10)
            pokeControls()
            return true
        }
        return false // everything else (⌘W, ⌘Q, menu shortcuts) goes to the system
    }

    func perform(_ action: HotkeyAction) {
        switch action {
        case .playPause: player.togglePause()
        case .toggleFullScreen: toggleFullScreen()
        case .exitPlayer: if isFullScreen { toggleFullScreen() } else { close() }
        case .toggleStats: toggleStats()
        case .volumeUp: player.setVolume(min(player.volume + 5, 100))
        case .volumeDown: player.setVolume(player.volume - 5)
        case .toggleMute: player.setMuted(!player.isMuted)
        case .seekBack: player.seek(by: -5)
        case .seekForward: player.seek(by: 5)
        case .seekBackLong: player.seek(by: -30)
        case .seekForwardLong: player.seek(by: 30)
        case .skipSegment: skipCurrentSegment()
        case .previousChapter: previousChapter()
        case .nextChapter: nextChapter()
        case .undoJump: returnFromJump()
        case .cycleAudio: cycleAudio()
        case .cycleSubtitles: cycleSubtitles()
        case .subtitlesEarlier: player.setSubtitleDelay(player.subtitleDelay - 0.1)
        case .subtitlesLater: player.setSubtitleDelay(player.subtitleDelay + 0.1)
        case .speedDown: player.setSpeed(player.speed - 0.25)
        case .speedUp: player.setSpeed(player.speed + 0.25)
        case .speedReset: player.setSpeed(1)
        case .previousEpisode: playPrevious()
        case .nextEpisode: playNext()
        case .back, .goHome, .goNextUp, .goFavorites, .search, .refresh: break // library window (Go menu)
        }
    }

    /// Whatever the on-screen corner button would do: Play Next if the Up Next card is up,
    /// otherwise skip the current intro / recap / credits.
    func skipCurrentSegment() {
        if showsUpNext {
            playNext()
        } else if let segment = activeSegment {
            jump(to: segment.end)
        }
    }

    // MARK: Trackpad scrubbing

    /// Two-finger horizontal swipe scrubs: keyframe seeks while moving (instant), one exact seek on release.
    func handleScroll(_ event: NSEvent) -> Bool {
        guard event.hasPreciseScrollingDeltas, player.duration > 0 else { return false }

        // Ignore inertial scrolling so the playhead lands where your fingers stopped.
        if !event.momentumPhase.isEmpty { return true }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            isTrackpadScrubbing = false
            scrubPreview = nil
        }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        if event.phase.contains(.began) || event.phase.contains(.changed) {
            if !isTrackpadScrubbing {
                guard abs(dx) > abs(dy) * 1.5, abs(dx) > 0.5 else { return true }
                isTrackpadScrubbing = true
                scrubPreview = player.timePos
                scrubOrigin = player.timePos
            }
            let fingerDX = event.isDirectionInvertedFromDevice ? dx : -dx
            let secondsPerPoint = max(0.1, player.duration / 2400)
            let target = min(max((scrubPreview ?? player.timePos) + Double(fingerDX) * secondsPerPoint, 0), player.duration)
            scrubPreview = target
            if abs(target - lastScrubSeek) > 1 {
                lastScrubSeek = target
                player.seek(to: target, exact: false)
            }
            pokeControls()
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            if isTrackpadScrubbing, let target = scrubPreview {
                player.seek(to: target, exact: true)
                if let scrubOrigin { offerJumpBack(from: scrubOrigin, to: target) }
            }
            scrubOrigin = nil
            isTrackpadScrubbing = false
            scrubPreview = nil
            lastScrubSeek = -10
        }
        return true
    }
}
