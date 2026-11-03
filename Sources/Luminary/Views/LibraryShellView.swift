import AppKit
import JellyfinKit
import SwiftUI

/// The app's one background color. Pages fade artwork into it, so it has to be the color the window really
/// shows (the system "window background" gets tinted by the wallpaper and wouldn't match). With the glass
/// option on, it becomes a light tint over a see-through window instead of a solid fill.
@MainActor
@Observable
final class AppTheme {
    static let shared = AppTheme()
    static let solidNS = NSColor(srgbRed: 0.145, green: 0.157, blue: 0.169, alpha: 1)
    private static let glassKey = "app.luminary.glass"

    var glass: Bool {
        didSet { UserDefaults.standard.set(glass, forKey: Self.glassKey) }
    }

    private init() {
        glass = UserDefaults.standard.object(forKey: Self.glassKey) as? Bool ?? true // glass is the default look
    }

    var backgroundNS: NSColor { glass ? Self.solidNS.withAlphaComponent(0.30) : Self.solidNS }
    var background: Color { Color(nsColor: backgroundNS) }

    // Convenience for views; reading these inside a body registers the dependency on `glass`.
    static var background: Color { shared.background }
    static var backgroundNS: NSColor { shared.backgroundNS }
}

enum SidebarItem: Hashable {
    case home
    case nextUp
    case favorites
    case library(id: String, name: String, collectionType: CollectionType?)
}

struct LibraryShellView: View {
    let session: AuthenticatedSession
    @Environment(SessionManager.self) private var manager
    @Environment(AppNavigator.self) private var navigator

