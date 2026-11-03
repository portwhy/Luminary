import Foundation
import JellyfinKit
import Observation
import SwiftUI

/// Pages you can open by id alone (no full item needed), e.g. from an episode's right-click menu.
enum Route: Hashable {
    case series(id: String, seasonId: String?)
}

/// What a library grid is currently filtered by. Within a category an item matches ANY selection; an item
/// must match every category that has a selection.
struct LibraryFilter: Equatable {
    var tags: Set<String> = []
    var genres: Set<String> = []
    var years: Set<Int> = []

    var isEmpty: Bool { tags.isEmpty && genres.isEmpty && years.isEmpty }
    var count: Int { tags.count + genres.count + years.count }
}

/// Library navigation state, shared with the menu bar so shortcuts (⌘[, ⌘1…) can drive it.
@MainActor
@Observable
final class AppNavigator {
    @ObservationIgnored private var pendingStartLibrary: String?

    /// Called once the sidebar's libraries are known: opens the start-page library if that's the setting
    /// (unless you've already gone somewhere else).
    func librariesDidLoad() {
        defer { pendingStartLibrary = nil }
        guard let id = pendingStartLibrary, selection == .home, path.isEmpty,
              let index = libraries.firstIndex(where: { $0.id == id }) else { return }
        showLibrary(at: index)
    }

    private(set) var selection: SidebarItem? = .home
    var path = NavigationPath()
    var searchText = ""
    var libraries: [BaseItemDto] = []
    /// Filters per library id, kept while the app is open so they survive leaving and returning.
    var libraryFilters: [String: LibraryFilter] = [:]
    private(set) var isSidebarVisible = true
    private(set) var pageTitle = "Home"
    private(set) var pageSubtitle: String?
    /// Bumped to ask the sidebar's search field to take focus.
    private(set) var searchFocusRequest = 0

    var canGoBack: Bool { !path.isEmpty || !searchText.isEmpty }

    func goBack() {
        if !path.isEmpty {
            path.removeLast()
        } else if !searchText.isEmpty {
            searchText = ""
        }
    }

    /// Switching section starts from that section's root, like Music or Finder.
    func show(_ item: SidebarItem?) {
        guard item != selection else { return }
        selection = item
        path = NavigationPath()
        searchText = ""
    }

    func showLibrary(at index: Int) {
        guard libraries.indices.contains(index) else { return }
        let library = libraries[index]
        show(.library(id: library.id, name: library.name ?? "Library", collectionType: library.collectionType))
    }

    /// Window content width, debounced while the window is being dragged to a new size. Grids derive their
    /// column count from this (plus whether the sidebar is open), so the count changes in the very same
    /// update as the layout instead of one frame later.
    private(set) var windowWidth: CGFloat = 0
    @ObservationIgnored private var widthTask: Task<Void, Never>?

    func noteWindowWidth(_ width: CGFloat) {
        guard width != windowWidth else { return }
        if windowWidth == 0 { windowWidth = width; return }
        widthTask?.cancel()
        widthTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            windowWidth = width
        }
    }

    /// Horizontal offset applied to the page while the sidebar slides. The page is laid out once, at its
    /// final width, and then glides in as one piece with the sidebar, so nothing re-lays out every frame.
    var pageSlide: CGFloat = 0

    func toggleSidebar() {
        let show = !isSidebarVisible
        // Start the page where it visually was (final layout shifted back), without animating...
        pageSlide = show ? -LibraryShellView.reservedWidth : LibraryShellView.reservedWidth
        isSidebarVisible = show
        // ...then slide it home on the next turn so both changes are drawn in the same frame first.
        DispatchQueue.main.async { [self] in
            withAnimation(.smooth(duration: 0.3)) { pageSlide = 0 }
        }
    }

    func setPage(title: String, subtitle: String?) {
        pageTitle = title
        pageSubtitle = (subtitle?.isEmpty ?? true) ? nil : subtitle
    }

    func open(_ route: Route) {
        path.append(route)
    }

    func focusSearch() {
        searchFocusRequest += 1
    }

    func reset() {
        // Settings → General → Start page. A library has to wait until the library list has loaded.
        let start = Preferences.shared.startPage
        selection = start == "nextUp" ? .nextUp : start == "favorites" ? .favorites : .home
        pendingStartLibrary = start.hasPrefix("library:") ? String(start.dropFirst("library:".count)) : nil
        path = NavigationPath()
        searchText = ""
        libraries = []
    }
}
