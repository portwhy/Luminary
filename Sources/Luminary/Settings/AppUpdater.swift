import AppKit
import Foundation
import Observation
import Sparkle

/// In-app updates through Sparkle: a background check every few hours, plus one when the app comes to the front
/// if the last was over an hour ago, Luminary → Check for Updates…, and
/// Settings → General → Updates. Updates are DMGs on GitHub Releases listed in `appcast.xml` in the repo, and Sparkle
/// only installs ones signed with our EdDSA key. Runs only in a real Luminary.app that has a feed URL in its
/// Info.plist (scripts/make-app.sh), so `swift run` and dev builds never check.
///
/// With automatic downloads on (the default), a new version downloads quietly and `readyVersion` is set: the library
/// window then shows a Restart to Update button. Ignoring it is fine, Sparkle installs the update when Luminary quits.
@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private let delegate = UpdaterDelegate()
    @ObservationIgnored private var installNow: (() -> Void)?

    var isAvailable: Bool { controller != nil }
    /// False while a check is already running.
    private(set) var canCheckForUpdates = false
    /// The version that's downloaded and waiting for a restart, if any.
    private(set) var readyVersion: String?

    var checksAutomatically: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }
    var installsAutomatically: Bool {
        didSet { controller?.updater.automaticallyDownloadsUpdates = installsAutomatically }
    }

    private init() {
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = hasFeed
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
            : nil
        checksAutomatically = controller?.updater.automaticallyChecksForUpdates ?? false
        installsAutomatically = controller?.updater.automaticallyDownloadsUpdates ?? false
        // Sparkle's scheduler never goes below an hour; every 4 hours, plus a check whenever Luminary comes to the front.
        controller?.updater.updateCheckInterval = 4 * 3600
        if controller != nil {
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { AppUpdater.shared.checkIfStale() }
            }
        }
        canCheckObservation = controller?.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { updater, _ in
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in AppUpdater.shared.canCheckForUpdates = canCheck }
        }
    }

    /// Coming back to Luminary after a while: look for a release now instead of waiting for the next scheduled check.
    /// The feed is a small text file, and this runs at most once an hour.
    private func checkIfStale() {
        guard let updater = controller?.updater, updater.automaticallyChecksForUpdates, updater.canCheckForUpdates,
              readyVersion == nil else { return }
        if let last = updater.lastUpdateCheckDate, Date().timeIntervalSince(last) < 3600 { return }
        updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Quits, installs the downloaded update and reopens Luminary.
    func restartToUpdate() {
        installNow?()
    }

    /// Luminary is quitting with a downloaded update waiting: Sparkle installs it now, so hand the sign-in over first.
    func applicationWillTerminate() {
        if readyVersion != nil { SessionManager.handOffForUpdate() }
    }

    fileprivate func updateIsReady(version: String, install: @escaping () -> Void) {
        installNow = install
        readyVersion = version
    }
}

/// Sparkle's delegate (it only keeps a weak reference, so `AppUpdater` owns it). Sparkle calls it on the main thread.
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    /// A silently downloaded update is ready. Returning true means we offer it ourselves (the Restart to Update
    /// button) instead of Sparkle popping up a window later; it still installs on quit either way.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let version = item.displayVersionString
        MainActor.assumeIsolated {
            AppUpdater.shared.updateIsReady(version: version, install: immediateInstallHandler)
        }
        return true
    }

    // Right before installing (both Restart to Update and installing on quit) and before relaunching: hand the sign-in
    // to the new version so macOS doesn't ask for the Keychain password after the update.
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        SessionManager.handOffForUpdate()
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        SessionManager.handOffForUpdate()
    }
}

enum AppVersion {
    /// "0.2.0" from Info.plist (scripts/make-app.sh), or "dev" for `swift run` / dev.sh builds.
    static let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
}
