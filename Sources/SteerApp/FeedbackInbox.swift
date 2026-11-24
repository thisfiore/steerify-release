import AppKit
import Foundation

// MARK: - Feedback inbox (choice feedback-intake A, request r261123-092352)
//
// A project's own users (people through the form, agents / MCP through the API) file on the Steerify relay
// (relay/feedback.mjs); the Mac pulls what came in onto the board as requests, then sends the board's state back so
// the relay can draw the roadmap page + each reporter's "Your requests" and mail every status change.
//
// steerify.json → "feedback": {"inbox": "<slug>", "url": "https://relay.steerify.dev", "areas": […], "hide": […], …}
// The inbox secret never lives in the repo: Keychain, service "steerify-feedback", account = the slug
// (scripts/feedback-inbox.sh registers a project and stores it).
// When: with the GitHub inbox (launch, wake, coming to the front), at most every 10 minutes per project.
// Order: pull → file → snapshot → ack, so a request is never invisible to its reporter in between.

struct FeedbackItem {
    let id, kind, title, text, page, version, source, agent, context, at: String
    let name, email: String
    let hasShot: Bool

    init?(_ o: [String: Any]) {
        guard let id = o["id"] as? String, !id.isEmpty else { return nil }
        let s = { (k: String) in (o[k] as? String) ?? "" }
        self.id = id; kind = s("kind"); title = s("title"); text = s("text"); page = s("page"); version = s("version")
        source = s("source"); agent = s("agent"); context = s("context"); at = s("at")
        let r = o["reporter"] as? [String: Any] ?? [:]
        name = (r["name"] as? String) ?? ""; email = (r["email"] as? String) ?? ""
        hasShot = (o["shot"] as? Bool) ?? false
    }

    var requestKind: RequestKind { kind == "bug" ? .fix : kind == "question" ? .question : .feature }
    var fromAgent: Bool { source == "agent" }

    /// The request text: title, details, then the facts the form collected.
    var requestText: String {
        var b = [title]
        if !text.isEmpty, text != title { b.append(text) }
        var facts: [String] = []
        if !page.isEmpty { facts.append("Where: \(page)") }
        if !version.isEmpty { facts.append("Version: \(version)") }
        if fromAgent, !context.isEmpty { facts.append("Agent context: \(context)") }
        if !facts.isEmpty { b.append(facts.joined(separator: "\n")) }
        return b.joined(separator: "\n\n")
    }
}

