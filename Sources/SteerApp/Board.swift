import Foundation
import CoreServices

// MARK: - Models (read loosely: current and older board formats both decode)

struct BoardOption: Identifiable, Hashable {
    let id: String
    let label: String
    let rec: Bool
    let points: [String]
    let mockHTML: String?      // inline HTML mockup
    let shot: String?          // image path relative to the board folder
    let proto: String?         // HTML prototype path relative to the board folder
    var simple = false         // small diagram (board class "mock simple")
}

struct BoardDecision: Identifiable, Hashable {
    let id: String
    let title: String
    let why: String            // may contain HTML
    let areas: [String]
    let tags: [String]
    let added: String?
    let revisedAt: String?
    let multi: Bool
    let gallery: [(img: String, caption: String, proto: String?)]
    let options: [BoardOption]
    /// When Claude marked the choice built (board.json `built`, ISO date).
    var built: String? = nil
    /// Where the choice came from ("request:<id>", "road:<slug>", …): board.json `from` (stamped by ask_choice),
    /// else a request id named in its why ("From request r261119-095609"). Choices of one origin are one piece of work.
    var origin: String? = nil
    /// Hash of the item's whole JSON: any edit (title, text, options…) makes the card redraw.
    var stamp: Int = 0
    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.stamp == b.stamp }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(stamp) }
}

extension BoardDecision {
    static func origin(from: String?, why: String) -> String? {
        if let f = from?.trimmingCharacters(in: .whitespaces), !f.isEmpty {
            return f.contains(":") ? f : "request:" + f
        }
        guard let m = why.range(of: #"\br\d{6}-\d{6}\b"#, options: .regularExpression) else { return nil }
        return "request:" + why[m]
    }
}

extension BoardStore {
    /// The origin an item is grouped by: a choice's origin, a request itself, a delivery's built choice's origin.
    func originKey(of ref: String) -> String? {
        if ref.hasPrefix("request:") { return ref }
        if ref.hasPrefix("choice:") { return decisions.first { "choice:" + $0.id == ref }?.origin }
        if ref.hasPrefix("test:"), let s = ships.first(where: { "test:" + $0.id == ref }) {
            return s.choices.lazy.compactMap { c in self.decisions.first { $0.id == c }?.origin }.first
        }
        return nil
    }
}

struct ShipTest: Hashable { let label: String; let url: String?; let check: String?; let img: String? }

struct ShipItem: Identifiable, Hashable {
    let id: String
    let title: String
    let area: String
    let status: String         // local | needs-deploy | live
    let what: String
    let tested: [String]
    let howTo: [String]
    let tests: [ShipTest]
    let issues: [String]
    let shots: [(img: String, caption: String)]
    var repos: [String] = []
    /// Roadmap items this delivery belongs to (exact text or slug), from the item's "road" field.
    var roads: [String] = []
    /// Choices this delivery built (ids, from the item's "choices" field).
    var choices: [String] = []
    /// Requirements this delivery meets (ids, from the item's "reqs" field): your OK marks them built.
    var reqs: [String] = []
    /// Feature crops: image path → the part of the picture to show in the list (0–1 rect, from `focus` on a test or shot).
    var focus: [String: CGRect] = [:]
    let version: Int
    let updated: String?
    var stamp: Int = 0
    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.version == b.version && a.stamp == b.stamp }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(version); h.combine(stamp) }
}

extension ShipItem {
    /// The card header: 2–4 short bullets. `what` as lines ("- a\n- b") or a list; older prose → its sentences (max 3).
    var bullets: [String] {
        let plain = BoardText.plain(what)
        let lines = plain.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).drop { "-•*·–".contains($0) }.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > 1 { return Array(lines.prefix(5)) }
        var out: [String] = []
        plain.enumerateSubstrings(in: plain.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { out.append(s) }
        }
        return Array((out.isEmpty ? [plain] : out).prefix(3))
    }
}

struct Requirement: Identifiable, Hashable {
    let id: String; let text: String; let status: String; let src: String?; let area: String; let group: String
    /// Why it is settled (board.json `evidence`): "OK on To test · …", "chapter approved …", a file or commit.
    var evidence: String? = nil
}
struct RoadItem: Identifiable, Hashable {
    var id: String { BoardFiles.slug(text) }; let text: String; let status: String; let track: String; let area: String
    /// Optional third element of a track item: {req, for, at, doneAt, area} (requests filed by Steerify).
    var request: String? = nil
    var forChapter: String? = nil
    var doneAt: String? = nil
    /// Last status change (meta.moved, ISO), else when it was done or filed: the chapter's activity (chapter-order).
    var movedAt: String? = nil
    /// What the key result is for: "core" (the objective is met when every core item is done) or an extra:
    /// "test", "tutorial", "enhancement", "later". Set by Claude or by you (meta.kind); nil = guessed from the words.
    var kindTag: String? = nil
    /// The kind was proposed by Claude and waits for your Keep / Undo on the chapter.
    var kindProposed: Bool = false

