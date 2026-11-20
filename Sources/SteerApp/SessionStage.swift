import SwiftUI

// MARK: - Sessions follow the tab (choice sessions-follow-tab, pick A)
//
// Every session has a stage: the board tab where its work stands now. It is read from the item and the
// rest of its feature (the thread: choices, deliveries, key results), never typed by hand, so a session moves
// with its item: choice answered → Ready, delivered → To test, OK → Release.
// The session list shows the open tab's sessions first and folds the others; the session you're in and the
// ones that need you are never folded. "Follow the tab" can be switched off (list header or Settings).

extension Prefs {
    static let sessionsFollowTab = "sessionsFollowTab"   // Bool, default true
    static var followTab: Bool { store.object(forKey: sessionsFollowTab) as? Bool ?? true }
}

/// The READY tab (its own work, delivered separately): looked up by name so this file builds with or without it.
private let readyTab = BoardTab(rawValue: "ready")

extension BoardStore {
    /// The tab where an item's feature stands now. nil = nothing on the board to follow (free session).
    func stage(of refs: [String]) -> BoardTab? {
        guard !refs.isEmpty else { return nil }
        // Asked for every session on every redraw: worked out once per board change (it froze the app on 19 Nov).
        return memoized("stage:" + refs.joined(separator: "|")) { computeStage(of: refs) }
    }
    private func computeStage(of refs: [String]) -> BoardTab? {
        if refs.contains(where: { $0.hasPrefix("task:") }) { return .task }                // a task run lives on Tasks
        var all = Set<String>()
        for r in refs { all.formUnion(thread(of: r)) }
        let shipIds = all.filter { $0.hasPrefix("test:") }.map { String($0.dropFirst(5)) }
        let tests = ships.filter { shipIds.contains($0.id) }
        let choiceIds = all.filter { $0.hasPrefix("choice:") }.map { String($0.dropFirst(7)) }
        let choices = decisions.filter { choiceIds.contains($0.id) }

        // What waits on you first, then what is in motion, then where the item was filed.
        if tests.contains(where: { [.toTest, .retest].contains(shipState($0)) }) { return .test }
        if choices.contains(where: { !isDecided($0) && !isParked($0) }) { return .choice }
        if choices.contains(where: { isDecided($0) && !isBuilt($0) }) { return readyTab ?? .choice }
        if tests.contains(where: { shipState($0) == .waiting }) { return .test }         // refine / broken: being fixed
        if tests.contains(where: { shipState($0) == .ok }) { return .release }           // OK → release (or released)
        if !choices.isEmpty { return choices.allSatisfy(isDecided) ? .road : .choice }   // answered + being built: in development
        let kinds = Set(refs.compactMap { $0.split(separator: ":").first.map(String.init) })
        if kinds.contains("req") || kinds.contains("reqs") { return .req }
        if kinds.contains("release") { return .release }
        if !tests.isEmpty { return .test }
        return .road                                                                     // road, track, request
    }
}

extension AppModel {
    /// The stage of a session (nil: a shell or a session without an item: always shown).
    func stage(of s: TerminalSession) -> BoardTab? {
        guard let item = s.item, let p = projects.first(where: { $0.id == s.projectId }) else { return nil }
        let refs = [item.ref] + s.alsoRefs
        // An answer of yours waiting for this session's next step: it is on the Ready tab.
        if let readyTab, nudges.contains(where: { $0.projectId == p.id && refs.contains($0.ref) }) { return readyTab }
        return board(for: p).stage(of: refs)
    }

    /// The session list split for a tab: the tab's own sessions (+ free ones, the one you're in, the ones that
    /// need you) and the rest, folded. With "follow the tab" off, everything is in `shown`.
    func sessionsFor(tab: BoardTab, projectId: String, follow: Bool) -> (shown: [TerminalSession], folded: [TerminalSession]) {
        let list = orderedSessions(of: projectId)
        guard follow else { return (list, []) }
        let cur = current(of: projectId)?.id
        var shown: [TerminalSession] = [], folded: [TerminalSession] = []
        for s in list {
            let st = stage(of: s)
            if st == nil || st == tab || s.id == cur || (s.running && s.status == .waiting) { shown.append(s) } else { folded.append(s) }
        }
        // This tab's sessions on top; kept-visible ones from other stages after them.
        let mine = shown.filter { stage(of: $0) == tab }
        return (mine + shown.filter { stage(of: $0) != tab }, folded)
    }

    /// How many sessions stand on each tab (for the counts on the tab bar).
    func sessionCounts(projectId: String) -> [BoardTab: Int] {
        var out: [BoardTab: Int] = [:]
        for s in sessions(of: projectId) where s.running && !isWrapped(s) { if let t = stage(of: s) { out[t, default: 0] += 1 } }
        return out
    }
}

/// A small coloured stage tag on a session chip ("CHOICE", "TO TEST"…), shown when it is not the open tab's.
struct StageTag: View {
    let tab: BoardTab
    var body: some View {
        Text(tab.short).font(Brand.label(8)).tracking(0.6)
            .foregroundStyle(tab.color)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(tab.color.opacity(0.7), lineWidth: 1))
            .fixedSize()
    }
}

extension BoardTab {
    var short: String { ["ready": "READY", "test": "TO TEST", "choice": "CHOICE", "req": "REQ", "road": "ROADMAP", "task": "TASK", "release": "RELEASE"][rawValue] ?? rawValue.uppercased() }
}

/// "Follow tab" checkbox in the session list header (same setting as in Settings → Personalisation).
struct FollowTabToggle: View {
    @AppStorage(Prefs.sessionsFollowTab, store: Prefs.store) private var follow = true
    var body: some View {
        Button { follow.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: follow ? "checkmark.square.fill" : "square").font(.system(size: S(10)))
                Text("Follow tab").font(.system(size: S(10.5)))
            }
            .foregroundStyle(follow ? Brand.amber : Brand.mute)
        }
        .buttonStyle(SteerButton()).fixedSize()
        .help(follow ? "Showing the open tab's sessions first, the rest folded. Click to show all." : "Showing every session. Click to follow the open tab.")
    }
}

/// "Others · 3 ▸": the folded sessions of the other stages, one click to open.
struct FoldedSessionsButton: View {
    let count: Int
    @Binding var open: Bool
    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
            HStack(spacing: 4) {
                Text("Others · \(count)").font(Brand.label(9)).tracking(0.7)
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: S(8), weight: .bold))
            }
            .foregroundStyle(Brand.mute)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Capsule().stroke(Brand.line))
        }
        .buttonStyle(SteerButton()).fixedSize()
        .help(open ? "Fold the sessions of the other tabs" : "Show the sessions of the other tabs")
    }
}
