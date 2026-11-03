import JellyfinKit
import SwiftUI

/// Root of each player window. `request` is the window's own value: changing it (next episode)
/// swaps in a fresh PlayerScreen in the same window.
struct PlayerWindowRoot: View {
    @Binding var request: PlaybackRequest?
    @Environment(SessionManager.self) private var session

    var body: some View {
        Group {
            if let current = request, case .signedIn(let authenticated) = session.state {
                PlayerScreen(client: authenticated.client, request: current) { next in
                    request = next
                }
                .id(current)
            } else if case .restoring = session.state {
                ProgressView().controlSize(.large)
            } else {
                Text("Sign in to Luminary to play this.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 640, minHeight: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

struct PlayerScreen: View {
    @State private var controller: PlaybackController

    init(client: JellyfinClient, request: PlaybackRequest, onNavigate: @escaping (PlaybackRequest) -> Void) {
        let controller = PlaybackController(client: client, request: request)
        controller.onNavigate = onNavigate
        _controller = State(initialValue: controller)
    }

    private var errorMessage: String? {
        controller.loadError ?? controller.player.errorMessage
    }

    var body: some View {
        ZStack {
            Color.black

            MPVVideoView(controller: controller)

            // Click to pause, double-click for full screen.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { controller.toggleFullScreen() }
                .onTapGesture { controller.player.togglePause() }

            if controller.player.isBuffering && errorMessage == nil {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .allowsHitTesting(false)
            }

            PlayerOverlay(controller: controller)
                .environment(\.interfaceScale, Preferences.shared.interfaceScale)
                .opacity(controller.controlsVisible ? 1 : 0)
                .allowsHitTesting(controller.controlsVisible)

            CornerCards(controller: controller)
                .environment(\.interfaceScale, Preferences.shared.interfaceScale)
            JumpBackPill(controller: controller)
                .environment(\.interfaceScale, Preferences.shared.interfaceScale)

            if controller.showsStats {
                VStack {
                    HStack {
                        Spacer()
                        StatsPanel(controller: controller)
                    }
                    Spacer()
                }
                .padding(.top, 60)
                .padding(.trailing, 20)
            }

            if let errorMessage {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    HStack {
                        if controller.qualitySelection == JellyfinClient.unlimitedBitrate {
                            Button("Try 8 Mbps Transcode") { controller.setMaxBitrate(8_000_000) }
                        }
                        Button("Close") { controller.close() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .padding(28)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .ignoresSafeArea()
        .onContinuousHover { phase in
            if case .active = phase { controller.pokeControls() }
        }
        .navigationTitle(controller.title)
        .task { await controller.start() }
        .onDisappear { controller.stop() }
    }
}

/// Skip Intro / Up Next, bottom-right above the controls. Its own view because it reads the playhead
/// every frame; keeping that out of PlayerScreen/PlayerOverlay means open menus are never rebuilt mid-click.
struct CornerCards: View {
    let controller: PlaybackController

    /// True for the first 5 seconds of an intro/credits segment. After that the Skip button hides, and comes
    /// back with the controls bar when the mouse moves (it goes again when the bar does).
    @State private var skipGrace = false
    @Environment(\.interfaceScale) private var scale

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Spacer()
            if controller.showsUpNext, let next = controller.nextEpisode {
                UpNextCard(controller: controller, next: next)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if let segment = controller.activeSegment, controller.canSkipSegment, let label = segment.skipLabel,
               controller.skipMode(for: segment) == .button, skipGrace || controller.controlsVisible {
                Button {
                    controller.skipCurrentSegment()
                } label: {
                    HStack(spacing: 8) {
                        Label(label, systemImage: "forward.end.fill")
                        if let binding = HotkeyStore.shared.binding(for: .skipSegment) {
                            KeyBadge(binding: binding).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                        .scaledFont(.headline)
                        .padding(.horizontal, 18 * scale)
                        .padding(.vertical, 10 * scale)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
                }
                .buttonStyle(PlayerButtonStyle(cornerRadius: 40, inset: 0))
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 36)
        .padding(.bottom, controller.controlsVisible ? 150 * scale : 48)
        .animation(.easeOut(duration: 0.2), value: controller.controlsVisible)
        .animation(.easeOut(duration: 0.25), value: controller.showsUpNext)
        .animation(.easeOut(duration: 0.25), value: skipGrace || controller.controlsVisible)
        .task(id: controller.activeSegment?.id) {
            guard let segment = controller.activeSegment else { skipGrace = false; return }
            controller.segmentBegan(segment) // skips it if Settings says "Skip automatically"
            skipGrace = true
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { skipGrace = false }
        }
    }
}

/// "19:03 / 2:02:03". Isolated for the same per-frame reason as CornerCards.
struct PlaybackClock: View {
    let controller: PlaybackController

    var body: some View {
        let player = controller.player
        Text(player.duration > 0
             ? "\(TimeFormat.string(controller.scrubPreview ?? player.timePos)) / \(TimeFormat.string(player.duration))"
             : "Loading…")
            .scaledFont(.callout)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
            .fixedSize()
    }
}

/// "↩ Back to 34:12" after a big jump, bottom-left above the controls, for 8 seconds.
struct JumpBackPill: View {
    let controller: PlaybackController
    @Environment(\.interfaceScale) private var scale

    var body: some View {
        VStack {
            Spacer()
            HStack {
                if let position = controller.jumpBackPosition {
                    HStack(spacing: 10) {
                        Button {
                            controller.returnFromJump()
                        } label: {
                            HStack(spacing: 8 * scale) {
                                Image(systemName: position < 1 ? "backward.end.fill" : "arrow.uturn.backward")
                                Text(position < 1 ? "Start from Beginning" : "Back to \(TimeFormat.string(position))")
                                if let binding = HotkeyStore.shared.binding(for: .undoJump) {
                                    KeyBadge(binding: binding).foregroundStyle(.white.opacity(0.8))
                                }
                            }
                            .scaledFont(.headline)
                        }
                        .buttonStyle(PlayerButtonStyle(cornerRadius: 40, inset: 0))

                        Button { controller.dismissJumpBack() } label: {
                            Image(systemName: "xmark")
                                .scaledFont(.caption, weight: .bold)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss")
                    }
                    .padding(.horizontal, 16 * scale)
                    .padding(.vertical, 10 * scale)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
                    .foregroundStyle(.white)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer()
            }
        }
        .padding(.leading, 36)
        .padding(.bottom, controller.controlsVisible ? 150 * scale : 48)
        .animation(.easeOut(duration: 0.2), value: controller.controlsVisible)
    }
}

struct UpNextCard: View {
    let controller: PlaybackController
    let next: BaseItemDto
    @Environment(\.interfaceScale) private var scale

    var body: some View {
        HStack(spacing: 14) {
            Artwork(url: controller.client.landscapeURL(for: next, maxWidth: 400), aspectRatio: 16.0 / 9.0, maxPixelSize: 400)
                .frame(width: 140 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(Preferences.shared.autoplayNext && controller.secondsRemaining <= Preferences.shared.upNextCountdown
                     ? "Next episode in \(controller.secondsRemaining)s" : "Up Next")
                    .scaledFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                // Long titles scroll sideways instead of changing the card's size.
                MarqueeText(text: [next.episodeLabel, next.name].compactMap { $0 }.joined(separator: " · "), isActive: true)
                    .scaledFont(.headline)
                HStack {
                    Button {
                        controller.playNext()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Play Now")
                            if let binding = HotkeyStore.shared.binding(for: controller.canSkipSegment ? .playNow : .skipSegment) {
                                KeyBadge(binding: binding).opacity(0.9)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Hide") { controller.dismissUpNext() }
                        .buttonStyle(.bordered)
                }
                .scaledControlSize(.small)
            }
        }
        .padding(12 * scale)
        .frame(width: 400 * scale)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }
}

struct PlayerOverlay: View {
    let controller: PlaybackController
    @Environment(\.interfaceScale) private var scale

    private var player: MPVPlayer { controller.player }
    /// Settings → Playback (5, 10, 15 or 30: each has a matching SF Symbol).
    private var skipSeconds: Int { Preferences.shared.skipButtonSeconds }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomPanel
        }
        .foregroundStyle(.white)
    }

    private var topBar: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(controller.title)
                    .scaledFont(.headline)
                if let subtitle = controller.subtitle {
                    Text(subtitle)
                        .scaledFont(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 160)

            HStack {
                Button { controller.close() } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .scaledFont(.callout, weight: .semibold)
                        .padding(.horizontal, 12 * scale)
                        .padding(.vertical, 6 * scale)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(PlayerButtonStyle(cornerRadius: 40, inset: 0))
                .help("Back to library" + HotkeyStore.shared.hint(.exitPlayer))
                Spacer()
            }
            // Leave room for the window's traffic lights unless we're full screen.
            .padding(.leading, controller.isFullScreen ? 20 : 84)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 44 * scale)
        .background(
            LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
        .onHover { controller.setHoveringControls($0) }
    }

    private var bottomPanel: some View {
        VStack(spacing: 8 * scale) {
            SeekBar(
                player: player,
                externalPreview: controller.scrubPreview,
                segments: controller.segments,
                chapters: controller.chapters,
                onJump: { origin, target in controller.offerJumpBack(from: origin, to: target) }
            )

            HStack(spacing: 4 * scale) {
                if controller.previousEpisode != nil {
                    Button { controller.playPrevious() } label: { Image(systemName: "backward.end.fill") }
                        .help("Previous episode" + HotkeyStore.shared.hint(.previousEpisode))
                }
                if controller.hasChapters {
                    Button { controller.previousChapter() } label: { Image(systemName: "chevron.left.2") }
                        .help("Previous chapter" + HotkeyStore.shared.hint(.previousChapter))
                }
                Button { player.seek(by: -Double(skipSeconds)) } label: { Image(systemName: "gobackward.\(skipSeconds)") }
                    .help("Back \(skipSeconds) seconds")

                Button { player.togglePause() } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                        .scaledFont(.title)
                        .frame(width: 30 * scale)
                }
                .help((player.isPaused ? "Play" : "Pause") + HotkeyStore.shared.hint(.playPause))

                Button { player.seek(by: Double(skipSeconds)) } label: { Image(systemName: "goforward.\(skipSeconds)") }
                    .help("Forward \(skipSeconds) seconds")
                if controller.hasChapters {
                    Button { controller.nextChapter() } label: { Image(systemName: "chevron.right.2") }
                        .help("Next chapter" + HotkeyStore.shared.hint(.nextChapter))
                }
                if controller.nextEpisode != nil {
                    Button { controller.playNext() } label: { Image(systemName: "forward.end.fill") }
                        .help("Next episode" + HotkeyStore.shared.hint(.nextEpisode))
                }

                PlaybackClock(controller: controller)
                    .padding(.leading, 6 * scale)

                if controller.isTranscoding {
                    Text("TRANSCODING")
                        .scaledFont(.caption2, weight: .bold)
                        .padding(.leading, 12 * scale)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.85), in: Capsule())
                        .help("The server is converting this video. Open Stats (I) for details.")
                }

                Spacer(minLength: 8)

                if controller.hasChapters { chaptersMenu }
                audioMenu
                subtitlesMenu
                settingsMenu

                Button { controller.toggleStats() } label: {
                    Image(systemName: controller.showsStats ? "info.circle.fill" : "info.circle")
                }
                .help("Playback stats" + HotkeyStore.shared.hint(.toggleStats))

                HStack(spacing: 0) {
                    Button { player.setMuted(!player.isMuted) } label: {
                        Image(systemName: volumeIcon).frame(width: 22 * scale)
                    }
                    .help("Mute" + HotkeyStore.shared.hint(.toggleMute))
                    Slider(
                        value: Binding(get: { min(player.volume, 100) }, set: { player.setVolume($0) }),
                        in: 0...100
                    )
                    .scaledControlSize(.small)
                    .frame(width: 80 * scale)
                }

                Button { controller.toggleFullScreen() } label: {
                    Image(systemName: controller.isFullScreen
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                }
                .help("Full Screen" + HotkeyStore.shared.hint(.toggleFullScreen))
            }
            .scaledFont(.title3)
            .buttonStyle(PlayerButtonStyle())
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 8 * scale)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .contentShape(Rectangle())
        .onTapGesture {} // swallow clicks so they don't pause the video
        .onHover { controller.setHoveringControls($0) }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: 1200 * scale)
    }

    private var volumeIcon: String {
        if player.isMuted || player.volume == 0 { return "speaker.slash.fill" }
        if player.volume < 34 { return "speaker.wave.1.fill" }
        if player.volume < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var audioMenu: some View {
        Menu {
            Picker("Audio", selection: Binding(
                get: { controller.selectedAudioIndex ?? -1 },
                set: { controller.selectAudio($0) }
            )) {
                ForEach(controller.audioStreams, id: \.index) { stream in
                    Text(stream.label).tag(stream.index)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "waveform")
        }
        .menuStyle(.button)  // a button-style menu, so the icon follows the player's text size and hover style
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(controller.audioStreams.isEmpty)
        .help("Audio" + HotkeyStore.shared.hint(.cycleAudio))
    }

    private var subtitlesMenu: some View {
        Menu {
            Picker("Subtitles", selection: Binding(
                get: { controller.selectedSubtitleIndex },
                set: { controller.selectSubtitle($0) }
            )) {
                Text("Off").tag(-1)
                ForEach(controller.subtitleStreams, id: \.index) { stream in
                    Text(stream.label + (controller.subtitleNeedsRestart(stream) ? " (burned in)" : ""))
                        .tag(stream.index)
                }
            }
            .pickerStyle(.inline)

            Divider()
            Text("Timing: \(String(format: "%+.1f", player.subtitleDelay)) s")
            Button("Show Earlier" + HotkeyStore.shared.hint(.subtitlesEarlier)) { player.setSubtitleDelay(player.subtitleDelay - 0.1) }
            Button("Show Later" + HotkeyStore.shared.hint(.subtitlesLater)) { player.setSubtitleDelay(player.subtitleDelay + 0.1) }
            Button("Reset Timing") { player.setSubtitleDelay(0) }
                .disabled(player.subtitleDelay == 0)

            Picker("Text Size", selection: Binding(get: { player.subtitleScale }, set: { player.setSubtitleScale($0) })) {
                ForEach([0.75, 0.9, 1.0, 1.15, 1.3, 1.5], id: \.self) { scale in
                    Text("\(Int(scale * 100))%").tag(scale)
                }
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: controller.selectedSubtitleIndex >= 0 ? "captions.bubble.fill" : "captions.bubble")
        }
        .menuStyle(.button)  // a button-style menu, so the icon follows the player's text size and hover style
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Subtitles" + HotkeyStore.shared.hint(.cycleSubtitles))
    }

    private var settingsMenu: some View {
        Menu {
            Picker("Quality", selection: Binding(get: { controller.qualitySelection }, set: { controller.setMaxBitrate($0) })) {
                let options = controller.qualityOptions
                if let original = options.first {
                    Section("Best picture, straight from your server") {
                        Text(original.label).tag(original.bitrate)
                    }
                }
                if options.count > 1 {
                    Section("Smaller: pick one if playback stutters") {
                        ForEach(options.dropFirst()) { option in
                            Text(option.label).tag(option.bitrate)
                        }
                    }
                }
            }
            .pickerStyle(.menu)

            Picker("Speed", selection: Binding(get: { player.speed }, set: { player.setSpeed($0) })) {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                    Text(speed == 1 ? "Normal" : String(format: "%gx", speed)).tag(speed)
                }
            }
            .pickerStyle(.menu)

            Picker("Aspect Ratio", selection: Binding(get: { player.aspectOverride }, set: { player.setAspectOverride($0) })) {
                Text("Auto").tag("-1")
                Text("16:9").tag("16:9")
                Text("4:3").tag("4:3")
                Text("1.85:1").tag("1.85:1")
                Text("2.39:1").tag("2.39:1")
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.button)  // a button-style menu, so the icon follows the player's text size and hover style
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Quality, speed, aspect ratio")
    }

    private var chaptersMenu: some View {
        Menu {
            ForEach(Array(controller.jumpPoints.enumerated()), id: \.offset) { _, point in
                Button("\(point.name)  —  \(TimeFormat.string(point.start))") {
                    controller.jump(to: point.start)
                }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
        .menuStyle(.button)  // a button-style menu, so the icon follows the player's text size and hover style
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Chapters")
    }
}

/// High-precision seek bar: buffered range, intro/credit and chapter markers, hover timestamp, click/drag to scrub.
/// Nothing but the empty track is drawn until mpv reports the duration, and every mark is clamped to the
/// track, so the bar can never spill outside its panel.
struct SeekBar: View {
    let player: MPVPlayer
    let externalPreview: Double?
    let segments: [MediaSegmentDto]
    var chapters: [ChapterInfo] = []
    var onJump: ((Double, Double) -> Void)? = nil

    @Environment(\.interfaceScale) private var scale
    @State private var hoverX: CGFloat?
    @State private var dragTime: Double?
    @State private var dragOrigin: Double?
    @State private var lastDragSeek: Double = -10

    private var isReady: Bool { player.duration > 0 }

    private func fraction(_ time: Double) -> CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(max(time / player.duration, 0), 1))
    }

    private func time(atX x: CGFloat, width: CGFloat) -> Double {
        Double(min(max(x / width, 0), 1)) * player.duration
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let shown = dragTime ?? externalPreview ?? player.timePos
            let active = isReady && (hoverX != nil || dragTime != nil || externalPreview != nil)
            let hoverTime: Double? = isReady ? (dragTime ?? hoverX.map { time(atX: $0, width: width) }) : nil
            let knob: CGFloat = active ? 14 * scale : 0

            ZStack(alignment: .leading) {
                // The track and everything on it share one rounded shape, so intro/credit markers and
                // the played part get the same rounded ends as the track itself.
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    if isReady {
                        Rectangle().fill(.white.opacity(0.22)).frame(width: width * fraction(player.cachedUntil))
                        Capsule().fill(.tint).frame(width: width * fraction(shown))
                        // Intro and credits marks, drawn after the played part so they stay visible once watched. The
                        // part you've watched is a solid gold instead of see-through yellow, which would turn green on blue.
                        ForEach(segments.filter { $0.skipLabel != nil }) { segment in
                            let start = fraction(segment.start)
                            let end = fraction(segment.end)
                            let playedEnd = min(max(fraction(shown), start), end)
                            Rectangle()
                                .fill(.yellow.opacity(0.6))
                                .frame(width: max(0, width * (end - playedEnd)))
                                .offset(x: width * playedEnd)
                            Rectangle()
                                .fill(Color(red: 0.74, green: 0.58, blue: 0.08))
                                .frame(width: max(0, width * (playedEnd - start)))
                                .offset(x: width * start)
                        }
                        ForEach(Array(chapters.dropFirst().enumerated()), id: \.offset) { _, chapter in
                            Rectangle()
                                .fill(.black.opacity(0.6))
                                .frame(width: 2)
                                .offset(x: min(max(width * fraction(chapter.start) - 1, 0), width - 2))
                        }
                    }
                }
                .frame(width: width, alignment: .leading)
                .clipShape(Capsule())

                // Knob sits on top, outside the clip.
                if isReady {
                    Circle()
                        .fill(.white)
                        .frame(width: knob, height: knob)
                        .offset(x: min(max(width * fraction(shown) - knob / 2, 0), width - knob))
                        .shadow(radius: 2)
                }
            }
            .frame(width: width, height: (active ? 8 : 5) * scale, alignment: .leading)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if let hoverTime {
                    Text(TimeFormat.string(hoverTime))
                        .scaledFont(.caption, weight: .semibold)
                        .monospacedDigit()
                        .padding(.horizontal, 7 * scale)
                        .padding(.vertical, 3 * scale)
                        .background(.black.opacity(0.8), in: Capsule())
                        .fixedSize()
                        .offset(x: min(max(width * fraction(hoverTime) - 26, 0), max(width - 52, 0)), y: -22 * scale)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverX = location.x
                case .ended: hoverX = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isReady else { return }
                        if dragOrigin == nil { dragOrigin = player.timePos }
                        let target = time(atX: value.location.x, width: width)
                        dragTime = target
                        if abs(target - lastDragSeek) > 1 {
                            lastDragSeek = target
                            player.seek(to: target, exact: false)
                        }
                    }
                    .onEnded { value in
                        guard isReady else { return }
                        let target = time(atX: value.location.x, width: width)
                        player.seek(to: target, exact: true)
                        if let dragOrigin { onJump?(dragOrigin, target) }
                        dragOrigin = nil
                        dragTime = nil
                        lastDragSeek = -10
                    }
            )
            .animation(.easeOut(duration: 0.12), value: active)
        }
        .frame(height: 24 * scale)
    }
}

enum TimeFormat {
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func runtime(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// A clearly visible hover state for player buttons: a light wash over the button while the pointer is on it and a
/// stronger one while pressed, so it's obvious which button is under the cursor even on a dimmed screen. The padding
/// is part of the button (so the whole highlighted area is clickable); the rows around it use tighter spacing to
/// keep the icons where they were.
struct PlayerHover: ViewModifier {
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = 6
    var pressed = false

    @State private var hovering = false
    @Environment(\.interfaceScale) private var scale

    func body(content: Content) -> some View {
        content
            .padding(inset * scale)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
                    .fill(.white.opacity(pressed ? 0.3 : (hovering ? 0.22 : 0)))
                    .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

struct PlayerButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    var inset: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(PlayerHover(cornerRadius: cornerRadius, inset: inset, pressed: configuration.isPressed))
    }
}

/// A key hint like "⇧↩" in a small outlined box. The return key is drawn with an SF Symbol, because the ↩ text
/// character sits too high next to the label text.
struct KeyBadge: View {
    let binding: KeyBinding

    var body: some View {
        HStack(spacing: 2) {
            let flags = binding.modifierFlags
            let modifiers = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
                + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            if !modifiers.isEmpty { Text(modifiers) }
            if binding.key == "Return" {
                Image(systemName: "return")
            } else {
                Text(binding.key)
            }
        }
        .scaledFont(.caption, weight: .semibold)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .fixedSize()
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.4)))
    }
}
