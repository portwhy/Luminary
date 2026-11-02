import Foundation
import Libmpv
import QuartzCore

/// Observed mpv properties. The raw value is passed as reply_userdata so events map back without string compares.
enum MPVProp: UInt64, CaseIterable {
    case timePos = 1
    case duration
    case pause
    case pausedForCache
    case volume
    case mute
    case eofReached
    case trackCount
    case aid
    case sid
    case cacheTime

    var name: String {
        switch self {
        case .timePos: "time-pos"
        case .duration: "duration"
        case .pause: "pause"
        case .pausedForCache: "paused-for-cache"
        case .volume: "volume"
        case .mute: "mute"
        case .eofReached: "eof-reached"
        case .trackCount: "track-list/count"
        case .aid: "aid"
        case .sid: "sid"
        case .cacheTime: "demuxer-cache-time"
        }
    }

    var format: mpv_format {
        switch self {
        case .timePos, .duration, .volume, .cacheTime: MPV_FORMAT_DOUBLE
        case .pause, .pausedForCache, .mute, .eofReached: MPV_FORMAT_FLAG
        case .trackCount: MPV_FORMAT_INT64
        case .aid, .sid: MPV_FORMAT_STRING
        }
    }
}

enum MPVValue: Sendable {
    case double(Double)
    case flag(Bool)
    case int(Int64)
    case string(String)
    case empty
}

struct MPVTrack: Identifiable, Hashable, Sendable {
    let id: Int                 // mpv's per-type track id (aid/sid value)
    let type: String            // "video", "audio", "sub"
    let title: String?
    let language: String?
    let codec: String?
    let isExternal: Bool
    let isSelected: Bool
    let ffIndex: Int?           // container stream index == Jellyfin MediaStream.Index for embedded tracks

    var displayName: String {
        var parts: [String] = []
        if let language, let name = Locale.current.localizedString(forLanguageCode: language) {
            parts.append(name)
        } else if let language {
            parts.append(language)
        }
        if let title, !title.isEmpty, !parts.contains(title) {
            parts.append(title)
        }
        if parts.isEmpty { parts.append("Track \(id)") }
        var label = parts.joined(separator: " – ")
        if let codec { label += " (\(codec.uppercased()))" }
        return label
    }
}

enum MPVEvent: Sendable {
    case property(MPVProp, MPVValue)
    case tracks([MPVTrack])
    case fileLoaded
    case endFile(isError: Bool, message: String?)
    case shutdown
}

/// Owns one mpv handle, its event thread and a serial command queue.
///
/// Threading rule: **the main thread never calls into libmpv.** While a file opens, mpv's VO thread
/// (MoltenVK) briefly needs the main thread to configure the CAMetalLayer; if main were blocked inside
/// an mpv call at that moment, both would wait forever. So commands go through `queue`, and everything
/// mpv tells us (including the track list) is read on the event thread and posted to main.
final class MPVCore: @unchecked Sendable {
    private let handle: OpaquePointer
    private let layer: CAMetalLayer
    private let onEvent: @Sendable (MPVEvent) -> Void
    private let queue = DispatchQueue(label: "luminary.mpv.commands", qos: .userInitiated)
    private let lock = NSLock()
    private var stopRequested = false

    init?(layer: CAMetalLayer, options: [(String, String)], onEvent: @escaping @Sendable (MPVEvent) -> Void) {
        guard let handle = mpv_create() else {
            print("[Luminary] mpv_create failed")
            return nil
        }
        self.handle = handle
        self.layer = layer
        self.onEvent = onEvent

        // Render target: pointer to the CAMetalLayer.
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        Self.check(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid), "wid")

        for (name, value) in options {
            Self.check(mpv_set_option_string(handle, name, value), "\(name)=\(value)")
        }
        mpv_request_log_messages(handle, "info")

        let status = mpv_initialize(handle)
        guard status >= 0 else {
            Self.check(status, "mpv_initialize")
            mpv_terminate_destroy(handle)
            return nil
        }

        for prop in MPVProp.allCases {
            mpv_observe_property(handle, prop.rawValue, prop.name, prop.format)
        }

