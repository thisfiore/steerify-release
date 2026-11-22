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
    case fix, refine, feature, task, question
    var id: String { rawValue }
    var label: String { ["fix": "Fix", "refine": "Refinement", "feature": "New feature", "task": "Task", "question": "Question"][rawValue]! }
    var color: Color { [.fix: Brand.amber, .refine: Brand.blue, .feature: Brand.green, .task: Brand.claude, .question: Brand.cream][self]! }
    /// The standard in one line per kind: shown on the pills and given to Apple Intelligence.
    var rule: String {
        switch self {
        case .fix: return "Something in the product is broken, wrong or does nothing. Result: code fixed."
        case .refine: return "A change to something the product already has: layout, wording, flow, behaviour. Result: code changed."
        case .feature: return "A capability the product does not have yet. Result: new code, planned as a chapter."
        case .task: return "Work done WITH the product or the team's tools, not ON it: a report, a tutorial, a data collection, sending something. Result: a file, a list or counts. No code changes."
        case .question: return "The user asks what to do or how something works. Result: an answer or a choice."
        }
    }
    /// Where this kind lands, in plain words.
    func destination(_ chapter: String?) -> String {
        switch self {
        case .fix, .refine: return RequestLog.fixesChapter
        case .feature: return "New chapter · Claude drafts it, you approve"
        case .task: return "Tasks · Claude does it, you check the result"
        case .question: return "A choice on the board"
        }
    }
}

/// The triage standard, refreshed by the board itself: every request whose kind was changed (by you in the sheet,
/// or by Claude at intake) is a lesson. The words use them for near-identical asks, Apple Intelligence sees the latest ones.
enum TriageLessons {
    struct Lesson { let text: String; let from: RequestKind; let to: RequestKind }

    static func load(_ dir: String, max: Int = 10) -> [Lesson] {
        RequestLog.raw(dir).compactMap { r -> (String, Lesson)? in
            guard let t = r["text"] as? String, let to = RequestKind(rawValue: r["kind"] as? String ?? ""),
                  let from = RequestKind(rawValue: r["guess"] as? String ?? ""), from != to else { return nil }
            return ((r["updated"] as? String) ?? (r["at"] as? String) ?? "", Lesson(text: t, from: from, to: to))
        }.sorted { $0.0 > $1.0 }.prefix(max).map(\.1)
    }

    /// A past correction that is almost the same ask (≥ 55% of the words shared).
    static func match(_ text: String, in lessons: [Lesson]) -> Lesson? {
        let mine = Set(RequestTriage.words(text).map(RequestTriage.stem))
        guard mine.count >= 4 else { return nil }
        return lessons.max { a, b in overlap(mine, a.text) < overlap(mine, b.text) }.flatMap { overlap(mine, $0.text) >= 0.55 ? $0 : nil }
    }

