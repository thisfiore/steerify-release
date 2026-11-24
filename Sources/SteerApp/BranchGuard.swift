import Foundation

// MARK: - Branch guard (choice parallel-sessions-branch-safety A, request r261124-074236)
//
// Flow "main": every session of a project shares the repo's own checkout. One session that runs `git switch` /
// `git checkout -b` moves the folder under all the others, and they keep committing on a branch they don't know about.
// Steerify watches `.git/HEAD` of each shared checkout that has a Claude session open in it (FSEvents, no polling) and
// says it at once: which repo, which branch now, how many sessions share the folder, and that "Worktree per feature"
// is the cure. It says it again when the folder is back on the release branch.

@MainActor
final class BranchGuard {
    static let shared = BranchGuard()
    private var stream: FSEventStreamRef?
    private var watched: [String] = []                 // .git folders, sorted
    private var heads: [String: String] = [:]          // repo path → branch last seen
    /// Every AppModel that reported (the app has more than one: the window's and the app's own); held weakly.
    private var models: [ObjectIdentifier: () -> AppModel?] = [:]
    private var live: [AppModel] { models.values.compactMap { $0() } }
    /// Test hook (`--branch-guard-all`, test copies): prints what it sees.
    nonisolated static let testAll = CommandLine.arguments.contains("--branch-guard-all") && CommandLine.arguments.contains("--background")

    /// A tab working in the repo's own checkout: Claude or a plain terminal (not a one-shot deploy, not a feature folder).
    static func shares(_ s: TerminalSession) -> Bool { s.running && s.workdir == nil && s.shellCommand == nil }

    /// FSEvents reports real paths: a repo given as "<board>/.." or through /tmp must compare equal.
    nonisolated static func canon(_ p: String) -> String { URL(fileURLWithPath: p).resolvingSymlinksInPath().standardizedFileURL.path }

    /// What HEAD points at: the branch name, or "detached at <sha>".
    nonisolated static func head(_ repo: String) -> String? {
        guard let s = try? String(contentsOfFile: (repo as NSString).appendingPathComponent(".git/HEAD"), encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("ref: refs/heads/") { return String(t.dropFirst(16)) }
        return "detached at " + t.prefix(7)
    }

    /// Shared checkouts worth watching: flow main, a real `.git` folder (not a linked worktree), a session open in it.
    func update(_ model: AppModel) {
        models[ObjectIdentifier(model)] = { [weak model] in model }
        var repos: Set<String> = []
        for m in live { for s in m.sessions where BranchGuard.shares(s) {
            guard let p = m.projects.first(where: { $0.id == s.projectId }), WorkFlow.of(p) == .main else { continue }
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: (s.repo.path as NSString).appendingPathComponent(".git"), isDirectory: &dir), dir.boolValue {
                repos.insert(BranchGuard.canon(s.repo.path))
            }
        } }
        let gits = repos.map { ($0 as NSString).appendingPathComponent(".git") }.sorted()
        guard gits != watched else { return }
        watched = gits
        if BranchGuard.testAll { FileHandle.standardError.write("[branch-guard] watch \(gits.count) checkout(s), \(live.map(\.sessions.count).reduce(0, +)) session(s)\n".data(using: .utf8)!) }
        for r in repos where heads[r] == nil { heads[r] = BranchGuard.head(r) }
        heads = heads.filter { repos.contains($0.key) }
        if let s = stream { FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s); stream = nil }
        guard !gits.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, n, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<BranchGuard>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            // Any change in .git re-reads HEAD (one tiny file): FSEvents coalesces the HEAD.lock → HEAD rename unreliably.
            if BranchGuard.testAll { FileHandle.standardError.write("[branch-guard] \(n) event(s)\n".data(using: .utf8)!) }
            let touched = Set(list.prefix(n).compactMap { p -> String? in
                guard let r = p.range(of: "/.git/") ?? (p.hasSuffix("/.git") ? p.range(of: "/.git", options: .backwards) : nil) else { return nil }
                return BranchGuard.canon(String(p[..<r.lowerBound]))
            })
            guard !touched.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { me.check(touched) } }
        }
        guard let s = FSEventStreamCreate(nil, cb, &ctx, gits as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)) else { return }
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
        stream = s
    }

    private func check(_ repos: Set<String>) {
        for r in repos {
            guard let now = BranchGuard.head(r), let before = heads[r], now != before else { continue }
            heads[r] = now
            guard let m = live.first(where: { $0.sessions.contains { BranchGuard.shares($0) && BranchGuard.canon($0.repo.path) == r } }) else { continue }
            let sessions = m.sessions.filter { BranchGuard.shares($0) && BranchGuard.canon($0.repo.path) == r }
            guard let p = sessions.first.flatMap({ s in m.projects.first { $0.id == s.projectId } }) else { continue }
            let name = sessions.first?.repo.name ?? (r as NSString).lastPathComponent
            let release = p.release?.repos[name]?.branch ?? "main"
            if let msg = BranchGuard.message(repo: name, from: before, to: now, release: release, sessions: sessions.count) {
                NSLog("[Steerify] branch guard: \(name) \(before) → \(now)")
                if BranchGuard.testAll { FileHandle.standardError.write("[branch-guard] \(msg)\n".data(using: .utf8)!) }
                for w in live { w.showToast(msg, projectId: p.id) }   // every window says it (test copies have two models)
            }
        }
    }

    /// The toast text (nil = nothing worth saying). Pure, for the test hook.
    nonisolated static func message(repo: String, from: String, to: String, release: String, sessions: Int) -> String? {
        if to == release { return from == release ? nil : "✓ \(repo) is back on \(release)" }
        let shared = sessions > 1 ? " · \(sessions) sessions on it" : ""
        return "⚠ \(repo) left \(release) → \(to)\(shared) · parallel work: Worktree per feature"
    }
}

