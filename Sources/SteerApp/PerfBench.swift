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

    static func switchProjects(_ w: NSWindow, _ m: AppModel, to other: String, out: String) {
        guard let home = m.selectedProjectId, m.projects.contains(where: { $0.id == other }) else {
            NSLog("switch-bench: no project \(other)"); NSApp.terminate(nil); return
        }
        var times: [Double] = []
        var targets = Array(repeating: [other, home], count: 4).flatMap { $0 }
        func step() {
            guard !targets.isEmpty else { finish(); return }
            let id = targets.removeFirst()
            let t0 = CFAbsoluteTimeGetCurrent()
            m.selectedProjectId = id
            w.contentView?.layoutSubtreeIfNeeded()
            w.displayIfNeeded()
            times.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            // Let async work settle between switches, as between two real clicks.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { step() }
        }
        func finish() {
            let warm = Array(times.dropFirst(2)).sorted()
            let r: [String: Any] = ["coldMs": ((times.first ?? 0) * 10).rounded() / 10,
                                    "warmAvgMs": ((warm.reduce(0, +) / Double(max(warm.count, 1))) * 10).rounded() / 10,
                                    "maxMs": ((times.max() ?? 0) * 10).rounded() / 10, "switches": times.count]
            if let d = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]) { try? d.write(to: URL(fileURLWithPath: out)) }
            NSLog("switch-bench: \(r)")
            NSApp.terminate(nil)
        }
        step()
    }

    /// What using the app costs while the board is on screen: the app's shared state changes (a session moves, a toast,
    /// a nudge) and the mouse moves over the list. Each change is timed until the window has laid out and drawn again.
    static func churn(_ w: NSWindow, _ m: AppModel, out: String) {
        var model: [Double] = [], hover: [Double] = []
        var n = 0
        let cv = w.contentView!
        func frame(_ change: () -> Void) -> Double {
            let t0 = CFAbsoluteTimeGetCurrent()
            change()
            w.contentView?.layoutSubtreeIfNeeded()
            w.displayIfNeeded()
            return (CFAbsoluteTimeGetCurrent() - t0) * 1000
        }
        func move(_ p: NSPoint) {
            if let e = NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) { w.sendEvent(e) }
        }
        func step() {
            if n < 120 {
                model.append(frame { m.objectWillChange.send() })
            } else if n < 180 {
                // Down the board list, 12 pt at a time: rows light up and go dark under the pointer.
                let y = cv.bounds.height - 220 - CGFloat(n - 120) * 12
                hover.append(frame { move(NSPoint(x: 300, y: y)) })
            } else { finish(); return }
            n += 1
            DispatchQueue.main.async { step() }
        }
        func stats(_ t: [Double]) -> [String: Any] {
            let s = t.sorted(); let avg = t.reduce(0, +) / Double(max(t.count, 1))
            return ["avgMs": (avg * 10).rounded() / 10, "p95Ms": ((s.isEmpty ? 0 : s[min(s.count - 1, Int(Double(s.count) * 0.95))]) * 10).rounded() / 10,
                    "maxMs": ((s.last ?? 0) * 10).rounded() / 10]
        }
        func finish() {
            let a = stats(model), b = stats(hover)
            let r: [String: Any] = ["modelAvgMs": a["avgMs"]!, "modelP95Ms": a["p95Ms"]!, "modelMaxMs": a["maxMs"]!,
                                    "hoverAvgMs": b["avgMs"]!, "hoverP95Ms": b["p95Ms"]!, "hoverMaxMs": b["maxMs"]!]
            if let d = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]) { try? d.write(to: URL(fileURLWithPath: out)) }
            NSLog("churn-bench: \(r)")
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
    /// How many times this chapter's fold was set in this run: a row keeps its own click only while this has not moved
    /// (a jump to a key result opens its chapter from outside the row).
    private var revs: [String: Int] = [:]
    func rev(_ project: String, _ slug: String) -> Int { revs[project + "/" + slug] ?? 0 }
    func set(_ project: String, _ slug: String, folded on: Bool) {
        revs[project + "/" + slug, default: 0] += 1
        var s = load(project)
        if on { s.insert(slug) } else { s.remove(slug) }
        folded[project] = s
        Prefs.store.set(s.sorted().joined(separator: "\n"), forKey: key(project))
    }
}
