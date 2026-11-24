import SwiftUI
import AppKit

// MARK: - Resume after quit (request r261123-211541, choice resume-interrupted-look option A: harbour wake-up modal)
//
// A restart reopens every Claude conversation with `claude --resume <id>`: history back, but nobody says "go", so a
// session that was mid-work just sits there (often under "Background agent … didn't finish before the previous
// session ended"). Before each conversation is resumed, its transcript tail says whether it stopped mid-work; Apple
// Intelligence (on this Mac) reads the last turn for the ambiguous ones. One modal, all projects: tick, Resume.

struct InterruptedSession: Identifiable, Equatable {
    enum Why: String { case agent, midTool, midStep, esc, atQuit, asked }
    var id: String { claudeId }
    let claudeId: String
    let projectId: String
    var projectName: String
    var title: String
    var why: Why
    /// Short, for the row: "“Build Partner mode…”", "was editing Board.swift".
    var detail: String
    var tick: Bool
    var ai = false
    // What the model reads (not shown).
    var lastAsk = ""
    var lastReply = ""

    var tag: String {
        switch why {
        case .agent: return "agent unfinished"
        case .midTool: return "mid tool"
        case .midStep: return "mid step"
        case .esc: return "stopped"
        case .atQuit: return "working at quit"
        case .asked: return "asked you"
        }
    }
}

/// The transcript's tail, read without the model (tested on real transcripts with `--interrupted-scan`).
enum InterruptedReader {
    struct Tail { var why: InterruptedSession.Why?; var detail: String; var lastAsk: String; var lastReply: String }

    static let stoppedAgent = "didn't finish before the previous session ended"

