import SwiftUI

// One start for a new project (request r261120-172615, choice init-one-start A). Three phases:
//   welcome — the board is empty and setup is not running: one centered modal over the dimmed window, one button
//             (Set up with Claude), what it does underneath, a quiet Skip link. No session pane, no second set of
//             buttons competing with it.
//   live    — the setup session runs: Claude on the right, and on the left the board filling in as Claude writes
//             it (the past conversations it linked, each choice as a real card you can answer, then the drafts).
//   board   — otherwise: the normal board (its Next strip says what to do first).
// Pressing the button also links the Claude Code conversations already in the project's folders to the board
// (`past:<id>` links), so they can be resumed from Steerify and Claude can map them to items.

enum ProjectSetup {
    /// Projects whose welcome was skipped with "Start empty" (per Mac).
    static let skippedKey = "setupSkipped"

    static func skipped(_ id: String) -> Bool { (Prefs.store.stringArray(forKey: skippedKey) ?? []).contains(id) }
    static func skip(_ id: String) {
        var s = Prefs.store.stringArray(forKey: skippedKey) ?? []
        if !s.contains(id) { s.append(id); Prefs.store.set(s, forKey: skippedKey) }
    }

    /// Projects whose live setup view you left for the full board ("Open the full board"), this run of the app.
    @MainActor static var leftLive = Set<String>()

    /// Nothing on the board yet: no goal, choices, requirements, roadmap or To test items.
    @MainActor static func isBlank(_ b: BoardStore) -> Bool {
        b.goal.trimmingCharacters(in: .whitespaces).isEmpty && b.decisions.isEmpty && b.requirements.isEmpty
            && b.roadmap.isEmpty && b.chapters.isEmpty && b.ships.isEmpty
    }

    @MainActor static func needsWelcome(_ b: BoardStore) -> Bool {
        b.loadedAt != .distantPast && isBlank(b) && !skipped(b.project.id)
    }

    enum Phase { case welcome, live, board }

    @MainActor static func phase(_ b: BoardStore, _ model: AppModel) -> Phase {
        let p = b.project
        let running = model.sessions.contains { $0.projectId == p.id && $0.covers("setup:" + p.id) && $0.running }
        if running { return leftLive.contains(p.id) ? .board : .live }
        return needsWelcome(b) ? .welcome : .board
    }

    static func ref(_ p: Project) -> ItemRef {
        var r = ItemRef(ref: "setup:" + p.id)!
        r.title = "Setup: " + p.name
        return r
    }
}

/// Picks the screen for the project's setup phase. Observes the board, so it moves on by itself as Claude writes.
struct SetupGate<Content: View, Live: View, Welcome: View>: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    @ViewBuilder let content: Content
    @ViewBuilder let live: Live
    @ViewBuilder let welcome: Welcome
    @State private var tick = 0     // re-render after "Start empty" / "Open the full board" (not observed otherwise)

    var body: some View {
        Group {
            switch ProjectSetup.phase(board, model) {
            case .welcome: welcome
            case .live: live
            case .board: content
            }
        }
        .id(tick)
        .onReceive(NotificationCenter.default.publisher(for: .setupSkipped)) { _ in tick += 1 }
    }
}

extension Notification.Name { static let setupSkipped = Notification.Name("steerify.setupSkipped") }

// MARK: - Past conversations: the Claude Code chats already held for the project's folders

enum PastConversations {
    struct Found { let id: String; let title: String; let date: Date; let repo: String }

    /// Claude Code keeps a folder's conversations in ~/.claude/projects/<path with every non-alphanumeric as ->/.
    static func folder(_ path: String) -> URL {
        let key = String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects/" + key)
    }

