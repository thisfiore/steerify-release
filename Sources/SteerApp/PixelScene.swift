import SwiftUI

/// Empty tabs: a small pixel boat on a calm sea (waves move gently), then the next steps if there are any.
struct PixelScene: View {
    /// true: an empty wooden pier on the left with a lantern (the "no projects yet" harbour).
    var dock = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.6)) { t in
            let phase = Int(t.date.timeIntervalSinceReferenceDate / 0.6) % 8
            Canvas { ctx, size in
                let px: CGFloat = 4
                let cols = Int(size.width / px), rows = Int(size.height / px)
                func dot(_ x: Int, _ y: Int, _ c: Color) {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px - 0.4, height: px - 0.4)), with: .color(c))
                }
                // stars + moon
                for (x, y) in [(6, 3), (19, 6), (33, 2), (48, 5), (61, 3), (75, 7), (88, 2), (97, 6)] where x < cols {
                    dot(x, y, Brand.cream.opacity((x + phase) % 3 == 0 ? 0.9 : 0.35))
                }
                let mx = cols - 14
                for y in 0..<6 { for x in 0..<6 where (x - 3) * (x - 3) + (y - 3) * (y - 3) <= 8 { dot(mx + x, 3 + y, Brand.cream.opacity(0.85)) } }
                // sea: three wave rows, shifting
                let sea = rows - 9
                for r in 0..<3 {
                    for x in 0..<cols where (x + phase * (r + 1) + r * 3) % 7 < 4 {
                        dot(x, sea + r * 3, (r == 0 ? Brand.blue : Brand.line2).opacity(r == 0 ? 0.55 : 0.8))
                    }
                }
                // pier: planks on posts, a lantern at its end (glows on the beat)
                if dock {
                    let px0 = max(cols / 2 - 34, 2), len = 18, top = sea - 2
                    for x in px0..<(px0 + len) { dot(x, top, Color(hex: 0x8a5a2b)); dot(x, top + 1, Color(hex: 0x5c3b1c)) }
                    for x in stride(from: px0 + 1, to: px0 + len, by: 5) { for y in (top + 2)...(top + 8) { dot(x, y, Color(hex: 0x4a2f16)) } }
                    let lx = px0 + len - 2
                    for y in (top - 6)..<top { dot(lx, y, Color(hex: 0x6b4a2a)) }
                    dot(lx - 1, top - 8, Brand.amber.opacity(phase % 2 == 0 ? 1 : 0.6)); dot(lx, top - 8, Brand.amber); dot(lx + 1, top - 8, Brand.amber.opacity(phase % 2 == 0 ? 1 : 0.6))
                    dot(lx, top - 9, Brand.amber.opacity(0.8)); dot(lx, top - 7, Brand.amber.opacity(0.8))
                    // the rope from the post to the boat, slack
                    let bx0 = cols / 2 - 7
                    for x in (px0 + len)..<(bx0) where (x - px0 - len) % 2 == 0 { dot(x, top + 1 + ((x - px0 - len) / 2) % 2, Brand.cream.opacity(0.35)) }
                }
                // boat (bobs one pixel)
                let bx = cols / 2 - 7, by = sea - 9 + (phase % 4 < 2 ? 0 : 1)
                let boat = ["......#.......", "......##......", "......###.....", "......####....", "......#####...", "......#.......",
                            "##############", ".############.", "..##########.."]
                for (y, row) in boat.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "#" {
                        dot(bx + x, by + y, y < 6 ? Brand.cream : Brand.amber)
                    }
                }
            }
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }
}

/// No project yet: the empty harbour, the logo, one wry line, one button.
struct NoProjectsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 16) {
            PixelWheel(size: S(64))
            PixelScene(dock: true).frame(maxWidth: 560)
            Text("NO PROJECTS YET").font(Brand.label(14)).tracking(1.6).foregroundStyle(Brand.cream)
            Text("The boat is ready. It just needs somewhere to go.").font(.system(size: S(13))).italic().foregroundStyle(Brand.mute)
            Text("Pick your project's folder, or start an empty one. Steerify creates its board.")
                .font(.system(size: S(12))).foregroundStyle(Brand.ink.opacity(0.75))
            HStack(spacing: 10) {
                ActionButton(title: "Add project…", icon: "ship", primary: true) { model.addWorkspace() }
                Text("⇧⌘O").font(.system(size: S(10.5), design: .monospaced)).foregroundStyle(Brand.mute)
            }.padding(.top, 4)
            Button("or start from a recipe of the book AI Traction →") { model.recipesOpen = true }
                .buttonStyle(.plain).font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.amber)
                .help("A ready folder for one build: fill a few plain files, Claude guides you from there")
            Button("or try the demo project (a tiny todo app) →") { model.openDemo() }
                .buttonStyle(.plain).font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.amber)
                .help("Opens Tiny Todo: a small todo app with a real board, to look around before using your own project")
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.bg)
    }
}

