import SwiftUI
import AppKit
import UserNotifications
import CoreGraphics

// MARK: - Permissions (chapter "Permissions: asked clearly, at the right moment", choice permissions-check: A)
//
// The core permissions Steerify — and the Claude sessions running in its terminals, which macOS charges to Steerify —
// need on this Mac. Their status is read live. A sheet (with a pixel harbour that lights a flag per permission) opens
// at first start, after an update and after a new app identity, only when one is missing. Later never blocks anything.
// Settings › Permissions lists the same rows.

enum Permission: String, CaseIterable, Identifiable {
    case notifications, screen, files
    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifications: return "Notifications"
        case .screen: return "Screen Recording"
        case .files: return "Files: Desktop, Documents, Downloads"
        }
    }
    var why: String {
        switch self {
        case .notifications: return "When Claude finishes or waits on you, even with Steerify behind other windows."
        case .screen: return "Capture… in a request, and the screenshots your Claude sessions take to test their work."
        case .files: return "Your recent screenshots in ⌘N, and sessions working on files in those folders."
        }
    }
    var color: Color {
        switch self {
        case .notifications: return Brand.amber
        case .screen: return Brand.blue
        case .files: return Brand.green
        }
    }
    /// 10×10 pixel glyphs, drawn like PixelArt's icons.
    var glyph: [String] {
        switch self {
        case .notifications: return ["....##....", "...####...", "..######..", "..######..", "..######..", ".########.", ".########.", "##########", "..........", "....##...."]
        case .screen: return ["##########", "#........#", "#.##.....#", "#.##.....#", "#........#", "#....##..#", "#........#", "##########", "....##....", "..######.."]
        case .files: return ["..........", "####......", "#..#######", "#........#", "##########", "#........#", "#........#", "#........#", "##########", ".........."]
        }
    }
    var settingsURL: URL {
        switch self {
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        case .screen: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .files: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
        }
    }

    enum State: Equatable { case on, off, notAsked }

    static var isApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static let folders: [URL] = ["Desktop", "Documents", "Downloads"].map {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0, isDirectory: true)
    }
    /// Files can't be checked without macOS asking, so they count as "not asked" until Steerify asked once.
    static var filesAsked: Bool {
        get { Prefs.store.bool(forKey: "permFilesAsked") }
        set { Prefs.store.set(newValue, forKey: "permFilesAsked") }
    }

    /// The real status, now.
    func state() async -> State {
        switch self {
        case .notifications:
            guard Permission.isApp else { return .notAsked }   // a bare executable has no notification center (it would crash)
            let s = await UNUserNotificationCenter.current().notificationSettings()
            switch s.authorizationStatus {
            case .authorized, .provisional, .ephemeral: return .on
            case .notDetermined: return .notAsked
            default: return .off
            }
        case .screen:
            if CGPreflightScreenCaptureAccess() { return .on }
            return Prefs.store.bool(forKey: "permScreenAsked") ? .off : .notAsked
        case .files:
            guard Self.filesAsked else { return .notAsked }
            // Asked before: reading no longer prompts, it just fails when denied.
            let ok = Self.folders.allSatisfy { (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) != nil }
            return ok ? .on : .off
        }
    }

    /// Ask macOS (its own prompt), or open the right System Settings pane when it was already refused.
    func request() async {
        switch self {
        case .notifications:
            guard Permission.isApp else { return }
            if await state() == .off { NSWorkspace.shared.open(settingsURL); return }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        case .screen:
            if Prefs.store.bool(forKey: "permScreenAsked") { NSWorkspace.shared.open(settingsURL); return }
            Prefs.store.set(true, forKey: "permScreenAsked")
            _ = CGRequestScreenCaptureAccess()      // first time: macOS's prompt; it applies after Steerify restarts
        case .files:
            if Self.filesAsked, await state() == .off { NSWorkspace.shared.open(settingsURL); return }
            Self.filesAsked = true
            for f in Self.folders { _ = try? FileManager.default.contentsOfDirectory(atPath: f.path) }   // one prompt per folder
        }
    }
}

/// Live statuses for the views; refreshed on demand and whenever Steerify comes to the front
/// (people grant in System Settings, then come back).
@MainActor final class PermissionStore: ObservableObject {
    static let shared = PermissionStore()
    @Published private(set) var states: [Permission: Permission.State] = [:]
    private var observing = false

