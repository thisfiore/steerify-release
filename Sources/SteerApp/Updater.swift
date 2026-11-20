import AppKit
import Sparkle

/// Updates for people who installed Steerify (choice update-experience, option A): Sparkle checks the appcast
/// on the public repo's latest release, downloads a new version in the background, and the top bar shows
/// "Restart to update". Quitting installs it too. Dev builds (build/Steerify.app in the repo) keep their own
/// "rebuilt on disk" restart and never talk to Sparkle.
/// STEERIFY_FEED_URL overrides the feed (testing against a local appcast).
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    private var controller: SPUStandardUpdaterController?
    private var installNow: (() -> Void)?
    weak var model: AppModel?
    /// The version waiting to be installed ("0.5.2"), once it is downloaded.
    private(set) var readyVersion: String?

    var enabled: Bool { controller != nil }

    static var isDevBuild: Bool {
        Bundle.main.bundleURL.path.hasSuffix("/build/Steerify.app") && ProcessInfo.processInfo.environment["STEERIFY_FEED_URL"] == nil
    }

    func start(_ model: AppModel) {
        self.model = model
        guard controller == nil, !CommandLine.arguments.contains("--background"), !Self.isDevBuild,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    /// Install the downloaded version now (Sparkle quits, replaces the app and reopens it). False when none is ready.
    func installIfReady() -> Bool {
        guard let go = installNow else { return false }
        go()
        return true
    }

    func fake(_ version: String, _ model: AppModel) {
        readyVersion = version
        DispatchQueue.main.async { model.updateReady = true }
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["STEERIFY_FEED_URL"]
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock: @escaping () -> Void) -> Bool {
        let v = item.displayVersionString
        MainActor.assumeIsolated {
            installNow = immediateInstallationBlock
            readyVersion = v
            model?.updateReady = true
        }
        // Test hook: install as soon as it is downloaded (the same path as clicking "Restart to update").
        if CommandLine.arguments.contains("--install-when-ready") {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.model?.restartForUpdate() } }
        }
        return true   // we show our own "Restart to update"; otherwise it installs on quit
    }
}