enum FeedbackInbox {
    /// (relay url, slug) from steerify.json → feedback.
    static func config(_ p: Project) -> (url: String, slug: String, feedback: [String: Any])? {
        guard let d = FileManager.default.contents(atPath: p.manifest),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let f = o["feedback"] as? [String: Any], let slug = f["inbox"] as? String,
              slug.range(of: #"^[a-z0-9][a-z0-9-]{3,60}$"#, options: .regularExpression) != nil else { return nil }
        let url = ((f["url"] as? String) ?? "https://relay.steerify.dev").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard url.hasPrefix("https://") || url.hasPrefix("http://127.0.0.1") || url.hasPrefix("http://localhost") else { return nil }
        return (url, slug, f)
    }

    /// The inbox secret from the Keychain (`security`, so the item made by scripts/feedback-inbox.sh opens without a prompt).
    static func secret(_ slug: String) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "steerify-feedback", "-a", slug, "-w"]
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return p.terminationStatus == 0 && !s.isEmpty ? s : nil
    }

    static func call(_ method: String, _ url: String, secret: String, json: Any? = nil) async -> (Data, String)? {
        guard let u = URL(string: url) else { return nil }
        var r = URLRequest(url: u, timeoutInterval: 30)
        r.httpMethod = method
        r.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
        r.setValue("Steerify", forHTTPHeaderField: "User-Agent")
        if let json, let body = try? JSONSerialization.data(withJSONObject: json) {
            r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (d, resp) = try? await URLSession.shared.data(for: r), let h = resp as? HTTPURLResponse, h.statusCode == 200 else { return nil }
        return (d, h.value(forHTTPHeaderField: "Content-Type") ?? "")
    }

    static func readJSON(_ path: String) -> [String: Any] {
        (FileManager.default.contents(atPath: path)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    /// What the relay needs to draw the pages and find status changes: chapters, what went live, the requests from
    /// outside (with a reporter). Nothing else of the board leaves the Mac.
    static func snapshot(_ p: Project, feedback: [String: Any]) -> [String: Any] {
        let board = readJSON((p.boardDir as NSString).appendingPathComponent("board.json"))
        let delivered = readJSON((p.boardDir as NSString).appendingPathComponent("delivered.json"))
        let keep = { (o: [String: Any], keys: [String]) in o.filter { keys.contains($0.key) } }
        let tracks = (board["tracks"] as? [[String: Any]] ?? []).map { keep($0, ["name", "area", "objective", "items", "draft", "rolling"]) }
        let live = (delivered["items"] as? [[String: Any]] ?? []).map { keep($0, ["id", "title", "area", "status", "updated", "added", "what", "road"]) }
        let reqs = RequestLog.raw(p.boardDir).filter { $0["reporter"] != nil }
            .map { keep($0, ["id", "title", "text", "kind", "status", "became", "at", "reporter", "feedback"]) }
        return ["feedback": keep(feedback, ["title", "areas", "hide", "keyResults"]), "tracks": tracks, "delivered": live, "requests": reqs]
    }
}

@MainActor
final class FeedbackInboxClock {
    static let shared = FeedbackInboxClock()
    var running = false
    var last: [String: Date] = [:]
    var sentHash: [String: Int] = [:]
}

@MainActor
extension AppModel {
    /// Test hook: `--feedback-inbox` (a test copy with STEERIFY_WORKSPACES + --scratch-writes): one forced run, then quit.
    func feedbackInboxTestHook() {
        guard CommandLine.arguments.contains("--feedback-inbox"), CommandLine.arguments.contains("--background") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.syncFeedbackInbox(force: true) {
                FileHandle.standardError.write("[feedback-inbox] done\n".data(using: .utf8)!); exit(0)
            }
        }
    }

    func syncFeedbackInbox(force: Bool = false, done: (() -> Void)? = nil) {
        let c = FeedbackInboxClock.shared
        guard TaskClock.enabled || force, AppModel.mayWriteBoards, !c.running else { done?(); return }
        let due = projects.compactMap { p -> (Project, String, String, [String: Any], String)? in
            guard let cfg = FeedbackInbox.config(p) else { return nil }
            if !force, let t = c.last[p.id], Date().timeIntervalSince(t) < 600 { return nil }
            guard let sec = FeedbackInbox.secret(cfg.slug) else { return nil }
            return (p, cfg.url, cfg.slug, cfg.feedback, sec)
        }
        guard !due.isEmpty else { done?(); return }
        c.running = true
        for (p, _, _, _, _) in due { c.last[p.id] = Date() }
        Task {
            for (p, url, slug, fb, sec) in due {
                let api = "\(url)/v1/feedback/\(slug)"
                var filed: [String] = []
                if let (d, _) = await FeedbackInbox.call("GET", api + "/inbox", secret: sec),
                   let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                    let items = (o["items"] as? [[String: Any]] ?? []).compactMap(FeedbackItem.init)
                    let known = Set(RequestLog.raw(p.boardDir).compactMap { $0["feedback"] as? String })
                    for i in items {
                        if !known.contains(i.id) {
                            var shot: (Data, String)? = nil
                            if i.hasShot { shot = await FeedbackInbox.call("GET", api + "/shot/\(i.id)", secret: sec) }
                            fileFeedback(i, slug: slug, in: p, shot: shot)
                        }
                        filed.append(i.id)
                    }
                    if !filed.isEmpty { board(for: p).reload(); notifyFeedback(filed.count, in: p) }
                }
                // The board's state: sent when it changed (and always right after filing, before the ack).
                let snap = FeedbackInbox.snapshot(p, feedback: fb)
                let h = ((try? JSONSerialization.data(withJSONObject: snap, options: .sortedKeys)) ?? Data()).hashValue
                if !filed.isEmpty || c.sentHash[p.id] != h {
                    if await FeedbackInbox.call("PUT", api + "/snapshot", secret: sec, json: snap) != nil { c.sentHash[p.id] = h }
                }
                if !filed.isEmpty { _ = await FeedbackInbox.call("POST", api + "/ack", secret: sec, json: ["ids": filed]) }
            }
            c.running = false
            done?()
        }
    }

    /// One item → one filed request (no session starts: you look first, as for GitHub issues).
    private func fileFeedback(_ i: FeedbackItem, slug: String, in p: Project, shot: (Data, String)?) {
        let id = RequestLog.newId() + "-fb" + String(i.id.suffix(6))   // two in the same second stay two
        var imgs: [String] = []
        if let (d, type) = shot, d.count < 10_000_000, type.hasPrefix("image/") {
            let rel = "img/requests"
            try? FileManager.default.createDirectory(atPath: (p.boardDir as NSString).appendingPathComponent(rel), withIntermediateDirectories: true)
            let ext = type.contains("png") ? "png" : type.contains("gif") ? "gif" : type.contains("webp") ? "webp" : "jpg"
            let r = "\(rel)/\(id)-1.\(ext)"
            if (try? d.write(to: URL(fileURLWithPath: (p.boardDir as NSString).appendingPathComponent(r)))) != nil { imgs.append(r) }
        }
        let b = board(for: p)
        let t = RequestTriage.classify(i.requestText, chapters: b.triageChapters, context: nil, lessons: TriageLessons.load(p.boardDir))
        let who = i.fromAgent ? "agent \(i.agent.isEmpty ? i.name : i.agent)" : (i.name.isEmpty ? "someone" : i.name)
        _ = RequestLog.edit(p.boardDir, id: id, create: true) { r in
            r["at"] = i.at.isEmpty ? RequestLog.now() : i.at; r["text"] = i.requestText; r["title"] = i.title
            r["kind"] = i.requestKind.rawValue; r["guess"] = i.requestKind.rawValue; r["chapter"] = t.chapter
            r["imgs"] = imgs; r["status"] = "filed"; r["became"] = [String](); r["area"] = b.areas.first?.key
            r["client"] = "feedback"; r["feedback"] = i.id; r["source"] = i.source
            r["reporter"] = ["name": i.name, "email": i.email]
            r["context"] = "feedback:\(slug)"; r["contextTitle"] = "Feedback form · \(who)"
        }
    }

    private func notifyFeedback(_ n: Int, in p: Project) {
        guard !CommandLine.arguments.contains("--background") else {
            FileHandle.standardError.write("[feedback-inbox] \(p.id): \(n) new\n".data(using: .utf8)!); return
        }
        let msg = n == 1 ? "1 new request from \(p.name)'s users: it's in Ready" : "\(n) new requests from \(p.name)'s users: they're in Ready"
        _ = SteerifyMCP.call("notify", ["message": msg], board: p.boardDir)
    }
}
