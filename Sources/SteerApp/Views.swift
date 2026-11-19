import SwiftUI
import AppKit
import WebKit
import SwiftTerm

enum Theme {
    static let terminalBg = NSColor(srgbRed: 0.031, green: 0.035, blue: 0.043, alpha: 1)
    static let terminalFg = NSColor(srgbRed: 0.85, green: 0.86, blue: 0.88, alpha: 1)
    static let accent = NSColor(srgbRed: 1.0, green: 0.69, blue: 0.13, alpha: 1)    // signal amber
    static let amber = Color(nsColor: accent)
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var since = SinceYouLeft.shared
    @AppStorage(Prefs.boardTab, store: Prefs.store) private var boardTab: BoardTab = .test

    var body: some View {
        Group {
            if let p = model.project {
                // The tabs span the whole window: board and sessions below both follow them.
                VStack(spacing: 0) {
                    TabBar(board: model.board(for: p), tab: $boardTab).id(p.id).background(Brand.bg)
                    BoardTerminalSplit {
                        BoardScreen(board: model.board(for: p)).id(p.id)
                    } right: {
                        TerminalPane(project: p)
                    }
                }
                .navigationTitle("")
                .overlay {
                    if let pv = model.preview, pv.projectId == p.id {
                        PreviewOverlay(board: model.board(for: p), state: pv).id(pv.id)
                    }
                }
                .overlay { if model.paletteOpen { PaletteView() } }
                .overlay {
                    if let rp = model.requestProjectId.flatMap({ id in model.projects.first { $0.id == id } }) {
                        RequestSheet(project: rp)   // same sheet when you switch its project: the text stays
                    }
                }
                .overlay { if let b = since.brief, b.projectId == p.id { SinceYouLeftSheet(brief: b, project: p).id(b.id) } }
                .overlay(alignment: .bottom) { if let t = model.toast { ToastView(toast: t).padding(.bottom, 18).transition(.move(edge: .bottom).combined(with: .opacity)) } }
                .animation(.easeOut(duration: 0.2), value: model.toast)
            } else {
                VStack(spacing: 12) {
                    Text("No projects yet").font(.system(size: S(16), weight: .semibold)).foregroundStyle(Brand.ink)
                    Text("Pick your project's folder, or start an empty one. Steerify creates its board.")
                        .font(.system(size: S(12.5))).foregroundStyle(Brand.mute)
                    Button("Add project…") { model.addWorkspace() }.buttonStyle(.borderedProminent).tint(Brand.amber)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // "Since you left": on open, when you come back to the app, and when you switch to a project you left a while ago.
        .onAppear {
            let a = CommandLine.arguments
            let forced = a.firstIndex(of: "--since-hours").flatMap { $0 + 1 < a.count ? Double(a[$0 + 1]) : nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { since.check(model, force: forced.map { Date().addingTimeInterval(-$0 * 3600) }) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in SinceYouLeft.markSeen(model.selectedProjectId) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in since.check(model) }
        .onChange(of: model.selectedProjectId) { old, _ in
            SinceYouLeft.markSeen(old)
            if since.brief != nil { since.brief = nil }
            DispatchQueue.main.async { since.check(model) }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { ProjectSwitcher() }
            ToolbarItem(placement: .principal) { Wordmark() }
            ToolbarItem(placement: .primaryAction) { HStack(spacing: 8) { NextUp(); NewRequestButton() }.fixedSize() }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.updateReady {
                    Button { model.restartForUpdate() } label: {
                        Label("Restart to update", systemImage: "arrow.triangle.2.circlepath").labelStyle(.titleAndIcon)
                            .foregroundStyle(Color(hex: 0x1a1200)).font(.system(size: S(11.5), weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Brand.amber))
                    }
                    .buttonStyle(SteerButton())
                    .help("A new build of Steerify is ready (⌥⌘R). Your sessions come back: Claude conversations resume with their history.")
                }
                Button { model.reloadBoard() } label: { Image(systemName: "arrow.clockwise") }.help("Reload board (⌘R)")
                if (model.project?.port ?? 0) > 0 {
                    Button { model.openWebBoard() } label: { Image(systemName: "safari") }.help("Open the web board in the browser")
                }
                NewSessionMenu()
            }
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if let p = model.project { ProjectCard(project: p).padding(.bottom, 4) }
                header("PROJECTS")
                ForEach(Array(model.projects.enumerated()), id: \.element.id) { i, p in
                    row(selected: model.selectedProjectId == p.id, action: { model.selectedProjectId = p.id }) {
                        Text(p.name)
                        Spacer()
                        let n = model.sessions(of: p.id).count
                        if n > 0 { Text("\(n)").font(.caption.monospacedDigit()).foregroundStyle(Brand.mute) }
                        if i < 9 { Text("⌥⌘\(i + 1)").font(.caption2).foregroundStyle(Brand.mute.opacity(0.7)) }
                    }
                }
                if let p = model.project {
                    header("SESSIONS")
                    ForEach(model.sessions(of: p.id)) { s in
                        let sel = model.current(of: p.id)?.id == s.id
                        row(selected: sel, action: { model.selectedSession[p.id] = s.id }) { SessionRow(session: s, selected: sel) }
                    }
                    if model.sessions(of: p.id).isEmpty {
                        Text("None yet · ⌘T").font(.callout).foregroundStyle(Brand.mute.opacity(0.7)).padding(.horizontal, 10)
                    }
                    header("REPOS")
                    ForEach(p.repos) { r in
                        Text(r.exists ? r.name : "\(r.name) · missing")
                            .foregroundStyle(r.exists ? Brand.ink.opacity(0.75) : Brand.mute.opacity(0.6))
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("New Claude session here") { model.newSession(.claude, repo: r) }
                                Button("New shell here") { model.newSession(.shell, repo: r) }
                            }
                            .onTapGesture(count: 2) { model.newSession(.claude, repo: r) }
                            .clickable()
                            .help("Double-click: new Claude session here · right-click for more")
                    }
                }
            }
            .padding(8)
        }
        .background(Color(hex: 0x0b0c0f))
    }

    private func header(_ t: String) -> some View {
        Text(t).font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute).padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 3)
    }

