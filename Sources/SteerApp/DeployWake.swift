import Foundation

// MARK: - A deploy wakes the session that waited on it (request r261121-103942)
//
// You press Deploy on the Release tab. A Claude session that ended on "Next step: deploy the API…" (or "pushed but not
// deployed") is told, once it is idle, that the deploy is done, so it can check it, mark its items and update the
// roadmap and the request. Several deploys in a row (API, then UI) reach it as one message. No tokens: the match reads
// Claude's last reply from the transcript.

enum DeployWait {
    /// A sentence that leaves a deploy open: still to do, waited on, or asked for (not "I deployed it").
    static let deployWords = #"\bnot (yet )?(deployed|live|released|shipped)\b|\bneeds? (a |to )?(deploy|redeploy|release)|\b(next step|next|then|still|once|after|when|until|before)\b[^.]{0,40}\b(re)?deploy(ed|s|ing)?\b|\b(re)?deploy (the|it|them|both|to|api|ui|and)\b|\bdeploy button|\bwait(s|ing)? (on|for) (the |a )?(deploy|release)|\bready to (ship|deploy|release)|\bship (it|them)\b|\bgoes live\b"#

    /// Words that name a repo in prose: its full name, and the parts of the name no other repo of the project has
    /// ("ACME-API" → "API" when the others are ACME-UI, ACME-Local, ACME-website).
    static func names(of repo: String, among all: [String]) -> [String] {
        func parts(_ n: String) -> [String] {
            n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { $0.lowercased() }.filter { $0.count >= 2 }
        }
        let others = Set(all.filter { $0.lowercased() != repo.lowercased() }.flatMap(parts))
        return [repo.lowercased()] + parts(repo).filter { !others.contains($0) }
    }

    /// Does this reply wait on a deploy of `repo`? `own` = the session works in that repo; `single` = the project
    /// releases only one repo (any deploy sentence is about it).
    static func waits(_ reply: String, repo: String, allRepos: [String], own: Bool) -> Bool {
        let ss = SessionOutlookReader.sentences(reply).suffix(12)
        let deploySentences = ss.filter { $0.range(of: deployWords, options: [.regularExpression, .caseInsensitive]) != nil }
        guard !deploySentences.isEmpty else { return false }
        if own || allRepos.count <= 1 { return true }
        let names = names(of: repo, among: allRepos)
        return deploySentences.contains { s in
            names.contains { n in
                s.range(of: "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: n) + "(?![A-Za-z0-9])",
                        options: [.regularExpression, .caseInsensitive]) != nil
            }
        }
    }

    /// What the session is told.
    static func message(_ deploys: [(repo: String, commit: String)]) -> String {
        let what = deploys.map { "\($0.repo) (\($0.commit.prefix(7)))" }.joined(separator: " and ")
        return "Steerify just deployed \(what) from the Release tab. Pick up what waited on this deploy: check it is live "
            + "and run the checks you named, then update the board (To test items, roadmap status, the request) as the "
            + "steerify skill says. Items the user has not approved yet stay as they are.\r"
    }
}

/// Deploys waiting to be told to a session (by session id): sent when it is idle, 20 s after the last deploy.
struct PendingWake { var deploys: [(repo: String, commit: String)]; var at: Date }

extension AppModel {
    /// After a deploy of `repo` succeeded: queue a wake-up for every live Claude session whose last reply waits on it.
    func wakeAfterDeploy(_ repo: Repo, commit: String, in p: Project) {
        let released = (p.release?.repos.keys).map(Array.init) ?? p.repos.map(\.name)
        for s in sessions where s.projectId == p.id && s.kind == .claude && s.running && !s.dry {
            guard let cid = s.claudeId, let url = SessionSummaries.transcript(cid),
                  let reply = SessionOutlookReader.lastReply(url),
                  DeployWait.waits(reply, repo: repo.name, allRepos: released, own: s.repo.name == repo.name) else { continue }
            var w = deployWakes[s.id] ?? PendingWake(deploys: [], at: Date())
            w.deploys.removeAll { $0.repo == repo.name }
            w.deploys.append((repo.name, commit))
            w.at = Date()
            deployWakes[s.id] = w
            NSLog("steerify deploy-wake queued → \(s.title): \(repo.name)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 21) { [weak self] in self?.flushDeployWakes() }
    }

    /// Send queued deploy wake-ups to sessions that are idle now (called with the nudges).
    func flushDeployWakes() {
        guard !deployWakes.isEmpty else { return }
        for (id, w) in deployWakes {
            guard let s = sessions.first(where: { $0.id == id }), s.running else { deployWakes[id] = nil; continue }
            guard s.status == .idle, Date().timeIntervalSince(w.at) >= 20 else { continue }
            s.view.send(txt: DeployWait.message(w.deploys))
            deployWakes[id] = nil
            showToast("Deploy done → told \(s.title)", projectId: s.projectId)
        }
    }
}

// MARK: - Test hook: `Steerify --deploy-wake-check <workspace folder>` prints, per linked conversation, which repo
// deploys would wake it.
enum DeployWakeCheck {
    @MainActor static func run(_ folder: String) {
        guard let p = ProjectStore.read(folder) else { print("no steerify.json in \(folder)"); return }
        let b = BoardStore(project: Project(id: p.id, name: p.name, boardDir: p.boardDir, port: 0, repos: p.repos))
        let released = (p.release?.repos.keys).map(Array.init) ?? p.repos.map(\.name)
        var seen = Set<String>()
        for l in b.links.reversed() where seen.insert(l.claudeSession).inserted {
            guard let url = SessionSummaries.transcript(l.claudeSession), let reply = SessionOutlookReader.lastReply(url) else { continue }
            let hits = released.filter { DeployWait.waits(reply, repo: $0, allRepos: released, own: l.repo == $0) }
            guard !hits.isEmpty else { continue }
            print("\(l.started.prefix(16)) \(SessionName.short(l.title ?? l.item, intent: l.intent))  ·  wakes on: \(hits.sorted().joined(separator: ", "))")
        }
        fflush(stdout)
    }
}
