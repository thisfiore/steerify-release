import SwiftUI
import AppKit

/// User preferences, all remembered in UserDefaults.
enum Prefs {
    /// Test instances (`--background`) get their own settings, so they never change tabs or sizes in the user's window.
    /// STEERIFY_PREFS_SUITE gives a test run settings of its own (two sessions testing at once never switch each other's tab).
    static let store: UserDefaults = CommandLine.arguments.contains("--background")
        ? UserDefaults(suiteName: ProcessInfo.processInfo.environment["STEERIFY_PREFS_SUITE"] ?? "com.frenkfiore.steerify.tests")! : .standard
    static let fontPreset = "fontPreset"            // small | medium | large
    static let terminalFraction = "terminalFraction" // share of the width for the terminal (default 0.30)
    static let sidebarVisible = "sidebarVisible"
    static let lastProject = "lastProject"
    static let boardTab = "boardTab"
    static let testLayout = "testLayout"      // list | grid (To test tab)
    static let remoteControl = "remoteControl" // Claude sessions start with Claude Code Remote Control (open them in the Claude app)
    static var remoteControlOn: Bool { store.object(forKey: remoteControl) as? Bool ?? true }
    static let terminalOverlay = "terminalOverlay" // recap card + recent screenshots over Claude sessions (TerminalOverlay.swift)
    static let autoConsolidate = "autoConsolidate" // Roadmap counts down and applies sure proposals by itself (on by default)

    static let defaultTerminal = 0.30
    static let terminalRange = 0.18...0.55

    enum Size: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var scale: CGFloat { [.small: 0.9, .medium: 1.0, .large: 1.16][self]! }
        var terminal: CGFloat { [.small: 11.5, .medium: 12.5, .large: 14.5][self]! }
        var note: String { [.small: "More on screen", .medium: "Balanced", .large: "Easy on the eyes"][self]! }
    }
    static var size: Size { Size(rawValue: store.string(forKey: fontPreset) ?? "") ?? .medium }
}

/// Scaled point size for every fixed font in the app (the whole UI is rebuilt when the preset changes).
func S(_ points: CGFloat) -> CGFloat { (points * Prefs.size.scale).rounded(.toNearestOrEven) }