    private func row<C: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder _ content: () -> C) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { content() }
                .font(.system(size: S(13)))
                .foregroundStyle(selected ? Color(hex: 0xffd27a) : Brand.ink)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Brand.amberDim : .clear))
                .contentShape(Rectangle())
        }.buttonStyle(SteerButton())
    }
}

struct SessionRow: View {
    @ObservedObject var session: TerminalSession
    var selected: Bool
    private var dot: SwiftUI.Color {
        guard session.running else { return .gray }
        switch session.status { case .working: return Brand.green; case .waiting: return Brand.amber; case .idle: return Brand.cream.opacity(0.7); default: return Brand.mute }
    }
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).lineLimit(1).fontWeight(selected ? .semibold : .regular)
                Text(session.kind == .claude ? session.status.label + (session.activity.map { " · " + $0 } ?? "") : "shell")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct NewSessionMenu: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Menu {
            if let p = model.project {
                Section("Claude Code") {
                    ForEach(p.repos) { r in Button(r.name) { model.newSession(.claude, repo: r) } }
                }
                Section("Shell") {
                    ForEach(p.repos) { r in Button(r.name) { model.newSession(.shell, repo: r) } }
                }
            }
        } label: { Label("New session", systemImage: "plus") }
        .help("New Claude Code session (⌘T)")
    }
}

// MARK: Board

struct BoardPane: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    var body: some View {
        ZStack {
            Color(nsColor: NSColor(srgbRed: 0.04, green: 0.04, blue: 0.04, alpha: 1))
            WebHost(webView: model.webView(for: project))
            switch model.boardState[project.id] {
            case .starting: ProgressView().controlSize(.small)
            case .missing:
                Text("Board not reachable on :\(project.port). No server.mjs in \(project.boardDir)?")
                    .foregroundStyle(.secondary).padding()
            default: EmptyView()
            }
        }
    }
}

/// Hosts a cached WKWebView. Swapping the subview (instead of recreating) keeps each project's board alive.
struct WebHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> NSView { let v = NSView(); attach(to: v); return v }
    func updateNSView(_ v: NSView, context: Context) { if webView.superview !== v { attach(to: v) } }
    private func attach(to v: NSView) {
        v.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = v.bounds
        webView.autoresizingMask = [.width, .height]
        v.addSubview(webView)
    }
}

// MARK: Terminals