    @State private var loadError: String?
    @State private var mouseMonitor: Any?
    @State private var escMonitor: Any?
    @State private var chrome = WindowChromeMetrics()
    @State private var isHoveringAccount = false
    @State private var isHoveringSettings = false
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openURL) private var openURL

    private var libraries: [BaseItemDto] { navigator.libraries }

    /// Floating panel width, and the space it reserves (panel + 8 pt margins). Fixed: the interface size only
    /// changes the sidebar's text and icons.
    private static let panelWidth: CGFloat = 232
    static let reservedWidth: CGFloat = panelWidth + 16
    /// Space between the button row and the sidebar panel. The same as the space above the row and as the
    /// sidebar's side and bottom margins, all measured from the inside edge of the window (the 1 pt outline isn't
    /// part of the dark area): 7 pt. Measures 1 pt short of the 8 pt side margin, but the window's outline makes it
    /// look equal, and it matches Claude's own window. The owner confirmed this by eye; don't "fix" it to 8.
    private static let rowGap: CGFloat = 7

    var body: some View {
        @Bindable var navigator = navigator
        // The sidebar is always mounted and always fully drawn at its final width. Showing/hiding it only
        // slides the finished panel (a cheap translation), so text and icons can't pop in late — unlike
        // the system split view, which re-renders the sidebar's contents after its animation.
        // Layout modelled on Apple's Music/TV apps: no window toolbar, a full-height floating sidebar with the
        // traffic lights on it, large titles inside each page. The page spans the whole window and runs
        // under the sidebar's glass; only its safe area is inset so content lays out beside the sidebar.
        ZStack(alignment: .topLeading) {
            NavigationStack(path: $navigator.path) {
                Group {
                    if navigator.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        detail
                    } else {
                        SearchResultsView(client: session.client, query: navigator.searchText)
                    }
                }
                .navigationDestination(for: BaseItemDto.self) { item in
                    ItemDestination(item: item, client: session.client)
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .series(id, seasonId):
                        SeriesDetailView(client: session.client, seriesId: id, initialSeasonId: seasonId)
                    }
                }
            }
            // Interface size (⌘= / ⌘-) for the pages; the sidebar applies it too, the title-bar row never does.
            .scaledFont(.body)
            .environment(\.interfaceScale, Preferences.shared.interfaceScale)
            .safeAreaPadding(.leading, navigator.isSidebarVisible ? Self.reservedWidth : 0)
            .offset(x: navigator.pageSlide)
            .scrollClipDisabled()
            .scrollIndicators(.hidden) // two-finger scrolling is all that's needed
            // Always the full window, even while a page is still loading (keeps everything pinned left).
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            sidebarPanel
                .scaledFont(.body)
                .environment(\.interfaceScale, Preferences.shared.interfaceScale)
                .frame(width: Self.panelWidth)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .padding(.top, chrome.rowCenterY + ChromeButton.size / 2 + Self.rowGap)
                .offset(x: navigator.isSidebarVisible ? 0 : -Self.reservedWidth)
                .animation(.smooth(duration: 0.3), value: navigator.isSidebarVisible)
                .allowsHitTesting(navigator.isSidebarVisible)
                .ignoresSafeArea(.container, edges: .top)

            chromeButtons
                .ignoresSafeArea(.container, edges: .top)

            trailingChrome
                .ignoresSafeArea(.container, edges: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.background)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { navigator.noteWindowWidth($0) }
        .background(WindowChromeReader(metrics: chrome, glass: AppTheme.shared.glass))
        .task {
            navigator.reset()
            await loadLibraries()
        }
        .task { await NetworkLocation.shared.update(client: session.client) } // home vs away quality
        .onAppear { installMouseBackButton(); installEscapeBack() }
        .onDisappear {
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            mouseMonitor = nil
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            escMonitor = nil
        }
    }

    // MARK: Title-bar row

    /// The title-bar row, level with the traffic lights: sidebar toggle (it never moves, so it can be clicked
    /// twice in a row), then Search, then Back when there's somewhere to go back to.
    private var chromeButtons: some View {
        @Bindable var navigator = navigator
        let toggleX = chrome.trafficLightsTrailing + 10
        let searchX = toggleX + ChromeButton.size + 8
        let searchWidth: CGFloat = 220
        let backX = searchX + searchWidth + 8
        let y = chrome.rowCenterY - ChromeButton.size / 2
        return ZStack(alignment: .topLeading) {
            ChromeButton(systemImage: "sidebar.leading", help: navigator.isSidebarVisible ? "Hide Sidebar (⌃⌘S)" : "Show Sidebar (⌃⌘S)") {
                navigator.toggleSidebar()
            }
            .offset(x: toggleX, y: y)

            SidebarSearchField(text: $navigator.searchText, focusRequest: navigator.searchFocusRequest)
                .frame(width: searchWidth, height: ChromeButton.size)
                .offset(x: searchX, y: y)

            if navigator.canGoBack {
                ChromeButton(systemImage: "chevron.backward", help: "Back" + HotkeyStore.shared.hint(.back)) {
                    navigator.goBack()
                }
                .offset(x: backX, y: y)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: navigator.canGoBack)
    }

    /// Right end of the title-bar row: Restart to Update while a downloaded update is waiting, and the version.
    private var trailingChrome: some View {
        let updater = AppUpdater.shared
        return HStack(spacing: 12) {
            if let version = updater.readyVersion {
                UpdateReadyButton(version: version) { updater.restartToUpdate() }
                    .transition(.opacity)
            }
            if AppVersion.current != "dev" {
                Text("v\(AppVersion.current)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: ChromeButton.size)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { chrome.trailingControlsWidth = $0 + 16 }
        .padding(.trailing, 16)
        .offset(y: chrome.rowCenterY - ChromeButton.size / 2)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .animation(.easeOut(duration: 0.2), value: updater.readyVersion)
    }

    // MARK: Sidebar

    private var sidebarPanel: some View {
        @Bindable var navigator = navigator
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    row(.home, "Home", "house")
                    row(.nextUp, "Next Up", "forward.end")
                    row(.favorites, "Favorites", "heart")

                    Text("Libraries")
                        .scaledFont(.subheadline, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                    ForEach(libraries) { library in
                        let name = library.name ?? "Library"
                        row(.library(id: library.id, name: name, collectionType: library.collectionType),
                            name, Self.icon(for: library))
                    }
                    if let loadError {
                        Button("Retry", systemImage: "arrow.clockwise") { Task { await loadLibraries() } }
                            .buttonStyle(.borderless)
                            .padding(.horizontal, 10)
                            .help(loadError)
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.never)

            accountFooter
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            SidebarMaterial()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07))
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 2)
    }

    private func row(_ item: SidebarItem, _ title: String, _ icon: String) -> some View {
        SidebarRow(title: title, systemImage: icon, isSelected: navigator.selection == item) {
            navigator.show(item)
        }
    }

    /// Mouse "back" side button (button 4, numbered 3) goes back, like Safari and Finder.
    private func installMouseBackButton() {
        guard mouseMonitor == nil else { return }
        let nav = navigator
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            guard event.buttonNumber == 3 else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard nav.canGoBack else { return false }
                nav.goBack()
                return true
            }
            return handled ? nil : event
        }
    }

    /// Esc goes back, like the Back button: from a series to wherever you came from. Only in the library window,
    /// and never while typing (the search field's own Esc clears it) or in a popover / sheet / the player.
    private func installEscapeBack() {
        guard escMonitor == nil else { return }
        let nav = navigator
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, !event.isARepeat,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  let window = event.window, window === WindowChromeReader.ReaderView.libraryWindow,
                  window.attachedSheet == nil, !(window.firstResponder is NSText) else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard nav.canGoBack else { return false }
                nav.goBack()
                return true
            }
            return handled ? nil : event
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch navigator.selection ?? .home {
        case .home:
            HomeView(client: session.client)
        case .nextUp:
            NextUpView(client: session.client)
        case .favorites:
            FavoritesView(client: session.client)
        case let .library(id, name, collectionType):
            LibraryGridView(client: session.client, libraryId: id, title: name, collectionType: collectionType)
                .id(id)
        }
    }

    /// Bottom of the sidebar, like Claude's: an account button that opens a menu (Settings, glass, report a
    /// problem, sign out), and a gear that goes straight to Settings.
    private var accountFooter: some View {
        let scale = Preferences.shared.interfaceScale
        return HStack(spacing: 6) {
            Menu {
                Section("\(session.user.name) · \(session.serverName)") {
                    Button("Settings…", systemImage: "gearshape") { openSettings() }
                    Toggle(isOn: Bindable(AppTheme.shared).glass) {
                        Label("Glass Background", systemImage: "drop")
                    }
                }
                Divider()
                Button("Report a Problem…", systemImage: "exclamationmark.bubble") { openURL(Links.issues) }
                Button("Support Luminary…", systemImage: "heart") { openURL(Links.support) }
                Divider()
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") {
                    Task { await manager.signOut() }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(session.user.name.prefix(1).uppercased())
                        .scaledFont(.callout, weight: .semibold)
                        .frame(width: 26 * scale, height: 26 * scale)
                        .background(.quaternary, in: Circle())
                    MarqueeText(text: session.user.name, isActive: isHoveringAccount)
                        .scaledFont(.callout, weight: .medium)
                    Image(systemName: "chevron.up.chevron.down")
                        .scaledFont(size: 10, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isHoveringAccount ? 0.08 : 0))
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .onHover { isHoveringAccount = $0 }
            .help("Account")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .scaledFont(size: 14)
                    .foregroundStyle(isHoveringSettings ? .primary : .secondary)
                    // Same height as the account button beside it (26 pt circle + 5 pt padding above and below).
                    .frame(width: 36 * scale, height: 36 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(isHoveringSettings ? 0.08 : 0))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringSettings = $0 }
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    @MainActor
    private func loadLibraries() async {
        do {
            let views = try await session.client.userViews()
            // Video-first client: hide music/books/playlists/live TV for now.
            let hidden: Set<CollectionType> = [.music, .books, .playlists, .livetv]
            navigator.libraries = views.filter { view in
                guard let type = view.collectionType else { return true }
                return !hidden.contains(type)
            }
            navigator.librariesDidLoad()
            loadError = nil
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
        }
    }

    static func icon(for library: BaseItemDto) -> String {
        let name = (library.name ?? "").lowercased()
        if name.contains("anime") { return "sparkles.tv" }
        switch library.collectionType?.rawValue {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "boxsets": return "square.stack"
        case "homevideos": return "video"
        default: return "folder"
        }
    }
}