// MARK: - Settings window (⌘,)

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(Prefs.fontPreset, store: Prefs.store) private var preset: String = Prefs.Size.medium.rawValue
    @AppStorage(Prefs.terminalFraction, store: Prefs.store) private var frac: Double = Prefs.defaultTerminal
    @AppStorage(Prefs.sessionsFollowTab, store: Prefs.store) private var followTab = true
    @AppStorage(Prefs.defaultFlow, store: Prefs.store) private var defaultFlow = WorkFlow.main.rawValue
    @AppStorage(Prefs.remoteControl, store: Prefs.store) private var remoteControl = true
    @AppStorage(Prefs.terminalOverlay, store: Prefs.store) private var terminalOverlay = true
    @AppStorage(Prefs.autoConsolidate, store: Prefs.store) private var autoConsolidate = true

    /// The open page, remembered. Test hook: `--settings-pane <id>`.
    @AppStorage("settingsPane", store: Prefs.store) private var pane: Pane = {
        let a = CommandLine.arguments
        return a.firstIndex(of: "--settings-pane").flatMap { $0 + 1 < a.count ? Pane(rawValue: a[$0 + 1]) : nil } ?? .look
    }()

    enum Pane: String, CaseIterable, Identifiable {
        case you, look, behaviour, permissions, branches, iphone, shortcuts
        var id: String { rawValue }
        var title: String { ["you": "You", "look": "Look", "behaviour": "Behaviour", "permissions": "Permissions", "branches": "Branches", "iphone": "iPhone", "shortcuts": "Shortcuts"][rawValue]! }
        var icon: String { ["you": "users", "look": "palette", "behaviour": "gear", "permissions": "lock", "branches": "branch", "iphone": "phone", "shortcuts": "keys"][rawValue]! }
        var sub: String {
            ["you": "How technical you are. Steerify and Claude fit their screens and words to it.",
             "look": "Text size and how the window is split.",
             "behaviour": "How Steerify behaves for you. New options land here.",
             "permissions": "What Steerify and the Claude sessions inside it may do on this Mac.",
             "branches": "How sessions use git when a project doesn't say. Each project can change it in its Release setup.",
             "iphone": "Steer from the phone: pair it once, the board follows.",
             "shortcuts": "Everything on the keyboard."][rawValue]!
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Brand.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    page
                }
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(pane)
        }
        .frame(width: 820, height: 600)
        .background(Brand.bg)
        .preferredColorScheme(.dark)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SETTINGS").font(Brand.label(9)).tracking(1.2).foregroundStyle(Brand.mute)
                .padding(.horizontal, 10).padding(.bottom, 8)
            ForEach(Pane.allCases) { p in
                let on = pane == p
                Button { pane = p } label: {
                    HStack(spacing: 10) {
                        ArtIcon(name: p.icon, size: 26, tile: true)
                        Text(p.title).font(.system(size: 13, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Brand.ink : Brand.ink.opacity(0.75))
                        Spacer(minLength: 0)
                        if p == .permissions, missingPermissions > 0 {
                            Text("\(missingPermissions)").font(Brand.label(8)).foregroundStyle(Color(hex: 0x1a1200))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Brand.amber))
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? Brand.panel2 : .clear))
                    .overlay(alignment: .leading) {
                        if on { RoundedRectangle(cornerRadius: 1).fill(Brand.amber).frame(width: 3, height: 18).offset(x: -1) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SteerButton())
            }
            Spacer()
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                .font(Brand.label(8)).foregroundStyle(Brand.mute.opacity(0.7)).padding(.horizontal, 10)
        }
        .padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 14)
        .frame(width: 196)
        .background(Brand.panel)
    }

    @ObservedObject private var perms = PermissionStore.shared
    private var missingPermissions: Int { Permission.allCases.filter { perms.states[$0] != nil && perms.states[$0] != .on }.count }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ArtIcon(name: pane.icon, size: 44, tile: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(pane.title.uppercased()).font(Brand.label(14)).tracking(1.2).foregroundStyle(Brand.amber)
                Text(pane.sub).font(.system(size: 12)).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch pane {
        case .you:
            if let p = model.project { ProjectLevelRow(project: p).id(p.id) }
            LevelPicker(inSettings: true)
        case .look:
            group("TEXT SIZE", "Board, sidebar and terminal together.") {
                HStack(spacing: 12) { ForEach(Prefs.Size.allCases) { s in sizeCard(s) } }
            }
            group("WINDOW", "How much of the window the terminal takes. You can also drag the divider.") {
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        layoutDiagram
                        HStack {
                            Text("Terminal").font(.system(size: 12)).foregroundStyle(Brand.mute)
                            Slider(value: $frac, in: Prefs.terminalRange).tint(Brand.amber)
                            Text("\(Int(frac * 100))%").font(.system(size: 12).monospacedDigit()).frame(width: 40)
                            Button("Reset") { frac = Prefs.defaultTerminal }.disabled(abs(frac - Prefs.defaultTerminal) < 0.005)
                        }
                    }
                }
                card {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sessions").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Brand.ink)
                            Text("Tabs on top or a list beside the terminal · ⌘B").font(.system(size: 11)).foregroundStyle(Brand.mute)
                        }
                        Spacer()
                        Picker("", selection: Binding(get: { SessionLayout(rawValue: Prefs.store.string(forKey: "sessionLayout") ?? "") ?? .list },
                                                      set: { Prefs.store.set($0.rawValue, forKey: "sessionLayout") })) {
                            ForEach(SessionLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 220)
                    }
                }
            }
        case .behaviour:
            group("SESSIONS", nil) {
                rows {
                    pref("terminal", "Session list follows the tab", "Sessions on the open tab first, the others folded. The one you're in and the ones that need you always show.", $followTab)
                    divider
                    pref("phone", "Open sessions on your phone", "New Claude sessions start with Remote Control: tap one in Steerify for iPhone to continue it in the Claude app. Needs a claude.ai login (Pro, Max, Team, Enterprise).", $remoteControl)
                    divider
                    pref("terminal", "Recap and screenshots over the terminal", "Coming back to a session after 5 min shows where it is (a title and 2 lines, made on this Mac). Your last 3 screenshots float above the prompt: click one to paste it.", $terminalOverlay)
                }
            }
            group("TEST LINKS", nil) {
                rows { TestBrowserRow() }
            }
            group("ROADMAP", nil) {
                rows {
                    pref("map", "Auto-consolidate", "Opening Roadmap counts down 10 s, then moves forward the key results whose deliveries you approved or sent back. Off: one Consolidate all button instead.", $autoConsolidate)
                }
            }
        case .permissions:
            PermissionsSettings()
        case .branches:
            group("DEFAULT FOR NEW PROJECTS", nil) {
                FlowPicker(flow: Binding(get: { WorkFlow(rawValue: defaultFlow) ?? .main }, set: { defaultFlow = $0.rawValue }))
            }
            group("SESSIONS SIDE BY SIDE", nil) { FlowGuide() }
        case .iphone:
            card { PhonePairingView() }
            Text("The phone icon at the end of the tab bar opens the pairing code too (green while the phone is connected).")
                .font(.system(size: 11)).foregroundStyle(Brand.mute)
        case .shortcuts:
            shortcuts
        }
    }

    // MARK: Building blocks

    private func group<C: View>(_ title: String, _ sub: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Brand.label(9)).tracking(1).foregroundStyle(Brand.mute)
            if let sub { Text(sub).font(.system(size: 11.5)).foregroundStyle(Brand.mute.opacity(0.85)) }
            content()
        }
    }
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content().padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel2))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.line))
    }
    /// Grouped rows in one card, like System Settings.
    private func rows<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel2))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.line))
    }
    private var divider: some View { Rectangle().fill(Brand.line).frame(height: 1).padding(.leading, 52) }

    private func pref(_ icon: String, _ title: String, _ sub: String, _ on: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ArtIcon(name: icon, size: 28, tile: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.ink)
                Text(sub).font(.system(size: 11.5)).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: on).labelsHidden().toggleStyle(.switch).tint(Brand.amber)
        }
        .padding(12)
    }

    /// A preset rendered at its own size: a card title, a line of text and a terminal line.
    private func sizeCard(_ s: Prefs.Size) -> some View {
        let on = preset == s.rawValue
        return Button { preset = s.rawValue } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(s.title.uppercased()).font(Brand.label(10)).tracking(0.8).foregroundStyle(on ? Brand.amber : Brand.mute); Spacer()
                    if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.amber) } }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Retouch ops 1–4").font(.system(size: 14.5 * s.scale, weight: .semibold)).foregroundStyle(.white)
                    Text("Some errors are not removed from the background.").font(.system(size: 12.5 * s.scale)).foregroundStyle(Brand.ink.opacity(0.85)).lineLimit(2)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.panel))
                Text("⏺ Fixing the edge…").font(.system(size: s.terminal, design: .monospaced)).foregroundStyle(Brand.cream)
                    .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0x050607)))
                Text(s.note).font(.system(size: 11)).foregroundStyle(Brand.mute)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel2))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Brand.amber : Brand.line, lineWidth: on ? 2 : 1))
        }.buttonStyle(SteerButton())
    }

    private var layoutDiagram: some View {
        GeometryReader { g in
            HStack(spacing: 3) {

                block("BOARD", Brand.panel).frame(maxWidth: .infinity)
                block("TERMINAL \(Int(frac * 100))%", Color(hex: 0x050607), Brand.amber).frame(width: g.size.width * frac)
            }
        }
        .frame(height: 70)
        .animation(.easeOut(duration: 0.15), value: frac)
    }
    private func block(_ t: String, _ c: Color, _ fg: Color = Brand.mute) -> some View {
        RoundedRectangle(cornerRadius: 5).fill(c).overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.line))
            .overlay(Text(t).font(Brand.label(9)).foregroundStyle(fg))
    }

    private var shortcuts: some View {
        let groups: [(String, String, [([String], String)])] = [
            ("FIND", "search", [
                (["⌘K"], "Search sessions and items · ↩ item + its session · ⌘↩ start a session"),
                (["⌘J"], "Next thing that waits on you (board + its session)"),
            ]),
            ("BOARD", "grid", [
                (["⌘1", "…", "⌘5"], "To test · Choices · Requirements · Roadmap · Release"),
                (["⌘[", "⌘]"], "Previous / next board tab"),
                (["⌘R"], "Reload the board"),
                (["←", "→", "+", "−", "0", "N", "Esc"], "In a picture: move, zoom, fit, pin a note, close"),
            ]),
            ("SESSIONS", "terminal", [
                (["⌘T"], "New Claude session (guided start)"), (["⇧⌘T"], "New shell"),
                (["⇧⌘[", "⇧⌘]"], "Previous / next session"),
                (["⌘B"], "Sessions as tabs on top / list beside the terminal"),
                (["⌘W"], "Close the current session (never the app)"),
            ]),
            ("WINDOW", "cube", [
                (["⌥⌘1", "…", "⌥⌘9"], "Switch project"),
                (["⇧⌘W"], "Close the window (sessions keep running)"),
                (["⌥⌘R"], "Restart to load a new build (sessions come back)"),
                (["⌘,"], "Settings"),
            ]),
        ]
        return VStack(alignment: .leading, spacing: 18) {
            ForEach(groups, id: \.0) { g in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        ArtIcon(name: g.1, size: 13)
                        Text(g.0).font(Brand.label(9)).tracking(1).foregroundStyle(Brand.mute)
                    }
                    rows {
                        ForEach(Array(g.2.enumerated()), id: \.offset) { i, r in
                            if i > 0 { Rectangle().fill(Brand.line).frame(height: 1) }
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    ForEach(Array(r.0.enumerated()), id: \.offset) { _, k in
                                        if k == "…" { Text("…").font(.system(size: 11)).foregroundStyle(Brand.mute) } else { keycap(k) }
                                    }
                                }
                                .frame(width: 200, alignment: .leading)
                                Text(r.1).font(.system(size: 12)).foregroundStyle(Brand.ink.opacity(0.88))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private func keycap(_ k: String) -> some View {
        Text(k).font(.system(size: 11.5, weight: .medium, design: .monospaced)).foregroundStyle(Brand.cream)
            .padding(.horizontal, 6).frame(minWidth: 24, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0x0c0d10)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.line2))
            .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 5).fill(Brand.line2).frame(height: 2).padding(.horizontal, 1) }
    }
}

// MARK: - Board | terminal split with a remembered ratio

struct BoardTerminalSplit<Left: View, Right: View>: View {
    @AppStorage(Prefs.terminalFraction, store: Prefs.store) private var frac: Double = Prefs.defaultTerminal
    @State private var dragStart: Double?
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let termW = (w * frac).rounded()
            HStack(spacing: 0) {
                left.frame(width: max(w - termW - 5, 0))
                Rectangle().fill(Brand.line).frame(width: 1)
                    .padding(.horizontal, 2)
                    .frame(width: 5)
                    .contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { v in
                            let start = dragStart ?? frac
                            if dragStart == nil { dragStart = frac }
                            frac = min(max(start - Double(v.translation.width / w), Prefs.terminalRange.lowerBound), Prefs.terminalRange.upperBound)
                        }
                        .onEnded { _ in dragStart = nil })
                    .onTapGesture(count: 2) { frac = Prefs.defaultTerminal }
                    .help("Drag to resize · double-click: back to 30%")
                right.frame(width: termW)
            }
        }
    }
}
