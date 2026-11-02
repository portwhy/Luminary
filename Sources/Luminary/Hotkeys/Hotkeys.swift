import AppKit
import Observation
import SwiftUI

/// A key + modifiers, matched by physical key code (so it works with any keyboard layout).
struct KeyBinding: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt
    var key: String // display label captured at record time: "→", "Space", "F"

    static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevant).rawValue
        self.key = key
    }

    /// Build from a pressed key (shortcut recorder). Returns nil for keys we can't label.
    init?(event: NSEvent) {
        let label: String
        if let name = Self.specialNames[event.keyCode] {
            label = name
        } else if let characters = event.characters(byApplyingModifiers: [])?.uppercased(),
                  characters.count == 1, characters != " " {
            label = characters
        } else {
            return nil
        }
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags, key: label)
    }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.relevant) == modifierFlags
    }

    /// "⇧→", "⌘[", "Space"
    var display: String {
        var symbols = ""
        if modifierFlags.contains(.control) { symbols += "⌃" }
        if modifierFlags.contains(.option) { symbols += "⌥" }
        if modifierFlags.contains(.shift) { symbols += "⇧" }
        if modifierFlags.contains(.command) { symbols += "⌘" }
        return symbols + key
    }

    /// For menu items (Go menu).
    var keyboardShortcut: KeyboardShortcut? {
        let equivalent: KeyEquivalent
        switch keyCode {
        case 123: equivalent = .leftArrow
        case 124: equivalent = .rightArrow
        case 125: equivalent = .downArrow
        case 126: equivalent = .upArrow
        case 36, 76: equivalent = .return
        case 53: equivalent = .escape
        case 49: equivalent = .space
        case 51: equivalent = .delete
        case 116: equivalent = .pageUp
        case 121: equivalent = .pageDown
        case 115: equivalent = .home
        case 119: equivalent = .end
        case 48: equivalent = .tab
        default:
            guard key.count == 1, let character = key.lowercased().first else { return nil }
            equivalent = KeyEquivalent(character)
        }
        var eventModifiers: EventModifiers = []
        if modifierFlags.contains(.command) { eventModifiers.insert(.command) }
        if modifierFlags.contains(.option) { eventModifiers.insert(.option) }
        if modifierFlags.contains(.control) { eventModifiers.insert(.control) }
        if modifierFlags.contains(.shift) { eventModifiers.insert(.shift) }
        return KeyboardShortcut(equivalent, modifiers: eventModifiers)
    }

    static let specialNames: [UInt16: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑",
        49: "Space", 36: "Return", 76: "Enter", 53: "Esc", 51: "Delete", 117: "⌦", 48: "Tab",
        116: "Page Up", 121: "Page Down", 115: "Home", 119: "End",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

enum HotkeyGroup: String, CaseIterable, Identifiable {
    case playback, seeking, tracks, episodes, navigation
    var id: String { rawValue }

    var title: String {
        switch self {
        case .playback: "Playback"
        case .seeking: "Seeking & Skipping"
        case .tracks: "Audio, Subtitles & Speed"
        case .episodes: "Episodes"
        case .navigation: "Library Navigation"
        }
    }
}

enum HotkeyAction: String, CaseIterable, Identifiable {
    // Player
    case playPause, toggleFullScreen, exitPlayer, toggleStats, volumeUp, volumeDown, toggleMute
    case seekBack, seekForward, seekBackLong, seekForwardLong, skipSegment, previousChapter, nextChapter, undoJump
    case cycleAudio, cycleSubtitles, subtitlesEarlier, subtitlesLater, speedDown, speedUp, speedReset
    case previousEpisode, nextEpisode
    // App
    case back, goHome, goNextUp, goFavorites, search, refresh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playPause: "Play / Pause"
        case .toggleFullScreen: "Full Screen"
        case .exitPlayer: "Exit Full Screen, then Back to Library"
        case .toggleStats: "Playback Stats"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .toggleMute: "Mute"
        case .seekBack: "Back 5 Seconds"
        case .seekForward: "Forward 5 Seconds"
        case .seekBackLong: "Back 30 Seconds"
        case .seekForwardLong: "Forward 30 Seconds"
        case .skipSegment: "Skip Intro / Credits / Recap, or Play Next"
        case .previousChapter: "Previous Chapter"
        case .nextChapter: "Next Chapter"
        case .undoJump: "Jump Back to Where You Were"
        case .cycleAudio: "Next Audio Track"
        case .cycleSubtitles: "Next Subtitle Track"
        case .subtitlesEarlier: "Subtitles Earlier (0.1 s)"
        case .subtitlesLater: "Subtitles Later (0.1 s)"
        case .speedDown: "Slower"
        case .speedUp: "Faster"
        case .speedReset: "Normal Speed"
        case .previousEpisode: "Previous Episode"
        case .nextEpisode: "Next Episode"
        case .back: "Back"
        case .goHome: "Home"
        case .goNextUp: "Next Up"
        case .goFavorites: "Favorites"
        case .search: "Search"
        case .refresh: "Refresh"
        }
    }

    var group: HotkeyGroup {
        switch self {
        case .playPause, .toggleFullScreen, .exitPlayer, .toggleStats, .volumeUp, .volumeDown, .toggleMute: .playback
        case .seekBack, .seekForward, .seekBackLong, .seekForwardLong, .skipSegment, .previousChapter, .nextChapter, .undoJump: .seeking
        case .cycleAudio, .cycleSubtitles, .subtitlesEarlier, .subtitlesLater, .speedDown, .speedUp, .speedReset: .tracks
        case .previousEpisode, .nextEpisode: .episodes
        case .back, .goHome, .goNextUp, .goFavorites, .search, .refresh: .navigation
        }
    }

    var isPlayerAction: Bool { group != .navigation }

    var defaultBinding: KeyBinding? {
        switch self {
        case .playPause: KeyBinding(keyCode: 49, key: "Space")
        case .toggleFullScreen: KeyBinding(keyCode: 3, key: "F")
        case .exitPlayer: KeyBinding(keyCode: 53, key: "Esc")
        case .toggleStats: KeyBinding(keyCode: 34, key: "I")
        case .volumeUp: KeyBinding(keyCode: 126, key: "↑")
        case .volumeDown: KeyBinding(keyCode: 125, key: "↓")
        case .toggleMute: KeyBinding(keyCode: 46, key: "M")
        case .seekBack: KeyBinding(keyCode: 123, key: "←")
        case .seekForward: KeyBinding(keyCode: 124, key: "→")
        case .seekBackLong: KeyBinding(keyCode: 123, modifiers: .shift, key: "←")
        case .seekForwardLong: KeyBinding(keyCode: 124, modifiers: .shift, key: "→")
        case .skipSegment: KeyBinding(keyCode: 36, key: "Return")
        case .previousChapter: KeyBinding(keyCode: 116, key: "Page Up")
        case .nextChapter: KeyBinding(keyCode: 121, key: "Page Down")
        case .undoJump: KeyBinding(keyCode: 6, modifiers: .command, key: "Z")
        case .cycleAudio: KeyBinding(keyCode: 0, key: "A")
        case .cycleSubtitles: KeyBinding(keyCode: 1, key: "S")
        case .subtitlesEarlier: KeyBinding(keyCode: 6, key: "Z")
        case .subtitlesLater: KeyBinding(keyCode: 7, key: "X")
        case .speedDown: KeyBinding(keyCode: 33, key: "[")
        case .speedUp: KeyBinding(keyCode: 30, key: "]")
        case .speedReset: KeyBinding(keyCode: 42, key: "\\")
        case .previousEpisode: KeyBinding(keyCode: 35, key: "P")
        case .nextEpisode: KeyBinding(keyCode: 45, key: "N")
        case .back: KeyBinding(keyCode: 33, modifiers: .command, key: "[")
        case .goHome: KeyBinding(keyCode: 18, modifiers: .command, key: "1")
        case .goNextUp: KeyBinding(keyCode: 19, modifiers: .command, key: "2")
        case .goFavorites: KeyBinding(keyCode: 20, modifiers: .command, key: "3")
        case .search: KeyBinding(keyCode: 3, modifiers: .command, key: "F")
        case .refresh: KeyBinding(keyCode: 15, modifiers: .command, key: "R")
        }
    }
}

