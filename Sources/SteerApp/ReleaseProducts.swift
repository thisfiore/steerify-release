import SwiftUI

// MARK: - Releases by product (choice release-products, pick A + note: pixel animation while shipping + central modal)
//
// The Release tab opens on one card per product (architecture piece): its pixel art, the last version and date, the
// key features in it, and what is ready to ship. Products live in steerify.json → "products"; without them, one per area.
// Versions are read from what already exists: git tags, the last pushed commit of the product's folders, deploys.json,
// or the last OK run of a task (TestFlight). Shipping a product opens a modal with a pixel scene until the version changes.

/// One product of a project, from steerify.json → "products".
struct ReleaseProduct: Identifiable, Hashable {
    let id: String
    let name: String
    /// Pixel sprite: mac | web | ios | platform | api | extension | box.
    let icon: String
    /// Board areas whose To test items belong to it.
    let areas: [String]
    /// Words in a To test title that make it this product's ("iPhone"): win over areas.
    let match: [String]
    let repo: String?
    /// Folders of the repo that are this product (commits outside them don't make it need a release).
    let paths: [String]
    /// Where the version comes from: "tag" (v* git tags) | "push" (last pushed commit of `paths`) | "deploy" (deploys.json) | "task:<id>".
    let version: String
    /// Shell command that ships it (run in a tab, like Deploy). nil = a Claude session ships it.
    let deploy: String?
    /// An .xcarchive (relative to the repo) whose Info.plist gives the version + build of the last upload.
    var archive: String? = nil
    /// One line for the Claude session that ships it ("push main: the site auto-deploys").
    let how: String?

    @MainActor static func load(_ p: Project, board: BoardStore) -> [ReleaseProduct] {
        let cfg = BoardFiles.json(p.boardDir, "steerify.json") as? [String: Any] ?? [:]
        if let raw = cfg["products"] as? [[String: Any]], !raw.isEmpty {
            return raw.compactMap { o in
                guard let id = o["id"] as? String, !id.isEmpty else { return nil }
                return ReleaseProduct(id: id, name: o["name"] as? String ?? id, icon: o["icon"] as? String ?? "box",
                                      areas: o["areas"] as? [String] ?? [], match: o["match"] as? [String] ?? [],
                                      repo: o["repo"] as? String, paths: o["paths"] as? [String] ?? [],
                                      version: o["version"] as? String ?? "push", deploy: o["deploy"] as? String, archive: o["archive"] as? String, how: o["how"] as? String)
            }
        }
        // No products yet: one per area, its repo's release setup decides how its version is read.
        return board.areas.map { a in
            let repo = p.repos.first { $0.areas.contains(a.key) }?.name ?? p.repos.first?.name
            let rc = repo.flatMap { p.release?.repos[$0] }
            return ReleaseProduct(id: a.key, name: a.name, icon: ProductArt.guess(a.key + " " + a.name), areas: [a.key], match: [],
                                  repo: repo, paths: [], version: rc?.liveCheck != nil ? "deploy" : "tag", deploy: nil, archive: nil, how: nil)
        }
    }

    func owns(_ s: ShipItem, among all: [ReleaseProduct]) -> Bool {
        let t = s.title.lowercased()
        if let byWord = all.first(where: { p in p.match.contains { t.contains($0.lowercased()) } }) { return byWord.id == id }
        return areas.contains(s.area)
    }
}

/// What a product shipped last and what waits for it. Read off the main thread.
struct ProductState: Equatable {
    var version = "—"
    var date: Date?
    /// The release before the last one: features shipped after it are "in this release".
    var previous: Date?
    var source = ""
    /// The raw id under a readable version (commit), shown small.
    var detail: String?
    /// Commits (and changed files) in the product's folders not in the last release.
    var unreleased = 0
    var dirty = 0

    /// "1.0 (42)" from an .xcarchive's Info.plist; the build is left out while it is the placeholder 1
    /// (older uploads let Apple number the build: the archive never knew it).
    static func archiveVersion(_ path: String) -> String? {
        guard let d = FileManager.default.contents(atPath: (path as NSString).appendingPathComponent("Info.plist")),
              let o = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
              let app = o["ApplicationProperties"] as? [String: Any],
              let v = app["CFBundleShortVersionString"] as? String else { return nil }
        let b = app["CFBundleVersion"] as? String ?? ""
        return b.isEmpty || b == "1" ? v : "\(v) (\(b))"
    }

