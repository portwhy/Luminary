import Foundation

// MARK: - Device profile
//
// Tells the server what Luminary can play. mpv plays essentially any container/codec, so direct play is
// allowed for everything; when the user caps the bitrate (or a file can't be direct played), the server
// transcodes to HLS (fMP4, HEVC or H.264). Text subtitles are delivered as separate files (keeps ASS
// styling) and image subtitles (PGS/VobSub) are burned in.

public struct DeviceProfile: Encodable, Sendable {
    public struct DirectPlayProfile: Encodable, Sendable {
        var Container: String
        var `Type`: String
    }

    public struct TranscodingProfile: Encodable, Sendable {
        var Container: String
        var `Type`: String
        var VideoCodec: String
        var AudioCodec: String
        var `Protocol`: String
        var Context: String
        var MaxAudioChannels: String
        var MinSegments: Int
        var BreakOnNonKeyFrames: Bool
    }

    public struct SubtitleProfile: Encodable, Sendable {
        var Format: String
        var Method: String
    }

    var Name: String
    var MaxStreamingBitrate: Int
    var MaxStaticBitrate: Int
    var DirectPlayProfiles: [DirectPlayProfile]
    var TranscodingProfiles: [TranscodingProfile]
    var SubtitleProfiles: [SubtitleProfile]
    var CodecProfiles: [String] = []
    var ContainerProfiles: [String] = []

    public static func luminary(maxBitrate: Int) -> DeviceProfile {
        let containers = "mkv,mp4,m4v,mov,webm,avi,ts,m2ts,mts,mpegts,wmv,asf,flv,3gp,ogv,ogg,mpg,mpeg,vob,divx,xvid"
        let textFormats = ["ass", "ssa", "srt", "subrip", "vtt", "webvtt", "ttml", "mov_text", "smi", "sub"]
        let imageFormats = ["pgssub", "pgs", "dvdsub", "vobsub", "dvbsub"]

        var subtitles: [SubtitleProfile] = []
        // Direct play: mpv reads every subtitle straight out of the file.
        for format in textFormats + imageFormats {
            subtitles.append(SubtitleProfile(Format: format, Method: "Embed"))
        }
        // Transcoding: text subs as separate files we load into mpv (styling and positioning intact)…
        for format in textFormats {
            subtitles.append(SubtitleProfile(Format: format, Method: "External"))
        }
        // …image subs can only be burned in.
        for format in imageFormats {
            subtitles.append(SubtitleProfile(Format: format, Method: "Encode"))
        }

        return DeviceProfile(
            Name: "Luminary (mpv)",
            MaxStreamingBitrate: maxBitrate,
            MaxStaticBitrate: maxBitrate,
            DirectPlayProfiles: [
                DirectPlayProfile(Container: containers, Type: "Video"),
                DirectPlayProfile(Container: "mp3,aac,m4a,flac,alac,opus,ogg,wav,wma", Type: "Audio"),
            ],
            TranscodingProfiles: [
                TranscodingProfile(
                    Container: "mp4", Type: "Video",
                    VideoCodec: "hevc,h264", AudioCodec: "aac,ac3,eac3,opus,flac,mp3",
                    Protocol: "hls", Context: "Streaming", MaxAudioChannels: "6",
                    MinSegments: 1, BreakOnNonKeyFrames: true
                ),
            ],
            SubtitleProfiles: subtitles
        )
    }
}

// MARK: - PlaybackInfo

public struct PlaybackInfoRequest: Encodable, Sendable {
    var userId: String
    var maxStreamingBitrate: Int
    var startTimeTicks: Int64?
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?
    var mediaSourceId: String?
    var enableDirectPlay: Bool
    var enableDirectStream: Bool
    var enableTranscoding: Bool
    var allowVideoStreamCopy: Bool
    var allowAudioStreamCopy: Bool
    var autoOpenLiveStream: Bool
    var deviceProfile: DeviceProfile

    enum CodingKeys: String, CodingKey {
        case userId = "UserId"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case startTimeTicks = "StartTimeTicks"
        case audioStreamIndex = "AudioStreamIndex"
        case subtitleStreamIndex = "SubtitleStreamIndex"
        case mediaSourceId = "MediaSourceId"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case allowVideoStreamCopy = "AllowVideoStreamCopy"
        case allowAudioStreamCopy = "AllowAudioStreamCopy"
        case autoOpenLiveStream = "AutoOpenLiveStream"
        case deviceProfile = "DeviceProfile"
    }
}

