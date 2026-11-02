import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension JellyfinClient {
    func reportPlaybackStart(_ report: PlaybackReport) async throws {
        try await post("/Sessions/Playing", report)
    }

    func reportPlaybackProgress(_ report: PlaybackReport) async throws {
        try await post("/Sessions/Playing/Progress", report)
    }

    func reportPlaybackStopped(_ report: PlaybackReport) async throws {
        try await post("/Sessions/Playing/Stopped", report)
    }

    /// Intro/credits/recap markers (Jellyfin 10.10+). Returns [] if the server has none or doesn't support them.
    func mediaSegments(itemId: String) async throws -> [MediaSegmentDto] {
        _ = try requireCredentials()
        do {
            let result: QueryResult<MediaSegmentDto> = try await get("/MediaSegments/\(itemId)")
            return result.items
        } catch JellyfinError.notFound {
            return []
        }
    }

    /// External (sidecar) subtitle file, e.g. an .ass next to the video on the server.
    func subtitleURL(itemId: String, mediaSourceId: String, streamIndex: Int, format: String) throws -> URL {
        let creds = try requireCredentials()
        return try url("/Videos/\(itemId)/\(mediaSourceId)/Subtitles/\(streamIndex)/0/Stream.\(format)", query: [
            URLQueryItem(name: "api_key", value: creds.accessToken),
        ])
    }
}

extension JellyfinClient {
    func post<Body: Encodable>(_ path: String, _ body: Body) async throws {
        _ = try requireCredentials()
        let data = try JSONEncoder().encode(body)
        try await perform(try makeRequest(path, method: "POST", jsonBody: data))
    }
}

// MARK: - Playback negotiation

public extension JellyfinClient {
    /// "Original quality": high enough that any file is allowed to direct play.
    static let unlimitedBitrate = 200_000_000

    /// POST /Items/{id}/PlaybackInfo: the server decides direct play vs transcode for this device
    /// profile, bitrate cap and track selection, and hands back the URL to open.
    func resolvePlayback(
        itemId: String,
        mediaSourceId: String? = nil,
        maxBitrate: Int = JellyfinClient.unlimitedBitrate,
        startTicks: Int64? = nil,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil
    ) async throws -> ResolvedPlayback {
        let creds = try requireCredentials()
        let body = PlaybackInfoRequest(
            userId: creds.userId,
            maxStreamingBitrate: maxBitrate,
            startTimeTicks: startTicks,
            audioStreamIndex: audioStreamIndex,
            subtitleStreamIndex: subtitleStreamIndex,
            mediaSourceId: mediaSourceId,
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            allowVideoStreamCopy: true,
            allowAudioStreamCopy: true,
            autoOpenLiveStream: true,
            deviceProfile: .luminary(maxBitrate: maxBitrate)
        )
        let request = try makeRequest(
            "/Items/\(itemId)/PlaybackInfo",
            method: "POST",
            query: [URLQueryItem(name: "userId", value: creds.userId)],
            jsonBody: try JSONEncoder().encode(body)
        )
        let response = try decode(PlaybackInfoResponse.self, from: try await perform(request))
        if let code = response.errorCode {
            throw JellyfinError.playbackRefused(code)
        }

        var chosen = response.mediaSources.first
        if let mediaSourceId, let match = response.mediaSources.first(where: { $0.id == mediaSourceId }) {
            chosen = match
        }
        guard let source = chosen else { throw JellyfinError.playbackRefused("NoMediaSource") }
        let playSessionId = response.playSessionId ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        if source.supportsDirectPlay == true {
            let url = try directStreamURL(itemId: itemId, mediaSourceId: source.id, playSessionId: playSessionId)
            return ResolvedPlayback(url: url, method: .directPlay, source: source, playSessionId: playSessionId, maxBitrate: maxBitrate)
        }
        if let transcodingUrl = source.transcodingUrl, let url = absoluteURL(serverRelative: transcodingUrl) {
            return ResolvedPlayback(url: url, method: .transcode, source: source, playSessionId: playSessionId, maxBitrate: maxBitrate)
        }
        throw JellyfinError.playbackRefused("NoCompatibleStream")
    }

    /// Kill the server-side ffmpeg for a play session (quality change, track change, close).
    func stopTranscoding(playSessionId: String) async throws {
        _ = try requireCredentials()
        try await perform(try makeRequest("/Videos/ActiveEncodings", method: "DELETE", query: [
            URLQueryItem(name: "deviceId", value: identity.deviceID),
            URLQueryItem(name: "playSessionId", value: playSessionId),
        ]))
    }

    /// This device's live session(s); carries TranscodingInfo while the server is transcoding for us.
    func currentSessions() async throws -> [SessionInfoDto] {
        _ = try requireCredentials()
        return try await get("/Sessions", query: [URLQueryItem(name: "deviceId", value: identity.deviceID)])
    }
}

// MARK: - Episodes, played & favorite state

public extension JellyfinClient {
    /// Previous, current and next episode around `episodeId`.
    func adjacentEpisodes(seriesId: String, episodeId: String) async throws -> [BaseItemDto] {
        let creds = try requireCredentials()
        let result: QueryResult<BaseItemDto> = try await get("/Shows/\(seriesId)/Episodes", query: [
            URLQueryItem(name: "userId", value: creds.userId),
            URLQueryItem(name: "adjacentTo", value: episodeId),
            URLQueryItem(name: "fields", value: JellyfinClient.defaultFields.joined(separator: ",")),
        ])
        return result.items
    }

    func setPlayed(_ played: Bool, itemId: String) async throws {
        let creds = try requireCredentials()
        try await perform(try makeRequest("/UserPlayedItems/\(itemId)", method: played ? "POST" : "DELETE", query: [
            URLQueryItem(name: "userId", value: creds.userId),
        ]))
    }

    /// "Remove from Continue Watching": clears the saved resume position (what Jellyfin web does).
    func clearResumePosition(itemId: String) async throws {
        let creds = try requireCredentials()
        struct Body: Encodable { let PlaybackPositionTicks: Int64 }
        try await perform(try makeRequest(
            "/UserItems/\(itemId)/UserData",
            method: "POST",
            query: [URLQueryItem(name: "userId", value: creds.userId)],
            jsonBody: try JSONEncoder().encode(Body(PlaybackPositionTicks: 0))
        ))
    }

    func setFavorite(_ favorite: Bool, itemId: String) async throws {
        let creds = try requireCredentials()
        try await perform(try makeRequest("/UserFavoriteItems/\(itemId)", method: favorite ? "POST" : "DELETE", query: [
            URLQueryItem(name: "userId", value: creds.userId),
        ]))
    }
}