/// Sidebar search box. ⌘F (Go → Search) focuses it; Esc clears it.
struct SidebarSearchField: View {
    @Binding var text: String
    let focusRequest: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand {
                    text = ""
                    isFocused = false
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(isFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: isFocused ? 1.5 : 1))
        .onChange(of: focusRequest) { isFocused = true }
    }
}

/// A poster grid. The column count is a pure function of the window width and whether the sidebar is open,
/// so it changes in the same update as the layout. (Measuring the grid's own width and reacting to it made
/// the first posters stretch for a frame at the new width, then shrink.) Window-drag resizes are debounced
/// in `AppNavigator.windowWidth`; opening/closing the sidebar re-flows at once, animated.
struct SettledGrid<Content: View>: View {
    var minimumCellWidth: CGFloat = 160
    var spacing: CGFloat = 20
    /// Horizontal padding the caller puts around the grid (both sides together).
    var horizontalPadding: CGFloat = 48
    @ViewBuilder let content: () -> Content

    @Environment(AppNavigator.self) private var navigator
    @Environment(\.interfaceScale) private var scale

    /// Bigger interface size → bigger cells → fewer columns (animated like any other column change).
    private var columnCount: Int {
        guard navigator.windowWidth > 0 else { return 4 }
        let inset = navigator.isSidebarVisible ? LibraryShellView.reservedWidth : 0
        let width = navigator.windowWidth - inset - horizontalPadding
        return max(1, Int((width + spacing * scale) / ((minimumCellWidth + spacing) * scale)))
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing * scale, alignment: .top), count: columnCount),
            alignment: .leading,
            spacing: 24 * scale,
            content: content
        )
        .animation(.smooth(duration: 0.3), value: columnCount)
    }
}