    var missing: [Permission] { Permission.allCases.filter { states[$0] != .on } }

    func refresh() async {
        var s: [Permission: Permission.State] = [:]
        for p in Permission.allCases { s[p] = await p.state() }
        states = s
    }

    func observe() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in await PermissionStore.shared.refresh() }
        }
    }
}

// MARK: - The start check

enum PermissionCheck {
    /// "<bundle id>|<version>": a new value = first start, an update, or a new identity (Steerify Dev).
    static var stamp: String {
        "\(Bundle.main.bundleIdentifier ?? "app")|\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")"
    }
    static let key = "permCheckStamp"
}

@MainActor
extension AppModel {
    /// Replaces the bare notification prompt at launch: once per first start / update / identity, and only when a
    /// core permission is missing, show the sheet. `--permissions` forces it (test hook).
    func startPermissionCheck() {
        let a = CommandLine.arguments
        let forced = a.contains("--permissions")
        if let i = a.firstIndex(of: "--permissions-shot"), i + 1 < a.count {   // render the sheet to a PNG, then quit
            let out = a[i + 1], grant = a.contains("--permissions-granted")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { PermissionSheet.renderShot(to: out, granted: grant) }
            return
        }
        if let i = a.firstIndex(of: "--perm-peek-shot"), i + 1 < a.count {   // PermissionPeek.swift: bar + open view as PNGs
            let out = a[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { PermissionPeekView.renderShots(to: out) }
            return
        }
        guard !a.contains("--background") || forced else { return }
        PermissionStore.shared.observe()
        let due = Prefs.store.string(forKey: PermissionCheck.key) != PermissionCheck.stamp
        guard due || forced else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            Task { @MainActor in
                await PermissionStore.shared.refresh()
                Prefs.store.set(PermissionCheck.stamp, forKey: PermissionCheck.key)
                guard forced || !PermissionStore.shared.missing.isEmpty else { return }
                PermissionSheet.present()
            }
        }
    }
}

// MARK: - Views

/// A permission's pixel glyph.
struct PermissionGlyph: View {
    let p: Permission
    var size: CGFloat = 26
    var lit = true
    var body: some View {
        Canvas { ctx, sz in
            let inset = sz.width * 0.17, cell = (sz.width - 2 * inset) / 10
            for (y, row) in p.glyph.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    ctx.fill(Path(CGRect(x: inset + CGFloat(x) * cell, y: inset + CGFloat(y) * cell, width: cell * 0.92, height: cell * 0.92)),
                             with: .color(lit ? p.color : Brand.mute.opacity(0.6)))
                }
            }
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: size * 0.22).fill((lit ? p.color : Brand.mute).opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: size * 0.22).stroke((lit ? p.color : Brand.mute).opacity(0.35))))
    }
}

