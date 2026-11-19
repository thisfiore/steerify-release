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

/// Pixel avatar: initials on a gradient tile whose colours come from the project name.
struct PixelAvatar: View {
    let name: String
    var size: CGFloat = 44
    var body: some View {
        let h = abs(name.unicodeScalars.reduce(7) { ($0 &* 31) &+ Int($1.value) })
        let hue = Double(h % 360) / 360
        RoundedRectangle(cornerRadius: size * 0.24)
            .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.75, brightness: 0.85),
                                          Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.55)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Canvas { ctx, sz in
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
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).stroke(Color.white.opacity(0.15)))
            .frame(width: size, height: size)
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
        let road = b.roadmap
        let done = road.filter { $0.status == "done" }.count
        let frac = road.isEmpty ? 0 : Double(done) / Double(road.count)
        let choices = b.decisions.filter { !b.isDecided($0) && !b.isParked($0) }.count
        let toTest = b.ships.filter { [.toTest, .retest].contains(b.shipState($0)) }.count
        let reqs = b.requirements.filter { $0.status == "question" && b.isOpen($0) }.count
        let confirm = b.requirements.filter { $0.status != "question" && b.isOpen($0) }.count
        let working = road.contains { $0.status == "wip" }

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PixelAvatar(name: project.name, size: S(40))
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
                    Text(" of the roadmap · \(done)/\(road.count)").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
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
