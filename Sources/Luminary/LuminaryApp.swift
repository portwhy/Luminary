import AppKit
import SwiftUI

@main
struct LuminaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = SessionManager()
    @State private var navigator = AppNavigator()
    private let hotkeys = HotkeyStore.shared

    var body: some Scene {
        WindowGroup("Luminary") {
            RootView()
                .environment(session)
                .environment(navigator)
                .frame(minWidth: 960, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button(navigator.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") { navigator.toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.control, .command])
                Button(AppTheme.shared.glass ? "Solid Background" : "Glass Background") { AppTheme.shared.glass.toggle() }
                    .keyboardShortcut("g", modifiers: [.control, .command])
            }
            CommandMenu("Go") {
                Button("Back") { navigator.goBack() }
                    .keyboardShortcut(hotkeys.shortcut(.back))
                    .disabled(!navigator.canGoBack)
                Divider()
                Button("Home") { navigator.show(.home) }
                    .keyboardShortcut(hotkeys.shortcut(.goHome))
                Button("Next Up") { navigator.show(.nextUp) }
                    .keyboardShortcut(hotkeys.shortcut(.goNextUp))
                Button("Favorites") { navigator.show(.favorites) }
                    .keyboardShortcut(hotkeys.shortcut(.goFavorites))
                if !navigator.libraries.isEmpty {
                    Divider()
                    ForEach(Array(navigator.libraries.prefix(6).enumerated()), id: \.offset) { index, library in
                        Button(library.name ?? "Library") { navigator.showLibrary(at: index) }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 4)")), modifiers: .command)
                    }
                }
                Divider()
                Button("Search") { navigator.focusSearch() }
                    .keyboardShortcut(hotkeys.shortcut(.search))
                Button("Refresh") {
                    NotificationCenter.default.post(name: .luminaryLibraryChanged, object: nil)
                }
                .keyboardShortcut(hotkeys.shortcut(.refresh))
            }
            CommandMenu("Account") {
                Button("Sign Out") {
                    Task { await session.signOut() }
                }
                .disabled(!session.isSignedIn)
            }
        }

        // One window per playing item. Hidden title bar: video edge to edge, our own overlay on top.
        WindowGroup("Player", id: "player", for: PlaybackRequest.self) { $request in
            PlayerWindowRoot(request: $request)
                .environment(session)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)

        Settings {
            SettingsView()
        }
    }
}

/// `swift run` launches a bare executable (no .app bundle). Without this the window
/// opens behind other apps, has no Dock icon and won't take keyboard focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