    static func read(_ pr: ReleaseProduct, in p: Project) -> ProductState {
        var st = ProductState()
        guard let repo = pr.repo.flatMap({ p.resolveRepo($0) }) ?? p.repos.first else { return st }
        let branch = p.release?.repos[repo.name]?.branch ?? "main"
        let paths = pr.paths.isEmpty ? [] : ["--"] + pr.paths
        func count(_ range: String) -> Int { Int(Git.run(repo.path, ["rev-list", "--count", range] + paths) ?? "") ?? 0 }
        var base: String?          // the commit of the last release: commits after it in `paths` = unreleased
        switch true {
        case pr.version == "tag":
            let tags = (Git.run(repo.path, ["for-each-ref", "refs/tags/v*", "--sort=-creatordate", "--count=2",
                                            "--format=%(refname:short)|%(creatordate:iso-strict)"]) ?? "")
                .split(separator: "\n").map { $0.split(separator: "|", maxSplits: 1).map(String.init) }
            if let t = tags.first, t.count == 2 {
                st.version = t[0]; st.date = Deploys.date(t[1]); base = t[0]
            }
            if tags.count > 1, tags[1].count == 2 { st.previous = Deploys.date(tags[1][1]) }
            st.source = "git tag"
        case pr.version == "deploy":
            let recs = Deploys.load(p.boardDir).filter { $0.repo == repo.name }
            if let r = recs.last { st.version = String(r.commit.prefix(7)); st.date = Deploys.date(r.at); base = r.commit }
            if recs.count > 1 { st.previous = Deploys.date(recs[recs.count - 2].at) }
            st.source = "deploy"
        case pr.version.hasPrefix("task:"):
            let task = String(pr.version.dropFirst(5))
            let runs = ((BoardFiles.json(p.boardDir, "tasks.json") as? [String: Any])?["runs"] as? [[String: Any]] ?? [])
                .filter { ($0["task"] as? String) == task && ($0["status"] as? String) == "ok" }
                .sorted { ($0["finished"] as? String ?? "") < ($1["finished"] as? String ?? "") }
            if let r = runs.last {
                let summary = (r["result"] as? [String: Any])?["summary"] as? String ?? ""
                let commit = summary.range(of: "\\b[0-9a-f]{7,40}\\b", options: .regularExpression).map { String(summary[$0]) }
                let build = summary.range(of: "build [0-9]+", options: [.regularExpression, .caseInsensitive]).map { String(summary[$0]) }
                st.version = build ?? commit ?? "last run"
                st.detail = commit
                st.date = Deploys.date(r["finished"] as? String)
                base = commit
            }
            if runs.count > 1 { st.previous = Deploys.date(runs[runs.count - 2]["finished"] as? String) }
            st.source = "task"
            // The uploaded archive says the app's version and build: "1.0 (1094)".
            if let a = pr.archive, let v = Self.archiveVersion((repo.path as NSString).appendingPathComponent(a)) {
                st.version = v; st.source = "TestFlight"; st.detail = nil
            }
        default:   // push: the product ships when its folders are pushed (auto-deploy)
            let log = (Git.run(repo.path, ["log", "-2", "--format=%h|%cI", "origin/" + branch] + paths) ?? "")
                .split(separator: "\n").map { $0.split(separator: "|").map(String.init) }
            if let l = log.first, l.count == 2 {
                // Readable: v<n> = the n-th pushed change of the product's folders (no bookkeeping, always goes up).
                let n = Int(Git.run(repo.path, ["rev-list", "--count", "origin/" + branch] + paths) ?? "") ?? 0
                st.version = n > 0 ? "v\(n)" : l[0]; st.detail = l[0]
                st.date = Deploys.date(l[1]); base = "origin/" + branch
            }
            if log.count > 1, log[1].count == 2 { st.previous = Deploys.date(log[1][1]) }
            st.source = "push"
        }
        if let base { st.unreleased = count(base + "..HEAD") }
        st.dirty = (Git.run(repo.path, ["status", "--porcelain", "--untracked-files=no"] + paths) ?? "")
            .split(separator: "\n").filter { !$0.contains(".steerify/") }.count
        return st
    }
}

// MARK: - The products section of the Release tab

struct ReleaseProducts: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let project: Project
    @ObservedObject private var runs = ShipRuns.shared
    @State private var states: [String: ProductState] = [:]

    private var products: [ReleaseProduct] { ReleaseProduct.load(project, board: board) }

    var body: some View {
        let all = products
        VStack(alignment: .leading, spacing: 10) {
            let need = all.filter { needs($0, all) }.count
            HStack(spacing: 8) {
                Text("PRODUCTS").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute)
                Text(need == 0 ? "all up to date" : "\(need) of \(all.count) need a release")
                    .font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(need == 0 ? Brand.green : Brand.amber)
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: S(250), maximum: S(420)), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(all) { pr in card(pr, all) }
            }
        }
        .task(id: "\(project.id)·\(model.deployTick)·\(board.ships.count)·\(runs.tick)") { await reload(all) }
    }

    private func ready(_ pr: ReleaseProduct, _ all: [ReleaseProduct]) -> [ShipItem] {
        board.ships.filter { board.goesInRelease($0) && pr.owns($0, among: all) }
    }
    private func features(_ pr: ReleaseProduct, _ all: [ReleaseProduct]) -> [ShipItem] {
        let since = states[pr.id]?.previous
        return board.ships
            .filter { $0.status == "live" && pr.owns($0, among: all) && (since == nil || (Deploys.date($0.updated) ?? .distantPast) > since!) }
            .sorted { ($0.updated ?? "") > ($1.updated ?? "") }
    }
    private func needs(_ pr: ReleaseProduct, _ all: [ReleaseProduct]) -> Bool {
        !ready(pr, all).isEmpty || (states[pr.id]?.unreleased ?? 0) > 0
    }

    private func reload(_ all: [ReleaseProduct]) async {
        let p = project
        let out = await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: all.map { ($0.id, ProductState.read($0, in: p)) })
        }.value
        states = out
        // Landed: its items are live and their key results done, so their feature sessions show released.
        model.landShips(p, states: out)
        // Test hook (test copies only): `--demo-ship <product id> shipping|done|failed` opens the modal on that state.
        let a = CommandLine.arguments
        if a.contains("--background"), let i = a.firstIndex(of: "--demo-ship"), i + 2 < a.count,
           runs.active.isEmpty, let pr = all.first(where: { $0.id == a[i + 1] }) {
            let key = p.id + "/" + pr.id
            var from = out[pr.id] ?? ProductState(); if a[i + 2] == "done" { from.version = "v0.5.12" }
            runs.start(ShipRun(key: key, projectId: p.id, product: pr, from: from, items: ready(pr, all).map(\.title)))
            if a[i + 2] == "done" { runs.finish(key, .done("v0.5.13")) }
            if a[i + 2] == "failed" {
                runs.active[key]?.command = pr.deploy; runs.active[key]?.log = "lsregister: -u failed (exit 1)\nrelease.sh: line 88: build failed"
                runs.finish(key, .failed("The release script stopped (code 1) before anything went out."))
            }
            if a.contains("--demo-ship-card") { runs.shown = nil }
        }
    }

    @ViewBuilder private func card(_ pr: ReleaseProduct, _ all: [ReleaseProduct]) -> some View {
        if let r = runs.active[project.id + "/" + pr.id] { ShippingCard(run: r, product: pr, state: states[pr.id] ?? ProductState()) }
        else { idleCard(pr, all) }
    }

    @ViewBuilder private func idleCard(_ pr: ReleaseProduct, _ all: [ReleaseProduct]) -> some View {
        let st = states[pr.id] ?? ProductState()
        let rd = ready(pr, all), ft = features(pr, all)
        let need = !rd.isEmpty || st.unreleased > 0
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                ProductArt(icon: pr.icon).frame(width: S(60), height: S(60))
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.name.uppercased()).font(Brand.label(12)).tracking(0.6).foregroundStyle(Brand.ink).lineLimit(1)
                    Text(st.version).font(.system(size: S(16), weight: .bold, design: .monospaced)).foregroundStyle(Brand.cream).lineLimit(1)
                    Text([st.date.map { Self.day($0) }, st.detail, st.source.isEmpty ? nil : st.source].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: S(11))).foregroundStyle(Brand.mute)
                }
                Spacer(minLength: 0)
            }
            Text("IN THIS RELEASE").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.green)
            if ft.isEmpty { Text("No approved items recorded").italic().font(.system(size: S(11.5))).foregroundStyle(Brand.mute) }
            ForEach(ft.prefix(3)) { s in line("✦", s.title, Brand.green, Brand.ink) }
            if ft.count > 3, st.previous != nil { Text("+ \(ft.count - 3) more").font(.system(size: S(11))).foregroundStyle(Brand.mute) }
            Rectangle().fill(Brand.line).frame(height: 1)
            HStack {
                if need {
                    Text("READY TO SHIP · \(rd.count)").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.amber)
                } else {
                    Text("UP TO DATE").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.green)
                }
                Spacer()
                if need {
                    ActionButton(title: rd.isEmpty ? "Ship" : "Ship · \(rd.count)",
                                 icon: "ship", primary: true) { model.askShip(projectId: project.id, product: pr.id) }
                        .help("Ship \(pr.name): its ready items, one release (" + (pr.deploy.map { "runs “\($0)”" } ?? "a Claude session ships it") + ")")
                }
            }
            ForEach(rd.prefix(4)) { s in line("▸", s.title, Brand.amber, Brand.amber) }
            if rd.count > 4 { Text("+ \(rd.count - 4) more").font(.system(size: S(11))).foregroundStyle(Brand.mute) }
            let extra = [st.unreleased > 0 ? "\(st.unreleased) commit\(st.unreleased == 1 ? "" : "s") since \(st.version)" : nil,
                         st.dirty > 0 ? "\(st.dirty) uncommitted" : nil].compactMap { $0 }
            if !extra.isEmpty { Text(extra.joined(separator: " · ")).font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.mute) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 11).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(need ? Brand.amber.opacity(0.55) : Brand.line2))
    }

    private func line(_ mark: String, _ text: String, _ c: Color, _ tc: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(mark).font(.system(size: S(9))).foregroundStyle(c)
            Text(text).font(.system(size: S(12))).foregroundStyle(tc).lineLimit(1)
        }
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = Calendar.current.isDateInToday(d) ? "'today' HH:mm" : "d MMM"
        return f.string(from: d)
    }
}