    /// nil = no transcript. `why` nil = the last turn ended normally.
    static func read(_ url: URL, wasWorking: Bool) -> Tail? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        let chunk: UInt64 = 700_000
        try? h.seek(toOffset: end > chunk ? end - chunk : 0)
        guard let data = try? h.readToEnd() else { return nil }
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        if end > chunk, !lines.isEmpty { lines.removeFirst() }                 // cut-off first line
        return read(lines: lines.map(String.init), wasWorking: wasWorking)
    }

    static func read(lines: [String], wasWorking: Bool) -> Tail {
        enum Last { case none, assistantText, assistantTool(String), toolResult, human, esc, stoppedNote(String) }
        var last = Last.none
        var lastAsk = "", lastReply = ""
        var background: [(id: String, what: String)] = []     // started after the last typed message
        var finished = Set<String>()
        var launched: [String: String] = [:]                   // every background launch in the tail, id → what
        var stopped: [String: String] = [:]                    // tool-use id → its summary, from "didn't finish" notes

        func tag(_ s: String, _ name: String) -> String? {
            guard let a = s.range(of: "<\(name)>"), let b = s.range(of: "</\(name)>", range: a.upperBound..<s.endIndex) else { return nil }
            return String(s[a.upperBound..<b.lowerBound])
        }
        func note(_ s: String) -> Bool {
            guard s.contains("<task-notification>") else { return false }
            let id = tag(s, "tool-use-id") ?? ""
            if s.contains(stoppedAgent) {
                var sum = (tag(s, "summary") ?? "").replacingOccurrences(of: " " + stoppedAgent, with: "")
                if let w = launched[id] { sum = w }
                else if let a = sum.firstIndex(of: "\""), let b = sum[sum.index(after: a)...].firstIndex(of: "\"") { sum = String(sum[sum.index(after: a)..<b]) }   // Background agent "Build …"
                stopped[id] = sum
                last = .stoppedNote(sum)
            } else { finished.insert(id) }
            return true
        }

        for line in lines {
            // Notes queued for Claude (background task ends) arrive as queue operations or as user messages.
            if line.contains("\"type\":\"queue-operation\"") {
                if let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let c = o["content"] as? String { _ = note(c) }
                continue
            }
            guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\""),
                  let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  o["isSidechain"] as? Bool != true, let msg = o["message"] as? [String: Any] else { continue }
            let parts: [[String: Any]] = (msg["content"] as? [[String: Any]]) ?? ((msg["content"] as? String).map { [["type": "text", "text": $0]] } ?? [])
            if o["type"] as? String == "assistant" {
                var tool: String?
                for p in parts {
                    switch p["type"] as? String {
                    case "text": if let t = p["text"] as? String, t.count > 3 { lastReply = t }
                    case "tool_use":
                        let name = p["name"] as? String ?? "tool"
                        let input = p["input"] as? [String: Any] ?? [:]
                        tool = describe(name, input)
                        if input["run_in_background"] as? Bool == true, let id = p["id"] as? String {
                            let what = (input["description"] as? String) ?? tool ?? name
                            background.append((id, what)); launched[id] = what
                        }
                    default: break
                    }
                }
                if let tool { last = .assistantTool(tool) } else if parts.contains(where: { $0["type"] as? String == "text" }) { last = .assistantText }
                continue
            }
            // user: a compaction summary or a meta note is not something you typed
            if o["isCompactSummary"] as? Bool == true || o["isMeta"] as? Bool == true || o["isVisibleInTranscriptOnly"] as? Bool == true { continue }
            if !parts.isEmpty, parts.allSatisfy({ $0["type"] as? String == "tool_result" }) { last = .toolResult; continue }
            let text = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            if note(text) { continue }
            if text.hasPrefix("[Request interrupted") { last = .esc; continue }
            if text.hasPrefix("<") || text.hasPrefix("Base directory for this skill") || text.isEmpty { continue }   // reminders, local commands
            lastAsk = text; last = .human
            background = []
        }

        let open = background.filter { !finished.contains($0.id) }
        let stoppedOne = open.first { stopped[$0.id] != nil } ?? open.first
        func q(_ s: String) -> String { "“" + SessionOutlookReader.short(s, max: 46) + "”" }
        var why: InterruptedSession.Why?, detail = ""
        switch last {
        case .stoppedNote(let s): why = .agent; detail = q(s.isEmpty ? (stoppedOne?.what ?? "background task") : s)
        case .assistantTool(let t):
            if let b = stoppedOne { why = .agent; detail = q(b.what) } else { why = .midTool; detail = t }
        case .toolResult: why = .midStep; detail = stoppedOne.map { q($0.what) } ?? "Claude never answered the last result"
        case .human: why = .midStep; detail = "your last message got no answer"
        case .esc: why = wasWorking ? .esc : nil; detail = "interrupted mid-answer"
        case .assistantText, .none:
            if let b = stoppedOne { why = .agent; detail = q(b.what) }        // a background task the quit killed
            else if wasWorking { why = .atQuit; detail = SessionOutlookReader.short(SessionSummaries.plain(lastReply, max: 60), max: 46) }
        }
        return Tail(why: why, detail: detail, lastAsk: String(lastAsk.prefix(1200)), lastReply: String(lastReply.suffix(1500)))
    }

    /// "was editing Board.swift", "was running swift build".
    static func describe(_ name: String, _ input: [String: Any]) -> String {
        func file(_ k: String) -> String? { (input[k] as? String).map { ($0 as NSString).lastPathComponent } }
        switch name {
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return "was editing " + (file("file_path") ?? file("notebook_path") ?? "a file")
        case "Read": return "was reading " + (file("file_path") ?? "a file")
        case "Bash": return "was running " + SessionOutlookReader.short((input["description"] as? String) ?? (input["command"] as? String) ?? "a command", max: 34)
        case "Agent", "Task": return "agent " + SessionOutlookReader.short((input["description"] as? String) ?? "", max: 34)
        default: return "was using " + name.replacingOccurrences(of: "mcp__", with: "").replacingOccurrences(of: "__", with: " ")
        }
    }

    /// What Resume types into each conversation.
    static func nudge(_ s: InterruptedSession) -> String {
        let what: String
        switch s.why {
        case .agent: return "Steerify quit while a background task was still running (\(s.detail)): it did not finish. Check what it left (partial output, half-done edits), run it again if it is still needed, then carry on with the work and finish it. If it needs my decision, put it on the board as a choice; otherwise go on without asking."
        case .midTool: what = "in the middle of a step (\(s.detail))"
        case .midStep: what = "in the middle of a step"
        case .esc: what = "while you were answering"
        case .atQuit, .asked: what = "while you were working"
        }
        return "Steerify quit \(what), so the work stopped there. Pick it up: check what the interrupted step left (half-done edits, commands that did not finish), redo it if needed, then carry on and finish. If it needs my decision, put it on the board as a choice; otherwise go on without asking."
    }
}

