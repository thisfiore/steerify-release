import SwiftUI

/// The auto-consolidate countdown's hero (choice autocons-countdown-pixel A, request r261123-113412): a night strip,
/// 160 × 26 pixels. A boat waits at the pier with its lantern, one buoy per key result waits out at sea, and a fuse of
/// amber lantern dots burns down one per second. At 0 the done card's BuoyVoyage sails the same boat past the buoys.
/// The grid is 26 pixels high and as wide as the card. ~6 frames/s; still while the window is in the background or with
/// Reduce Motion (the ring beside it keeps the number).
struct PierCountdown: View {
    let left: Int, total: Int, buoys: Int
    var still = false
    @Environment(\.controlActiveState) private var active

    static let rows = 26

    var body: some View {
        let frozen = still || active == .inactive
        TimelineView(.animation(minimumInterval: 1.0 / 6, paused: frozen)) { tl in
            let tick = frozen ? 0 : Int(tl.date.timeIntervalSinceReferenceDate * 6)
            Canvas { ctx, size in Self.draw(ctx, size, tick: tick, left: left, total: total, buoys: buoys) }
        }
        .accessibilityHidden(true)
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, tick: Int, left: Int, total: Int, buoys: Int) {
        let px = size.height / CGFloat(rows)
        let cols = max(Int(size.width / px), 80)
        let ox: CGFloat = 0, oy: CGFloat = 0
        func dot(_ x: Int, _ y: Int, _ c: Color, _ a: Double = 1) {
            guard x >= 0, x < cols, y >= 0, y < rows else { return }
            ctx.fill(Path(CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px + 0.3, height: px + 0.3)),
                     with: .color(c.opacity(a)))
        }
        let wood = Color(hex: 0x8a5a2b), dark = Color(hex: 0x5c3b1c), post = Color(hex: 0x4a2f16)
        ctx.fill(Path(CGRect(x: ox, y: oy, width: px * CGFloat(cols), height: px * CGFloat(rows))), with: .color(Color(hex: 0x141a26)))
        let beat = tick / 3                                   // stars, waves and bobbing move twice a second
        // stars + a small moon
        for i in 0..<(cols / 18) {
            let x = 34 + (i * 37) % max(cols - 44, 1), y = 2 + (i * 5) % 9
            dot(x, y, Brand.cream, (i + beat) % 3 == 0 ? 1 : 0.35)
        }
        for y in 0..<4 { for x in 0..<4 where (x * 2 - 3) * (x * 2 - 3) + (y * 2 - 3) * (y * 2 - 3) <= 10 { dot(cols - 10 + x, 2 + y, Brand.cream, 0.85) } }
        // sea
        let sea = rows - 8
        for r in 0..<3 {
            for x in 0..<cols where (x + beat * (r + 1) + r * 3) % 7 < 4 {
                dot(x, sea + r * 3, r == 0 ? Color(hex: 0x3d6ea5) : Color(hex: 0x26364d))
            }
        }
        // the pier: planks on two posts, a lantern at its end
        for x in 0..<18 { dot(x, sea - 3, wood); dot(x, sea - 2, dark) }
        for y in (sea - 1)..<rows { dot(3, y, post); dot(12, y, post) }
        for y in (sea - 10)..<(sea - 3) { dot(15, y, Color(hex: 0x6b4a2a)) }
        dot(14, sea - 11, Brand.amber); dot(16, sea - 11, Brand.amber); dot(15, sea - 11, Brand.amber, beat % 2 == 0 ? 1 : 0.6)
        // the fuse: one lantern dot per second left, burning down from the right
        for i in 0..<max(left, 0) { dot(20 + i * 2, 2, Brand.amber, i == left - 1 && beat % 2 == 1 ? 0.55 : 1) }
        let bx = 18, bob = beat % 2
        // buoys: one per key result (at most 14), amber = waiting
        let shown = min(max(buoys, 1), 14)
        for i in 0..<shown {
            let x = 40 + i * (cols - 52) / max(shown - 1, 1), b = (beat + i) % 2
            dot(x, sea - 3 + b, Brand.cream); dot(x, sea - 2 + b, Brand.amber)
            dot(x - 1, sea - 1 + b, Brand.amber); dot(x, sea - 1 + b, Brand.amber); dot(x + 1, sea - 1 + b, Brand.amber)
        }
        dot(17, sea - 1, Brand.cream, 0.35)                   // the moored line
        // hull, mast, sail (Claude orange), amber flag
        for x in 0..<12 { dot(bx + x, sea - 1 + bob, wood) }
        for x in 1..<11 { dot(bx + x, sea + bob, dark) }
        for y in 0..<9 { dot(bx + 5, sea - 10 + y + bob, Color(hex: 0x6b4a2a)) }
        for y in 0..<7 { for x in 0...Int(Double(y) / 1.6) { dot(bx + 6 + x, sea - 9 + y + bob, Color(hex: 0xd97757)) } }
        dot(bx + 4, sea - 11 + bob, Brand.amber); dot(bx + 3, sea - 11 + bob, Brand.amber); dot(bx + 4, sea - 10 + bob, Brand.amber)
    }
}
