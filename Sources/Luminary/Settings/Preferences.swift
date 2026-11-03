import AppKit
import JellyfinKit
import Observation
import SwiftUI

/// What to do when an intro, recap or credits segment starts (Jellyfin media segments).
enum SegmentSkipMode: String, CaseIterable, Identifiable {
    case button, automatic, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .button: "Show a Skip button"
        case .automatic: "Skip automatically"
        case .off: "Do nothing"
        }
    }
}

enum ResumeMode: String, CaseIterable, Identifiable {
    case resume, beginning
    var id: String { rawValue }
    var title: String {
        switch self {
        case .resume: "Resume where I left off"
        case .beginning: "Always start from the beginning"
        }
    }
}

enum SubtitleMode: String, CaseIterable, Identifiable {
    case serverDefault, always, foreign, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .serverDefault: "Use my Jellyfin settings"
        case .always: "Always"
        case .foreign: "Only when the audio is in another language"
        case .off: "Off (forced subtitles only)"
        }
    }
}

enum SubtitleStyle: String, CaseIterable, Identifiable {
    case original, simple
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Keep the file's styling"
        case .simple: "Clean, simple text"
        }
    }
}

enum HDRMode: String, CaseIterable, Identifiable {
    case automatic, sdr
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "HDR on HDR displays"
        case .sdr: "Always SDR"
        }
    }
}

/// Languages offered in Settings. Jellyfin reports ISO 639-2 codes (some files use 639-1 or the "T" variants),
/// so each language matches all of its spellings.
struct TrackLanguage: Identifiable, Hashable {
    let name: String
    let codes: [String]
    var id: String { codes[0] }

    static let all: [TrackLanguage] = [
        TrackLanguage(name: "English", codes: ["eng", "en"]),
        TrackLanguage(name: "Japanese", codes: ["jpn", "ja"]),
        TrackLanguage(name: "Spanish", codes: ["spa", "es"]),
        TrackLanguage(name: "French", codes: ["fre", "fra", "fr"]),
        TrackLanguage(name: "German", codes: ["ger", "deu", "de"]),
        TrackLanguage(name: "Italian", codes: ["ita", "it"]),
        TrackLanguage(name: "Portuguese", codes: ["por", "pt"]),
        TrackLanguage(name: "Korean", codes: ["kor", "ko"]),
        TrackLanguage(name: "Chinese", codes: ["chi", "zho", "zh"]),
        TrackLanguage(name: "Russian", codes: ["rus", "ru"]),
        TrackLanguage(name: "Hindi", codes: ["hin", "hi"]),
        TrackLanguage(name: "Arabic", codes: ["ara", "ar"]),
        TrackLanguage(name: "Dutch", codes: ["dut", "nld", "nl"]),
        TrackLanguage(name: "Polish", codes: ["pol", "pl"]),
        TrackLanguage(name: "Swedish", codes: ["swe", "sv"]),
        TrackLanguage(name: "Turkish", codes: ["tur", "tr"]),
    ]

    /// True when `code` (from a media stream) is this language. An empty preference never matches.
    static func matches(_ preference: String, _ code: String?) -> Bool {
        guard !preference.isEmpty, let code = code?.lowercased() else { return false }
        let codes = all.first { $0.id == preference }?.codes ?? [preference]
        return codes.contains(code)
    }
}

