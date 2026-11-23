import AppKit
import Darwin

/// A Claude session that sent no hook yet, 20 s after it started: why, read from the process tree and the screen,
/// so its card says it instead of "warming up" forever, with a Restart (choice stuck-warming-up, option A).
struct StuckStart: Equatable {
    /// Short, for the card: "stopped: chat not found", "waiting on a prompt", "still loading · 25 s".
    var reason: String
    /// Claude is gone and the shell sits idle: Restart is the way out (else it may still come).
    var stopped: Bool
    static let after: TimeInterval = 20

    /// Reads one session. nil = not stuck (a signal came, or it is too early).
    @MainActor static func diagnose(_ s: TerminalSession, now: Date = Date()) -> StuckStart? {
        guard s.kind == .claude, s.running, s.status == .starting, let at = s.launchedAt else { return nil }
        let age = now.timeIntervalSince(at)
        guard age >= after else { return nil }
        let pid = s.view.process?.shellPid ?? 0
        let screen = (s.view.terminalContentSnapshot(region: .history(maximumScrollbackRows: 60))?.rows.map(\.text) ?? [])
            .suffix(40).joined(separator: "\n").lowercased()
        return read(screen: screen, claudeRunning: pid > 0 && hasChild(pid), age: age)
    }

    /// The rules, apart from the process (tested on their own).
    static func read(screen: String, claudeRunning: Bool, age: TimeInterval) -> StuckStart {
        if !claudeRunning {
            if screen.contains("no conversation found") { return .init(reason: "stopped: chat not found", stopped: true) }
            if screen.contains("command not found") || screen.contains("not found: claude") {
                return .init(reason: "stopped: claude not installed", stopped: true)
            }
            return .init(reason: "stopped: Claude isn't running", stopped: true)
        }
        if screen.contains("trust") { return .init(reason: "waiting on a prompt in the terminal", stopped: false) }
        if screen.contains("/login") || screen.contains("log in") || screen.contains("sign in") {
            return .init(reason: "needs a login in the terminal", stopped: false)
        }
        if screen.contains("error") { return .init(reason: "error in the terminal", stopped: false) }
        let n = Int(age)
        return .init(reason: n < 90 ? "still loading · \(n) s" : "no signal for \(n / 60 > 0 ? "\(n / 60) min" : "\(n) s")", stopped: false)
    }

    /// Whether the session's shell has a child (claude) right now.
    static func hasChild(_ pid: pid_t) -> Bool {
        var kids = [pid_t](repeating: 0, count: 16)
        let n = kids.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, Int32($0.count)) }
        return n > 0
    }
}

extension AppModel {
    /// Every few seconds: refresh the reason on sessions that are still warming up.
    func checkStuckStarts() {
        for s in sessions where s.kind == .claude {
            let d = StuckStart.diagnose(s)
            if d != s.stuck { s.stuck = d }
        }
    }

    /// Restart a stuck session in place: same chat (resumed when it has one on disk), same item, folder and name.
    func restartStuck(_ old: TerminalSession) {
        guard old.kind == .claude, let p = projects.first(where: { $0.id == old.projectId }),
              let i = sessions.firstIndex(where: { $0.id == old.id }) else { return }
        let cmd: [String]? = old.claudeId.flatMap { SessionLinks.resumable($0) ? ["--resume", $0] : nil } ?? old.command
        let s = TerminalSession(project: p, repo: old.repo, kind: .claude, item: old.item, command: cmd, dry: old.dry, claudeId: old.claudeId)
        s.alsoRefs = old.alsoRefs
        s.workdir = old.workdir
        s.extraEnv = old.extraEnv
        s.title = old.autoTitle
        s.customName = old.customName
        s.pinned = old.pinned
        old.terminate()
        _ = s.view
        sessions[i] = s
        if selectedSession[p.id] == old.id { selectedSession[p.id] = s.id }
        persistSessions()
    }
}
