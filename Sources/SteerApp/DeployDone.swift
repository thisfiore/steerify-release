import SwiftUI

// MARK: - A deploy finished (choice deploy-finished, option A, from request r261122-122452)
//
// When the deploy shell exits 0, the tab shows a pixel-art card over its log: a boat sailing out, fireworks and a
// rocket going up, what turned live / done on the board, and Close tab (it closes by itself after 30 s). A failed
// deploy shows nothing: the tab stays on its log.

/// What one successful deploy did, shown over its tab.
struct DeployCelebration: Equatable {
    let repo: String
    let commit: String
    let took: TimeInterval
    /// To test items that turned live with this deploy.
    var live: [String] = []
    /// Key results marked done because their approved deliveries are now live.
    var done: [String] = []
    /// Claude sessions told to check the live site (DeployWake).
    var checking: [String] = []
}

struct DeployDoneOverlay: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: TerminalSession
    let done: DeployCelebration
    @State private var left = 30

    var body: some View {
        ZStack {
            Color(hex: 0x0d0f12).opacity(0.84)
            VStack(spacing: 12) {
                DeployPixelArt().frame(maxWidth: S(320)).aspectRatio(1.6, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 6))
                Text("\(done.repo) is live").font(.system(size: S(22), weight: .heavy)).foregroundStyle(Brand.cream)
                Text("commit \(String(done.commit.prefix(7))) · deployed in \(Self.duration(done.took))")
                    .font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.mute)
                VStack(alignment: .leading, spacing: 6) {
                    row(true, done.live.isEmpty ? "No To test items waited on it"
                        : "\(done.live.count) To test item\(done.live.count == 1 ? "" : "s") → live", help: done.live)
                    if !done.done.isEmpty {
                        row(true, "\(done.done.count) key result\(done.done.count == 1 ? "" : "s") → done", help: done.done)
                    }
                    row(true, "Deploy logged on the Release tab", help: [])
                    ForEach(done.checking, id: \.self) { t in row(false, "Claude checks the live site · \(t)", help: []) }
                }
                .padding(.horizontal, 26).padding(.vertical, 4)
                HStack(spacing: 12) {
                    Button { model.close(session) } label: {
                        Text("Close tab").font(.system(size: S(13), weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Brand.amber)).foregroundStyle(Color(hex: 0x1a1200))
                    }
                    .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                    Button { session.celebration = nil } label: {
                        Text("Keep the log").font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.cream)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                    }
                    .buttonStyle(SteerButton())
                }
                Text("Closes by itself in \(left) s").font(.system(size: S(11))).foregroundStyle(Brand.mute)
            }
            .padding(.vertical, 20).padding(.horizontal, 24)
            .frame(maxWidth: S(560))
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.line2))
        }
        .task {
            while left > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard session.celebration != nil else { return }     // Keep the log: no auto-close
                left -= 1
            }
            if session.celebration != nil { model.close(session) }
        }
    }

    private func row(_ ok: Bool, _ text: String, help: [String]) -> some View {
        HStack(spacing: 9) {
            Text(ok ? "✓" : "…").font(.system(size: S(10), weight: .heavy)).foregroundStyle(Color(hex: 0x0d0f12))
                .frame(width: S(15), height: S(15)).background(RoundedRectangle(cornerRadius: 4).fill(ok ? Brand.green : Brand.amber))
            Text(text).font(.system(size: S(12.5), design: .monospaced)).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help.joined(separator: "\n"))
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = max(1, Int(t.rounded()))
        return s < 60 ? "\(s) s" : "\(s / 60)m \(String(format: "%02d", s % 60))s"
    }
}

