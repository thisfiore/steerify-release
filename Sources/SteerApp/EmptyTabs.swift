import SwiftUI

// Empty tabs: each tab has its own pixel scene, says what it is for and shows what lands in it.

/// What an empty tab explains: what it is for, three sample items, how things get there.
struct TabGuide {
    let purpose: String
    let examples: [(text: String, tag: String)]
    let lands: String

    static func of(_ t: BoardTab) -> TabGuide {
        switch t {
        case .ready:
            return TabGuide(purpose: "Your answers that wait for a session, where you left off, and everything else that waits on you.",
                            examples: [("Choice answered: Export button top right", "START SESSION"),
                                       ("Refine: login page spacing on mobile", "START SESSION"),
                                       ("Chapter: Mac app · 7/12", "BACK TO IT")],
                            lands: "You pick a choice or send a test back: it lands here, ready for Claude.")
        case .test:
            return TabGuide(purpose: "Finished work for you to check: a picture, a direct link, what to look at. You say OK, Refine or Broken.",
                            examples: [("Export button on Orders", "NEW · V1"),
                                       ("Retouch: heal keeps the logo", "RE-TEST · V3"),
                                       ("Login page on mobile", "REFINE · YOUR NOTE")],
                            lands: "A session finishes a piece of work and delivers it here.")
        case .choice:
            return TabGuide(purpose: "Decisions only you can make. Each option shows its result; pick one, add a note, Claude builds it.",
                            examples: [("Where does the Export button go?", "3 OPTIONS · PROTOTYPE"),
                                       ("Pixel font for labels", "2 OPTIONS · PICTURES"),
                                       ("Weekly report: email or Slack?", "SUGGESTED: EMAIL")],
                            lands: "Claude adds one when it hits a question of taste, scope or order.")
        case .req:
            return TabGuide(purpose: "The rules the product must keep: numbers, limits, must-haves. Claude checks the code against them.",
                            examples: [("Opens in under 0.5 s", "AGREED"),
                                       ("Idle at ~0% CPU with 6 sessions", "BUILT · EVIDENCE"),
                                       ("Should guests see prices?", "QUESTION FOR YOU")],
                            lands: "They come with each chapter; open questions wait here for your answer.")
        case .road:
            return TabGuide(purpose: "Chapters of work and their key results. Each one moves todo → wip → review → done.",
                            examples: [("Mac app: board + sessions", "7/12 DONE"),
                                       ("In-app updates", "REVIEW"),
                                       ("Fixes & refinements", "YOUR REQUESTS")],
                            lands: "A feature request becomes a draft chapter; you approve it, Claude works through it.")
        case .task:
            return TabGuide(purpose: "Work Claude does for you with your tools, not code: once or on a schedule. Each run ends with a result you check.",
                            examples: [("Weekly sales report", "EVERY MON 08:00"),
                                       ("Tutorial from the SOP, 7 chapters", "ONCE"),
                                       ("Collect 40 competitor ads", "ONCE · 40 RECORDS")],
                            lands: "+ Task: describe the outcome you want; Claude sets it up and runs it.")
        case .release:
            return TabGuide(purpose: "Approved work on its way out: commit, push, deploy.", examples: [], lands: "Say OK on a To test item and it waits here.")
        }
    }
}