    private static func overlap(_ mine: Set<String>, _ other: String) -> Double {
        let theirs = Set(RequestTriage.words(other).map(RequestTriage.stem))
        return Double(mine.intersection(theirs).count) / Double(max(1, mine.union(theirs).count))
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
    var title: String? = nil      // 2–4 words naming it (Apple Intelligence), written once when its session starts

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

    /// The file is read and parsed once per draw: "is this request finished" asks for it per session, per row.
    @MainActor static func cached(_ dir: String) -> [BoardRequest] { TurnMemo.get("requests:" + dir) { load(dir) } }
    static func load(_ dir: String) -> [BoardRequest] {
        raw(dir).map { r in
            BoardRequest(id: s(r["id"]), at: s(r["at"]), text: s(r["text"]), kind: RequestKind(rawValue: s(r["kind"])) ?? .refine,
                         chapter: r["chapter"] as? String, imgs: r["imgs"] as? [String] ?? [], context: r["context"] as? String,
                         contextTitle: r["contextTitle"] as? String, status: (r["status"] as? String) ?? "filed",
                         became: r["became"] as? [String] ?? [], note: r["note"] as? String, area: r["area"] as? String,
                         title: r["title"] as? String)
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
    var options: [String] = [] // closest chapters by words, best first (the menu lists them first; the model picks among them)
}

/// A chapter as triage sees it: its name, key results, and objective (for the model).
typealias TriageChapter = (name: String, items: [String], about: String)

extension BoardStore {
    var triageChapters: [TriageChapter] {
        chapters.filter { !$0.draft }.map { c in (name: c.name, items: roadmap.filter { $0.track == c.name }.map(\.text), about: c.objective ?? "") }
    }
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
    /// Doing, not building (choice tasks-place): an outcome with existing tools and standards, often repeating.
    /// Not "process" / "schedule" / "standard" alone: in product talk they mean the app's flow ("double step slows the process").
    static let taskWords = ["process the ", "process all", "process these", "process our", "collect", "collection", "download ", "scrape",
                            "every day", "every week", "every monday", "every morning", "weekly", "daily", "each week", "each month",
                            "monthly", "recurring", "our sop", "standard operating", "tutorial with", "make a tutorial", "record a tutorial",
                            "prepare ", "send the", "send a ", "report on", "weekly report", "newsletter", "run our", "using our",
                            "with our tools", "data collection", "ogni settimana", "ogni giorno", "settimanal", "raccogli", "prepara ", "procedura"]
    /// Words about the app's own screens: a request full of them is about changing the product, not a task done with it.
    static let productWords = ["button", "tab", "modal", "screen", "view", "card", "ui", "ux", "layout", "label", "pill", "sheet", "menu",
                               "toolbar", "top bar", "sidebar", "shortcut", "cmd", "click", "session", "roadmap", "choice", "column",
                               "overlay", "toast", "notification", "badge", "the app", "steerify", "classif", "triage", "apple intelligence"]
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

    static func classify(_ text: String, chapters: [TriageChapter], context: String?, lessons: [TriageLessons.Lesson] = []) -> Triage {
        let t = " " + text.lowercased() + " "
        func hits(_ list: [String]) -> [String] {
            let h = list.filter { t.contains($0) }
            return h.filter { w in !h.contains { $0 != w && $0.contains(w) } }     // "disappears" covers "disappear"
        }
        let fx = hits(fixWords), rf = hits(refineWords), ft = hits(featureWords), qs = hits(questionWords), tk = hits(taskWords)
        var score: [RequestKind: Int] = [.fix: fx.count * 2, .refine: rf.count, .feature: ft.count * 2, .question: qs.count, .task: tk.count * 2]
        // Talking about the app's own screens = changing the product: a task needs more than one task word to win then.
        let pw = productWords.filter { w in t.range(of: "\\b" + NSRegularExpression.escapedPattern(for: w), options: .regularExpression) != nil }
        if !pw.isEmpty { score[.task] = max(0, tk.count * 2 - 2 * min(pw.count, 2)) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?") { score[.question, default: 0] += 3 }
        let n = words(text).count
        if n > 45 { score[.feature, default: 0] += 2 }      // long, many-sided asks are features more often than not
        let order: [RequestKind] = [.fix, .feature, .task, .question, .refine]
        let best = order.max { (score[$0] ?? 0) < (score[$1] ?? 0) || ((score[$0] ?? 0) == (score[$1] ?? 0) && order.firstIndex(of: $0)! < order.firstIndex(of: $1)!) }!
        var kind = (score[best] ?? 0) == 0 ? RequestKind.refine : best
        if kind == .question && trimmed.hasSuffix("?") == false && (score[.question] ?? 0) < 2 { kind = .refine }
        let quoted: ([String]) -> String = { $0.prefix(3).map { "“\($0.trimmingCharacters(in: .whitespaces))”" }.joined(separator: ", ") }
        var why: String
        let lesson = TriageLessons.match(text, in: lessons)
        if let l = lesson { kind = l.to }
        switch kind {
        case .fix: why = "Sounds like something broken: " + quoted(fx)
        case .feature: why = ft.isEmpty ? "Long and many-sided: a feature" : "Asks for something new: " + quoted(ft)
        case .task: why = "Something to do, not to build: " + quoted(tk)
        case .question: why = trimmed.hasSuffix("?") ? "Ends with a question mark" : "Asks a question: " + quoted(qs)
        case .refine: why = rf.isEmpty ? "Short change to something that exists" : "A change to something that exists: " + quoted(rf)
        }
        if lesson != nil { why = "Like a request you filed as \(kind.label.lowercased()) before" }
        else if kind != .task && !tk.isEmpty && !pw.isEmpty { why += " · about the app (\(quoted(pw))), so not a task" }

        let (chapter, chWhy, options) = pickChapter(text, chapters: chapters, context: context)
        return Triage(kind: kind, kindWhy: why, chapter: chapter, chapterWhy: chWhy, options: options)
    }

    // MARK: Chapter by words
    // Measured on 44 real requests of this board (r261121-233830): the old count of shared words was wrong 19 times
    // ("can", "area", "work" matched anything; big chapters won by size; "you were looking at it" alone was enough).
    // Now: rare words weigh more (a word every chapter has weighs ~0), chatter is dropped, ⌘N = CMD+N, and a chapter
    // is named only when it clearly beats the next one. Otherwise: no chapter, with the closest ones offered.

    /// Words that say nothing about which feature a request is about.
    static let chatter: Set<String> = ["can", "need", "want", "like", "very", "bit", "more", "less", "now", "you", "new", "app", "steerify",
        "claude", "work", "never", "after", "before", "first", "right", "start", "open", "keep", "see", "get", "got", "one", "two", "way",
        "thing", "stuff", "case", "lot", "much", "really", "nice", "better", "good", "think", "maybe", "probably", "sure", "always", "still",
        "even", "here", "its", "our", "let", "lets", "use", "using", "used", "don", "dont", "why", "how", "which", "who", "will", "been",
        "being", "same", "other", "every", "each", "give", "put", "take", "show", "shown", "look", "looking", "goes", "doing", "done",
        "about", "over", "under", "via", "per", "out", "off", "yes", "time", "pretty", "please", "because", "these", "those", "something"]
    /// Different words, one topic (prefix → topic).
    static let sameTopic: [(String, String)] = [("iphone", "phone"), ("ios", "phone"), ("mobile", "phone"), ("testflight", "phone"),
        ("screenshot", "shot"), ("screencapture", "shot"), ("pictur", "shot"), ("image", "shot"),
        ("lag", "slow"), ("slow", "slow"), ("perf", "slow"), ("fast", "slow"), ("instant", "slow"),
        ("suggest", "triag"), ("guess", "triag"), ("classif", "triag"), ("intellig", "triag"), ("triag", "triag")]

    /// The words of a text that can tell features apart: stemmed, chatter out, shortcuts as one word ("CMD+N" = "⌘N" = kbdn).
    static func topicWords(_ s: String) -> Set<String> {
        let low = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "⌘", with: " ⌘")
            .replacingOccurrences(of: #"(?:cmd|command|⌘)\s*\+?\s*([a-z0-9])\b"#, with: " kbd$1 ", options: .regularExpression)
        var out = Set<String>()
        for raw in low.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        where (raw.count >= 3 || raw.hasPrefix("kbd")) && !stop.contains(raw) && !chatter.contains(raw) {
            var w = stem(raw)
            if chatter.contains(w) { continue }
            if let t = sameTopic.first(where: { w.hasPrefix($0.0) }) { w = t.1 }
            out.insert(w)
        }
        return out
    }

    /// The chapter a request is about, why, and the closest chapters (best first, up to 3).
    static func pickChapter(_ text: String, chapters: [TriageChapter], context: String?) -> (String?, String, [String]) {
        let chs = chapters.filter { $0.name != RequestLog.fixesChapter }
        let vocab = chs.map { c in (c.name, topicWords(c.name), topicWords(c.items.joined(separator: " \n "))) }
        var df: [String: Int] = [:]
        for v in vocab { for w in v.1.union(v.2) { df[w, default: 0] += 1 } }
        let n = Double(chs.count + 1)
        func weight(_ w: String) -> Double { log(n / Double(df[w] ?? 1)) }
        let mine = topicWords(text)
        let scored = vocab.map { (name, inName, inItems) -> (name: String, score: Double, words: [String]) in
            let a = mine.intersection(inName), b = mine.intersection(inItems).subtracting(a)
            var sc = a.reduce(0) { $0 + 2 * weight($1) } + b.reduce(0) { $0 + weight($1) }
            if sc > 0 && name == context { sc += 1 }      // what you were looking at helps a chapter that matches, never alone
            return (name, sc, a.union(b).sorted { weight($0) > weight($1) })
        }.sorted { $0.score > $1.score }
        let options = scored.prefix(3).filter { $0.score > 0 }.map(\.name)
        guard let best = scored.first, best.score > 0 else { return (nil, "No chapter matches: Claude will place it", []) }
        let second = scored.count > 1 ? scored[1].score : 0
        let shown = best.words.prefix(3).map { "“\($0.hasPrefix("kbd") ? "⌘" + $0.dropFirst(3).uppercased() : $0)”" }.joined(separator: ", ")
        if best.score >= 2.5 && best.score - second >= 1.5 {
            return (best.name, best.name == context ? "You were looking at it · \(shown) match" : "Its words: \(shown)", options)
        }
        return (nil, "No clear chapter: Claude will place it (or pick one)", options)
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
    func fileRequest(projectId: String, text: String, kind: RequestKind, guess: RequestKind? = nil, chapter: String?, images: [URL],
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
            r["guess"] = (guess ?? kind).rawValue      // what Steerify suggested: a different kind is a lesson (TriageLessons)
            r["chapter"] = chapter; r["imgs"] = imgs; r["context"] = context; r["contextTitle"] = contextTitle
            r["status"] = fileOnly ? "filed" : "working"; r["became"] = became; r["area"] = area
        }
        b.reload()
        // Filed for another project (menu bar, ⌃⌥N, the FOR pills): its session starts there, you stay where you are.
        if !fileOnly { startRequestSession(projectId: p.id, id: id, focus: p.id == selectedProjectId) }
        return id
    }

    /// Start (or reopen) the Claude session of a request, briefed with everything Steerify knows.
    func startRequestSession(projectId: String, id: String, focus: Bool = true) {
        guard let p = projects.first(where: { $0.id == projectId }),
              let r = RequestLog.load(p.boardDir).first(where: { $0.id == id }) else { return }
        var item = ItemRef(ref: "request:" + id)!
        item.title = "Request: " + r.short
        item.area = r.area
        RequestLog.edit(p.boardDir, id: id) { $0["status"] = ($0["status"] as? String) == "filed" ? "working" : $0["status"] }
        nameRequestSession(r, in: p)
        // Test copies (`--dry-sessions`) print the command instead of starting Claude (and the brief to stderr).
        if CommandLine.arguments.contains("--dry-sessions") { FileHandle.standardError.write(("BRIEF\n" + requestBrief(r, in: p) + "\n").data(using: .utf8)!) }
        start(projectId: p.id, item: item, intent: .intake, dry: CommandLine.arguments.contains("--dry-sessions"), extraBrief: requestBrief(r, in: p), focus: focus)
    }

    /// A request session is named after what was asked ("New · Tasks tab session label"), never "Request …".
    /// The words name it at once; Apple Intelligence gives 2–4 better words a moment later, kept in requests.json.
    func nameRequestSession(_ r: BoardRequest, in p: Project) {
        guard r.title == nil else { return }
        let dir = p.boardDir, ref = "request:" + r.id
        Task { @MainActor in
            guard let t = await SessionName.requestSubject(r.text) else { return }
            RequestLog.edit(dir, id: r.id) { if $0["title"] == nil { $0["title"] = t } }
            for s in sessions where s.projectId == p.id && s.item?.ref == ref { s.title = "New · " + t }
            persistSessions()
        }
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
        if r.kind == .task {
            let known = TaskStore.summary(p.boardDir)
            out.append(known.isEmpty ? "No tasks on the board yet." : "Tasks already on the board (reuse one if it is the same work):\n" + known.joined(separator: "\n"))
        } else if let c = r.chapter {
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
        if let t = r.became.first(where: { $0.hasPrefix("task:") }) {
            let last = TaskStore.load(p.boardDir).runs.first { "task:" + $0.task == t }
            switch last?.status {
            case "running": return ("task running", Brand.claude)
            case "done": return ("result to check", Brand.amber)
            case "noresult": return ("no result", Brand.red)
            case "ok": return ("task done", Brand.green)
            default: return ("task ready", Brand.cream)
            }
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