    /// The newest conversations of the project's repos (newest first), with the first thing you asked as title.
    static func find(_ p: Project, limit: Int = 12) -> [Found] {
        var out: [Found] = []
        var seen = Set<String>()
        for r in p.repos where r.exists {
            // The path as Steerify knows it and as the system resolves it (/tmp → /private/tmp): Claude files by either.
            let real = realpath(r.path, nil).map { defer { free($0) }; return String(cString: $0) } ?? r.path
            for dir in Set([folder(r.path), folder(real)]) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for f in files where f.pathExtension == "jsonl" && seen.insert(f.lastPathComponent).inserted {
                let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                out.append(Found(id: f.deletingPathExtension().lastPathComponent, title: "", date: date, repo: r.name))
            }
            }
        }
        return out.sorted { $0.date > $1.date }.prefix(limit).compactMap { f in
            guard let url = SessionSummaries.transcript(f.id), let t = firstAsk(url) else { return nil }
            return Found(id: f.id, title: t, date: f.date, repo: f.repo)
        }
    }

    /// The first thing a person asked in a transcript (reads only its beginning).
    static func firstAsk(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: 256 * 1024)) ?? Data()
        let s = String(decoding: data, as: UTF8.self)
        for line in s.split(separator: "\n") where line.contains("\"type\":\"user\"") {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  o["isSidechain"] as? Bool != true, let msg = o["message"] as? [String: Any] else { continue }
            var texts: [String] = []
            if let c = msg["content"] as? String { texts = [c] }
            else if let parts = msg["content"] as? [[String: Any]] { texts = parts.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String } }
            for t in texts {
                if let r = t.range(of: "<command-args>"), let e = t.range(of: "</command-args>"), r.upperBound <= e.lowerBound {
                    let args = t[r.upperBound..<e.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !args.isEmpty { return clip(args) }
                    continue
                }
                if t.hasPrefix("<") || t.hasPrefix("Base directory for this skill") || t.hasPrefix("Caveat:") { continue }
                let line = t.split(separator: "\n").first.map(String.init) ?? t
                if line.trimmingCharacters(in: .whitespaces).count > 3 { return clip(line) }
            }
        }
        return nil
    }

    private static func clip(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 70 ? String(t.prefix(68)) + "…" : t
    }

    /// Links the conversations not on the board yet as `past:<id>`. Returns how many it added.
    @MainActor @discardableResult
    static func link(_ p: Project, board: BoardStore) -> Int {
        let known = Set(board.links.map(\.claudeSession))
        let fresh = find(p).filter { !known.contains($0.id) }
        for f in fresh.reversed() {
            SessionLinks.append(SessionLink(item: "past:" + f.id, claudeSession: f.id, intent: "past", repo: f.repo,
                                            title: f.title, started: AppModel.iso.string(from: f.date), by: "setup"), in: p.boardDir)
        }
        if !fresh.isEmpty { board.reload() }
        return fresh.count
    }
}

// MARK: - Welcome: one modal, one button

