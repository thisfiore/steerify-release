import Foundation
import SwiftUI
import FoundationModels
import ImageIO
import Vision

// MARK: - Local AI helpers (choice local-ai-helpers: session summaries, request triage, commits → roadmap, screenshot check)
//
// Apple Intelligence's on-device model, free and private. One question at a time (the model is shared), every answer
// cached on disk by its inputs, and each helper still does something useful without it (word model / plain rules).

enum LocalAI {
    static var ready: Bool {
        guard #available(macOS 26, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // Disk cache: <app support>/local-ai.json, key → answer.
    nonisolated(unsafe) private static var cache: [String: String] = {
        (try? Data(contentsOf: cacheFile)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }()
    private static let lock = NSLock()
    private static var cacheFile: URL { ProjectStore.dir.appendingPathComponent("local-ai.json") }
    static func cached(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return cache[key] }
    static func remember(_ key: String, _ value: String) {
        lock.lock(); cache[key] = value
        if cache.count > 4000 { cache = Dictionary(uniqueKeysWithValues: cache.shuffled().prefix(3000).map { ($0.key, $0.value) }) }
        let snapshot = cache; lock.unlock()
        saver.schedule { if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: cacheFile, options: .atomic) } }
    }
    private static let saver = Debouncer(delay: 2)

    /// Ask the on-device model (serialised; nil when it is off, busy too long, or refuses). Cached under `key`.
    static func ask(key: String, instructions: String, prompt: String, temperature: Double = 0.2) async -> String? {
        if let c = cached(key) { return c }
        guard ready, #available(macOS 26, *) else { return nil }
        guard let out = await Gate.shared.run({
            let s = LanguageModelSession(instructions: instructions)
            return try? await s.respond(to: String(prompt.prefix(9000)), options: GenerationOptions(temperature: temperature)).content
        }) else { return nil }
        let clean = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        remember(key, clean)
        return clean
    }

    /// Stable short hash for cache keys.
    static func hash(_ s: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 36)
    }

    /// One model call at a time.
    actor Gate {
        static let shared = Gate()
        private var busy = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        func run<T: Sendable>(_ work: @Sendable () async -> T?) async -> T? {
            if busy { await withCheckedContinuation { waiting.append($0) } }
            busy = true
            let r = await work()
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
            return r
        }
    }
}

final class Debouncer: @unchecked Sendable {
    private let delay: Double
    private var item: DispatchWorkItem?
    private let q = DispatchQueue(label: "steerify.debounce")
    init(delay: Double) { self.delay = delay }
    func schedule(_ f: @escaping @Sendable () -> Void) {
        q.async { self.item?.cancel(); let w = DispatchWorkItem(block: f); self.item = w; self.q.asyncAfter(deadline: .now() + self.delay, execute: w) }
    }
}

// MARK: - 1 · Session summaries: know a conversation without opening it

struct SessionSummary: Equatable {
    let text: String
    let ai: Bool
}

