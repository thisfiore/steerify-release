import SwiftUI

// "Next": a slim companion of the READY tab (choice next-companion, A). One 34 px line above every tab but Ready:
// on the left the one move that pushes the project forward (a moving pixel sprite + what it is), on the right quiet
// recap counts of the rest (to ship · to test · to build) and the move's one coloured button.
// Order of the move: Claude waits → ship approved → test → build answers → choices → draft chapter → resume.

enum NextKind {
    case waiting, ship, test, build, choice, draft, resume
    var sprite: NextSprite.Kind {
        switch self {
        case .waiting, .resume: return .spark
        case .ship: return .ship
        case .test: return .flask
        case .build, .choice, .draft: return .bricks
        }
    }
    var color: Color {
        switch self {
        case .waiting, .resume: return Brand.claude
        case .ship: return Brand.green
        case .test: return Brand.blue
        case .build, .choice, .draft: return Brand.amber
        }
    }
    /// Text on the coloured button.
    var ink: Color { self == .waiting || self == .resume ? .white : Color(hex: 0x0d0f12) }
}

struct NextPlanStep: Identifiable {
    let id: String
    let kind: NextKind
    let text: String
    let detail: String?
    let button: String
    let claude: Bool          // the button starts / opens Claude work (spark), otherwise it just shows you the item
    let action: () -> Void
}

/// The counts behind the recap (what waits, by kind).
struct NextRecap { var ship = 0, test = 0, build = 0, working = 0 }

extension AppModel {
    func nextRecap(_ p: Project) -> NextRecap {
        let b = board(for: p)
        return NextRecap(ship: releasable(p.id).count,
                         test: b.ships.filter { [.toTest, .retest].contains(b.shipState($0)) }.count,
                         build: groupedNudges(p.id).count,
                         working: sessions(of: p.id).filter { $0.running && $0.status != .waiting }.count)
    }

    /// The next steps for a project, grouped by kind, most urgent first (the strip shows the first one).
    func nextPlan(_ p: Project, openReady: @escaping () -> Void = {}) -> [NextPlanStep] {
        let b = board(for: p)
        var out: [NextPlanStep] = []
        func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? one : "\(n) \(many)" }

        let waiting = sessions(of: p.id).filter { $0.running && $0.status == .waiting }
        if let s = waiting.first {
            out.append(NextPlanStep(id: "waiting", kind: .waiting,
                                    text: waiting.count == 1 ? "Claude asks you in \(s.title)" : "Claude waits on you in \(waiting.count) sessions",
                                    detail: waiting.count == 1 ? nil : s.title, button: "Answer", claude: true) { [weak self] in self?.selectedSession[p.id] = s.id })
        }

        let rel = releasable(p.id)
        if !rel.isEmpty {
            out.append(NextPlanStep(id: "release", kind: .ship,
                                    text: "\(rel.count) approved to ship",
                                    detail: rel.prefix(2).map(\.title).joined(separator: ", ") + (rel.count > 2 ? " …" : ""),
                                    button: "Ship \(rel.count)", claude: false) { openReady() })
        }

        let toTest = b.ships.filter { [.toTest, .retest].contains(b.shipState($0)) }
            .sorted { ($0.updated ?? "") > ($1.updated ?? "") }
        if let t = toTest.first {
            out.append(NextPlanStep(id: "test", kind: .test, text: plural(toTest.count, "1 delivery", "deliveries") + " to test",
                                    detail: (toTest.count == 1 ? "" : "newest: ") + t.title,
                                    button: toTest.count == 1 ? "Test it" : "Test newest", claude: false) { [weak self] in
                self?.focusItem(projectId: p.id, ref: "test:" + t.id)
            })
        }

        let groups = groupedNudges(p.id)
        if let g = groups.first {
            out.append(NextPlanStep(id: "ready", kind: .build,
                                    text: groups.count == 1 ? "\(g.title) is answered" : "\(groups.count) answers ready to build",
                                    detail: groups.count == 1 ? "ready to build" : groups.prefix(2).map(\.title).joined(separator: " · "),
                                    button: groups.count == 1 ? "Start building" : "Open", claude: groups.count == 1) { [weak self] in
                if groups.count == 1 { self?.takeGroup(g) } else { openReady() }
            })
        }

        // Choices before the draft chapter: right after setup, your answers are what the chapter is drafted from.
        // "Did I get it right?" leads when it is still open.
        let open = b.decisions.filter { !b.isDecided($0) && !b.isParked($0) }
        if let d = open.first(where: { $0.id == "setup-understood" }) ?? open.first {
            out.append(NextPlanStep(id: "choices", kind: .choice, text: plural(open.count, "1 choice", "choices") + " to answer",
                                    detail: d.title, button: "Answer", claude: false) { [weak self] in self?.focusItem(projectId: p.id, ref: "choice:" + d.id) })
        }

