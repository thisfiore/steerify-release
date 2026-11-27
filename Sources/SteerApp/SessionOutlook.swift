import Foundation
import SwiftUI

// MARK: - When is an idle session done? (choice session-done-rule, request r261120-082945)
//
// An idle Claude session is done unless it still needs something that lives only in its chat:
// · Claude asks you something that is not on the board            → stays ("asks you: …")
// · Claude names a next step it would take                        → stays ("next: …", Go on sends it)
// · what it waits on is on the board (To test, a choice, release) → done
// · nothing left to do                                            → done
// · a newer session took the same feature / chapter               → done ("→ taken over by …")
// Read from Claude's last reply in the transcript (no tokens spent), cached by file size.

enum SessionOutlook: Equatable {
    case nothing
    case onBoard(String)
    case takenOver(String)
    case ask(String)
    case next(String)
    /// Its turn ended but background shells it started still run (Claude carries on when they finish): not done.
    case shells(Int)

    var isDone: Bool { switch self { case .nothing, .onBoard, .takenOver: return true; case .ask, .next, .shells: return false } }

    /// The short line under the session's name.
    var line: String {
        switch self {
        case .nothing: return "done · nothing left"
        case .onBoard(let w): return "done · waits on \(w)"
        case .takenOver(let by): return "done · → \(by)"
        case .ask(let t): return "asks you: " + t
        case .next(let t): return "next: " + t
        case .shells(let n): return "waiting · \(n) shell\(n == 1 ? "" : "s") still running"
        }
    }
}

enum SessionOutlookReader {
    // MARK: Claude's last reply (tail of the transcript)

    nonisolated(unsafe) private static var urls: [String: URL] = [:]
    nonisolated(unsafe) private static var memo: [String: (size: Int, outlook: SessionOutlook?)] = [:]

    /// The reading of a conversation's last reply, nil when there is no transcript or no reply yet.
    static func outlook(claudeId: String) -> SessionOutlook? {
        if urls[claudeId] == nil, let u = SessionSummaries.transcript(claudeId) { urls[claudeId] = u }
        guard let url = urls[claudeId] else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if let m = memo[claudeId], m.size == size { return m.outlook }
        let o = lastReply(url).map(classify)
        memo[claudeId] = (size, o)
        return o
    }

    /// The assistant text of the last turn (after the last human message), read from the end of the file.
    static func lastReply(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        let chunk: UInt64 = 400_000
        try? h.seek(toOffset: end > chunk ? end - chunk : 0)
        guard let data = try? h.readToEnd(), let s = String(data: data, encoding: .utf8) else { return nil }
        var texts: [String] = []
        for line in s.split(separator: "\n").reversed() {
            guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\""),
                  let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  o["isSidechain"] as? Bool != true, let msg = o["message"] as? [String: Any] else { continue }
            if o["type"] as? String == "user" {
                // A tool result is part of the turn; a typed message ends it.
                if let parts = msg["content"] as? [[String: Any]], parts.allSatisfy({ $0["type"] as? String == "tool_result" }) { continue }
                break
            }
            if let parts = msg["content"] as? [[String: Any]] {
                for p in parts.reversed() where p["type"] as? String == "text" { if let t = p["text"] as? String { texts.insert(t, at: 0) } }
            }
            if !texts.isEmpty && texts.joined().count > 40 { break }     // the closing words are enough
        }
        let out = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    // MARK: Reading it

