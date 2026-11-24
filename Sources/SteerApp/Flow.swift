import SwiftUI
import AppKit

// MARK: - How sessions use git (choice branches-releases-standard, request r261119-172532)
//
// Three modes, per project in steerify.json → release.flow, default from Settings (⌘,):
//   main      every session works in the repo's own checkout, on the release branch (simple projects; the old way)
//   worktree  a feature gets its own folder + branch steer/<feature>; merged into the release branch after your OK
//   pr        like worktree, and the branch goes up as a pull request; your OK merges it
// The board always stays in the main checkout ($STEERIFY_BOARD), whatever the mode.

enum WorkFlow: String, CaseIterable, Identifiable, Codable {
    case main, worktree, pr
    var id: String { rawValue }
    var title: String { [.main: "On main", .worktree: "Worktree per feature", .pr: "Branch + pull request"][self]! }
    var short: String { [.main: "main", .worktree: "worktrees", .pr: "pull requests"][self]! }
    var note: String {
        [.main: "Every session in the repo's own folder, on main. Simple projects.",
         .worktree: "Each feature in its own folder and branch. Merged after your OK.",
         .pr: "Each feature on a branch, opened as a pull request. Your OK merges it."][self]!
    }
    var lines: [String] {
        [.main: ["one folder, one branch", "commit only your own changes", "warns if a session switches branch"],
         .worktree: ["steer/<feature> in its own folder", "sessions never share a checkout", "OK → merge into main, folder removed"],
         .pr: ["steer/<feature> in its own folder", "pushed + pull request on GitHub", "OK or a merge on GitHub → shipped"]][self]!
    }
    /// When to pick it, in one line (the cards + Settings → Branches).
    var bestFor: String {
        [.main: "One session at a time.", .worktree: "Several sessions in parallel.", .pr: "Someone reviews and merges on GitHub."][self]!
    }

    /// Intents that write code get the feature's folder; the others (release, ship, look…) work in the main checkout.
    static let codeIntents: Set<Intent> = [.build, .fix, .plan]

    /// The default for projects that don't say (Settings). "main" unless you change it.
    static var appDefault: WorkFlow { WorkFlow(rawValue: Prefs.store.string(forKey: Prefs.defaultFlow) ?? "") ?? .main }
    static func of(_ p: Project) -> WorkFlow { p.release?.flow.flatMap(WorkFlow.init(rawValue:)) ?? appDefault }
}

extension Prefs { static let defaultFlow = "defaultFlow" }   // main | worktree | pr

/// A feature's own checkout: <repo>-worktrees/<slug>, next to the repo, on branch steer/<slug>.
struct Worktree {
    let path: String
    let branch: String
    let main: String        // the repo's own checkout

    static func slug(_ s: String) -> String {
        let base = BoardFiles.slug(s).lowercased()
        return String(base.prefix(48)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Where the feature of `key` lives for this repo (nothing is created).
    static func place(repo: Repo, key: String) -> Worktree {
        let s = slug(key)
        let parent = (repo.path as NSString).deletingLastPathComponent
        let path = ((parent as NSString).appendingPathComponent(repo.name + "-worktrees") as NSString).appendingPathComponent(s)
        return Worktree(path: path, branch: "steer/" + s, main: repo.path)
    }

    /// Creates the folder (from the release branch) if it isn't there; reuses the branch if it exists. Error text on failure.
    func ensure(from base: String) -> String? {
        if FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git")) { return nil }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let exists = Worktree.git(main, ["rev-parse", "--verify", "--quiet", "refs/heads/" + branch]).ok
        let r = exists ? Worktree.git(main, ["worktree", "add", path, branch])
                       : Worktree.git(main, ["worktree", "add", "-b", branch, path, base])
        return r.ok ? nil : r.out
    }

    static func git(_ dir: String, _ args: [String]) -> (ok: Bool, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir] + args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        let done = DispatchSemaphore(value: 0)   // never waitUntilExit on the main thread (see Git.run)
        p.terminationHandler = { _ in done.signal() }
        guard (try? p.run()) != nil else { return (false, "could not run git") }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        done.wait()
        return (p.terminationStatus == 0, (String(data: d, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension AppModel {
    /// The folder a new session for `item` should run in, and what it tells Claude. 
    func workplace(for item: ItemRef, intent: Intent, repo: Repo, in p: Project) -> (dir: String, brief: String, env: [String: String]) {
        let flow = WorkFlow.of(p)
        let base = p.release?.repos[repo.name]?.branch ?? "main"
        var env = ["STEERIFY_FLOW": flow.rawValue, "STEERIFY_REPO_MAIN": repo.path, "STEERIFY_RELEASE_BRANCH": base]
        // A fix / refinement filed as a request is code work too: its intake fixes it (choice parallel-sessions-branch-safety A).
        let codeIntake = intent == .intake && item.kind == "request"
            && [.fix, .refine].contains(RequestLog.cached(p.boardDir).first { $0.id == item.id }?.kind)
        guard flow != .main, WorkFlow.codeIntents.contains(intent) || codeIntake, ["road", "choice", "test", "request"].contains(item.kind) else {
            return (repo.path, "", env)   // the repo's own checkout; Claude still learns the mode
        }
        // One folder per feature: the roadmap key result the item belongs to, else the item itself.
        let key = board(for: p).roads(of: item.ref).sorted().first.map { String($0.dropFirst(5)) } ?? item.id
        let w = Worktree.place(repo: repo, key: key)
        if let err = w.ensure(from: base) {
            NSLog("[Steerify] worktree failed for \(item.ref): \(err)")
            return (repo.path, "Steerify could not create the feature folder (\(err.prefix(160))); work in the main checkout this time.", env)
        }
        env["STEERIFY_BRANCH"] = w.branch
        env["STEERIFY_WORKTREE"] = w.path
        let brief = "Git flow of this project: \(flow.rawValue). You are in the feature folder \(w.path) on branch \(w.branch) "
            + "(main checkout: \(repo.path), release branch: \(base)). Commit here; the board stays at $STEERIFY_BOARD (never edit the .steerify copy in this folder). "
            + "See 'Branches and releases' in the steerify skill."
        return (w.path, brief, env)
    }
}

// MARK: - Pickers (Release setup, Settings)

/// Three cards, one per mode: what it means in three short lines.
struct FlowPicker: View {
    @Binding var flow: WorkFlow
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(WorkFlow.allCases) { f in
                let on = f == flow
                Button { flow = f } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(f.title.uppercased()).font(Brand.label(9)).tracking(0.6).foregroundStyle(on ? Brand.amber : Brand.mute)
                            Spacer()
                            if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.amber) }
                        }
                        FlowDiagram(flow: f).frame(height: 38)
                        Text(f.bestFor).font(.system(size: S(11), weight: .semibold)).foregroundStyle(on ? Brand.cream : Brand.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(f.lines, id: \.self) { l in
                            Text("· " + l).font(.system(size: S(11))).foregroundStyle(Brand.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel2))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Brand.amber : Brand.line, lineWidth: on ? 2 : 1))
                    .contentShape(Rectangle())
                }.buttonStyle(SteerButton())
            }
        }
    }
}