// MARK: - Shipping: a central modal with a pixel scene, then the confirmation

struct ShipRun: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let projectId: String
    let product: ReleaseProduct
    let from: ProductState
    let items: [String]
    /// The To test ids it ships: marked live when it lands; their sessions show "shipping" meanwhile.
    var itemIds: [String] = []
    let started = Date()
    enum Phase: Equatable { case shipping, done(String), failed(String) }
    var phase: Phase = .shipping
    /// The shell tab running the release script, and its last lines when it stopped (handed to Claude on a failure).
    var shell: UUID?
    var command: String?
    var log = ""
    /// The release script ended well: now waiting for the new version to show up.
    var scriptDone = false
    var finished: Date?
}

@MainActor
final class ShipRuns: ObservableObject {
    static let shared = ShipRuns()
    @Published var active: [String: ShipRun] = [:]
    /// The run the modal shows (nil = hidden; a run keeps going in the background).
    @Published var shown: String?
    /// The ship sheet to show (ShipProduct.swift): every ship button opens it.
    @Published var ask: ShipAsk?
    /// Bumped while a run is shipping, so the products read their version again.
    @Published var tick = 0
    private var poll: Task<Void, Never>?

    func start(_ r: ShipRun) {
        active[r.key] = r; shown = r.key
        // Only while something ships: look at the versions again every 15 s (nothing runs when idle).
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.active.values.contains(where: { $0.phase == .shipping }) else { return }
                self.tick += 1
            }
        }
    }

    func runDeploy(_ cmd: String, repo: Repo, in p: Project, model: AppModel, key: String) {
        let s = TerminalSession(project: p, repo: repo, kind: .shell, item: nil)
        s.shellCommand = cmd
        active[key]?.shell = s.id; active[key]?.command = cmd
        s.onExit = { [weak self, weak s] code in
            Task { @MainActor in
                guard let self else { return }
                model.deployTick += 1
                if code != 0 {
                    self.active[key]?.log = s.map { Self.tail($0) } ?? ""
                    self.finish(key, .failed("The release script stopped (code \(code)) before anything went out."))
                }
                else { self.active[key]?.scriptDone = true; self.tick += 1 }   // the version check turns it into done
            }
        }
        _ = s.view
        model.sessions.append(s)
        model.selectedSession[p.id] = s.id
    }

    /// The last lines a shell tab printed (the part that says why a release stopped).
    static func tail(_ s: TerminalSession, lines: Int = 60) -> String {
        s.view.selectAll()                                   // SwiftTerm's public way to read the buffer
        let text = s.view.getSelection() ?? ""
        s.view.selectNone()
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var tail = Array(all.suffix(lines * 3).filter { !$0.isEmpty }.suffix(lines))
        if tail.joined().count > 6000 { tail = Array(tail.suffix(25)) }
        return tail.joined(separator: "\n")
    }

    /// A release that stopped: a Claude session gets the script, the log tail and the items, finds why, fixes, ships.
    func fixWithClaude(_ key: String, model: AppModel) {
        guard let r = active[key], case .failed = r.phase else { return }
        var x = ItemRef(ref: "release:" + r.projectId)!; x.title = "Release: " + r.product.name
        let log = r.log.isEmpty ? "(log not captured: read the shell tab)" : r.log
        let script: String = r.command ?? r.product.deploy ?? "ship"
        let waiting: String = r.items.isEmpty ? "none, just its unreleased commits" : r.items.joined(separator: "; ")
        var brief = "The release of \(r.product.name) stopped. Script: “\(script)” (from \(r.from.version)). "
        brief += "Last lines of its log:\n```\n\(log)\n```\n"
        brief += "Find why it stopped, fix the cause (not the symptom), then run the release again. Items waiting: \(waiting). "
        brief += "Tell me in two lines what went wrong and what you changed."
        close(key)
        model.start(projectId: r.projectId, item: x, intent: .ship, extraBrief: brief, fresh: true)
    }

    /// Products read again: a shipping one whose version changed is done.
    @discardableResult
    func check(project: String, states: [String: ProductState]) -> [ShipRun] {
        var landed: [ShipRun] = []
        for (k, r) in active where r.projectId == project && r.phase == .shipping {
            guard let st = states[r.product.id], st.version != "—", st.version != r.from.version else { continue }
            finish(k, .done(st.version)); landed.append(r)
        }
        return landed
    }

    func finish(_ key: String, _ phase: ShipRun.Phase) {
        guard var r = active[key] else { return }
        r.phase = phase; r.finished = Date(); active[key] = r; shown = key   // the confirmation always comes to the front
        // Out: the card keeps its fireworks for a minute, then settles to Up to date.
        if case .done = phase {
            let at = r.finished
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.celebrate))
                guard let self, self.active[key]?.finished == at else { return }
                self.active[key] = nil
                if self.shown == key { self.shown = nil }
            }
        }
    }
    static let celebrate: Double = 60

    /// Hides the modal. A failed run is let go; a done one stays on its card until its minute is up.
    func close(_ key: String) {
        if case .failed = active[key]?.phase { active[key] = nil }
        if shown == key { shown = nil }
    }
    func dismiss(_ key: String) {
        if active[key]?.phase != .shipping { active[key] = nil }
        if shown == key { shown = nil }
    }
}

