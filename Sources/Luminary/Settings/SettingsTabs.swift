import AppKit
import JellyfinKit
import SwiftUI

/// Public pages the app links to (About tab, account menu, login screen).
enum Links {
    static let github = URL(string: "https://github.com/portwhy/Luminary")!
    static let issues = URL(string: "https://github.com/portwhy/Luminary/issues")!
    static let support = URL(string: "https://ko-fi.com/portwhy")!
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable private var preferences = Preferences.shared
    @Bindable private var theme = AppTheme.shared
    @Environment(SessionManager.self) private var session
    @Environment(AppNavigator.self) private var navigator
    private let hotkeys = HotkeyStore.shared

    /// The slider moves in steps (85 % … 150 %).
    private var scaleStep: Binding<Double> {
        Binding(
            get: { Double(Preferences.interfaceScales.firstIndex(of: preferences.interfaceScale) ?? 1) },
            set: { preferences.interfaceScale = Preferences.interfaceScales[Int($0.rounded())] }
        )
    }

    private var shortcutHint: String {
        [HotkeyAction.zoomIn, .zoomOut, .zoomReset]
            .compactMap { hotkeys.binding(for: $0)?.display }
            .joined(separator: " · ")
    }

    var body: some View {
        Form {
            if case .signedIn(let account) = session.state {
                Section("Account") {
                    LabeledContent {
                        Button("Sign Out") { Task { await session.signOut() } }
                    } label: {
                        Text(account.user.name)
                        Text("Signed in to \(account.serverName)")
                    }
                }
            }

            Section {
                LabeledContent("Interface size") {
                    HStack(spacing: 10) {
                        Slider(value: scaleStep, in: 0...Double(Preferences.interfaceScales.count - 1), step: 1) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "textformat.size.smaller")
                        } maximumValueLabel: {
                            Image(systemName: "textformat.size.larger")
                        }
                        .frame(width: 220)
                        Text("\(Int((preferences.interfaceScale * 100).rounded())) %")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Glass background", isOn: $theme.glass)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Interface size makes text, posters and cards bigger or smaller. Shortcuts: \(shortcutHint).")
                    .foregroundStyle(.secondary)
            }

            Section("Library") {
                Picker("Open to", selection: $preferences.startPage) {
                    Text("Home").tag("home")
                    Text("Next Up").tag("nextUp")
                    Text("Favorites").tag("favorites")
                    if !navigator.libraries.isEmpty {
                        Divider()
                        ForEach(navigator.libraries) { library in
                            Text(library.name ?? "Library").tag("library:\(library.id)")
                        }
                    }
                }
                Toggle("Hide watched items in libraries", isOn: $preferences.hideWatchedInLibraries)
            }

            Section {
                Toggle("Show Recently Added on Home", isOn: $preferences.showRecentlyAdded)
                if preferences.showRecentlyAdded {
                    ForEach(navigator.libraries) { library in
                        Toggle(library.name ?? "Library", isOn: Binding(
                            get: { !preferences.hiddenRecentlyAdded.contains(library.id) },
                            set: { shown in
                                if shown {
                                    preferences.hiddenRecentlyAdded.remove(library.id)
                                } else {
                                    preferences.hiddenRecentlyAdded.insert(library.id)
                                }
                            }
                        ))
                        .padding(.leading, 16)
                    }
                }
            } header: {
                Text("Home")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Playback

struct PlaybackSettings: View {
    @Bindable private var preferences = Preferences.shared
    private let location = NetworkLocation.shared

    private var qualityChoices: some View {
        ForEach(QualityOption.all) { option in
            Text(option.bitrate == JellyfinClient.unlimitedBitrate ? "Original (best, no transcoding)" : option.label)
                .tag(option.bitrate)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("At home", selection: $preferences.qualityAtHome) { qualityChoices }
                Picker("Away from home", selection: $preferences.qualityAway) { qualityChoices }
            } header: {
                Text("Quality")
            } footer: {
                Text("“Home” means the same network as your Jellyfin server. "
                     + (location.isHome ? "You're at home right now." : "You're away from home right now.")
                     + " Picking a quality in the player changes the one for where you are.")
                    .foregroundStyle(.secondary)
            }

            Section("Skipping") {
                Picker("Intros and recaps", selection: $preferences.introSkip) {
                    ForEach(SegmentSkipMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Credits", selection: $preferences.creditsSkip) {
                    ForEach(SegmentSkipMode.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Episodes") {
                Toggle("Play the next episode automatically", isOn: $preferences.autoplayNext)
                Picker("Show Up Next", selection: $preferences.upNextCountdown) {
                    ForEach([10, 20, 30, 45, 60], id: \.self) { Text("\($0) seconds before the end").tag($0) }
                }
            }

            Section {
                Picker("Arrow keys", selection: $preferences.seekShort) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Picker("Shift + arrow keys", selection: $preferences.seekLong) {
                    ForEach([30, 60, 90, 120], id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Picker("On-screen skip buttons", selection: $preferences.skipButtonSeconds) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) seconds").tag($0) }
                }
            } header: {
                Text("Skip Lengths")
            }

            Section("Starting a Video") {
                Picker("When you've watched part of it", selection: $preferences.resumeMode) {
                    ForEach(ResumeMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Speed", selection: $preferences.defaultSpeed) {
                    ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { speed in
                        Text(speed == 1 ? "Normal" : String(format: "%g×", speed)).tag(speed)
                    }
                }
            }

            Section {
                Picker("Hide controls after", selection: $preferences.controlsHideDelay) {
                    ForEach([1.5, 2.5, 4.0, 6.0], id: \.self) { Text(String(format: "%g seconds", $0)).tag($0) }
                }
                Picker("Maximum volume", selection: $preferences.volumeLimit) {
                    ForEach([100, 130, 150], id: \.self) { Text("\($0) %").tag($0) }
                }
            } header: {
                Text("Controls")
            } footer: {
                Text("Volume above 100 % boosts quiet videos (↑ key). It can distort loud ones.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Audio & Subtitles

struct SubtitleSettings: View {
    @Bindable private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                Picker("Preferred audio", selection: $preferences.audioLanguage) {
                    Text("Use my Jellyfin settings").tag("")
                    Divider()
                    ForEach(TrackLanguage.all) { Text($0.name).tag($0.id) }
                }
            } header: {
                Text("Audio")
            } footer: {
                Text("Used when a video has this language; otherwise the server's choice is kept.")
                    .foregroundStyle(.secondary)
            }

            Section("Subtitles") {
                Picker("Show subtitles", selection: $preferences.subtitleMode) {
                    ForEach(SubtitleMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Subtitle language", selection: $preferences.subtitleLanguage) {
                    ForEach(TrackLanguage.all) { Text($0.name).tag($0.id) }
                }
                .disabled(preferences.subtitleMode == .serverDefault || preferences.subtitleMode == .off)
            }

            Section {
                Picker("Size", selection: $preferences.subtitleScale) {
                    ForEach([0.75, 0.9, 1.0, 1.15, 1.3, 1.5], id: \.self) { Text("\(Int($0 * 100)) %").tag($0) }
                }
                Picker("Position", selection: $preferences.subtitlePosition) {
                    Text("Bottom").tag(100)
                    Text("A little higher").tag(95)
                    Text("Higher").tag(90)
                }
                Picker("Styling", selection: $preferences.subtitleStyle) {
                    ForEach(SubtitleStyle.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Look")
            } footer: {
                Text("Styled subtitles (common in anime) keep their own fonts, colors and placement unless you choose clean, simple text. Changes apply to the next video.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Video

struct VideoSettings: View {
    @Bindable private var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                Picker("HDR", selection: $preferences.hdrMode) {
                    ForEach(HDRMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Smooth color banding", isOn: $preferences.deband)
                Toggle("Hardware decoding", isOn: $preferences.hardwareDecoding)
            } footer: {
                Text("HDR video lights up HDR displays like the MacBook Pro's; “Always SDR” converts it for SDR screens. "
                     + "Smoothing banding helps soft gradients in anime and dark scenes, at a small GPU cost. "
                     + "Turn hardware decoding off only to troubleshoot: it uses much more power. Changes apply to the next video.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutSettings: View {
    @Environment(\.openURL) private var openURL

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development build"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text("Luminary").font(.title.weight(.semibold))
                Text("Version \(version)").foregroundStyle(.secondary)
            }
            Text("A fast, native Jellyfin player for Mac.\nFree and open source. Built with AI help.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("GitHub") { openURL(Links.github) }
                Button("Report a Problem") { openURL(Links.issues) }
                Button {
                    openURL(Links.support)
                } label: {
                    Label("Support Luminary", systemImage: "heart.fill")
                }
            }
            .padding(.top, 6)

            Spacer()
            Text("Licensed under the GNU GPL v3. Playback by mpv and FFmpeg (via MPVKit), with libass, libplacebo and MoltenVK.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
}
