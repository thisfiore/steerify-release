import AppKit
import Foundation

// MARK: - What you did on the iPhone, landing on the board (choice mobile-sync: GitHub is the store, our server adds realtime)
//
// The phone never writes the Mac's files. It keeps one file of its own on GitHub, `<board>/inbox/<device>.json`:
//   {"device": "…", "items": [{"id", "kind": verdict|testNote|pick|request|start|ship|deploy|taskVerdict|taskRun, "ref", "pick", "note", "test",
//                              "requestKind", "intent", "target", "label", "at"}]}
// The Mac fetches, applies each new item with the same code as a click on the Mac (setShip / setTest / setChoice /
// fileRequest / starts.json), and records what it applied in `<board>/inbox-applied.json`, which it commits and pushes:
// the phone reads it and drops those items. Only the phone touches inbox/, only the Mac touches inbox-applied.json, so
// pulling the phone's commits never conflicts.
// When: at launch, on wake, when Steerify comes to the front (no polling; the Steerify server will add "pull now").

enum PhoneInbox {
    static func appliedFile(_ boardDir: String) -> String { (boardDir as NSString).appendingPathComponent("inbox-applied.json") }

    static func applied(_ boardDir: String) -> [String: Any] {
        guard let d = FileManager.default.contents(atPath: appliedFile(boardDir)),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
        return o["items"] as? [String: Any] ?? [:]
    }