enum SessionSummaries {
    static func transcript(_ id: String) -> URL? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return nil }
        for d in dirs {
            let u = root.appendingPathComponent("\(d)/\(id).jsonl")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// What was asked and what Claude said, from a Claude Code transcript (.jsonl), newest last.
    static func extract(_ url: URL) -> (asks: [String], replies: [String])? {
        guard let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) else { return nil }
        var asks: [String] = [], replies: [String] = []
        for line in s.split(separator: "\n") where line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\"") {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let msg = o["message"] as? [String: Any], o["isSidechain"] as? Bool != true else { continue }
            let type = o["type"] as? String
            var texts: [String] = []
            if let c = msg["content"] as? String { texts = [c] }
            else if let parts = msg["content"] as? [[String: Any]] { texts = parts.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String } }
            for t in texts {
                if type == "assistant" { if t.count > 20 { replies.append(t) } ; continue }
                guard (o["origin"] as? [String: Any])?["kind"] as? String == "human" || o["origin"] == nil else { continue }
                if t.hasPrefix("Base directory for this skill") || t.hasPrefix("<system-reminder>") || t.hasPrefix("<local-command") { continue }
                if let r = t.range(of: "<command-args>"), let e = t.range(of: "</command-args>") {
                    asks.append("/steerify " + t[r.upperBound..<e.lowerBound])
                } else if !t.hasPrefix("<") { asks.append(t) }
            }
        }
        return asks.isEmpty && replies.isEmpty ? nil : (asks, replies)
    }

    /// Plain first sentence(s) of Claude's last reply: the free summary.
    static func plain(_ reply: String, max: Int = 150) -> String {
        var t = reply.replacingOccurrences(of: "\\*\\*|`|^#+ ", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        let lines = t.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("|") && !$0.hasPrefix("```") }
        var out = lines.first.map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 } ?? ""
        if out.count > max { out = String(out.prefix(max - 1)) + "…" }
        return out
    }

    nonisolated(unsafe) private static var memoStore: [String: SessionSummary] = [:]
    private static let memoLock = NSLock()
    /// Summaries load from many chips at once: the cache is locked.
    private static func memo(_ k: String) -> SessionSummary? { memoLock.lock(); defer { memoLock.unlock() }; return memoStore[k] }
    private static func memo(_ k: String, _ v: SessionSummary) { memoLock.lock(); memoStore[k] = v; memoLock.unlock() }

    /// One or two plain lines: what was done, what it waits on. Apple Intelligence when on, else Claude's last words.
    static func summary(_ id: String) async -> SessionSummary? {
        guard let url = transcript(id) else { return nil }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let key = "sum|\(id)|\(size / 4096)"          // a new summary every ~4 KB of conversation
        if let m = memo(key) { return m }
        if let c = LocalAI.cached(key) { let s = SessionSummary(text: c, ai: true); memo(key, s); return s }
        guard let x = await Task.detached(priority: .utility, operation: { extract(url) }).value else { return nil }
        let fallback = x.replies.last.map { plain($0) } ?? x.asks.last.map { "Asked: " + plain($0, max: 120) } ?? ""
        var parts = ["FIRST ASK: " + String((x.asks.first ?? "").prefix(600))]
        if x.asks.count > 1 { parts.append("LATEST ASK: " + String(x.asks.last!.prefix(600))) }
        for r in x.replies.suffix(3) { parts.append("CLAUDE: " + String(r.prefix(1400))) }
        if let ai = await LocalAI.ask(key: key,
            instructions: """
            You summarise a Claude Code work session for the person who owns it, so they know it without opening it.
            Write at most two short plain lines, no markdown, no lists. Line 1: what was done (past tense, concrete).
            Line 2 starts with "Now:" and says what it waits on or the next step. Max 30 words in total.
            """,
            prompt: parts.joined(separator: "\n\n")) {
            let tidy = ai.replacingOccurrences(of: "**", with: "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
            let s = SessionSummary(text: tidy, ai: true); memo(key, s); return s
        }
        guard !fallback.isEmpty else { return nil }
        let s = SessionSummary(text: fallback, ai: false); memo(key, s); return s
    }
}

// MARK: - 2 · Request triage with the on-device model (the word model answers first, this refines it)

extension RequestTriage {
    static func refine(_ text: String, chapters: [(name: String, items: [String])], context: String?, words: Triage) async -> Triage? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 12, LocalAI.ready else { return nil }
        let list = chapters.filter { $0.name != RequestLog.fixesChapter }.prefix(14)
        let menu = list.enumerated().map { i, c in "\(i + 1). \(c.name) — " + c.items.prefix(4).joined(separator: "; ").prefix(220) }.joined(separator: "\n")
        let prompt = """
        Chapters:
        \(menu)

        \(context.map { "The user was looking at the chapter: \($0)\n" } ?? "")Request: \(clean.prefix(1500))

        Answer in exactly this form:
        kind: fix|refine|feature|task|question
        chapter: <number, or 0 if none fits>
        why: <max 10 words>
        """
        guard let a = await LocalAI.ask(key: "tri|" + LocalAI.hash(prompt), instructions: """
            You file requests for a software project.
            fix = something is broken, wrong or does nothing ("the button does nothing", "crashes when…").
            refine = a small change to how something that exists looks or reads ("make the tabs smaller", "rename X").
            feature = a capability that does not exist yet ("let me export…", "add a calendar", "integrate with…").
            task = work to DO with tools and standards that exist, not code to build: make a tutorial or a report, collect or process data, send something; often repeats ("every Monday").
            question = the user asks what to do or how something works ("should we…?", "how does…?").
            Pick the chapter only when the request is clearly about it.
            """, prompt: prompt) else { return nil }
        func field(_ n: String) -> String? {
            a.split(whereSeparator: \.isNewline).map(String.init).first { $0.lowercased().hasPrefix(n + ":") }
                .map { String($0.dropFirst(n.count + 1)).trimmingCharacters(in: .whitespaces) }
        }
        guard let k = field("kind")?.lowercased(), let kind = RequestKind.allCases.first(where: { k.hasPrefix($0.rawValue) }) else { return nil }
        let why = (field("why") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ".\"")).prefix(90)
        var t = words
        t.kind = kind
        t.kindWhy = why.isEmpty ? words.kindWhy : String(why)
        // The words' chapter stays when there is one (it was the better guess in tests); the model fills the gap.
        // …and only when the request shares at least one word with that chapter (no home is better than a wrong one).
        if words.chapter == nil, let n = field("chapter").flatMap({ Int($0.prefix { $0.isNumber }) }), n >= 1 && n <= list.count {
            let c = Array(list)[n - 1]
            let mine = Set(RequestTriage.words(clean).map(RequestTriage.stem))
            let theirs = Set((RequestTriage.words(c.name) + c.items.flatMap(RequestTriage.words)).map(RequestTriage.stem))
            if let w = mine.intersection(theirs).first { t.chapter = c.name; t.chapterWhy = "Closest chapter by meaning · “\(w)”" }
        }
        t.ai = true
        return t
    }
}