/// Setting up Steerify, in pixels: a boat at the pier, one signal flag per permission on its mast.
/// A missing permission's flag hangs grey and still; a granted one flies in its colour; all granted, the sail goes up.
struct PermissionHarbour: View {
    let states: [Permission: Permission.State]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { t in
            let phase = Int(t.date.timeIntervalSinceReferenceDate / 0.35) % 12
            Canvas { ctx, size in
                let px: CGFloat = 5
                let cols = Int(size.width / px), rows = Int(size.height / px)
                func dot(_ x: Int, _ y: Int, _ c: Color) {
                    guard x >= 0, y >= 0, x < cols, y < rows else { return }
                    ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px - 0.4, height: px - 0.4)), with: .color(c))
                }
                let all = Permission.allCases.allSatisfy { states[$0] == .on }
                // dawn sky: stars fade when everything is on
                for (x, y) in [(5, 3), (17, 6), (29, 2), (44, 5), (58, 3), (71, 6), (84, 2), (95, 5)] where x < cols {
                    dot(x, y, Brand.cream.opacity(all ? 0.15 : ((x + phase) % 3 == 0 ? 0.85 : 0.3)))
                }
                // sea
                let sea = rows - 7
                for r in 0..<3 {
                    for x in 0..<cols where (x + phase * (r + 1) / 2 + r * 3) % 7 < 4 { dot(x, sea + r * 2, (r == 0 ? Brand.blue : Brand.line2).opacity(r == 0 ? 0.5 : 0.8)) }
                }
                // pier
                let p0 = max(cols / 2 - 30, 2), plen = 14, top = sea - 1
                for x in p0..<(p0 + plen) { dot(x, top, Color(hex: 0x8a5a2b)); dot(x, top + 1, Color(hex: 0x5c3b1c)) }
                for x in stride(from: p0 + 1, to: p0 + plen, by: 5) { for y in (top + 2)...(top + 6) { dot(x, y, Color(hex: 0x4a2f16)) } }
                // boat (bobs)
                let bob = phase % 4 < 2 ? 0 : 1
                let bx = p0 + plen + 3, by = sea - 2 + bob
                for x in 0..<22 { dot(bx + x, by, Color(hex: 0x8a5a2b)) }
                for x in 1..<21 { dot(bx + x, by + 1, Color(hex: 0x5c3b1c)) }
                for x in 3..<19 { dot(bx + x, by + 2, Color(hex: 0x4a2f16)) }
                // mast
                let mx = bx + 9
                for y in (by - 13)..<by { dot(mx, y, Color(hex: 0x6b4a2a)) }
                // sail, raised when all are on
                if all {
                    for row in 0..<10 { for x in 1...(row / 2 + 1) { dot(mx + x, by - 12 + row, Brand.cream.opacity(0.9)) } }
                }
                // the signal line from the mast top down to the bow, the flags hang on it
                for k in 0..<11 { dot(mx - 1 - k, by - 13 + k, Brand.cream.opacity(k % 2 == 0 ? 0.45 : 0.2)) }
                // one flag per permission, on that line
                for (i, p) in Permission.allCases.enumerated() {
                    let on = states[p] == .on
                    let fx = mx - 3 - i * 3, fy = by - 12 + i * 3
                    let wave = on ? (phase + i) % 2 : 0
                    let c = on ? p.color : Brand.mute.opacity(0.55)
                    for dy in 0..<2 { for dx in 0..<3 { dot(fx - dx, fy + dy + (dx == 2 ? wave : 0), c) } }
                    dot(fx + 1, fy, Color(hex: 0x6b4a2a).opacity(0.6))
                }
                // lighthouse on the right: its lamp turns while something is missing
                let lx = min(cols / 2 + 26, cols - 6)
                for y in (sea - 10)..<sea { for x in 0..<3 { dot(lx + x, y, (y % 3 == 0) ? Brand.red.opacity(0.8) : Brand.cream.opacity(0.75)) } }
                dot(lx + 1, sea - 12, all ? Brand.green : Brand.amber)
                if !all {
                    let beam = phase % 6
                    for k in 1...(3 + beam) { dot(lx + 1 - k, sea - 12 + (k % 2 == 0 ? 0 : 0), Brand.amber.opacity(0.5 - Double(k) * 0.05)) }
                }
            }
        }
    }
}

/// One row: glyph, what it is for, its live status, one button.
struct PermissionRow: View {
    let p: Permission
    let state: Permission.State?
    var body: some View {
        HStack(spacing: 12) {
            PermissionGlyph(p: p, size: 30, lit: state == .on)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.ink)
                Text(p.why).font(.system(size: 11.5)).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            switch state {
            case .on:
                Text("✓ ON").font(Brand.label(9)).foregroundStyle(Brand.green)
            case .off:
                Button { NSWorkspace.shared.open(p.settingsURL) } label: { PermButtonLabel(text: "Open Settings", primary: false) }.buttonStyle(.plain)
                    .help("macOS said no before: switch Steerify on in System Settings")
            default:
                Button { Task { await p.request(); try? await Task.sleep(for: .seconds(1)); await PermissionStore.shared.refresh() } } label: {
                    PermButtonLabel(text: "Allow…", primary: true)
                }.buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Brand.panel2))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.line))
    }
}

/// Drawn buttons: the brand's look, and they render in pictures (system buttons don't).
struct PermButtonLabel: View {
    let text: String
    let primary: Bool
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(primary ? Color(hex: 0x1a1200) : Brand.cream)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(primary ? Brand.amber : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary ? Brand.amber : Brand.line2))
            .contentShape(Rectangle())
    }
}