/// App-wide preferences (the Settings window), stored in UserDefaults. Read once when a screen or a video opens,
/// never per frame.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    // MARK: Appearance

    /// Interface size steps (View → Bigger / Smaller, ⌘= / ⌘-).
    static let interfaceScales: [Double] = [0.85, 1.0, 1.15, 1.3, 1.5]

    var interfaceScale = Stored.double("interfaceScale", 1.0) {
        didSet { Stored.set(interfaceScale, "interfaceScale") }
    }

    private var scaleIndex: Int { Self.interfaceScales.firstIndex(of: interfaceScale) ?? 1 }
    var canZoomIn: Bool { scaleIndex < Self.interfaceScales.count - 1 }
    var canZoomOut: Bool { scaleIndex > 0 }

    func zoomIn() { if canZoomIn { interfaceScale = Self.interfaceScales[scaleIndex + 1] } }
    func zoomOut() { if canZoomOut { interfaceScale = Self.interfaceScales[scaleIndex - 1] } }
    func resetZoom() { interfaceScale = 1.0 }

    // MARK: General

    /// "home", "nextUp", "favorites" or "library:<id>".
    var startPage = Stored.string("startPage", "home") { didSet { Stored.set(startPage, "startPage") } }
    var showRecentlyAdded = Stored.bool("showRecentlyAdded", true) { didSet { Stored.set(showRecentlyAdded, "showRecentlyAdded") } }
    /// Library ids whose Recently Added shelf is hidden on Home.
    var hiddenRecentlyAdded = Set(Stored.strings("hiddenRecentlyAdded")) {
        didSet { Stored.set(Array(hiddenRecentlyAdded), "hiddenRecentlyAdded") }
    }
    var hideWatchedInLibraries = Stored.bool("hideWatchedInLibraries", false) {
        didSet { Stored.set(hideWatchedInLibraries, "hideWatchedInLibraries") }
    }

    // MARK: Playback

    var qualityAtHome = Stored.int("qualityAtHome", Stored.int("maxBitrate", JellyfinClient.unlimitedBitrate)) {
        didSet { Stored.set(qualityAtHome, "qualityAtHome") }
    }
    var qualityAway = Stored.int("qualityAway", Stored.int("maxBitrate", JellyfinClient.unlimitedBitrate)) {
        didSet { Stored.set(qualityAway, "qualityAway") }
    }

    /// The quality cap for where the Mac is right now (home network or not).
    var currentMaxBitrate: Int {
        get { NetworkLocation.shared.isHome ? qualityAtHome : qualityAway }
        set { if NetworkLocation.shared.isHome { qualityAtHome = newValue } else { qualityAway = newValue } }
    }

    var introSkip = Stored.enumValue("introSkip", SegmentSkipMode.button) { didSet { Stored.set(introSkip.rawValue, "introSkip") } }
    var creditsSkip = Stored.enumValue("creditsSkip", SegmentSkipMode.button) { didSet { Stored.set(creditsSkip.rawValue, "creditsSkip") } }
    var autoplayNext = Stored.bool("autoplayNext", true) { didSet { Stored.set(autoplayNext, "autoplayNext") } }
    var upNextCountdown = Stored.int("upNextCountdown", 30) { didSet { Stored.set(upNextCountdown, "upNextCountdown") } }
    var seekShort = Stored.int("seekShort", 5) { didSet { Stored.set(seekShort, "seekShort") } }
    var seekLong = Stored.int("seekLong", 30) { didSet { Stored.set(seekLong, "seekLong") } }
    var skipButtonSeconds = Stored.int("skipButtonSeconds", 10) { didSet { Stored.set(skipButtonSeconds, "skipButtonSeconds") } }
    var resumeMode = Stored.enumValue("resumeMode", ResumeMode.resume) { didSet { Stored.set(resumeMode.rawValue, "resumeMode") } }
    var defaultSpeed = Stored.double("defaultSpeed", 1.0) { didSet { Stored.set(defaultSpeed, "defaultSpeed") } }
    var controlsHideDelay = Stored.double("controlsHideDelay", 2.5) { didSet { Stored.set(controlsHideDelay, "controlsHideDelay") } }
    var volumeLimit = Stored.int("volumeLimit", 130) { didSet { Stored.set(volumeLimit, "volumeLimit") } }

    // MARK: Audio & subtitles

    /// TrackLanguage id ("jpn"), or "" for the server's choice.
    var audioLanguage = Stored.string("audioLanguage", "") { didSet { Stored.set(audioLanguage, "audioLanguage") } }
    var subtitleMode = Stored.enumValue("subtitleMode", SubtitleMode.serverDefault) { didSet { Stored.set(subtitleMode.rawValue, "subtitleMode") } }
    var subtitleLanguage = Stored.string("subtitleLanguage", "eng") { didSet { Stored.set(subtitleLanguage, "subtitleLanguage") } }
    var subtitleScale = Stored.double("subtitleScale", 1.0) { didSet { Stored.set(subtitleScale, "subtitleScale") } }
    /// mpv `sub-pos`: 100 is the bottom of the picture, smaller is higher.
    var subtitlePosition = Stored.int("subtitlePosition", 100) { didSet { Stored.set(subtitlePosition, "subtitlePosition") } }
    var subtitleStyle = Stored.enumValue("subtitleStyle", SubtitleStyle.original) { didSet { Stored.set(subtitleStyle.rawValue, "subtitleStyle") } }

    // MARK: Video (advanced)

    var hardwareDecoding = Stored.bool("hardwareDecoding", true) { didSet { Stored.set(hardwareDecoding, "hardwareDecoding") } }
    var hdrMode = Stored.enumValue("hdrMode", HDRMode.automatic) { didSet { Stored.set(hdrMode.rawValue, "hdrMode") } }
    var deband = Stored.bool("deband", false) { didSet { Stored.set(deband, "deband") } }

    private init() {
        if !Self.interfaceScales.contains(interfaceScale) { interfaceScale = 1.0 }
    }
}

