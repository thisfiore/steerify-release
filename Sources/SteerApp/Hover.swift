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
    /// Full width, the same size as the main call to action above it.
    var large = false
    let action: () -> Void
    var body: some View {
        let r: CGFloat = large ? 8 : 6
        Button(action: action) {
            HStack(spacing: large ? 7 : 6) {
                ClaudeSpark(size: S(large ? 13.5 : 12), color: prominent ? .white : Brand.claude)
                Text(title).font(.system(size: S(large ? 13.5 : 11.5), weight: large ? .bold : .semibold))
            }
            .frame(maxWidth: large ? .infinity : nil)
            .foregroundStyle(prominent ? Color.white : Brand.claude)
            .padding(.horizontal, 10).padding(.vertical, large ? 9 : 5)
            .background(RoundedRectangle(cornerRadius: r).fill(prominent ? Brand.claude : Brand.claude.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: r).stroke(Brand.claude.opacity(prominent ? 1 : 0.55)))
            .contentShape(Rectangle())
        }
        .buttonStyle(SteerButton())
    }
}


/// The big call to action, in the landing's pixel style: stepped corners, pixel icon, hard pixel shadow, presses down.
/// The standard for every main action (Choose, Test, New request, File + build with Claude, Update, Ship).
/// Three variants: title only · title + `subtitle` · title + `shortcut` on the right (faded text, choice pixel-cta-shortcut B).
struct PixelCTA: View {
    let title: String
    var subtitle: String? = nil
    var color: Color = Brand.amber
    var small = false
    var icon = "play"          // a PixelIcon name: "ship" (set sail), "rocket" (release), "choice", "test", "plus", "claude", "update"
    var shortcut: String? = nil   // shown as faded text on the right, e.g. "⌘↩"; bind the real key with .keyboardShortcut
    var fullWidth = false
    var selected = false       // already chosen: a dim fill in the colour, the label in the colour
    var ink: Color = Color(hex: 0x1a1200)
    let action: () -> Void
    var body: some View {
        Button(action: action) { EmptyView() }
            .buttonStyle(PixelCTAStyle(title: title, subtitle: subtitle, color: color, small: small, icon: icon,
                                       shortcut: shortcut, fullWidth: fullWidth, selected: selected, ink: ink))
    }
}

private struct PixelCTAStyle: ButtonStyle {
    let title: String; let subtitle: String?; let color: Color; var small = false; var icon = "play"
    var shortcut: String? = nil; var fullWidth = false; var selected = false; var ink: Color = Color(hex: 0x1a1200)
    func makeBody(configuration: Configuration) -> some View {
        CTALabel(title: title, subtitle: subtitle, color: color, small: small, icon: icon, shortcut: shortcut,
                 fullWidth: fullWidth, selected: selected, ink: ink, pressed: configuration.isPressed)
    }
    struct CTALabel: View {
        let title: String; let subtitle: String?; let color: Color; var small = false; var icon = "play"
        var shortcut: String? = nil; var fullWidth = false; var selected = false; var ink: Color = Color(hex: 0x1a1200)
        let pressed: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hover = false
        var body: some View {
            let px: CGFloat = small ? 2 : 3
            let fg = selected ? color : ink
            HStack(spacing: small ? 6 : 10) {
                if fullWidth { Spacer(minLength: 0) }
                PixelIcon(name: icon, size: S(small ? 9 : (icon == "play" ? 13 : 16)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased()).font(.system(size: S(small ? 11 : 14), weight: .black, design: .monospaced)).tracking(small ? 0.8 : 1.2)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if let subtitle { Text(subtitle).font(.system(size: S(10.5), weight: .semibold, design: .monospaced)).opacity(0.7).lineLimit(1) }
                }
                if let shortcut {
                    Text(shortcut).font(.system(size: S(small ? 10 : 11.5), weight: .bold, design: .monospaced)).opacity(0.5)
                        .padding(.leading, small ? 0 : 2)
                }
                if fullWidth { Spacer(minLength: 0) }
            }
            .foregroundStyle(fg)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, small ? 10 : 18).padding(.vertical, small ? 5 : 11)
            .background(PixelBox(step: px).fill(selected ? color.opacity(0.16) : color).brightness(hover && enabled ? 0.06 : 0))
            .overlay(selected ? PixelBox(step: px).stroke(color, lineWidth: 1.5) : nil)
            .background(PixelBox(step: px).fill(Color.black.opacity(0.55)).offset(x: px, y: pressed ? px : px * 2))   // hard pixel shadow
            .offset(y: pressed ? px : 0)
            .opacity(enabled ? 1 : 0.5)
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
