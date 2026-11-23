import SwiftUI

// MARK: - Who is steering (chapter "Who is steering: a level for non-technical people", choice skill-level-setup)
//
// How technical the person at the wheel is. Asked once on first launch, changeable in Settings → You.
// The choice's note: presets only, a direct question ("How technical are you?"), pixel art on top, a clear
// explanation per level: what you will see, and how Steerify says the same thing in your words.

enum Level: String, CaseIterable, Identifiable {
    case explorer, tinkerer, builder
    var id: String { rawValue }

    static let key = "steererLevel"
    /// The Mac's level; nil until the person has answered (the first-launch sheet shows then).
    static var chosen: Level? { Prefs.store.string(forKey: key).flatMap(Level.init(rawValue:)) }
    static var current: Level { chosen ?? .builder }

    var name: String { ["explorer": "Explorer", "tinkerer": "Tinkerer", "builder": "Builder"][rawValue]! }
    var who: String {
        ["explorer": "I have an idea. Code is not my thing.",
         "tinkerer": "I use apps and spreadsheets. I can follow along.",
         "builder": "I read code, use git and ship myself."][rawValue]!
    }
    /// What changes, in one or two plain sentences.
    var explain: String {
        ["explorer": "Claude takes the technical decisions for you, following the AI Traction recipes, and only asks about what you will see, pay or do.",
         "tinkerer": "Claude names the tools it uses and says in a line what each one does and costs. You decide the big ones.",
         "builder": "Everything as it is today: the terminal, branches, pull requests and every technical choice."][rawValue]!
    }
    var sees: [String] {
        switch self {
        case .explorer: return ["Just the board, terminal hidden", "A Publish button, no git", "Choices about results, never tech"]
        case .tinkerer: return ["Terminal folded, open it any time", "Release in a few clear steps", "Tools named, with what they cost"]
        case .builder:  return ["Full terminal next to the board", "Branches, worktrees, pull requests", "Every technical choice is yours"]
        }
    }
    /// The same news ("your change is out"), said at this level.
    var says: String {
        ["explorer": "Your new menu page is live. Take a look!",
         "tinkerer": "The menu page is published on your website (Vercel).",
         "builder": "Merged steer/menu into main, deployed, health check 200."][rawValue]!
    }
    /// The same button, named at this level.
    var releaseWord: String { ["explorer": "Publish", "tinkerer": "Release", "builder": "Release · deploy"][rawValue]! }
    var color: Color { [.explorer: Brand.green, .tinkerer: Brand.violet, .builder: Brand.claude][self]! }
}

// MARK: - Pixel characters (24 × 24: rectangles of colour, as in the prototype)

enum LevelArt {
    static let palette: [Character: Color] = [
        "k": Color(hex: 0x16171c), "s": Color(hex: 0xf2c79a), "h": Color(hex: 0x5a3b22), "a": Brand.amber, "g": Brand.green,
        "b": Brand.blue, "c": Brand.cream, "r": Brand.red, "m": Color(hex: 0x7b7f8a), "v": Brand.violet, "o": Brand.claude]
    typealias R = (Int, Int, Int, Int, Character)
    static let art: [Level: [R]] = [
        // explorer: green hat, backpack, a compass in hand
        .explorer: [(8,3,8,3,"g"),(6,5,12,2,"g"),(8,7,8,6,"s"),(9,9,2,2,"k"),(13,9,2,2,"k"),(10,12,4,1,"o"),(7,13,10,7,"b"),
                    (4,14,3,6,"h"),(17,13,4,4,"a"),(18,14,2,2,"r"),(8,20,3,3,"h"),(13,20,3,3,"h")],
        // tinkerer: goggles, overalls, a spanner
        .tinkerer: [(8,3,8,4,"v"),(8,7,8,6,"s"),(8,8,8,3,"m"),(9,9,2,1,"b"),(13,9,2,1,"b"),(10,12,4,1,"k"),(7,13,10,7,"a"),
                    (18,10,2,8,"m"),(17,9,4,2,"m"),(4,15,3,3,"s"),(8,20,3,3,"k"),(13,20,3,3,"k")],
        // builder: cap, grey hoodie, a laptop
        .builder:  [(7,3,10,3,"o"),(7,6,12,1,"o"),(8,7,8,6,"s"),(9,9,2,2,"k"),(13,9,2,2,"k"),(10,12,4,1,"k"),(7,13,10,7,"m"),
                    (3,15,10,6,"c"),(4,16,8,4,"b"),(2,21,12,1,"m"),(13,20,3,3,"k")]]

