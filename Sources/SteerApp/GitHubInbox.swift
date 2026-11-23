import AppKit
import Foundation

// MARK: - GitHub Issues as the inbox (chapter "Distribution, updates + feedback on GitHub")
//
// A project that says where its public issues live, in steerify.json:
//   "issues": {"repo": "owner/name"}
// gets every open issue there as a request on its board (requests.json), once: the request keeps the issue's URL
// in "issue", so the same issue is never filed twice. Bug → Fix, enhancement → New feature, question → Question.
// Issues are written by anyone: they land as "filed" (no Claude session starts by itself); you press Start.
// Screenshots in the issue (GitHub attachments) come along into img/requests/.
// When: at launch, on wake, when Steerify comes to the front, at most every 10 minutes per project.
// Auth: none needed for a public repo; with `gh` logged in, its token is used (private repos, higher rate limit).

struct GitHubIssue {
    let number: Int
    let title: String
    let body: String
    let url: String
    let author: String
    let labels: [String]
    let createdAt: String
    let images: [URL]

    /// The kind the issue says itself (its label, or the form's "Bug: " / "Feature: " title); nil = Steerify guesses.
    var statedKind: RequestKind? {
        let l = Set(labels.map { $0.lowercased() })
        if l.contains("bug") { return .fix }
        if l.contains("enhancement") || l.contains("feature") { return .feature }
        if l.contains("question") { return .question }
        let t = title.lowercased()
        if t.hasPrefix("bug") { return .fix }
        if t.hasPrefix("feature") || t.hasPrefix("idea") { return .feature }
        return nil
    }

    /// The request text: title, then the body without the form's empty answers.
    var text: String {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { $0.trimmingCharacters(in: .whitespaces) != "_No response_" }
        var b = lines.joined(separator: "\n")
        while b.contains("\n\n\n") { b = b.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        b = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.count > 4000 { b = String(b.prefix(3997)) + "…" }
        return b.isEmpty ? title : title + "\n\n" + b
    }
}

enum GitHubInbox {
    /// steerify.json → "issues": {"repo": "owner/name"} (read directly: the key is optional and new).
    static func repo(_ p: Project) -> String? {
        guard let d = FileManager.default.contents(atPath: p.manifest),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let r = (o["issues"] as? [String: Any])?["repo"] as? String else { return nil }
        let parts = r.split(separator: "/")
        return parts.count == 2 && parts.allSatisfy({ $0.allSatisfy { $0.isLetter || $0.isNumber || "-_.".contains($0) } }) ? r : nil
    }

    /// `gh auth token`, if gh is installed and logged in.
    static func token() -> String? {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = ["auth", "token"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let d = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let t = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return p.terminationStatus == 0 && !t.isEmpty ? t : nil
        }
        return nil
    }

    static func get(_ url: URL, token: String?) async -> Data? {
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("Steerify", forHTTPHeaderField: "User-Agent")
        if let token { r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return d
    }

    /// Picture links in an issue body that GitHub hosts (attachments), at most 4.
    static func images(in body: String) -> [URL] {
        let pattern = #"(?:!\[[^\]]*\]\((https://[^)\s]+)\))|(?:<img[^>]*src="(https://[^"]+)")"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = body as NSString
        var out: [URL] = []
        for m in re.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            for i in 1...2 where m.range(at: i).location != NSNotFound {
                guard let u = URL(string: ns.substring(with: m.range(at: i))), let h = u.host?.lowercased() else { continue }
                let ok = (h == "github.com" && u.path.hasPrefix("/user-attachments/")) || h.hasSuffix(".githubusercontent.com")
                if ok, !out.contains(u) { out.append(u) }
            }
        }
        return Array(out.prefix(4))
    }

    /// Open issues (pull requests left out), oldest first.
    static func fetch(repo: String) async -> [GitHubIssue]? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/issues?state=open&per_page=50&sort=created&direction=asc") else { return nil }
        let tok = token()
        guard let d = await get(url, token: tok), let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return nil }
        return arr.compactMap { o in
            guard o["pull_request"] == nil, let n = o["number"] as? Int, let url = o["html_url"] as? String else { return nil }
            let body = o["body"] as? String ?? ""
            return GitHubIssue(number: n, title: o["title"] as? String ?? "Issue #\(n)", body: body, url: url,
                               author: (o["user"] as? [String: Any])?["login"] as? String ?? "someone",
                               labels: (o["labels"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String },
                               createdAt: o["created_at"] as? String ?? "", images: images(in: body))
        }
    }