/// Centred over the Release tab while a product ships, and for the confirmation.
struct ShipModal: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var runs = ShipRuns.shared
    let projectId: String

    var body: some View {
        if let k = runs.shown, let r = runs.active[k], r.projectId == projectId {
            ZStack {
                Color.black.opacity(0.62).ignoresSafeArea().onTapGesture { runs.close(k) }
                VStack(spacing: 14) {
                    ShipPixelScene(icon: r.product.icon, phase: r.phase)
                        .frame(width: S(384), height: S(240)).clipShape(RoundedRectangle(cornerRadius: 8))
                    switch r.phase {
                    case .shipping:
                        Text("Shipping \(r.product.name)…").font(.system(size: S(20), weight: .heavy)).foregroundStyle(Brand.cream)
                        Text("from \(r.from.version) · \(r.product.deploy == nil ? "Claude is on it" : "running its release")")
                            .font(.system(size: S(11.5), design: .monospaced)).foregroundStyle(Brand.mute)
                    case .done(let v):
                        Text("\(r.product.name) \(v) is out").font(.system(size: S(22), weight: .heavy)).foregroundStyle(Brand.cream)
                        Text("\(r.from.version) → \(v) · in \(Self.took(r.started))").font(.system(size: S(11.5), design: .monospaced)).foregroundStyle(Brand.green)
                    case .failed(let why):
                        // Not an alarm: nothing broke for anyone, the boat just stayed in the harbour (request r261123-110518).
                        Text("\(r.product.name) stayed in the harbour").font(.system(size: S(20), weight: .heavy)).foregroundStyle(Brand.cream)
                        Text("\(r.from.version) is still live · " + why).font(.system(size: S(12))).foregroundStyle(Brand.mute)
                            .multilineTextAlignment(.center).frame(maxWidth: S(400))
                    }
                    let failed: Bool = { if case .failed = r.phase { return true }; return false }()
                    if !r.items.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            if failed { Text("STILL WAITING TO SHIP").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.amber) }
                            ForEach(r.items.prefix(5), id: \.self) { t in
                                HStack(spacing: 8) {
                                    let mark = r.phase == .shipping || failed
                                    Text(mark ? "▸" : "✦").foregroundStyle(mark ? Brand.amber : Brand.green)
                                    Text(t).font(.system(size: S(12.5))).foregroundStyle(failed ? Brand.mute : Brand.ink).lineLimit(1)
                                }
                            }
                            if r.items.count > 5 { Text("+ \(r.items.count - 5) more").font(.system(size: S(11))).foregroundStyle(Brand.mute) }
                        }
                        .frame(maxWidth: S(360), alignment: .leading)
                    }
                    if failed {
                        HStack(spacing: 10) {
                            Button { runs.fixWithClaude(k, model: model) } label: {
                                Label("Fix it with Claude", systemImage: "sparkles").font(.system(size: S(13), weight: .semibold))
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(Brand.amber)).foregroundStyle(Color(hex: 0x1a1200))
                            }
                            .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                            .help("A Claude session gets the log, finds why it stopped, fixes it and ships again")
                            if let sid = r.shell, model.sessions.contains(where: { $0.id == sid }) {
                                Button { model.selectedSession[r.projectId] = sid; runs.close(k) } label: {
                                    Text("See the log").font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.cream)
                                        .padding(.horizontal, 10).padding(.vertical, 8)
                                }
                                .buttonStyle(SteerButton())
                            }
                            Button { runs.close(k) } label: {
                                Text("Later").font(.system(size: S(12))).foregroundStyle(Brand.mute).padding(.horizontal, 8).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                        }
                    } else {
                    Button { runs.close(k) } label: {
                        Text(r.phase == .shipping ? "Keep working · I'll tell you" : "Nice")
                            .font(.system(size: S(13), weight: .semibold))
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 7).fill(r.phase == .shipping ? Brand.panel2 : Brand.amber))
                            .foregroundStyle(r.phase == .shipping ? Brand.cream : Color(hex: 0x1a1200))
                    }
                    .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                    }
                }
                .padding(26)
                .background(RoundedRectangle(cornerRadius: 14).fill(Brand.panel))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(r.phase == .shipping ? Brand.line2 : Brand.amber.opacity(0.7)))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            .animation(.spring(duration: 0.35), value: r.phase)
        }
    }

    static func took(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        return s < 60 ? "\(s) s" : "\(s / 60) min \(s % 60) s"
    }
}