struct TerminalPane: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("sessionLayout", store: Prefs.store) private var layout: SessionLayout = .tabs
    @AppStorage(Prefs.boardTab, store: Prefs.store) private var tab: BoardTab = .test
    @AppStorage(Prefs.sessionsFollowTab, store: Prefs.store) private var follow = true
    @State private var othersOpen = false
    let project: Project

    var body: some View {
        let all = model.orderedSessions(of: project.id)
        let split = model.sessionsFor(tab: tab, projectId: project.id, follow: follow)
        let list = split.shown + (othersOpen ? split.folded : [])
        let wrapped = Set(model.wrappedSessions(of: project.id).map(\.id))
        let current = model.current(of: project.id)
        let _ = boardTick
        Group {
            if all.isEmpty {
                EmptyTerminals(project: project)
            } else if layout == .tabs {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(list) { s in
                                    SessionChip2(session: s, selected: current?.id == s.id, wrapped: wrapped.contains(s.id),
                                                 stage: follow ? stageTag(s) : model.stage(of: s),
                                                 select: { model.selectedSession[project.id] = s.id }, close: { model.close(s) })
                                }
                            }.padding(.vertical, 6)
                            .animation(.easeInOut(duration: 0.25), value: list.map(\.id))
                        }
                        CloseWrappedButton(count: wrapped.count) { model.closeWrapped(projectId: project.id) }
                        if !split.folded.isEmpty { FoldedSessionsButton(count: split.folded.count, open: $othersOpen) }
                        FollowTabToggle()
                        NewSessionButton(project: project)
                        layoutToggle
                    }
                    .padding(.horizontal, 8)
                    .background(Color(hex: 0x0b0c0f))
                    .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
                    terminal(current)
                }
            } else {
                HStack(spacing: 0) {
                    terminal(current)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(follow ? tab.short : "SESSIONS").font(Brand.label(9)).tracking(0.8).foregroundStyle(follow ? tab.color : Brand.mute)
                            Spacer()
                            NewSessionButton(project: project)
                            layoutToggle
                        }.padding(.bottom, 2)
                        FollowTabToggle().padding(.bottom, 2)
                        CloseWrappedButton(count: wrapped.count) { model.closeWrapped(projectId: project.id) }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(split.shown) { s in
                                    SessionChip2(session: s, selected: current?.id == s.id, wrapped: wrapped.contains(s.id), vertical: true,
                                                 stage: follow ? stageTag(s) : model.stage(of: s),
                                                 select: { model.selectedSession[project.id] = s.id }, close: { model.close(s) })
                                }
                                if follow && split.shown.isEmpty {
                                    Text("No sessions on \(tab.title.capitalized)").font(.system(size: S(11))).foregroundStyle(Brand.mute.opacity(0.7)).padding(.horizontal, 6)
                                }
                                if !split.folded.isEmpty {
                                    FoldedSessionsButton(count: split.folded.count, open: $othersOpen).padding(.top, 8)
                                    if othersOpen {
                                        ForEach(split.folded) { s in
                                            SessionChip2(session: s, selected: current?.id == s.id, wrapped: wrapped.contains(s.id), vertical: true,
                                                         stage: model.stage(of: s),
                                                         select: { model.selectedSession[project.id] = s.id }, close: { model.close(s) })
                                            .opacity(0.6)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .frame(width: S(190))
                    .background(Color(hex: 0x0b0c0f))
                    .overlay(alignment: .leading) { Rectangle().fill(Brand.line).frame(width: 1) }
                }
            }
        }
        .background(Color(nsColor: Theme.terminalBg))
        .onReceive(NotificationCenter.default.publisher(for: .steerifyBoardReloaded)) { _ in boardTick += 1 }
    }

    /// Board reloads (a delivery went live, a key result done) re-rank the tabs.
    @State private var boardTick = 0

    /// The stage tag, only when the session stands on another tab than the open one.
    private func stageTag(_ s: TerminalSession) -> BoardTab? {
        let st = model.stage(of: s)
        return st == tab ? nil : st
    }

    @ViewBuilder private func terminal(_ s: TerminalSession?) -> some View {
        if let s { TerminalHost(session: s).id(s.id) } else { EmptyTerminals(project: project) }
    }

    private var layoutToggle: some View {
        Button { layout = layout == .tabs ? .list : .tabs } label: {
            Image(systemName: layout == .tabs ? "sidebar.right" : "rectangle.topthird.inset.filled").font(.system(size: S(11)))
        }
        .buttonStyle(SteerButton()).foregroundStyle(Brand.mute)
        .help(layout == .tabs ? "Sessions as a list beside the terminal (⌘B)" : "Sessions as tabs on top (⌘B)")
    }
}

