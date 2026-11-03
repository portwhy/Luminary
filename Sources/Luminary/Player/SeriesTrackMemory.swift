import Foundation
import JellyfinKit

/// What the viewer last picked in the player for a series, so the next episode starts the same way. Tracks are matched
/// by language and title, because stream numbers differ from file to file. Stored on this Mac only, cleared on sign-out.
struct RememberedTracks: Codable {
    struct Track: Codable {
        var language: String?
        var title: String?
        var forced: Bool

        init(_ stream: MediaStream) {
            language = stream.language
            title = stream.title
            forced = stream.isForced == true
        }
    }

    var audio: Track?
    var subtitle: Track?
    var subtitleOff = false
    var updated = Date()
}

@MainActor
enum SeriesTrackMemory {
    private static let key = "app.luminary.seriesTracks"
    private static let limit = 200

    static func tracks(for seriesId: String) -> RememberedTracks? { load()[seriesId] }

    static func rememberAudio(_ stream: MediaStream, seriesId: String) {
        update(seriesId) { $0.audio = RememberedTracks.Track(stream) }
    }

    /// `nil` = the viewer turned subtitles off.
    static func rememberSubtitle(_ stream: MediaStream?, seriesId: String) {
        update(seriesId) {
            $0.subtitle = stream.map(RememberedTracks.Track.init)
            $0.subtitleOff = stream == nil
        }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    /// The stream in this file that best matches a remembered one: same language and forced flag, preferring the same title.
    static func match(_ track: RememberedTracks.Track, in streams: [MediaStream]) -> MediaStream? {
        let sameKind = streams.filter {
            ($0.language ?? "").lowercased() == (track.language ?? "").lowercased() && ($0.isForced == true) == track.forced
        }
        return sameKind.first { $0.title == track.title } ?? sameKind.first
    }

    private static func update(_ seriesId: String, _ change: (inout RememberedTracks) -> Void) {
        var all = load()
        var entry = all[seriesId] ?? RememberedTracks()
        change(&entry)
        entry.updated = Date()
        all[seriesId] = entry
        if all.count > limit { // a few hundred series is plenty; drop the least recently used
            for id in all.sorted(by: { $0.value.updated < $1.value.updated }).prefix(all.count - limit).map(\.key) { all[id] = nil }
        }
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load() -> [String: RememberedTracks] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: RememberedTracks].self, from: data)) ?? [:]
    }
}
