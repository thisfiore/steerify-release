import SwiftUI

/// The one button style of the app: hand pointer, brighter on hover, pressed feedback.
struct SteerButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoverLabel(configuration: configuration) }
    private struct HoverLabel: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label
                .brightness(hover ? 0.12 : 0)
                .opacity(configuration.isPressed ? 0.75 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Rectangle())
                .pointerStyle(.link)
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.12), value: hover)
        }
    }
}

/// For things that are clickable but not Buttons (tap gestures, rows): hand pointer + subtle hover tint.
struct Clickable: ViewModifier {
    var tint = true
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 6).fill(tint && hover ? Color.white.opacity(0.05) : .clear))
            .contentShape(Rectangle())
            .pointerStyle(.link)
            .onHover { hover = $0 }
    }
}

extension View {
    func clickable(tint: Bool = true) -> some View { modifier(Clickable(tint: tint)) }
}

/// Claude's orange, for everything Claude does for you.
extension Brand { static let claude = Color(hex: 0xD97757) }

/// An 8-ray spark in Claude orange (drawn, not the official logo artwork).
struct ClaudeSpark: View {
    var size: CGFloat = 12
    var color: Color = Brand.claude
    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r = min(sz.width, sz.height) / 2
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                let long = i % 2 == 0 ? r : r * 0.78
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + cos(a) * long, y: c.y + sin(a) * long))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: max(1.4, r * 0.32), lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// The one pattern for "a Claude session can do this for you": orange spark + short label.
struct ClaudeButton: View {
    var title = "Do it with Claude"
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ClaudeSpark(size: S(12), color: prominent ? .white : Brand.claude)
                Text(title).font(.system(size: S(11.5), weight: .semibold))
            }
            .foregroundStyle(prominent ? Color.white : Brand.claude)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(prominent ? Brand.claude : Brand.claude.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.claude.opacity(prominent ? 1 : 0.55)))
        }
        .buttonStyle(SteerButton())
    }
}


/// The big call to action, in the landing's pixel style: stepped corners, hard pixel shadow, presses down.
struct PixelCTA: View {
    let title: String
    var subtitle: String? = nil
    var color: Color = Brand.amber
    var small = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(PixelCTAStyle(title: title, subtitle: subtitle, color: color, small: small))
    }
}

private struct PixelCTAStyle: ButtonStyle {
    let title: String; let subtitle: String?; let color: Color; var small = false
    func makeBody(configuration: Configuration) -> some View { CTALabel(title: title, subtitle: subtitle, color: color, small: small, pressed: configuration.isPressed) }
    struct CTALabel: View {
        let title: String; let subtitle: String?; let color: Color; var small = false; let pressed: Bool
        @State private var hover = false
        var body: some View {
            let px: CGFloat = small ? 2 : 3
            HStack(spacing: small ? 6 : 10) {
                PixelIcon(name: "play", size: S(small ? 9 : 13)).foregroundStyle(Color(hex: 0x1a1200))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased()).font(.system(size: S(small ? 11 : 14), weight: .black, design: .monospaced)).tracking(small ? 0.8 : 1.2)
                    if let subtitle { Text(subtitle).font(.system(size: S(10.5), weight: .semibold, design: .monospaced)).opacity(0.7) }
                }
            }
            .foregroundStyle(Color(hex: 0x1a1200))
            .padding(.horizontal, small ? 10 : 18).padding(.vertical, small ? 5 : 11)
            .background(PixelBox(step: px).fill(color).brightness(hover ? 0.06 : 0))
            .background(PixelBox(step: px).fill(Color.black.opacity(0.55)).offset(x: px, y: pressed ? px : px * 2))   // hard pixel shadow
            .offset(y: pressed ? px : 0)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .pointerStyle(.link)
            .animation(.easeOut(duration: 0.08), value: pressed)
        }
    }
}

/// A rectangle with stepped (pixel) corners.
struct PixelBox: Shape {
    var step: CGFloat = 3
    func path(in r: CGRect) -> Path {
        let s = step
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 2 * s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + s)); p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2 * s)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - 2 * s)); p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.maxY - s)); p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - s)); p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - 2 * s)); p.addLine(to: CGPoint(x: r.minX, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + 2 * s)); p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.minY + s)); p.closeSubpath()
        return p
    }
}
