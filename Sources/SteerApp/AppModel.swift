import AppKit
import CoreServices
import WebKit

/// App state. Board web views and terminal views are cached per project so switching is instant.
@MainActor
final class AppModel: ObservableObject {
    @Published var projects: [Project] { didSet { ProjectIcons.shared.refresh(projects) } }
    @Published var selectedProjectId: String? {
        didSet {
            if let id = selectedProjectId { Prefs.store.set(id, forKey: Prefs.lastProject) }
            if oldValue != selectedProjectId { nextIndex = 0 }
            // From one project to another: the pixel loader covers the time the new board takes to build.
            if oldValue != nil, oldValue != selectedProjectId, let p = project { SwitchLoader.shared.show(p.name) }
        }
    }
    @Published var sidebarVisible: Bool = Prefs.store.object(forKey: Prefs.sidebarVisible) as? Bool ?? true {
        didSet { Prefs.store.set(sidebarVisible, forKey: Prefs.sidebarVisible) }
    }
    @Published var sessions: [TerminalSession] = [] { didSet { adoptLabels(sessions); TurnMemo.watch(sessions: sessions, boards: Array(boards.values), model: self) } }
    @Published var selectedSession: [String: UUID] = [:]   // per project
    @Published var boardState: [String: BoardState] = [:]
    /// The image preview open over the window (nil = closed).
    @Published var preview: PreviewState?
    /// ⌘K palette.
    @Published var paletteOpen = false
    /// ⌘N: the New request sheet, pinned to the project it was opened in (nil = closed). A session that
    /// switches the window to another project meanwhile must not move the request there.
    @Published var requestProjectId: String?
    var requestOpen: Bool {
        get { requestProjectId != nil }
        set { requestProjectId = newValue ? (requestProjectId ?? selectedProjectId) : nil; if !newValue { requestPickProject = false } }
    }
    /// Opened from outside the window (⌃⌥N, menu bar): the sheet asks which project it is for.
    @Published var requestPickProject = false
    var requestSeed = ""
    /// "+ Task" on the Tasks tab opens New request with Task already picked.
    var requestKindSeed: RequestKind?
    var paletteSeed = ""
    /// Ask the board to show an item: switch tab, scroll to it, flash it.
    @Published var focus: FocusRequest?
    @Published var highlightRef: String?
    /// Which actionable item ⌘J goes to next.
    @Published var nextIndex = 0
    /// Set by the menu bar label (it lives as long as the app): reopens the main window.
    static var reopenWindow: (() -> Void)?
    var quittingForUpdate = false
    var gitCache: [String: RepoGit] = [:]
    var lastShipCheck = Date.distantPast
    /// Bumped when a deploy is recorded or items turn live: the Release tab reloads its repos and reasons.
    @Published var deployTick = 0
    /// A short message at the bottom of the window (from Claude via the Steerify MCP, or from the app).
    @Published var toast: Toast?
    struct Toast: Equatable {
        let id = UUID(); let message: String; let projectId: String?; let ref: String?
        var undo: (() -> Void)? = nil
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    func showToast(_ message: String, projectId: String? = nil, ref: String? = nil, undo: (() -> Void)? = nil) {
        let t = Toast(message: message, projectId: projectId, ref: ref, undo: undo)
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in if self?.toast == t { self?.toast = nil } }
    }

    /// steerify.json changed (Claude, you, git): take the new repos / release / automation right away.
    func reloadManifest(_ projectId: String) {
        guard let i = projects.firstIndex(where: { $0.id == projectId }), let fresh = ProjectStore.read(projects[i].boardDir) else { return }
        if fresh != projects[i] { projects[i] = fresh }
    }