/// The start sheet (choice permissions-check, A).
struct PermissionSheet: View {
    @ObservedObject var store = PermissionStore.shared
    var close: () -> Void = {}

    var body: some View {
        let missing = store.missing.count
        VStack(alignment: .leading, spacing: 12) {
            PermissionHarbour(states: store.states)
                .frame(height: 112)
                .background(RoundedRectangle(cornerRadius: 10).fill(Brand.bg))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(missing == 0 ? "Steerify is all set" : "Steerify needs \(missing) thing\(missing == 1 ? "" : "s") from macOS")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Brand.cream)
            Text("For Steerify and the Claude sessions inside it: macOS counts what a session does as Steerify. One click each; you can change them later in Settings › Permissions.")
                .font(.system(size: 12)).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
            ForEach(Permission.allCases) { p in PermissionRow(p: p, state: store.states[p]) }
            HStack {
                if store.states[.screen] == .off || Prefs.store.bool(forKey: "permScreenAsked") && store.states[.screen] != .on {
                    Text("Screen Recording applies after Steerify restarts.").font(.system(size: 11)).foregroundStyle(Brand.mute)
                }
                Spacer()
                if missing > 0 { Button("Later") { close() }.buttonStyle(.plain).foregroundStyle(Brand.mute).font(.system(size: 12)) }
                Button { close() } label: { PermButtonLabel(text: "Done", primary: missing == 0) }.buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(Brand.panel)
        .preferredColorScheme(.dark)
        .task { await store.refresh() }
    }

    private static var window: NSWindow?

    /// As a sheet on the main window (AppKit, so no view of the app has to know about it).
    @MainActor static func present() {
        guard window == nil, let host = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        panel.contentViewController = NSHostingController(rootView: PermissionSheet(close: {
            if let w = window { host.endSheet(w) }
            window = nil
        }))
        window = panel
        host.beginSheet(panel)
    }

    /// `--permissions-shot <file.png> [--permissions-granted]`: the sheet as a picture (2×), then quit.
    @MainActor static func renderShot(to path: String, granted: Bool) {
        Task { @MainActor in
            let states: [Permission: Permission.State] = granted ? Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, .on) })
                : [.notifications: .on, .screen: .notAsked, .files: .notAsked]
            let view = PermissionShotView(states: states)
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}

/// The sheet with fixed statuses (ImageRenderer draws one frame; no live store).
private struct PermissionShotView: View {
    let states: [Permission: Permission.State]
    var body: some View {
        let missing = Permission.allCases.filter { states[$0] != .on }.count
        VStack(alignment: .leading, spacing: 12) {
            PermissionHarbour(states: states).frame(height: 112)
                .background(RoundedRectangle(cornerRadius: 10).fill(Brand.bg)).clipShape(RoundedRectangle(cornerRadius: 10))
            Text(missing == 0 ? "Steerify is all set" : "Steerify needs \(missing) things from macOS")
                .font(.system(size: 17, weight: .bold)).foregroundStyle(Brand.cream)
            Text("For Steerify and the Claude sessions inside it: macOS counts what a session does as Steerify. One click each; you can change them later in Settings › Permissions.")
                .font(.system(size: 12)).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
            ForEach(Permission.allCases) { p in PermissionRow(p: p, state: states[p]) }
            HStack(spacing: 12) { Spacer(); if missing > 0 { Text("Later").foregroundStyle(Brand.mute).font(.system(size: 12)) }; PermButtonLabel(text: "Done", primary: missing == 0) }
        }
        .padding(18).frame(width: 760).background(Brand.panel).environment(\.colorScheme, .dark)
    }
}

/// Settings › Permissions: the same rows, live.
struct PermissionsSettings: View {
    @ObservedObject var store = PermissionStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Permission.allCases) { p in PermissionRow(p: p, state: store.states[p]) }
            Text("Claude sessions run in Steerify's terminals, so macOS charges what they do to Steerify (\(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Steerify") in System Settings).")
                .font(.system(size: 11)).foregroundStyle(Brand.mute)
        }
        .task { await store.refresh() }
    }
}