/// Sidebar row styled like the macOS sidebar: monochrome icon, gray pill when selected.
struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.interfaceScale) private var scale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9 * scale) {
                Image(systemName: systemImage)
                    .frame(width: 20 * scale)
                MarqueeText(text: title, isActive: isHovering)
            }
            .scaledFont(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7 * scale)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.11 : (isHovering ? 0.05 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// The real macOS sidebar material.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Sets the page title shown in the library window's title row.
    func pageTitle(_ title: String, subtitle: String? = nil) -> some View {
        modifier(PageTitleModifier(title: title, subtitle: subtitle))
    }
}

private struct PageTitleModifier: ViewModifier {
    let title: String
    let subtitle: String?

    func body(content: Content) -> some View {
        content
            // (no .navigationTitle: changing the window title makes AppKit re-lay out the title bar)
            .navigationBarBackButtonHidden(true)   // the shell draws its own Back button
    }
}

/// Large page title at the top of a page's scrolling content (Music/TV style).
struct PageHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .scaledFont(.largeTitle, weight: .bold)
                .lineLimit(1)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .scaledFont(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

/// Round 32 pt button for the title-bar row (sized so the gaps above and below the row look equal to the sidebar's side margins).
struct ChromeButton: View {
    static let size: CGFloat = 32

    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: Self.size, height: Self.size) // icon centered in the full circle
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

/// Capsule in the title-bar row, shown once an update has downloaded: restarts into the new version.
struct UpdateReadyButton: View {
    let version: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Restart to Update")
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: ChromeButton.size)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Luminary \(version) is ready. Restarts Luminary to install it (it also installs the next time you quit).")
        .onHover { isHovering = $0 }
    }
}