    /// UI actions sent by `Steerify --mcp` (Claude sessions): toast, jump to an item, refresh.
    private func handleUI(_ info: [AnyHashable: Any]) {
        let board = info["board"] as? String ?? ""
        let p = projects.first { URL(fileURLWithPath: $0.boardDir).standardizedFileURL.path == URL(fileURLWithPath: board).standardizedFileURL.path }
        let ref = info["ref"] as? String
        if let p {
            reloadManifest(p.id)
            board_(p).reload()
            if let ref, info["action"] as? String == "focus" { focusItem(projectId: p.id, ref: ref) }
        }
        if let m = info["message"] as? String { showToast(m, projectId: p?.id, ref: ref) }
    }
    private func board_(_ p: Project) -> BoardStore { board(for: p) }
    /// Answers waiting for a session, and what was just sent to sessions (Nudges.swift).
    @Published var nudges: [Nudge] = []
    @Published var recentPings: [Nudge] = []
    /// Deploys to tell sessions that waited on them (DeployWake.swift), by session id.
    var deployWakes: [UUID: PendingWake] = [:]
    var notified = Set<String>()
    /// Projects whose waiting answers go out now, without the change-your-mind delay ("Send now" on the setup view).
    var rushNudges = Set<String>()
    /// When the next delayed ping is due (one re-check scheduled at a time).
    var nudgeRecheckAt: Date?
    /// iPhones connected to each project's relay channel right now (Relay.swift): the tab bar's phone icon turns green.
    @Published var phones: [String: Int] = [:]
    @Published var pairingProjectId: String?          // the "Connect your iPhone" window is open for this project
    private var statusWatcher: StatusWatcher?
    private var nudgeTimer: Timer?
    private var nudgePending = false
    private var liveTimer: Timer?

