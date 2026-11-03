import JellyfinKit

/// Picks the starting audio and subtitle tracks from Settings → Audio & Subtitles, falling back to what the
/// server chose (the user's Jellyfin preferences) whenever a preference doesn't apply to this file.
struct TrackChoice {
    let audio: Int?
    /// Jellyfin stream index, or -1 for off.
    let subtitle: Int

    @MainActor
    static func choose(streams: [MediaStream], serverAudio: Int?, serverSubtitle: Int?) -> TrackChoice {
        let preferences = Preferences.shared
        let audioStreams = streams.filter(\.isAudio)
        let subtitles = streams.filter(\.isSubtitle)

        // Audio: the preferred language if the file has it (its default track first), else the server's pick.
        let preferredAudio = audioStreams
            .filter { TrackLanguage.matches(preferences.audioLanguage, $0.language) }
            .sorted { ($0.isDefault == true ? 0 : 1) < ($1.isDefault == true ? 0 : 1) }
            .first
        // nil = leave it to the server, so an unchanged choice never forces a second negotiation.
        let audio = preferredAudio?.index ?? serverAudio
        let audioLanguage = audioStreams.first { $0.index == (audio ?? audioStreams.first?.index) }?.language

        let subtitleLanguage = preferences.subtitleLanguage
        /// Full subtitles in the preferred language (not "forced" signs-only tracks), default track first.
        func full(in language: String) -> MediaStream? {
            subtitles
                .filter { $0.isForced != true && TrackLanguage.matches(language, $0.language) }
                .sorted { ($0.isDefault == true ? 0 : 1) < ($1.isDefault == true ? 0 : 1) }
                .first
        }
        /// Forced subtitles (signs, foreign dialogue) for the language being heard.
        var forced: MediaStream? {
            subtitles.first { $0.isForced == true && ($0.language == nil || $0.language?.lowercased() == audioLanguage?.lowercased()) }
        }

        let subtitle: Int
        switch preferences.subtitleMode {
        case .serverDefault:
            subtitle = serverSubtitle ?? -1
        case .always:
            subtitle = full(in: subtitleLanguage)?.index ?? serverSubtitle ?? subtitles.first { $0.isForced != true }?.index ?? -1
        case .foreign:
            if TrackLanguage.matches(subtitleLanguage, audioLanguage) {
                subtitle = forced?.index ?? -1 // you understand the audio
            } else {
                subtitle = full(in: subtitleLanguage)?.index ?? serverSubtitle ?? -1
            }
        case .off:
            subtitle = forced?.index ?? -1
        }
        return TrackChoice(audio: audio, subtitle: subtitle)
    }
}