/// The pixel scene of an empty tab: the same night sea, a different thing on it per tab.
struct TabScene: View {
    let kind: BoardTab
    var height: CGFloat = 120

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.6)) { t in
            let phase = Int(t.date.timeIntervalSinceReferenceDate / 0.6) % 8
            Canvas { ctx, size in draw(ctx, size, phase) }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private static let colors: [Character: Color] = [
        "a": Brand.amber, "w": Brand.cream, "r": Brand.red, "g": Brand.line2, "b": Brand.blue,
        "n": Color(hex: 0x8a5a2b), "f": Color(hex: 0x3f8a55), "v": Brand.violet, "m": Brand.mute,
    ]

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ phase: Int) {
        let px: CGFloat = 4
        let cols = Int(size.width / px), rows = Int(size.height / px)
        func dot(_ x: Int, _ y: Int, _ c: Color) {
            guard x >= 0, y >= 0, x < cols, y < rows else { return }
            ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px - 0.4, height: px - 0.4)), with: .color(c))
        }
        func sprite(_ s: [String], _ x0: Int, _ y0: Int, _ alpha: Double = 1) {
            for (y, row) in s.enumerated() {
                for (x, ch) in row.enumerated() { if let c = Self.colors[ch] { dot(x0 + x, y0 + y, c.opacity(alpha)) } }
            }
        }
        let sea = rows - 9, mid = cols / 2
        // Sky: stars everywhere; a sun rising on Ready, the moon elsewhere.
        for (x, y) in [(6, 3), (19, 6), (33, 2), (48, 5), (61, 3), (75, 7), (88, 2), (97, 6), (110, 4), (122, 2)] where x < cols {
            dot(x, y, Brand.cream.opacity((x + phase) % 3 == 0 ? 0.9 : 0.3))
        }
        if kind == .ready {
            let sx = max(mid + 10, cols - 16)
            for y in 0..<6 { for x in 0..<13 where (x - 6) * (x - 6) + (y - 6) * (y - 6) <= 36 { dot(sx + x, sea - 6 + y, Brand.amber.opacity(0.75)) } }
        } else {
            let mx = cols - 14
            for y in 0..<6 { for x in 0..<6 where (x - 3) * (x - 3) + (y - 3) * (y - 3) <= 8 { dot(mx + x, 3 + y, Brand.cream.opacity(0.85)) } }
        }
        for r in 0..<3 {
            for x in 0..<cols where (x + phase * (r + 1) + r * 3) % 7 < 4 {
                dot(x, sea + r * 3, (r == 0 ? Brand.blue : Brand.line2).opacity(r == 0 ? 0.55 : 0.8))
            }
        }
        let bob = phase % 4 < 2 ? 0 : 1
        let boat = ["......w.......", "......ww......", "......www.....", "......wwww....", "......wwwww...", "......w.......",
                    "aaaaaaaaaaaaaa", ".aaaaaaaaaaaa.", "..aaaaaaaaaa.."]
        switch kind {
        case .ready, .release:
            // Sails up, a pennant on the mast: ready to go.
            let bx = mid - 7, by = sea - 9 + bob
            sprite(boat, bx, by)
            dot(bx + 6, by - 1, Brand.cream); dot(bx + 7, by - 1, Brand.amber); dot(bx + 8, by - 1 + (phase % 2), Brand.amber)
        case .test:
            // A lighthouse sweeping the sea: something to inspect, nothing found yet.
            let lh = ["....a....", "...aaa...", "..rrrrr..", "...www...", "...rrr...", "...www...", "...rrr...",
                      "..wwwww..", "..rrrrr..", "..wwwww..", ".ggggggg.", "ggggggggg"]
            let lx = mid - 4, ly = sea - lh.count + 2
            let dir = phase % 4 < 2 ? -1 : 1
            for i in stride(from: 2, to: 30, by: 2) {
                let spread = i / 5
                for s in -spread...spread where (i + s) % 2 == 0 {
                    dot(lx + 4 + dir * i, ly + 1 + s, Brand.amber.opacity(0.45 - Double(i) / 80))
                }
            }
            sprite(lh, lx, ly)
        case .choice:
            // A signpost at a fork: two ways, one blinks.
            let post = [".......n.......", ".aaaaaan.......", "aaaaaaan.......", ".aaaaaan.......", ".......n.......",
                        ".......nbbbbbb.", ".......nbbbbbbb", ".......nbbbbbb.", ".......n.......", ".......n.......",
                        "....fffffff....", "..ggggggggggg.."]
            let x0 = mid - 7, y0 = sea - post.count + 2
            sprite(Array(post.prefix(4)), x0, y0, phase % 2 == 0 ? 1 : 0.55)
            sprite(Array(post.dropFirst(4)), x0, y0 + 4)
        case .req:
            // A message in a bottle: the rules, floating by.
            let bottle = ["...bbbbbbbb.....", "..b........b....", ".b..wwwwww..bbbn", ".b..wwwwww..bbbn", "..b........b....", "...bbbbbbbb....."]
            let x0 = mid - 8 + (phase % 8) / 2, y0 = sea - 3 + bob
            sprite(bottle, x0, y0, 0.95)
        case .road:
            // A dotted route from a small boat to a flag on an island.
            let island = [".......naaaa...", ".......naaaaaa.", ".......naaaa...", ".......n.......", ".......n.......",
                          ".....fffff.....", "...fffffffff...", ".fffffffffffff.", "ggggggggggggggg"]
            let ix = mid + 6, iy = sea - island.count + 2
            var isl = island; if phase % 2 == 1 { isl[1] = ".......naaaaa.." }
            sprite(isl, ix, iy)
            let small = ["...w...", "...ww..", "...www.", "aaaaaaa", ".aaaaa."]
            let sx = mid - 26
            sprite(small, sx, sea - 4 + bob)
            for x in stride(from: sx + 9, to: ix, by: 2) { dot(x, sea - 2, Brand.cream.opacity((x / 2 + phase) % 4 == 0 ? 0.9 : 0.35)) }
        case .task:
            // Claude fishing for you: a rod, a line, a bobber, now and then a fish.
            let bx = mid - 10, by = sea - 9 + bob
            sprite(boat, bx, by)
            let tipX = bx + 22, tipY = by - 3
            for i in 0...8 { dot(bx + 13 + i, by + 5 - i, Color(hex: 0x8a5a2b)) }
            for y in (tipY + 1)..<(sea - 1) where y % 2 == 0 { dot(tipX, y, Brand.cream.opacity(0.4)) }
            dot(tipX, sea - 1 + (phase % 2), Brand.red)
            if phase == 5 || phase == 6 {
                let fish = ["..vv.", ".vvvv", "..vv."]
                sprite(fish, tipX + 4, sea - 4 - (phase == 5 ? 1 : 0))
            }
        }
    }
}

