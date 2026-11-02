import AppKit
import MediaPlayer

/// Registers the player with macOS as the "Now Playing" app, so the AirPods stem press, the keyboard's media
/// keys, the Touch Bar / Control Centre and Bluetooth headsets all control Luminary. Without this, macOS has
/// no app to send "play/pause" to: the headset reconfigures its audio route (the brief dropout) and nothing
/// pauses.
@MainActor
final class NowPlayingBridge {
    private unowned let controller: PlaybackController
    private var registered: [(MPRemoteCommand, Any)] = []
    private var timer: Timer?

    init(controller: PlaybackController) {
        self.controller = controller
    }

    func activate() {
        guard registered.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()

        func add(_ command: MPRemoteCommand, _ handler: @escaping @MainActor (PlaybackController, MPRemoteCommandEvent) -> Void) {
            command.isEnabled = true
            let token = command.addTarget { [weak self] event in
                // May arrive on any thread: hop to the main actor and report success straight away.
                Task { @MainActor in
                    guard let self else { return }
                    handler(self.controller, event)
                    self.refresh()
                }
                return .success
            }
            registered.append((command, token))
        }

        add(center.playCommand) { c, _ in c.player.setPaused(false) }
        add(center.pauseCommand) { c, _ in c.player.setPaused(true) }
        add(center.togglePlayPauseCommand) { c, _ in c.player.togglePause() }
        add(center.nextTrackCommand) { c, _ in c.playNext() }
        add(center.previousTrackCommand) { c, _ in c.playPrevious() }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        add(center.skipForwardCommand) { c, _ in c.player.seek(by: 10) }
        add(center.skipBackwardCommand) { c, _ in c.player.seek(by: -10) }
        add(center.changePlaybackPositionCommand) { c, event in
            if let event = event as? MPChangePlaybackPositionCommandEvent { c.player.seek(to: event.positionTime) }
        }

        refresh()
        // Keeps the elapsed time honest after seeks and episode changes; the system extrapolates in between.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func deactivate() {
        timer?.invalidate()
        timer = nil
        for (command, token) in registered { command.removeTarget(token) }
        registered = []
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = nil
        info.playbackState = .stopped
    }

    func refresh() {
        let player = controller.player
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: controller.subtitle ?? controller.title,
            MPMediaItemPropertyArtist: controller.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.timePos,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPaused ? 0.0 : player.speed,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if player.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = player.duration }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = player.isPaused ? .paused : .playing
    }
}
