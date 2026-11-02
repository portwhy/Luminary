import Foundation

/// Item kind ("Movie", "Series", "Episode", ...). Modelled as an open string wrapper rather than an enum
/// so a new server-side kind never breaks decoding of a whole library page.
public struct BaseItemKind: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let movie = BaseItemKind(rawValue: "Movie")
    public static let series = BaseItemKind(rawValue: "Series")
    public static let season = BaseItemKind(rawValue: "Season")
    public static let episode = BaseItemKind(rawValue: "Episode")
    public static let boxSet = BaseItemKind(rawValue: "BoxSet")
    public static let video = BaseItemKind(rawValue: "Video")
    public static let folder = BaseItemKind(rawValue: "Folder")
    public static let collectionFolder = BaseItemKind(rawValue: "CollectionFolder")
    public static let userView = BaseItemKind(rawValue: "UserView")
}

/// Library type of a user view ("movies", "tvshows", ...). Anime libraries are normally "tvshows" or "movies";
/// the app tells them apart by name.
public struct CollectionType: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let movies = CollectionType(rawValue: "movies")
    public static let tvshows = CollectionType(rawValue: "tvshows")
    public static let music = CollectionType(rawValue: "music")
    public static let boxsets = CollectionType(rawValue: "boxsets")
    public static let homevideos = CollectionType(rawValue: "homevideos")
    public static let books = CollectionType(rawValue: "books")
    public static let playlists = CollectionType(rawValue: "playlists")
    public static let livetv = CollectionType(rawValue: "livetv")
}

public enum ImageType: String, Sendable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case thumb = "Thumb"
    case logo = "Logo"
    case banner = "Banner"
}

public struct UserItemDataDto: Codable, Hashable, Sendable {
    public let playbackPositionTicks: Int64?
    public let playCount: Int?
    public let isFavorite: Bool?
    public let played: Bool?
    public let unplayedItemCount: Int?
    public let playedPercentage: Double?
    public let lastPlayedDate: String?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
        case isFavorite = "IsFavorite"
        case played = "Played"
        case unplayedItemCount = "UnplayedItemCount"
        case playedPercentage = "PlayedPercentage"
        case lastPlayedDate = "LastPlayedDate"
    }
}

public struct MediaStream: Codable, Hashable, Sendable {
    public let index: Int
    public let type: String?          // "Video", "Audio", "Subtitle", "Attachment"
    public let codec: String?
    public let language: String?
    public let title: String?
    public let displayTitle: String?
    public let isDefault: Bool?
    public let isForced: Bool?
    public let isExternal: Bool?
    public let width: Int?
    public let height: Int?
    public let bitDepth: Int?
    public let videoRange: String?    // "SDR", "HDR"
    public let profile: String?
    public let channels: Int?
    public let channelLayout: String?
    public let sampleRate: Int?
    public let bitRate: Int?
    public let averageFrameRate: Double?
    public let realFrameRate: Double?
    public let isTextSubtitleStream: Bool?
    /// How the server will deliver this subtitle for the current play method: "Embed", "External", "Encode", "Hls".
    public let deliveryMethod: String?
    public let deliveryUrl: String?

    enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case codec = "Codec"
        case language = "Language"
        case title = "Title"
        case displayTitle = "DisplayTitle"
        case isDefault = "IsDefault"
        case isForced = "IsForced"
        case isExternal = "IsExternal"
        case width = "Width"
        case height = "Height"
        case bitDepth = "BitDepth"
        case videoRange = "VideoRange"
        case profile = "Profile"
        case channels = "Channels"
        case channelLayout = "ChannelLayout"
        case sampleRate = "SampleRate"
        case bitRate = "BitRate"
        case averageFrameRate = "AverageFrameRate"
        case realFrameRate = "RealFrameRate"
        case isTextSubtitleStream = "IsTextSubtitleStream"
        case deliveryMethod = "DeliveryMethod"
        case deliveryUrl = "DeliveryUrl"
    }
}

public struct MediaSourceInfo: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let path: String?
    public let container: String?
    public let size: Int64?
    public let bitrate: Int?
    public let runTimeTicks: Int64?
    public let supportsDirectPlay: Bool?
    public let supportsDirectStream: Bool?
    public let supportsTranscoding: Bool?
    public let transcodingUrl: String?
    public let transcodingSubProtocol: String?
    public let transcodingContainer: String?
    public let mediaStreams: [MediaStream]?
    public let defaultAudioStreamIndex: Int?
    public let defaultSubtitleStreamIndex: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case path = "Path"
        case container = "Container"
        case size = "Size"
        case bitrate = "Bitrate"
        case runTimeTicks = "RunTimeTicks"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case transcodingUrl = "TranscodingUrl"
        case transcodingSubProtocol = "TranscodingSubProtocol"
        case transcodingContainer = "TranscodingContainer"
        case mediaStreams = "MediaStreams"
        case defaultAudioStreamIndex = "DefaultAudioStreamIndex"
        case defaultSubtitleStreamIndex = "DefaultSubtitleStreamIndex"
    }
}

