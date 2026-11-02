import JellyfinKit
import SwiftUI

/// "Is this playing well?" panel (I key / ⓘ button): play method and why, source file, what the server's
/// transcoder is doing and how fast, and what mpv is decoding/dropping/buffering.
struct StatsPanel: View {
    let controller: PlaybackController

    private var player: MPVPlayer { controller.player }
    private var mpv: [String: String] { controller.stats.mpv }
    private var transcode: TranscodingInfo? { controller.stats.transcoding }
    private var source: MediaSourceInfo? { controller.playback?.source }

    private enum Health { case good, warning, bad }

    private var bufferAhead: Double { max(0, player.cachedUntil - player.timePos) }

    private var sourceFPS: Double? {
        controller.videoStream?.realFrameRate ?? controller.videoStream?.averageFrameRate
    }

    /// Transcoder output fps divided by the video's fps: above 1 means the server is ahead of playback.
    private var transcodeSpeed: Double? {
        guard let fps = transcode?.framerate, let sourceFPS, sourceFPS > 0 else { return nil }
        return fps / sourceFPS
    }

    private var health: (Health, String) {
        if controller.isTranscoding {
            if bufferAhead >= 15 {
                return (.good, "Transcode is ahead of playback (\(Int(bufferAhead)) s buffered).")
            }
            if let speed = transcodeSpeed {
                if speed >= 1.15 { return (.good, String(format: "Server is transcoding %.1f× faster than playback.", speed)) }
                if speed >= 1.0 { return (.warning, String(format: "Transcode is only just keeping up (%.2f×). A lower quality would be safer.", speed)) }
                return (.bad, String(format: "Server can’t keep up (%.2f×). Lower the quality in ⚙︎.", speed))
            }
            return player.isBuffering
                ? (.warning, "Waiting for the server’s transcoder…")
                : (.good, "Transcoding.")
        }
        if player.isBuffering && player.isFileLoaded {
            return (.bad, "Network isn’t keeping up with the original file. Pick a lower quality in ⚙︎ to transcode.")
        }
        if bufferAhead < 5 && player.isFileLoaded {
            return (.warning, "Small buffer (\(Int(bufferAhead)) s). The connection is close to this file’s bitrate.")
        }
        return (.good, "Direct play: the original file, untouched, no work on the server.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Playback Info").font(.headline)
                Spacer()
                Button { controller.toggleStats() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            let status = health
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(status.0 == .good ? Color.green : status.0 == .warning ? Color.yellow : Color.red)
                    .frame(width: 9, height: 9)
                    .padding(.top, 4)
                Text(status.1).fixedSize(horizontal: false, vertical: true)
            }

            section("Playback") {
                row("Method", controller.isTranscoding ? "Transcode (HLS)" : "Direct Play")
                row("Quality", controller.qualityLabel)
                if let reasons = transcode?.transcodeReasons, !reasons.isEmpty {
                    row("Why", reasons.map(Self.humanize).joined(separator: ", "))
                }
            }

            section("Source") {
                if let source {
                    row("File", [source.container?.uppercased(), source.size.map(Self.bytes)].compactMap { $0 }.joined(separator: " · "))
                    if let bitrate = source.bitrate { row("Bitrate", Self.bitrate(bitrate)) }
                }
                if let video = controller.videoStream {
                    row("Video", Self.describe(video: video))
                }
                if let audio = controller.audioStreams.first(where: { $0.index == controller.selectedAudioIndex }) {
                    row("Audio", audio.label)
                }
            }

            if let transcode {
                section("Server transcoder") {
                    row("Video", transcode.isVideoDirect == true
                        ? "Copied (no re-encode)"
                        : [transcode.videoCodec?.uppercased(), resolution(transcode.width, transcode.height)].compactMap { $0 }.joined(separator: " "))
                    row("Audio", transcode.isAudioDirect == true
                        ? "Copied (no re-encode)"
                        : [transcode.audioCodec?.uppercased(), transcode.audioChannels.map { "\($0) ch" }].compactMap { $0 }.joined(separator: " "))
                    if let bitrate = transcode.bitrate { row("Bitrate", Self.bitrate(bitrate)) }
                    if let fps = transcode.framerate {
                        row("Speed", transcodeSpeed.map { String(format: "%.0f fps (%.1f×)", fps, $0) } ?? String(format: "%.0f fps", fps))
                    }
                    if let progress = transcode.completionPercentage {
                        row("Progress", String(format: "%.0f%%", progress))
                    }
                    row("Hardware", transcode.hardwareAccelerationType.flatMap { $0 == "none" ? nil : $0.uppercased() } ?? "None (CPU)")
                }
            }

            section("Player") {
                row("Decoder", Self.decoder(mpv["hwdec-current"]))
                row("Output", [resolution(Int(mpv["video-params/w"] ?? ""), Int(mpv["video-params/h"] ?? "")),
                               mpv["video-params/pixelformat"]].compactMap { $0 }.joined(separator: " · "))
                row("Frame rate", [mpv["estimated-vf-fps"].map { "\($0) shown" }, mpv["container-fps"].map { "\($0) source" }]
                    .compactMap { $0 }.joined(separator: " / "))
                row("Dropped", "\(mpv["decoder-frame-drop-count"] ?? "0") decoder · \(mpv["frame-drop-count"] ?? "0") display")
                row("Buffer", String(format: "%.0f s ahead", bufferAhead))
                if let speed = mpv["cache-speed"] { row("Download", speed) }
                if let bitrate = mpv["video-bitrate"] { row("Video rate", bitrate) }
                if let sync = mpv["avsync"] { row("A/V sync", sync) }
            }
        }
        .font(.callout)
        .padding(16)
        .frame(width: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .foregroundStyle(.white)
    }

    // MARK: Layout helpers

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resolution(_ width: Int?, _ height: Int?) -> String? {
        guard let width, let height else { return nil }
        return "\(width)×\(height)"
    }

    // MARK: Formatting

    private static func describe(video: MediaStream) -> String {
        var parts: [String] = []
        if let codec = video.codec { parts.append(codec.uppercased() + (video.profile.map { " \($0)" } ?? "")) }
        if let width = video.width, let height = video.height { parts.append("\(width)×\(height)") }
        if let bitDepth = video.bitDepth { parts.append("\(bitDepth)-bit") }
        if let range = video.videoRange { parts.append(range) }
        if let fps = video.realFrameRate ?? video.averageFrameRate { parts.append(String(format: "%.3g fps", fps)) }
        return parts.joined(separator: " · ")
    }

    private static func decoder(_ value: String?) -> String {
        switch value {
        case nil, "", "no": return "Software"
        case let name?: return name.contains("videotoolbox") ? "Hardware (VideoToolbox)" : "Hardware (\(name))"
        }
    }

    private static func bitrate(_ bitsPerSecond: Int) -> String {
        bitsPerSecond >= 1_000_000
            ? String(format: "%.1f Mbps", Double(bitsPerSecond) / 1_000_000)
            : "\(bitsPerSecond / 1000) kbps"
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// "ContainerBitrateExceedsLimit" → "Container bitrate exceeds limit"
    private static func humanize(_ reason: String) -> String {
        var words: [String] = []
        var current = ""
        for character in reason {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.joined(separator: " ").lowercased()
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}