/// Shipping: the product rides a boat over the waves, crates being loaded. Done: fireworks over the harbour.
/// Failed: the boat bobs in the harbour under a grey sky.
struct ShipPixelScene: View {
    let icon: String
    let phase: ShipRun.Phase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { tl in
            let t = Int(tl.date.timeIntervalSinceReferenceDate / 0.15)
            Canvas { ctx, size in draw(ctx, size, t) }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ tick: Int) {
        let cols = 64, rows = 40
        let px = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
        let ox = (size.width - px * CGFloat(cols)) / 2, oy = (size.height - px * CGFloat(rows)) / 2
        func dot(_ x: Int, _ y: Int, _ c: Color, _ a: Double = 1) {
            guard x >= 0, x < cols, y >= 0, y < rows else { return }
            ctx.fill(Path(CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px, height: px)), with: .color(c.opacity(a)))
        }
        let failed: Bool = { if case .failed = phase { return true }; return false }()
        let done: Bool = { if case .done = phase { return true }; return false }()
        ctx.fill(Path(CGRect(x: ox, y: oy, width: px * CGFloat(cols), height: px * CGFloat(rows))),
                 with: .color(failed ? Color(hex: 0x1b1d22) : Color(hex: 0x141a26)))
        let slow = tick / 3
        // done: stars and fireworks over the harbour, the product hops above the boat
        if done {
            let slow = tick / 3
            for (i, (x, y)) in [(5, 3), (14, 7), (27, 2), (41, 5), (55, 3), (60, 9), (9, 12), (35, 9)].enumerated() {
                dot(x, y, Brand.cream, (i + slow) % 3 == 0 ? 1 : 0.4)
            }
            let fw: [Color] = [Brand.amber, Brand.green, Brand.blue, Brand.violet, Brand.red]
            for (k, (cx, cy, off)) in [(12, 9, 0), (50, 7, 3), (32, 6, 6)].enumerated() {
                let p = (slow + off) % 9
                guard p <= 5 else { continue }
                let r = Double(p + 1), c = fw[(k + (slow + off) / 9) % fw.count]
                for a in 0..<12 {
                    let an = Double(a) * .pi / 6
                    dot(Int((Double(cx) + cos(an) * r).rounded()), Int((Double(cy) + sin(an) * r).rounded()), c, p > 3 ? 0.55 : 1)
                }
                dot(cx, cy, .white)
            }
        }
        // sun (or a grey cloud), and a gull
        if done {
        } else if failed { for x in 8..<20 { for y in 4..<8 where (x + y) % 5 != 0 { dot(x, y, Brand.mute, 0.5) } } }
        else {
            for x in 50..<56 { for y in 4..<10 where !((x == 50 || x == 55) && (y == 4 || y == 9)) { dot(x, y, Brand.amber) } }
            let gx = (slow % 70) - 4, gy = 10 + (slow % 4 < 2 ? 0 : 1)
            dot(gx, gy, Brand.cream); dot(gx + 1, gy + 1, Brand.cream); dot(gx + 2, gy, Brand.cream)
        }
        // pier on the left
        for x in 0..<9 { dot(x, 27, Color(hex: 0x5b3d1e)) }
        for y in 28..<38 { dot(2, y, Color(hex: 0x5b3d1e)); dot(7, y, Color(hex: 0x5b3d1e)) }
        // sea
        for r in 0..<4 {
            for x in 0..<cols where (x + slow * (r + 1) + r * 3) % 7 < 4 {
                dot(x, 30 + r * 3, r == 0 ? Color(hex: 0x3d6ea5) : Color(hex: 0x26364d))
            }
        }
        // the boat: still at the pier when failed, sailing otherwise
        let bx = failed ? 10 : done ? 24 : 10 + (slow % 36), bob = (tick / 4) % 2
        let by = 26 + bob
        for x in 0..<16 { dot(bx + x, by + 2, Color(hex: 0x8a5a2b)) }
        for x in 1..<15 { dot(bx + x, by + 3, Color(hex: 0x6e4520)) }
        for x in 3..<13 { dot(bx + x, by + 4, Color(hex: 0x6e4520)) }
        // mast + sail
        for y in (by - 12)...(by + 1) { dot(bx + 12, y, Brand.cream) }
        for y in 0..<9 { for x in 0..<(y / 2 + 1) { dot(bx + 13 + x, by - 11 + y, failed ? Brand.mute : Brand.cream, 0.9) } }
        if !failed { dot(bx + 12, by - 13, Brand.amber); dot(bx + 13, by - 13, Brand.amber, tick % 2 == 0 ? 1 : 0.4) }   // flag
        // the product rides on deck
        sprite(dot, x: bx + 1, y: by - 10 - (done && (tick / 3) % 4 == 0 ? 2 : 0), scale: 1)
        // loading dots under the scene
        if !failed && !done { for i in 0..<3 { dot(28 + i * 3, 38, Brand.amber, (tick / 2) % 3 == i ? 1 : 0.25) } }
    }

    /// The product's sprite (24×24 map shown at 10×10 on deck: every other pixel).
    private func sprite(_ dot: (Int, Int, Color, Double) -> Void, x: Int, y: Int, scale: Int) {
        let map = ProductArt.map(icon)
        for (yy, row) in map.enumerated() where yy % 2 == 0 {
            for (xx, ch) in row.enumerated() where xx % 2 == 0 {
                guard let c = ProductArt.color(ch) else { continue }
                dot(x + xx / 2, y + yy / 2, c, 1)
            }
        }
    }
}

// MARK: - Shipping on the card (choice ship-on-card, A: a harbour strip)