/// The Set up welcome's hero (choice welcome-pixel-art A): a pixel harbour at dawn across the top of the card.
/// Sun rising behind the sea, a lighthouse sweeping its beam, a gull crossing, the boat at the pier. `sailFrom` set →
/// the boat sails out to the right (pressing Set up with Claude). Draws ~10 frames/s on a 156×50 grid; stops when
/// the app is not active or Reduce Motion is on (a still frame), so it costs nothing in the background.
struct HarbourDawn: View {
    var sailFrom: Date?
    /// The setup's progress (0 = at the pier, 1 = at the lighthouse): the live setup view sails the boat across as
    /// Claude reads, asks and drafts (request r261121-203027). `moving` = Claude is working (a wake behind the boat).
    var voyage: Double? = nil
    var moving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var active

    private static let cols = 156, rows = 50
    private static let boat = ["......#.......", "......##......", "......###.....", "......####....", "......#####...", "......#.......",
                               "##############", ".############.", "..##########.."]
    private static let start = Date()

    var body: some View {
        let still = reduceMotion || (active == .inactive && sailFrom == nil && !moving)
        TimelineView(.animation(minimumInterval: 0.1, paused: still)) { tl in
            Canvas { ctx, size in draw(ctx, size, still ? 4 : tl.date.timeIntervalSince(Self.start), tl.date) }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, _ now: Date) {
        let px = size.width / CGFloat(Self.cols)
        let cols = Self.cols, rows = max(Self.rows, Int(size.height / px))
        // A wide, short frame (the live setup panel): keep the sea, pier, boat and lighthouse in view, crop the sky.
        var ctx = ctx
        let over = CGFloat(Self.rows) * px - size.height
        if over > 0 { ctx.translateBy(x: 0, y: -over) }
        func dot(_ x: Int, _ y: Int, _ c: Color, _ a: Double = 1) {
            guard x >= 0, x < cols, y >= 0, y < rows else { return }
            ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px + 0.3, height: px + 0.3)), with: .color(c.opacity(a)))
        }
        let phase = Int(t / 0.6) % 8, horizon = 38
        // sky: night violet into Claude orange at the horizon (banded, pixel-style)
        let bands: [Color] = [Color(hex: 0x1a1430), Color(hex: 0x2a1a3a), Color(hex: 0x40223e), Color(hex: 0x5e2c40),
                              Color(hex: 0x7f3a42), Color(hex: 0xa24a46), Color(hex: 0xc0604c), Color(hex: 0xd97757)]
        for (i, c) in bands.enumerated() {
            let y0 = horizon * i / bands.count, y1 = horizon * (i + 1) / bands.count
            ctx.fill(Path(CGRect(x: 0, y: CGFloat(y0) * px, width: size.width, height: CGFloat(y1 - y0) * px + 0.5)), with: .color(c))
        }
        // stars fade as the sun comes up
        let dawn = min(1, t / 20)
        for (x, y) in [(8, 4), (25, 9), (44, 3), (70, 6), (96, 2), (60, 12), (132, 8), (148, 4), (118, 11)] {
            dot(x, y, Brand.cream, ((x + phase) % 3 == 0 ? 0.9 : 0.4) * (1 - dawn * 0.7))
        }
        // sun rising (6 px in the first 20 s), cut by the horizon
        let sy = 36 - Int(dawn * 6)
        for y in -6...6 { for x in -6...6 where x * x + y * y <= 36 && sy + y < horizon { dot(110 + x, sy + y, Brand.amber, 0.92) } }
        // sea
        ctx.fill(Path(CGRect(x: 0, y: CGFloat(horizon) * px, width: size.width, height: size.height)), with: .color(Color(hex: 0x0d1020)))
        for r in 0..<4 {
            for x in 0..<cols where (x + phase * (r + 1) + r * 3) % 7 < 4 {
                dot(x, horizon + 2 + r * 3, r == 0 ? Brand.blue : Brand.line2, r == 0 ? 0.6 : 0.9)
            }
        }
        // sun's reflection
        for r in 0..<3 { for x in (104 + r)...(116 - r) where (x + phase + r) % 3 != 0 { dot(x, horizon + 1 + r * 3, Brand.amber, 0.5 - Double(r) * 0.12) } }
        // pier
        let wood = Color(hex: 0x8a5a2b), wood2 = Color(hex: 0x5c3b1c), post = Color(hex: 0x4a2f16)
        for x in 0..<30 { dot(x, horizon - 2, wood); dot(x, horizon - 1, wood2) }
        for x in stride(from: 2, to: 30, by: 6) { for y in horizon..<(horizon + 10) { dot(x, y, post) } }
        // lighthouse: striped tower, lamp, sweeping beam
        let lx = 140, base = horizon - 1
        for y in 0..<16 { for i in 0..<4 { dot(lx + i, base - y, (y / 3) % 2 == 1 ? Brand.cream : Brand.claude) } }
        for i in -1...4 { dot(lx + i, base - 16, post) }
        for (x, y) in [(1, 17), (2, 17), (1, 18), (2, 18)] { dot(lx + x, base - y, Brand.amber) }
        let dir = phase % 8 < 4 ? -1 : 1
        for k in 3..<26 { dot(lx + 1 + dir * k, base - 18 + k / 9, Brand.amber, max(0, 0.38 - Double(k) * 0.013)) }
        // a gull crossing
        let gx = Int(t * 6) % (cols + 20) - 10, gy = 12 + (Int(t * 2) % 2)
        for (i, dy) in [0, -1, 0, -1, 0].enumerated() { dot(gx + i, gy + dy, Brand.cream, 0.85) }
        // boat: bobs at the pier, sails out on press
        var bx = 34
        if let v = voyage { bx += Int(min(1, max(0, v)) * 88) + (moving ? Int(t * 1.5) % 3 : 0) }
        if let s = sailFrom { bx += Int(max(0, now.timeIntervalSince(s)) * 90) }
        let by = horizon - 10 + (phase % 4 < 2 ? 0 : 1)
        for (y, row) in Self.boat.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" { dot(bx + x, by + y, y < 6 ? Brand.cream : Brand.amber) }
        }
        // wake behind a sailing boat
        if sailFrom != nil || moving { for k in 1..<10 where k % 2 == 1 { dot(bx - k, horizon - 1 + (k / 3) % 2, Brand.cream, 0.5 - Double(k) * 0.05) } }
    }
}