    static let kinds = ["core", "test", "tutorial", "enhancement", "later"]
    /// The kind in use: the tag, else a guess from the text (a "Later: …" idea, a tutorial, a test project…).
    var kind: String { kindTag ?? Self.guessKind(text) }
    var isCore: Bool { kind == "core" }
    var kindGuessed: Bool { kindTag == nil }

    static func guessKind(_ text: String) -> String {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("later") || t.hasPrefix("someday") || t.hasPrefix("maybe") || t.hasPrefix("nice to have") || t.hasPrefix("idea:") { return "later" }
        if t.hasPrefix("tutorial") || t.hasPrefix("video") || t.hasPrefix("docs:") || t.hasPrefix("launch pass") { return "tutorial" }
        if t.hasPrefix("test ") || t.hasPrefix("tests") || t.hasPrefix("test:") || t.hasPrefix("usability study") || t.hasPrefix("e2e") { return "test" }
        if t.hasPrefix("polish") || t.hasPrefix("enhancement") || t.hasPrefix("refine") { return "enhancement" }
        return "core"
    }
}

/// OKR reading of a chapter: the core decides whether the objective is met; extras never hold it back.
struct ChapterProgress {
    let core: [RoadItem], extras: [RoadItem]
    var coreDone: Int { core.filter { $0.status == "done" }.count }
    var extrasDone: Int { extras.filter { $0.status == "done" }.count }
    /// Extras that are still promised work (later ideas are not).
    var extrasOpen: Int { extras.filter { $0.status != "done" && $0.kind != "later" }.count }
    var fraction: Double { core.isEmpty ? 0 : Double(coreDone) / Double(core.count) }
    var coreReleased: Bool { !core.isEmpty && coreDone == core.count }
    /// The day the last core key result was marked done (when known).
    var releasedOn: String? { coreReleased ? core.compactMap(\.doneAt).max() : nil }
    init(_ items: [RoadItem]) {
        let c = items.filter(\.isCore)
        // A chapter with no core at all (only extras): every item counts, as before.
        if c.isEmpty { core = items; extras = [] } else { core = c; extras = items.filter { !$0.isCore } }
    }
}
/// A roadmap chapter (track). `draft`: drafted by Claude from a feature request, waiting for your OK.
struct Chapter: Identifiable, Hashable { var id: String { name }; let name: String; let area: String; let draft: Bool; let request: String?; let objective: String? }

/// A user verdict / pick as stored in decisions.json → choices[key].
struct Verdict { var pick: Any?; var note: String; var at: String?; var v: Int?; var parked: Bool
    var pickString: String? { pick as? String }
}

// MARK: - Store

