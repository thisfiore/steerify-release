import SwiftUI
import AppKit

/// What the crew is up to, in one word and a mood.
enum CrewMood { case working, yourTurn, idle, quiet }

extension AppModel {
    var liveClaude: [TerminalSession] { sessions.filter { $0.kind == .claude && $0.running } }
    var workingCount: Int { liveClaude.filter { $0.status == .working }.count }
    var raisingHands: Int { liveClaude.filter { $0.status == .waiting }.count }
    /// Urgent things waiting on you across all projects.
    var waitingOnYou: Int { projects.reduce(0) { $0 + nextSteps($1).filter(\.urgent).count } }

    var mood: CrewMood {
        if raisingHands > 0 || waitingOnYou > 0 { return .yourTurn }
        if workingCount > 0 { return .working }
        if !liveClaude.isEmpty { return .idle }
        return .quiet
    }

    /// Last time any session did something (for "Idle for 2 h").
    var lastActivity: Date? { liveClaude.compactMap(\.statusAt).max() }
}

/// The pixel wheel as a small menu bar image (template: follows light / dark menu bars).
enum MenuBarIcon {
    @MainActor static let wheel: NSImage = {
        let r = ImageRenderer(content: PixelWheelMono(size: 16))
        r.scale = 2
        let img = r.nsImage ?? NSImage()
        img.isTemplate = true
        return img
    }()
}

/// One-colour pixel wheel (for template images).
struct PixelWheelMono: View {
    var size: CGFloat
    var body: some View {
        Canvas { ctx, sz in
            let cell = sz.width / 17, c = 8.0
            for y in 0..<17 { for x in 0..<17 {
                let dx = Double(x) - c, dy = Double(y) - c, r = hypot(dx, dy), a = atan2(dy, dx)
                let k = (a / (.pi / 4)).rounded(), da = abs(a - k * .pi / 4) * r
                let on = (r <= 2.2 && !((x == 7 && y == 7) || (x == 8 && y == 8) || (x == 7 && y == 9))) || (r >= 4.6 && r <= 5.9)
                    || (da < 0.55 && r <= 7.4) || (r > 7.4 && r <= 8.3 && da < 0.9)
                if on { ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell * 0.95, height: cell * 0.95)), with: .color(.black)) }
            } }
        }
        .frame(width: size, height: size)
    }
}