        let thread = Thread { [self] in self.runEventLoop() }
        thread.name = "luminary.mpv.events"
        thread.qualityOfService = .userInteractive
        thread.start()
        print("[Luminary] mpv initialised")
    }

    /// Ask mpv to shut down after any queued commands. Don't use this core afterwards.
    func shutdown() {
        queue.async { [self] in
            lock.lock()
            stopRequested = true
            lock.unlock()
            mpv_wakeup(handle)
        }
    }

    private var isStopRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    // MARK: Commands (asynchronous, ordered, never on the main thread)

    func command(_ args: [String]) {
        queue.async { [self] in
            var cargs: [UnsafePointer<CChar>?] = args.map { UnsafePointer<CChar>(strdup($0)) }
            cargs.append(nil)
            defer {
                for pointer in cargs {
                    if let pointer { free(UnsafeMutablePointer(mutating: pointer)) }
                }
            }
            Self.check(mpv_command(handle, &cargs), Self.redact(args.joined(separator: " ")))
        }
    }

    func setString(_ name: String, _ value: String) {
        queue.async { [self] in
            Self.check(mpv_set_property_string(handle, name, value), "\(name)=\(value)")
        }
    }

    func setFlag(_ name: String, _ value: Bool) {
        queue.async { [self] in
            var flag: Int32 = value ? 1 : 0
            Self.check(mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag), name)
        }
    }

    func setDouble(_ name: String, _ value: Double) {
        queue.async { [self] in
            var number = value
            Self.check(mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &number), name)
        }
    }

    /// Read properties as display strings (mpv's own OSD formatting) on the command queue, never on main.
    func query(_ names: [String], completion: @escaping @Sendable ([String: String]) -> Void) {
        queue.async { [self] in
            var values: [String: String] = [:]
            for name in names {
                if let cString = mpv_get_property_osd_string(handle, name) {
                    values[name] = String(cString: cString)
                    mpv_free(cString)
                }
            }
            completion(values)
        }
    }

    // MARK: Event loop (its own thread)

    private func runEventLoop() {
        while true {
            guard let event = mpv_wait_event(handle, -1) else { continue }
            let id = event.pointee.event_id
            if id == MPV_EVENT_SHUTDOWN { break }
            if id == MPV_EVENT_NONE {
                if isStopRequested { break }
                continue
            }
            process(event.pointee)
        }
        mpv_terminate_destroy(handle)
        withExtendedLifetime(layer) {}
        print("[Luminary] mpv shut down")
        onEvent(.shutdown)
    }

    private func process(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let data = event.data, let prop = MPVProp(rawValue: event.reply_userdata) else { return }
            let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
            let value: MPVValue
            switch property.format {
            case MPV_FORMAT_DOUBLE:
                value = .double(property.data.assumingMemoryBound(to: Double.self).pointee)
            case MPV_FORMAT_FLAG:
                value = .flag(property.data.assumingMemoryBound(to: Int32.self).pointee != 0)
            case MPV_FORMAT_INT64:
                value = .int(property.data.assumingMemoryBound(to: Int64.self).pointee)
            case MPV_FORMAT_STRING:
                if let cString = property.data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee {
                    value = .string(String(cString: cString))
                } else {
                    value = .empty
                }
            default:
                value = .empty
            }
            onEvent(.property(prop, value))
            if prop == .trackCount || prop == .aid || prop == .sid {
                onEvent(.tracks(readTracks()))
            }

        case MPV_EVENT_FILE_LOADED:
            print("[Luminary] file loaded")
            onEvent(.tracks(readTracks()))
            onEvent(.fileLoaded)

        case MPV_EVENT_END_FILE:
            guard let data = event.data else { return }
            let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            let isError = endFile.reason == MPV_END_FILE_REASON_ERROR
            let message = isError ? String(cString: mpv_error_string(endFile.error)) : nil
            print("[Luminary] end of file\(message.map { " (error: \($0))" } ?? "")")
            onEvent(.endFile(isError: isError, message: message))

        case MPV_EVENT_LOG_MESSAGE:
            guard let data = event.data else { return }
            let log = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
            print("[mpv/\(String(cString: log.prefix))] \(String(cString: log.level)): \(Self.redact(String(cString: log.text)))", terminator: "")

        default:
            break
        }
    }

    /// Safe here: we're on the event thread, not main.
    private func readTracks() -> [MPVTrack] {
        let count = Int(int("track-list/count") ?? 0)
        var tracks: [MPVTrack] = []
        for index in 0..<count {
            let prefix = "track-list/\(index)/"
            guard let type = string(prefix + "type"), let id = int(prefix + "id") else { continue }
            tracks.append(MPVTrack(
                id: Int(id),
                type: type,
                title: string(prefix + "title"),
                language: string(prefix + "lang"),
                codec: string(prefix + "codec"),
                isExternal: flag(prefix + "external"),
                isSelected: flag(prefix + "selected"),
                ffIndex: int(prefix + "ff-index").map { Int($0) }
            ))
        }
        return tracks
    }

    private func string(_ name: String) -> String? {
        guard let cString = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(cString) }
        return String(cString: cString)
    }

    private func int(_ name: String) -> Int64? {
        var value: Int64 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 ? value : nil
    }

    private func flag(_ name: String) -> Bool {
        var value: Int32 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value) >= 0 && value != 0
    }

    private static func check(_ status: Int32, _ context: String) {
        if status < 0 {
            print("[Luminary] mpv error in \(context): \(String(cString: mpv_error_string(status)))")
        }
    }

    /// Keep the access token out of terminal output.
    static func redact(_ text: String) -> String {
        guard let range = text.range(of: "api_key=") else { return text }
        let tail = text[range.upperBound...]
        let end = tail.firstIndex(where: { $0 == "&" || $0 == " " || $0 == "\n" || $0 == "'" || $0 == "\"" }) ?? tail.endIndex
        return text.replacingCharacters(in: range.upperBound..<end, with: "•••")
    }
}