/// What an empty tab shows: its own scene, a wry line, what the tab is for with examples, and a way on.
struct EmptyBoard: View {
    @EnvironmentObject var model: AppModel
    let projectId: String
    let title: String
    let line: String
    var kind: BoardTab? = nil

    var body: some View {
        VStack(spacing: 12) {
            if let kind { TabScene(kind: kind).frame(maxWidth: 560) } else { PixelScene().frame(maxWidth: 520, maxHeight: 110) }
            Text(title).font(Brand.label(12)).tracking(1.2).foregroundStyle(Brand.cream)
            Text(line).font(.system(size: S(12.5))).italic().foregroundStyle(Brand.mute)
            if let kind {
                TabGuideCard(kind: kind).frame(maxWidth: 600).padding(.top, 6)
                actions(kind).padding(.top, 2)
            }
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func actions(_ kind: BoardTab) -> some View {
        HStack(spacing: 14) {
            if kind == .task {
                ActionButton(title: "+ Task", icon: "task", primary: true) { model.requestKindSeed = .task; model.requestOpen = true }
            }
            if kind != .ready {
                Button { Prefs.store.set(BoardTab.ready.rawValue, forKey: Prefs.boardTab) } label: {
                    HStack(spacing: 5) {
                        PixelIcon(name: "play", size: S(8))
                        Text("Where you left off and what waits on you: READY ⌘1").font(.system(size: S(11.5), weight: .semibold))
                    }
                }
                .buttonStyle(SteerButton()).foregroundStyle(Brand.amber)
            }
        }
    }
}

/// "What this tab is for": one line, three sample items drawn like the real ones (dimmed, dashed), how they land here.
struct TabGuideCard: View {
    let kind: BoardTab
    var body: some View {
        let g = TabGuide.of(kind)
        VStack(alignment: .leading, spacing: 9) {
            Text("WHAT THIS TAB IS FOR").font(Brand.label(9)).tracking(1).foregroundStyle(kind.color)
            Text(g.purpose).font(.system(size: S(13))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            if !g.examples.isEmpty {
                Text("FOR EXAMPLE").font(Brand.label(8.5)).tracking(1).foregroundStyle(Brand.mute).padding(.top, 4)
                ForEach(g.examples.indices, id: \.self) { i in
                    let e = g.examples[i]
                    HStack(spacing: 10) {
                        PixelIcon(name: kind.icon, size: S(10)).foregroundStyle(kind.color.opacity(0.8))
                        Text(e.text).font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(Brand.cream.opacity(0.85)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(e.tag).font(Brand.label(8.5)).tracking(0.5).foregroundStyle(kind.color.opacity(0.9))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(kind.color.opacity(0.12)))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.line2, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
            }
            HStack(alignment: .top, spacing: 6) {
                Text("→").font(.system(size: S(12), weight: .bold)).foregroundStyle(kind.color)
                Text(g.lands).font(.system(size: S(12))).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.panel2.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.line))
    }
}

/// READY, below your answers: where you left off (the chapters you were on) and everything else that waits on you,
/// grouped by kind, with the full titles.
struct LeftOffSection: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    @State private var all = false

    var body: some View {
        let answered = Set(model.groupedNudges(project.id).flatMap { $0.nudges.map(\.ref) } + model.releasable(project.id).map { "test:" + $0.id })
        let steps = model.nextSteps(project).filter { !answered.contains($0.ref) }
        let left = model.whereYouLeftOff(project, limit: 4)
        VStack(alignment: .leading, spacing: 14) {
            if !left.isEmpty {
                header("WHERE YOU LEFT OFF", "The chapters you were on: what happened last, the next step, one way back in.", Brand.amber)
                ResumeChapters(project: project, limit: 4, showHeader: false)
            }
            if !steps.isEmpty {
                header("ALSO WAITING ON YOU", "\(steps.count) thing\(steps.count == 1 ? "" : "s") only you can move, most pressing first.", Brand.cream)
                    .padding(.top, left.isEmpty ? 0 : 8)
                let shown = all ? steps : Array(steps.prefix(8))
                let cats = Dictionary(grouping: shown, by: { Self.category($0) })
                ForEach(Self.order.filter { cats[$0] != nil }, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            PixelIcon(name: Self.icon(c), size: S(9)).foregroundStyle(Brand.mute)
                            Text(c.uppercased() + " · \(cats[c]!.count)").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.mute)
                        }
                        ForEach(cats[c]!) { row($0) }
                    }
                }
                if steps.count > 8 {
                    Button(all ? "show less" : "+\(steps.count - 8) more") { all.toggle() }
                        .buttonStyle(.link).font(.system(size: S(11.5)))
                }
            }
            if left.isEmpty && steps.isEmpty {
                VStack(spacing: 10) {
                    Text("All quiet on deck. Start a fresh session and Claude will look for the next thing.")
                        .font(.system(size: S(12))).foregroundStyle(Brand.mute)
                    ClaudeButton(title: "Find the next thing with Claude", prominent: true) { model.newSession(.claude) }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func header(_ title: String, _ sub: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Brand.label(10)).tracking(1).foregroundStyle(c)
            Text(sub).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
        }
    }

    private func row(_ s: NextStep) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(s.urgent ? Brand.amber : Brand.line2).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).font(.system(size: S(13), weight: .semibold)).foregroundStyle(Brand.ink).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(s.reason).font(.system(size: S(11))).foregroundStyle(s.urgent ? Brand.amber : Brand.mute)
            }
            Spacer(minLength: 8)
            ActionButton(title: "Go", primary: s.urgent) {
                if s.ref.hasPrefix("session:") { model.jumpNext() } else { model.openCombo(projectId: project.id, ref: s.ref, startNew: false) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.line))
    }

    static let order = ["Sessions", "To test", "Choices", "Chapters", "Roadmap", "Questions", "Other"]
    static func category(_ s: NextStep) -> String {
        if s.ref.hasPrefix("session:") || s.reason.hasPrefix("session") { return "Sessions" }
        switch s.ref.split(separator: ":").first.map(String.init) ?? "" {
        case "test": return "To test"
        case "choice": return "Choices"
        case "track": return "Chapters"
        case "road": return "Roadmap"
        case "req": return "Questions"
        default: return "Other"
        }
    }
    static func icon(_ c: String) -> String {
        ["Sessions": "term", "To test": "test", "Choices": "choice", "Chapters": "road", "Roadmap": "road", "Questions": "req"][c] ?? "play"
    }
}