/// Menu bar label: wheel + a count when something waits on you, a dot while Claude works.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.wheel)
            switch model.mood {
            case .yourTurn: Text("\(model.waitingOnYou + model.raisingHands)").monospacedDigit()
            case .working: Text("●")
            default: EmptyView()
            }
        }
        .onAppear {
            AppModel.reopenWindow = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            MenuBarWatch.shared.start()   // macOS may keep the wheel off screen: the window then says so
            AppModel.openProjects = { openWindow(id: "projects"); NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

/// The menu bar window.
struct MenuBarPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menuBarShown", store: Prefs.store) private var shown = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            requestButton
            hero
            if !model.sessions.isEmpty { sessionsList }
            projectsList
            Divider().overlay(Brand.line)
            actions
        }
        .padding(14)
        .frame(width: 320)
        .background(Brand.bg)
        .preferredColorScheme(.dark)
        .tint(Brand.amber)
    }

    // MARK: Pieces (most important first: what to do, then what's going on)

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                PixelWheel(size: 15)
                Circle().fill(moodColor).frame(width: 7, height: 7)
                Text(moodLine).font(.system(size: 12.5, weight: .medium)).foregroundStyle(moodColor).lineLimit(1)
                Spacer(minLength: 0)
            }
            Text(countsLine).font(.system(size: 11)).foregroundStyle(Brand.mute).lineLimit(1).padding(.leading, 22)
        }
    }

    /// "5 to test · 1 choice · 1 rowing": what used to be two big tiles.
    private var countsLine: String {
        let toTest = model.projects.reduce(0) { n, p in n + model.board(for: p).ships.filter { [.toTest, .retest].contains(model.board(for: p).shipState($0)) }.count }
        let choices = model.projects.reduce(0) { n, p in n + model.board(for: p).decisions.filter { !model.board(for: p).isDecided($0) && !model.board(for: p).isParked($0) }.count }
        var parts = ["\(toTest) to test", "\(choices) choice\(choices == 1 ? "" : "s")"]
        if model.workingCount > 0 { parts.append("\(model.workingCount) rowing") }
        if model.raisingHands > 0 { parts.append("\(model.raisingHands) raising a hand") }
        return parts.joined(separator: " · ")
    }

    private var moodColor: Color {
        switch model.mood { case .working: Brand.blue; case .yourTurn: Brand.amber; case .idle: Brand.cream; case .quiet: Brand.mute }
    }

    private var moodLine: String {
        switch model.mood {
        case .working: return "We're working · \(model.workingCount) session\(model.workingCount == 1 ? "" : "s") rowing"
        case .yourTurn:
            let n = model.waitingOnYou + model.raisingHands
            return "Your turn · \(n) thing\(n == 1 ? "" : "s") wait\(n == 1 ? "s" : "") on you"
        case .idle: return "Idle \(Self.since(model.lastActivity)) · the crew is napping"
        case .quiet: return "All quiet. Suspiciously quiet."
        }
    }

    /// The one thing you can always do from here: file a request (also ⌃⌥N from any app).
    @ViewBuilder private var requestButton: some View {
        if !model.projects.isEmpty {
            Button { go { if model.project == nil, let p = model.projects.first { model.selectedProjectId = p.id }; model.requestOpen = true; model.requestPickProject = true } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("New request").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(GlobalHotKey.label).font(.system(size: 11, design: .monospaced)).opacity(0.75)
                }
                .foregroundStyle(Brand.amber)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(Brand.amberDim))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.amber.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(SteerButton())
            .help("A fix, a tweak, a feature, a question. \(GlobalHotKey.label) opens it from any app.")
        }
    }

    @ViewBuilder private var hero: some View {
        if let p = model.projects.first(where: { !model.nextSteps($0).filter(\.urgent).isEmpty }),
           let step = model.nextSteps(p).first(where: \.urgent) {
            Button { go { model.selectedProjectId = p.id; model.nextIndex = 0; model.jumpNext() } } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("NEXT FOR YOU · \(p.name.uppercased())").font(Brand.label(8.5)).tracking(0.8).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("⌘J").font(.system(size: 10, design: .monospaced))
                    }.foregroundStyle(Color(hex: 0x1a1200).opacity(0.65))
                    Text(step.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color(hex: 0x1a1200)).lineLimit(1)
                    Text(step.reason).font(.system(size: 11)).foregroundStyle(Color(hex: 0x1a1200).opacity(0.75)).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Brand.amber))
            }.buttonStyle(SteerButton())
        }
    }

    /// Sessions that need you or are working first; idle ones fill up to 4 rows.
    private var shownSessions: [TerminalSession] {
        func rank(_ s: TerminalSession) -> Int {
            if model.isWrapped(s) { return 4 }
            let st = s.kind == .claude ? s.status : (s.running ? .working : .ended)
            switch st { case .waiting: return 0; case .working: return 1; case .starting: return 2; case .idle: return 3; case .ended: return 4 }
        }
        return Array(model.sessions.enumerated().map { (rank($0.element), $0.offset, $0.element) }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2).prefix(4))
    }

    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("SESSIONS").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute)
                Spacer()
                if model.sessions.count > 4 {
                    Button("+\(model.sessions.count - 4) more") { go {} }.buttonStyle(SteerButton()).font(.system(size: 10.5)).foregroundStyle(Brand.mute)
                }
            }
            ForEach(shownSessions) { s in
                Button { go { model.selectedProjectId = s.projectId; model.selectedSession[s.projectId] = s.id } } label: {
                    MenuSessionRow(session: s, project: model.projects.first { $0.id == s.projectId }?.name ?? "", outlook: model.outlook(s), turn: model.yourTurn(s))
                }.buttonStyle(SteerButton())
            }
        }
    }

    private var projectsList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("PROJECTS").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute)
            ForEach(model.switcherProjects) { p in
                let n = model.nextSteps(p).filter(\.urgent).count
                Button { go { model.selectedProjectId = p.id } } label: {
                    HStack {
                        PixelAvatar(name: p.name, size: 16, projectId: p.id)
                        Text(p.name).font(.system(size: 12)).foregroundStyle(Brand.ink).lineLimit(1)
                        Spacer()
                        Text(n == 0 ? "all clear" : "\(n) for you").font(.system(size: 11)).foregroundStyle(n == 0 ? Brand.mute : Brand.amber)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel))
                }.buttonStyle(SteerButton())
            }
        }
    }

    /// One row of icons instead of a menu; the footer keeps the settings.
    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                iconAction("macwindow", "Open Steerify") { go {} }
                iconAction("magnifyingglass", "Search sessions and items", "⌘K") { go { model.paletteOpen = true } }
                Button { go { model.newSession(.claude) } } label: {
                    HStack(spacing: 6) { ClaudeSpark(size: 12); Text("Guided").font(.system(size: 12)); Text("⌘T").font(.system(size: 10, design: .monospaced)).opacity(0.6) }
                        .foregroundStyle(Brand.claude).frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel))
                }.buttonStyle(SteerButton()).help("Guided session with Claude (⌘T)")
            }
            HStack {
                Toggle("Show in the menu bar", isOn: $shown).toggleStyle(.checkbox).font(.system(size: 11)).foregroundStyle(Brand.mute)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(SteerButton()).font(.system(size: 11)).foregroundStyle(Brand.mute)
            }
        }
    }

    private func iconAction(_ icon: String, _ help: String, _ key: String? = nil, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                if let key { Text(key).font(.system(size: 10, design: .monospaced)).opacity(0.6) }
            }
            .foregroundStyle(Brand.cream).frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel))
        }.buttonStyle(SteerButton()).help(help + (key.map { " (\($0))" } ?? ""))
    }

    /// Bring the window up, then do the thing.
    private func go(_ then: @escaping () -> Void) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: then)
    }

    static func since(_ d: Date?) -> String {
        guard let d else { return "for a while" }
        let m = Int(-d.timeIntervalSinceNow / 60)
        return m < 1 ? "for a moment" : m < 60 ? "for \(m) min" : m < 1440 ? "for \(m / 60) h" : "for \(m / 1440) d"
    }
}

