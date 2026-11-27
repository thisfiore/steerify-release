import AppKit
import SwiftTerm

enum SessionKind: String { case claude, shell }

/// One terminal: a login shell in a repo, optionally starting Claude Code.
/// The view is created once and kept alive, so switching tabs or projects never restarts anything.
final class TerminalSession: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let projectId: String
    let repo: Repo
    let kind: SessionKind
    /// The name on the session row. A name you gave it (rename) wins over every automatic one (SessionLabels.swift).
    @Published var title: String { didSet { if let c = customName { if title != c { autoTitle = title; title = c } } else { autoTitle = title } } }
    private(set) var autoTitle = ""
    /// Your own name for the session (nil = Steerify's), and pinned = always on top of the list. Shared with the iPhone.
    @Published var customName: String? { didSet { title = customName ?? autoTitle } }
    @Published var pinned = false
    var labelsAdopted = false
    @Published var running = true
    @Published var directory: String?

    private(set) lazy var view: LocalProcessTerminalView = makeView()

    /// The board folder of the project (STEERIFY_BOARD) and the item this session works on, if any.
    let boardDir: String
    let item: ItemRef?
    /// Arguments for `claude` (nil for a plain shell), e.g. ["--session-id", id, "--name", title, "/steerify fix test:x"].
    let command: [String]?
    /// Dry run (tests): print the command instead of running it.
    let dry: Bool
    /// The Claude Code conversation id (resumable with `claude --resume`), for Claude sessions.
    var claudeId: String?
    /// Other board items this session works on (a combined session for one topic).
    var alsoRefs: [String] = []
    func covers(_ ref: String) -> Bool { item?.ref == ref || alsoRefs.contains(ref) }

    /// Type a prompt into the running Claude Code and press Enter. Text and Enter in one write arrive as a paste,
    /// where the "\r" is just a newline: the line sat in the prompt, never sent (request r261121-203129).
    /// So the text goes first (newlines flattened), Enter follows as its own keystroke.
    func submit(_ text: String) {
        let line = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: " ")
        view.send(txt: line)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.running else { return }
            self.view.send(txt: "\r")
        }
    }
    /// From Claude Code hooks (Status.swift).
    @Published var status: SessionStatus = .starting
    /// A shell session that runs one command and exits (deploys), and what to do with its exit code.
    var shellCommand: String?
    var onExit: ((Int32) -> Void)?
    /// A deploy that exited 0: the card shown over the tab (DeployDone.swift).
    @Published var celebration: DeployCelebration?
    var statusAt: Date?
    /// When the process was started, and why it still shows "warming up" after a while (StuckStart.swift).
    var launchedAt: Date?
    @Published var stuck: StuckStart?
    /// The stop check (ProcessCheck.swift): what it found on the last stop, the turn it read, whether it just nudged.
    @Published var processFlag: String?
    var processSig: String?
    var processNudgedLast = false
    /// The folder the session runs in when it is not the repo's own checkout (a feature worktree, Flow.swift),
    /// and what Steerify adds to its environment (STEERIFY_FLOW, STEERIFY_BRANCH…).
    var workdir: String?
    var extraEnv: [String: String] = [:]

    init(project: Project, repo: Repo, kind: SessionKind, item: ItemRef? = nil, command: [String]? = nil, dry: Bool = false, claudeId: String? = nil) {
        self.projectId = project.id
        self.boardDir = project.boardDir
        self.repo = repo
        self.kind = kind
        self.item = item
        self.command = command
        self.dry = dry
        self.claudeId = claudeId
        let t = item?.title ?? repo.name
        self.title = t
        self.autoTitle = t
        super.init()
    }

    private func makeView() -> LocalProcessTerminalView {
        let v = SteerTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        v.processDelegate = self
        v.font = NSFont.monospacedSystemFont(ofSize: Prefs.size.terminal, weight: .regular)
        v.nativeBackgroundColor = Theme.terminalBg
        v.nativeForegroundColor = Theme.terminalFg
        v.caretColor = Theme.accent
        v.optionAsMetaKey = true

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["STEERIFY_PROJECT"] = projectId
        env["STEERIFY_SESSION"] = id.uuidString
        env["STEERIFY_BOARD"] = boardDir
        if let item { env["STEERIFY_ITEM"] = item.ref }
        env["STEERIFY_LEVEL"] = Level.of(boardDir: boardDir, repoPath: repo.path).rawValue   // who is steering (Level.swift)
        let envs = TestEnvs.load(boardDir)
        if !envs.isEmpty { env["STEERIFY_ENVS"] = TestEnvs.describe(envs) }   // where to point To test links
        env.merge(extraEnv) { _, new in new }
        let shell = env["SHELL"] ?? "/bin/zsh"
        var args = shellCommand.map { ["-l", "-c", $0 + "; s=$?; echo; echo \"[Steerify] exit $s\"; exit $s"] } ?? ["-l"]
        if kind == .claude {
            // Remote Control: the session can be continued in the Claude app; its link is read off the screen below.
            let rc = Prefs.remoteControlOn && !dry ? ["--remote-control", Self.shellQuote(String(title.prefix(60)))] : []
            let line = (["claude", "--settings", Self.shellQuote(SessionHooks.settings.path),
                         "--mcp-config", Self.shellQuote(SessionHooks.mcpConfig.path)] + rc + (command ?? []).map { $0.hasPrefix("-") ? $0 : Self.shellQuote($0) }).joined(separator: " ")
            if !rc.isEmpty { watchRemoteLink(v) }
            // Dry (test copies): echo what would run; STEERIFY_DRY_LOG set → the same lines go to that file too.
            var full = dry ? "{ echo " + Self.shellQuote(line) + "; pwd; git branch --show-current; env | grep ^STEERIFY_ | sort; }" : line
            if dry, let log = env["STEERIFY_DRY_LOG"] { full += " 2>&1 | tee -a " + Self.shellQuote(log) }
            args = Self.claudeArgs(launch: Self.launchLine(full, id: id), shell: shell)
        }
        launchedAt = Date()
        v.startProcess(executable: shell, args: args,
                       environment: env.map { "\($0.key)=\($0.value)" },
                       execName: "-" + (shell as NSString).lastPathComponent,
                       currentDirectory: workdir ?? repo.path)
        return v
    }

    /// The shell's arguments for a Claude session. The launch line used to be typed into the new shell before it
    /// was ready: when many shells started at once (a restore of ~40 sessions) some lost it, and the card said
    /// "warming up" forever over an idle shell (request r261123-112615). Now the shell runs it itself (`-i` loads the
    /// user's rc files, so `claude` is on the PATH as in a typed command), then stays as a normal login shell.
    static func claudeArgs(launch: String, shell: String) -> [String] {
        ["-l", "-i", "-c", launch + "; exec " + shellQuote(shell) + " -l"]
    }

    /// The text typed into the new shell to run `command`. It is typed before the shell is ready, while the
    /// terminal is still in line mode, where macOS keeps at most 1024 bytes of a line (MAX_CANON): a long
    /// prompt was cut ("…the h") and claude never started. Long commands go to a script that removes itself,
    /// and only a short `. '<script>'` is typed (still in the shell's history, same shell, same cwd).
    static func launchLine(_ command: String, id: UUID) -> String {
        guard command.utf8.count > 400 else { return command }
        let dir = ProjectStore.dir.appendingPathComponent("launch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(id.uuidString).sh")
        let body = "rm -f \(shellQuote(file.path))\n\(command)\n"
        guard (try? body.write(to: file, atomically: true, encoding: .utf8)) != nil else { return command }
        return ". " + shellQuote(file.path)
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    func terminate() {
        if running { view.terminate() }
    }

    // MARK: Remote Control link (claude.ai/code/session_…), printed by Claude Code when the session starts

    @Published var remoteURL: String?
    private var remoteScanPending = false
    private var remoteScans = 0

    /// Reads the screen after new output until the link shows up (then stops looking), at most every 0.8 s, ~2 minutes.
    private func watchRemoteLink(_ v: LocalProcessTerminalView) {
        v.setProcessOutputHandler { [weak self] in
            DispatchQueue.main.async { self?.scheduleRemoteScan(v) }
        }
        if BoardStore.debug { FileHandle.standardError.write("remote watch on\n".data(using: .utf8)!) }
    }
    private func scheduleRemoteScan(_ v: LocalProcessTerminalView) {
        guard remoteURL == nil, !remoteScanPending else { return }
        remoteScanPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak v] in
            guard let self, let v else { return }
            self.remoteScanPending = false
            self.remoteScans += 1
            let snap = v.terminalContentSnapshot(region: .history(maximumScrollbackRows: 300))
            let text = (snap?.rows.map(\.text) ?? []).joined()   // wrapped rows joined: the link may span two
            if BoardStore.debug { FileHandle.standardError.write("remote scan \(self.remoteScans): snap \(snap == nil ? "nil" : "\(snap!.rows.count) rows") · \(text.suffix(160))\n".data(using: .utf8)!) }
            if let r = text.range(of: #"https://claude\.ai/code/session_[A-Za-z0-9]{24}"#, options: .regularExpression) {
                self.remoteURL = String(text[r])
                v.setProcessOutputHandler(nil)
                NotificationCenter.default.post(name: .steerifySessionRemote, object: self)
            } else if self.remoteScans > 150 {
                v.setProcessOutputHandler(nil)          // no Remote Control here (not logged in to claude.ai, or turned off)
            }
        }
    }

    // MARK: LocalProcessTerminalViewDelegate
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    /// Claude Code sets the terminal title to what it is working on; plain shells set "user@host:path" (ignored).
    @Published var activity: String?
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.contains("@") else { return }
        DispatchQueue.main.async { self.activity = t }
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        DispatchQueue.main.async { self.directory = directory }
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { self.running = false; self.status = .ended; if let c = exitCode { self.onExit?(c) } }
    }
}