    private static func has(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    /// Things that already have a place on the board.
    static let boardWords = #"to test|choices? tab|\bchoices?\b|on the board|release tab|\bverdict|your pick|\bpick\b|ready to build|\bdeliver(ed|y)?\b|\bship (it|them)\b|release (it|them)|roadmap|key result|requirements? tab"#
    /// A question or a request for you.
    static let askWords = #"\?|\b(let me know|tell me|your call|please (confirm|check|choose|decide)|i need (you|your))\b"#
    /// An offer or a step Claude would take next.
    static let nextWords = #"\b(want me to|shall i|should i|would you like( me)? to|i can (also |now |then )?(do|start|build|fix|add|move|go)|next step:|next step would be|the next step is to|next up|next:|next,|then i('ll| will))(?!\w)"#

    /// Sentences, without code, links or markdown.
    static func sentences(_ text: String) -> [String] {
        var t = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*\\*|`|^#+ ", with: "", options: .regularExpression)
        var out: [String] = []
        for line in t.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "^[-*•] |^\\d+\\. ", with: "", options: .regularExpression)
            guard !l.isEmpty, !l.hasPrefix("|") else { continue }
            // Split after . ? ! followed by a space and a capital.
            let parts = l.replacingOccurrences(of: "([.?!])\\s+(?=[A-Z])", with: "$1\u{1}", options: .regularExpression).split(separator: "\u{1}")
            out += parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return out
    }

    static func short(_ s: String, max: Int = 90) -> String {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        return t.count > max ? String(t.prefix(max - 1)) + "…" : t
    }

    /// What the last reply leaves open.
    static func classify(_ text: String) -> SessionOutlook {
        let ss = sentences(text)
        // The closing part of the reply is where a question or next step lives.
        let tail = Array(ss.suffix(6))
        let open = tail.filter { has($0, askWords) || has($0, nextWords) }
        let loose = open.filter { !has($0, boardWords) }
        if let n = loose.first(where: { has($0, nextWords) }) {
            return .next(short(n.replacingOccurrences(of: #"^(next step|next)\s*:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])))
        }
        if let a = loose.first { return .ask(short(a)) }
        if let b = (open + tail.reversed()).first(where: { has($0, boardWords) }) { return .onBoard(boardPlace(b)) }
        return .nothing
    }

    /// "To test", "a choice", "the release"… from the sentence that points at the board.
    static func boardPlace(_ s: String) -> String {
        if has(s, #"to test|\bverdict|\bdeliver"#) { return "To test" }
        if has(s, #"choice|\bpick\b"#) { return "a choice" }
        if has(s, #"release|\bship\b"#) { return "the release" }
        if has(s, #"requirement"#) { return "requirements" }
        return "the board"
    }
}

extension BoardStore {
    /// Chapter slugs an item belongs to: the chapter itself, or the chapters of its key results.
    func chapters(of ref: String) -> Set<String> { memoized("chapters:" + ref) { computeChapters(of: ref) } }
    private func computeChapters(of ref: String) -> Set<String> {
        if ref.hasPrefix("track:") || ref.hasPrefix("reqs:") { return [String(ref.split(separator: ":", maxSplits: 1)[1])] }
        let roadIds = Set(roads(of: ref).map { String($0.dropFirst("road:".count)) })
        return Set(roadmap.filter { roadIds.contains($0.id) }.map { BoardFiles.slug($0.track) })
    }

    /// A newer conversation started on the same feature or chapter (not this one).
    func takenOver(item: String, claudeId: String?) -> SessionLink? {
        // Asked for every session chip on every redraw (40% of the main thread on 20 Nov).
        memoized("takenOver:" + item + "|" + (claudeId ?? "")) { computeTakenOver(item: item, claudeId: claudeId) }
    }
    private func computeTakenOver(item: String, claudeId: String?) -> SessionLink? {
        let mine = links.filter { $0.claudeSession == claudeId }.map(\.started).max()
            ?? links.filter { $0.item == item }.map(\.started).min()
        guard let since = mine else { return nil }
        let thread = thread(of: item)
        // Same chapter counts when one of the two sessions is about the whole chapter (Resume, Tidy); two sessions on
        // different key results of a chapter are different work. The rolling fixes chapter never links anything.
        let fixes = BoardFiles.slug(RequestLog.fixesChapter)
        func isChapter(_ r: String) -> Bool { r.hasPrefix("track:") || r.hasPrefix("reqs:") }
        let chs = chapters(of: item).subtracting([fixes])
        return links.filter { l in
            guard l.claudeSession != claudeId, l.started > since else { return false }
            // A release session ships the item: a hand-off, not a take-over (ShipHandoff.swift: shipping, then released).
            if l.intent == "ship" { return false }
            if thread.contains(l.item) { return true }
            return (isChapter(item) || isChapter(l.item)) && !chs.isDisjoint(with: chapters(of: l.item))
        }.max { $0.started < $1.started }
    }
}

extension AppModel {
    /// What an idle Claude session still needs (nil: not idle, not Claude, or no reply to read).
    func outlook(_ s: TerminalSession) -> SessionOutlook? {
        // One look at the transcript per session per draw (it was asked 5–10 times: chips, order, menu bar, tab counts).
        TurnMemo.get("outlook:\(s.id)") { readOutlook(s) }
    }
    private func readOutlook(_ s: TerminalSession) -> SessionOutlook? {
        guard s.kind == .claude, s.running, s.status == .idle else { return nil }
        if let n = s.backgroundShells { return .shells(n) }      // request r261127-154245
        if let item = s.item, let p = projects.first(where: { $0.id == s.projectId }),
           let l = board(for: p).takenOver(item: item.ref, claudeId: s.claudeId) {
            return .takenOver(SessionName.short(l.title ?? l.item, intent: l.intent))
        }
        guard let id = s.claudeId else { return nil }
        return SessionOutlookReader.outlook(claudeId: id)
    }

    /// Go on: tell an idle session to take the next step it named.
    func goOn(_ s: TerminalSession) {
        guard s.status == .idle, case .next(let n)? = outlook(s) else { return }
        s.submit("Go ahead with the next step you named (\(n)). If it needs my decision, put it on the board as a choice.")
    }
}

// MARK: - Test hook: `Steerify --outlook-check <workspace folder>` prints the reading of every linked conversation.
enum SessionOutlookCheck {
    @MainActor static func run(_ folder: String) {
        guard let p = ProjectStore.read(folder) else { print("no steerify.json in \(folder)"); return }
        let b = BoardStore(project: Project(id: p.id, name: p.name, boardDir: p.boardDir, port: 0, repos: p.repos))
        var seen = Set<String>()
        for l in b.links.reversed() where seen.insert(l.claudeSession).inserted {
            let name = SessionName.short(l.title ?? l.item, intent: l.intent)
            let taken = b.takenOver(item: l.item, claudeId: l.claudeSession)
            let o = taken.map { SessionOutlook.takenOver(SessionName.short($0.title ?? $0.item, intent: $0.intent)) }
                ?? SessionOutlookReader.outlook(claudeId: l.claudeSession)
            print("\(o.map { $0.isDone ? "DONE " : "OPEN " } ?? "---- ") \(l.started.prefix(16)) \(name)  ·  \(o?.line ?? "(no transcript)")")
        }
        fflush(stdout)
    }
}

// MARK: - Your turn on the board (choice session-status-colors, request r261120-174008)
//
// "Waits on the board" is not done: something of yours is open there (a test, a choice, a release). The session
// stays in the list in its own colour with a button that opens that item; only sessions with nothing left are
// grey, ticked and closed by "Close N done". Rowing is blue, needs you (in the chat) amber.

/// The board item of a session's work that waits on you, and the button that opens it.
struct BoardTurn: Equatable {
    let ref: String
    let verb: String
    let tab: BoardTab
}

extension BoardStore {
    func yourTurn(of refs: [String]) -> BoardTurn? {
        guard !refs.isEmpty else { return nil }
        return memoized("turn:" + refs.joined(separator: "|")) { computeTurn(refs) }
    }
    private func computeTurn(_ refs: [String]) -> BoardTurn? {
        var all = Set<String>()
        for r in refs { all.formUnion(thread(of: r)) }
        let tests = ships.filter { all.contains("test:" + $0.id) }
        if let t = tests.first(where: { [.toTest, .retest].contains(shipState($0)) }) {
            return BoardTurn(ref: "test:" + t.id, verb: "Test", tab: .test)
        }
        if let c = decisions.first(where: { all.contains("choice:" + $0.id) && !isDecided($0) && !isParked($0) }) {
            return BoardTurn(ref: "choice:" + c.id, verb: "Answer", tab: .choice)
        }
        if let t = tests.first(where: { shipState($0) == .ok && $0.status != "live" }) {
            return BoardTurn(ref: "release:" + t.id, verb: "Release", tab: .release)
        }
        return nil
    }
}

extension AppModel {
    /// Idle and its work waits on you on the board (nil while it rows, asks in the chat, names a next step, or was taken over).
    func yourTurn(_ s: TerminalSession) -> BoardTurn? {
        guard s.kind == .claude, s.running, s.status == .idle, let item = s.item,
              let p = projects.first(where: { $0.id == s.projectId }) else { return nil }
        switch outlook(s) {
        case .ask?, .next?, .takenOver?, .shells?: return nil
        default: return handedOff(s) ? nil : board(for: p).yourTurn(of: [item.ref] + s.alsoRefs)
        }
    }
}

// MARK: - Background shells still running (request r261127-154245-fb3486e7)
//
// Claude Code ends a turn while shells it started in the background still run ("done 4:12 PM · 2 shells still
// running", footer "· 2 shells · ↓ to manage") and picks up again when they finish. Only its footer says so: read the
// bottom rows of the terminal (a copied read, no selection).
extension TerminalSession {
    var backgroundShells: Int? {
        guard kind == .claude, running else { return nil }
        // The footer sits under the last output: the bottom of the screen, or higher up while the screen is not full.
        let rows = view.terminalDimensions.rows
        let lines = view.visibleRowsText(0..<rows).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return Self.shells(in: Array(lines.suffix(6)))
    }

    /// "· 2 shells", "2 shells still running", "1 background shell" → 2 / 1; nil when none. Rows are joined as they
    /// are (a narrow terminal wraps "2 shells" over two rows).
    static func shells(in lines: [String]) -> Int? {
        let text = lines.joined()
        let ms = text.ranges(of: #/\b([1-9][0-9]?) (?:background )?(?:shells?|bash(?:es)?)\b(?! (?:was|were|done|finished|completed))/#.ignoresCase())
        guard let r = ms.last else { return nil }
        return Int(text[r].prefix { $0.isNumber })
    }
}

/// Test hook `--background --shells-demo <item ref>`: a dry session on the item, idle, whose terminal shows Claude Code's
/// "2 shells still running" footer: logs whether it counts as done, then again once the footer is gone.
enum ShellsDemo {
    static func log(_ s: String) { FileHandle.standardError.write(("[shells] " + s + "\n").data(using: .utf8)!) }
    @MainActor static func run(_ m: AppModel, _ r: String) {
        guard CommandLine.arguments.contains("--background"), let p = m.project, let ref = ItemRef(ref: r),
              let s = m.start(projectId: p.id, item: ref, intent: .build, dry: true) else { log("no session"); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            s.view.feed(text: "\u{1b}[2J\u{1b}[H")
            s.view.feed(text: "* Churned for 3m 46s · done 4:12 PM · 2 shells still running\r\n\r\n> \r\n>> auto mode on · 2 shells · ↓ to manage\r\n")
            s.status = .idle; s.statusAt = Date().addingTimeInterval(-600)
            TurnMemo.clear(); m.sessionsChanged()
            log("footer on: shells=\(String(describing: s.backgroundShells)) line=\(m.outlook(s)?.line ?? "-") wrapped=\(m.isWrapped(s)) closeable=\(m.wrappedSessions(of: p.id).count)")
            if CommandLine.arguments.contains("--shells-keep") { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                s.view.feed(text: "\u{1b}[2J\u{1b}[H* Churned for 9m 2s · done 4:21 PM\r\n\r\n> \r\n>> auto mode on\r\n")
                TurnMemo.clear(); m.sessionsChanged()
                log("footer off: shells=\(String(describing: s.backgroundShells)) line=\(m.outlook(s)?.line ?? "-") wrapped=\(m.isWrapped(s))")
            }
        }
    }
}