struct TabChip: View {
    @ObservedObject var session: TerminalSession
    var selected: Bool
    var select: () -> Void
    var close: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(!session.running ? Color.gray : session.status == .waiting ? Brand.amber : session.status == .working ? Brand.green : Brand.cream.opacity(0.7)).frame(width: 6, height: 6)
            Text(session.title).lineLimit(1).font(.system(size: S(11.5)))
            Button(action: close) { Image(systemName: "xmark").font(.system(size: S(8), weight: .bold)) }
                .buttonStyle(SteerButton()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color(nsColor: Theme.terminalBg) : .clear))
        .foregroundStyle(selected ? .primary : .secondary)
        .clickable(tint: !selected)
        .onTapGesture(perform: select)
    }
}

/// The terminal pane at rest: a little pixel terminal typing to itself, then the best ways to start.
struct EmptyTerminals: View {
    @EnvironmentObject var model: AppModel
    let project: Project

    var body: some View {
        let top = model.nextSteps(project).first { $0.urgent && !$0.ref.hasPrefix("session:") }
        let recent = recentConversations
        ScrollView {
            VStack(spacing: 18) {
                PixelTerminal().frame(width: 220, height: 150).padding(.top, 30)
                VStack(spacing: 4) {
                    Text("NO SESSIONS YET").font(Brand.label(11)).tracking(1.2).foregroundStyle(Brand.cream)
                    Text("The crew is resting. Give them something to row toward.").font(.system(size: S(12))).italic().foregroundStyle(Brand.mute)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if !model.whereYouLeftOff(project).isEmpty {
                        ResumeChapters(project: project, compact: true)
                    } else if let top {
                        section("WHERE IT MATTERS")
                        Button { startTop(top) } label: {
                            HStack(spacing: 10) {
                                ClaudeSpark(size: S(16), color: .white)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(top.reason.uppercased()).font(Brand.label(8.5)).foregroundStyle(Color.white.opacity(0.85))
                                    Text(top.title).font(.system(size: S(13), weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                                }
                                Spacer(minLength: 6)
                                Image(systemName: "arrow.right").font(.system(size: S(12), weight: .bold)).foregroundStyle(.white)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.claude))
                        }
                        .buttonStyle(SteerButton())
                        .help("Starts a Claude session on it, in the right repo, already briefed")
                    }

                    if !recent.isEmpty {
                        section("PICK UP A CONVERSATION")
                        ForEach(recent, id: \.claudeSession) { l in
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.uturn.backward").font(.system(size: S(10), weight: .bold)).foregroundStyle(Brand.cream)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(l.title ?? l.item).font(.system(size: S(12.5))).foregroundStyle(Brand.ink).lineLimit(1)
                                    Text("\(l.intent) · \(l.repo) · \(SessionChip.ago(l.started))").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                                    SessionSummaryLine(claudeId: l.claudeSession, size: 11, lines: 3)
                                }
                                Spacer()
                                ClaudeButton(title: "Resume") { model.resume(l, projectId: project.id) }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel))
                        }
                    }

                    section("OR START FRESH")
                    HStack(spacing: 8) {
                        ClaudeButton(title: "Guided session", prominent: top == nil) { model.newSession(.claude) }
                            .help("Claude lists what waits on you and asks where to start (⌘T)")
                        repoMenu(title: "Claude in…", kind: .claude)
                        repoMenu(title: "Shell in…", kind: .shell)
                    }
                }
                .frame(maxWidth: 420)

                HStack(spacing: 14) {
                    hint("⌘T", "guided"); hint("⇧⌘T", "shell"); hint("⌘K", "search"); hint("⌘J", "next")
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
    }

    private var recentConversations: [SessionLink] {
        var seen = Set<String>()
        return model.board(for: project).links.reversed()
            .filter { seen.insert($0.claudeSession).inserted && SessionLinks.resumable($0.claudeSession) }
            .prefix(3).map { $0 }
    }

    private func startTop(_ step: NextStep) {
        if let n = model.nudges.first(where: { $0.projectId == project.id && $0.ref == step.ref }) { model.takeNudge(n); return }
        guard var item = ItemRef(ref: step.ref) else { return }
        item = BoardFiles.resolve(item, in: project)
        model.focusItem(projectId: project.id, ref: step.ref)
        model.start(projectId: project.id, item: item, intent: model.naturalIntent(item, in: project))
    }