public struct BaseItemDto: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let type: BaseItemKind?
    public let collectionType: CollectionType?
    public let isFolder: Bool?
    public let overview: String?
    public let productionYear: Int?
    public let premiereDate: String?      // kept as a string: Jellyfin emits 7 fractional digits
    public let officialRating: String?
    public let communityRating: Double?
    public let runTimeTicks: Int64?
    public let childCount: Int?
    public let indexNumber: Int?
    public let parentIndexNumber: Int?
    public let seriesId: String?
    public let seriesName: String?
    public let seasonId: String?
    public let seasonName: String?
    public let primaryImageAspectRatio: Double?
    public let imageTags: [String: String]?
    public let backdropImageTags: [String]?
    public let parentBackdropItemId: String?
    public let parentBackdropImageTags: [String]?
    public let parentThumbItemId: String?
    public let parentThumbImageTag: String?
    public let seriesPrimaryImageTag: String?
    public let userData: UserItemDataDto?
    public let mediaSources: [MediaSourceInfo]?
    public let chapters: [ChapterInfo]?
    public let taglines: [String]?
    public let genres: [String]?
    public let tags: [String]?
    public let studios: [NameIdPair]?
    public let people: [BaseItemPerson]?
    public let criticRating: Double?
    public let providerIds: [String: String]?
    public let remoteTrailers: [MediaURL]?
    public let status: String?          // series: "Continuing" / "Ended"
    public let endDate: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case collectionType = "CollectionType"
        case isFolder = "IsFolder"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case premiereDate = "PremiereDate"
        case officialRating = "OfficialRating"
        case communityRating = "CommunityRating"
        case runTimeTicks = "RunTimeTicks"
        case childCount = "ChildCount"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case seasonId = "SeasonId"
        case seasonName = "SeasonName"
        case primaryImageAspectRatio = "PrimaryImageAspectRatio"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case parentBackdropItemId = "ParentBackdropItemId"
        case parentBackdropImageTags = "ParentBackdropImageTags"
        case parentThumbItemId = "ParentThumbItemId"
        case parentThumbImageTag = "ParentThumbImageTag"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case userData = "UserData"
        case mediaSources = "MediaSources"
        case chapters = "Chapters"
        case taglines = "Taglines"
        case genres = "Genres"
        case tags = "Tags"
        case studios = "Studios"
        case people = "People"
        case criticRating = "CriticRating"
        case providerIds = "ProviderIds"
        case remoteTrailers = "RemoteTrailers"
        case status = "Status"
        case endDate = "EndDate"
    }
}

public struct NameIdPair: Codable, Hashable, Sendable {
    public let name: String?
    public let id: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
    }
}

public struct BaseItemPerson: Codable, Hashable, Sendable {
    public let name: String?
    public let id: String?
    public let role: String?
    public let type: String?            // "Actor", "Director", "Writer", "Producer", "GuestStar"…
    public let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
        case role = "Role"
        case type = "Type"
        case primaryImageTag = "PrimaryImageTag"
    }
}

public struct MediaURL: Codable, Hashable, Sendable {
    public let url: String?
    public let name: String?

    enum CodingKeys: String, CodingKey {
        case url = "Url"
        case name = "Name"
    }
}

public struct ChapterInfo: Codable, Hashable, Sendable {
    public let startPositionTicks: Int64
    public let name: String?
    public let imageTag: String?

    public var start: TimeInterval { Ticks.seconds(startPositionTicks) }

    enum CodingKeys: String, CodingKey {
        case startPositionTicks = "StartPositionTicks"
        case name = "Name"
        case imageTag = "ImageTag"
    }
}

public extension MediaStream {
    var isAudio: Bool { type == "Audio" }
    var isSubtitle: Bool { type == "Subtitle" }
    var isVideo: Bool { type == "Video" }
    /// Jellyfin's own human label ("Japanese - AAC - Stereo - Default"), with fallbacks.
    var label: String { displayTitle ?? title ?? language ?? "Track \(index)" }
}

public extension BaseItemDto {
    /// 0...1 watch progress, if the item is partially played.
    var progress: Double? {
        guard let pct = userData?.playedPercentage, pct > 0 else { return nil }
        return min(pct / 100, 1)
    }

    var runtimeSeconds: TimeInterval? { runTimeTicks.map(Ticks.seconds) }

    var resumeSeconds: TimeInterval? {
        guard let ticks = userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return Ticks.seconds(ticks)
    }

    /// "S1:E3" for episodes.
    var episodeLabel: String? {
        guard type == .episode, let episode = indexNumber else { return nil }
        if let season = parentIndexNumber { return "S\(season):E\(episode)" }
        return "E\(episode)"
    }
}