// MARK: - 3 · Commits → roadmap: recent commits that look like they finished (or started) a key result

struct RepoCommit: Hashable { let hash: String; let date: String; let subject: String; let repo: String }

enum CommitMatch {
    /// Code commits only: commits that touch nothing but the board folder (choices, deliveries) prove nothing.
    static func commits(_ repos: [Repo], board: String, days: Int = 21) -> [RepoCommit] {
        repos.filter(\.exists).flatMap { r -> [RepoCommit] in
            let p = Process(); let out = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            var args = ["-C", r.path, "log", "--since=\(days).days", "--no-merges", "-n", "80", "--pretty=%h%x09%cI%x09%s", "--", "."]
            let b = URL(fileURLWithPath: board).standardizedFileURL.path, rp = URL(fileURLWithPath: r.path).standardizedFileURL.path
            if b.hasPrefix(rp + "/") { args.append(":(exclude)" + String(b.dropFirst(rp.count + 1))) }
            args.append(":(exclude,glob)**/.steerify/**")
            p.arguments = args
            p.standardOutput = out; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return [] }
            let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return String(decoding: d, as: UTF8.self).split(separator: "\n").compactMap { l in
                let f = l.split(separator: "\t", maxSplits: 2).map(String.init)
                return f.count == 3 ? RepoCommit(hash: f[0], date: f[1], subject: f[2], repo: r.name) : nil
            }
        }
    }

    /// For each open key result, the commits that share enough words to be worth a look (cheap, no model).
    static func candidates(_ items: [RoadItem], _ commits: [RepoCommit]) -> [(RoadItem, [RepoCommit], Double)] {
        items.compactMap { it in
            let w = Set(RequestTriage.words(it.text).map(RequestTriage.stem))
            guard w.count >= 2 else { return nil }
            let scored = commits.map { c -> (RepoCommit, Double) in
                let cw = Set(RequestTriage.words(c.subject).map(RequestTriage.stem))
                return (c, Double(w.intersection(cw).count) / Double(w.count))
            }.filter { !$0.0.subject.hasPrefix("To test:") && $0.1 >= 0.5 && w.intersection(Set(RequestTriage.words($0.0.subject).map(RequestTriage.stem))).count >= 3 }
             .sorted { $0.1 > $1.1 }
            guard let best = scored.first else { return nil }
            return (it, scored.prefix(3).map(\.0), best.1)
        }
    }

    /// Words decide (most of the key result's words in one commit subject); in the grey zone (½–¾ of the words)
    /// the model can say no. (Tested: it says no too often to be asked about clear matches.)
    static func verdict(_ item: RoadItem, _ cs: [RepoCommit], overlap: Double) async -> (String, RepoCommit)? {
        guard let top = cs.first else { return nil }
        if overlap >= 0.75 { return ("done", top) }
        let prompt = "Key result: \(item.text)\n\nCommit: \(top.subject.prefix(600))\n\nIs this commit's main subject the same thing as the key result? Answer yes or no."
        if let a = await LocalAI.ask(key: "cm3|" + LocalAI.hash(prompt), instructions: """
            You check a software roadmap against git history. Answer no when the commit only shares some words with the key \
            result or is about something nearby.
            """, prompt: prompt), a.lowercased().hasPrefix("no") { return nil }
        return ("partly", top)
    }
}