    private func section(_ t: String) -> some View {
        Text(t).font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute).padding(.top, 4)
    }

    private func repoMenu(title: String, kind: SessionKind) -> some View {
        Menu {
            ForEach(project.repos.filter(\.exists)) { r in Button(r.name) { model.newSession(kind, repo: r) } }
        } label: {
            HStack(spacing: 5) {
                PixelIcon(name: "term", size: 9)
                Text(title).font(.system(size: S(11.5), weight: .semibold))
            }
        }
        .menuStyle(.borderlessButton).fixedSize()
        .foregroundStyle(Brand.cream)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.line2))
        .pointerStyle(.link)
    }

    private func hint(_ k: String, _ t: String) -> some View {
        HStack(spacing: 4) {
            Text(k).font(.system(size: S(10.5), weight: .semibold, design: .monospaced)).foregroundStyle(Brand.cream)
            Text(t).font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
        }
    }
}

/// A small pixel CRT: lines type themselves, the cursor blinks, the Claude spark waits on the screen.
struct PixelTerminal: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.18)) { t in
            let tick = reduceMotion ? 40 : Int(t.date.timeIntervalSinceReferenceDate / 0.18) % 64
            Canvas { ctx, size in
                let px = floor(min(size.width / 55, size.height / 37))
                let ox = (size.width - 55 * px) / 2, oy = (size.height - 37 * px) / 2
                func dot(_ x: Int, _ y: Int, _ c: SwiftUI.Color) { ctx.fill(Path(CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px - 0.5, height: px - 0.5)), with: .color(c)) }
                // case + stand
                for x in 0..<55 { dot(x, 0, Brand.cream.opacity(0.85)); dot(x, 30, Brand.cream.opacity(0.85)) }
                for y in 0..<31 { dot(0, y, Brand.cream.opacity(0.85)); dot(54, y, Brand.cream.opacity(0.85)) }
                for x in 22..<33 { dot(x, 31, Brand.mute); dot(x, 32, Brand.mute) }
                for x in 16..<39 { dot(x, 33, Brand.cream.opacity(0.6)) }
                // screen
                for y in 2..<29 { for x in 2..<53 { dot(x, y, Color(hex: 0x050607)) } }
                // prompt + typed lines (bars of pixels), growing with time
                let lines: [(Int, SwiftUI.Color)] = [(18, Brand.cream.opacity(0.75)), (26, Brand.mute), (14, Brand.green.opacity(0.8)), (22, Brand.mute)]
                var budget = tick
                for (i, l) in lines.enumerated() {
                    let y = 5 + i * 4
                    dot(4, y, Brand.amber); dot(5, y, Brand.amber)            // ›
                    let n = min(l.0, max(0, budget)); budget -= l.0 + 3
                    for x in 0..<n where x % 5 != 4 { dot(8 + x, y, l.1) }
                    if n < l.0 && n >= 0 && budget < 0 {
                        if (tick / 2) % 2 == 0 { dot(8 + n, y, Brand.amber); dot(8 + n, y - 1, Brand.amber) }   // cursor
                        break
                    }
                }
                // Claude spark on the screen (pixel version), gently pulsing
                let a = 0.55 + 0.45 * (reduceMotion ? 1 : abs(sin(Double(tick) / 6)))
                let cx = 45, cy = 21
                for d in 0...3 { dot(cx + d, cy, Brand.claude.opacity(a)); dot(cx - d, cy, Brand.claude.opacity(a)); dot(cx, cy + d, Brand.claude.opacity(a)); dot(cx, cy - d, Brand.claude.opacity(a)) }
                for d in 1...2 { dot(cx + d, cy + d, Brand.claude.opacity(a)); dot(cx - d, cy - d, Brand.claude.opacity(a)); dot(cx + d, cy - d, Brand.claude.opacity(a)); dot(cx - d, cy + d, Brand.claude.opacity(a)) }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Hosts the session's long-lived terminal view and gives it keyboard focus.
struct TerminalHost: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    func makeNSView(context: Context) -> NSView { let v = NSView(); attach(to: v); return v }
    func updateNSView(_ v: NSView, context: Context) { if session.view.superview !== v { attach(to: v) } }
    private func attach(to v: NSView) {
        v.subviews.forEach { $0.removeFromSuperview() }
        let t = session.view
        t.removeFromSuperview()
        t.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(t)
        NSLayoutConstraint.activate([
            t.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 8),
            t.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
            t.topAnchor.constraint(equalTo: v.topAnchor, constant: 6),
            t.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4),
        ])
        DispatchQueue.main.async { t.window?.makeFirstResponder(t) }
    }
}


