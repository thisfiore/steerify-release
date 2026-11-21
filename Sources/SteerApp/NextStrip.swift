import SwiftUI

// "Next" strip (choice first-run-next, A): on top of the board, at most 2 things to do now, each with one button.
// Built for the first visit after setup (answer the setup choices, approve chapter 1) and kept afterwards: it groups
// what waits on you (a session's question, answers ready to build, items to test, a draft chapter, open choices)
// and, when nothing does, the chapter to resume. Nothing waiting → no strip.

struct NextPlanStep: Identifiable {
    let id: String
    let text: String
    let detail: String?
    let button: String
    let claude: Bool          // the button starts / opens Claude work (spark), otherwise it just shows you the item
    let action: () -> Void
}

extension AppModel {
    /// The next 1–2 steps for a project, grouped by kind, most urgent first.
    func nextPlan(_ p: Project, openReady: @escaping () -> Void = {}) -> [NextPlanStep] {
        let b = board(for: p)
        var out: [NextPlanStep] = []
        func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? one : "\(n) \(many)" }

        let waiting = sessions(of: p.id).filter { $0.running && $0.status == .waiting }
        if let s = waiting.first {
            out.append(NextPlanStep(id: "waiting", text: waiting.count == 1 ? "Claude waits on your answer" : "Claude waits on you in \(waiting.count) sessions",
                                    detail: s.title, button: "Open", claude: true) { [weak self] in self?.selectedSession[p.id] = s.id })
        }

        let rel = releasable(p.id)
        if let r = rel.first {
            out.append(NextPlanStep(id: "release", text: rel.count == 1 ? "An approved change is ready to release" : "\(rel.count) approved changes ready to release",
                                    detail: rel.count == 1 ? r.title : "one release, or pick what goes in", button: "Open", claude: false) { openReady() })
        }

        let groups = groupedNudges(p.id)
        if let g = groups.first {
            out.append(NextPlanStep(id: "ready", text: groups.count == 1 ? "Your answers are ready to build" : "\(groups.count) answers ready to build",
                                    detail: groups.count == 1 ? g.title : groups.prefix(2).map(\.title).joined(separator: " · "),
                                    button: groups.count == 1 ? "Start" : "Open", claude: groups.count == 1) { [weak self] in
                if groups.count == 1 { self?.takeGroup(g) } else { openReady() }
            })
        }

        let toTest = b.ships.filter { [.toTest, .retest].contains(b.shipState($0)) }
            .sorted { ($0.updated ?? "") > ($1.updated ?? "") }
        if let t = toTest.first {
            out.append(NextPlanStep(id: "test", text: "Test " + plural(toTest.count, "what Claude delivered", "deliveries"),
                                    detail: t.title, button: "Test", claude: false) { [weak self] in self?.focusItem(projectId: p.id, ref: "test:" + t.id) })
        }

        // Choices before the draft chapter: right after setup, your answers are what the chapter is drafted from.
        // "Did I get it right?" leads when it is still open.
        let open = b.decisions.filter { !b.isDecided($0) && !b.isParked($0) }
        if let d = open.first(where: { $0.id == "setup-understood" }) ?? open.first {
            out.append(NextPlanStep(id: "choices", text: "Answer " + plural(open.count, "a choice", "choices") + ": Claude builds from your pick",
                                    detail: d.title, button: "Answer", claude: false) { [weak self] in self?.focusItem(projectId: p.id, ref: "choice:" + d.id) })
        }

        if let c = b.chapters.first(where: \.draft) {
            out.append(NextPlanStep(id: "draft", text: "Approve the draft chapter", detail: c.name, button: "Open", claude: false) { [weak self] in
                self?.focusItem(projectId: p.id, ref: "track:" + BoardFiles.slug(c.name))
            })
        }

        if out.isEmpty, let c = whereYouLeftOff(p, limit: 1).first {
            let live = liveSession(for: "track:" + BoardFiles.slug(c.track), in: p)
            out.append(NextPlanStep(id: "resume", text: "Resume “\(c.track)”", detail: c.next.map { "Next: " + $0 },
                                    button: live == nil ? "Resume" : "Back to it", claude: true) { [weak self] in
                if let live { self?.selectedSession[p.id] = live.id } else { self?.resumeChapter(c, in: p) }
            })
        }
        return Array(out.prefix(2))
    }
}

struct NextStrip: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    var openReady: () -> Void = {}

    var body: some View {
        let steps = model.nextPlan(board.project, openReady: openReady)
        if steps.isEmpty {
            NudgeStrip(projectId: board.project.id, open: openReady)   // only its "Sent your … to …" line can show here
        } else {
            VStack(alignment: .leading, spacing: S(8)) {
                Text("NEXT").font(Brand.label(9)).tracking(0.9).foregroundStyle(Brand.claude)
                ForEach(Array(steps.enumerated()), id: \.element.id) { i, s in row(i + 1, s) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.claude.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.claude.opacity(0.45)))
            .padding(.horizontal, 12).padding(.top, 10)
        }
    }

    private func row(_ n: Int, _ s: NextPlanStep) -> some View {
        HStack(spacing: S(10)) {
            Text("\(n)").font(.system(size: S(12), weight: .bold, design: .monospaced)).foregroundStyle(Brand.claude).frame(width: S(14))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.text).font(.system(size: S(13), weight: .semibold)).foregroundStyle(Brand.ink).lineLimit(1)
                if let d = s.detail { Text(d).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(1).truncationMode(.tail) }
            }
            Spacer(minLength: 8)
            if s.claude {
                ClaudeButton(title: s.button, prominent: n == 1, action: s.action)
            } else {
                ActionButton(title: s.button, icon: "play", primary: n == 1, action: s.action)
            }
        }
    }
}