/// The iPhone just connected (request r261123-211230): a pixel phone drops in with a green ✓ on its screen while
/// fireworks burst around it in the brand colours, then it settles into a calm twinkle. `since` = when the connection
/// was detected (nil: the window opened already connected, so no burst). Still frame under Reduce Motion; paused when
/// the app is not active; after the burst it redraws twice a second only.
struct PairedCheer: View {
    var since: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var active
    @State private var settled = false   // flips 5 s after the burst: back to 2 frames/s (mac-perf-idle)
    private static let n = 44
    private static let phone = [
        "..##########..",
        ".############.",
        "##..........##",
        "##..........##",
        "##..........##",
        "##..........##",
        "##..........##",
        "##..........##",
        "##..........##",
        "##..........##",
        "##..........##",
        "##..........##",
        "##..........##",
        "##..........##",
        "##....##....##",
        ".############.",
        "..##########.."]
    private static let check = ["........#", ".......##", "......##.", "#....##..", "##..##...", ".####....", "..##....."]
    /// (seconds after since, centre x, centre y, colour index)
    private static let bursts: [(Double, Int, Int, Int)] = [
        (0.5, 8, 9, 0), (0.8, 35, 8, 1), (1.2, 7, 28, 2), (1.5, 37, 26, 3), (1.9, 22, 5, 1),
        (2.3, 10, 18, 3), (2.6, 34, 17, 0), (3.0, 21, 37, 2), (3.4, 6, 8, 1), (3.8, 38, 34, 0)]
    private static let palette: [Color] = [Brand.amber, Brand.claude, Brand.cream, Brand.green]