    static func writeApplied(_ boardDir: String, _ items: [String: Any]) {
        let o: [String: Any] = ["steerify": 1, "items": items]
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: URL(fileURLWithPath: appliedFile(boardDir)), options: .atomic)
        }
    }

    /// A file from git as bytes, written to a temporary file (Git.run reads text only).
    static func blob(root: String, ref: String) -> String? {
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("steerify-phone-\(UUID().uuidString).jpg")
        FileManager.default.createFile(atPath: dst.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: dst) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root, "cat-file", "blob", ref]
        p.standardOutput = fh; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit(); try? fh.close()
        let size = (try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Int) ?? 0
        return p.terminationStatus == 0 && size > 0 ? dst.path : nil
    }

    struct Fetched { let root: String; let rel: String; let branch: String; let items: [[String: Any]]; let current: Bool }

    /// git work, off the main thread: fetch, take in commits that only touch inbox/, read every inbox file from origin.
    static func fetch(boardDir: String) -> Fetched? {
        guard let root = Git.run(boardDir, ["rev-parse", "--show-toplevel"])?.trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty,
              let branch = Git.run(root, ["rev-parse", "--abbrev-ref", "HEAD"])?.trimmingCharacters(in: .whitespacesAndNewlines), branch != "HEAD",
              Git.run(root, ["remote"])?.contains("origin") == true else { return nil }
        let realRoot = (root as NSString).resolvingSymlinksInPath, realBoard = (boardDir as NSString).resolvingSymlinksInPath
        guard realBoard.hasPrefix(realRoot) else { return nil }
        let rel = String(realBoard.dropFirst(realRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let inboxDir = rel.isEmpty ? "inbox" : rel + "/inbox"
        let boardRel = rel
        guard Git.run(root, ["fetch", "-q", "origin", branch]) != nil else { return nil }
        let remote = "origin/" + branch
        // Phone commits only: fast to take in, cannot conflict. Anything else waits for the project's own flow.
        var current = (Git.run(root, ["rev-list", "--count", "HEAD.." + remote])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "1") == "0"
        if !current {
            let files = (Git.run(root, ["diff", "--name-only", "HEAD..." + remote]) ?? "").split(separator: "\n").map(String.init)
            if !files.isEmpty, files.allSatisfy({ $0.hasPrefix(inboxDir + "/") }) {
                current = Git.run(root, ["pull", "-q", "--rebase", "--autostash", "origin", branch]) != nil
            }
        }
        var items: [[String: Any]] = []
        let list = (Git.run(root, ["ls-tree", "--name-only", remote, inboxDir + "/"]) ?? "").split(separator: "\n").map(String.init)
        for path in list where path.hasSuffix(".json") {
            guard let text = Git.run(root, ["show", remote + ":" + path]), let d = text.data(using: .utf8),
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            let device = o["device"] as? String ?? (path as NSString).lastPathComponent
            for var it in o["items"] as? [[String: Any]] ?? [] {
                it["device"] = device
                // A request's screenshots: out of git into temporary files (fileRequest copies them into img/requests/).
                if let imgs = it["images"] as? [String], !imgs.isEmpty {
                    it["localImages"] = imgs.compactMap { rel -> String? in
                        guard !rel.contains(".."), rel.hasPrefix("inbox/files/") else { return nil }   // only the phone's own pictures
                        return blob(root: root, ref: remote + ":" + (boardRel.isEmpty ? rel : boardRel + "/" + rel))
                    }
                }
                items.append(it)
            }
        }
        return Fetched(root: root, rel: rel, branch: branch, items: items, current: current)
    }
}

@MainActor
final class PhoneInboxClock {
    static let shared = PhoneInboxClock()
    var running = false
    var observing = false
}

@MainActor
extension AppModel {
    func startPhoneInbox() {
        let c = PhoneInboxClock.shared
        guard !c.observing else { return }
        c.observing = true
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPhoneInbox() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncPhoneInbox() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.syncPhoneInbox() }
    }

    func syncPhoneInbox() {
        guard TaskClock.enabled, !PhoneInboxClock.shared.running else { return }
        PhoneInboxClock.shared.running = true
        let list = projects.map { ($0.id, $0.boardDir) }
        DispatchQueue.global(qos: .utility).async {
            let got = list.compactMap { id, dir in PhoneInbox.fetch(boardDir: dir).map { (id, dir, $0) } }
            DispatchQueue.main.async {
                for (id, dir, f) in got { self.applyPhoneInbox(projectId: id, boardDir: dir, f) }
                PhoneInboxClock.shared.running = false
            }
        }
    }

    private func applyPhoneInbox(projectId: String, boardDir: String, _ f: PhoneInbox.Fetched) {
        guard let p = projects.first(where: { $0.id == projectId }) else { return }
        var done = PhoneInbox.applied(boardDir)
        let fresh = f.items.filter { done[$0["id"] as? String ?? ""] == nil }.sorted { ($0["at"] as? String ?? "") < ($1["at"] as? String ?? "") }
        guard !fresh.isEmpty else { return }
        let b = board(for: p)
        b.reload()
        var n = 0
        var answers: [(key: String, change: (inout [String: Any]) -> Void)] = []
        for it in fresh {
            guard let id = it["id"] as? String, !id.isEmpty else { continue }
            let why = applyPhoneItem(it, board: b, project: p, answers: &answers)
            var rec: [String: Any] = ["at": BoardStore.now(), "ok": why == nil]
            if let why { rec["why"] = why } else { n += 1 }
            done[id] = rec
        }
        b.updateMany(answers)                              // verdicts, test notes, picks: one save
        PhoneInbox.writeApplied(boardDir, done)
        if n > 0 { showToast("From your iPhone: \(n) change\(n == 1 ? "" : "s") on the board", projectId: p.id) }
        // Tell the phone: commit + push only the applied list (the rest of the board follows the project's own commits).
        guard f.current else { return }
        let path = f.rel.isEmpty ? "inbox-applied.json" : f.rel + "/inbox-applied.json"
        let root = f.root, branch = f.branch
        DispatchQueue.global(qos: .utility).async {
            _ = Git.run(root, ["add", path])
            if Git.run(root, ["commit", "-q", "-m", "iPhone: \(fresh.count) applied", "--", path]) != nil,
               Git.run(root, ["push", "-q", "origin", branch]) != nil {
                DispatchQueue.main.async { self.relayPull(p, why: "applied") }     // the phone reads the board again now
            }
        }
    }

    /// nil = applied; otherwise why not (the phone shows it).
    private func applyPhoneItem(_ it: [String: Any], board b: BoardStore, project p: Project,
                                answers: inout [(key: String, change: (inout [String: Any]) -> Void)]) -> String? {
        let ref = it["ref"] as? String ?? "", note = it["note"] as? String ?? "", pick = it["pick"] as? String
        switch it["kind"] as? String {
        case "verdict":
            let sid = ref.replacingOccurrences(of: "ship:", with: "")
            guard let s = b.ships.first(where: { $0.id == sid }), let pick else { return "Not on To test: \(sid)" }
            let v = s.version   // same rules as BoardStore.setShip
            answers.append(("ship:" + sid, { c in
                if (c["v"] as? Int) != v { c["pick"] = nil; c["tests"] = nil; c["v"] = v }
                c["pick"] = pick
                if !note.isEmpty { c["note"] = note }
            }))
            if pick == "ok" { b.markBuilt(by: s) }
        case "testNote":
            let sid = ref.replacingOccurrences(of: "ship:", with: "")
            guard let s = b.ships.first(where: { $0.id == sid }), let n = it["test"] as? Int, n >= 1, n <= s.tests.count else { return "Not on To test: \(sid)" }
            let v = s.version, ok = pick == "ok"   // same shape as BoardStore.setTest: tests["<i>"] = {ok: true} | {note}
            answers.append(("ship:" + sid, { c in
                if (c["v"] as? Int) != v { c["pick"] = nil; c["tests"] = nil; c["v"] = v }
                var tests = c["tests"] as? [String: Any] ?? [:]
                tests[String(n - 1)] = ok ? ["ok": true] : ["note": note]
                c["tests"] = tests
            }))
        case "pick":
            guard b.decisions.contains(where: { $0.id == ref }), let pick else { return "Choice not on the board: \(ref)" }
            answers.append((ref, { c in                // same as BoardStore.setChoice
                c["pick"] = pick
                if !note.isEmpty { c["note"] = note }
                c["parked"] = nil
            }))
        case "request":
            let kind = RequestKind(rawValue: it["requestKind"] as? String ?? "") ?? .refine
            let shots = (it["localImages"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
            defer { for u in shots { try? FileManager.default.removeItem(at: u) } }
            let chapter = (it["chapter"] as? String).flatMap { c in b.chapters.contains { $0.name == c } ? c : nil }
            guard fileRequest(projectId: p.id, text: note, kind: kind, chapter: chapter, images: shots, context: nil,
                              contextTitle: nil, client: "iphone", fileOnly: false) != nil else { return "Couldn't file the request" }
        case "pin":     // a note pinned on a picture (test:<id> or choice:<id>), same shape as BoardStore.addPin
            guard let img = it["img"] as? String, let x = it["x"] as? Double, let y = it["y"] as? Double, !note.isEmpty else { return "Pin without a place or a note" }
            let key = BoardStore.key(for: ref)
            let v = ref.hasPrefix("test:") ? b.ships.first { "test:" + $0.id == ref }?.version : nil
            if ref.hasPrefix("test:"), v == nil { return "Not on To test: \(ref)" }
            if ref.hasPrefix("choice:"), !b.decisions.contains(where: { "choice:" + $0.id == ref }) { return "Choice not on the board: \(ref)" }
            answers.append((key, { c in
                var list = c["pins"] as? [[String: Any]] ?? []
                var pin: [String: Any] = ["img": img, "x": (x * 1000).rounded() / 1000, "y": (y * 1000).rounded() / 1000, "note": note, "at": BoardStore.now()]
                if let v { pin["v"] = v }
                list.append(pin)
                c["pins"] = list
            }))
        case "sessionName":   // rename a Mac session (ref = its Claude conversation id; empty note = Steerify's name)
            guard !ref.isEmpty else { return "Which session?" }
            _ = applyPhoneLabel(projectId: p.id, boardDir: p.boardDir, claudeId: ref, name: .some(note))
        case "sessionPin":    // pin = "on" | "off"
            guard !ref.isEmpty else { return "Which session?" }
            _ = applyPhoneLabel(projectId: p.id, boardDir: p.boardDir, claudeId: ref, pinned: pick == "on")
        case "chapter":       // a draft chapter: pick = "approve" (Add to roadmap) | "discard", same as the Mac's draft panel
            guard let ch = b.chapters.first(where: { $0.name == ref }) else { return "No chapter \(ref)" }
            guard ch.draft else { return nil }                    // already approved (or approved twice): nothing to do
            let approve = pick == "approve"
            let r = SteerifyMCP.call(approve ? "approve_chapter" : "discard_chapter", ["name": ref], board: p.boardDir)
            if r.1 { return r.0 }
            if let id = ch.request {
                RequestLog.edit(p.boardDir, id: id) { x in
                    x["status"] = approve ? "approved" : "discarded"
                    if approve { x["became"] = Array(NSOrderedSet(array: (x["became"] as? [String] ?? []) + ["track:" + BoardFiles.slug(ref)])) }
                }
            }
            b.reload()
        case "ship":          // Release → "Ship on the Mac": the Release tab's Prepare release (choice ios-release-scope, pick A)
            guard p.release != nil else { return "No release setup on the Mac yet" }
            var x = ItemRef(ref: "release:" + p.id)!; x.title = "Release: " + p.name
            guard start(projectId: p.id, item: x, intent: .ship, focus: false) != nil else { return "Couldn't start the release" }
        case "deploy":        // ref = the repo: its deploy command, in a shell tab, exactly as the Release tab's Deploy
            guard let repo = p.repos.first(where: { $0.name == ref }) ?? p.resolveRepo(ref) else { return "No repo \(ref)" }
            guard let cmd = p.release?.repos[repo.name]?.deploy, !cmd.isEmpty else { return "\(repo.name) has no deploy command" }
            deploy(repo, in: p)
        case "taskVerdict":   // ref = run id · pick = ok | redo (Redo runs it again with your note), same as the Tasks tab
            guard let run = TaskStore.load(p.boardDir).runs.first(where: { $0.id == ref }) else { return "No task run \(ref)" }
            guard run.status == "done" else { return nil }        // already checked (here or on the Mac)
            setRunVerdict(projectId: p.id, run: run, ok: pick == "ok", note: note)
        case "taskRun":       // ref = task id: Run now
            guard TaskStore.load(p.boardDir).tasks.contains(where: { $0.id == ref }) else { return "No task \(ref)" }
            if TaskStore.load(p.boardDir).runs.contains(where: { $0.task == ref && $0.status == "running" }) { return nil }   // already running
            guard runTask(projectId: p.id, taskId: ref, note: note.isEmpty ? nil : note, focus: false) != nil else { return "Couldn't start the task" }
        case "start":
            StartQueue.append(p.boardDir, [
                "id": it["id"] as? String ?? UUID().uuidString, "ref": ref, "intent": it["intent"] as? String ?? "plan", "note": note,
                "target": "mac", "at": it["at"] as? String ?? StartQueue.now(), "from": "iphone", "state": "queued",
            ])
        default:
            // The phone is newer than this Mac build (e.g. "deploy" from a Mac built before it existed, 22 Nov).
            return "Steerify on this Mac is older than the iPhone app: update it, then tap again"
        }
        return nil
    }
}

// MARK: - The board on GitHub stays current (feedback 21 Nov: the phone showed old choices)
//
// The phone reads the board from GitHub, so a project with a paired phone (a relay channel in steerify.json) gets its
// board files committed and pushed ~30 s after they change: board, decisions, requests, starts, delivered, tasks, deploys and the
// pictures. Only those paths (sessions.json, perf.jsonl, decisions.prev.json stay local). Incoming phone commits are taken
// in first; anything else on the remote is rebased the same way, and a rebase that does not apply cleanly is aborted and
// tried again on the next change. Then the phone is told to pull (relay).

@MainActor
final class BoardPublishClock {
    static let shared = BoardPublishClock()
    var pending: [String: DispatchWorkItem] = [:]     // project id → scheduled publish
    var running = Set<String>()
    var observing = false
}

@MainActor
extension AppModel {
    func startBoardPublish() {
        let c = BoardPublishClock.shared
        guard !c.observing else { return }
        c.observing = true
        NotificationCenter.default.addObserver(forName: .steerifyBoardReloaded, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleBoardPublish(); self?.publishStatus() }   // your turn / done depend on the board
        }
        NotificationCenter.default.addObserver(forName: .steerifyAreasPublished, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleBoardPublish() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.scheduleBoardPublish(delay: 1) }
    }

    func scheduleBoardPublish(delay: Double = 30) {
        guard TaskClock.enabled else { return }
        let c = BoardPublishClock.shared
        for p in projects where RelayConfig.of(p) != nil {      // only projects paired with a phone
            if c.pending[p.id] != nil { continue }               // at most one publish per 30 s (sessions.json changes all the time)
            let pid = p.id, dir = p.boardDir
            let w = DispatchWorkItem { [weak self] in self?.publishBoard(projectId: pid, boardDir: dir) }
            c.pending[p.id] = w
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
        }
    }

    private func publishBoard(projectId: String, boardDir: String) {
        let c = BoardPublishClock.shared
        c.pending[projectId] = nil
        guard !c.running.contains(projectId) else { scheduleBoardPublish(); return }
        c.running.insert(projectId)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let pushed = BoardPublish.run(boardDir: boardDir)
            DispatchQueue.main.async {
                c.running.remove(projectId)
                guard let self, pushed, let p = self.projects.first(where: { $0.id == projectId }) else { return }
                self.relayPull(p, why: "board")
            }
        }
    }
}