        if let c = b.chapters.first(where: \.draft) {
            out.append(NextPlanStep(id: "draft", kind: .draft, text: "Approve the draft chapter", detail: c.name, button: "Open", claude: false) { [weak self] in
                self?.focusItem(projectId: p.id, ref: "track:" + BoardFiles.slug(c.name))
            })
        }

        if out.isEmpty, let c = whereYouLeftOff(p, limit: 1).first {
            let live = liveSession(for: "track:" + BoardFiles.slug(c.track), in: p)
            out.append(NextPlanStep(id: "resume", kind: .resume, text: "Resume “\(c.track)”", detail: c.next.map { "next: " + $0 },
                                    button: live == nil ? "Resume" : "Back to it", claude: true) { [weak self] in
                if let live { self?.selectedSession[p.id] = live.id } else { self?.resumeChapter(c, in: p) }
            })
        }
        return out
    }
}

struct NextStrip: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    var openReady: () -> Void = {}
    /// Opens a tab: the recap counts jump to where those items live (ship → Release, test → To test, build → Ready).
    var openTab: (BoardTab) -> Void = { _ in }

    var body: some View {
        let p = board.project
        let steps = model.nextPlan(p, openReady: openReady)
        let recap = model.nextRecap(p)
        Group {
            if let s = steps.first {
                line(s, recap)
            } else {
                VStack(spacing: 0) {
                    NudgeStrip(projectId: p.id, open: openReady)   // only its "Sent your … to …" line can show here
                    allClear(recap)
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 8)
    }

    private func line(_ s: NextPlanStep, _ r: NextRecap) -> some View {
        HStack(spacing: S(10)) {
            NextSprite(kind: s.kind.sprite, cell: S(2.2))
            HStack(spacing: 0) {
                Text(s.text).font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(Brand.ink)
                    .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                if let d = s.detail, !d.isEmpty {
                    Text(" · " + d).font(.system(size: S(12))).foregroundStyle(Brand.mute).lineLimit(1).truncationMode(.tail)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            recapChips(r, skip: s.kind)
            moveButton(s)
        }
        .padding(.leading, 10).padding(.trailing, 5)
        .frame(height: S(34))
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.line))
        .help("Next: the step that moves the project forward. The READY tab has the full list.")
    }

    /// Quiet counts with a moving pixel icon; the step already shown on the left is not repeated.
    private func recapChips(_ r: NextRecap, skip: NextKind) -> some View {
        let items: [(NextSprite.Kind, Int, String, Bool, BoardTab)] = [
            (.ship, r.ship, "to ship", skip != .ship, .release),
            (.flask, r.test, "to test", skip != .test, .test),
            (.bricks, r.build, "to build", skip != .build, .ready),
        ].filter { $0.1 > 0 && $0.3 }
        return HStack(spacing: S(3)) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                if i > 0 { Rectangle().fill(Brand.line2).frame(width: 1, height: S(14)) }
                RecapChip(sprite: it.0, count: it.1, label: it.2) { openTab(it.4) }
            }
            if !items.isEmpty { Rectangle().fill(Brand.line2).frame(width: 1, height: S(14)).padding(.leading, S(2)) }
        }
    }

    /// One recap count: a button that opens the tab where those items are (hover lights it up).
    private struct RecapChip: View {
        let sprite: NextSprite.Kind
        let count: Int
        let label: String
        let action: () -> Void
        @State private var hover = false
        var body: some View {
            Button(action: action) {
                HStack(spacing: S(5)) {
                    NextSprite(kind: sprite, cell: S(1.5))
                    Text("\(count)").font(.system(size: S(11), weight: .bold, design: .monospaced)).foregroundStyle(Brand.cream)
                    Text(label).font(.system(size: S(11), weight: .medium, design: .monospaced))
                        .foregroundStyle(hover ? Brand.ink : Brand.mute)
                }
                .padding(.horizontal, S(5)).frame(height: S(22))
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(hover ? 0.07 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).pointerStyle(.link)
            .onHover { hover = $0 }
            .fixedSize()
            .help("Open \(count) \(label)")
        }
    }

    private func moveButton(_ s: NextPlanStep) -> some View {
        Button(action: s.action) {
            HStack(spacing: 5) {
                if s.claude { ClaudeSpark(size: S(11), color: s.kind.ink) }
                else { PixelIcon(name: s.kind == .ship ? "boat" : "play", size: S(9)).foregroundStyle(s.kind.ink) }
                Text(s.button).font(.system(size: S(11.5), weight: .bold))
            }
            .foregroundStyle(s.kind.ink)
            .padding(.horizontal, 11).frame(height: S(24))
            .background(RoundedRectangle(cornerRadius: 5).fill(s.kind.color))
        }
        .buttonStyle(SteerButton())
        .fixedSize()
    }

    private func allClear(_ r: NextRecap) -> some View {
        HStack(spacing: S(10)) {
            NextSprite(kind: .flag, cell: S(2.2))
            Text(r.working > 0 ? "Nothing waits on you · \(r.working) \(r.working == 1 ? "session" : "sessions") working" : "Nothing waits on you")
                .font(.system(size: S(12))).foregroundStyle(Brand.mute).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: S(30))
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.line.opacity(0.7)))
    }
}

