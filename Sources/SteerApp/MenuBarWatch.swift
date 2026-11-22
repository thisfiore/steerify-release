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

    /// `--fake-menubar-hidden`: the strip as it looks when macOS hides the wheel (screenshots of test copies).
    private init() { hidden = CommandLine.arguments.contains("--fake-menubar-hidden") }

    func start() {
        guard !started, !CommandLine.arguments.contains("--background") else { return }
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
                Text("Menu Bar › Steerify: switch it off and on")
                    .font(.system(size: 11.5)).foregroundStyle(Brand.mute).lineLimit(1)
                Spacer(minLength: 8)
                Button("Open Menu Bar settings") { watch.openSettings() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Not now") { watch.dismissed = true }
                    .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Brand.mute)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Brand.amber.opacity(0.14))
            .overlay(alignment: .bottom) { Rectangle().fill(Brand.amber.opacity(0.5)).frame(height: 1) }
        }
    }
}
