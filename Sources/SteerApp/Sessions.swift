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
    @Published var title: String
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
    /// From Claude Code hooks (Status.swift).
    @Published var status: SessionStatus = .starting
    /// A shell session that runs one command and exits (deploys), and what to do with its exit code.
    var shellCommand: String?
    var onExit: ((Int32) -> Void)?
    var statusAt: Date?
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
        self.title = item?.title ?? repo.name
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
        env.merge(extraEnv) { _, new in new }
        let shell = env["SHELL"] ?? "/bin/zsh"
        v.startProcess(executable: shell, args: shellCommand.map { ["-l", "-c", $0 + "; s=$?; echo; echo \"[Steerify] exit $s\"; exit $s"] } ?? ["-l"],
                       environment: env.map { "\($0.key)=\($0.value)" },
                       execName: "-" + (shell as NSString).lastPathComponent,
                       currentDirectory: workdir ?? repo.path)
        if kind == .claude {
            let line = (["claude", "--settings", Self.shellQuote(SessionHooks.settings.path),
                         "--mcp-config", Self.shellQuote(SessionHooks.mcpConfig.path)] + (command ?? []).map { $0.hasPrefix("-") ? $0 : Self.shellQuote($0) }).joined(separator: " ")
            v.send(txt: (dry ? "echo " + Self.shellQuote(line) + "; pwd; git branch --show-current; env | grep ^STEERIFY_ | sort" : line) + "\r")
        }
        return v
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    func terminate() {
        if running { view.terminate() }
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
