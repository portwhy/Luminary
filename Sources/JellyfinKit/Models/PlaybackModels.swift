import Foundation

/// Body for /Sessions/Playing, /Sessions/Playing/Progress and /Sessions/Playing/Stopped.
public struct PlaybackReport: Encodable, Sendable {
    public var itemId: String
    public var mediaSourceId: String
    public var playSessionId: String
    public var positionTicks: Int64
    public var isPaused: Bool
    public var isMuted: Bool
    public var volumeLevel: Int
    public var audioStreamIndex: Int?
    public var subtitleStreamIndex: Int?
    public var playMethod: String
    public var canSeek: Bool

    public init(
        itemId: String,
        mediaSourceId: String,
        playSessionId: String,
        positionTicks: Int64,
        isPaused: Bool = false,
        isMuted: Bool = false,
        volumeLevel: Int = 100,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        playMethod: String = "DirectPlay",
        canSeek: Bool = true
    ) {
        self.itemId = itemId
        self.mediaSourceId = mediaSourceId
        self.playSessionId = playSessionId
        self.positionTicks = positionTicks
        self.isPaused = isPaused
        self.isMuted = isMuted
        self.volumeLevel = volumeLevel
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.playMethod = playMethod
        self.canSeek = canSeek
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case isMuted = "IsMuted"
        case volumeLevel = "VolumeLevel"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case playMethod = "PlayMethod"
        case canSeek = "CanSeek"
    }
}

/// Jellyfin 10.10+ media segment (filled by the Intro Skipper plugin or other segment providers).
public struct MediaSegmentDto: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let itemId: String?
    public let type: String          // "Intro", "Outro", "Recap", "Preview", "Commercial", "Unknown"
    public let startTicks: Int64
    public let endTicks: Int64

    public init(id: String, itemId: String?, type: String, startTicks: Int64, endTicks: Int64) {
        self.id = id
        self.itemId = itemId
        self.type = type
        self.startTicks = startTicks
        self.endTicks = endTicks
    }

    public var start: TimeInterval { Ticks.seconds(startTicks) }
    public var end: TimeInterval { Ticks.seconds(endTicks) }

    /// Button label, or nil for segment types we don't offer to skip.
    public var skipLabel: String? {
        switch type {
        case "Intro": return "Skip Intro"
        case "Recap": return "Skip Recap"
        case "Outro": return "Skip Credits"
        case "Preview": return "Skip Preview"
        case "Commercial": return "Skip Ad"
        default: return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case itemId = "ItemId"
        case type = "Type"
        case startTicks = "StartTicks"
        case endTicks = "EndTicks"
    }
}