    /// One picture into a temporary file (≤ 10 MB, images only).
    static func download(_ u: URL, token: String?) async -> URL? {
        var r = URLRequest(url: u, timeoutInterval: 30)
        r.setValue("Steerify", forHTTPHeaderField: "User-Agent")
        if let token, u.host == "github.com" { r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        guard let (d, resp) = try? await URLSession.shared.data(for: r), let h = resp as? HTTPURLResponse, h.statusCode == 200,
              d.count < 10_000_000, let type = h.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("image/") else { return nil }
        let ext = type.contains("png") ? "png" : type.contains("gif") ? "gif" : type.contains("webp") ? "webp" : "jpg"
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("steerify-issue-\(UUID().uuidString).\(ext)")
        return (try? d.write(to: dst)) != nil ? dst : nil
    }
}

@MainActor
final class GitHubInboxClock {
    static let shared = GitHubInboxClock()
    var running = false
    var observing = false
    var last: [String: Date] = [:]
}

@MainActor
extension AppModel {
    func startGitHubInbox() {
        let c = GitHubInboxClock.shared
        guard !c.observing else { return }
        c.observing = true
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncGitHubIssues(); self?.syncFeedbackInbox() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncGitHubIssues(); self?.syncFeedbackInbox() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.syncGitHubIssues(); self?.syncFeedbackInbox() }
        feedbackInboxTestHook()   // FeedbackInbox.swift: the users' feedback inbox runs on the same clock
    }

    /// `force`: ignore the 10-minute spacing (the --github-inbox test hook).
    func syncGitHubIssues(force: Bool = false, done: (() -> Void)? = nil) {
        let c = GitHubInboxClock.shared
        guard TaskClock.enabled || force, !c.running else { done?(); return }
        let due = projects.compactMap { p -> (Project, String)? in
            guard let r = GitHubInbox.repo(p) else { return nil }
            if !force, let t = c.last[p.id], Date().timeIntervalSince(t) < 600 { return nil }
            return (p, r)
        }
        guard !due.isEmpty else { done?(); return }
        c.running = true
        for (p, _) in due { c.last[p.id] = Date() }
        Task {
            for (p, repo) in due {
                guard let issues = await GitHubInbox.fetch(repo: repo) else { continue }
                let known = Set(RequestLog.raw(p.boardDir).compactMap { $0["issue"] as? String })
                let fresh = issues.filter { !known.contains($0.url) }
                guard !fresh.isEmpty else { continue }
                let tok = fresh.contains(where: { !$0.images.isEmpty }) ? GitHubInbox.token() : nil
                for issue in fresh {
                    var shots: [URL] = []
                    for u in issue.images { if let f = await GitHubInbox.download(u, token: tok) { shots.append(f) } }
                    fileIssue(issue, repo: repo, in: p, shots: shots)
                    for f in shots { try? FileManager.default.removeItem(at: f) }
                }
                board(for: p).reload()
                notifyIssues(fresh.count, in: p)
            }
            c.running = false
            done?()
        }
    }

    /// One issue → one filed request (no roadmap item, no session: you look first).
    private func fileIssue(_ i: GitHubIssue, repo: String, in p: Project, shots: [URL]) {
        let id = RequestLog.newId() + "-gh\(i.number)"
        let rel = "img/requests"
        try? FileManager.default.createDirectory(atPath: (p.boardDir as NSString).appendingPathComponent(rel), withIntermediateDirectories: true)
        var imgs: [String] = []
        for (n, u) in shots.enumerated() {
            let r = "\(rel)/\(id)-\(n + 1).\(u.pathExtension.isEmpty ? "png" : u.pathExtension)"
            if (try? FileManager.default.copyItem(atPath: u.path, toPath: (p.boardDir as NSString).appendingPathComponent(r))) != nil { imgs.append(r) }
        }
        let b = board(for: p)
        // No label: the same local triage as the New request sheet (words + your past corrections), chapter included.
        let t = RequestTriage.classify(i.text, chapters: b.triageChapters, context: nil, lessons: TriageLessons.load(p.boardDir))
        let kind = i.statedKind ?? t.kind
        RequestLog.edit(p.boardDir, id: id, create: true) { r in
            r["at"] = RequestLog.now(); r["text"] = i.text; r["kind"] = kind.rawValue; r["guess"] = kind.rawValue
            r["chapter"] = t.chapter
            r["imgs"] = imgs; r["status"] = "filed"; r["became"] = [String](); r["area"] = b.areas.first?.key
            r["client"] = "github"; r["issue"] = i.url
            r["context"] = i.url; r["contextTitle"] = "GitHub \(repo) #\(i.number) · @\(i.author)"
        }
    }

    private func notifyIssues(_ n: Int, in p: Project) {
        guard !CommandLine.arguments.contains("--background") else {   // test copies: print, never toast in the real app
            FileHandle.standardError.write("[github-inbox] \(p.id): \(n) new\n".data(using: .utf8)!); return
        }
        let msg = n == 1 ? "1 new GitHub issue on \(p.name): it's in Requests" : "\(n) new GitHub issues on \(p.name): they're in Requests"
        _ = SteerifyMCP.call("notify", ["message": msg], board: p.boardDir)
    }
}