public struct PlaybackInfoResponse: Decodable, Sendable {
    public let mediaSources: [MediaSourceInfo]
    public let playSessionId: String?
    public let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
        case errorCode = "ErrorCode"
    }
}

/// What to play and how, after negotiation.
public struct ResolvedPlayback: Sendable {
    public enum Method: String, Sendable {
        case directPlay = "DirectPlay"
        case transcode = "Transcode"
    }

    public let url: URL
    public let method: Method
    public let source: MediaSourceInfo
    public let playSessionId: String
    public let maxBitrate: Int
}

// MARK: - Sessions (for the transcoding stats panel)

public struct TranscodingInfo: Decodable, Hashable, Sendable {
    public let audioCodec: String?
    public let videoCodec: String?
    public let container: String?
    public let isVideoDirect: Bool?
    public let isAudioDirect: Bool?
    public let bitrate: Int?
    public let framerate: Double?
    public let completionPercentage: Double?
    public let width: Int?
    public let height: Int?
    public let audioChannels: Int?
    public let hardwareAccelerationType: String?
    public let transcodeReasons: [String]?

    enum CodingKeys: String, CodingKey {
        case audioCodec = "AudioCodec"
        case videoCodec = "VideoCodec"
        case container = "Container"
        case isVideoDirect = "IsVideoDirect"
        case isAudioDirect = "IsAudioDirect"
        case bitrate = "Bitrate"
        case framerate = "Framerate"
        case completionPercentage = "CompletionPercentage"
        case width = "Width"
        case height = "Height"
        case audioChannels = "AudioChannels"
        case hardwareAccelerationType = "HardwareAccelerationType"
        case transcodeReasons = "TranscodeReasons"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        audioCodec = try c.decodeIfPresent(String.self, forKey: .audioCodec)
        videoCodec = try c.decodeIfPresent(String.self, forKey: .videoCodec)
        container = try c.decodeIfPresent(String.self, forKey: .container)
        isVideoDirect = try c.decodeIfPresent(Bool.self, forKey: .isVideoDirect)
        isAudioDirect = try c.decodeIfPresent(Bool.self, forKey: .isAudioDirect)
        bitrate = try c.decodeIfPresent(Int.self, forKey: .bitrate)
        framerate = try c.decodeIfPresent(Double.self, forKey: .framerate)
        completionPercentage = try c.decodeIfPresent(Double.self, forKey: .completionPercentage)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        audioChannels = try c.decodeIfPresent(Int.self, forKey: .audioChannels)
        hardwareAccelerationType = try c.decodeIfPresent(String.self, forKey: .hardwareAccelerationType)
        // Older servers send a comma-separated string, newer ones an array.
        if let list = try? c.decodeIfPresent([String].self, forKey: .transcodeReasons) {
            transcodeReasons = list
        } else if let joined = try? c.decodeIfPresent(String.self, forKey: .transcodeReasons) {
            transcodeReasons = joined.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            transcodeReasons = nil
        }
    }
}

public struct PlayStateInfo: Decodable, Hashable, Sendable {
    public let playMethod: String?
    public let positionTicks: Int64?
    public let isPaused: Bool?

    enum CodingKeys: String, CodingKey {
        case playMethod = "PlayMethod"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
    }
}

public struct SessionInfoDto: Decodable, Sendable {
    public let id: String?
    public let deviceId: String?
    public let client: String?
    public let playState: PlayStateInfo?
    public let transcodingInfo: TranscodingInfo?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case deviceId = "DeviceId"
        case client = "Client"
        case playState = "PlayState"
        case transcodingInfo = "TranscodingInfo"
    }
}

public extension ResolvedPlayback {
    /// Pin a transcode's output width (height follows the aspect ratio), so "720p" really means 1280 wide.
    /// Direct play is returned untouched.
    func limitingWidth(_ maxWidth: Int?) -> ResolvedPlayback {
        guard method == .transcode, let maxWidth,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return self }
        // percentEncoded* keeps the server's own encoding of every other parameter byte-for-byte.
        var items = (components.percentEncodedQueryItems ?? []).filter {
            let name = $0.name.lowercased()
            return name != "maxwidth" && name != "maxheight"
        }
        items.append(URLQueryItem(name: "MaxWidth", value: String(maxWidth)))
        components.percentEncodedQueryItems = items
        guard let limited = components.url else { return self }
        return ResolvedPlayback(url: limited, method: method, source: source, playSessionId: playSessionId, maxBitrate: maxBitrate)
    }
}