// MARK: - The state behind the modal

@MainActor
final class ResumeInterrupted: ObservableObject {
    static let shared = ResumeInterrupted()
    @Published var found: [InterruptedSession] = []
    @Published var open = false
    @Published var reading = false        // Apple Intelligence still reading
    @Published var sailing = false        // Resume pressed: sails up, boats leave
    var demo = false

    func present(_ list: [InterruptedSession]) {
        guard !list.isEmpty else { return }
        found = list
        open = true
        NSLog("resume-interrupted: offered \(list.count): " + list.map { "\($0.claudeId.prefix(8)) \($0.why.rawValue) tick=\($0.tick)" }.joined(separator: ", "))
        Task { await classify() }
    }

    /// Apple Intelligence on the last turn: mid-work, finished, or waiting on you (+ what it was doing).
    private func classify() async {
        guard LocalAI.ready else { return }
        reading = true
        defer { reading = false }
        for i in found.indices {
            let s = found[i]
            guard !s.lastReply.isEmpty || !s.lastAsk.isEmpty else { continue }
            let prompt = "Signal: \(s.tag) (\(s.detail))\nLast message from the user:\n\(s.lastAsk.prefix(800))\n\nClaude's last words:\n\(s.lastReply.suffix(1200))"
            guard let out = await LocalAI.ask(key: "interrupted:" + LocalAI.hash(prompt),
                instructions: "A coding assistant's session was cut off when its app quit. Decide if it was in the middle of work (MID), had finished (DONE), or had asked the user a question and was waiting (WAITING). Answer on one line exactly: MID|DONE|WAITING: what it was doing, at most 7 words, no quotes.",
                prompt: prompt) else { continue }
            let up = out.uppercased()
            let verdict = up.hasPrefix("WAITING") ? "WAITING" : up.hasPrefix("DONE") ? "DONE" : up.hasPrefix("MID") ? "MID" : ""
            guard !verdict.isEmpty, i < found.count, found[i].id == s.id else { continue }
            var what = out.split(separator: ":", maxSplits: 1).dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            what = what.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”."))
            // Hard signals (a tool cut off, an agent stopped) stay ticked; the model decides the soft ones.
            if s.why == .atQuit || s.why == .esc {
                if verdict == "WAITING" { found[i].why = .asked; found[i].tick = false }
                if verdict == "DONE" { found[i].tick = false }
            }
            if !what.isEmpty, what.count <= 60, s.why != .agent { found[i].detail = what.prefix(1).lowercased() + what.dropFirst() }
            found[i].ai = true
        }
    }

    func toggle(_ id: String) { if let i = found.firstIndex(where: { $0.id == id }) { found[i].tick.toggle() } }

    func close() { withAnimation(.easeOut(duration: 0.2)) { open = false }; sailing = false }

