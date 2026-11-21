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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                section("TEXT SIZE", "Board, sidebar and terminal together.") {
                    HStack(spacing: 12) {
                        ForEach(Prefs.Size.allCases) { s in sizeCard(s) }
                    }
                }
                section("LAYOUT", "How much of the window the terminal takes. You can also drag the divider.") {
                    VStack(alignment: .leading, spacing: 10) {
                        layoutDiagram
                        HStack {
                            Text("Terminal").font(.system(size: 12)).foregroundStyle(Brand.mute)
                            Slider(value: $frac, in: Prefs.terminalRange, step: 0.01).tint(Brand.amber).frame(maxWidth: 320)
                            Text("\(Int(frac * 100))%").font(.system(size: 12).monospacedDigit()).frame(width: 40)
                            Button("Reset to 30%") { frac = Prefs.defaultTerminal }.disabled(abs(frac - Prefs.defaultTerminal) < 0.005)
                        }
                        Picker("Sessions  ⌘B", selection: Binding(get: { SessionLayout(rawValue: Prefs.store.string(forKey: "sessionLayout") ?? "") ?? .tabs },
                                                                  set: { Prefs.store.set($0.rawValue, forKey: "sessionLayout") })) {
                            ForEach(SessionLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).frame(maxWidth: 320).font(.system(size: 12.5))
                    }
                }
                // Every new preference lands here, one toggle per line with what it does.
                section("PERSONALISATION", "How Steerify behaves for you. New options land here.") {
                    VStack(alignment: .leading, spacing: 10) {
                        pref("Session list follows the tab", "Sessions on the open tab first, the others folded. The one you're in and the ones that need you always show.", $followTab)
                    }
                }
                section("BRANCHES · DEFAULT FOR NEW PROJECTS", "How sessions use git when a project doesn't say. Each project can change it in its Release setup.") {
                    FlowPicker(flow: Binding(get: { WorkFlow(rawValue: defaultFlow) ?? .main }, set: { defaultFlow = $0.rawValue }))
                }
                section("SHORTCUTS", nil) { shortcuts }
            }
            .padding(24)
        }
        .frame(width: 640, height: 640)
        .background(Brand.bg)
        .preferredColorScheme(.dark)
    }

    private func pref(_ title: String, _ sub: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Brand.ink)
                Text(sub).font(.system(size: 11)).foregroundStyle(Brand.mute)
            }
        }
        .toggleStyle(.switch).tint(Brand.amber)
    }

    private func section<C: View>(_ title: String, _ sub: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Brand.label(10)).tracking(1).foregroundStyle(Brand.amber)
            if let sub { Text(sub).font(.system(size: 12)).foregroundStyle(Brand.mute) }
            content()
        }
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
        let rows: [(String, String)] = [
            ("⌘K", "Search sessions and items · ↩ item + its session · ⌘↩ start a session"),
            ("⌘J", "Next thing that waits on you (board + its session)"),
            ("⌘1 … ⌘5", "To test · Choices · Requirements · Roadmap · Release"),
            ("⌥⌘1 … ⌥⌘9", "Switch project"), ("⌘B", "Sessions as tabs on top / list beside the terminal"),
("⌘]  /  ⌘[", "Next / previous board tab"),
            ("⌘T", "New Claude session (guided start)"), ("⇧⌘T", "New shell"),
            ("⇧⌘]  /  ⇧⌘[", "Next / previous session"), ("⌘W", "Close the current session (never the app)"), ("⇧⌘W", "Close the window (sessions keep running)"),
            ("⌘R", "Reload the board"), ("⌥⌘R", "Restart to load a new build (sessions come back)"), ("⌘,", "Settings"),
            ("← →  + −  0  N  Esc", "In a picture preview: move, zoom, fit, pin a note, close"),
        ]
        return VStack(spacing: 0) {
            ForEach(rows, id: \.0) { r in
                HStack {
                    Text(r.0).font(.system(size: 12, design: .monospaced)).foregroundStyle(Brand.cream).frame(width: 190, alignment: .leading)
                    Text(r.1).font(.system(size: 12)).foregroundStyle(Brand.ink.opacity(0.85))
                    Spacer()
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
            }
        }
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