/// Settings → Branches: what each mode means for sessions running side by side (request r261124-074236).
struct FlowGuide: View {
    private let rows: [(icon: String, title: String, text: String)] = [
        ("rectangle.stack", "Parallel sessions on main share one folder",
         "If one session switches or creates a branch, the folder moves for all of them. Steerify warns at once (a toast naming the repo and the branch) and again when it is back."),
        ("square.split.2x1", "Worktree per feature keeps them apart",
         "build, fix and plan (and fixes filed as requests) get their own folder next to the repo, on steer/<feature>. A branch switch in one never touches another. The board stays in the main folder."),
        ("arrow.triangle.pull", "Pull requests: merge in Steerify or on GitHub",
         "Your OK on the card merges the PR. If the owner merges it on GitHub instead, the Release tab shows “merged on GitHub”: Prepare release pulls it, deploys, marks the card live and removes the folder."),
        ("slider.horizontal.3", "Per project",
         "This is the default for projects that don't choose. Each project can pick its own in Release → Edit setup."),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.title) { r in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: r.icon).font(.system(size: 12)).foregroundStyle(Brand.amber).frame(width: 18).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Brand.cream)
                        Text(r.text).font(.system(size: 11.5)).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel2))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.line))
    }
}

/// A tiny branch picture: main as a line, features as branches that come back after OK.
struct FlowDiagram: View {
    let flow: WorkFlow
    var body: some View {
        Canvas { ctx, size in
            let y = size.height - 8, w = size.width
            var main = Path(); main.move(to: CGPoint(x: 4, y: y)); main.addLine(to: CGPoint(x: w - 4, y: y))
            ctx.stroke(main, with: .color(Brand.green), lineWidth: 2)
            if flow == .main {
                for i in 0..<5 { let x = 12 + CGFloat(i) * (w - 24) / 4
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7)), with: .color(Brand.amber)) }
                return
            }
            for (a, b, h) in [(0.12, 0.55, 22.0), (0.42, 0.88, 12.0)] {
                var p = Path()
                p.move(to: CGPoint(x: w * a, y: y))
                p.addLine(to: CGPoint(x: w * a + 8, y: y - h)); p.addLine(to: CGPoint(x: w * b - 8, y: y - h)); p.addLine(to: CGPoint(x: w * b, y: y))
                ctx.stroke(p, with: .color(Brand.blue), style: StrokeStyle(lineWidth: 1.6, dash: flow == .pr ? [] : [3, 2]))
                ctx.fill(Path(ellipseIn: CGRect(x: w * b - 4, y: y - 4, width: 8, height: 8)), with: .color(Brand.green))
                if flow == .pr {
                    let r = CGRect(x: w * (a + b) / 2 - 9, y: y - h - 6, width: 18, height: 12)
                    ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Brand.blue))
                    ctx.draw(Text("PR").font(.system(size: 7, weight: .bold)).foregroundColor(.black), at: CGPoint(x: r.midX, y: r.midY))
                }
            }
        }
    }
}