@MainActor
extension BoardStore {
    /// Commit-based proposals (unchecked: they never apply by themselves). Refreshed at most every 10 minutes per board.
    func refreshCommitProposals(force: Bool = false) async {
        guard force || Date().timeIntervalSince(commitCheckedAt) > 600 else { return }
        commitCheckedAt = Date()
        let open = roadmap.filter { r in ["todo", "wip", "you"].contains(r.status) && chapters.first { $0.name == r.track }?.draft != true }
        let repos = project.repos, dir = project.boardDir
        let cands = await Task.detached(priority: .utility) { CommitMatch.candidates(open, CommitMatch.commits(repos, board: dir)) }.value
        var out: [RoadProposal] = []
        for (it, cs, ov) in cands.prefix(24) {
            guard let (v, c) = await CommitMatch.verdict(it, cs, overlap: ov) else { continue }
            let to = v == "done" ? "review" : "wip"
            let order = ["todo": 0, "you": 1, "wip": 2, "review": 3]
            guard (order[to] ?? 0) > (order[it.status] ?? 0) else { continue }
            out.append(RoadProposal(item: it.text, from: it.status, to: to,
                                    evidence: "commit \(c.hash) · \(c.repo) · “\(c.subject.prefix(70))\(c.subject.count > 70 ? "…" : "")”",
                                    sure: false, fromCommit: true))
        }
        commitProposals = out
    }
}

// MARK: - 4 · Screenshot check: no wasted tests (missing, tiny, blank, repeated, or not showing what the test says)

struct ShotIssue: Hashable, Identifiable {
    var id: String { (img ?? "-") + "|" + problem + "|" + (test.map(String.init) ?? "") }
    let img: String?
    let test: Int?           // 0-based test index, nil for a gallery screenshot
    let problem: String
    let ai: Bool
}

enum ShotCheck {
    static let minWidth = 1400
    /// A test picture this wide with no focus is a whole Retina window: unreadable in the row.
    static let wholeWindowWidth = 2800