struct SetupModal: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore

    private var p: Project { board.project }
    private var started: Bool { board.lastLink("setup:" + p.id) != nil }
    private var boardFolder: String {
        let repo = p.repos.first.map { ($0.path as NSString).lastPathComponent } ?? p.name
        return p.boardDir.hasSuffix("/.steerify") ? "\(repo)/.steerify/" : (p.boardDir as NSString).lastPathComponent + "/"
    }

    var body: some View {
        ZStack {
            // The window behind, dimmed: a few empty board rows so it reads as "your board, still empty".
            VStack(spacing: S(12)) {
                ForEach(0..<5, id: \.self) { _ in RoundedRectangle(cornerRadius: 10).fill(Brand.panel).frame(height: S(64)) }
                Spacer()
            }
            .padding(S(24)).opacity(0.35).blur(radius: 1.5)
            Color.black.opacity(0.55)

            VStack(spacing: S(16)) {
                Text(started ? "Finish setting up \(p.name)" : "Set up \(p.name) with Claude")
                    .font(.system(size: S(24), weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text(started ? "Claude picks up where it stopped. Nothing it drafted is lost."
                             : "Claude reads the project, asks you a few questions,\nand drafts the board for you to approve.")
                    .font(.system(size: S(13.5))).foregroundStyle(Brand.mute).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: setUp) {
                    HStack(spacing: S(8)) {
                        ClaudeSpark(size: S(15), color: .white)
                        Text(started ? "Resume setup with Claude" : "Set up with Claude").font(.system(size: S(16), weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, S(26)).padding(.vertical, S(12))
                    .background(RoundedRectangle(cornerRadius: 9).fill(Brand.claude))
                }
                .buttonStyle(SteerButton())
                .keyboardShortcut(.defaultAction)
                .help("Starts a Claude Code session: /steerify init")

                HStack(alignment: .top, spacing: S(14)) {
                    step("Reads the project", "Code, README, git history, your past Claude chats here.")
                    step("Asks you", "Choices with pictures, on the board.")
                    step("Drafts the board", "Goal, requirements, roadmap. You approve.")
                }
                .padding(.top, S(4))

                Rectangle().fill(Brand.line).frame(height: 1)
                (Text("Writes ").foregroundStyle(Brand.ink).fontWeight(.semibold) + Text("only in \(boardFolder) · ").foregroundStyle(Brand.mute)
                 + Text("Sends ").foregroundStyle(Brand.ink).fontWeight(.semibold) + Text("what Claude reads to Anthropic · ").foregroundStyle(Brand.mute)
                 + Text("Never ").foregroundStyle(Brand.ink).fontWeight(.semibold) + Text("pushes or deploys · ~10 min, resume any time").foregroundStyle(Brand.mute))
                    .font(.system(size: S(11.5))).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)

                Button("Skip, start with an empty board") {
                    ProjectSetup.skip(p.id)
                    NotificationCenter.default.post(name: .setupSkipped, object: nil)
                }
                .buttonStyle(.plain).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).underline()
                .help("The empty board, to fill yourself")
            }
            .padding(.horizontal, S(32)).padding(.vertical, S(30))
            .frame(width: S(560))
            .background(RoundedRectangle(cornerRadius: 16).fill(Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.line2))
            .shadow(color: .black.opacity(0.7), radius: 40, y: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.bg)
        .onAppear {   // test hook: `--setup-start` presses "Set up with Claude" after 1.5 s
            if CommandLine.arguments.contains("--background"), CommandLine.arguments.contains("--setup-start") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { setUp() }
            }
        }
    }

    private func setUp() {
        PastConversations.link(p, board: board)
        // Test copies (`--dry-sessions`) echo the command instead of starting Claude.
        model.start(projectId: p.id, item: ProjectSetup.ref(p), intent: .initialize,
                    dry: CommandLine.arguments.contains("--dry-sessions"))
    }

    private func step(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(Brand.line).frame(height: 1).padding(.bottom, S(5))
            Text(title).font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(Brand.ink)
            Text(line).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Live: the board filling in while Claude sets it up

struct SetupLive: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore

    private var p: Project { board.project }
    private var past: [SessionLink] { board.links.filter { $0.item.hasPrefix("past:") }.reversed() }
    private var open: [BoardDecision] { board.decisions.filter { !board.isDecided($0) && !board.isParked($0) } }
    private var answered: [BoardDecision] { board.decisions.filter { board.isDecided($0) } }
    private var drafts: [Chapter] { board.chapters.filter(\.draft) }

    private var status: String {
        if !drafts.isEmpty { return "Roadmap drafted: approve it when it looks right" }
        if !open.isEmpty { return "Waiting on your answers: Claude drafts the roadmap from them" }
        if !answered.isEmpty { return "Drafting from your answers…" }
        return "Reading and running the project…"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: S(12)) {
                HStack(spacing: 8) {
                    Text("\(p.name.uppercased()) · BEING SET UP").font(Brand.label(10)).tracking(0.9).foregroundStyle(Brand.claude)
                    Spacer()
                    Button("Open the full board") {
                        ProjectSetup.leftLive.insert(p.id)
                        NotificationCenter.default.post(name: .setupSkipped, object: nil)
                    }
                    .buttonStyle(.plain).font(.system(size: S(11))).foregroundStyle(Brand.mute).underline()
                }
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).opacity(drafts.isEmpty ? 1 : 0)
                    Text(status).font(.system(size: S(13), weight: .semibold)).foregroundStyle(Brand.ink)
                }

                if !past.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LINKED · \(past.count) past Claude conversation\(past.count == 1 ? "" : "s")")
                            .font(Brand.label(9)).tracking(0.7).foregroundStyle(Brand.mute)
                        Text(past.prefix(3).map { "“\($0.title ?? "")”" }.joined(separator: " · ") + (past.count > 3 ? " …" : ""))
                            .font(.system(size: S(12))).foregroundStyle(Brand.ink).lineLimit(2)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.line))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ForEach(open) { d in
                    DecisionCard(board: board, d: d).id("choice:" + d.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if !answered.isEmpty {
                    Text("ANSWERED · " + answered.map(\.title).joined(separator: " · "))
                        .font(.system(size: S(11.5))).foregroundStyle(Brand.green).lineLimit(2)
                }

                ForEach(drafts) { c in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ROADMAP · DRAFT").font(Brand.label(9)).tracking(0.7).foregroundStyle(Brand.green)
                            Text(c.name).font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(Brand.ink)
                            if let o = c.objective { Text(o).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(2) }
                        }
                        Spacer()
                        ActionButton(title: "Review it", primary: true) {
                            ProjectSetup.leftLive.insert(p.id)
                            NotificationCenter.default.post(name: .setupSkipped, object: nil)
                            model.focusItem(projectId: p.id, ref: "track:" + BoardFiles.slug(c.name))
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.green.opacity(0.5)))
                }
                if drafts.isEmpty {
                    skeleton(board.requirements.isEmpty ? "Requirements: drafting after your answers…" : "Requirements: \(board.requirements.count) drafted")
                    skeleton("Roadmap: drafting after your answers…")
                }
            }
            .padding(S(18))
            .animation(.easeOut(duration: 0.5), value: board.decisions.count + past.count + drafts.count)
        }
        .background(Brand.bg)
    }

    private func skeleton(_ t: String) -> some View {
        Text(t).font(.system(size: S(12))).foregroundStyle(Brand.mute)
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: S(44), alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.line2, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// "NOT SET UP": shown next to a project whose board is still empty (switcher, project list).
struct SetupTag: View {
    var body: some View {
        Text("NOT SET UP").font(Brand.label(8.5)).tracking(0.6).foregroundStyle(Brand.amber)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Brand.amber.opacity(0.8)))
            .fixedSize()
            .help("Its board is empty: open it and press Set up with Claude")
    }
}