/// "rowing…", "raising a hand", "idle 14 min", "gone home".
struct MenuSessionRow: View {
    @ObservedObject var session: TerminalSession
    let project: String
    var outlook: SessionOutlook? = nil
    var turn: BoardTurn? = nil
    var body: some View {
        let st = session.kind == .claude ? session.status : (session.running ? .working : .ended)
        let (word, c): (String, Color) = {
            if turn != nil { return ("your turn", Brand.violet) }
            switch outlook {
            case .ask?: return ("asks you", Brand.amber)
            case .next?: return ("next step", Brand.cream)
            case let o? where o.isDone: return ("done", Brand.mute)
            default: break
            }
            switch st {
            case .working: return (session.kind == .claude ? "rowing…" : "shell", session.kind == .claude ? Brand.blue : Brand.cream.opacity(0.6))
            case .waiting: return ("raising a hand", Brand.amber)
            case .idle: return ("idle \(MenuBarPanel.since(session.statusAt).replacingOccurrences(of: "for ", with: ""))", Brand.cream)
            case .starting: return ("warming up", Brand.mute)
            case .ended: return ("gone home", Brand.mute)
            }
        }()
        HStack(spacing: 7) {
            ZStack(alignment: .bottomTrailing) { AutoIcon(title: session.item?.title ?? session.title, size: 14); Circle().fill(c).frame(width: 5, height: 5).offset(x: 2, y: 2) }
            Text(session.title).font(.system(size: 12)).foregroundStyle(Brand.ink).lineLimit(1)
            Text(project).font(.system(size: 10.5)).foregroundStyle(Brand.mute).lineLimit(1).layoutPriority(-1)
            Spacer(minLength: 4)
            Text(word).font(.system(size: 10.5)).foregroundStyle(c).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel))
    }
}