    /// Pixel size, a luminance spread (≈0 = blank) and a content hash, without loading AppKit.
    static func inspect(_ path: String) -> (w: Int, spread: Double, hash: Int)? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int else { return nil }
        let thumbOpts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 48]
        guard let small = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else { return (w, 99, 0) }
        let n = 48, bytes = n * n * 4
        var px = [UInt8](repeating: 0, count: bytes)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (w, 99, 0) }
        ctx.draw(small, in: CGRect(x: 0, y: 0, width: n, height: n))
        var lum: [Double] = []; lum.reserveCapacity(n * n)
        var h = Hasher()
        for i in stride(from: 0, to: bytes, by: 4) {
            lum.append(0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2]))
            h.combine(px[i] >> 4); h.combine(px[i + 1] >> 4); h.combine(px[i + 2] >> 4)
        }
        let mean = lum.reduce(0, +) / Double(lum.count)
        let sd = (lum.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lum.count)).squareRoot()
        return (w, sd, h.finalize())
    }

    /// The rules that need no model (also run by the MCP `deliver`, so Claude hears about them first).
    /// `focused`: pictures that come with a `focus` crop (a whole window is fine then: the list shows the crop).
    static func basic(dir: String, shots: [String], tests: [(label: String, img: String?)], focused: Set<String> = []) -> [ShotIssue] {
        var out: [ShotIssue] = []
        var seen: [Int: String] = [:]             // content hash → first user ("test 2" / "screenshot 1")
        func look(_ img: String, test: Int?, name: String) {
            let path = (dir as NSString).appendingPathComponent(img)
            guard FileManager.default.fileExists(atPath: path) else { out.append(ShotIssue(img: img, test: test, problem: "picture missing", ai: false)); return }
            guard let x = inspect(path) else { out.append(ShotIssue(img: img, test: test, problem: "can't be opened", ai: false)); return }
            if x.w < minWidth { out.append(ShotIssue(img: img, test: test, problem: "small: \(x.w) px wide (needs \(minWidth))", ai: false)) }
            if test != nil, x.w >= wholeWindowWidth, !focused.contains(img) {
                out.append(ShotIssue(img: img, test: test, problem: "whole window (\(x.w) px): crop to the feature or add focus", ai: false))
            }
            if x.spread < 2.5 { out.append(ShotIssue(img: img, test: test, problem: "looks blank", ai: false)) }
            if x.hash != 0, test != nil {
                if let first = seen[x.hash], first != name { out.append(ShotIssue(img: img, test: test, problem: "same picture as \(first)", ai: false)) }
                else { seen[x.hash] = name }
            }
        }
        var looked = Set<String>()
        for (i, t) in tests.enumerated() {
            guard let img = t.img, !img.isEmpty else { out.append(ShotIssue(img: nil, test: i, problem: "no picture", ai: false)); continue }
            looked.insert(img)
            look(img, test: i, name: "test \(i + 1)")
        }
        for (i, s) in shots.enumerated() where !looked.contains(s) { look(s, test: nil, name: "screenshot \(i + 1)") }
        return out
    }

    /// Text on a picture (Vision, on device).
    static func ocr(_ path: String) -> String {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return "" }
        let req = VNRecognizeTextRequest(); req.recognitionLevel = .fast; req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: img).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " · ")
    }

    /// Basic rules + (with Apple Intelligence) "does the picture show what the test says to check?".
    static func check(_ item: ShipItem, dir: String) async -> [ShotIssue] {
        let tests = item.tests.map { (label: $0.label, img: $0.img) }
        var out = await Task.detached(priority: .utility) { basic(dir: dir, shots: item.shots.map(\.img), tests: tests, focused: Set(item.focus.keys)) }.value
        guard LocalAI.ready else { return out }
        let bad = Set(out.compactMap(\.img))
        for (i, t) in item.tests.enumerated() {
            guard let img = t.img, let check = t.check, !check.isEmpty, !bad.contains(img) else { continue }
            let path = (dir as NSString).appendingPathComponent(img)
            let mtime = ((try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date)?.timeIntervalSince1970 ?? 0
            let key = "shot|\(img)|\(Int(mtime))|" + LocalAI.hash(t.label + check)
            let text: String
            if LocalAI.cached(key) == nil {
                text = await Task.detached(priority: .utility) { ocr(path) }.value
                guard text.count >= 8 else { continue }        // a picture with no text: nothing to compare with
                // Most of the check's words are on the screen: it shows it, no need to ask.
                let want = Set(RequestTriage.words(check).filter { $0.count >= 4 }.map(RequestTriage.stem))
                let got = Set(RequestTriage.words(text).map(RequestTriage.stem))
                if want.isEmpty || Double(want.intersection(got).count) / Double(want.count) >= 0.25 { LocalAI.remember(key, "yes - words match"); continue }
            } else { text = "" }
            guard let a = await LocalAI.ask(key: key, instructions: """
                You check screenshots before a person tests a software change. You get the text read from the screenshot \
                and what the test asks to look at. Say "no" only when the screenshot clearly shows a different screen. When in doubt say "unsure".
                """, prompt: "Test: \(t.label)\nShould show: \(check)\n\nText on the screenshot: \(text.prefix(3000))\n\nAnswer: yes|no|unsure, then a dash and max 8 words why.") else { continue }
            let low = a.lowercased()
            if low.hasPrefix("no") {
                let why = a.split(separator: "-", maxSplits: 1).dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                out.append(ShotIssue(img: img, test: i, problem: "may not show it" + (why.isEmpty ? "" : ": " + why.prefix(70)), ai: true))
            }
        }
        return out
    }
}

// MARK: - Small views

/// "What happened in this conversation", in one or two lines, loaded in the background.
struct SessionSummaryLine: View {
    let claudeId: String?
    var size: CGFloat = 11
    var lines = 2
    @State private var s: SessionSummary?
    var body: some View {
        Group {
            if let s {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if s.ai { Image(systemName: "apple.intelligence").font(.system(size: S(size - 1))).foregroundStyle(Brand.blue) }
                    Text(s.text).font(.system(size: S(size))).foregroundStyle(Brand.ink.opacity(0.8)).lineLimit(lines)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help(s.ai ? "Summary by Apple Intelligence, on this Mac" : "Claude's last words in this conversation")
            } else { Color.clear.frame(width: 1, height: 1) }     // an empty Group never runs its .task
        }
        .task(id: claudeId) { if let id = claudeId { s = await SessionSummaries.summary(id) } }
    }
}