/// Night harbour: a boat with a flag sails out, fireworks burst, a rocket climbs and pops (64 × 40 pixels).
struct DeployPixelArt: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.18)) { tl in
            let t = Int(tl.date.timeIntervalSinceReferenceDate / 0.18)
            Canvas { ctx, size in DeployPixelArt.draw(ctx, size, t) }
        }
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ tick: Int) {
        let cols = 64, rows = 40
        let px = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
        let ox = (size.width - px * CGFloat(cols)) / 2, oy = (size.height - px * CGFloat(rows)) / 2
        func dot(_ x: Int, _ y: Int, _ c: Color, _ a: Double = 1) {
            guard x >= 0, x < cols, y >= 0, y < rows else { return }
            ctx.fill(Path(CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px, height: px)), with: .color(c.opacity(a)))
        }
        ctx.fill(Path(CGRect(x: ox, y: oy, width: px * CGFloat(cols), height: px * CGFloat(rows))), with: .color(Color(hex: 0x141a26)))
        let slow = tick / 3                                   // stars, sea and fireworks run at a calmer pace
        for (i, (x, y)) in [(5, 3), (14, 7), (27, 2), (41, 5), (55, 3), (60, 9), (9, 12), (35, 9)].enumerated() {
            dot(x, y, Brand.cream, (i + slow) % 3 == 0 ? 1 : 0.4)
        }
        // fireworks: three bursts on a cycle
        let fw: [Color] = [Brand.amber, Brand.green, Brand.blue, Brand.violet, Brand.red]
        for (k, (cx, cy, off)) in [(16, 10, 0), (46, 7, 3), (30, 14, 6)].enumerated() {
            let p = (slow + off) % 9
            guard p <= 5 else { continue }
            let r = Double(p + 1), c = fw[(k + (slow + off) / 9) % fw.count]
            for a in 0..<12 {
                let an = Double(a) * .pi / 6
                dot(Int((Double(cx) + cos(an) * r).rounded()), Int((Double(cy) + sin(an) * r).rounded()), c, p > 3 ? 0.55 : 1)
            }
            dot(cx, cy, .white)
        }
        // rocket: climbs from the right shore with a flickering flame, pops at the top, starts again
        let cycle = tick % 40, rx = 52
        if cycle < 26 {
            let ry = 27 - cycle
            dot(rx, ry - 3, Brand.red)                                         // nose
            for y in (ry - 2)...ry { dot(rx - 1, y, Brand.cream); dot(rx, y, Brand.cream); dot(rx + 1, y, Brand.cream) }
            dot(rx, ry - 1, Brand.blue)                                        // window
            dot(rx - 2, ry, Brand.red); dot(rx + 2, ry, Brand.red)             // fins
            dot(rx, ry + 1, Brand.amber); dot(rx, ry + 2, Brand.amber, tick % 2 == 0 ? 1 : 0.5)
            if tick % 2 == 0 { dot(rx - 1, ry + 2, Brand.red, 0.8); dot(rx + 1, ry + 2, Brand.red, 0.8) }
            for y in stride(from: ry + 3, to: min(ry + 7, 29), by: 1) where (y + tick) % 2 == 0 { dot(rx, y, Brand.mute, 0.5) }   // smoke
        } else if cycle < 34 {
            let r = Double(cycle - 25)
            for a in 0..<16 {
                let an = Double(a) * .pi / 8
                dot(Int((Double(rx) + cos(an) * r).rounded()), Int((1.0 + sin(an) * r * 0.8).rounded()) + 1,
                    a % 2 == 0 ? Brand.amber : Brand.cream, cycle > 30 ? 0.5 : 1)
            }
        }
        // sea
        for r in 0..<3 {
            for x in 0..<cols where (x + slow * (r + 1) + r * 3) % 7 < 4 {
                dot(x, 30 + r * 3, r == 0 ? Color(hex: 0x3d6ea5) : Color(hex: 0x26364d))
            }
        }
        // boat sailing right
        let bx = 4 + (slow % 44) - 6, by = 26
        for x in 0..<12 { dot(bx + x, by + 2, Color(hex: 0x8a5a2b)) }
        for x in 1..<11 { dot(bx + x, by + 3, Color(hex: 0x5c3b1c)) }
        for y in 0..<9 { dot(bx + 5, by - 8 + y, Color(hex: 0x6b4a2a)) }
        for y in 0..<7 { for x in 0...Int(Double(y) / 1.6) { dot(bx + 6 + x, by - 7 + y, Brand.cream) } }
        dot(bx + 5, by - 9, Brand.amber); dot(bx + 4, by - 9, Brand.amber); dot(bx + 4, by - 8, Brand.amber)
    }
}

/// The card, only while the session has one (observes the session so it appears the moment the deploy exits).
struct DeployDoneLayer: View {
    @ObservedObject var session: TerminalSession
    var body: some View {
        if let c = session.celebration { DeployDoneOverlay(session: session, done: c) }
    }
}