/// One project's board, read from its workspace folder and kept live with FSEvents (no polling).
@MainActor
final class BoardStore: ObservableObject {
    let project: Project
    @Published private(set) var decisions: [BoardDecision] = [] { didSet { memo = [:] } }
    @Published private(set) var ships: [ShipItem] = [] { didSet { memo = [:] } }
    @Published private(set) var requirements: [Requirement] = []
    @Published private(set) var roadmap: [RoadItem] = [] { didSet { memo = [:] } }
    @Published private(set) var chapters: [Chapter] = []
    @Published private(set) var areas: [(key: String, name: String)] = []
    @Published private(set) var goal: String = ""
    @Published private(set) var store: [String: Any] = ["choices": [String: Any](), "history": [Any]()] {
        didSet { choiceMap = (store["choices"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [String: Any] }; memo = [:] }
    }
    /// Verdicts as native dictionaries, converted once per change. Reading them straight from `store`
    /// re-bridged the whole decisions file on every lookup (the hot spot of 19 Nov).
    private var choiceMap: [String: [String: Any]] = [:]
    @Published private(set) var loadedAt = Date.distantPast { didSet { memo = [:] } }
    /// Answers that are costly to work out and only change with the board (an item's thread, a session's stage).
    /// Emptied on every board change, and after 5 s for what lives outside the board files (the request log).
    private var memo: [String: Any] = [:]
    private var memoAt = Date.distantPast
    func memoized<T>(_ key: String, _ make: () -> T) -> T {
        if Date().timeIntervalSince(memoAt) > 5 { memo = [:]; memoAt = Date() }
        if let hit = memo[key] { return hit as! T }
        let v = make(); memo[key] = v as Any; return v
    }
    @Published private(set) var links: [SessionLink] = [] { didSet { memo = [:] } }
    /// Local AI: roadmap proposals read from recent commits (LocalAI.swift), never applied by themselves.
    @Published var commitProposals: [RoadProposal] = []
    /// Local AI: key results a recent Claude session is working on (LocalAI.swift), never applied by themselves.
    @Published var sessionProposals: [RoadProposal] = []
    var commitCheckedAt = Date.distantPast
    private var manifestTime: Date?

    private var stream: FSEventStreamRef?

    init(project: Project) {
        self.project = project
        reload()
        watch()
    }

    // MARK: Reading

    static let debug = ProcessInfo.processInfo.environment["STEERIFY_DEBUG"] != nil

    func reload() {
        if Self.debug { FileHandle.standardError.write("reload \(project.id)\n".data(using: .utf8)!) }
        let dir = project.boardDir
        let board = BoardFiles.json(dir, "board.json") as? [String: Any] ?? [:]
        goal = board["goal"] as? String ?? ""

        var areaList: [(String, String)] = []
        if let a = board["areas"] as? [String: Any] {
            for (k, v) in a { areaList.append((k, (v as? [String: Any])?["name"] as? String ?? k)) }
        }

        decisions = (board["decisions"] as? [[String: Any]] ?? []).map { d in
            let opts = (d["options"] as? [[String: Any]] ?? []).map { o in
                BoardOption(id: str(o["id"]), label: str(o["label"]), rec: o["rec"] as? Bool ?? false,
                            points: o["points"] as? [String] ?? [], mockHTML: o["mock"] as? String,
                            shot: o["shot"] as? String, proto: o["proto"] as? String,
                            simple: (o["simple"] as? Bool ?? false) || (d["simple"] as? Bool ?? false))
            }
            let gal = (d["gallery"] as? [[String: Any]] ?? []).compactMap { g -> (String, String, String?)? in
                guard let img = g["img"] as? String else { return nil }
                return (img, str(g["caption"]), g["proto"] as? String)
            }
            var bd = BoardDecision(id: str(d["id"]), title: str(d["title"]), why: str(d["why"] ?? d["meta"]),
                                 areas: d["areas"] as? [String] ?? [], tags: d["tags"] as? [String] ?? [],
                                 added: d["added"] as? String, revisedAt: d["revisedAt"] as? String,
                                 multi: d["multi"] as? Bool ?? false,
                                 gallery: gal.map { (img: $0.0, caption: $0.1, proto: $0.2) }, options: opts)
            bd.stamp = stamp(d)
            bd.built = d["built"] as? String
            bd.origin = BoardDecision.origin(from: d["from"] as? String ?? d["request"] as? String, why: bd.why)
            return bd
        }

        let del = BoardFiles.json(dir, "delivered.json")
        let items = (del as? [String: Any])?["items"] as? [[String: Any]] ?? (del as? [[String: Any]] ?? [])
        ships = items.map { it in
            var si = ShipItem(id: str(it["id"]), title: str(it["title"]), area: str(it["area"]), status: str(it["status"]),
                     what: (it["what"] as? [String])?.map { "- " + $0 }.joined(separator: "\n") ?? str(it["what"]), tested: it["tested"] as? [String] ?? [], howTo: it["howTo"] as? [String] ?? [],
                     tests: (it["tests"] as? [[String: Any]] ?? []).map {
                         ShipTest(label: str($0["label"]), url: $0["url"] as? String, check: $0["check"] as? String, img: $0["img"] as? String) },
                     issues: it["issues"] as? [String] ?? [],
                     shots: (it["shots"] as? [[String: Any]] ?? []).compactMap { s in (s["img"] as? String).map { (img: $0, caption: str(s["caption"])) } },
                     version: it["version"] as? Int ?? 1, updated: (it["updated"] ?? it["added"]) as? String)
            si.stamp = stamp(it)
            si.repos = it["repos"] as? [String] ?? []
            si.choices = (it["choices"] as? [String] ?? []).map { $0.hasPrefix("choice:") ? String($0.dropFirst(7)) : $0 }
            si.reqs = (it["reqs"] as? [String] ?? []).map { $0.hasPrefix("req:") ? String($0.dropFirst(4)) : $0 }
            si.roads = (it["road"] as? [String]) ?? ((it["road"] as? String).map { [$0] } ?? [])
            for x in (it["shots"] as? [[String: Any]] ?? []) + (it["tests"] as? [[String: Any]] ?? []) {
                if let img = x["img"] as? String, let r = BoardFiles.focusRect(x["focus"]) { si.focus[img] = r }
            }
            return si
        }.sorted { ($0.updated ?? "") > ($1.updated ?? "") }   // newest first, whatever the file order

        requirements = (board["requirements"] as? [[String: Any]] ?? []).flatMap { g in
            (g["items"] as? [[String: Any]] ?? []).map {
                Requirement(id: str($0["id"]), text: str($0["text"]), status: str($0["status"]), src: $0["src"] as? String,
                            area: str(g["area"]), group: str(g["h"]), evidence: $0["evidence"] as? String)
            }
        }

        let trackList = board["tracks"] as? [[String: Any]] ?? []
        chapters = trackList.map { t in
            Chapter(name: str(t["name"]), area: str(t["area"]), draft: t["draft"] as? Bool ?? false,
                    request: t["request"] as? String, objective: t["objective"] as? String)
        }
        roadmap = trackList.flatMap { t in
            (t["items"] as? [[Any]] ?? []).compactMap { pair -> RoadItem? in
                guard let text = pair.first as? String else { return nil }
                let meta = pair.count > 2 ? pair[2] as? [String: Any] : nil
                let area = (meta?["area"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? str(t["area"])
                return RoadItem(text: text, status: pair.count > 1 ? str(pair[1]) : "todo", track: str(t["name"]), area: area,
                                request: meta?["req"] as? String, forChapter: (meta?["for"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                doneAt: meta?["doneAt"] as? String,
                                movedAt: (meta?["moved"] ?? meta?["doneAt"] ?? meta?["at"]) as? String,
                                kindTag: (meta?["kind"] as? String).flatMap { RoadItem.kinds.contains($0) ? $0 : nil },
                                kindProposed: meta?["kindProposed"] as? Bool ?? false)
            }
        }

        // Older boards have no areas map: derive them from what the items use.
        if areaList.isEmpty {
            let used = Set(ships.map(\.area) + decisions.flatMap(\.areas) + roadmap.map(\.area)).filter { !$0.isEmpty }
            areaList = used.sorted().map { ($0, $0.capitalized) }
        }
        areas = areaList.sorted { $0.1 < $1.1 }.map { (key: $0.0, name: $0.1) }

        let raw = BoardFiles.json(dir, "decisions.json") as? [String: Any] ?? [:]
        store = raw["choices"] != nil ? raw : ["choices": [String: Any](), "history": [Any]()]
        links = SessionLinks.load(dir)
        let first = loadedAt == .distantPast
        let mtime = (try? FileManager.default.attributesOfItem(atPath: project.manifest)[.modificationDate] as? Date) ?? nil
        if !first, mtime != manifestTime {
            let id = project.id
            DispatchQueue.main.async { NotificationCenter.default.post(name: .steerifyManifestChanged, object: id) }
        }
        manifestTime = mtime
        loadedAt = Date()
        // Announce real reloads only (not the first load inside init), and never synchronously:
        // listeners may ask the model for this very board.
        if !first { DispatchQueue.main.async { NotificationCenter.default.post(name: .steerifyBoardReloaded, object: nil) } }
    }

    /// Latest Claude conversation started for an item, if any.
    func lastLink(_ ref: String) -> SessionLink? { links.last { $0.item == ref } }

    /// A session already took this answer: one was started on the item at or after your verdict.
    /// From then on the item is in Claude's court, not yours, even when that session has ended.
    func takenBySession(_ ref: String, since at: String?) -> Bool {
        guard let at else { return false }
        return links.contains { $0.item == ref && $0.started >= at }
    }

    func areaName(_ k: String) -> String { areas.first { $0.key == k }?.name ?? k }

    private var choices: [String: Any] { store["choices"] as? [String: Any] ?? [:] }

    func choiceMapEntry(_ key: String) -> [String: Any]? { choiceMap[key] }
    func verdict(_ key: String) -> Verdict {
        let c = choiceMap[key] ?? [:]
        return Verdict(pick: c["pick"], note: c["note"] as? String ?? "", at: c["at"] as? String, v: c["v"] as? Int,
                       parked: c["parked"] as? Bool ?? false)
    }

    // States, same rules as the web board.
    func isParked(_ d: BoardDecision) -> Bool { verdict(d.id).parked }
    /// Already built for the current answer: a build session started for it, a delivery names it (`choices`),
    /// or Claude marked it (`built`), after the pick. Changing the answer makes it buildable again.
    func isBuilt(_ d: BoardDecision) -> Bool {
        guard isDecided(d) else { return false }
        let at = verdict(d.id).at ?? ""
        if let b = d.built, b >= at { return true }
        if ships.contains(where: { $0.choices.contains(d.id) && ($0.updated ?? "") >= at }) { return true }
        return links.contains { $0.item == "choice:" + d.id && $0.intent == "build" && $0.started >= at }
    }

    func isDecided(_ d: BoardDecision) -> Bool {
        let v = verdict(d.id)
        if v.parked { return false }
        if let r = d.revisedAt, let at = v.at, at < r { return false }
        if d.multi { return !((v.pick as? [Any])?.isEmpty ?? true) }
        return v.pickString != nil
    }
    /// ok | refine | broken | nil (to test) for the item's current version.
    func shipPick(_ s: ShipItem) -> String? {
        let v = verdict("ship:" + s.id)
        return v.v == s.version ? v.pickString : nil
    }
    func shipNote(_ s: ShipItem) -> String { verdict("ship:" + s.id).note }

    /// Where an item stands for YOU.
    enum ShipState { case toTest, retest, waiting, ok }

    /// Per-test feedback on the current version: index → (ok, note).
    func testFeedback(_ s: ShipItem) -> [Int: (ok: Bool, note: String)] {
        let c = choiceMap["ship:" + s.id] ?? [:]
        guard (c["v"] as? Int) == s.version, let t = c["tests"] as? [String: Any] else { return [:] }
        var out: [Int: (Bool, String)] = [:]
        for (k, v) in t { if let i = Int(k), let d = v as? [String: Any] { out[i] = (d["ok"] as? Bool ?? false, d["note"] as? String ?? "") } }
        return out
    }

    /// The verdict that counts: your pick, else per-test notes mean "refine" (same suggestion as the web board).
    func effectivePick(_ s: ShipItem) -> String? {
        if let p = shipPick(s) { return p }
        let fb = testFeedback(s)
        if fb.values.contains(where: { !$0.note.isEmpty }) { return "refine" }
        return nil
    }

    /// Your verdict on an earlier version, when this one is new (a re-test).
    func previousVerdict(_ s: ShipItem) -> (v: Int, pick: String, note: String)? {
        let v = verdict("ship:" + s.id)
        guard let old = v.v, old < s.version, let pick = v.pickString else { return nil }
        return (old, pick, v.note)
    }

    func shipState(_ s: ShipItem) -> ShipState {
        switch effectivePick(s) {
        case "ok": return .ok
        case "refine", "broken": return .waiting
        default: return previousVerdict(s) != nil ? .retest : .toTest
        }
    }

    // MARK: Writing (decisions.json only, same shape as the web board)

    /// Other options blended into the pick (choices[id].mix).
    func mix(_ d: BoardDecision) -> [String] {
        choiceMap[d.id]?["mix"] as? [String] ?? []
    }

    func setChoice(_ d: BoardDecision, pick: String?, note: String? = nil, mix: [String]? = nil) {
        update(d.id) { c in
            if let pick { c["pick"] = pick }
            if let note { c["note"] = note }
            if let mix { c["mix"] = mix.isEmpty ? nil : mix }
            c["parked"] = nil
        }
    }

    func setChoiceMulti(_ d: BoardDecision, picks: [String], note: String) {
        update(d.id) { c in
            c["pick"] = picks.isEmpty ? ["__note"] : picks
            c["note"] = note
            c["parked"] = nil
        }
    }

    func setParked(_ d: BoardDecision, _ parked: Bool) {
        update(d.id) { c in
            if parked { c["parked"] = true; c["parkedAt"] = Self.now() } else { c["parked"] = nil; c["parkedAt"] = nil }
        }
    }

    func setShip(_ s: ShipItem, pick: String?, note: String? = nil) {
        update("ship:" + s.id) { c in
            if (c["v"] as? Int) != s.version { c["pick"] = nil; c["tests"] = nil; c["v"] = s.version }
            if let pick { c["pick"] = pick }
            if let note { c["note"] = note }
        }
        if pick == "ok" { markBuilt(by: s) }
    }

    /// Your OK on a delivery marks the requirements it names (`reqs`) built, with the delivery as evidence.
    func markBuilt(by s: ShipItem) {
        let ids = s.reqs.filter { id in requirements.contains { $0.id == id && $0.status != "built" } }
        guard !ids.isEmpty else { return }
        let dir = project.boardDir, ev = "OK on To test · “\(s.title)” v\(s.version)"
        DispatchQueue.global(qos: .userInitiated).async {
            for id in ids { _ = SteerifyMCP.call("set_requirement_status", ["id": id, "status": "built", "evidence": ev], board: dir) }
            DispatchQueue.main.async { self.reload() }
        }
    }

    /// Per-test answer, same shape as the web board: tests["<i>"] = {ok: true} or {note: "…"}; nil clears it.
    func setTest(_ s: ShipItem, index: Int, ok: Bool? = nil, note: String? = nil) {
        update("ship:" + s.id) { c in
            if (c["v"] as? Int) != s.version { c["pick"] = nil; c["tests"] = nil; c["v"] = s.version }
            var tests = c["tests"] as? [String: Any] ?? [:]
            let k = String(index)
            if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tests[k] = ["note": note] }
            else if ok == true { tests[k] = ["ok": true] }
            else { tests[k] = nil }
            c["tests"] = tests
        }
    }

    func setRequirement(_ r: Requirement, pick: String, note: String? = nil) {
        update("req:" + r.id) { c in
            c["pick"] = pick
            if let note { c["note"] = note }
        }
    }

    func editPins(_ ref: String, _ change: (inout [[String: Any]]) -> Void) {
        update(Self.key(for: ref)) { c in
            var list = c["pins"] as? [[String: Any]] ?? []
            change(&list)
            for i in list.indices where list[i]["at"] == nil { list[i]["at"] = Self.now() }
            c["pins"] = list
        }
    }

    static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    /// One save for many requirement verdicts (no racing writes).
    func setRequirements(_ rs: [Requirement], pick: String) {
        guard !rs.isEmpty else { return }
        reload()
        var all = choices
        var history = store["history"] as? [Any] ?? []
        let at = Self.now()
        for r in rs {
            var c = all["req:" + r.id] as? [String: Any] ?? [:]
            c["pick"] = pick; c["at"] = at
            all["req:" + r.id] = c
            history.append(["id": "req:" + r.id, "pick": pick, "text": "", "note": "", "at": at])
        }
        store["choices"] = all
        store["history"] = history
        save()
    }

    func clearRequirements(_ rs: [Requirement]) {
        reload()
        var all = choices
        for r in rs { all["req:" + r.id] = nil }
        store["choices"] = all
        save()
    }

    /// Settled: you agreed (status or verdict), it is a rule, or Claude verified it is built.
    func isConfirmed(_ r: Requirement) -> Bool {
        ["agreed", "rule", "built"].contains(r.status) || verdict("req:" + r.id).pickString == "agree"
    }
    func isOpen(_ r: Requirement) -> Bool { !isConfirmed(r) && verdict("req:" + r.id).pickString == nil }

    /// The roadmap chapter a requirements chapter is about (same words in the names), with its progress.
    func roadChapter(for group: String) -> (name: String, done: Int, total: Int)? {
        let gw = Self.words(group.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression))
        guard !gw.isEmpty else { return nil }
        var best: (String, Double)? = nil
        for t in Set(roadmap.map(\.track)) {
            let s = Double(gw.intersection(Self.words(t)).count) / Double(gw.count)
            if s > (best?.1 ?? 0) { best = (t, s) }
        }
        guard let b = best, b.1 >= 0.75 else { return nil }
        let p = ChapterProgress(roadmap.filter { $0.track == b.0 })   // the core, like the chapter header
        return (b.0, p.coreDone, p.core.count)
    }

    private func update(_ key: String, _ change: (inout [String: Any]) -> Void) {
        reload()                                     // never overwrite a newer save from the web board
        var all = choices
        var c = all[key] as? [String: Any] ?? [:]
        change(&c)
        c["at"] = Self.now()
        all[key] = c
        var history = store["history"] as? [Any] ?? []
        history.append(["id": key, "pick": c["pick"] ?? NSNull(), "text": "", "note": c["note"] ?? "", "at": c["at"]!])
        store["choices"] = all
        store["history"] = history
        save()
    }

    /// Through the board server when it runs (it backs up and pushes to git), else straight to the file.
    private func save() {
        guard let data = try? JSONSerialization.data(withJSONObject: store, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        let dir = project.boardDir, port = project.port
        DispatchQueue.global(qos: .userInitiated).async {
            if port > 0, BoardServers.isListening(port) {
                var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/decisions")!)
                req.httpMethod = "POST"
                req.httpBody = data
                let sem = DispatchSemaphore(value: 0)
                var ok = false
                URLSession.shared.dataTask(with: req) { _, r, _ in ok = (r as? HTTPURLResponse)?.statusCode == 204; sem.signal() }.resume()
                _ = sem.wait(timeout: .now() + 3)
                if ok { return }
            }
            let file = URL(fileURLWithPath: dir).appendingPathComponent("decisions.json")
            if let prev = try? Data(contentsOf: file) { try? prev.write(to: URL(fileURLWithPath: dir).appendingPathComponent("decisions.prev.json")) }
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: Watching

    private func watch() {
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let me = Unmanaged<BoardStore>.fromOpaque(info).takeUnretainedValue()
            if BoardStore.debug { FileHandle.standardError.write("fsevent\n".data(using: .utf8)!) }
            DispatchQueue.main.async { me.reload() }
        }
        guard let s = FSEventStreamCreate(nil, cb, &ctx, [project.boardDir] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }

    deinit {
        if let s = stream { FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s) }
    }
}

/// Hash of ALL the bytes (Data.hashValue only looks at the first 80 bytes, so later edits went unseen).
private func stamp(_ obj: Any) -> Int {
    guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return 0 }
    var h = Hasher()
    d.withUnsafeBytes { h.combine(bytes: $0) }
    return h.finalize()
}

private func str(_ v: Any?) -> String { (v as? String) ?? (v.map { "\($0)" } ?? "") }

/// Board text can hold simple HTML (<b>, <a>, <br>). Turn it into plain text with **bold** kept for Markdown.
enum BoardText {
    static func plain(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "</?(b|strong)>", with: "**", options: .regularExpression)
        s = s.replacingOccurrences(of: "<link[^>]*>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] { s = s.replacingOccurrences(of: a, with: b) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func attributed(_ html: String) -> AttributedString {
        (try? AttributedString(markdown: plain(html), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(plain(html))
    }
}

// MARK: - Item ↔ session links (sessions.json in the workspace, travels with git)

/// One Claude Code conversation started for a board item.
struct SessionLink: Codable, Hashable {
    var item: String            // "test:<id>", "choice:<id>", …
    var claudeSession: String   // Claude Code session id (UUID), resumable with `claude --resume`
    var intent: String
    var repo: String            // repo name from steerify.json
    var title: String?
    var started: String
    var by: String = "steerify"
    var dir: String? = nil      // the folder it ran in, when not the repo's checkout (feature worktree): resume needs it
}

enum SessionLinks {
    static func file(_ dir: String) -> URL { URL(fileURLWithPath: dir).appendingPathComponent("sessions.json") }

    static func load(_ dir: String) -> [SessionLink] {
        struct F: Codable { var links: [SessionLink] }
        guard let d = try? Data(contentsOf: file(dir)), let f = try? JSONDecoder().decode(F.self, from: d) else { return [] }
        return f.links
    }

    static func append(_ link: SessionLink, in dir: String) {
        struct F: Codable { var steerify = 1; var links: [SessionLink] }
        var all = load(dir)
        all.append(link)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let d = try? enc.encode(F(links: all)) { try? d.write(to: file(dir), options: .atomic) }
    }

    /// Is this Claude Code conversation still on this Mac (~/.claude/projects/*/<id>.jsonl)?
    static func resumable(_ id: String) -> Bool {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return false }
        return dirs.contains { FileManager.default.fileExists(atPath: root.appendingPathComponent("\($0)/\(id).jsonl").path) }
    }
}

// MARK: - Notes pinned on visuals (stored with the item's verdict in decisions.json)

struct Pin: Hashable {
    let img: String; let x: Double; let y: Double; let note: String; let at: String?
}

extension BoardStore {
    /// The decisions.json key that holds an item's verdict (and its pins).
    static func key(for ref: String) -> String {
        if ref.hasPrefix("test:") { return "ship:" + ref.dropFirst(5) }
        if ref.hasPrefix("choice:") { return String(ref.dropFirst(7)) }
        if ref.hasPrefix("req:") { return ref }
        return "pin:" + ref
    }

    func pins(_ ref: String) -> [Pin] {
        let c = choiceMap[Self.key(for: ref)] ?? [:]
        return (c["pins"] as? [[String: Any]] ?? []).compactMap {
            guard let img = $0["img"] as? String, let x = $0["x"] as? Double, let y = $0["y"] as? Double else { return nil }
            return Pin(img: img, x: x, y: y, note: $0["note"] as? String ?? "", at: $0["at"] as? String)
        }
    }

    func addPin(_ ref: String, img: String, x: Double, y: Double, note: String, version: Int? = nil) {
        editPins(ref) { list in
            var p: [String: Any] = ["img": img, "x": (x * 1000).rounded() / 1000, "y": (y * 1000).rounded() / 1000, "note": note]
            if let version { p["v"] = version }
            list.append(p)
        }
    }

    func removePin(_ ref: String, _ pin: Pin) {
        editPins(ref) { list in
            list.removeAll { ($0["img"] as? String) == pin.img && ($0["x"] as? Double) == pin.x && ($0["y"] as? Double) == pin.y }
        }
    }
}


extension Notification.Name {
    static let steerifyBoardReloaded = Notification.Name("SteerifyBoardReloaded")
    static let steerifyManifestChanged = Notification.Name("SteerifyManifestChanged")
}


// MARK: - Consolidation: what the board itself says about roadmap items (no tokens)

struct RoadProposal: Identifiable, Hashable {
    var id: String { item + "→" + to }
    let item: String           // exact roadmap text
    let from: String
    let to: String
    let evidence: String
    let sure: Bool             // explicit link (sure) or a strong text match (likely, unchecked by default)
    var fromCommit = false     // read from a recent commit (Local AI), never sure
    var fromSession = false    // read from a Claude session working on it (Local AI), never sure, never past wip
}

extension BoardStore {
    private static let stop: Set<String> = ["the", "and", "for", "with", "from", "this", "that", "via", "new", "now", "into", "only", "also", "when", "what"]
    static func words(_ s: String) -> Set<String> {
        let f = s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        return Set(f.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 && !stop.contains($0) })
    }

    /// Status the roadmap item should have, from its linked To test deliveries.
    func consolidation(track: String) -> [RoadProposal] {
        let order = ["todo": 0, "you": 1, "wip": 2, "review": 3, "done": 4]
        var out: [RoadProposal] = []
        for r in roadmap where r.track == track && r.status != "done" {
            let slug = BoardFiles.slug(r.text)
            let linked = ships.filter { $0.roads.contains { $0 == r.text || BoardFiles.slug($0) == slug } }
            var best: (String, String, Bool)? = nil            // (to, evidence, sure)
            func consider(_ s: ShipItem, sure: Bool) {
                let pick = effectivePick(s)
                let to: String, ev: String
                if pick == "ok" { to = "done"; ev = "OK on To test · “\(s.title)” v\(s.version)\(s.status == "live" ? " · live" : "")" }
                else if pick == "refine" || pick == "broken" { to = "wip"; ev = "\(pick!) on “\(s.title)”" }
                else { to = "review"; ev = "on To test · “\(s.title)”" }
                if best == nil || (order[to] ?? 0) > (order[best!.0] ?? 0) || (sure && !best!.2) { best = (to, ev, sure) }
            }
            linked.forEach { consider($0, sure: true) }
            if linked.isEmpty {
                // Strong text match only (most of the words of the roadmap item in the delivery's title).
                let w = Self.words(r.text)
                if w.count >= 3 {
                    for s in ships where effectivePick(s) == "ok" {
                        let tw = Self.words(s.title)
                        let hit = Double(w.intersection(tw).count) / Double(w.count)
                        if hit >= 0.6 { consider(s, sure: false) }
                    }
                }
            }
            if let b = best, (order[b.0] ?? 0) > (order[r.status] ?? 0) || (b.0 == "wip" && r.status == "review") {
                out.append(RoadProposal(item: r.text, from: r.status, to: b.0, evidence: b.1, sure: b.2))
            } else if best == nil, let c = commitProposals.first(where: { $0.item == r.text && $0.from == r.status }) {
                out.append(c)          // no delivery says anything: what the commits say
            } else if best == nil, let c = sessionProposals.first(where: { $0.item == r.text && $0.from == r.status }) {
                out.append(c)          // nor the commits: what a session working on it says
            }
        }
        return out
    }

    /// Set roadmap statuses (item text → status) and reload. Returns the previous statuses (for undo).
    @discardableResult
    func setRoad(_ changes: [(String, String)]) -> [(String, String)] {
        let before = changes.compactMap { c in roadmap.first { $0.text == c.0 }.map { ($0.text, $0.status) } }
        let dir = project.boardDir
        DispatchQueue.global(qos: .userInitiated).async {
            for (item, st) in changes { _ = SteerifyMCP.call("set_roadmap_status", ["item": item, "status": st], board: dir) }
            DispatchQueue.main.async { self.reload() }
        }
        return before
    }

    /// Set key-result kinds (item text → kind, nil = back to the guess) and reload. Returns the previous tags (for undo).
    @discardableResult
    func setRoadKind(_ changes: [(String, String?)]) -> [(String, String?)] {
        let before = changes.compactMap { c in roadmap.first { $0.text == c.0 }.map { ($0.text, $0.kindTag) } }
        let dir = project.boardDir
        DispatchQueue.global(qos: .userInitiated).async {
            for (item, k) in changes { _ = SteerifyMCP.call("set_roadmap_kind", ["item": item, "kind": k ?? ""], board: dir) }
            DispatchQueue.main.async { self.reload() }
        }
        return before
    }

    func applyRoad(_ ps: [RoadProposal]) {
        let dir = project.boardDir
        DispatchQueue.global(qos: .userInitiated).async {
            for p in ps { _ = SteerifyMCP.call("set_roadmap_status", ["item": p.item, "status": p.to], board: dir) }
            DispatchQueue.main.async { self.reload() }
        }
    }
}
