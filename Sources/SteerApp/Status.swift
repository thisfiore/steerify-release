import Foundation
import CoreServices
import AppKit
import UserNotifications

/// What a Claude session is doing, from Claude Code hooks (no polling, no screen scraping).
enum SessionStatus: String {
    case starting, working, idle, waiting, ended
    var label: String { ["starting": "starting", "working": "working", "idle": "idle", "waiting": "needs you", "ended": "ended"][rawValue]! }
}

/// Hooks for Steerify sessions: a tiny script writes the last hook event of each session to
/// Application Support/Steerify/status/<STEERIFY_SESSION>. Loaded with `claude --settings <file>`,
/// so the user's own hooks keep running.
enum SessionHooks {
    static var dir: URL { ProjectStore.dir.appendingPathComponent("status", isDirectory: true) }
    static var script: URL { ProjectStore.dir.appendingPathComponent("hook.sh") }
    static var settings: URL { ProjectStore.dir.appendingPathComponent("claude-hooks.json") }
    /// One MCP config per Steerify copy (bundle id + install path), pointing at that copy's own binary,
    /// so test / demo copies never redirect the user's sessions to a temporary binary.
    static var mcpConfig: URL {
        let exe = Bundle.main.executablePath ?? "steerify"
        let tag = String(UInt(bitPattern: exe.hashValue == 0 ? 1 : abs(exe.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) })), radix: 36)
        return ProjectStore.dir.appendingPathComponent("claude-mcp.\(Bundle.main.bundleIdentifier ?? "app").\(tag).json")
    }

    /// Writes the script + settings file (idempotent). Returns the settings path for `--settings`.
    @discardableResult
    static func install() -> String {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sh = """
        #!/bin/sh
        # Steerify: record the last Claude Code hook event of this session (read by the Steerify app).
        [ -z "$STEERIFY_SESSION" ] && exit 0
        in=$(cat)
        ev=$(printf '%s' "$in" | sed -n 's/.*"hook_event_name"[[:space:]]*:[[:space:]]*"\\([A-Za-z]*\\)".*/\\1/p' | head -1)
        msg=$(printf '%s' "$in" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\\([^"]*\\)".*/\\1/p' | head -1)
        d="$HOME/Library/Application Support/Steerify/status"
        mkdir -p "$d"
        printf '%s\\t%s\\t%s\\n' "$ev" "$(date +%s)" "$msg" > "$d/$STEERIFY_SESSION.tmp" && mv "$d/$STEERIFY_SESSION.tmp" "$d/$STEERIFY_SESSION"
        exit 0
        """
        if (try? String(contentsOf: script, encoding: .utf8)) != sh {
            try? sh.write(to: script, atomically: true, encoding: .utf8)
            chmod(script.path, 0o755)
        }
        let cmd = "\"\(script.path)\""
        let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "StopFailure",
                      "Notification", "PermissionRequest", "SessionEnd"]
        var hooks: [String: Any] = [:]
        for e in events { hooks[e] = [["hooks": [["type": "command", "command": cmd]]]] }
        if let d = try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: settings, options: .atomic)
        }
        // The Steerify MCP server (this same binary in --mcp mode), for every Claude session Steerify starts.
        if let exe = Bundle.main.executablePath,
           let d = try? JSONSerialization.data(withJSONObject: ["mcpServers": ["steerify": ["command": exe, "args": ["--mcp"]]]],
                                               options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: mcpConfig, options: .atomic)
        }
        return settings.path
    }

    /// Hook event → status.
    static func status(event: String, message: String) -> SessionStatus {
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": return .working
        case "Stop", "StopFailure", "SessionStart": return .idle
        case "PermissionRequest": return .waiting
        case "Notification": return message.lowercased().contains("waiting for your input") ? .idle : .waiting
        case "SessionEnd": return .ended
        default: return .idle
        }
    }

    static func read(_ sessionId: UUID) -> (SessionStatus, Date)? {
        guard let s = try? String(contentsOf: dir.appendingPathComponent(sessionId.uuidString), encoding: .utf8) else { return nil }
        let parts = s.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
        guard parts.count >= 2, let t = Double(parts[1]) else { return nil }
        return (status(event: parts[0], message: parts.count > 2 ? parts[2] : ""), Date(timeIntervalSince1970: t))
    }
}

/// Watches the status folder and updates the sessions.
@MainActor
final class StatusWatcher {
    private var stream: FSEventStreamRef?
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        SessionHooks.install()
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let me = Unmanaged<StatusWatcher>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { me.refresh() }
        }
        if let s = FSEventStreamCreate(nil, cb, &ctx, [SessionHooks.dir.path] as CFArray,
                                       FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
                                       FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) {
            FSEventStreamSetDispatchQueue(s, .main)
            FSEventStreamStart(s)
            stream = s
        }
        // A session still warming up after 20 s: say why on its card (StuckStart.swift).
        stuckTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model?.checkStuckStarts() }
        }
    }
    private var stuckTimer: Timer?

    func refresh() {
        guard let model else { return }
        BranchGuard.shared.update(model)   // a session that ended no longer keeps its checkout watched
        var changed = false
        for s in model.sessions where s.kind == .claude {
            if !s.running { if s.status != .ended { s.status = .ended; changed = true }; continue }
            if let (st, at) = SessionHooks.read(s.id), st != s.status || at != s.statusAt {
                s.status = st; s.statusAt = at; s.stuck = nil; changed = true
            }
        }
        if changed { model.sessionsChanged() }
    }
}

/// macOS notifications (only when the app is not in front, never for test instances).
enum Notify {
    static func ask() {
        guard !CommandLine.arguments.contains("--background") else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    static func send(_ title: String, _ body: String) {
        guard !CommandLine.arguments.contains("--background"), !NSApp.isActive else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
