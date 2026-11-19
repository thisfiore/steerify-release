import Foundation
import Darwin

/// Makes sure a project's board server is listening. Uses the one already running (SB's LaunchAgent),
/// otherwise starts `node <boardDir>/server.mjs` and stops it again when the app quits.
final class BoardServers {
    static let shared = BoardServers()
    private var started: [String: Process] = [:]
    private lazy var nodePath: String? = Self.resolveNode()
    var node: String? { nodePath }

    /// Cheap check: can we open a TCP connection to 127.0.0.1:port?
    static func isListening(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return rc == 0
    }

    /// Calls back on the main queue once the board answers (or after ~4 s).
    func ensure(_ project: Project, ready: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            if Self.isListening(project.port) { return DispatchQueue.main.async { ready(true) } }
            let script = (project.boardDir as NSString).appendingPathComponent("server.mjs")
            guard let node = nodePath, FileManager.default.fileExists(atPath: script) else {
                return DispatchQueue.main.async { ready(false) }
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: node)
            p.arguments = [script]
            p.currentDirectoryURL = URL(fileURLWithPath: (project.boardDir as NSString).deletingLastPathComponent)
            var env = ProcessInfo.processInfo.environment
            env["BOARD_PORT"] = String(project.port)
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return DispatchQueue.main.async { ready(false) } }
            DispatchQueue.main.sync { started[project.id] = p }
            var ok = false
            for _ in 0..<40 { if Self.isListening(project.port) { ok = true; break }; usleep(100_000) }
            DispatchQueue.main.async { ready(ok) }
        }
    }

    func stopAll() {
        for p in started.values where p.isRunning { p.terminate() }
        started.removeAll()
    }

    /// GUI apps don't get the shell PATH. Ask the interactive shell first (nvm lives in .zshrc), then a login
    /// shell, then nvm's folder; keep the first node that actually runs (a stale Homebrew node can fail to load).
    /// `PATH` comes first: `Steerify --mcp` inherits the Claude session's PATH, and must not spawn an interactive
    /// shell there (it shares Claude's terminal from another process group: zsh -i gets SIGTTOU and stops for good).
    private static func resolveNode() -> String? {
        var candidates: [String] = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { "\($0)/node" }
        if let s = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) && run($0, ["--version"]) != nil }) { return s }
        candidates = []
        for flags in ["-ilc", "-lc"] {
            if let s = run("/bin/zsh", [flags, "command -v node"])?.split(separator: "\n").last.map(String.init) {
                candidates.append(s.trimmingCharacters(in: .whitespaces))
            }
        }
        let nvm = NSHomeDirectory() + "/.nvm/versions/node"
        if let vs = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            candidates += vs.sorted(by: >).map { "\(nvm)/\($0)/bin/node" }
        }
        candidates += ["/opt/homebrew/bin/node", "/usr/local/bin/node"]
        return candidates.first { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) && run($0, ["--version"]) != nil }
    }

    /// Runs a command, returns stdout when it exits 0 within `timeout` (a stopped or stuck shell is killed).
    private static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 5) -> String? {
        let r = Self.exec(exe, args, timeout: timeout)
        guard r.status == 0 else { return nil }
        return r.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs a process with stdin closed, drains stdout and stderr together (no pipe-buffer deadlock),
    /// and SIGKILLs it after `timeout` (status -1). Never blocks forever.
    static func exec(_ exe: String, _ args: [String], cwd: String? = nil, timeout: TimeInterval) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return (-2, "", "\(error)") }
        var o = Data(), e = Data()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { o = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { e = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            kill(p.processIdentifier, SIGKILL)
            _ = done.wait(timeout: .now() + 2)
            return (-1, "", "timed out after \(Int(timeout)) s: \(exe) \(args.prefix(1).joined())")
        }
        _ = g.wait(timeout: .now() + 2)   // a grandchild holding the pipe open must not block us either
        return (p.terminationStatus, String(data: o, encoding: .utf8) ?? "", String(data: e, encoding: .utf8) ?? "")
    }
}