    static func draw(_ level: Level, in ctx: GraphicsContext, x: CGFloat, y: CGFloat, px: CGFloat, flip: Bool = false) {
        for (l, t, w, h, c) in art[level] ?? [] {
            let lx = flip ? CGFloat(24 - l - w) : CGFloat(l)
            ctx.fill(Path(CGRect(x: x + lx * px, y: y + CGFloat(t) * px, width: CGFloat(w) * px, height: CGFloat(h) * px)),
                     with: .color(palette[c] ?? .gray))
        }
    }
}

struct LevelCharacter: View {
    let level: Level
    var size: CGFloat = 72
    var body: some View {
        Canvas { ctx, sz in LevelArt.draw(level, in: ctx, x: 0, y: 0, px: sz.width / 24) }
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// The header: a night harbour, the three characters on the quay, the picked one waving (bobs) under a lantern.
struct LevelBanner: View {
    var picked: Level?
    var height: CGFloat = 110
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { t in
            let phase = still ? 0 : Int(t.date.timeIntervalSinceReferenceDate / 0.5) % 8
            Canvas { ctx, size in
                let px: CGFloat = 3
                let cols = Int(size.width / px), rows = Int(size.height / px)
                func dot(_ x: Int, _ y: Int, _ c: Color) {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px - 0.3, height: px - 0.3)), with: .color(c))
                }
                // sky: stars that twinkle, a moon
                for i in 0..<28 {
                    let x = (i * 37 + 11) % max(cols, 1), y = (i * 13 + 3) % max(rows - 16, 1)
                    dot(x, y, Brand.cream.opacity((i + phase) % 4 == 0 ? 0.9 : 0.3))
                }
                let mx = cols - 22
                for y in 0..<7 { for x in 0..<7 where (x - 3) * (x - 3) + (y - 3) * (y - 3) <= 9 { dot(mx + x, 3 + y, Brand.cream.opacity(0.85)) } }
                // sea, moving
                let sea = rows - 6
                for r in 0..<2 { for x in 0..<cols where (x + phase * (r + 1) + r * 3) % 7 < 4 { dot(x, sea + r * 3, (r == 0 ? Brand.blue : Brand.line2).opacity(0.6)) } }
                // quay: planks across the middle
                let q0 = cols / 2 - 60, q1 = cols / 2 + 60, top = sea - 2
                for x in max(q0, 0)..<min(q1, cols) { dot(x, top, Color(hex: 0x8a5a2b)); dot(x, top + 1, Color(hex: 0x5c3b1c)) }
                // the three characters on the quay; the picked one hops
                let gap: CGFloat = 40 * px
                for (i, l) in Level.allCases.enumerated() {
                    let cx = size.width / 2 + CGFloat(i - 1) * gap - 12 * px
                    let hop: CGFloat = (l == picked && phase % 2 == 0) ? -px * 2 : 0
                    LevelArt.draw(l, in: ctx, x: cx, y: CGFloat(top) * px - 23 * px + hop, px: px)
                    if l == picked {   // a lantern glow above the picked one
                        let g = Int((cx + 12 * px) / px)
                        dot(g, top - 30, Brand.amber); dot(g - 1, top - 29, Brand.amber.opacity(0.6)); dot(g + 1, top - 29, Brand.amber.opacity(0.6))
                    }
                }
            }
        }
        .frame(height: height)
        .background(LinearGradient(colors: [Color(hex: 0x0b1020), Brand.bg], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

// MARK: - The picker (first-launch sheet and Settings → You)

struct LevelPicker: View {
    /// true inside Settings: no title block of its own, saves on click.
    var inSettings = false
    var onDone: (() -> Void)? = nil
    var onLater: (() -> Void)? = nil
    /// A first answer starts in the middle; Settings shows the saved one.
    @State private var pick: Level = Level.chosen ?? .tinkerer

    var body: some View {
        VStack(alignment: .leading, spacing: S(16)) {
            LevelBanner(picked: pick, height: inSettings ? 90 : 120)
            if !inSettings {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HOW TECHNICAL ARE YOU?").font(Brand.label(16)).tracking(1.4).foregroundStyle(Brand.cream)
                    Text("Steerify changes its screens and its words to fit you. Claude talks to you the same way. You can change it any time in Settings.")
                        .font(.system(size: S(12.5))).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: S(12)) {
                ForEach(Level.allCases) { l in card(l) }
            }
            .fixedSize(horizontal: false, vertical: true)   // cards as tall as the tallest one, no taller
            if !inSettings {
                HStack {
                    Text("Started from an AI Traction recipe? Explorer fits best.").font(.system(size: S(11))).foregroundStyle(Brand.mute)
                    Spacer()
                    if let onLater {
                        Button("Later", action: onLater).buttonStyle(.plain).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                            .keyboardShortcut(.cancelAction).padding(.trailing, 6)
                    }
                    ActionButton(title: "I'm \(pick.article) \(pick.name)", icon: "ship", primary: true) { save(); onDone?() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func save() { Prefs.store.set(pick.rawValue, forKey: Level.key) }

    private func card(_ l: Level) -> some View {
        let on = pick == l
        return Button { pick = l; if inSettings { save() } } label: {
            VStack(alignment: .leading, spacing: S(10)) {
                HStack(spacing: S(10)) {
                    LevelCharacter(level: l, size: S(inSettings ? 44 : 60))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(l.name.uppercased()).font(Brand.label(12)).tracking(1).foregroundStyle(on ? l.color : Brand.cream)
                        Text(l.who).font(.system(size: S(11.5))).foregroundStyle(Brand.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(l.explain).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
                section("WHAT YOU'LL SEE") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(l.sees, id: \.self) { s in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Rectangle().fill(l.color).frame(width: 5, height: 5)
                                Text(s).font(.system(size: S(11.5))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                section("HOW WE SAY IT") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("“\(l.says)”").font(.system(size: S(11.5))).italic().foregroundStyle(Brand.cream)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text("The button").font(.system(size: S(10.5))).foregroundStyle(Brand.mute).fixedSize()
                            Text(l.releaseWord).font(.system(size: S(10.5), weight: .semibold)).foregroundStyle(Color(hex: 0x1a1200)).lineLimit(1).fixedSize()
                                .padding(.horizontal, 7).padding(.vertical, 2).background(RoundedRectangle(cornerRadius: 4).fill(l.color))
                        }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Brand.bg))
                }
                Spacer(minLength: 0)
            }
            .padding(S(12))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Brand.panel2 : Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? l.color : Brand.line, lineWidth: on ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(l.name): \(l.who)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Brand.label(8)).tracking(1).foregroundStyle(Brand.mute)
            c()
        }
    }
}

extension Level { var article: String { self == .explorer ? "an" : "a" } }

/// First launch: the picker on a scrim, until the person answers (or presses Later: asked again next launch).
struct LevelSheet: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            LevelPicker(onDone: { model.levelOpen = false }, onLater: { model.levelOpen = false })
            .padding(S(22))
            .frame(width: S(900))
            .background(RoundedRectangle(cornerRadius: 16).fill(Brand.bg))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.line2))
        }
    }
}
