import Foundation
import SwiftUI

// MARK: - Process check on every stop (choice process-check-action, pick B: nudge Claude once)
//
// When a Claude session stops, Steerify reads its last reply. A question left for the user in the chat that belongs on
// the board (a pick between options, scope, taste) gets one line typed back: "put it on the board with ask_choice".
// Once per stop, never twice in a row for the same session (the reply to a nudge is never nudged: no loops).
// Questions only the chat can answer (a password, a login, "may I run this?") are left alone.
// Apple Intelligence (on-device) tells the two apart; without it a plain rule does. Every check lands in
// <app support>/process-checks.jsonl, for the weekly counts later.

enum ProcessCheck {
    enum Verdict: String { case board = "BOARD", chat = "CHAT", none = "NONE" }

    static var enabled: Bool { Prefs.store.object(forKey: "processCheck") as? Bool ?? true }
    static let nudgeLine = "Steerify check: your last turn ends with a question for me in the chat. Put it on the board with ask_choice (2–4 options, each showing its result, pros and cons), keep building what does not depend on it, then end with where it waits."

    /// The last paragraph of a reply, where an ending question sits.
    static func ending(_ reply: String) -> String {
        let paras = reply.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return paras.suffix(3).joined(separator: "\n")
    }

    /// Free first pass: no question mark at the end → nothing to ask the model.
    static func endsWithQuestion(_ reply: String) -> Bool {
        let last = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[*_`)\\]]+$", with: "", options: .regularExpression)
        return last.hasSuffix("?")
    }

    /// Rule used without Apple Intelligence: chat-only asks are about access and permission.
    static func ruleVerdict(_ reply: String) -> Verdict {
        guard endsWithQuestion(reply) else { return .none }
        let end = ending(reply).lowercased()
        let chatOnly = ["password", "token", "api key", "login", "log in", "sign in", "2fa", "code you", "credentials",
                        "may i", "can i run", "ok to run", "should i proceed", "want me to proceed", "permission", "secret"]
        return chatOnly.contains { end.contains($0) } ? .chat : .board
    }

    static func classify(_ reply: String) async -> Verdict {
        guard endsWithQuestion(reply) else { return .none }
        let end = String(ending(reply).suffix(1200))
        let key = "pcheck1:" + LocalAI.hash(end)
        let ans = await LocalAI.ask(key: key, instructions: """
            A coding assistant ended its turn with this text. Decide where its question belongs.
            BOARD: it asks the user to decide something (pick between options, scope, naming, design, order, yes/no on a feature).
            CHAT: only the user can type the answer (a password, a code, a login, permission to run or deploy something, a fact only they know right now).
            NONE: there is no real question for the user.
            Answer with one word: BOARD, CHAT or NONE.
            """, prompt: end, temperature: 0)
        guard let a = ans?.uppercased() else { return ruleVerdict(reply) }
        if a.contains("BOARD") { return .board }
        if a.contains("CHAT") { return .chat }
        if a.contains("NONE") { return .none }
        return ruleVerdict(reply)
    }

    static func log(_ entry: [String: Any]) {
        let file = ProjectStore.dir.appendingPathComponent("process-checks.jsonl")
        guard let d = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        if let h = try? FileHandle(forWritingTo: file) { h.seekToEndOfFile(); h.write(d + Data("\n".utf8)); try? h.close() }
        else { try? (d + Data("\n".utf8)).write(to: file) }
    }

    /// The last thing Claude said in this conversation.
    static func lastReply(_ claudeId: String) -> String? {
        guard let url = SessionSummaries.transcript(claudeId), let x = SessionSummaries.extract(url) else { return nil }
        return x.replies.last
    }
}

extension AppModel {
    /// A Claude session just stopped (working → idle): check how its turn ended.
    func processCheck(_ s: TerminalSession) {
        guard ProcessCheck.enabled, s.kind == .claude, s.running, let cid = s.claudeId,
              !CommandLine.arguments.contains("--background") || CommandLine.arguments.contains("--process-check-demo") else { return }
        // The transcript gets the last reply a moment after the Stop hook fires.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak s] in
            guard let self, let s, let reply = ProcessCheck.lastReply(cid) else { return }
            let sig = LocalAI.hash(reply)
            guard s.processSig != sig else { return }          // same turn seen already
            s.processSig = sig
            Task { @MainActor in
                let v = await ProcessCheck.classify(reply)
                guard s.running, s.status == .idle else { return }     // you typed in the meantime: your call
                var entry: [String: Any] = ["at": BoardStore.now(), "project": s.projectId, "session": cid, "verdict": v.rawValue,
                                            "ai": LocalAI.ready, "end": String(ProcessCheck.ending(reply).suffix(240))]
                if let r = s.item?.ref { entry["item"] = r }
                switch v {
                case .board where !s.processNudgedLast:
                    s.processNudgedLast = true
                    s.processFlag = "question in chat · nudged"
                    NSLog("steerify process check → \(s.title): nudge")
                    s.submit(ProcessCheck.nudgeLine)
                    entry["action"] = "nudged"
                case .board:
                    // It asked again right after a nudge: no loop, you decide.
                    s.processFlag = "question in chat · still asking"
                    entry["action"] = "flagged"
                default:
                    s.processNudgedLast = false            // a clean turn: the next question may be nudged again
                    s.processFlag = nil
                    entry["action"] = "none"
                }
                ProcessCheck.log(entry)
            }
        }
    }
}

/// On the session row: the last stop check, when it found something.
struct ProcessFlag: View {
    @ObservedObject var session: TerminalSession
    var body: some View {
        if let f = session.processFlag {
            HStack(spacing: 4) {
                Image(systemName: f.hasSuffix("nudged") ? "arrow.uturn.left" : "exclamationmark.triangle.fill").font(.system(size: S(8.5), weight: .bold))
                Text(f).font(.system(size: S(10), weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(f.hasSuffix("nudged") ? Brand.blue : Brand.amber)
            .help(f.hasSuffix("nudged")
                  ? "Claude stopped with a question in the chat. Steerify asked it once to put the question on the board."
                  : "Claude asked again after the nudge. Answer it in the session, or tell it to use the board.")
        }
    }
}
