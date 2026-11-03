import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation

/// SwiftUI-facing player state. Everything here is main-actor; mpv events hop over from the event thread.
@MainActor
@Observable
final class MPVPlayer {
    private(set) var timePos: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPaused = false
    private(set) var isBuffering = true
    private(set) var cachedUntil: Double = 0
    private(set) var volume: Double = 100
    private(set) var isMuted = false
    private(set) var audioTracks: [MPVTrack] = []
    private(set) var subtitleTracks: [MPVTrack] = []
    private(set) var selectedAudioID: Int?
    private(set) var selectedSubtitleID: Int?
    private(set) var isFileLoaded = false
    private(set) var errorMessage: String?
    private(set) var speed: Double = 1
    private(set) var subtitleDelay: Double = 0
    private(set) var subtitleScale: Double = 1
    private(set) var aspectOverride = "-1"

    @ObservationIgnored var onFileLoaded: (() -> Void)?
    @ObservationIgnored var onFirstFrame: (() -> Void)?
    @ObservationIgnored var onEndOfFile: (() -> Void)?
    @ObservationIgnored var onPauseChanged: ((Bool) -> Void)?

    @ObservationIgnored private var core: MPVCore?
    @ObservationIgnored private var pausedForCache = false
    @ObservationIgnored private var sleepAssertion: IOPMAssertionID = 0
    @ObservationIgnored private var pendingLoad: (url: URL, start: Double)?
    @ObservationIgnored private static let volumeKey = "app.luminary.player.volume"

