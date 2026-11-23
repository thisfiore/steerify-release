import AppKit
import SwiftUI

/// ⌘J across projects (request r261123-100223, choice next-cross-order).
/// Order: items of a focused chapter (any project, BoardStore.inFocus) first, then this project, then the other projects.
/// Only the user's own move (⌘J, a click) changes the project in the window.
struct NextEntry: Identifiable {
    var id: String { projectId + "|" + step.ref }
    let projectId: String
    let projectName: String
    let step: NextStep
    let focused: Bool
}

extension AppModel {
    /// Everything urgent that waits on you, in every project of the switcher, in ⌘J order.
    func nextAcross() -> [NextEntry] {
        TurnMemo.get("nextAcross:" + (selectedProjectId ?? "")) {
            let here = selectedProjectId
            var all: [NextEntry] = []
            for p in switcherProjects {
                let b = board(for: p)
                for s in nextSteps(p) where s.urgent {
                    all.append(NextEntry(projectId: p.id, projectName: p.name, step: s, focused: b.inFocus(s.ref)))
                }
            }
            func tier(_ e: NextEntry) -> Int { e.focused ? 0 : e.projectId == here ? 1 : 2 }
            let order = Dictionary(uniqueKeysWithValues: switcherProjects.enumerated().map { ($1.id, $0) })
            return all.sorted { a, b in
                if tier(a) != tier(b) { return tier(a) < tier(b) }
                if a.step.score != b.step.score { return a.step.score > b.step.score }
                if (a.projectId == here) != (b.projectId == here) { return a.projectId == here }
                return (order[a.projectId] ?? 99) < (order[b.projectId] ?? 99)
            }
        }
    }

    /// What ⌘J goes to now: the first one not visited in this walk.
    func nextUp() -> NextEntry? {
        let list = nextAcross()
        return list.first { !nextSeen.contains($0.id) } ?? list.first
    }

    /// ⌘J: go to the next thing that waits on you, in whatever project it is (the only way ⌘J changes project).
    func jumpNext() {
        let list = nextAcross()
        guard !list.isEmpty else { return }
        nextSeen.formIntersection(Set(list.map(\.id)))        // drop what is gone
        if list.allSatisfy({ nextSeen.contains($0.id) }) { nextSeen = [] }   // walked them all: start again
        guard let e = list.first(where: { !nextSeen.contains($0.id) }) else { return }
        let i = list.firstIndex { $0.id == e.id } ?? 0
        nextSeen.insert(e.id)
        go(e, position: "\(i + 1)/\(list.count)")
    }

    /// Open one entry (from ⌘J or the list): switch project if it is elsewhere, and say so.
    func go(_ e: NextEntry, position: String? = nil) {
        let moved = e.projectId != selectedProjectId
        let reason = e.step.reason.prefix(1).uppercased() + e.step.reason.dropFirst()
        let head = position.map { "⌘J \($0)" } ?? "⌘J"
        showToast("\(head) · \(moved ? "now in \(e.projectName) · " : "")\(e.focused ? "★ " : "")\(reason)", projectId: e.projectId, ref: e.step.ref)
        if e.step.ref.hasPrefix("session:"), let id = UUID(uuidString: String(e.step.ref.dropFirst(8))) {
            selectedProjectId = e.projectId
            selectedSession[e.projectId] = id; return
        }
        openCombo(projectId: e.projectId, ref: e.step.ref, startNew: false)
    }

    /// The user is typing (a text field or the terminal has the keyboard): don't move the board under them.
    var userIsTyping: Bool {
        guard let r = NSApp.keyWindow?.firstResponder else { return false }
        return r is NSTextView || String(describing: type(of: r)).contains("Terminal")
    }

    /// A Claude session added an item (choice, chapter draft): show it only if it is in the project on screen
    /// and you are not typing. Another project never takes the window (request r261123-100223).
    func revealFromClaude(projectId: String, ref: String) {
        guard projectId == selectedProjectId, !userIsTyping else { return }
        focusItem(projectId: projectId, ref: ref)
    }
}

/// The ⌘J list on hover: grouped Focus · this project · each other project, with each project's icon.
struct NextAcrossList: View {
    @EnvironmentObject var model: AppModel
    var close: () -> Void
    var body: some View {
        let list = model.nextAcross()
        let here = model.selectedProjectId
        let up = model.nextUp()?.id
        let focus = list.filter(\.focused)
        let rest = list.filter { !$0.focused }
        var groups: [(title: String, pid: String?, items: [NextEntry])] = []
        if !focus.isEmpty { groups.append(("★ FOCUS", nil, focus)) }
        var seen: [String] = []
        for e in rest where !seen.contains(e.projectId) { seen.append(e.projectId) }
        for pid in seen {
            let items = rest.filter { $0.projectId == pid }
            groups.append(((items[0].projectName + (pid == here ? " · here" : "")).uppercased(), pid, items))
        }
        return VStack(alignment: .leading, spacing: 2) {
            if list.isEmpty {
                Text("Nothing waits on you").font(.system(size: S(12))).foregroundStyle(Brand.mute).padding(8)
            }
            ForEach(groups, id: \.title) { g in
                HStack(spacing: 6) {
                    if let pid = g.pid, let p = model.projects.first(where: { $0.id == pid }) {
                        PixelAvatar(name: p.name, size: 14, projectId: p.id)
                    }
                    Text(g.title).font(Brand.label(9)).tracking(0.6).foregroundStyle(g.pid == nil ? Brand.amber : Brand.mute)
                }.padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                ForEach(g.items) { e in
                    Button { close(); model.nextSeen.insert(e.id); model.go(e) } label: {
                        HStack(spacing: 8) {
                            if g.pid == nil { PixelAvatar(name: e.projectName, size: 14, projectId: e.projectId) }
                            Text(NextUp.tag(e.step.reason)).font(Brand.label(8)).tracking(0.5).foregroundStyle(Brand.amber)
                                .frame(width: S(52), alignment: .leading)
                            Text(e.step.title).font(.system(size: S(12))).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(e.id == up ? Brand.amber.opacity(0.16) : .clear))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .help("\(e.projectName) · \(e.step.reason)")
                }
            }
            Divider().padding(.top, 4)
            Text("⌘J walks this list · it changes project only when you go")
                .font(.system(size: S(10.5))).foregroundStyle(Brand.mute).padding(.horizontal, 8).padding(.vertical, 4)
        }
        .padding(6).frame(width: S(380))
    }
}