/// UserDefaults under "app.luminary.<name>". Missing or mistyped values fall back to the default.
private enum Stored {
    private static let defaults = UserDefaults.standard
    private static func key(_ name: String) -> String { "app.luminary.\(name)" }

    static func bool(_ name: String, _ fallback: Bool) -> Bool {
        (defaults.object(forKey: key(name)) as? NSNumber)?.boolValue ?? fallback
    }
    static func int(_ name: String, _ fallback: Int) -> Int {
        guard let value = (defaults.object(forKey: key(name)) as? NSNumber)?.intValue, value > 0 else { return fallback }
        return value
    }
    static func double(_ name: String, _ fallback: Double) -> Double {
        guard let value = (defaults.object(forKey: key(name)) as? NSNumber)?.doubleValue, value > 0 else { return fallback }
        return value
    }
    static func string(_ name: String, _ fallback: String) -> String {
        defaults.string(forKey: key(name)) ?? fallback
    }
    static func strings(_ name: String) -> [String] {
        defaults.stringArray(forKey: key(name)) ?? []
    }
    static func enumValue<E: RawRepresentable>(_ name: String, _ fallback: E) -> E where E.RawValue == String {
        defaults.string(forKey: key(name)).flatMap(E.init(rawValue:)) ?? fallback
    }
    static func set(_ value: Any, _ name: String) {
        defaults.set(value, forKey: key(name))
    }
}

// MARK: - Interface scale

private struct InterfaceScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Size multiplier for the library window's pages and sidebar text. The title-bar row and menus stay at
    /// system size.
    var interfaceScale: CGFloat {
        get { self[InterfaceScaleKey.self] }
        set { self[InterfaceScaleKey.self] = newValue }
    }
}

/// A text style that grows with the interface scale. At 100 % it is exactly the system text style, so the
/// default look never changes; at other sizes it's the same font at a scaled point size (sharp, not zoomed).
private struct ScaledFont: ViewModifier {
    let style: Font.TextStyle?
    let size: CGFloat
    let weight: Font.Weight?
    let design: Font.Design

    @Environment(\.interfaceScale) private var scale

    func body(content: Content) -> some View {
        content.font(font)
    }

    private var font: Font {
        if scale == 1, let style {
            let base = Font.system(style, design: design)
            return weight.map { base.weight($0) } ?? base
        }
        return .system(size: (size * scale).rounded(), weight: weight ?? defaultWeight, design: design)
    }

    private var defaultWeight: Font.Weight { style == .headline ? .bold : .regular }
}

extension Font.TextStyle {
    /// The point size macOS uses for this style.
    var pointSize: CGFloat {
        let nsStyle: NSFont.TextStyle = switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
        return NSFont.preferredFont(forTextStyle: nsStyle).pointSize
    }
}

/// Standard macOS buttons come in fixed sizes and ignore the font, so they step a size up or down instead.
private struct ScaledControlSize: ViewModifier {
    let base: ControlSize
    @Environment(\.interfaceScale) private var scale

    func body(content: Content) -> some View {
        content.controlSize(size)
    }

    private var size: ControlSize {
        let order: [ControlSize] = [.mini, .small, .regular, .large, .extraLarge]
        let index = order.firstIndex(of: base) ?? 2
        let step = scale >= 1.3 ? 1 : (scale < 1 ? -1 : 0)
        return order[min(max(index + step, 0), order.count - 1)]
    }
}

extension View {
    /// Like `.controlSize(.large)`, but a size bigger at 130 % and up, a size smaller below 100 %.
    func scaledControlSize(_ base: ControlSize) -> some View {
        modifier(ScaledControlSize(base: base))
    }

    /// Like `.font(.callout.weight(.medium))`, but follows the interface size setting.
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(style: style, size: style.pointSize, weight: weight, design: design))
    }

    /// Like `.font(.system(size: 34, weight: .bold))`, but follows the interface size setting.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(style: nil, size: size, weight: weight, design: design))
    }
}
