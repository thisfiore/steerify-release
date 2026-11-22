import AppKit
import QuartzCore

/// The pixel loader in the middle of the window while a project switch is built (request r261121-233129).
///
/// Switching builds the new board on the main thread (~0.2–0.3 s on a big board), so a SwiftUI animation would freeze
/// for exactly that time. This one is plain Core Animation: it is committed to the window before the switch starts,
/// and the render server keeps the wheel turning and the dots blinking while the main thread is busy.
@MainActor
final class SwitchLoader {
    static let shared = SwitchLoader()

    private var view: LoaderView?
    private var shownAt = Date.distantPast
    private var hideWork: DispatchWorkItem?
    /// Shown at least this long, so a fast switch reads as a beat, not a flicker.
    private let minimum: TimeInterval = 0.4

    /// Off for test runs that time the switch itself (perf-check measures the board, not the loader).
    static var enabled = !CommandLine.arguments.contains("--no-switch-loader")

    func show(_ name: String, hold: Bool = false) {
        guard Self.enabled, let w = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }),
              let host = w.contentView else { return }
        let v: LoaderView
        if let existing = view, existing.superview === host { v = existing }
        else {
            view?.removeFromSuperview()
            v = LoaderView(frame: host.bounds)
            v.autoresizingMask = [.width, .height]
            host.addSubview(v)
            view = v
            shownAt = Date()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        v.layout(name: name)
        v.layer?.removeAnimation(forKey: "out")
        v.layer?.opacity = 1
        CATransaction.commit()
        CATransaction.flush()          // on screen now, before SwiftUI starts on the new board
        hideWork?.cancel()
        if hold { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        // A timer fires only once the main thread is free again, i.e. after the new board has been built.
        DispatchQueue.main.asyncAfter(deadline: .now() + minimum, execute: work)
    }

    private func hide() {
        guard let v = view, let l = v.layer else { return }
        // One more turn of the run loop: the new board's first frame is drawn before the loader lifts.
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                if self?.view === v, v.layer?.opacity == 0 { v.removeFromSuperview(); self?.view = nil }
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.18
            l.opacity = 0
            l.add(fade, forKey: "out")
            CATransaction.commit()
        }
    }

    // MARK: The pixel wheel, turned in the raster (crisp pixels at every angle)

    /// Frames over one spoke step (45°): the wheel looks the same after it, so 6 frames loop seamlessly.
    static let frames: [CGImage] = (0..<6).compactMap { wheel(phase: Double($0) / 6 * .pi / 4, cell: 8) }

    /// The same raster as `PixelWheel` (TopBar.swift), with the spokes turned by `phase`.
    static func wheel(phase: Double, cell: Int) -> CGImage? {
        let n = 17, px = n * cell
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let amber = CGColor(srgbRed: 1, green: 0.69, blue: 0.125, alpha: 1)
        let cream = CGColor(srgbRed: 0.949, green: 0.91, blue: 0.812, alpha: 1)
        let c = 8.0
        for y in 0..<n { for x in 0..<n {
            let dx = Double(x) - c, dy = Double(y) - c, r = hypot(dx, dy), a = atan2(dy, dx) - phase
            let k = (a / (.pi / 4)).rounded(), da = abs(a - k * .pi / 4) * r
            var col: CGColor? = nil
            if r <= 2.2 { col = amber }
            else if (r >= 4.6 && r <= 5.9) || (da < 0.55 && r <= 7.4) || (r > 7.4 && r <= 8.3 && da < 0.9) { col = cream }
            guard let col else { continue }
            ctx.setFillColor(col)
            // CG is bottom-up; the raster is top-down.
            ctx.fill(CGRect(x: x * cell, y: (n - 1 - y) * cell, width: cell - 1, height: cell - 1))
        } }
        return ctx.makeImage()
    }
}

/// The overlay: the board dims, a small card in the middle with the turning wheel, LOADING + three dots, the project name.
private final class LoaderView: NSView {
    private let card = CALayer(), wheel = CALayer(), title = CATextLayer(), name = CATextLayer()
    private let dots = (0..<3).map { _ in CALayer() }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.backgroundColor = CGColor(srgbRed: 0.027, green: 0.031, blue: 0.039, alpha: 0.62)
        layer = root          // layer-hosting: AppKit leaves these layers to us
        wantsLayer = true
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        card.backgroundColor = CGColor(srgbRed: 0.067, green: 0.075, blue: 0.094, alpha: 1)
        card.borderColor = CGColor(srgbRed: 0.204, green: 0.224, blue: 0.267, alpha: 1)
        card.borderWidth = 1
        card.cornerRadius = 4
        // The hard pixel shadow of the app's buttons.
        card.shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        card.shadowOpacity = 0.9; card.shadowRadius = 0; card.shadowOffset = CGSize(width: 4, height: -4)
        root.addSublayer(card)

        wheel.magnificationFilter = .nearest
        wheel.contentsScale = scale
        wheel.contents = SwitchLoader.frames.first
        let turn = CAKeyframeAnimation(keyPath: "contents")
        turn.values = SwitchLoader.frames
        turn.calculationMode = .discrete
        turn.duration = 0.48
        turn.repeatCount = .infinity
        wheel.add(turn, forKey: "turn")
        card.addSublayer(wheel)

        for (l, size, color) in [(title, 16.0, CGColor(srgbRed: 1, green: 0.69, blue: 0.125, alpha: 1)),
                                 (name, 12.0, CGColor(srgbRed: 0.561, green: 0.541, blue: 0.49, alpha: 1))] {
            l.font = (LabelFont.ready ? NSFont(name: LabelFont.name, size: size) : nil) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
            l.fontSize = size
            l.foregroundColor = color
            l.alignmentMode = .center
            l.truncationMode = .end
            l.contentsScale = scale
            card.addSublayer(l)
        }
        title.string = "LOADING"

        for (i, d) in dots.enumerated() {
            d.backgroundColor = CGColor(srgbRed: 1, green: 0.69, blue: 0.125, alpha: 1)
            let blink = CAKeyframeAnimation(keyPath: "opacity")
            blink.values = [0.15, 1, 0.15, 0.15]
            blink.keyTimes = [0, 0.25, 0.5, 1]
            blink.calculationMode = .discrete
            blink.duration = 0.9
            blink.repeatCount = .infinity
            blink.beginTime = CACurrentMediaTime() + Double(i) * 0.15
            d.opacity = 0.15
            d.add(blink, forKey: "blink")
            card.addSublayer(d)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // clicks go through to the board
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); place() }

    func layout(name n: String) {
        name.string = n.uppercased()
        place()
    }

    private func place() {
        guard let root = layer else { return }
        root.frame = bounds
        let w: CGFloat = 220, h: CGFloat = 168
        card.frame = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h).integral
        // Card sublayers: origin bottom-left (the layer is not flipped).
        wheel.frame = CGRect(x: (w - 68) / 2, y: h - 22 - 68, width: 68, height: 68)
        let titleW: CGFloat = 92
        title.frame = CGRect(x: (w - titleW - 20) / 2, y: 42, width: titleW, height: 20)
        for (i, d) in dots.enumerated() { d.frame = CGRect(x: title.frame.maxX + 2 + CGFloat(i) * 7, y: 46, width: 4, height: 4) }
        name.frame = CGRect(x: 14, y: 18, width: w - 28, height: 16)
    }
}