extension AppModel {
    /// Test hook: `--background --branch-guard-all <item ref>`: open two terminals in the first project's repo,
    /// so a `git switch` in its repo shows the warning (printed as `[branch-guard] …`).
    func branchGuardTestHook() {
        let a = CommandLine.arguments
        // `--background --dry-intake <request id>`: a dry intake session on that request of the first project (where it runs).
        if a.contains("--background"), let i = a.firstIndex(of: "--dry-intake"), i + 1 < a.count, let p = projects.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                var x = ItemRef(ref: "request:" + a[i + 1])!; x.title = "Request"
                self?.start(projectId: p.id, item: x, intent: .intake, dry: true)
            }
        }
        // `--background --git-state <repo path> <release branch>`: what the Release tab reads (with PRs), printed, then quit.
        if a.contains("--background"), let i = a.firstIndex(of: "--git-state"), i + 2 < a.count {
            let r = Repo(name: (a[i + 1] as NSString).lastPathComponent, path: a[i + 1])
            let g = Git.state(r, releaseBranch: a[i + 2], withPRs: true)
            FileHandle.standardError.write("[git-state] ready=\(g?.readyBranches.map { "\($0.name)+\($0.ahead)" } ?? []) merged=\(g?.mergedPRs.map { "\($0.name) \($0.url)" } ?? [])\n".data(using: .utf8)!)
            exit(0)
        }
        guard BranchGuard.testAll, let i = a.firstIndex(of: "--branch-guard-all"), i + 1 < a.count,
              let ref = ItemRef(ref: a[i + 1]), let p = projects.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.selectedProjectId = p.id
            _ = ref; _ = self.newSession(.shell); _ = self.newSession(.shell)   // two terminals sharing the checkout
            FileHandle.standardError.write("[branch-guard] watching \(self.sessions.count) session(s)\n".data(using: .utf8)!)
        }
    }
}
