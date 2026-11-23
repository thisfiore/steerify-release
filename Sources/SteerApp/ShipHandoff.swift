import Foundation

// MARK: - Ship hands off (choice ship-feature-session-end, pick A, from request r261123-155602)
//
// When you ship from Ready or the Release tab, one release does the work (a release session or the product's
// release script). The feature sessions of the items it ships stop saying "Release → your turn": they show
// "shipping" while it runs, and once the item is live they are done ("released"), sink to the bottom and go with
// Close N done. A release that stops (script failed, session idle without shipping) gives the items back: the
// Release button comes back on their sessions.

extension AppModel {
    /// To test ids a release is shipping right now: a product run still shipping, or a release session at work
    /// (not idle) that covers them.
    func shippingIds(_ projectId: String) -> Set<String> {
        TurnMemo.get("shipping:" + projectId) {
            var ids = Set<String>()
            for r in ShipRuns.shared.active.values where r.projectId == projectId && r.phase == .shipping { ids.formUnion(r.itemIds) }
            for s in sessions where s.projectId == projectId && s.kind == .claude && s.running && s.status != .idle
                && s.item?.ref.hasPrefix("release:") == true {
                ids.formUnion(s.alsoRefs.filter { $0.hasPrefix("test:") }.map { String($0.dropFirst(5)) })
            }
            return ids
        }
    }

    /// An idle feature session whose only open board item is its release, and that release is being shipped elsewhere.
    func handedOff(_ s: TerminalSession) -> Bool {
        guard s.kind == .claude, s.running, s.status == .idle, let item = s.item, !item.ref.hasPrefix("release:"),
              let p = projects.first(where: { $0.id == s.projectId }),
              let t = board(for: p).yourTurn(of: [item.ref] + s.alsoRefs), t.verb == "Release" else { return false }
        return shippingIds(p.id).contains(String(t.ref.dropFirst("release:".count)))
    }

    /// Its work went out: every To test item of its feature is live.
    func isReleased(_ s: TerminalSession) -> Bool {
        guard let item = s.item, let p = projects.first(where: { $0.id == s.projectId }) else { return false }
        let b = board(for: p)
        var all = Set<String>()
        for r in [item.ref] + s.alsoRefs { all.formUnion(b.thread(of: r)) }
        let tests = b.ships.filter { all.contains("test:" + $0.id) }
        return !tests.isEmpty && tests.allSatisfy { $0.status == "live" }
    }
}

// MARK: - Test hook: `--ship-handoff-demo <test id> [shipping|back|live]` (background test copies only)
// A dry feature session on test:<id> (idle), then a dry release session that ships it: logs the feature session's
// state at each step and stops on the given one (for a --snapshot): shipping (release at work), back (release
// went idle without shipping), live (the item turned live; needs --scratch-writes).
enum ShipHandoffDemo {
    static func log(_ s: String) { FileHandle.standardError.write(("[handoff] " + s + "\n").data(using: .utf8)!) }
    @MainActor static func run(_ m: AppModel, _ id: String, stop: String) {
        guard CommandLine.arguments.contains("--background"), let p = m.project,
              let ref = ItemRef(ref: "test:" + id) else { return }
        func state(_ s: TerminalSession, _ step: String) {
            TurnMemo.clear()
            log("\(step): turn=\(m.yourTurn(s)?.verb ?? "-") handedOff=\(m.handedOff(s)) wrapped=\(m.isWrapped(s)) released=\(m.isReleased(s)) shipping=\(m.shippingIds(p.id).sorted())")
        }
        guard let f = m.start(projectId: p.id, item: ref, intent: .fix, dry: true) else { log("no feature session"); return }
        f.status = .idle; f.statusAt = Date().addingTimeInterval(-600)
        state(f, "before")
        var x = ItemRef(ref: "release:" + p.id)!; x.title = "Release: " + p.name
        guard let r = m.start(projectId: p.id, item: x, intent: .ship, dry: true, also: [ref.ref], focus: false) else { log("no release session"); return }
        r.status = .working
        m.selectedSession[p.id] = f.id
        m.sessionsChanged()
        state(f, "shipping")
        if stop == "shipping" { return }
        r.status = .idle; r.statusAt = Date().addingTimeInterval(-600); m.sessionsChanged()
        state(f, "back")
        if stop == "back" { return }
        r.status = .working; m.sessionsChanged()
        let b = m.board(for: p)
        guard let item = b.ships.first(where: { $0.id == id }) else { log("no item"); return }
        m.setLive([item], in: p, live: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            _ = b.reload(); r.status = .idle; m.sessionsChanged()
            state(f, "live")
        }
    }
}
