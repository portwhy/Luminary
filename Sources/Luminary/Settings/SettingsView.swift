import AppKit
import SwiftUI

struct SettingsView: View {
    private enum Tab { case general, playback, audio, video, shortcuts, about }

    /// Always opens on General (macOS would otherwise reopen the last tab you looked at).
    @State private var tab = Tab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.rectangle") }
                .tag(Tab.playback)
            SubtitleSettings()
                .tabItem { Label("Audio/Subs", systemImage: "captions.bubble") }
                .tag(Tab.audio)
            VideoSettings()
                .tabItem { Label("Video", systemImage: "sparkles.tv") }
                .tag(Tab.video)
            ShortcutsSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(Tab.shortcuts)
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .onAppear { tab = .general }
        .frame(width: 680, height: 680)
    }
}

struct ShortcutsSettings: View {
    private let store = HotkeyStore.shared

    var body: some View {
        VStack(spacing: 0) {
            Form {
                ForEach(HotkeyGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(HotkeyAction.allCases.filter { $0.group == group }) { action in
                            LabeledContent(action.title) {
                                HStack(spacing: 6) {
                                    ShortcutRecorder(action: action)
                                    Button {
                                        store.reset(action)
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Restore default (\(action.defaultBinding?.display ?? "none"))")
                                    .opacity(store.isCustomized(action) ? 1 : 0)
                                    .disabled(!store.isCustomized(action))
                                }
                            }
                        }
                    }
                }
                Section("Built In") {
                    LabeledContent("Jump to 0–90 % of the video", value: "0 – 9")
                    LabeledContent("Open library 1–6 in the sidebar", value: "⌘4 – ⌘9")
                    LabeledContent("Show / hide sidebar", value: "⌃⌘S")
                    LabeledContent("Close player window", value: "⌘W")
                    LabeledContent("Mouse back button", value: "Back")
                    LabeledContent("Two-finger swipe in the player", value: "Scrub")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text(store.notice ?? "Click a shortcut and press the new keys. Esc cancels, Delete clears it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore All Defaults") { store.resetAll() }
            }
            .padding(14)
        }
    }
}

/// Click, press keys, done. Captures the next key-down in this window only.
struct ShortcutRecorder: View {
    let action: HotkeyAction
    private let store = HotkeyStore.shared

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(isRecording ? "Press keys…" : (store.binding(for: action)?.display ?? "None"))
                .font(.system(.body, design: .rounded).weight(.medium))
                .foregroundStyle(store.binding(for: action) == nil && !isRecording ? .secondary : .primary)
                .frame(minWidth: 96)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                let modifiers = event.modifierFlags.intersection(KeyBinding.relevant)
                if event.keyCode == 53 && modifiers.isEmpty {           // Esc: cancel
                    stopRecording()
                } else if (event.keyCode == 51 || event.keyCode == 117) && modifiers.isEmpty { // Delete: clear
                    store.set(nil, for: action)
                    stopRecording()
                } else if let binding = KeyBinding(event: event) {
                    store.set(binding, for: action)
                    stopRecording()
                }
            }
            return nil // swallow while recording
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}
