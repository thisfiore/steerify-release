import SwiftUI

// New project welcome (choice new-project-welcome, A): a project whose board is still empty opens on a welcome
// screen instead of empty tabs. It says what setup does, what it writes and what leaves the Mac, and has one button
// that starts `/steerify init setup:<project>` in the session pane on the right. It stays until the board has
// something on it (Claude's drafts) or you pick "Start empty"; leave halfway and it comes back, with "Resume setup".

enum ProjectSetup {
    /// Projects whose welcome was skipped with "Start empty" (per Mac).
    static let skippedKey = "setupSkipped"

    static func skipped(_ id: String) -> Bool { (Prefs.store.stringArray(forKey: skippedKey) ?? []).contains(id) }
    static func skip(_ id: String) {
        var s = Prefs.store.stringArray(forKey: skippedKey) ?? []
        if !s.contains(id) { s.append(id); Prefs.store.set(s, forKey: skippedKey) }
    }

    /// Nothing on the board yet: no goal, choices, requirements, roadmap or To test items.
    @MainActor static func isBlank(_ b: BoardStore) -> Bool {
        b.goal.trimmingCharacters(in: .whitespaces).isEmpty && b.decisions.isEmpty && b.requirements.isEmpty
            && b.roadmap.isEmpty && b.chapters.isEmpty && b.ships.isEmpty
    }

    @MainActor static func needsWelcome(_ b: BoardStore) -> Bool {
        b.loadedAt != .distantPast && isBlank(b) && !skipped(b.project.id)
    }

    static func ref(_ p: Project) -> ItemRef {
        var r = ItemRef(ref: "setup:" + p.id)!
        r.title = "Setup: " + p.name
        return r
    }
}

/// Shows `content` normally, `welcome` while the project still needs setting up. Observes the board, so the
/// welcome goes away by itself as soon as Claude's first drafts land.
struct SetupGate<Content: View, Welcome: View>: View {
    @ObservedObject var board: BoardStore
    @ViewBuilder let content: Content
    @ViewBuilder let welcome: Welcome
    @State private var tick = 0     // re-render after "Start empty" (UserDefaults is not observed)

    var body: some View {
        Group {
            if ProjectSetup.needsWelcome(board) { welcome } else { content }
        }
        .id(tick)
        .onReceive(NotificationCenter.default.publisher(for: .setupSkipped)) { _ in tick += 1 }
    }
}

extension Notification.Name { static let setupSkipped = Notification.Name("steerify.setupSkipped") }

struct NewProjectWelcome: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore

    private var p: Project { board.project }
    private var started: Bool { board.lastLink("setup:" + p.id) != nil }
    private var running: Bool { model.sessions.contains { $0.projectId == p.id && $0.covers("setup:" + p.id) && $0.running } }
    private var boardFolder: String {
        let repo = p.repos.first.map { ($0.path as NSString).lastPathComponent } ?? p.name
        return p.boardDir.hasSuffix("/.steerify") ? "\(repo)/.steerify/" : (p.boardDir as NSString).lastPathComponent + "/"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: S(18)) {
                HStack(spacing: 8) {
                    Text(running ? "SETTING UP" : "NOT SET UP").font(Brand.label(9)).tracking(0.8)
                        .foregroundStyle(running ? Brand.claude : Brand.amber)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(running ? Brand.claude : Brand.amber))
                }
                Text(running ? "\(p.name) is being set up" : "\(p.name) is ready to steer")
                    .font(.system(size: S(22), weight: .bold)).foregroundStyle(.white)
                Text(running ? "Answer Claude's questions in the session on the right. Its drafts show up here for you to approve."
                             : "Claude will read the project and ask you a few questions. Then it drafts the board for you to approve.")
                    .font(.system(size: S(13))).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: S(14)) {
                    step(1, "Reads the project", "Code, README, git history. Empty folder? It skips this.")
                    step(2, "Interviews you", "Goal, users, what's next. Until it has enough context.")
                    step(3, "Drafts goal, requirements, roadmap", "As drafts. Nothing is agreed until you say so.")
                }

                HStack(spacing: 14) {
                    if running {
                        ClaudeButton(title: "Go to the session", prominent: true) { setUp() }
                    } else {
                        ClaudeButton(title: started ? "Resume setup with Claude" : "Set up with Claude", prominent: true) { setUp() }
                            .scaleEffect(1.15, anchor: .leading).padding(.trailing, S(30))
                            .help("Starts a Claude Code session on the right: /steerify init")
                        Button("Start empty") {
                            ProjectSetup.skip(p.id)
                            NotificationCenter.default.post(name: .setupSkipped, object: nil)
                        }
                        .buttonStyle(.plain).font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.ink)
                        .help("Skip setup: the empty board, to fill yourself")
                    }
                    Spacer()
                    Text("~10 min · stop and resume any time").font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                }

                Rectangle().fill(Brand.line).frame(height: 1)
                Grid(alignment: .leading, horizontalSpacing: S(28), verticalSpacing: S(6)) {
                    GridRow { trust("Writes", "only in \(boardFolder)"); trust("Runs", "Claude Code on this Mac") }
                    GridRow { trust("Sends", "what Claude reads to Anthropic"); trust("Never", "pushes or deploys") }
                }
            }
            .frame(maxWidth: S(620), alignment: .leading)
            .padding(.top, S(48)).padding(.horizontal, S(24))
            .frame(maxWidth: .infinity)
        }
        .background(Brand.bg)
        .onAppear {   // test hook: `--setup-start` presses "Set up with Claude" after 1.5 s
            if CommandLine.arguments.contains("--background"), CommandLine.arguments.contains("--setup-start") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { setUp() }
            }
        }
    }

    private func setUp() {
        // Test copies (`--dry-sessions`) echo the command instead of starting Claude.
        model.start(projectId: p.id, item: ProjectSetup.ref(p), intent: .initialize,
                    dry: CommandLine.arguments.contains("--dry-sessions"))
    }

    private func step(_ n: Int, _ title: String, _ line: String) -> some View {
        HStack(alignment: .top, spacing: S(12)) {
            Text("\(n)").font(.system(size: S(12), design: .monospaced)).foregroundStyle(Brand.ink)
                .frame(width: S(26), height: S(26))
                .background(Circle().fill(Brand.panel2)).overlay(Circle().stroke(Brand.line2))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(.white)
                Text(line).font(.system(size: S(12))).foregroundStyle(Brand.mute)
            }
        }
    }

    private func trust(_ bold: String, _ rest: String) -> some View {
        (Text(bold + " ").foregroundStyle(Brand.ink).fontWeight(.semibold) + Text(rest).foregroundStyle(Brand.mute))
            .font(.system(size: S(12)))
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
