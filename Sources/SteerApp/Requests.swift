import SwiftUI
import AppKit

// MARK: - New request: one button for anything (fix, refinement, feature, question)
//
// Flow (choice req-flow, pick A): you type it (+ screenshots) → Steerify files it at once, locally and for free
// (kind + matching chapter, with why) → a Claude session starts already briefed and takes it from there.
// Fixes and refinements go to one rolling "Fixes & refinements" chapter per project (req-fixes A); a feature
// becomes a chapter draft that Claude writes and you approve (req-features A). Everything is kept in
// <board>/requests.json so each request stays traceable: where it went, which session, what it became.

enum RequestKind: String, CaseIterable, Identifiable {
    case fix, refine, feature, question
    var id: String { rawValue }
    var label: String { ["fix": "Fix", "refine": "Refinement", "feature": "New feature", "question": "Question"][rawValue]! }
    var color: Color { [.fix: Brand.amber, .refine: Brand.blue, .feature: Brand.green, .question: Brand.cream][self]! }
    /// Where this kind lands, in plain words.
    func destination(_ chapter: String?) -> String {
        switch self {
        case .fix, .refine: return RequestLog.fixesChapter
        case .feature: return "New chapter · Claude drafts it, you approve"
        case .question: return "A choice on the board"
        }
    }
}

/// One request as stored in requests.json.
struct BoardRequest: Identifiable, Hashable {
    let id: String
    let at: String
    let text: String
    let kind: RequestKind
    let chapter: String?          // the feature chapter it is about (fixes link to it)
    let imgs: [String]            // relative to the board folder
    let context: String?          // what you were looking at (ref)
    let contextTitle: String?
    let status: String            // filed | working | done | approved | discarded | <anything Claude writes>
    let became: [String]          // board refs it turned into (road:…, track:…, choice:…, test:…)
    let note: String?             // Claude's one line on what happened
    let area: String?

    var short: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return first.count > 110 ? String(first.prefix(107)) + "…" : first
    }
}

enum RequestLog {
    static let fixesChapter = "Fixes & refinements"
    static func file(_ dir: String) -> String { (dir as NSString).appendingPathComponent("requests.json") }

    static func raw(_ dir: String) -> [[String: Any]] {
        (BoardFiles.json(dir, "requests.json") as? [String: Any])?["items"] as? [[String: Any]] ?? []
    }

    static func load(_ dir: String) -> [BoardRequest] {
        raw(dir).map { r in
            BoardRequest(id: s(r["id"]), at: s(r["at"]), text: s(r["text"]), kind: RequestKind(rawValue: s(r["kind"])) ?? .refine,
                         chapter: r["chapter"] as? String, imgs: r["imgs"] as? [String] ?? [], context: r["context"] as? String,
                         contextTitle: r["contextTitle"] as? String, status: (r["status"] as? String) ?? "filed",
                         became: r["became"] as? [String] ?? [], note: r["note"] as? String, area: r["area"] as? String)
        }.sorted { $0.at > $1.at }
    }

    /// Read-modify-write of one request (creates it when `create`). Returns false if it is not there.
    @discardableResult
    static func edit(_ dir: String, id: String, create: Bool = false, _ change: (inout [String: Any]) -> Void) -> Bool {
        var all = raw(dir)
        if let i = all.firstIndex(where: { $0["id"] as? String == id }) {
            change(&all[i])
        } else if create {
            var r: [String: Any] = ["id": id]; change(&r); all.append(r)
        } else { return false }
        let o: [String: Any] = ["steerify": 1, "items": all]
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return false }
        return (try? d.write(to: URL(fileURLWithPath: file(dir)), options: .atomic)) != nil
    }

    static func now() -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    static func newId() -> String {
        let f = DateFormatter(); f.dateFormat = "yyMMdd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        return "r" + f.string(from: Date())
    }

    private static func s(_ v: Any?) -> String { (v as? String) ?? "" }
}

// MARK: - Local triage (no tokens): kind + matching chapter, with why

struct Triage: Equatable {
    var kind: RequestKind
    var kindWhy: String
    var chapter: String?
    var chapterWhy: String
    var ai = false             // refined by Apple Intelligence (LocalAI.swift)
}