enum BoardPublish {
    static let files = ["board.json", "decisions.json", "requests.json", "starts.json", "delivered.json", "tasks.json", "inbox-applied.json", "steerify.json", "session-labels.json", "areas.json", "deploys.json"]

    /// Commit the board files that changed and push. true = something reached GitHub.
    static func run(boardDir: String) -> Bool {
        guard let root = Git.run(boardDir, ["rev-parse", "--show-toplevel"]), !root.isEmpty,
              let branch = Git.run(root, ["rev-parse", "--abbrev-ref", "HEAD"]), branch != "HEAD" else { return false }
        let realRoot = (root as NSString).resolvingSymlinksInPath, realBoard = (boardDir as NSString).resolvingSymlinksInPath
        guard realBoard.hasPrefix(realRoot) else { return false }
        let rel = String(realBoard.dropFirst(realRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        func path(_ f: String) -> String { rel.isEmpty ? f : rel + "/" + f }
        let paths = files.map(path).filter { FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent($0)) }
            + [path("img"), path("protos"), path("kit")].filter { FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent($0)) }
        _ = Git.run(root, ["add", "--"] + paths)
        let staged = (Git.run(root, ["diff", "--cached", "--name-only", "--"] + paths) ?? "").isEmpty == false
        if staged { _ = Git.run(root, ["commit", "-q", "-m", "Board: synced for the iPhone", "--"] + paths) }
        // Ahead of GitHub? (just committed, or earlier board commits not pushed yet)
        _ = Git.run(root, ["fetch", "-q", "origin", branch])
        let ahead = Int(Git.run(root, ["rev-list", "--count", "origin/\(branch)..HEAD"]) ?? "0") ?? 0
        guard ahead > 0 else { return false }
        let behind = Int(Git.run(root, ["rev-list", "--count", "HEAD..origin/\(branch)"]) ?? "0") ?? 0
        if behind > 0, Git.run(root, ["pull", "-q", "--rebase", "--autostash", "origin", branch]) == nil {
            _ = Git.run(root, ["rebase", "--abort"])          // not clean: leave it, try again on the next change
            return false
        }
        return Git.run(root, ["push", "-q", "origin", branch]) != nil
    }
}