/// The product card while it ships, and for a minute after it is out: the boat sails across a strip, the steps tick,
/// fireworks on the card when the version changes. The modal can be closed: the card keeps telling.
struct ShippingCard: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var runs = ShipRuns.shared
    let run: ShipRun
    let product: ReleaseProduct
    let state: ProductState

    private var done: String? { if case .done(let v) = run.phase { return v }; return nil }
    private var failed: String? { if case .failed(let w) = run.phase { return w }; return nil }

    var body: some View {
        let tint = done != nil ? Brand.green : failed != nil ? Brand.red : Brand.amber
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                ProductArt(icon: product.icon).frame(width: S(60), height: S(60))
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name.uppercased()).font(Brand.label(12)).tracking(0.6).foregroundStyle(Brand.ink).lineLimit(1)
                    Text("\(run.from.version) → \(done ?? "…")").font(.system(size: S(16), weight: .bold, design: .monospaced))
                        .foregroundStyle(Brand.cream).lineLimit(1).minimumScaleFactor(0.7)
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        Text(subtitle(tl.date)).font(.system(size: S(11))).foregroundStyle(failed != nil ? Brand.red : Brand.mute).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            ShipStrip(icon: product.icon, phase: run.phase)
                .frame(maxWidth: .infinity).frame(height: S(78))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle()).onTapGesture { runs.shown = run.key }
                .help("Open the shipping window")
            steps
            ForEach(run.items.prefix(4), id: \.self) { t in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(done != nil ? "✦" : "▸").font(.system(size: S(9))).foregroundStyle(done != nil ? Brand.green : Brand.amber)
                    Text(t).font(.system(size: S(12))).foregroundStyle(done != nil ? Brand.ink : Brand.amber).lineLimit(1)
                }
            }
            if run.items.count > 4 { Text("+ \(run.items.count - 4) more").font(.system(size: S(11))).foregroundStyle(Brand.mute) }
            HStack(spacing: 8) {
                Spacer()
                if failed != nil {
                    ActionButton(title: "Fix it with Claude", icon: "term", primary: true) { runs.fixWithClaude(run.key, model: model) }
                    ActionButton(title: "Later", icon: "play") { runs.dismiss(run.key) }
                } else if done != nil {
                    ActionButton(title: "Nice") { runs.dismiss(run.key) }
                } else {
                    ActionButton(title: "Open", icon: "ship") { runs.shown = run.key }
                        .help(product.deploy.map { "“\($0)” is running in a shell tab" } ?? "A Claude session is shipping it")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 11).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(tint.opacity(done != nil ? 0.8 : 0.6), lineWidth: done != nil ? 1.5 : 1))
        .animation(.spring(duration: 0.35), value: run.phase)
    }

    private func subtitle(_ now: Date) -> String {
        if let w = failed { return w }
        if done != nil { return "out · in \(Self.span(run.started, run.finished ?? now))" }
        return "shipping · \(Self.span(run.started, now))"
    }

    /// What really happened so far: started → the script (or Claude) → the new version seen → out.
    private var steps: some View {
        let script = product.deploy != nil
        let list: [(String, Int)] = {   // 2 = done, 1 = now, 0 = to come, -1 = stopped
            if done != nil { return [("started", 2), (script ? "script" : "Claude", 2), ("live", 2)] }
            if failed != nil { return [("started", 2), (script ? "script stopped" : "stopped", -1), ("live", 0)] }
            if script && run.scriptDone { return [("started", 2), ("script", 2), ("new version?", 1)] }
            return [("started", 2), (script ? "release script" : "Claude ships it", 1), ("live", 0)]
        }()
        return HStack(spacing: 5) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, s in
                if i > 0 { Text("·").foregroundStyle(Brand.mute) }
                Text((s.1 == 2 ? "✓ " : s.1 == 1 ? "▸ " : s.1 == -1 ? "✕ " : "") + s.0)
                    .foregroundStyle(s.1 == 2 ? Brand.green : s.1 == 1 ? Brand.amber : s.1 == -1 ? Brand.red : Brand.mute)
            }
        }
        .font(.system(size: S(10.5), weight: .semibold, design: .monospaced))
    }

    static func span(_ a: Date, _ b: Date) -> String {
        let s = max(0, Int(b.timeIntervalSince(a)))
        return s < 60 ? "\(s) s" : "\(s / 60) min \(s % 60) s"
    }
}