    var body: some View {
        let burstOver = settled || (since.map { Date().timeIntervalSince($0) > 5 } ?? true)
        // The burst plays even when Steerify is not the front app (you are looking at the phone); the calm twinkle after it pauses.
        let still = reduceMotion || (active == .inactive && burstOver)
        Group {
            // .animation wakes on every display frame (it only filters): fine for the 5 s burst; the calm twinkle after
            // it ticks twice a second with .periodic, and stops while the app is in the back.
            if still { frame(Date(), 99) }
            else if burstOver { TimelineView(.periodic(from: .now, by: 0.5)) { tl in frame(tl.date, 99) } }
            else { TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in frame(tl.date, since.map { max(0, tl.date.timeIntervalSince($0)) } ?? 99) } }
        }
        .background(Color(hex: 0x0b1a12))
        .accessibilityLabel("iPhone connected")
        .task(id: since) {
            settled = false
            guard let s = since else { return }
            try? await Task.sleep(nanoseconds: UInt64(max(0, 5.1 - Date().timeIntervalSince(s)) * 1e9))
            settled = true
        }
    }

    private func frame(_ now: Date, _ t: Double) -> some View {
        Canvas { ctx, size in draw(ctx, size, reduceMotion ? 99 : t, now.timeIntervalSinceReferenceDate) }
            .overlay(alignment: .bottom) {
                Text("CONNECTED · AHOY!").font(Brand.label(12)).tracking(1.6).foregroundStyle(Brand.green)
                    .padding(.bottom, 12)
                    .scaleEffect(t < 1.2 ? 0.6 + 0.4 * min(1, max(0, (t - 0.6) / 0.6)) : 1)
                    .opacity(t < 0.6 ? 0 : 1)
            }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, _ clock: Double) {
        let n = Self.n, px = size.width / CGFloat(n)
        func dot(_ x: Int, _ y: Int, _ c: Color, _ a: Double = 1) {
            guard x >= 0, x < n, y >= 0, y < n, a > 0 else { return }
            ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px + 0.3, height: px + 0.3)), with: .color(c.opacity(min(1, a))))
        }
        // calm twinkles (always)
        let tick = Int(clock / 0.5)
        for (i, (x, y)) in [(3, 3), (40, 4), (5, 39), (39, 37), (17, 2), (28, 41), (2, 22), (41, 23), (12, 34), (32, 10)].enumerated() {
            dot(x, y, Self.palette[i % 4], (tick + i) % 3 == 0 ? 0.9 : 0.25)
        }
        // fireworks: a rising spark, then a ring of pixels flying out and fading
        for (t0, cx, cy, ci) in Self.bursts {
            let c = Self.palette[ci], dt = t - t0
            if dt > -0.4 && dt < 0 {   // the rocket going up
                let y = cy + Int((-dt / 0.4) * 10)
                dot(cx, y, Brand.cream, 0.9); dot(cx, y + 1, Brand.amber, 0.5)
            } else if dt >= 0 && dt < 1.4 {
                let r = 1 + dt * 8, fade = 1 - dt / 1.4
                for k in 0..<16 {
                    let a = Double(k) / 16 * 2 * .pi
                    for (f, al) in [(1.0, 1.0), (0.78, 0.55), (0.56, 0.25)] {   // a spark and its trail
                        let x = cx + Int((cos(a) * r * f).rounded()), y = cy + Int((sin(a) * r * f + dt * dt * 4).rounded())
                        dot(x, y, k % 4 == 0 ? Brand.cream : c, fade * al)
                    }
                }
                if dt < 0.15 { for dx in -1...1 { for dy in -1...1 { dot(cx + dx, cy + dy, Brand.cream) } } }
            }
        }
        // confetti raining for the first 4.5 s
        if t > 0.3 && t < 4.5 {
            let fall = 1 - max(0, t - 3.5)
            for i in 0..<34 {
                let x = (i * 37 + 5) % n, speed = 9 + Double((i * 13) % 7)
                let y = Int((t - 0.3) * speed) - (i * 11) % 30
                let wob = Int(t * 4 + Double(i)) % 2
                dot(x + wob, y, Self.palette[i % 4], fall)
                if i % 3 == 0 { dot(x + wob + 1, y, Self.palette[i % 4], fall * 0.7) }
            }
        }
        // the phone drops in with a bounce (0 → 0.6 s), then breathes one pixel
        let ox = (n - 14) / 2, rest = (n - 17) / 2 - 3
        var oy = rest
        if t < 0.6 { let k = t / 0.6; oy = rest - Int((1 - k) * (1 - k) * 40) }
        else if t < 0.9 { oy = rest - Int(sin((t - 0.6) / 0.3 * .pi) * 3) }
        else if Int(clock / 1.0) % 2 == 0 { oy = rest - 1 }
        // glow behind the phone once it lands
        if t >= 0.6 {
            let g = min(1, (t - 0.6) / 0.5)
            for y in -3...19 { for x in -3...16 where x < 0 || x > 13 || y < 0 || y > 16 { if (x + y) % 2 == 0 { dot(ox + x, oy + y, Brand.green, 0.18 * g) } } }
        }
        for (y, row) in Self.phone.enumerated() {
            for (x, ch) in row.enumerated() {
                if ch == "#" { dot(ox + x, oy + y, Brand.cream) }
                else if y >= 2 && y <= 14 && x >= 2 && x <= 11 && ch == "." { dot(ox + x, oy + y, Brand.green, t >= 0.6 ? 0.9 : 0.25) }
            }
        }
        // ✓ drawn on the screen stroke by stroke (0.7 → 1.1 s)
        let shown = t < 0.7 ? 0 : min(Self.check.count * 9, Int((t - 0.7) / 0.4 * Double(Self.check.count * 9)))
        var k = 0
        for x in 0..<9 { for y in 0..<Self.check.count {
            let row = Array(Self.check[y])
            if row[x] == "#" { if k < shown { dot(ox + 2 + x, oy + 5 + y, Color(hex: 0x0b1a12)) }; k += 1 }
        } }
    }
}
