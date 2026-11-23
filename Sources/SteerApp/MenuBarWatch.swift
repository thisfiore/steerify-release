import SwiftUI
import AppKit

/// Notices when macOS hides Steerify's menu bar wheel (macOS 26: System Settings › Menu Bar › Allow in the Menu Bar,
/// or a full menu bar). The status item still exists then, but its window is never on screen: occlusion says so.
@MainActor final class MenuBarWatch: ObservableObject {
    static let shared = MenuBarWatch()
    /// The wheel should be in the menu bar but macOS keeps it off screen.
    @Published private(set) var hidden = false
    /// "Not now": no banner until the next launch.
    @Published var dismissed = false
    private var observer: NSObjectProtocol?
    private var started = false

    /// System Settings › Menu Bar (macOS 26; Control Centre on older systems, where the same list lives).
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!

    /// A test copy: a `--background` run, a bare executable (`swift run`, `.build/…/SteerApp`, listed by macOS as
    /// "SteerApp"), the test build (`build/test/Steerify.app`) or any copy in a temp / scratch folder. They all share
    /// your app's name and bundle id, so macOS mixes their menu bar rows up with yours.
    static let isTestCopy: Bool = {
        if CommandLine.arguments.contains("--background") { return true }
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        guard path.hasSuffix(".app") else { return true }
        return path.contains("/build/test/") || ["/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"].contains { path.hasPrefix($0) }
    }()

    /// Only the app you use puts a wheel in the menu bar. Test copies never do, unless started with `--menubar` to
    /// test the wheel itself. Each copy that adds one gets its own row in System Settings › Menu Bar.
    static let allowed: Bool = CommandLine.arguments.contains("--menubar") || !isTestCopy

    /// A test copy takes itself out of macOS's app list as it starts (LaunchServices registers every copy that runs),
    /// so System Settings › Menu Bar and "Open with" only know your Steerify. `scripts/clean-test-copies.sh` does the
    /// same for copies left from before.
    static func forgetTestCopy() {
        guard isTestCopy, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        p.arguments = ["-u", Bundle.main.bundleURL.path]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        // After launch: macOS registers the running app as it checks in, which would undo an earlier call.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { try? p.run() }
    }

    /// `--fake-menubar-hidden`: the strip as it looks when macOS hides the wheel (screenshots of test copies).
    private init() { hidden = CommandLine.arguments.contains("--fake-menubar-hidden") }

    func start() {
        guard !started, Self.allowed else { return }
        started = true
        // The status item's window appears a moment after launch; check once it has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.attach() }
    }

    private func attach() {
        guard let w = NSApp.windows.first(where: { String(describing: type(of: $0)).contains("StatusBarWindow") }) else { return }
        update(w)
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main) { [weak self] n in
            guard let w = n.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.update(w) }
        }
    }

    private func update(_ w: NSWindow) {
        let shown = Prefs.store.object(forKey: "menuBarShown") as? Bool ?? true
        hidden = shown && !w.occlusionState.contains(.visible)
    }

    func openSettings() { NSWorkspace.shared.open(Self.settingsURL) }

    /// macOS 26 remembers a hidden status item per app ("NSStatusItem VisibleCC <name>" = 0 in the app's defaults) and
    /// creates it off screen from then on; switching the app on in Menu Bar settings does not clear it. Steerify's own
    /// setting (menuBarShown) decides: when it is on, every saved "hidden" goes back to visible before the item exists.
    static func clearHiddenFlag() {
        guard allowed,
              Prefs.store.object(forKey: "menuBarShown") as? Bool ?? true else { return }
        let d = UserDefaults.standard
        for (k, v) in d.dictionaryRepresentation() where k.hasPrefix("NSStatusItem Visible") && (v as? Bool) == false {
            d.set(true, forKey: k)
        }
    }

    /// "Show it": clears the flag and puts the wheel back now (out and in again, so AppKit makes a new, visible item).
    func showAgain() {
        Self.clearHiddenFlag()
        Prefs.store.set(false, forKey: "menuBarShown")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Prefs.store.set(true, forKey: "menuBarShown")
            self.hidden = false
            if let o = self.observer { NotificationCenter.default.removeObserver(o); self.observer = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.attach() }
        }
    }
}

/// A slim strip under the tabs while macOS hides the wheel.
struct MenuBarHiddenStrip: View {
    @ObservedObject var watch = MenuBarWatch.shared
    var body: some View {
        if watch.hidden && !watch.dismissed {
            HStack(spacing: 10) {
                PixelWheel(size: 14)
                Text("macOS is hiding the Steerify wheel in the menu bar")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Brand.cream)
                Spacer(minLength: 8)
                Button("Show it") { watch.showAgain() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Menu Bar settings") { watch.openSettings() }
                    .buttonStyle(.bordered).controlSize(.small)
                Button("Not now") { watch.dismissed = true }
                    .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Brand.mute)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Brand.amber.opacity(0.14))
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.amber.opacity(0.5)).frame(height: 1) }
        }
    }
}
