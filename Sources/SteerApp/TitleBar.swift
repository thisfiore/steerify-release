import SwiftUI
import AppKit

/// The main window's top bar (title bar + toolbar): black, with the Mac's blur of what is behind the window.
/// SwiftUI has no behind-window blur for the toolbar, so this reaches the window's title bar view and puts a dark
/// vibrancy view (+ a black tint) under the toolbar items. Attach once with `.blackTitleBar()`.
extension View {
    func blackTitleBar() -> some View { background(BlackTitleBar()) }
}

private struct BlackTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ v: NSView, context: Context) { (v as? Probe)?.apply() }

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // The toolbar is rebuilt when the window first lays out: apply again once it has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.apply() }
        }

        func apply() {
            guard let w = window, let bar = w.standardWindowButton(.closeButton)?.superview?.superview else { return }
            w.titlebarSeparatorStyle = .none
            // `bar` is the title bar container; the system paints its gray in NSTitlebarView's background view (and
            // any material it adds): hidden, ours below replaces them (again whenever the toolbar is rebuilt).
            for v in bar.subviews where v.identifier != Self.blurId {
                if v is NSVisualEffectView { v.isHidden = true }
                for sub in v.subviews where sub is NSVisualEffectView || String(describing: type(of: sub)).contains("BackgroundView") {
                    sub.isHidden = true
                }
            }
            if bar.subviews.contains(where: { $0.identifier == Self.blurId }) { return }

            let blur = NSVisualEffectView(frame: bar.bounds)
            blur.identifier = Self.blurId
            blur.material = .hudWindow             // the darkest of the system materials
            blur.blendingMode = .behindWindow      // blurs the desktop / windows behind
            blur.state = .active                   // stays blurred when the window is in the background
            blur.appearance = NSAppearance(named: .darkAqua)
            blur.autoresizingMask = [.width, .height]

            let tint = NSView(frame: blur.bounds)
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
            tint.autoresizingMask = [.width, .height]
            blur.addSubview(tint)

            // A hairline under the bar, like the board's panel lines.
            let line = NSView(frame: NSRect(x: 0, y: 0, width: blur.bounds.width, height: 1))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
            line.autoresizingMask = [.width, .maxYMargin]
            blur.addSubview(line)

            bar.addSubview(blur, positioned: .below, relativeTo: bar.subviews.first)
        }

        static let blurId = NSUserInterfaceItemIdentifier("steerify-black-titlebar")
    }
}