    /// Send each ticked conversation its nudge, once it is ready (its SessionStart hook came in).
    func resume(_ model: AppModel) {
        let picked = found.filter(\.tick)
        NSLog("resume-interrupted: Resume pressed, \(picked.count) ticked (demo \(demo))")
        withAnimation(.easeInOut(duration: 0.3)) { sailing = true }
        for s in picked where !demo {
            Task { @MainActor in
                // Up to 3 minutes for the session to be ready: with many sessions restoring at launch, Claude's
                // SessionStart can take well over 40 s, and a nudge given up on silently is a resume that never happens.
                for _ in 0..<360 {
                    if let t = model.sessions.first(where: { $0.claudeId == s.claudeId }) {
                        guard t.running else { NSLog("resume-interrupted: \(s.claudeId.prefix(8)) closed before it was ready"); return }
                        if t.status == .working { NSLog("resume-interrupted: \(s.claudeId.prefix(8)) already working"); return }
                        if t.status == .idle || t.status == .waiting {
                            let ok = await Self.deliver(InterruptedReader.nudge(s), to: t)
                            NSLog("resume-interrupted: \(ok ? "Claude took it" : "NOT taken after 3 tries") · \(s.claudeId.prefix(8)) (\(s.why.rawValue))")
                            if !ok { model.showToast("“\(s.title)” didn't pick up the resume: open it and press Enter", projectId: s.projectId) }
                            return
                        }
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                NSLog("resume-interrupted: \(s.claudeId.prefix(8)) not ready after 3 min, nothing sent")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in self?.close() }
    }

    /// Type the nudge and make sure Claude took it: its UserPromptSubmit hook turns the session "working".
    /// SessionStart (→ idle) comes while Claude Code is still drawing its screen, and on a busy Mac keys typed then
    /// are lost (seen in a real quit → reopen → Resume test: sent, never arrived). Not taken in 8 s: press Enter again
    /// (the text may be sitting in the box), then clear the line (Ctrl-U) and type it again.
    private static func deliver(_ text: String, to t: TerminalSession) async -> Bool {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        for attempt in 0..<4 {
            switch attempt {
            case 0: t.submit(text)
            case 1: t.view.send(txt: "\r")
            default: t.view.send(txt: "\u{15}"); try? await Task.sleep(nanoseconds: 200_000_000); t.submit(text)
            }
            for _ in 0..<16 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard t.running else { return false }
                if t.status == .working { return true }
            }
            NSLog("resume-interrupted: not taken yet (try \(attempt + 1)), status \(t.status)")
        }
        return false
    }

    /// Screenshots / UI tests: `--resume-demo` shows the modal with invented sessions (Resume sends nothing).
    func showDemo() {
        demo = true
        present([
            .init(claudeId: "d1", projectId: "steerify", projectName: "Steerify", title: "Partner mode · iOS", why: .agent, detail: "“Build Partner mode in iOS app”", tick: true),
            .init(claudeId: "d2", projectId: "steerify", projectName: "Steerify", title: "Roadmap · fix", why: .midTool, detail: "was editing Board.swift", tick: true),
            .init(claudeId: "d3", projectId: "todo", projectName: "Todo demo", title: "Dark mode · build", why: .atQuit, detail: "running the UI tests", tick: true),
            .init(claudeId: "d4", projectId: "todo", projectName: "Todo demo", title: "Export · choose", why: .asked, detail: "waits on your answer", tick: false),
        ])
    }
}

extension AppModel {
    /// Called by restoreSessions for each Claude conversation, BEFORE it is resumed (resuming appends to the transcript).
    func interruptedCheck(_ saved: SavedSession, project p: Project, title: String) -> InterruptedSession? {
        guard let cid = saved.claudeId, let url = SessionSummaries.transcript(cid) else { return nil }
        let wasWorking = saved.status == SessionStatus.working.rawValue
        guard let t = InterruptedReader.read(url, wasWorking: wasWorking), let why = t.why else { return nil }
        return InterruptedSession(claudeId: cid, projectId: p.id, projectName: p.name, title: title, why: why, detail: t.detail,
                                  tick: why != .asked, lastAsk: t.lastAsk, lastReply: t.lastReply)
    }
}

// MARK: - Test hook: `Steerify --interrupted-scan [n]` reads the newest n transcripts (all projects) and prints the verdicts.
enum InterruptedScan {
    static func run(_ n: Int, root dir: String? = nil) {
        let root = dir.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        var files: [(URL, Date)] = []
        for d in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            for f in (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(d).path)) ?? [] where f.hasSuffix(".jsonl") {
                let u = root.appendingPathComponent(d).appendingPathComponent(f)
                if let m = try? fm.attributesOfItem(atPath: u.path)[.modificationDate] as? Date { files.append((u, m)) }
            }
        }
        var counts: [String: Int] = [:]
        for (u, m) in files.sorted(by: { $0.1 > $1.1 }).prefix(n) {
            guard let t = InterruptedReader.read(u, wasWorking: false) else { continue }
            let k = t.why?.rawValue ?? "ended"
            counts[k, default: 0] += 1
            print("\(ISO8601DateFormatter().string(from: m).prefix(16))  \(dir == nil ? "" : u.lastPathComponent + "  ")\(k.padding(toLength: 8, withPad: " ", startingAt: 0))  \(u.deletingPathExtension().lastPathComponent.prefix(8))  \(t.detail)")
        }
        print("— " + counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " · "))
        fflush(stdout)
    }
}