/// "Delivered v2 · Soul 2 bench  [Open]" — messages from Claude sessions (Steerify MCP) and the app.
struct ToastView: View {
    @EnvironmentObject var model: AppModel
    let toast: AppModel.Toast
    var body: some View {
        HStack(spacing: 10) {
            ClaudeSpark(size: S(13))
            Text(toast.message).font(.system(size: S(12.5), weight: .medium)).foregroundStyle(Brand.ink).lineLimit(2)
            if let undo = toast.undo {
                Button("Undo") { undo(); model.toast = nil }
                    .buttonStyle(SteerButton()).font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.amber)
            }
            if let ref = toast.ref, let pid = toast.projectId {
                Button("Open") { model.openCombo(projectId: pid, ref: ref, startNew: false); model.toast = nil }
                    .buttonStyle(SteerButton()).font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.amber)
            }
            Button { model.toast = nil } label: { Image(systemName: "xmark").font(.system(size: S(9), weight: .bold)) }
                .buttonStyle(SteerButton()).foregroundStyle(Brand.mute)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Capsule().fill(Color(hex: 0x1b1e25)))
        .overlay(Capsule().stroke(Brand.claude.opacity(0.5)))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }
}


/// Top-left: wheel + the current project (pixel avatar, name ▾). Opens the project card and the switcher.
struct ProjectSwitcher: View {
    @EnvironmentObject var model: AppModel
    @State private var open = false
    var body: some View {
        HStack(spacing: 10) {
            if let p = model.project {
                Button { open.toggle() } label: {
                    HStack(spacing: 7) {
                        PixelAvatar(name: p.name, size: S(20))
                        Text(p.name).font(.system(size: S(13), weight: .semibold)).foregroundStyle(Brand.ink)
                            .lineLimit(1).fixedSize()   // the project name is always shown in full
                        let road = model.board(for: p).roadmap
                        let frac = road.isEmpty ? 0 : Double(road.filter { $0.status == "done" }.count) / Double(road.count)
                        PixelProgress(fraction: frac, blocks: 10, working: road.contains { $0.status == "wip" })
                            .frame(width: S(64)).scaleEffect(y: 0.8)
                        Text("\(Int(frac * 100))%").font(.system(size: S(11), weight: .bold).monospacedDigit()).foregroundStyle(Brand.green)
                        Image(systemName: "chevron.down").font(.system(size: S(9), weight: .bold)).foregroundStyle(Brand.mute)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(open ? 0.08 : 0.03)))
                }
                .buttonStyle(SteerButton())
                .help("Switch project (⌥⌘1…9)")
                .popover(isPresented: $open, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        ProjectCard(project: p)
                        Text("PROJECTS").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute)
                        ForEach(Array(model.projects.enumerated()), id: \.element.id) { i, q in
                            let n = model.nextSteps(q).filter(\.urgent).count
                            Button { model.selectedProjectId = q.id; open = false } label: {
                                HStack(spacing: 8) {
                                    PixelAvatar(name: q.name, size: S(22))
                                    Text(q.name).font(.system(size: S(12.5), weight: q.id == p.id ? .semibold : .regular)).foregroundStyle(Brand.ink)
                                    Spacer()
                                    if n > 0 { Text("\(n)").font(.system(size: S(10), weight: .bold)).foregroundStyle(Color(hex: 0x1a1200)).padding(.horizontal, 5).background(Capsule().fill(Brand.amber)) }
                                    if i < 9 { Text("⌥⌘\(i + 1)").font(.system(size: S(10))).foregroundStyle(Brand.mute) }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(q.id == p.id ? Brand.amberDim : .clear))
                                .contentShape(Rectangle())
                            }.buttonStyle(SteerButton())
                        }
                        Divider().overlay(Brand.line)
                        Button("Add project…") { open = false; model.addWorkspace() }.buttonStyle(SteerButton()).font(.system(size: S(12))).foregroundStyle(Brand.mute)
                    }
                    .padding(14).frame(width: S(300))
                    .background(Brand.bg)
                    .preferredColorScheme(.dark)
                }
            }
        }
    }
}