/// A wide harbour (96×22 pixels) for the card: the boat carries the product across while it ships,
/// fireworks over it when it is out, a grey sky and the boat at the pier when it stopped.
struct ShipStrip: View {
    let icon: String
    let phase: ShipRun.Phase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { tl in
            let t = Int(tl.date.timeIntervalSinceReferenceDate / 0.15)
            Canvas { ctx, size in draw(ctx, size, t) }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ tick: Int) {
        let rows = 22
        let px = size.height / CGFloat(rows)
        let cols = max(40, Int(size.width / px))
        let ox = (size.width - px * CGFloat(cols)) / 2
        func dot(_ x: Int, _ y: Int, _ c: Color, _ a: Double = 1) {
            guard x >= 0, x < cols, y >= 0, y < rows else { return }
            ctx.fill(Path(CGRect(x: ox + CGFloat(x) * px, y: CGFloat(y) * px, width: px + 0.3, height: px + 0.3)), with: .color(c.opacity(a)))
        }
        let failed: Bool = { if case .failed = phase { return true }; return false }()
        let done: Bool = { if case .done = phase { return true }; return false }()
        let slow = tick / 3
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(failed ? Color(hex: 0x1b1d22) : Color(hex: 0x141a26)))
        // stars (a grey cloud when it stopped)
        if failed {
            for x in 14..<28 { for y in 2..<5 where (x + y) % 5 != 0 { dot(x, y, Brand.mute, 0.45) } }
        } else {
            for i in 0..<(cols / 8) { dot((i * 37 + 11) % cols, (i * 7 + 2) % 11, Brand.cream, (i + slow) % 3 == 0 ? 0.9 : 0.3) }
        }
        if done {
            let fw: [Color] = [Brand.amber, Brand.green, Brand.blue, Brand.violet, Brand.red]
            let spots = [(cols / 6, 6, 0), (cols / 2 - 4, 5, 3), (cols * 5 / 6 - 14, 7, 6), (cols / 3 + 4, 9, 5)]
            for (k, (cx, cy, off)) in spots.enumerated() {
                let p = (slow + off) % 9
                if p < 3 { dot(cx, cy + 9 - p * 3, Brand.cream, 0.8); continue }   // the rocket going up
                let r = Double(p - 2), c = fw[(k + (slow + off) / 9) % fw.count]
                for a in 0..<12 {
                    let an = Double(a) * .pi / 6
                    dot(Int((Double(cx) + cos(an) * r).rounded()), Int((Double(cy) + sin(an) * r * 0.8).rounded()), c, p > 6 ? 0.5 : 1)
                }
            }
        } else if !failed {
            let gx = cols - 1 - (slow % (cols + 6)), gy = 4 + (slow % 4 < 2 ? 0 : 1)   // a gull
            dot(gx, gy, Brand.cream); dot(gx + 1, gy + 1, Brand.cream); dot(gx + 2, gy, Brand.cream)
        }
        // pier on the left, the lighthouse on the right
        for x in 0..<8 { dot(x, 15, Color(hex: 0x5b3d1e)) }
        for y in 16..<rows { dot(1, y, Color(hex: 0x5b3d1e)); dot(6, y, Color(hex: 0x5b3d1e)) }
        for y in 8..<18 { dot(cols - 4, y, Brand.cream, 0.85); dot(cols - 3, y, (y / 2) % 2 == 0 ? Brand.red : Brand.cream, 0.85) }
        dot(cols - 4, 7, Brand.amber, done || tick % 4 < 2 ? 1 : 0.3); dot(cols - 3, 7, Brand.amber, done || tick % 4 < 2 ? 1 : 0.3)
        // sea
        for r in 0..<3 {
            for x in 0..<cols where (x + slow * (r + 1) + r * 3) % 7 < 4 {
                dot(x, 18 + r * 2, r == 0 ? Color(hex: 0x3d6ea5) : Color(hex: 0x26364d))
                dot(x, 19 + r * 2, Color(hex: 0x26364d), 0.6)
            }
        }
        // the boat: at the pier when stopped, across the strip while shipping, by the lighthouse when out
        let span = max(1, cols - 28)
        let bx = failed ? 8 : done ? cols - 22 : 8 + (slow % span), by = 14 + (tick / 4) % 2
        for x in 0..<16 { dot(bx + x, by + 2, Color(hex: 0x8a5a2b)) }
        for x in 1..<15 { dot(bx + x, by + 3, Color(hex: 0x6e4520)) }
        for x in 3..<13 { dot(bx + x, by + 4, Color(hex: 0x6e4520)) }
        for y in (by - 12)...(by + 1) { dot(bx + 12, y, Brand.cream) }
        for y in 0..<9 { for x in 0..<(y / 2 + 1) { dot(bx + 13 + x, by - 11 + y, failed ? Brand.mute : Brand.cream, 0.9) } }
        if !failed { dot(bx + 12, by - 13, Brand.amber); dot(bx + 13, by - 13, Brand.amber, tick % 2 == 0 ? 1 : 0.4) }
        // the product on deck (its 24×24 art at 10×10), hopping when it is out
        let hop = done && (tick / 3) % 4 == 0 ? 1 : 0
        let map = ProductArt.map(icon)
        for (yy, row) in map.enumerated() where yy % 2 == 0 {
            for (xx, ch) in row.enumerated() where xx % 2 == 0 {
                guard let c = ProductArt.color(ch) else { continue }
                dot(bx + 1 + xx / 2, by - 10 - hop + yy / 2, c)
            }
        }
        // crates waiting on the pier while it loads
        if !failed && !done && slow % span < 6 { dot(2, 14, Brand.amber); dot(4, 14, Brand.amber); dot(3, 13, Brand.amber) }
    }
}

// MARK: - Pixel art per product (24×24, Steerify palette)

struct ProductArt: View {
    let icon: String