enum RequestTriage {
    static let fixWords = ["bug", "broken", "crash", "crashes", "error", "errors", "fails", "failed", "failing", "wrong", "doesn't", "doesnt",
                           "not working", "isn't", "stuck", "hangs", "hang", "freeze", "frozen", "missing", "regression", "fix", "404", "500",
                           "blank", "disappear", "disappears", "non funziona", "errore", "rotto", "sbagliat", "bloccat", "manca"]
    static let refineWords = ["tweak", "smaller", "bigger", "larger", "colour", "color", "spacing", "padding", "rename", "move", "align",
                              "label", "wording", "polish", "nicer", "cleaner", "clearer", "better", "faster", "shorter", "simpler",
                              "instead", "should be", "too ", "more ", "less ", "a bit", "più", "meno", "sposta"]
    static let featureWords = ["new ", "add ", "support", "integrate", "integration", "would like", "i want", "we need", "feature",
                               "allow", "let me", "ability", "option to", "build ", "create ", "aggiungi", "nuov", "vorrei", "serve "]
    static let questionWords = ["how ", "why ", "should we", "should i", "which ", "what if", "can we", "is it", "does it",
                                "come ", "perché", "quale", "dovremmo"]

    static let stop: Set<String> = ["the", "and", "for", "with", "that", "this", "from", "into", "when", "what", "where", "your", "have",
                                    "should", "would", "could", "there", "them", "they", "then", "than", "just", "only", "also", "some",
                                    "make", "made", "does", "doesn", "isn", "not", "are", "was", "were", "has", "but", "all", "any",
                                    "chapter", "nov", "dec", "oct", "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep"]

    static func words(_ s: String) -> [String] {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { $0.count >= 3 && !stop.contains($0) }
    }

    /// Light stem: "shots" ~ "shot", "labels" ~ "label", "tested" ~ "test".
    static func stem(_ w: String) -> String {
        for suf in ["ings", "ing", "ies", "es", "ed", "s"] where w.count > suf.count + 3 && w.hasSuffix(suf) { return String(w.dropLast(suf.count)) }
        return w
    }

    static func classify(_ text: String, chapters: [(name: String, items: [String])], context: String?) -> Triage {
        let t = " " + text.lowercased() + " "
        func hits(_ list: [String]) -> [String] {
            let h = list.filter { t.contains($0) }
            return h.filter { w in !h.contains { $0 != w && $0.contains(w) } }     // "disappears" covers "disappear"
        }
        let fx = hits(fixWords), rf = hits(refineWords), ft = hits(featureWords), qs = hits(questionWords)
        var score: [RequestKind: Int] = [.fix: fx.count * 2, .refine: rf.count, .feature: ft.count * 2, .question: qs.count]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") { score[.question, default: 0] += 3 }
        let n = words(text).count
        if n > 45 { score[.feature, default: 0] += 2 }      // long, many-sided asks are features more often than not
        let order: [RequestKind] = [.fix, .feature, .question, .refine]
        let best = order.max { (score[$0] ?? 0) < (score[$1] ?? 0) || ((score[$0] ?? 0) == (score[$1] ?? 0) && order.firstIndex(of: $0)! < order.firstIndex(of: $1)!) }!
        var kind = (score[best] ?? 0) == 0 ? RequestKind.refine : best
        if kind == .question && trimmed.hasSuffix("?") == false && (score[.question] ?? 0) < 2 { kind = .refine }
        let quoted: ([String]) -> String = { $0.prefix(3).map { "“\($0.trimmingCharacters(in: .whitespaces))”" }.joined(separator: ", ") }
        let why: String
        switch kind {
        case .fix: why = "Sounds like something broken: " + quoted(fx)
        case .feature: why = ft.isEmpty ? "Long and many-sided: a feature" : "Asks for something new: " + quoted(ft)
        case .question: why = trimmed.hasSuffix("?") ? "Ends with a question mark" : "Asks a question: " + quoted(qs)
        case .refine: why = rf.isEmpty ? "Short change to something that exists" : "A change to something that exists: " + quoted(rf)
        }

        // Chapter: shared words with each chapter's name (×3) and key results (×1); what you were looking at +4.
        let mine = Set(words(text).map(stem))
        var bestCh: (String, Int, [String])? = nil
        for c in chapters where c.name != RequestLog.fixesChapter {
            let nameW = Set(words(c.name).map(stem)), itemW = Set(c.items.flatMap(words).map(stem))
            let inName = mine.intersection(nameW), inItems = mine.intersection(itemW).subtracting(inName)
            var sc = inName.count * 3 + inItems.count
            if c.name == context { sc += 4 }
            if sc > (bestCh?.1 ?? 0) { bestCh = (c.name, sc, Array(inName) + Array(inItems)) }
        }
        var chapter: String? = nil, chWhy = "No chapter matches: Claude will place it"
        if let b = bestCh, b.1 >= 3 {
            chapter = b.0
            let w = b.2.prefix(3).map { "“\($0)”" }.joined(separator: ", ")
            chWhy = b.0 == context ? "You were looking at it" + (w.isEmpty ? "" : " · \(w) match") : "\(b.2.count) word\(b.2.count == 1 ? "" : "s") match: \(w)"
        }
        return Triage(kind: kind, kindWhy: why, chapter: chapter, chapterWhy: chWhy)
    }
}

