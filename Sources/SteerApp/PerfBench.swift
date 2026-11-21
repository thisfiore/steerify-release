import AppKit

/// Test hooks for speed: scroll the board and time every frame, click a point like a person. Test windows only.
@MainActor
enum PerfBench {
    /// The board's list: the tallest scroll view in the window.
    static func boardScroll(_ w: NSWindow) -> NSScrollView? {
        var best: NSScrollView? = nil
        func walk(_ v: NSView) {
            if let s = v as? NSScrollView, let d = s.documentView,
               d.frame.height > (best?.documentView?.frame.height ?? 0), s.frame.width > 400 { best = s }
            v.subviews.forEach(walk)
        }
        if let root = w.contentView?.superview ?? w.contentView { walk(root) }
        return best
    }

    static func scroll(_ w: NSWindow, out: String) {
        guard let s = boardScroll(w), let doc = s.documentView else { NSLog("scroll-bench: no scroll view"); NSApp.terminate(nil); return }
        let clip = s.contentView
        var times: [Double] = []
        var y: CGFloat = 0, down = true, laps = 0
        func step() {
            let maxY = max(0, doc.frame.height - clip.bounds.height)
            y = down ? min(maxY, y + 60) : max(0, y - 60)
            let t0 = CFAbsoluteTimeGetCurrent()
            clip.scroll(to: NSPoint(x: 0, y: doc.isFlipped ? y : maxY - y))
            s.reflectScrolledClipView(clip)
            w.contentView?.layoutSubtreeIfNeeded()
            w.displayIfNeeded()
            times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            if down && y >= maxY { down = false; laps += 1 }
            else if !down && y <= 0 { laps += 1 }
            if laps >= 2 || times.count > 2000 { finish(); return }
            DispatchQueue.main.async { step() }
        }
        func finish() {
            let sorted = times.sorted()
            let avg = times.reduce(0, +) / Double(max(times.count, 1))
            let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            let r: [String: Any] = ["frames": times.count, "avgMs": (avg * 10).rounded() / 10, "p95Ms": (p95 * 10).rounded() / 10,
                                    "maxMs": ((sorted.last ?? 0) * 10).rounded() / 10, "height": Int(doc.frame.height)]
            if let d = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]) { try? d.write(to: URL(fileURLWithPath: out)) }
            NSLog("scroll-bench: \(r)")
            NSApp.terminate(nil)
        }
        step()
    }

    static func click(_ w: NSWindow, x: Double, y: Double) {
        guard let cv = w.contentView else { return }
        let p = NSPoint(x: x, y: cv.bounds.height - y)          // content coords are bottom-up
        func send(_ type: NSEvent.EventType) {
            if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                w.sendEvent(e)
            }
        }
        // Press, then release 60 ms later, as a finger does (tap gestures ignore a press and release in the same instant).
        send(.leftMouseDown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { send(.leftMouseUp) }
        NSLog("click: \(x), \(y)")
    }
}

/// Chapters folded to one line on the roadmap, per project, remembered in the app's settings.
@MainActor
final class ChapterFolds {
    static let shared = ChapterFolds()
    /// Read from settings once per project.
    private var folded: [String: Set<String>] = [:]
    private func key(_ project: String) -> String { "collapsedChapters-" + project }
    private func load(_ project: String) -> Set<String> {
        if let f = folded[project] { return f }
        // Older builds saved it under "collapsedChapters.<id>".
        let raw = Prefs.store.string(forKey: key(project)) ?? Prefs.store.string(forKey: "collapsedChapters." + project) ?? ""
        let s = Set(raw.split(separator: "\n").map(String.init))
        folded[project] = s
        return s
    }
    func isFolded(_ project: String, _ slug: String) -> Bool { load(project).contains(slug) }
    func set(_ project: String, _ slug: String, folded on: Bool) {
        var s = load(project)
        if on { s.insert(slug) } else { s.remove(slug) }
        folded[project] = s
        Prefs.store.set(s.sorted().joined(separator: "\n"), forKey: key(project))
    }
}
