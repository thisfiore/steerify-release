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
            Button("or try the demo project (a tiny todo app) →") { model.openDemo() }
                .buttonStyle(.plain).font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.amber)
                .help("Opens Tiny Todo: a small todo app with a real board, to look around before using your own project")
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.bg)
    }
}