/// User-customisable shortcuts. Only differences from the defaults are stored (UserDefaults), so new
/// default shortcuts in future versions show up automatically.
@MainActor
@Observable
final class HotkeyStore {
    static let shared = HotkeyStore()

    /// actionId → binding; a stored nil means "deliberately cleared".
    private var overrides: [String: KeyBinding?] = [:]
    /// Shown under the list after a change, e.g. "⌘[ was moved from Slower."
    private(set) var notice: String?

    @ObservationIgnored private let storageKey = "app.luminary.hotkeys"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: KeyBinding?].self, from: data) {
            overrides = decoded
        }
    }

    func binding(for action: HotkeyAction) -> KeyBinding? {
        if let override = overrides[action.rawValue] { return override }
        return action.defaultBinding
    }

    func isCustomized(_ action: HotkeyAction) -> Bool {
        overrides[action.rawValue] != nil
    }

    /// " (M)" for tooltips; empty when unbound.
    func hint(_ action: HotkeyAction) -> String {
        binding(for: action).map { " (\($0.display))" } ?? ""
    }

    func shortcut(_ action: HotkeyAction) -> KeyboardShortcut? {
        binding(for: action)?.keyboardShortcut
    }

    func playerAction(for event: NSEvent) -> HotkeyAction? {
        HotkeyAction.allCases.first { $0.isPlayerAction && binding(for: $0)?.matches(event) == true }
    }

    /// Assign (or clear, with nil). A binding can only do one thing, so it's taken off any other action.
    func set(_ binding: KeyBinding?, for action: HotkeyAction) {
        notice = nil
        if let binding {
            for other in HotkeyAction.allCases where other != action && self.binding(for: other) == binding {
                overrides[other.rawValue] = .some(nil)
                notice = "\(binding.display) was removed from “\(other.title)”."
            }
        }
        if binding == action.defaultBinding {
            overrides.removeValue(forKey: action.rawValue)
        } else {
            overrides[action.rawValue] = .some(binding)
        }
        save()
    }

    func reset(_ action: HotkeyAction) {
        notice = nil
        overrides.removeValue(forKey: action.rawValue)
        // If the default now collides with something the user assigned, clear the other one.
        if let binding = action.defaultBinding {
            for other in HotkeyAction.allCases where other != action && self.binding(for: other) == binding {
                overrides[other.rawValue] = .some(nil)
                notice = "\(binding.display) was removed from “\(other.title)”."
            }
        }
        save()
    }

    func resetAll() {
        overrides = [:]
        notice = "All shortcuts restored to their defaults."
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