// MARK: - Filing + the briefed session

@MainActor
extension AppModel {
    /// The roadmap chapter of a board ref (road:, track:, test: via its road links), for triage and context.
    func chapter(of ref: String?, in p: Project) -> String? {
        guard let ref, let item = ItemRef(ref: ref) else { return nil }
        let b = board(for: p)
        switch item.kind {
        case "road": return b.roadmap.first { $0.id == item.id }?.track
        case "track": return b.chapters.first { BoardFiles.slug($0.name) == item.id }?.name
        case "test":
            guard let s = b.ships.first(where: { $0.id == item.id }) else { return nil }
            return s.roads.lazy.compactMap { r in b.roadmap.first { $0.text == r || $0.id == BoardFiles.slug(r) }?.track }.first
        case "request": return RequestLog.load(p.boardDir).first { $0.id == item.id }?.chapter
        default: return nil
        }
    }

    /// File a request: save screenshots + the request, put fixes/refinements on the rolling chapter at once,
    /// then (unless `fileOnly`) start the briefed Claude session. Returns the request id.
    @discardableResult
    func fileRequest(projectId: String, text: String, kind: RequestKind, chapter: String?, images: [URL],
                     context: String?, contextTitle: String?, fileOnly: Bool) -> String? {
        guard let p = projects.first(where: { $0.id == projectId }) else { return nil }
        let b = board(for: p)
        let id = RequestLog.newId()
        let area = chapter.flatMap { c in b.chapters.first { $0.name == c }?.area } ?? b.areas.first?.key
        // Screenshots into the board (img/requests/<id>-n.png), so Claude and the history can open them later.
        let rel = "img/requests"
        try? FileManager.default.createDirectory(atPath: (p.boardDir as NSString).appendingPathComponent(rel), withIntermediateDirectories: true)
        var imgs: [String] = []
        for (i, u) in images.enumerated() {
            let ext = u.pathExtension.isEmpty ? "png" : u.pathExtension.lowercased()
            let r = "\(rel)/\(id)-\(i + 1).\(ext)"
            if (try? FileManager.default.copyItem(atPath: u.path, toPath: (p.boardDir as NSString).appendingPathComponent(r))) != nil { imgs.append(r) }
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var became: [String] = []
        // Fixes and refinements: a key result on the rolling chapter, right now (free, local).
        if kind == .fix || kind == .refine {
            let first = clean.split(whereSeparator: \.isNewline).first.map(String.init) ?? clean
            var line = (kind == .fix ? "Fix: " : "") + (first.count > 120 ? String(first.prefix(117)) + "…" : first)
            if b.roadmap.contains(where: { $0.text == line }) { line += " (\(id))" }
            let r = SteerifyMCP.call("add_roadmap_item", ["chapter": RequestLog.fixesChapter, "text": line, "status": "todo",
                                                          "area": area ?? "", "request": id, "for": chapter ?? "", "create": true], board: p.boardDir)
            if !r.1 { became.append("road:" + BoardFiles.slug(line)) }
        }
        RequestLog.edit(p.boardDir, id: id, create: true) { r in
            r["at"] = RequestLog.now(); r["text"] = clean; r["kind"] = kind.rawValue
            r["chapter"] = chapter; r["imgs"] = imgs; r["context"] = context; r["contextTitle"] = contextTitle
            r["status"] = fileOnly ? "filed" : "working"; r["became"] = became; r["area"] = area
        }
        b.reload()
        if !fileOnly { startRequestSession(projectId: p.id, id: id) }
        return id
    }

    /// Start (or reopen) the Claude session of a request, briefed with everything Steerify knows.
    func startRequestSession(projectId: String, id: String) {
        guard let p = projects.first(where: { $0.id == projectId }),
              let r = RequestLog.load(p.boardDir).first(where: { $0.id == id }) else { return }
        var item = ItemRef(ref: "request:" + id)!
        item.title = "Request: " + r.short
        item.area = r.area
        RequestLog.edit(p.boardDir, id: id) { $0["status"] = ($0["status"] as? String) == "filed" ? "working" : $0["status"] }
        // Test copies (`--dry-sessions`) print the command instead of starting Claude (and the brief to stderr).
        if CommandLine.arguments.contains("--dry-sessions") { FileHandle.standardError.write(("BRIEF\n" + requestBrief(r, in: p) + "\n").data(using: .utf8)!) }
        start(projectId: p.id, item: item, intent: .intake, dry: CommandLine.arguments.contains("--dry-sessions"), extraBrief: requestBrief(r, in: p))
    }

    /// Everything the session needs so it never asks what the request is.
    func requestBrief(_ r: BoardRequest, in p: Project) -> String {
        let b = board(for: p)
        var out = ["NEW REQUEST from the user (filed by Steerify, \(r.at.prefix(16).replacingOccurrences(of: "T", with: " "))), id \(r.id):",
                   "\"\"\"\n\(r.text)\n\"\"\"",
                   "Kind: \(r.kind.label) (Steerify's local triage; the user saw it and could change it).",
                   "Destination: \(r.kind.destination(r.chapter))."]
        if !r.imgs.isEmpty {
            out.append("Screenshots (open each one): " + r.imgs.map { (p.boardDir as NSString).appendingPathComponent($0) }.joined(separator: " "))
        }
        if let c = r.context { out.append("The user was looking at \(c)" + (r.contextTitle.map { " (\"\($0)\")" } ?? "") + ".") }
        if r.kind == .fix || r.kind == .refine, let road = r.became.first(where: { $0.hasPrefix("road:") }),
           let it = b.roadmap.first(where: { "road:" + $0.id == road }) {
            out.append("Already filed as the key result \"\(it.text)\" in the chapter \"\(RequestLog.fixesChapter)\" (mark it wip / review / done with set_roadmap_status).")
        }
        if let c = r.chapter {
            let items = b.roadmap.filter { $0.track == c }
            out.append("Matching chapter \"\(c)\" — key results:\n" + items.map { "- [\($0.status)] \($0.text)" }.joined(separator: "\n"))
            if let g = b.requirements.first(where: { b.roadChapter(for: $0.group)?.name == c })?.group {
                out.append("Its requirements (\(g)):\n" + b.requirements.filter { $0.group == g }.map { "- \($0.id) [\($0.status)] \($0.text)" }.joined(separator: "\n"))
            }
            let related = b.ships.filter { s in s.roads.contains { rd in items.contains { $0.text == rd || $0.id == BoardFiles.slug(rd) } } }.prefix(6)
            if !related.isEmpty { out.append("Related To test items: " + related.map { "test:\($0.id) (\($0.title))" }.joined(separator: ", ")) }
        } else {
            out.append("Chapters on the roadmap: " + b.chapters.filter { !$0.draft }.map { "\"\($0.name)\"" }.joined(separator: ", "))
        }
        out.append("Follow the steerify skill, intent `intake`. When it has a home, call update_request (id \(r.id)) with status + became[] + one line of note.")
        return out.joined(separator: "\n\n")
    }

    /// Where a request stands now, in a few words, from the board itself.
    func requestState(_ r: BoardRequest, in p: Project) -> (String, Color) {
        let b = board(for: p)
        if sessions.contains(where: { $0.projectId == p.id && $0.covers("request:" + r.id) && $0.running && $0.status == .working }) { return ("Claude on it", Brand.claude) }
        if let ch = b.chapters.first(where: { $0.request == r.id }) { return ch.draft ? ("draft to approve", Brand.amber) : ("chapter on the roadmap", Brand.green) }
        if let road = r.became.first(where: { $0.hasPrefix("road:") }), let it = b.roadmap.first(where: { "road:" + $0.id == road }) {
            let l = ["done": "done", "review": "to test", "wip": "in progress", "you": "waits on you", "todo": "to do"][it.status] ?? it.status
            return (l, it.status == "done" ? Brand.green : it.status == "todo" ? Brand.mute : Brand.amber)
        }
        if let c = r.became.first(where: { $0.hasPrefix("choice:") }), let d = b.decisions.first(where: { "choice:" + $0.id == c }) {
            return b.isDecided(d) ? ("choice answered", Brand.green) : ("choice to make", Brand.amber)
        }
        switch r.status {
        case "discarded": return ("discarded", Brand.mute)
        case "done": return ("done", Brand.green)
        case "filed": return ("filed · no session", Brand.mute)
        case "needs-you": return ("waits on you", Brand.amber)
        case "working": return ("in progress", Brand.cream)
        case "approved": return ("on the roadmap", Brand.green)
        default: return (r.status, Brand.cream)
        }
    }
}