/// Pictures that would waste a test, on a To test card, with one way to get them redone.
struct ShotIssues: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let item: ShipItem
    @State private var issues: [ShotIssue] = []
    var body: some View {
        Group {
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.exclamationmark").foregroundStyle(Brand.amber)
                        Text("PICTURE CHECK").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.amber)
                        Text("\(issues.count) to look at before testing").font(.system(size: S(11.5))).foregroundStyle(Brand.ink)
                        Spacer()
                        ActionButton(title: "Ask Claude to redo them") {
                            var r = ItemRef(ref: "test:" + item.id)!; r.title = item.title; r.area = item.area
                            model.start(projectId: board.project.id, item: r, intent: .fix, extraBrief: brief)
                        }
                    }
                    ForEach(issues) { i in
                        HStack(spacing: 6) {
                            Text(i.test.map { "Test \($0 + 1)" } ?? "Screenshot").font(.system(size: S(11), weight: .semibold)).foregroundStyle(Brand.cream)
                            Text(i.problem).font(.system(size: S(11))).foregroundStyle(Brand.ink.opacity(0.85)).lineLimit(1)
                            if i.ai { Image(systemName: "apple.intelligence").font(.system(size: S(10))).foregroundStyle(Brand.blue).help("Apple Intelligence read the picture") }
                        }
                    }
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.amberDim.opacity(0.5)))
            } else { Color.clear.frame(width: 1, height: 1) }
        }
        .task(id: "\(item.id)|\(item.version)|\(item.stamp)") { issues = await ShotCheck.check(item, dir: board.project.boardDir) }
    }
    private var brief: String {
        "Steerify's picture check found problems on the To test pictures of \(item.id) (v\(item.version)): "
            + issues.map { ($0.test.map { "test \($0 + 1)" } ?? "screenshot") + ($0.img.map { " (\($0))" } ?? "") + ": " + $0.problem }.joined(separator: "; ")
            + ". Retake them full size (≥\(ShotCheck.minWidth) px) on the real feature, each showing what its check says, and re-deliver with the same id."
    }
}

// MARK: - `Steerify --local-ai-check <board dir>`: run the four helpers on a real board and print what they say

enum LocalAICheck {
    @MainActor static func run(_ dir: String) async {
        func say(_ s: String) { print(s); fflush(stdout) }
        guard let p = ProjectStore.read(dir) else { say("no board at \(dir)"); exit(1) }
        let b = BoardStore(project: p)
        say("Apple Intelligence ready: \(LocalAI.ready)")
        say("\n== 1 · Session summaries")
        var seen = Set<String>()
        for l in b.links.reversed() where seen.insert(l.claudeSession).inserted && seen.count <= 4 {
            let t0 = Date()
            let s = await SessionSummaries.summary(l.claudeSession)
            say("· \(l.title ?? l.item)\n  \(s.map { ($0.ai ? "[AI] " : "[plain] ") + $0.text } ?? "(no transcript)")  (\(String(format: "%.1f", Date().timeIntervalSince(t0)))s)")
        }
        say("\n== 2 · Request triage")
        let chs = b.chapters.filter { !$0.draft }.map { c in (name: c.name, items: b.roadmap.filter { $0.track == c.name }.map(\.text)) }
        for t in ["The Resume button on the To test card does nothing when the conversation was deleted",
                  "Make the session tabs a bit smaller, they take too much space",
                  "Let me export the whole board as a PDF to send to a client",
                  "Should the landing page show pricing already?"] {
            let w = RequestTriage.classify(t, chapters: chs, context: nil)
            let a = await RequestTriage.refine(t, chapters: chs, context: nil, words: w)
            say("· \(t)\n  words: \(w.kind.rawValue) · \(w.chapter ?? "-") · \(w.kindWhy)\n  AI:    \(a.map { "\($0.kind.rawValue) · \($0.chapter ?? "-") · \($0.kindWhy)" } ?? "(none)")")
        }
        say("\n== 3 · Commits → roadmap")
        let open = b.roadmap.filter { ["todo", "wip", "you"].contains($0.status) }
        for (it, cs, ov) in CommitMatch.candidates(open, CommitMatch.commits(p.repos, board: dir)) {
            say("  candidate \(String(format: "%.2f", ov)) · \(it.text.prefix(50)) ← \(cs[0].hash) \(cs[0].subject.prefix(50))")
        }
        await b.refreshCommitProposals(force: true)
        if b.commitProposals.isEmpty { say("· no proposals") }
        for c in b.commitProposals { say("· \(c.item)\n  \(c.from) → \(c.to) · \(c.evidence)") }
        say("\n== 4 · Screenshot check")
        for s in b.ships.prefix(6) {
            let i = await ShotCheck.check(s, dir: dir)
            say("· \(s.title) v\(s.version): " + (i.isEmpty ? "ok" : i.map { ($0.test.map { "test \($0 + 1)" } ?? "shot") + " " + $0.problem + ($0.ai ? " [AI]" : "") }.joined(separator: "; ")))
        }
        try? await Task.sleep(for: .seconds(3))      // let the answer cache reach the disk
        exit(0)
    }
}
