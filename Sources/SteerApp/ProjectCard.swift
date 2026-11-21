import SwiftUI

/// 5×7 pixel font (capitals and digits) for project avatars.
enum PixelFont {
    static let glyphs: [Character: [String]] = [
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".####", "#....", "#....", "#....", "#....", "#....", ".####"],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".####", "#....", "#....", "#.###", "#...#", "#...#", ".###."],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
        "J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    ]
    /// Two initials: "Acme Corp" → AC, "Blink" → BL, "Steerify" → ST.
    static func initials(_ name: String) -> String {
        let words = name.uppercased().split { !$0.isLetter }
        if words.count >= 2 { return String([words[0].first!, words[1].first!]) }
        return String(words.first?.prefix(2) ?? "?")
    }
}

/// Pixel avatar: the project's favicon pixelated on a tile in its brand colours (ProjectIcon.swift), or its
/// initials on a gradient whose colours come from the project name. Pixels snap to whole screen pixels, so
/// it stays sharp at 20 pt.
struct PixelAvatar: View {
    let name: String
    var size: CGFloat = 44
    /// The project, to show its favicon. nil = initials only.
    var projectId: String? = nil
    /// Shown instead of the project's own look (the Projects window's preview).
    var look: ProjectIconLook? = nil
    @ObservedObject private var icons = ProjectIcons.shared
    @Environment(\.displayScale) private var scale

    var body: some View {
        let l = look ?? icons.look(projectId)
        let h = abs(name.unicodeScalars.reduce(7) { ($0 &* 31) &+ Int($1.value) })
        let hue = Double(h % 360) / 360
        let colors = l?.colors.map { [$0.0.color, $0.1.color] }
            ?? [Color(hue: hue, saturation: 0.75, brightness: 0.85),
                Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.55)]
        let grid = size > 32 ? (l?.large ?? l?.small) : (l?.small ?? l?.large)
        RoundedRectangle(cornerRadius: size * 0.24)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Canvas { ctx, sz in
                    if let grid { drawGrid(grid, ctx, sz) } else { drawInitials(ctx, sz) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).stroke(Color.white.opacity(0.15)))
            .frame(width: size, height: size)
    }

    /// One whole number of screen pixels per cell, centred.
    private func drawGrid(_ g: PixelGrid, _ ctx: GraphicsContext, _ sz: CGSize) {
        let s = max(1, scale)
        // Whole screen pixels per cell, as big as fits in ~80% of the tile.
        var px = (sz.width * 0.8 / CGFloat(g.n) * s).rounded()
        if px * CGFloat(g.n) > sz.width * 0.86 * s { px -= 1 }
        let cell = max(1, px) / s
        let w = cell * CGFloat(g.n)
        let ox = (floor((sz.width - w) / 2 * s)) / s, oy = (floor((sz.height - w) / 2 * s)) / s
        let shadow = max(1 / s, floor(cell * 0.3 * s) / s)
        for (i, p) in g.px.enumerated() {
            guard let p else { continue }
            let r = CGRect(x: ox + CGFloat(i % g.n) * cell, y: oy + CGFloat(i / g.n) * cell, width: cell, height: cell)
            ctx.fill(Path(r.offsetBy(dx: shadow, dy: shadow)), with: .color(.black.opacity(0.22)))
        }
        for (i, p) in g.px.enumerated() {
            guard let p else { continue }
            ctx.fill(Path(CGRect(x: ox + CGFloat(i % g.n) * cell, y: oy + CGFloat(i / g.n) * cell, width: cell, height: cell)), with: .color(p.color))
        }
    }

    private func drawInitials(_ ctx: GraphicsContext, _ sz: CGSize) {
        let letters = Array(PixelFont.initials(name))
        let cols = letters.count * 5 + (letters.count - 1)
        let cell = floor(sz.width * 0.68 / CGFloat(cols))
        let ox = (sz.width - CGFloat(cols) * cell) / 2, oy = (sz.height - 7 * cell) / 2
        for (i, ch) in letters.enumerated() {
            for (y, row) in (PixelFont.glyphs[ch] ?? []).enumerated() {
                for (x, c) in row.enumerated() where c == "#" {
                    let r = CGRect(x: ox + CGFloat(i * 6 + x) * cell, y: oy + CGFloat(y) * cell, width: cell, height: cell)
                    ctx.fill(Path(r.offsetBy(dx: cell * 0.35, dy: cell * 0.35)), with: .color(.black.opacity(0.25)))   // drop shadow
                    ctx.fill(Path(r), with: .color(.white))
                }
            }
        }
    }
}