/// Tiny animated pixel sprites for the Next line (10 × 9 cells): a ship bobbing, a flask bubbling, Claude's spark,
/// bricks stacking, a flag waving. Still when Reduce Motion is on or the window is in the background.
struct NextSprite: View {
    enum Kind { case ship, flask, spark, bricks, flag }
    let kind: Kind
    var cell: CGFloat = 2.2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var active

    private static let palette: [Character: Color] = [
        "w": Brand.cream, "s": Brand.amber, "h": Color(hex: 0xb3673f), "b": Brand.blue, "c": Color(hex: 0xc9d4ec),
        "g": Brand.green, "o": Color(hex: 0xeafff1), "k": Brand.claude, "r": Brand.amber, "R": Color(hex: 0xd9861a),
        "f": Brand.green, "p": Brand.mute,
    ]
    private static let start = Date()

    static let frames: [Kind: (ms: Double, frames: [[String]])] = {
        let hull = ["....w.....", "....ws....", "....wss...", "....wsss..", "....wssss.", "....w.....", "hhhhhhhhh.", ".hhhhhhh.."]
        let ship = [[".........."] + hull + ["b..bb..bb."], hull + ["..........", ".bb..bb..b"]]
        let base = ["...cccc...", "....cc....", "....cc....", "...c..c...", "..c....c..", ".cggggggc.", ".cggggggc.", ".cggggggc.", "..cccccc.."]
        let bub: [(Int, Int)] = [(5, 6), (4, 5), (5, 3), (4, 1)]
        let flask: [[String]] = (0..<4).map { i in
            base.enumerated().map { y, row in
                var a = Array(row)
                for (x, by) in [bub[i], bub[(i + 2) % 4]] where by == y { a[x] = "o" }
                return String(a)
            }
        }
        let empty = Array(repeating: "..........", count: 9)
        let spark = [
            ["..........", "..........", "....k.....", "...kkk....", "....k.....", "..........", "..........", "..........", ".........."],
            ["....k.....", "....k.....", "....k.....", "kkkkkkkkk.", "....k.....", "....k.....", "....k.....", "..........", ".........."],
            ["k...k...k.", ".k..k..k..", "..k.k.k...", "kkkkkkkkk.", "..k.k.k...", ".k..k..k..", "k...k...k.", "..........", ".........."],
        ]
        let brick = ["..rrrRrrr.", "..rRrrrRr.", ".rrrRrrrR.", ".rRrrrRrr.", "rrrRrrrRrr"]
        let bricks: [[String]] = [2, 3, 4, 5, 5, 5].map { n in
            var rows = empty
            for i in 0..<n { rows[8 - i] = brick[4 - i] }
            return rows
        }
        let pole = ["p.........", "p.........", "p.........", "p.........", "p.........", "ppp......."]
        let flag = [["pfffff....", "pffffff...", "pfffff...."] + pole, ["pffff.....", "pfffffff..", "pffff....."] + pole]
        return [.ship: (0.5, ship), .flask: (0.26, flask), .spark: (0.3, spark), .bricks: (0.33, bricks), .flag: (0.6, flag)]
    }()

    var body: some View {
        let still = reduceMotion || active == .inactive
        let spec = Self.frames[kind]!
        TimelineView(.animation(minimumInterval: spec.ms, paused: still)) { tl in
            let n = still ? 0 : Int(tl.date.timeIntervalSince(Self.start) / spec.ms) % spec.frames.count
            Canvas { ctx, _ in
                for (y, row) in spec.frames[n].enumerated() {
                    for (x, ch) in row.enumerated() where ch != "." {
                        ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.3, height: cell + 0.3)),
                                 with: .color(Self.palette[ch] ?? Brand.mute))
                    }
                }
            }
        }
        .frame(width: 10 * cell, height: 9 * cell)
        .accessibilityHidden(true)
    }
}