/// Where the window's traffic lights actually are, so our buttons line up with them exactly.
@MainActor
@Observable
final class WindowChromeMetrics {
    var rowCenterY: CGFloat = 18
    var trafficLightsTrailing: CGFloat = 76
    /// Width of the controls at the right end of the row (version, Restart to Update), kept clear of double-click-to-zoom.
    var trailingControlsWidth: CGFloat = 0
}

/// Reads the hosting NSWindow: measures the traffic lights (re-measured on resize / full screen) and lets
/// the window be dragged from empty background areas, since there's no title bar to grab.
struct WindowChromeReader: NSViewRepresentable {
    let metrics: WindowChromeMetrics
    /// Read from the theme in the parent's body so toggling it re-runs `updateNSView`.
    let glass: Bool

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.metrics = metrics
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) { nsView.applyGlass(glass) }

    final class ReaderView: NSView {
        /// Distance from the window's top edge to the center of the traffic lights and the button row. 1 pt more than
        /// the 8 pt panel margins, because the window's own outline takes some of the top gap.
        static let rowCenterTarget: CGFloat = 24
        /// Gap from the window's left edge to the red light. Equal to the gap above the lights
        /// (`rowCenterTarget` minus the 8 pt light radius), a couple of points more than the gap above them looks equal, because the window outline eats into the
        /// left edge as well and the lights are round (matched against Claude's own window).
        static let leftMargin: CGFloat = 17
        /// Distance from one light's left edge to the next: macOS's standard 23 pt (16 pt light + 7 pt gap).
        static let lightSpacing: CGFloat = 23
        private static let lightKinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        /// The library window (never the player's), so Esc-to-go-back can ignore other windows.
        nonisolated(unsafe) static weak var libraryWindow: NSWindow?

        weak var metrics: WindowChromeMetrics?
        private var observers: [NSObjectProtocol] = []
        private var titleObservation: NSKeyValueObservation?
        private var isPinning = false
        private var doubleClickMonitor: Any?
        private var glassView: NSView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            titleObservation = nil
            if let doubleClickMonitor { NSEvent.removeMonitor(doubleClickMonitor) }
            doubleClickMonitor = nil
            guard let window else { return }
            Self.libraryWindow = window
            installDoubleClickToZoom(on: window)

            window.isMovableByWindowBackground = true
            applyGlass(AppTheme.shared.glass)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])

            // AppKit puts the traffic lights back in their default spot whenever it re-lays out the title bar
            // (navigation changing the title, key/resign, resize, full screen…). Correcting after the fact
            // leaves a frame in the wrong place, so every one of those events is handled synchronously
            // (`queue: nil` runs the block on the posting thread, inside AppKit's own layout pass), which puts
            // the lights back before anything is drawn. `didUpdate` fires every event-loop turn as a net.
            func watch(_ name: Notification.Name, _ object: AnyObject?) {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { self?.pin() }
                })
            }
            for kind in Self.lightKinds {
                guard let button = window.standardWindowButton(kind) else { continue }
                button.isHidden = false
                button.postsFrameChangedNotifications = true
                watch(NSView.frameDidChangeNotification, button)
                if let container = button.superview {
                    container.postsFrameChangedNotifications = true
                    watch(NSView.frameDidChangeNotification, container)
                }
            }
            for name in [NSWindow.didUpdateNotification, NSWindow.didResizeNotification,
                         NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
                         NSWindow.didEndLiveResizeNotification] {
                watch(name, window)
            }
            titleObservation = window.observe(\.title, options: []) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.pin() }
            }

            pin()
            // First layout of a new window settles a moment after it appears.
            for delay in [0.05, 0.25, 0.8] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.pin() }
            }
        }

        /// Glass mode: the window itself becomes see-through and a glass layer sits behind the content, so what is
        /// behind the window shows through. Library window only (the player has its own window and never gets this).
        func applyGlass(_ on: Bool) {
            guard let window else { return }
            window.isOpaque = !on
            window.backgroundColor = on ? .clear : AppTheme.solidNS
            if on, glassView == nil, let frameView = window.contentView?.superview {
                let view: NSView
                if #available(macOS 26.0, *) {
                    view = NSGlassEffectView()
                } else {
                    let effect = NSVisualEffectView()
                    effect.material = .underWindowBackground
                    effect.blendingMode = .behindWindow
                    effect.state = .active
                    view = effect
                }
                view.frame = frameView.bounds
                view.autoresizingMask = [.width, .height]
                frameView.addSubview(view, positioned: .below, relativeTo: window.contentView)
                glassView = view
            } else if !on, let glassView {
                glassView.removeFromSuperview()
                self.glassView = nil
            }
            window.invalidateShadow()
        }

        /// With no title bar to grab, double-clicking the empty strip along the top edge zooms the window to fill
        /// the screen (and back), like a normal title bar. Our own controls on the left are excluded.
        private func installDoubleClickToZoom(on window: NSWindow) {
            doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak window] event in
                guard event.clickCount == 2, let window, event.window === window, let self,
                      let metrics = self.metrics, let contentHeight = window.contentView?.bounds.height
                else { return event }
                let fromTop = contentHeight - event.locationInWindow.y
                let controlsRight = metrics.trafficLightsTrailing + 10 + ChromeButton.size * 2 + 220 + 8 * 4
                let trailingControlsLeft = window.contentView.map { $0.bounds.width - metrics.trailingControlsWidth } ?? .infinity
                guard fromTop >= 0, fromTop <= 44, event.locationInWindow.x > controlsRight,
                      event.locationInWindow.x < trailingControlsLeft else { return event }
                window.zoom(nil)
                return nil
            }
        }

        /// Puts each traffic light's center exactly `rowCenterTarget` from the top, and publishes where the
        /// row should go. Idempotent and re-entrancy safe: moving one light can make AppKit move the others,
        /// so it repeats until all three agree (bounded).
        private func pin() {
            guard !isPinning, let window, let metrics else { return }
            isPinning = true
            defer { isPinning = false }

            if window.styleMask.contains(.fullScreen) {
                // No traffic lights in full screen: keep the buttons near the top-left corner.
                if metrics.rowCenterY != Self.rowCenterTarget { metrics.rowCenterY = Self.rowCenterTarget }
                if metrics.trafficLightsTrailing != 4 { metrics.trafficLightsTrailing = 4 }
                return
            }
            guard let contentHeight = window.contentView?.bounds.height else { return }

            for _ in 0..<4 {
                var moved = false
                for (index, kind) in Self.lightKinds.enumerated() {
                    guard let button = window.standardWindowButton(kind) else { continue }
                    let rect = button.convert(button.bounds, to: nil)
                    let dy = (contentHeight - rect.midY) - Self.rowCenterTarget
                    // Left margin equals the top margin; the three lights keep AppKit's 7 pt gaps.
                    let targetLeft = Self.leftMargin + CGFloat(index) * Self.lightSpacing
                    let dx = targetLeft - rect.minX
                    guard abs(dy) >= 0.5 || abs(dx) >= 0.5 else { continue }
                    let flipped = button.superview?.isFlipped == true
                    button.setFrameOrigin(NSPoint(x: button.frame.origin.x + dx,
                                                  y: button.frame.origin.y + (flipped ? -dy : dy)))
                    moved = true
                }
                if !moved { break }
            }

            if let zoom = window.standardWindowButton(.zoomButton) {
                let trailing = zoom.convert(zoom.bounds, to: nil).maxX.rounded()
                if metrics.rowCenterY != Self.rowCenterTarget { metrics.rowCenterY = Self.rowCenterTarget }
                if metrics.trafficLightsTrailing != trailing { metrics.trafficLightsTrailing = trailing }
            }
        }
    }
}
