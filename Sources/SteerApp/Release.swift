import SwiftUI
import AppKit

/// How a project releases, set up once and kept in steerify.json ("release").
struct ReleaseConfig: Codable, Hashable {
    struct RepoRelease: Codable, Hashable {
        var branch: String
        var deploy: String?        // command Steerify runs in a visible shell tab (your SSH, your keys)
        var liveCheck: String?     // URL returning JSON with "commit" (+ "committedAt"): tells which version is live
    }
    var repos: [String: RepoRelease]
    var notes: String?
    var flow: String?          // how sessions use git: main | worktree | pr (Flow.swift); nil = the Settings default
}

/// Per-project automation, in steerify.json ("automation").
struct Automation: Codable, Hashable {
    var pingIdle: Bool?
    var delaySeconds: Int?
}

/// Git state of one repo, read on demand (never polled).
struct RepoGit: Identifiable {
    var id: String { name }
    let name: String
    let branch: String
    let dirty: Int
    let unpushed: Int
    let readyBranches: [(name: String, ahead: Int)]
}

enum Git {
    static func run(_ dir: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir] + args
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        // Never waitUntilExit here: on the main thread it spins the run loop, SwiftUI then updates
        // in the middle of a view update and aborts (crash 19 Nov, Release tab).
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        guard (try? p.run()) != nil else { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        done.wait()
        return p.terminationStatus == 0 ? String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    static func state(_ repo: Repo, releaseBranch: String, ignoring: String? = nil) -> RepoGit? {
        guard repo.exists, let branch = run(repo.path, ["rev-parse", "--abbrev-ref", "HEAD"]) else { return nil }
        // The board folder (verdicts, sessions…) changes all the time: it is not unshipped work.
        var pathspec = ["--", "."]
        if let ig = ignoring, ig.hasPrefix(repo.path + "/") { pathspec.append(":!" + String(ig.dropFirst(repo.path.count + 1))) }
        let dirty = (run(repo.path, ["status", "--porcelain", "--untracked-files=no"] + pathspec) ?? "").split(separator: "\n").count
        let unpushed = Int(run(repo.path, ["rev-list", "--count", "@{u}..HEAD"]) ?? "0") ?? 0
        var ready: [(String, Int)] = []
        for b in (run(repo.path, ["for-each-ref", "--format=%(refname:short)", "refs/heads"]) ?? "").split(separator: "\n").map(String.init)
        where b != releaseBranch {
            if let n = Int(run(repo.path, ["rev-list", "--count", "\(releaseBranch)..\(b)"]) ?? ""), n > 0 { ready.append((b, n)) }
        }
        return RepoGit(name: repo.name, branch: branch, dirty: dirty, unpushed: unpushed, readyBranches: ready)
    }
}

extension ProjectStore {
    /// Writes one top-level key of steerify.json, keeping everything else as it is.
    static func setManifestKey(_ project: Project, _ key: String, _ value: Any?) {
        _ = JSONFile.edit(project.manifest, key: key, value: value)
    }
}

/// Edit one top-level key of a JSON file with node, keeping the file's own key order and indentation
/// (clean diffs for files other people and sessions edit too).
enum JSONFile {
    static func edit(_ path: String, key: String, value: Any?) -> (String, Bool) {
        guard let node = BoardServers.shared.node else { return ("node not found", true) }
        let v = value.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }.flatMap { String(data: $0, encoding: .utf8) } ?? "undefined"
        let js = """
        const fs = require('fs'); const P = process.argv[1]; const raw = fs.readFileSync(P, 'utf8'); const o = JSON.parse(raw);
        const indent = (raw.match(/\\n( +)"/) || [, '  '])[1].length; const v = \(v);
        if (v === undefined) delete o[process.argv[2]]; else o[process.argv[2]] = v;
        fs.writeFileSync(P, JSON.stringify(o, null, indent) + '\\n'); console.log('saved ' + process.argv[2]);
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: node)
        p.arguments = ["-e", js, path, key]
        let err = Pipe(); p.standardError = err; p.standardOutput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return ("could not run node", true) }
        p.waitUntilExit()
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return p.terminationStatus == 0 ? ("\(key) saved in \((path as NSString).lastPathComponent)", false) : (e, true)
    }
}

/// ⌘5 Release: what is ready to ship (your OKs not live yet, branches ahead), and one button to ship it,
/// following the project's release setup.
struct ReleaseScreen: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    @State private var git: [RepoGit] = []
    @State private var loading = false
    @State private var editing = false

    private var project: Project { model.projects.first { $0.id == board.project.id } ?? board.project }
    private var ready: [ShipItem] { board.ships.filter { board.goesInRelease($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if project.release == nil || editing {
                    ReleaseSetup(project: project, done: { editing = false; model.reloadBoard() })
                } else {
                    header
                    ReleaseProducts(board: board, project: project)
                    readyCard
                    envCard
                    gitCard
                }
            }
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 12)
        }
        .task(id: project.release) { await loadGit(); await model.checkLive(project) }
        // A deploy finished, a live check found a new version, items turned live: show it now.
        .onChange(of: model.deployTick) { _, _ in Task { await loadGit() } }
        .onChange(of: board.ships.map { "\($0.id)·\($0.status)·\($0.updated ?? "")" }) { _, _ in Task { await loadGit() } }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PixelIcon(name: "ship", size: S(22)).foregroundStyle(Brand.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("RELEASE").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute)
                Text("\(ready.count) item\(ready.count == 1 ? "" : "s") ready to ship").font(.system(size: S(15), weight: .semibold)).foregroundStyle(.white)
            }
            Spacer()
            Button { editing = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: S(10)))
                    Text(WorkFlow.of(project).short).font(.system(size: S(11), design: .monospaced))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Brand.panel2)).overlay(Capsule().stroke(Brand.line))
            }
            .buttonStyle(SteerButton()).foregroundStyle(Brand.cream)
            .help("Branches: " + WorkFlow.of(project).title + ". " + WorkFlow.of(project).note + " Change it in the setup.")
            Button("Edit setup") { editing = true }.buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
            SessionChip(projectId: project.id, ref: "release:" + project.id)
            // Products ship from their cards (one release per product); a whole-project release only for what no product owns.
            if ready.contains(where: { model.product(of: $0, in: project) == nil }) || model.products(project).isEmpty {
            ActionButton(title: "Prepare release", icon: "ship", primary: true) {
                var x = ItemRef(ref: "release:" + project.id)!; x.title = "Release: " + project.name
                model.start(projectId: project.id, item: x, intent: .ship)
            }
            .disabled(ready.isEmpty && !git.contains { $0.unpushed > 0 || !$0.readyBranches.isEmpty })
            .help("A Claude session ships everything ready, following this project's release setup, and marks the items live")
            }
        }
    }

    private var readyCard: some View {
        Card {
            HStack {
                Text("GOES IN THE RELEASE").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.green)
                Spacer()
                if ready.count > 1 {
                    Button("Mark all \(ready.count) live") {
                        let prev = Dictionary(uniqueKeysWithValues: ready.map { ($0.id, $0.status) })
                        let items = ready
                        model.setLive(items, in: project, live: true)
                        model.showToast("\(items.count) items → live", projectId: project.id, undo: { model.setLive(items, in: project, live: false, previous: prev) })
                    }.buttonStyle(SteerButton()).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.green)
                }
            }
            Text("They turn live by themselves once their repo is committed and pushed (or deployed, for repos with a live check).")
                .font(.system(size: S(11))).foregroundStyle(Brand.mute)
            if ready.isEmpty { Text("Nothing approved is waiting. OK a To test item (or deliver one tested on stage / prod) to see it here.").italic().font(.system(size: S(12))).foregroundStyle(Brand.mute) }
            ForEach(ready) { s in
                HStack(spacing: 10) {
                    let after = board.shipState(s) == .afterRelease
                    Image(systemName: after ? "hourglass" : "checkmark.square.fill").foregroundStyle(after ? Brand.amber : Brand.green)
                        .help(after ? "Tested on stage / prod: it goes out untested, then comes back to To test" : "Approved")
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(s.title).font(.system(size: S(12.5), weight: .medium)).foregroundStyle(Brand.ink).lineLimit(1)
                            if after { Text("test after release").font(.system(size: S(10.5))).foregroundStyle(Brand.amber).fixedSize() }
                        }
                        Text("\(board.areaName(s.area)) · \(s.status.replacingOccurrences(of: "-", with: " ")) · \(s.repos.joined(separator: ", "))")
                            .font(.system(size: S(11))).foregroundStyle(Brand.mute).lineLimit(1)
                    }
                    Spacer()
                    if let c = model.shipCheck(s, in: project), !c.live {
                        Text(c.why).font(.system(size: S(10.5))).foregroundStyle(Brand.amber).lineLimit(1).frame(maxWidth: S(220), alignment: .trailing)
                    }
                    Button("Mark live") {
                        let prev = [s.id: s.status]
                        model.setLive([s], in: project, live: true)
                        model.showToast("“\(s.title.prefix(40))” → live", projectId: project.id, undo: { model.setLive([s], in: project, live: false, previous: prev) })
                    }.buttonStyle(SteerButton()).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.green)
                    // Ships its product with its other ready items, through the one ship sheet (choice ship-by-product).
                    if let ship = model.shipLabel(s, in: project) {
                        Button(ship.title) { model.askShip(item: s, in: project) }
                            .buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.cream)
                            .help("Ship \(ship.product.name) with its \(ship.count) ready item\(ship.count == 1 ? "" : "s")")
                    } else {
                        Button("Ship just this") {
                            var x = ItemRef(ref: "test:" + s.id)!; x.title = s.title; x.area = s.area
                            model.start(projectId: project.id, item: x, intent: .release)
                        }.buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.cream)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var gitCard: some View {
        Card {
            HStack {
                Text("REPOS").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.blue)
                Spacer()
                if loading { ProgressView().controlSize(.mini) }
                Button { Task { await loadGit() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(SteerButton()).foregroundStyle(Brand.mute)
            }
            ForEach(git) { g in
                let target = project.release?.repos[g.name]
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(Brand.mute).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(g.name).font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(.white)
                            Text(g.branch).font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.cream)
                            if let t = target, t.branch != g.branch { Text("→ \(t.branch)").font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.mute) }
                        }
                        HStack(spacing: 10) {
                            stat(g.dirty, "uncommitted", Brand.amber)
                            stat(g.unpushed, "unpushed", Brand.blue)
                            ForEach(g.readyBranches, id: \.name) { b in
                                Text("\(b.name) +\(b.ahead)").font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.green)
                            }
                            if g.dirty == 0 && g.unpushed == 0 && g.readyBranches.isEmpty { Text("clean").font(.system(size: S(11))).foregroundStyle(Brand.mute) }
                        }
                        if let d = target?.deploy, !d.isEmpty { Text("deploy: \(d)").font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.mute).lineLimit(1) }
                        if let t = Deploys.load(project.boardDir).last(where: { $0.repo == g.name }) {
                            Text("live: \(String(t.commit.prefix(7))) · \(t.by) · \(SessionChip.ago(t.at))").font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.green)
                        }
                    }
                    Spacer()
                    if let d = target?.deploy, !d.isEmpty, let repo = project.repos.first(where: { $0.name == g.name }) {
                        ActionButton(title: "Deploy", icon: "ship") { model.deploy(repo, in: project) }
                            .help("Runs “\(d)” in a shell tab with your keys; when it succeeds the approved items of this repo become live")
                    }
                }
                .padding(.vertical, 3)
            }
            if git.isEmpty && !loading { Text("No repos in the release setup.").font(.system(size: S(12))).foregroundStyle(Brand.mute) }
        }
    }

    /// Where To test links go. Missing = sessions are told to ask, never to guess a host.
    private var envCard: some View {
        Card {
            HStack {
                Text("WHERE TO TEST").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.amber)
                Spacer()
                Button(project.environments.isEmpty ? "Add addresses" : "Edit") { editing = true }
                    .buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.cream)
            }
            if project.environments.isEmpty {
                Text("No addresses yet: Claude asks you before putting a link on To test.").italic()
                    .font(.system(size: S(12))).foregroundStyle(Brand.mute)
            }
            ForEach(project.environments, id: \.self) { e in
                HStack(spacing: 10) {
                    Image(systemName: "link").font(.system(size: S(10))).foregroundStyle(Brand.mute)
                    Text(e.name).font(.system(size: S(12.5), weight: .medium)).foregroundStyle(Brand.ink).frame(width: S(110), alignment: .leading)
                    Text(e.url).font(.system(size: S(11.5), design: .monospaced)).foregroundStyle(Brand.cream).lineLimit(1).textSelection(.enabled)
                    if let a = e.area { Text(board.areaName(a)).font(.system(size: S(11))).foregroundStyle(Brand.mute) }
                    Spacer()
                }
            }
        }
    }

    private func stat(_ n: Int, _ label: String, _ c: Color) -> some View {
        Group { if n > 0 { Text("\(n) \(label)").font(.system(size: S(11))).foregroundStyle(c) } }
    }

    private func loadGit() async {
        guard let cfg = project.release else { return }
        loading = true
        let repos = project.repos.filter { cfg.repos[$0.name] != nil }
        let board = URL(fileURLWithPath: project.boardDir).standardizedFileURL.path
        let result = await Task.detached(priority: .utility) {
            repos.compactMap { Git.state($0, releaseBranch: cfg.repos[$0.name]?.branch ?? "main", ignoring: board) }
        }.value
        git = result
        // The ready card's reasons read the same cache: keep them in step with what the repos card shows.
        for g in result { if let r = repos.first(where: { $0.name == g.name }) { model.gitCache[r.path] = g } }
        loading = false
    }
}

/// One-time setup per project: which repos ship, from which branch, how to deploy, notes for Claude.
struct ReleaseSetup: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    let done: () -> Void
    @State private var include: [String: Bool] = [:]
    @State private var branch: [String: String] = [:]
    @State private var deploy: [String: String] = [:]
    @State private var live: [String: String] = [:]
    @State private var notes = ""
    @State private var flow: WorkFlow = WorkFlow.appDefault
    @State private var envs: [TestEnv] = []

    var body: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SET UP RELEASES · ONCE").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.amber)
                    Text("How does \(project.name) ship?").font(.system(size: S(15), weight: .semibold)).foregroundStyle(.white)
                    Text("Saved in steerify.json, so it travels with the project.").font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                }
                Spacer()
                ClaudeButton(title: "Do it with Claude") {
                    var x = ItemRef(ref: "release:" + project.id)!; x.title = "Release setup: " + project.name
                    model.start(projectId: project.id, item: x, intent: .plan)
                }.help("A session reads the repos (scripts, README, CI) and fills the release setup in steerify.json for you to check")
            }
            ForEach(project.repos) { r in
                HStack(spacing: 10) {
                    Toggle("", isOn: Binding(get: { include[r.name] ?? false }, set: { include[r.name] = $0 })).toggleStyle(.checkbox).labelsHidden()
                    Text(r.name).font(.system(size: S(12.5), weight: .medium)).frame(width: S(150), alignment: .leading)
                    TextField("branch", text: Binding(get: { branch[r.name] ?? "main" }, set: { branch[r.name] = $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: S(110)).disabled(!(include[r.name] ?? false))
                    TextField("deploy command, e.g. npm run deploy", text: Binding(get: { deploy[r.name] ?? "" }, set: { deploy[r.name] = $0 }))
                        .textFieldStyle(.roundedBorder).disabled(!(include[r.name] ?? false))
                    TextField("live check URL (returns commit)", text: Binding(get: { live[r.name] ?? "" }, set: { live[r.name] = $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: S(230)).disabled(!(include[r.name] ?? false))
                }
                .font(.system(size: S(12)))
                .opacity(r.exists ? 1 : 0.5)
            }
            Text("BRANCHES · HOW SESSIONS USE GIT").font(Brand.label(9)).foregroundStyle(Brand.mute).padding(.top, 4)
            FlowPicker(flow: $flow)
            EnvironmentsEditor(envs: $envs, areas: Array(Set(project.repos.flatMap(\.areas))).sorted())
            Text("NOTES FOR CLAUDE").font(Brand.label(9)).foregroundStyle(Brand.mute).padding(.top, 4)
            TextField("e.g. deploy the API before the UI; release notes in the platform's Releases; never deploy on Fridays", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...5).font(.system(size: S(12)))
            HStack {
                Spacer()
                if project.release != nil { Button("Cancel", action: done).buttonStyle(SteerButton()).foregroundStyle(Brand.mute) }
                ActionButton(title: "Save setup", icon: "ship", primary: true) {
                    var repos: [String: Any] = [:]
                    for r in project.repos where include[r.name] == true {
                        var e: [String: Any] = ["branch": (branch[r.name] ?? "main").isEmpty ? "main" : branch[r.name]!]
                        if let d = deploy[r.name], !d.isEmpty { e["deploy"] = d }
                        if let l = live[r.name], !l.isEmpty { e["liveCheck"] = l }
                        repos[r.name] = e
                    }
                    var cfg: [String: Any] = ["repos": repos]
                    if !notes.isEmpty { cfg["notes"] = notes }
                    cfg["flow"] = flow.rawValue
                    ProjectStore.setManifestKey(project, "release", cfg)
                    let clean = envs.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && TestEnvs.host($0.url) != nil }
                    ProjectStore.setManifestKey(project, "environments", clean.isEmpty ? nil : clean.map { e -> [String: Any] in
                        var d: [String: Any] = ["name": e.name.trimmingCharacters(in: .whitespaces), "url": e.url.trimmingCharacters(in: .whitespaces)]
                        if let a = e.area, !a.isEmpty { d["area"] = a }
                        if let n = e.note, !n.isEmpty { d["note"] = n }
                        return d
                    })
                    done()
                }
                .disabled(!include.values.contains(true))
            }
        }
        .onAppear {
            let cfg = project.release
            for r in project.repos {
                include[r.name] = cfg?.repos[r.name] != nil || (cfg == nil && r.git != nil)
                branch[r.name] = cfg?.repos[r.name]?.branch ?? "main"
                deploy[r.name] = cfg?.repos[r.name]?.deploy ?? ""
                live[r.name] = cfg?.repos[r.name]?.liveCheck ?? ""
            }
            notes = cfg?.notes ?? ""
            flow = WorkFlow.of(project)
            envs = project.environments
        }
    }
}


// MARK: - Deploys, without Claude: run from Steerify, or detected from the live version

struct DeployRecord: Codable { var repo: String; var commit: String; var at: String; var by: String; var committedAt: String? }

enum Deploys {
    static func file(_ dir: String) -> URL { URL(fileURLWithPath: dir).appendingPathComponent("deploys.json") }
    static func load(_ dir: String) -> [DeployRecord] {
        struct F: Codable { var deploys: [DeployRecord] }
        guard let d = try? Data(contentsOf: file(dir)), let f = try? JSONDecoder().decode(F.self, from: d) else { return [] }
        return f.deploys
    }
    /// true = a new version was recorded.
    @discardableResult
    static func append(_ r: DeployRecord, in dir: String) -> Bool {
        struct F: Codable { var steerify = 1; var deploys: [DeployRecord] }
        var all = load(dir)
        if all.last(where: { $0.repo == r.repo })?.commit == r.commit { return false }   // same version already recorded
        all.append(r)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let d = try? e.encode(F(deploys: Array(all.suffix(500)))) { try? d.write(to: file(dir), options: .atomic) }
        return true
    }
    /// ISO dates come as "…Z" (Steerify, deliveries) and "…+01:00" (git): compare them as dates, never as text.
    static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let frac = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    /// Latest live moment per repo: the newer of "deployed at" and "live commit was committed at".
    static func liveSince(_ dir: String) -> [String: Date] {
        var out: [String: Date] = [:]
        for r in load(dir) {
            guard let t = [date(r.at), date(r.committedAt)].compactMap({ $0 }).max() else { continue }
            if t > (out[r.repo] ?? .distantPast) { out[r.repo] = t }
        }
        return out
    }
}

extension AppModel {
    /// Test copies (`--background`) never write a board, except a scratch list of workspaces
    /// (`STEERIFY_WORKSPACES=<file>` + `--scratch-writes`), used to test deploys end to end.
    nonisolated static var mayWriteBoards: Bool {
        let a = CommandLine.arguments
        guard a.contains("--background") else { return true }
        return a.contains("--scratch-writes") && !(ProcessInfo.processInfo.environment["STEERIFY_WORKSPACES"] ?? "").isEmpty
    }

    /// Run a repo's deploy command in a visible shell tab; when it exits 0 the deploy is recorded.
    func deploy(_ repo: Repo, in p: Project) {
        guard let cmd = p.release?.repos[repo.name]?.deploy, !cmd.isEmpty else { return }
        let commit = Git.run(repo.path, ["rev-parse", "HEAD"]) ?? "unknown"
        let s = TerminalSession(project: p, repo: repo, kind: .shell, item: nil)
        s.shellCommand = cmd
        let started = Date()
        s.onExit = { [weak self, weak s] code in
            Task { @MainActor in
                guard let self else { return }
                self.deployTick += 1                       // even a failed deploy changes the repo state (push, commits)
                guard code == 0 else { return }
                Deploys.append(DeployRecord(repo: repo.name, commit: commit, at: BoardStore.now(), by: "steerify deploy",
                                            committedAt: Git.run(repo.path, ["log", "-1", "--format=%cI", commit])), in: p.boardDir)
                let shipped = self.markLive(p)
                let done = self.markRoadsDone(of: shipped, in: p)   // their key results: approved + live = done
                let checking = self.wakeAfterDeploy(repo, commit: commit, in: p)   // the session that waited on this deploy finishes up
                s?.celebration = DeployCelebration(repo: repo.name, commit: commit, took: Date().timeIntervalSince(started),
                                                   live: shipped.map(\.title), done: done, checking: checking)
                // A deployed app restarts: ask its live check again until it answers with the new version.
                if p.release?.repos[repo.name]?.liveCheck != nil {
                    for delay in [5, 20, 60, 150] {
                        try? await Task.sleep(for: .seconds(delay == 5 ? 5 : delay - 5))
                        await self.checkLive(p)
                    }
                }
            }
        }
        selectedProjectId = p.id
        _ = s.view
        sessions.append(s)
        selectedSession[p.id] = s.id
        persistSessions()      // the deploy shell itself is never saved (one-shot): only the selection changes
    }

    /// Ask each repo's live-check URL which commit is running (no tokens; every 10 min and on the Release tab).
    func checkLive(_ p: Project) async {
        guard AppModel.mayWriteBoards, let cfg = p.release else { return }
        for (name, r) in cfg.repos {
            guard let u = r.liveCheck, let url = URL(string: u) else { continue }
            var req = URLRequest(url: url); req.timeoutInterval = 8
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let commit = obj["commit"] as? String, !commit.isEmpty else { continue }
            if Deploys.append(DeployRecord(repo: name, commit: commit, at: (obj["startedAt"] as? String) ?? BoardStore.now(),
                                           by: "live check", committedAt: obj["committedAt"] as? String), in: p.boardDir) { deployTick += 1 }
        }
        markLive(p)
    }

    /// Why an approved item is (not yet) shipped, per repo it touches. nil = cannot tell (no repo in the release setup).
    func shipCheck(_ s: ShipItem, in p: Project) -> (live: Bool, why: String)? {
        guard let cfg = p.release else { return nil }
        var repos = s.repos.compactMap { p.resolveRepo($0) }.filter { cfg.repos[$0.name] != nil }
        if repos.isEmpty, cfg.repos.count == 1, let only = p.repos.first(where: { cfg.repos[$0.name] != nil }) { repos = [only] }
        guard !repos.isEmpty else { return nil }
        let since = Deploys.liveSince(p.boardDir)
        var reasons: [String] = []
        for r in Array(Set(repos)) {
            let rc = cfg.repos[r.name]!
            let st = gitCache[r.path] ?? Git.state(r, releaseBranch: rc.branch, ignoring: URL(fileURLWithPath: p.boardDir).standardizedFileURL.path)
            if let st { gitCache[r.path] = st }
            if rc.liveCheck != nil {
                // Deployed apps: the running version must be at or after this delivery.
                if let live = since[r.name], let delivered = Deploys.date(s.updated), live >= delivered { continue }
                reasons.append("\(r.name): not deployed since")
            } else if let st {
                // Push-to-ship: everything committed and pushed on the release branch → shipped.
                let dirty = st.dirty, unpushed = st.unpushed
                if dirty == 0 && unpushed == 0 && st.branch == rc.branch { continue }
                reasons.append(st.branch != rc.branch ? "\(r.name): on \(st.branch), not \(rc.branch)"
                               : [dirty > 0 ? "\(dirty) uncommitted" : nil, unpushed > 0 ? "\(unpushed) unpushed" : nil].compactMap { $0 }.map { "\(r.name): \($0)" }.joined(separator: " · "))
            }
        }
        return (reasons.isEmpty, reasons.isEmpty ? "shipped" : reasons.joined(separator: " · "))
    }

    /// Approved items become live as soon as their repos show them shipped (push or deploy). No tokens.
    /// Returns the items that turned live now.
    @discardableResult
    func markLive(_ p: Project) -> [ShipItem] {
        guard AppModel.mayWriteBoards else { return [] }   // test copies never write the board
        gitCache = [:]
        let b = board(for: p)
        let ready = b.ships.filter { b.goesInRelease($0) && (shipCheck($0, in: p)?.live ?? false) }
        guard !ready.isEmpty else { return [] }
        deployTick += 1
        setLive(ready, in: p, live: true)
        showToast("\(ready.count) approved item\(ready.count == 1 ? "" : "s") shipped → live", projectId: p.id)
        return ready
    }

    /// The key results of approved deliveries that just went live: marked done (no tokens). Returns their texts.
    func markRoadsDone(of items: [ShipItem], in p: Project) -> [String] {
        guard AppModel.mayWriteBoards, !items.isEmpty else { return [] }
        let b = board(for: p)
        var texts: [String] = []
        for s in items where b.effectivePick(s) == "ok" {
            for rd in s.roads {
                guard let r = b.roadmap.first(where: { $0.text == rd || $0.id == BoardFiles.slug(rd) }), r.status != "done",
                      !texts.contains(r.text) else { continue }
                texts.append(r.text)
            }
        }
        if !texts.isEmpty { b.setRoad(texts.map { ($0, "done") }) }
        return texts
    }

    /// Write status live (or back) through the board's deliver.mjs, keeping your verdict.
    func setLive(_ items: [ShipItem], in p: Project, live: Bool, previous: [String: String] = [:]) {
        let script = (p.boardDir as NSString).appendingPathComponent("deliver.mjs")
        guard FileManager.default.fileExists(atPath: script), let node = BoardServers.shared.node else { return }
        let raw = ((BoardFiles.json(p.boardDir, "delivered.json") as? [String: Any])?["items"] as? [[String: Any]]) ?? []
        let dir = p.boardDir
        DispatchQueue.global(qos: .userInitiated).async {
            for s in items {
                guard var item = raw.first(where: { $0["id"] as? String == s.id }) else { continue }
                item["status"] = live ? "live" : (previous[s.id] ?? "local")
                item["keepVerdict"] = true
                guard let json = try? JSONSerialization.data(withJSONObject: item), let str = String(data: json, encoding: .utf8) else { continue }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: node)
                proc.arguments = [script, str]
                proc.currentDirectoryURL = URL(fileURLWithPath: dir)
                proc.standardOutput = FileHandle.nullDevice; proc.standardError = FileHandle.nullDevice
                try? proc.run(); proc.waitUntilExit()
            }
        }
    }

    /// Throttled: at most once a minute (called when sessions go idle, on the Release tab, every 10 min).
    func checkShippedSoon() {
        guard Date().timeIntervalSince(lastShipCheck) > 60 else { return }
        lastShipCheck = Date()
        for p in projects { Task { await checkLive(p) } }
    }
}

/// Rows of name · address · area: the only hosts To test links may use (steerify.json → "environments").
struct EnvironmentsEditor: View {
    @Binding var envs: [TestEnv]
    let areas: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHERE TO TEST · THE ONLY ADDRESSES IN TO TEST LINKS").font(Brand.label(9)).foregroundStyle(Brand.mute).padding(.top, 4)
            ForEach(envs.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    TextField("name, e.g. platform", text: $envs[i].name).textFieldStyle(.roundedBorder).frame(width: S(130))
                    TextField("https://…", text: $envs[i].url).textFieldStyle(.roundedBorder)
                        .foregroundStyle(envs[i].url.isEmpty || TestEnvs.host(envs[i].url) != nil ? Brand.ink : Brand.red)
                    Picker("", selection: Binding(get: { envs[i].area ?? "" }, set: { envs[i].area = $0.isEmpty ? nil : $0 })) {
                        Text("any area").tag("")
                        ForEach(areas, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: S(120))
                    Button { envs.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(SteerButton()).foregroundStyle(Brand.mute)
                }
                .font(.system(size: S(12)))
            }
            Button { envs.append(TestEnv(name: "", url: "")) } label: { Label("Add an address", systemImage: "plus") }
                .buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.cream)
        }
    }
}