    /// Session states from hooks + moving answers forward: on every board change, state change, and once a minute.
    func startAutomation() {
        guard statusWatcher == nil else { return }
        statusWatcher = StatusWatcher(model: self)
        Notify.ask()
        NotificationCenter.default.addObserver(forName: .steerifyBoardReloaded, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleNudges() }
        }
        NotificationCenter.default.addObserver(forName: .steerifyManifestChanged, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated { if let id = n.object as? String { self?.reloadManifest(id) } }
        }
        if !CommandLine.arguments.contains("--background") {
            DistributedNotificationCenter.default().addObserver(forName: SteerifyMCP.uiNotification, object: nil, queue: .main) { [weak self] n in
                let info = n.userInfo ?? [:]
                MainActor.assumeIsolated { self?.handleUI(info) }
            }
        }
        nudgeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusWatcher?.refresh(); self?.evaluateNudges() }
        }
        nudgeTimer?.tolerance = 10
        liveTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; for p in self.projects { Task { await self.checkLive(p) } } }
        }
        liveTimer?.tolerance = 60
        for p in projects { Task { await checkLive(p) } }
        for p in projects { _ = board(for: p) }       // watch every project's board, not only the open one
        statusWatcher?.refresh()
        evaluateNudges()
        startTaskClock()
        startStartQueue()
        startPhoneInbox()
        startGitHubInbox()
        startRelay()
        startBoardPublish()
    }

    func sessionsChanged() {
        objectWillChange.send()
        publishStatus()
        if sessions.contains(where: { $0.kind == .claude && $0.status == .idle }) { checkShippedSoon() }
        scheduleNudges()
    }

    /// Coalesce: many file / state events in a burst → one evaluation, never re-entrant.
    func scheduleNudges() {
        guard !nudgePending else { return }
        nudgePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.nudgePending = false
            self.evaluateNudges()
        }
    }

    /// ⌘J: the next item that waits on you (board jumps there, its session shows).
    func jumpNext() {
        guard let p = project else { return }
        let list = nextSteps(p).filter(\.urgent)
        guard !list.isEmpty else { return }
        let i = nextIndex % list.count
        let step = list[i]
        nextIndex = (nextIndex + 1) % list.count
        // Always say why ⌘J brought you here, so a jump is never a mystery.
        showToast("⌘J \(i + 1)/\(list.count) · \(step.reason.prefix(1).uppercased() + step.reason.dropFirst())", projectId: p.id, ref: step.ref)
        if step.ref.hasPrefix("session:"), let id = UUID(uuidString: String(step.ref.dropFirst(8))) {
            selectedSession[p.id] = id; return
        }
        openCombo(projectId: p.id, ref: step.ref, startNew: false)
    }

    struct FocusRequest: Equatable { let id = UUID(); let projectId: String; let ref: String }

    func focusItem(projectId: String, ref: String) {
        selectedProjectId = projectId
        focus = FocusRequest(projectId: projectId, ref: ref)
        highlightRef = ref
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in if self?.highlightRef == ref { self?.highlightRef = nil } }
    }

    /// ⌘K ↩: the item on the board + its session in the terminal (live, else its last conversation resumed).
    /// ⌘↩ (startNew): a new session for the item with its natural intent.
    func openCombo(projectId: String, ref: String, startNew: Bool) {
        guard let p = projects.first(where: { $0.id == projectId }), var item = ItemRef(ref: ref) else { return }
        focusItem(projectId: projectId, ref: ref)
        if !startNew {
            if let live = sessions.first(where: { $0.projectId == projectId && $0.item?.ref == ref && $0.running }) {
                selectedSession[projectId] = live.id; return
            }
            if let link = board(for: p).lastLink(ref), SessionLinks.resumable(link.claudeSession) {
                resume(link, projectId: projectId); return
            }
            return                                   // no session yet: the item is shown, ⌘↩ starts one
        }
        item = BoardFiles.resolve(item, in: p)
        start(projectId: projectId, item: item, intent: naturalIntent(item, in: p))
    }

    /// What "start" means for an item: fix a refined test, build a decided choice, plan a roadmap item…
    func naturalIntent(_ item: ItemRef, in p: Project) -> Intent {
        let b = board(for: p)
        switch item.kind {
        case "test":
            let pick = b.ships.first { $0.id == item.id }.flatMap { b.effectivePick($0) }
            return pick == "refine" || pick == "broken" ? .fix : pick == "ok" ? .release : .look
        case "choice":
            return b.decisions.first { $0.id == item.id }.map { b.isDecided($0) } == true ? .build : .look
        case "road": return .plan
        case "track", "reqs": return .resume
        case "release": return .ship
        case "req": return .check
        case "request": return .intake
        case "task": return .run
        default: return .look
        }
    }

    enum BoardState { case starting, ready, missing }

    private var webViews: [String: WKWebView] = [:]
    var boards: [String: BoardStore] = [:]

    /// The native board of a project (read from its workspace files, kept live).
    func board(for p: Project) -> BoardStore {
        if let b = boards[p.id] { return b }
        let b = BoardStore(project: p)
        boards[p.id] = b
        TurnMemo.watch(sessions: sessions, boards: Array(boards.values), model: self)
        return b
    }

    /// The project's own HTML board, in the browser (older setups / sharing).
    func openWebBoard() {
        guard let p = project, p.port > 0 else { return }
        BoardServers.shared.ensure(p) { ok in if ok { NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(p.port)/")!) } }
    }

    init() {
        projects = ProjectStore.load()
        ProjectIcons.shared.refresh(projects)
        let last = Prefs.store.string(forKey: Prefs.lastProject)
        selectedProjectId = projects.first(where: { $0.id == last })?.id ?? projects.first?.id
    }

    var project: Project? { projects.first { $0.id == selectedProjectId } }

    func addWorkspace() {
        guard let folder = ProjectStore.pickFolder() else { return }
        addWorkspace(folder: folder)
    }

    /// Any folder becomes a project: its board is opened, or created in `<folder>/.steerify` the first time.
    func addWorkspace(folder: String) {
        let created = ProjectStore.boardFolder(in: folder) == nil
        guard let path = ProjectStore.openOrCreate(folder, takenIds: Set(projects.map(\.id))),
              let p = ProjectStore.read(path) else {
            showToast("Couldn't create a board in \((folder as NSString).lastPathComponent)")
            return
        }
        if !projects.contains(where: { $0.id == p.id }) {
            projects.append(p)
            ProjectStore.save(projects.map(\.boardDir))
        }
        selectedProjectId = p.id
        if created { showToast("\(p.name) is steered: its board is in .steerify/", projectId: p.id) }
    }

    func select(index: Int) {
        let list = switcherProjects
        guard list.indices.contains(index) else { return }
        selectedProjectId = list[index].id
    }

    // MARK: Board

    func webView(for p: Project) -> WKWebView {
        if let w = webViews[p.id] { return w }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.setValue(false, forKey: "drawsBackground")   // no white flash before the dark board paints
        webViews[p.id] = w
        boardState[p.id] = .starting
        guard p.port > 0 else { boardState[p.id] = .missing; return w }
        BoardServers.shared.ensure(p) { [weak self, weak w] ok in
            guard let self, let w else { return }
            self.boardState[p.id] = ok ? .ready : .missing
            if ok { w.load(URLRequest(url: URL(string: "http://127.0.0.1:\(p.port)/")!)) }
        }
        return w
    }

    /// ⌘R: re-read the project's steerify.json (repos, areas) and its board files.
    func reloadBoard() {
        guard let p = project else { return }
        if let fresh = ProjectStore.read(p.boardDir), let i = projects.firstIndex(where: { $0.id == p.id }), fresh != projects[i] {
            projects[i] = fresh
            boards[p.id] = nil              // rebuilt from the new manifest on next use
        }
        board(for: projects.first { $0.id == p.id }!).reread()
    }

    // MARK: Sessions

    func sessions(of projectId: String) -> [TerminalSession] {
        sessions.filter { $0.projectId == projectId }
    }

    func current(of projectId: String) -> TerminalSession? {
        let list = sessions(of: projectId)
        if let id = selectedSession[projectId], let s = list.first(where: { $0.id == id }) { return s }
        return list.last
    }

    /// New session in the current project. A fresh Claude session starts with "/steerify" (guided start).
    @discardableResult
    func newSession(_ kind: SessionKind, repo: Repo? = nil) -> TerminalSession? {
        guard let p = project else { return nil }
        let cid = kind == .claude ? UUID().uuidString.lowercased() : nil
        let r = repo ?? p.repos.first!
        let s = TerminalSession(project: p, repo: r, kind: kind,
                                command: cid.map { ["--session-id", $0, "--name", "Guided · \(r.name)", "/steerify"] }, claudeId: cid)
        s.title = kind == .claude ? "Guided · \(r.name)" : r.name
        return open(s)
    }

    /// Start (or focus) a Claude session for a board item, already briefed: "/steerify <intent> <item>".
    @discardableResult
    func start(projectId: String, item ref: ItemRef, intent: Intent, dry: Bool = false,
               extraBrief: String? = nil, also: [String] = [], focus: Bool = true, fresh: Bool = false) -> TerminalSession? {
        guard let p = projects.first(where: { $0.id == projectId }) else { return nil }
        if focus { selectedProjectId = p.id }   // false: the session starts in the background (a request filed for another project)
        if !fresh, let existing = sessions.first(where: { $0.projectId == p.id && $0.covers(ref.ref) && $0.running }) {
            selectedSession[p.id] = existing.id          // one live session per item: jump to it
            if let extraBrief { existing.submit(extraBrief) }
            else if existing.kind == .claude, existing.status == .idle {
                // Resume on an idle session: say something, never just show it (request r261121-122352).
                // Working: it is already on it. Needs you: typing would answer its prompt, so leave it.
                let r = BoardFiles.resolve(ref, in: p).ref
                existing.submit("/steerify \(intent.rawValue) \(r) — " + (notesHint(r, in: p).map { $0 + " " } ?? "") + resumeNudge(claudeId: existing.claudeId, ref: r, in: p))
            }
            existing.alsoRefs += also.filter { !existing.covers($0) }
            return existing
        }
        let item = BoardFiles.resolve(ref, in: p)
        // Notes you left on a To test item travel with the very first line, whatever the verdict (request r261122-095541).
        let prompt = "/steerify \(intent.rawValue) \(item.ref)" + (notesHint(item.ref, in: p).map { " — " + $0 } ?? "")
        // Same feature (design → dev → test → release) already open → continue in that conversation (SessionFlow.swift).
        if !fresh, let live = liveThreadSession(projectId: p.id, ref: item.ref) {
            selectedSession[p.id] = live.id
            let extra = extraBrief.map { " — " + $0.replacingOccurrences(of: "\n", with: " ") } ?? ""
            live.submit(prompt + extra)
            live.alsoRefs += ([item.ref] + also).filter { !live.covers($0) }
            if !dry, let cid = live.claudeId {
                SessionLinks.append(SessionLink(item: item.ref, claudeSession: cid, intent: intent.rawValue, repo: live.repo.name,
                                                title: item.title ?? item.ref, started: BoardStore.now()), in: p.boardDir)
            }
            persistSessions()
            return live
        }
        // Same item, or the same feature, again → resume that Claude conversation (history + your new instruction), in its repo.
        let b = board(for: p)
        // fresh: a task run starts a new conversation each time (its brief has the run id + outcome).
        let prevOwn = fresh ? nil : b.lastLink(item.ref).flatMap { SessionLinks.resumable($0.claudeSession) ? $0 : nil }
        let prevThread = prevOwn == nil && !fresh ? b.lastLink(inThread: b.thread(of: item.ref)).flatMap { SessionLinks.resumable($0.claudeSession) ? $0 : nil } : nil
        if let prev = prevOwn ?? prevThread,
           let repo = p.repos.first(where: { $0.name == prev.repo && $0.exists }) ?? BoardFiles.repo(for: item.area, in: p) {
            var cmd = ["--resume", prev.claudeSession, prompt]
            if let extraBrief, prevThread != nil { cmd[2] = prompt + " — " + extraBrief.replacingOccurrences(of: "\n", with: " ") }
            else if extraBrief == nil { cmd[2] = prompt + " — " + resumeNudge(claudeId: prev.claudeSession, ref: item.ref, in: p) }
            let s = TerminalSession(project: p, repo: repo, kind: .claude, item: item, command: cmd, dry: dry, claudeId: prev.claudeSession)
            s.title = SessionName.short(item.title ?? item.ref, intent: intent.rawValue)
            // A conversation resumes only in the folder it was started in (its feature worktree, if any).
            if let d = prev.dir, FileManager.default.fileExists(atPath: d) { s.workdir = d }
            s.extraEnv = ["STEERIFY_FLOW": WorkFlow.of(p).rawValue, "STEERIFY_REPO_MAIN": repo.path]
            if prevThread != nil {
                s.alsoRefs = [prev.item] + also.filter { $0 != item.ref && $0 != prev.item }
                if !dry {
                    SessionLinks.append(SessionLink(item: item.ref, claudeSession: prev.claudeSession, intent: intent.rawValue, repo: repo.name,
                                                    title: item.title ?? item.ref, started: BoardStore.now(), dir: s.workdir), in: p.boardDir)
                }
            }
            return open(s)
        }
        guard let repo = BoardFiles.repo(for: item.area, in: p) else { return nil }
        let id = UUID().uuidString.lowercased()
        let title = item.title ?? item.ref
        var brief = "Steerify: this session belongs to the board item \(item.ref) (\"\(title)\") of the project \(p.name). "
            + "The board folder is $STEERIFY_BOARD. Work on this item directly with the steerify skill; never ask which item to work on."
        if let extraBrief { brief += "\n\n" + extraBrief }
        // Branches and releases (Flow.swift): code work may get the feature's own folder + branch.
        let place = workplace(for: item, intent: intent, repo: repo, in: p)
        let workdir = place.dir == repo.path ? nil : place.dir
        if !place.brief.isEmpty { brief += "\n\n" + place.brief }
        if !dry {
            SessionLinks.append(SessionLink(item: item.ref, claudeSession: id, intent: intent.rawValue, repo: repo.name,
                                            title: title, started: BoardStore.now(), dir: workdir), in: p.boardDir)
        }
        let short = SessionName.short(title, intent: intent.rawValue)
        let s = TerminalSession(project: p, repo: repo, kind: .claude, item: item,
                                command: ["--session-id", id, "--name", short,
                                          "--append-system-prompt", brief, prompt], dry: dry, claudeId: id)
        s.title = short
        s.workdir = workdir
        s.extraEnv = place.env
        s.alsoRefs = also.filter { $0 != item.ref }
        if !dry { for r in s.alsoRefs { SessionLinks.append(SessionLink(item: r, claudeSession: id, intent: intent.rawValue, repo: repo.name, title: title, started: BoardStore.now(), dir: workdir), in: p.boardDir) } }
        return open(s)
    }

    /// Reopen an item's last conversation and tell it to go on (what it named next, else state of the art + next step).
    func resume(_ link: SessionLink, projectId: String) {
        guard let p = projects.first(where: { $0.id == projectId }) else { return }
        if let live = sessions.first(where: { $0.projectId == p.id && $0.item?.ref == link.item && $0.running }) {
            selectedSession[p.id] = live.id; return
        }
        guard var item = ItemRef(ref: link.item) else { return }
        item.title = link.title
        let repo = p.repos.first { $0.name == link.repo } ?? p.repos.first!
        let go = "/steerify \(link.intent) \(link.item) — " + resumeNudge(claudeId: link.claudeSession, ref: link.item, in: p)
        let s = TerminalSession(project: p, repo: repo, kind: .claude, item: item, command: ["--resume", link.claudeSession, go], claudeId: link.claudeSession)
        if let d = link.dir, FileManager.default.fileExists(atPath: d) { s.workdir = d }
        s.title = SessionName.short(link.title ?? link.item, intent: link.intent)
        open(s)
    }

    /// steerify://start?project=sb&item=test:<id>&intent=fix[&dry=1]   ·   steerify://new?project=sb   ·   open?item=   ·   since?hours=
    func handle(_ url: URL) {
        guard url.scheme == "steerify", let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let q = Dictionary((c.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let pid = q["project"] ?? selectedProjectId ?? ""
        switch url.host {
        case "start":
            guard let ref = q["item"].flatMap(ItemRef.init(ref:)) else { return }
            start(projectId: pid, item: ref, intent: Intent(rawValue: q["intent"] ?? "") ?? .look, dry: q["dry"] == "1")
        case "new":
            if projects.contains(where: { $0.id == pid }) { selectedProjectId = pid }
            newSession(.claude)
        case "open":       // steerify://open?project=sb&item=choice:<id> → that item on the board
            if let ref = q["item"], !ref.isEmpty { focusItem(projectId: pid, ref: ref) }
        case "since":      // steerify://since?project=sb&hours=20 → the "Since you left" brief as if you were away that long
            if projects.contains(where: { $0.id == pid }) { selectedProjectId = pid }
            let h = Double(q["hours"] ?? "") ?? 20
            DispatchQueue.main.async { SinceYouLeft.shared.check(self, force: Date().addingTimeInterval(-h * 3600)) }
        default: break
        }
        if q["dry"] != "1" && !CommandLine.arguments.contains("--background") { NSApp.activate(ignoringOtherApps: true) }
    }

    private func open(_ s: TerminalSession) -> TerminalSession {
        _ = s.view   // start the process now: sessions keep working while their tab is hidden
        sessions.append(s)
        selectedSession[s.projectId] = s.id
        persistSessions()
        return s
    }

    func close(_ s: TerminalSession) {
        s.terminate()
        sessions.removeAll { $0.id == s.id }
        persistSessions()
        if selectedSession[s.projectId] == s.id { selectedSession[s.projectId] = orderedSessions(of: s.projectId).first?.id }
    }

    /// ⇧⌘] / ⇧⌘[ : next / previous session of the current project.
    func cycleSession(_ d: Int) {
        guard let p = project else { return }
        let list = orderedSessions(of: p.id)
        guard !list.isEmpty, let cur = current(of: p.id), let i = list.firstIndex(where: { $0.id == cur.id }) else { return }
        selectedSession[p.id] = list[(i + d + list.count) % list.count].id
    }

    /// Text size preset changed: resize every open terminal.
    func applyFonts() {
        for s in sessions { s.view.font = NSFont.monospacedSystemFont(ofSize: Prefs.size.terminal, weight: .regular) }
    }

    func closeCurrent() {
        guard let p = project, let s = current(of: p.id) else { return }
        close(s)
    }

    // MARK: Sessions survive a restart

    struct SavedSession: Codable { var projectId: String; var repo: String; var kind: String; var item: String?; var title: String?; var claudeId: String?; var selected: Bool; var dir: String? = nil }

    func persistSessions() {
        // Test instances never touch your sessions (`--test-persist`: they save to their own test settings, to test a restart).
        if CommandLine.arguments.contains("--background") && !CommandLine.arguments.contains("--test-persist") { return }
        // One-shot shells (a deploy: `shellCommand`) did their job; after a restart they would only be empty tabs.
        let list = sessions.filter { !$0.dry && $0.shellCommand == nil }.map { s in
            SavedSession(projectId: s.projectId, repo: s.repo.name, kind: s.kind.rawValue, item: s.item?.ref, title: s.autoTitle,
                         claudeId: s.claudeId, selected: selectedSession[s.projectId] == s.id, dir: s.workdir)
        }
        Prefs.store.set(try? JSONEncoder().encode(list), forKey: "openSessions")
    }

    /// Reopen last time's sessions: Claude conversations resumed (history kept), shells in their repos.
    func restoreSessions() {
        guard sessions.isEmpty, !CommandLine.arguments.contains("--background") || CommandLine.arguments.contains("--test-persist"),
              let d = Prefs.store.data(forKey: "openSessions"),
              let list = try? JSONDecoder().decode([SavedSession].self, from: d) else { return }
        for saved in list {
            guard let p = projects.first(where: { $0.id == saved.projectId }),
                  let repo = p.repos.first(where: { $0.name == saved.repo && $0.exists }) ?? p.repos.first else { continue }
            var item = saved.item.flatMap(ItemRef.init(ref:))
            item?.title = saved.title
            let s: TerminalSession
            if saved.kind == "claude" {
                guard let cid = saved.claudeId, SessionLinks.resumable(cid) else { continue }   // never got a message: nothing to resume
                s = TerminalSession(project: p, repo: repo, kind: .claude, item: item, command: ["--resume", cid], claudeId: cid)
                if let d = saved.dir, FileManager.default.fileExists(atPath: d) { s.workdir = d }
                s.title = saved.title.map { $0.contains(" · ") && $0.count <= 28 ? $0 : SessionName.short($0, intent: nil) } ?? "Guided · \(repo.name)"
            } else {
                s = TerminalSession(project: p, repo: repo, kind: .shell, item: item)
            }
            _ = s.view
            sessions.append(s)
            if saved.selected { selectedSession[p.id] = s.id }
        }
        persistSessions()
    }

    // MARK: New build → offer a restart (never automatic: Claude may be mid-task)

    @Published var updateReady = false
    private var updateStream: FSEventStreamRef?
    private let launchedAt = Date()

    func watchForUpdates() {
        let bundleDir = Bundle.main.bundleURL.deletingLastPathComponent().path
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let me = Unmanaged<AppModel>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { me.checkUpdate() }
        }
        guard let s = FSEventStreamCreate(nil, cb, &ctx, [bundleDir] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        updateStream = s
    }

    private func checkUpdate() {
        guard let exe = Bundle.main.executableURL,
              let m = try? FileManager.default.attributesOfItem(atPath: exe.path)[.modificationDate] as? Date else { return }
        updateReady = m > launchedAt.addingTimeInterval(2)
    }

    /// "Update" (top bar, ⌥⌘R, What's new): with Claude sessions at work, ask first; otherwise restart at once.
    func confirmRestartForUpdate() {
        let working = sessions.filter { $0.kind == .claude && $0.running && $0.status == .working }.count
        if working > 0 {
            let a = NSAlert()
            a.messageText = "\(working) session\(working == 1 ? " is" : "s are") still rowing"
            a.informativeText = "Updating restarts Steerify and stops \(working == 1 ? "it" : "them") mid-step. Conversations come back with their history, the running step doesn't."
            a.addButton(withTitle: "Keep working")
            a.addButton(withTitle: "Update anyway")
            guard a.runModal() == .alertSecondButtonReturn else { return }
        }
        restartForUpdate()
    }

    /// Save the sessions, reopen the app from the new build, quit this one.
    func restartForUpdate() {
        // Test hook (`--press-update`, test copies only): log the restart instead of doing it.
        if CommandLine.arguments.contains("--press-update") { FileHandle.standardError.write("[update] restart\n".data(using: .utf8)!); return }
        quittingForUpdate = true
        persistSessions()
        if AppUpdater.shared.installIfReady() { return }   // a downloaded release: Sparkle replaces the app and reopens it
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.8; /usr/bin/open '\(Bundle.main.bundleURL.path)'"]
        try? p.run()
        NSApp.terminate(nil)
    }

    func shutdown() {
        sessions.forEach { $0.terminate() }
        BoardServers.shared.stopAll()
    }
}