    var body: some View {
        Canvas { ctx, sz in
            let m = Self.map(icon), n = CGFloat(m.count)
            let cell = min(sz.width, sz.height) / n
            for (y, row) in m.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let c = Self.color(ch) else { continue }
                    ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.3, height: cell + 0.3)), with: .color(c))
                }
            }
        }
    }

    static func guess(_ s: String) -> String {
        let t = s.lowercased()
        if t.contains("iphone") || t.contains("ios") || t.contains("mobile") { return "ios" }
        if t.contains("mac") || t.contains("desktop") { return "mac" }
        if t.contains("site") || t.contains("web") || t.contains("landing") { return "web" }
        if t.contains("api") || t.contains("server") || t.contains("backend") { return "api" }
        if t.contains("extension") || t.contains("plugin") { return "extension" }
        if t.contains("platform") || t.contains("ui") || t.contains("dashboard") { return "platform" }
        return "box"
    }

    /// k dark · m metal · b blue · c cream · a amber · g green · r red · v violet · w white · . none
    static func color(_ ch: Character) -> Color? {
        switch ch {
        case "k": return Color(hex: 0x16171c)
        case "m": return Color(hex: 0x6b7280)
        case "n": return Color(hex: 0x3a3f4b)
        case "b": return Color(hex: 0x3d6ea5)
        case "B": return Brand.blue
        case "c": return Brand.cream
        case "a": return Brand.amber
        case "g": return Brand.green
        case "r": return Brand.red
        case "v": return Brand.violet
        case "w": return .white
        default: return nil
        }
    }

    static func map(_ icon: String) -> [String] { maps[icon] ?? maps["box"]! }

    static let maps: [String: [String]] = [
        "mac": [
            "........................",
            "........................",
            "...mmmmmmmmmmmmmmmmmm...",
            "...mkkkkkkkkkkkkkkkkm...",
            "...mkbbbbbbbbbbbbbbkm...",
            "...mkbccccbbbbbbaabkm...",
            "...mkbbbbbbbbbbbaabkm...",
            "...mkbccccccccbbbbbkm...",
            "...mkbbbbbbbbbbbbbbkm...",
            "...mkbcccccbbbggggbkm...",
            "...mkbbbbbbbbbggggbkm...",
            "...mkbccccccccbbbbbkm...",
            "...mkbbbbbbbbbbbbbbkm...",
            "...mkbbbbbbbbbbbbbbkm...",
            "...mkkkkkkkkkkkkkkkkm...",
            "...mmmmmmmmmmmmmmmmmm...",
            ".mmmmmmmmmmmmmmmmmmmmmm.",
            "nnnnnnnnnkkkkkknnnnnnnnn",
            ".nnnnnnnnnnnnnnnnnnnnnn.",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................"],
        "web": [
            "........................",
            "........................",
            "........bbbbbbbb........",
            "......bbggbbbbggbb......",
            ".....bggggbccbgggbb.....",
            "....bgggggbccbggggbb....",
            "...bbgggggbccbbgggbbb...",
            "...bbbgggbbccbbbbbbbb...",
            "..bbbbbbbbbccbbbbbbbbb..",
            "..bbbbbbbbbccbbbggggbb..",
            "aaccccccccccccccccccccaa",
            "aaccccccccccccccccccccaa",
            "..bbbgggbbbccbbbgggggb..",
            "..bbggggggbccbbbggggbb..",
            "...bggggggbccbbbbgggb...",
            "...bbgggggbccbbbbbbbb...",
            "....bbgggbbccbbbbbbb....",
            ".....bbbbbbccbbgggb.....",
            "......bbbbbccbbggb......",
            "........bbbbbbbb........",
            "........................",
            "........................",
            "........................",
            "........................"],
        "ios": [
            "........................",
            "........mmmmmmmm........",
            ".......mkkkkkkkkm.......",
            ".......mkkkmmkkkm.......",
            ".......mbbbbbbbbm.......",
            ".......mbccccccbm.......",
            ".......mbbbbbbbbm.......",
            ".......mbccccbbbm.......",
            ".......mbbbbbbbbm.......",
            ".......mbaaaaaabm.......",
            ".......mbaaaaaabm.......",
            ".......mbbbbbbbbm.......",
            ".......mbccccccbm.......",
            ".......mbbbbbbbbm.......",
            ".......mbggbbggbm.......",
            ".......mbggbbggbm.......",
            ".......mbbbbbbbbm.......",
            ".......mbbbbbbbbm.......",
            ".......mkkkkkkkkm.......",
            ".......mkkkcckkkm.......",
            "........mmmmmmmm........",
            "........................",
            "........................",
            "........................"],
        "platform": [
            "........................",
            "........................",
            ".mmmmmmmmmmmmmmmmmmmmmm.",
            ".mkrkakgkkkkkkkkkkkkkkm.",
            ".mmmmmmmmmmmmmmmmmmmmmm.",
            ".mnnnnkbbbbbbbbbbbbbbbm.",
            ".mnccnkbbbbbbbbbbbbbbbm.",
            ".mnnnnkbbbbbbbbbbbaabbm.",
            ".mnccnkbbbbbbbbbbaaabbm.",
            ".mnnnnkbbbbbbbbaabbbbbm.",
            ".mnccnkbbbbbbaaabbbbbbm.",
            ".mnnnnkbbbbbaabbbbbbbbm.",
            ".mnccnkbbaaabbbbbbbbbbm.",
            ".mnnnnkbbbbbbbbbbbbbbbm.",
            ".mnnnnkkkkkkkkkkkkkkkkm.",
            ".mnnnnkggggkvvvvkcccckm.",
            ".mnnnnkggggkvvvvkcccckm.",
            ".mnnnnkkkkkkkkkkkkkkkkm.",
            ".mmmmmmmmmmmmmmmmmmmmmm.",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................"],
        "api": [
            "........................",
            "........................",
            "........................",
            "....aa............aa....",
            "...aa..............aa...",
            "...aa...mmmmmmmm...aa...",
            "...aa...mkkkkkkm...aa...",
            "..aa....mkggggkm....aa..",
            "..aa....mkkkkkkm....aa..",
            ".aa.....mkbbbbkm.....aa.",
            "..aa....mkkkkkkm....aa..",
            "..aa....mkggggkm....aa..",
            "...aa...mkkkkkkm...aa...",
            "...aa...mmmmmmmm...aa...",
            "...aa......mm......aa...",
            "....aa.....mm.....aa....",
            "...........mm...........",
            "........cccmmccc........",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................"],
        "extension": [
            "........................",
            "........................",
            "........vvvv............",
            ".......vvvvvv...........",
            ".......vvvvvv...........",
            "...vvvvvvvvvvvvvvvv.....",
            "...vvvvvvvvvvvvvvvv.....",
            "...vvvvvvvvvvvvvvvv.....",
            "...vvvvvvvvvvvvvvvvvv...",
            "...vvvvvvvvvvvvvvvvvvv..",
            "...vvvvvvvvvvvvvvvvvvv..",
            "...vvvvvvvvvvvvvvvvvv...",
            "...vvvvvvvvvvvvvvvv.....",
            ".....vvvvvvvvvvvvvv.....",
            "....vvvvvvvvvvvvvvv.....",
            "....vvvvvvvvvvvvvvv.....",
            ".....vvvvvvvvvvvvvv.....",
            "...vvvvvvvvvvvvvvvv.....",
            "...vvvvvvvvvvvvvvvv.....",
            "...vvvvvvvvvvvvvvvv.....",
            "........................",
            "........................",
            "........................",
            "........................"],
        "box": [
            "........................",
            "........................",
            "........................",
            "......aaaaaaaaaaaa......",
            ".....aaccaaaaaaccaa.....",
            "....aaaaaaaaaaaaaaaa....",
            "....mmmmmmmmmmmmmmmm....",
            "....maaaaaaaaaaaaaam....",
            "....maaaaakkkkaaaaam....",
            "....maaaaaaaaaaaaaam....",
            "....maaaaaaaaaaaaaam....",
            "....maaaaaaaaaaaaaam....",
            "....maaaaaaaaaaaaaam....",
            "....maaaaaaaaaaaaaam....",
            "....maaaaaaaaaaaaaam....",
            "....mmmmmmmmmmmmmmmm....",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................"],
    ]
}