// MARK: - The modal (option A)

struct ResumeInterruptedHost: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var r = ResumeInterrupted.shared
    var body: some View {
        if r.open { ResumeInterruptedSheet().transition(.opacity) }
    }
}

struct ResumeInterruptedSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var r = ResumeInterrupted.shared

    var body: some View {
        let picked = r.found.filter(\.tick).count
        let groups = Dictionary(grouping: r.found, by: \.projectId)
        let order = r.found.map(\.projectId).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { if !r.sailing { r.close() } }
            VStack(alignment: .leading, spacing: 0) {
                HarbourWake(boats: r.found.map { $0.tick }, sailing: r.sailing)
                    .aspectRatio(150.0 / 46.0, contentMode: .fit).frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) { LinearGradient(colors: [.clear, Brand.bg], startPoint: .top, endPoint: .bottom).frame(height: S(26)) }
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    Text("BACK FROM A RESTART").font(Brand.label(10.5)).tracking(1.4).foregroundStyle(Brand.amber)
                    Text(r.sailing ? "\(picked) session\(picked == 1 ? "" : "s") setting sail"
                         : "\(r.found.count) session\(r.found.count == 1 ? "" : "s") stopped when Steerify quit")
                        .font(.system(size: S(19), weight: .bold)).foregroundStyle(.white)
                    HStack(spacing: 6) {
                        if r.reading { ProgressView().controlSize(.mini) }
                        Text(r.reading ? "Apple Intelligence is reading the last turns…"
                             : r.found.contains(where: \.ai) ? "Read on this Mac with Apple Intelligence · tick the ones to resume"
                             : "Tick the ones to resume: Claude picks up where it stopped")
                            .font(.system(size: S(12))).foregroundStyle(Brand.mute)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 12)
                if r.found.count <= 6 { list(order, groups) }
                else { ScrollView { list(order, groups) }.frame(height: S(330)) }
                HStack(spacing: 12) {
                    Button("Not now") { r.close() }.buttonStyle(SteerButton()).font(.system(size: S(12))).foregroundStyle(Brand.mute)
                        .keyboardShortcut(.cancelAction).disabled(r.sailing)
                    Spacer()
                    PixelCTA(title: picked == 0 ? "Pick one to resume" : "Resume \(picked)", subtitle: "Claude goes on where it stopped", icon: "ship") {
                        if picked > 0 && !r.sailing { r.resume(model) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .opacity(picked == 0 || r.sailing ? 0.5 : 1)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
            }
            .frame(width: S(640))
            .background(RoundedRectangle(cornerRadius: 14).fill(Brand.bg))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.amber.opacity(0.35)))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
            .onExitCommand { if !r.sailing { r.close() } }
        }
    }

    private func list(_ order: [String], _ groups: [String: [InterruptedSession]]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(order, id: \.self) { pid in
                let rows = groups[pid] ?? []
                Text("\(rows.first?.projectName ?? pid) · \(rows.count)".uppercased())
                    .font(Brand.label(9.5)).tracking(1).foregroundStyle(Brand.amber).padding(.top, 6)
                ForEach(rows) { row($0) }
            }
        }.padding(.horizontal, 20).padding(.bottom, 10)
    }

    private func row(_ s: InterruptedSession) -> some View {
        Button { r.toggle(s.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: s.tick ? "checkmark.square.fill" : "square")
                    .font(.system(size: S(14))).foregroundStyle(s.tick ? Brand.amber : Brand.mute)
                Text(s.title).font(.system(size: S(13), weight: .semibold)).foregroundStyle(s.tick ? Brand.ink : Brand.mute).lineLimit(1)
                Text(s.tag).font(.system(size: S(10), weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill((s.why == .asked ? Brand.blue : Brand.claude).opacity(0.18)))
                    .foregroundStyle(s.why == .asked ? Brand.blue : Brand.claude)
                Spacer(minLength: 8)
                if s.ai { Image(systemName: "apple.intelligence").font(.system(size: S(10))).foregroundStyle(Brand.blue).help("Read on this Mac") }
                Text(s.detail).font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.mute).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(s.tick ? Brand.amber.opacity(0.25) : Brand.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(r.sailing)
    }
}

/// The harbour at dawn: one moored boat per stopped session, a lighthouse sweeping. Ticked boats raise their sail;
/// on Resume they sail out to sea, the others stay at the pier.
struct HarbourWake: View {
    let boats: [Bool]
    let sailing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var sailAt: Date?

    private static let cols = 150, rows = 46, sea = 36

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.09, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                draw(ctx, size, t: reduceMotion ? 30 : tl.date.timeIntervalSince(start),
                     go: sailAt.map { reduceMotion ? 5 : tl.date.timeIntervalSince($0) })
            }
        }
        .onChange(of: sailing) { _, on in sailAt = on ? Date() : nil }
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, t: Double, go: Double?) {
        let cols = Self.cols, sea = Self.sea
        let px = size.width / CGFloat(cols)
        func dot(_ x: Int, _ y: Int, _ c: Color, _ a: Double = 1) {
            guard x >= 0, x < cols, y >= 0, y < Self.rows + 4 else { return }
            ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px + 0.3, height: px + 0.3)), with: .color(c.opacity(a)))
        }
        func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Color, _ a: Double = 1) {
            ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: CGFloat(w) * px + 0.3, height: CGFloat(h) * px + 0.3)), with: .color(c.opacity(a)))
        }
        let phase = Int(t / 0.5)
        // dawn sky: night above, warming at the horizon (brighter once boats leave)
        let dawn = min(1, (go ?? 0) / 2.5)
        let bands: [Color] = [Color(hex: 0x0f1020), Color(hex: 0x15162a), Color(hex: 0x1f1b34), Color(hex: 0x30223c), Color(hex: 0x4a2a40), Color(hex: 0x6e3a40), Color(hex: 0x9a5640)]
        for (i, c) in bands.enumerated() {
            let y0 = sea * i / bands.count, y1 = sea * (i + 1) / bands.count
            rect(0, y0, cols, y1 - y0 + 1, c)
        }
        if dawn > 0 { rect(0, sea - 8, cols, 8, Brand.amber, 0.12 * dawn) }
        for (x, y) in [(10, 3), (28, 8), (47, 2), (63, 6), (82, 3), (101, 9), (118, 4), (136, 7), (144, 2)] {
            dot(x, y, Brand.cream, ((x + phase) % 3 == 0 ? 0.9 : 0.4) * (1 - dawn * 0.7))
        }
        // the sun peeking at dawn
        let sunY = sea - 1 - Int(dawn * 4)
        for y in -4...0 { for x in -6...6 where x * x + y * y * 3 <= 36 { dot(118 + x, sunY + y, Brand.amber, 0.25 + 0.5 * dawn) } }
        // sea + waves
        rect(0, sea, cols, Self.rows - sea + 4, Color(hex: 0x0d1020))
        for r in 0..<3 { for x in 0..<cols where (x + phase * (r + 1) + r * 3) % 7 < 4 { dot(x, sea + 2 + r * 3, r == 0 ? Brand.blue : Brand.line2, r == 0 ? 0.55 : 0.9) } }
        // lighthouse on the left with its sweeping beam
        let wood = Color(hex: 0x8a5a2b), wood2 = Color(hex: 0x5c3b1c), post = Color(hex: 0x4a2f16), grey = Color(hex: 0x5b606b)
        let lx = 4
        for y in 0..<18 { for i in 0..<4 { dot(lx + i, sea - 1 - y, (y / 3) % 2 == 1 ? Brand.cream : Brand.claude) } }
        for i in -1...4 { dot(lx + i, sea - 19, post) }
        rect(lx + 1, sea - 21, 2, 2, Brand.amber)
        let sweep = sin(t * 1.3)
        for k in 3..<46 { dot(lx + 2 + k, sea - 20 + Int(Double(k) * sweep * 0.25), Brand.amber, max(0, 0.36 - Double(k) * 0.007)) }
        // pier
        let shown = Array(boats.prefix(8))
        let slot = 15, pierX = 12, pierEnd = pierX + max(4, shown.count) * slot + 4
        for x in pierX..<pierEnd { dot(x, sea - 2, wood); dot(x, sea - 1, wood2) }
        for x in stride(from: pierX + 2, to: pierEnd, by: 7) { for y in sea..<(sea + 7) { dot(x, y, post) } }
        // boats
        let sails: [Color] = [Brand.claude, Brand.amber, Brand.green, Brand.blue, Brand.violet]
        for (i, ticked) in shown.enumerated() {
            let home = pierX + 2 + i * slot
            var bx = Double(home)
            if let go, ticked {
                let d = max(0, go - Double(i) * 0.25)
                bx += d * d * 9                                   // accelerating out to sea
            }
            let x = Int(bx.rounded()), bob = (phase + i) % 4 < 2 ? 0 : 1
            guard x < cols + 2 else { continue }
            let y = sea + 1 + bob
            // hull
            rect(x, y - 1, 13, 1, wood); rect(x + 1, y, 11, 1, wood2); rect(x + 2, y + 1, 9, 1, post)
            // mast
            rect(x + 6, y - 11, 1, 10, Brand.cream)
            if ticked {
                // sail up (a raised triangle), pennant flapping
                let c = sails[i % sails.count]
                for r in 0..<8 { rect(x + 7, y - 10 + r, min(r + 1, 6), 1, c) }
                dot(x + 7 + phase % 2, y - 12, c)
                if go != nil { for k in 1...3 { dot(x - k * 2, y + 1, Brand.cream, 0.5 - Double(k) * 0.12) } }   // wake
            } else {
                rect(x + 7, y - 3, 5, 2, grey)                    // sail furled
                dot(x + 2, y - 2, Brand.cream)                    // mooring line to the pier
            }
        }
        // celebration: little sparks over the sea once they are out
        if let go, go > 1.2 {
            for f in 0..<3 {
                let cx = 70 + f * 22, cy = 10 + (f % 2) * 6, ph = (Int(go * 10) + f * 7) % 24
                if ph > 3 { let r = min(ph - 3, 8); for a in 0..<8 { let an = Double(a) * .pi / 4
                    dot(cx + Int(cos(an) * Double(r)), cy + Int(sin(an) * Double(r)), [Brand.amber, Brand.green, Brand.claude][f], max(0, 1 - Double(r) / 9)) } }
            }
        }
    }
}