    private static func cacheDirectory(_ name: String) -> String {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("Luminary/mpv/\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.path
    }

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.volumeKey)
        volume = min(saved > 0 ? saved : 100, Double(Preferences.shared.volumeLimit))
        subtitleScale = Preferences.shared.subtitleScale
    }

    /// The options that make this a "direct play, native rendering" player. Settings → Audio & Subtitles and
    /// Video are read here, so changes there apply to the next video.
    private var options: [(String, String)] {
        let preferences = Preferences.shared
        var options: [(String, String)] = [
            // Render: gpu-next (libplacebo) → Vulkan → MoltenVK → Metal, into our CAMetalLayer.
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            // Decode: VideoToolbox hardware decoding (H.264, HEVC incl. 10-bit, VP9, AV1 on M3+).
            ("hwdec", preferences.hardwareDecoding ? "videotoolbox" : "no"),
            // Subtitles: libass with the file's own styling and embedded fonts, untouched (or a clean plain style).
            ("sub-ass-override", preferences.subtitleStyle == .original ? "no" : "force"),
            ("sub-scale", String(preferences.subtitleScale)),
            ("sub-pos", String(preferences.subtitlePosition)),
            ("embeddedfonts", "yes"),
            ("sub-auto", "fuzzy"),
            // Network: generous read-ahead so seeks within the buffer are instant.
            ("cache", "yes"),
            ("demuxer-max-bytes", "300MiB"),
            ("demuxer-max-back-bytes", "100MiB"),
            ("demuxer-readahead-secs", "60"),
            ("network-timeout", "30"),
            // Check the server's https certificate (mpv doesn't by default). The stream URL carries the access token,
            // so without this a fake server on public Wi-Fi could pick it up. Uses the macOS trusted issuers.
            ("tls-verify", "yes"),
            ("user-agent", "Luminary/\(AppVersion.current)"),
            // Keep the HTTPS connection alive across range requests (MKV index, seeks) instead of a new
            // TLS handshake each time, and reconnect transparently if the proxy drops it.
            ("stream-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=4,multiple_requests=1"),
            // Start rendering as soon as there's a frame; don't wait to fill a buffer first.
            ("cache-pause-initial", "no"),
            ("cache-pause-wait", "0.5"),
            // libplacebo compiles shaders on first use. Cache them so later starts skip that work.
            ("gpu-shader-cache-dir", Self.cacheDirectory("shaders")),
            ("icc-cache-dir", Self.cacheDirectory("icc")),
            // Behavior: we draw our own UI and handle input ourselves.
            ("keep-open", "yes"),
            ("idle", "yes"),
            ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"),
            ("osc", "no"),
            ("ytdl", "no"),
            // mpv's built-in Lua add-ons (stats page, console, menus…): Luminary draws its own UI, so none of them run.
            // Less code in the player, and LuaJIT never has to generate code under the hardened runtime.
            ("load-scripts", "no"),
            ("load-stats-overlay", "no"),
            ("load-console", "no"),
            ("load-auto-profiles", "no"),
            ("load-select", "no"),
            ("load-commands", "no"),
            ("load-positioning", "no"),
            ("load-context-menu", "no"),
            ("audio-client-name", "Luminary"),
            ("volume", String(Int(volume))),
            ("volume-max", String(preferences.volumeLimit)),
            ("deband", preferences.deband ? "yes" : "no"),
        ]
        // HDR: by default mpv drives the display in HDR (EDR) for HDR video; "Always SDR" tone-maps instead.
        if preferences.hdrMode == .sdr { options.append(("target-colorspace-hint", "no")) }
        return options
    }

    // MARK: Lifecycle

    /// Called by the host view once its Metal layer is in a window.
    func attach(layer: MetalLayer) {
        guard core == nil else { return }
        let core = MPVCore(layer: layer, options: options) { [weak self] event in
            let player = self
            DispatchQueue.main.async {
                MainActor.assumeIsolated { player?.apply(event) }
            }
        }
        guard let core else {
            errorMessage = "Couldn’t start the video engine (libmpv failed to initialize). See the terminal for details."
            return
        }
        print("[Luminary] player attached to Metal layer")
        self.core = core
        if let pending = pendingLoad {
            pendingLoad = nil
            load(url: pending.url, startAt: pending.start)
        }
    }

    func load(url: URL, startAt: Double = 0) {
        guard let core else {
            pendingLoad = (url, startAt)
            return
        }
        isFileLoaded = false
        isBuffering = true
        updateSleepAssertion()
        print("[Luminary] loading \(MPVCore.redact(url.absoluteString)) from \(Int(startAt))s")
        var args = ["loadfile", url.absoluteString, "replace", "-1"]
        if startAt > 1 {
            args.append("start=\(String(format: "%.3f", startAt))")
        }
        core.command(args)
    }

    func shutdown() {
        core?.shutdown()
        core = nil
        releaseSleepAssertion()
    }

    /// Keep the display (and the Mac) awake while a video is playing, like any video player. Paused or stopped
    /// playback lets the screen sleep normally again. Called on state changes only, never per frame.
    private func updateSleepAssertion() {
        if isFileLoaded, !isPaused {
            guard sleepAssertion == 0 else { return }
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Luminary is playing a video" as CFString,
                &id)
            if result == kIOReturnSuccess { sleepAssertion = id }
        } else {
            releaseSleepAssertion()
        }
    }

    private func releaseSleepAssertion() {
        guard sleepAssertion != 0 else { return }
        IOPMAssertionRelease(sleepAssertion)
        sleepAssertion = 0
    }

    // MARK: Transport

    func togglePause() { setPaused(!isPaused) }

    func setPaused(_ paused: Bool) {
        core?.setFlag("pause", paused)
    }

    /// Absolute seek. `exact: false` snaps to keyframes (instant, used while scrubbing).
    func seek(to seconds: Double, exact: Bool = true) {
        let target = max(0, duration > 0 ? min(seconds, duration - 0.5) : seconds)
        timePos = target // optimistic, keeps the seek bar from snapping back
        core?.command(["seek", String(format: "%.3f", target), exact ? "absolute+exact" : "absolute+keyframes"])
    }

    func seek(by delta: Double) {
        seek(to: timePos + delta, exact: true)
    }

    func setVolume(_ value: Double) {
        let clamped = min(max(value, 0), Double(Preferences.shared.volumeLimit))
        volume = clamped
        core?.setDouble("volume", clamped)
        UserDefaults.standard.set(clamped, forKey: Self.volumeKey)
        if isMuted && clamped > 0 { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        core?.setFlag("mute", muted)
    }

    // MARK: Picture & timing

    func setSpeed(_ value: Double) {
        speed = min(max(value, 0.25), 4)
        core?.setDouble("speed", speed)
    }

    func setSubtitleDelay(_ seconds: Double) {
        subtitleDelay = (seconds * 10).rounded() / 10
        core?.setDouble("sub-delay", subtitleDelay)
    }

    /// Scales text subtitles (SRT/VTT). ASS keeps its authored size because sub-ass-override=no.
    func setSubtitleScale(_ value: Double) {
        subtitleScale = value
        core?.setDouble("sub-scale", value)
    }

    func setAspectOverride(_ value: String) {
        aspectOverride = value
        core?.setString("video-aspect-override", value)
    }

    /// Display-formatted property values for the stats panel, delivered on main.
    func query(_ names: [String], completion: @escaping @MainActor ([String: String]) -> Void) {
        core?.query(names) { values in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(values) }
            }
        }
    }

    // MARK: Tracks

    func selectAudio(_ id: Int?) {
        core?.setString("aid", id.map(String.init) ?? "no")
    }

    func selectSubtitle(_ id: Int?) {
        core?.setString("sid", id.map(String.init) ?? "no")
    }

    func cycleAudio() {
        core?.command(["cycle", "audio"])
    }

    func cycleSubtitles() {
        core?.command(["cycle", "sub"])
    }

    func addSubtitle(url: URL, title: String, language: String?, select: Bool) {
        var args = ["sub-add", url.absoluteString, select ? "select" : "auto", title]
        if let language { args.append(language) }
        core?.command(args)
    }

    // MARK: Events

    private func apply(_ event: MPVEvent) {
        switch event {
        case .property(let prop, let value):
            applyProperty(prop, value)
        case .tracks(let tracks):
            audioTracks = tracks.filter { $0.type == "audio" }
            subtitleTracks = tracks.filter { $0.type == "sub" }
            selectedAudioID = audioTracks.first(where: \.isSelected)?.id
            selectedSubtitleID = subtitleTracks.first(where: \.isSelected)?.id
        case .fileLoaded:
            isFileLoaded = true
            updateSleepAssertion()
            errorMessage = nil
            onFileLoaded?()
        case .endFile(let isError, let message):
            releaseSleepAssertion()
            if isError {
                errorMessage = "Playback failed: \(message ?? "unknown error")."
                isBuffering = false
            }
        case .shutdown:
            break
        }
    }

    private func applyProperty(_ prop: MPVProp, _ value: MPVValue) {
        switch (prop, value) {
        case (.timePos, .double(let v)):
            timePos = v
        case (.duration, .double(let v)):
            duration = v
        case (.pause, .flag(let v)):
            if isPaused != v {
                isPaused = v
                updateSleepAssertion()
                onPauseChanged?(v)
            }
        case (.pausedForCache, .flag(let v)):
            pausedForCache = v
            isBuffering = v
        case (.volume, .double(let v)):
            volume = v
        case (.mute, .flag(let v)):
            isMuted = v
        case (.eofReached, .flag(let v)):
            if v { onEndOfFile?() }
        case (.aid, .string(let v)):
            selectedAudioID = Int(v)
        case (.sid, .string(let v)):
            selectedSubtitleID = Int(v)
        case (.aid, .empty):
            selectedAudioID = nil
        case (.sid, .empty):
            selectedSubtitleID = nil
        case (.cacheTime, .double(let v)):
            cachedUntil = v
        default:
            break
        }
        // First decoded frame clears the initial spinner even if paused-for-cache never toggled.
        if prop == .timePos, isFileLoaded, isBuffering, !pausedForCache, case .double = value {
            isBuffering = false
            if let onFirstFrame {
                self.onFirstFrame = nil
                onFirstFrame()
            }
        }
    }
}