/// Chunky segmented progress bar; the next block pulses amber while work is in progress.
struct PixelProgress: View {
    let fraction: Double
    var blocks = 20
    var working = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { t in
            let on = Int((fraction * Double(blocks)).rounded(.down))
            let pulse = !reduceMotion && Int(t.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
            HStack(spacing: 2) {
                ForEach(0..<blocks, id: \.self) { i in
                    Rectangle()
                        .fill(i < on ? Brand.green : (i == on && working ? Brand.amber.opacity(pulse ? 1 : 0.35) : Brand.line2))
                        .frame(height: 9)
                }
            }
        }
    }
}

/// The project at a glance, at the top of the sidebar.
struct ProjectCard: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    @AppStorage(Prefs.boardTab, store: Prefs.store) private var tab: BoardTab = .test
    @State private var more = false

    var body: some View {
        let b = model.board(for: project)
        // Core key results only: tests, tutorials, enhancements and later ideas never make a project look behind.
        let road = b.roadmap.filter(\.isCore)
        let done = road.filter { $0.status == "done" }.count
        let frac = road.isEmpty ? 0 : Double(done) / Double(road.count)
        let choices = b.decisions.filter { !b.isDecided($0) && !b.isParked($0) }.count
        let toTest = b.ships.filter { [.toTest, .retest].contains(b.shipState($0)) }.count
        let reqs = b.requirements.filter { $0.status == "question" && b.isOpen($0) }.count
        let confirm = b.requirements.filter { $0.status != "question" && b.isOpen($0) }.count
        let working = road.contains { $0.status == "wip" }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PixelAvatar(name: project.name, size: S(40), projectId: project.id)
                Text(project.name).font(.system(size: S(16), weight: .bold)).foregroundStyle(.white).lineLimit(2)
            }
            if !b.goal.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.goal).font(.system(size: S(11.5))).foregroundStyle(Brand.ink.opacity(0.75)).lineLimit(more ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    if b.goal.count > 130 {
                        Button(more ? "less" : "more") { more.toggle() }.buttonStyle(.link).pointerStyle(.link).font(.system(size: S(10.5)))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                PixelProgress(fraction: frac, working: working)
                HStack(spacing: 0) {
                    Text("\(Int(frac * 100))%").font(.system(size: S(12), weight: .bold).monospacedDigit()).foregroundStyle(Brand.green)
                    Text(" of the core roadmap · \(done)/\(road.count)").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                stat("test", toTest, "to test", .test)
                stat("choice", choices, choices == 1 ? "choice" : "choices", .choice)
                stat("req", reqs, reqs == 1 ? "question to decide" : "questions to decide", .req)
                if confirm > 0 { stat("req", confirm, "proposals to confirm", .req).opacity(0.7) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.line))
    }

    private func stat(_ icon: String, _ n: Int, _ label: String, _ t: BoardTab) -> some View {
        Button { tab = t } label: {
            HStack(spacing: 7) {
                PixelIcon(name: icon, size: S(10)).foregroundStyle(n > 0 ? Brand.amber : Brand.mute)
                Text("\(n)").font(.system(size: S(11.5), weight: .semibold).monospacedDigit()).foregroundStyle(n > 0 ? Brand.ink : Brand.mute)
                Text(label).font(.system(size: S(11))).foregroundStyle(Brand.mute)
                Spacer()
            }.contentShape(Rectangle())
        }.buttonStyle(SteerButton())
    }
}
