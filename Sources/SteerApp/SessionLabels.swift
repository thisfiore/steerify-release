import SwiftUI

// MARK: - Your names and pins for sessions (request r261122-132024: rename and pin a session, shared with the iPhone)
//
// `<board>/session-labels.json`, keyed by the Claude Code conversation id, so a name and a pin survive a restart and a
// resume (the conversation keeps its id):
//   {"steerify": 1, "sessions": {"<claudeId>": {"name": "Pricing page", "pinned": true, "at": "…"}}}
// The Mac is the only writer. The iPhone sees names and pins in the live session list (relay "status": `id`, `pinned`)
// and changes them through its inbox (kinds `sessionName`, `sessionPin`), applied by PhoneInbox.swift with the same code
// as a click here. The file is pushed with the board (BoardPublish) so a phone without the relay still reads it.

@MainActor
enum SessionLabels {
    struct Label { var name: String?; var pinned: Bool }

    static func file(_ boardDir: String) -> String { (boardDir as NSString).appendingPathComponent("session-labels.json") }

    static func load(_ boardDir: String) -> [String: Label] {
        guard let d = FileManager.default.contents(atPath: file(boardDir)),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let all = o["sessions"] as? [String: [String: Any]] else { return [:] }
        return all.mapValues { Label(name: ($0["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }, pinned: $0["pinned"] as? Bool ?? false) }
    }

    /// Write one conversation's label (no name and not pinned = dropped from the file).
    static func save(_ boardDir: String, claudeId: String, _ l: Label) {
        var all: [String: Any] = [:]
        if let d = FileManager.default.contents(atPath: file(boardDir)),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] { all = o["sessions"] as? [String: Any] ?? [:] }
        if l.name == nil && !l.pinned { all[claudeId] = nil } else {
            var e: [String: Any] = ["pinned": l.pinned, "at": BoardStore.now()]
            if let n = l.name { e["name"] = n }
            all[claudeId] = e
        }
        let o: [String: Any] = ["steerify": 1, "sessions": all]
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: URL(fileURLWithPath: file(boardDir)), options: .atomic)
        }
    }

    /// A name typed by you: one line, trimmed, at most 40 characters. Empty = back to Steerify's name.
    static func clean(_ name: String?) -> String? {
        let t = (name ?? "").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(40))
    }
}

@MainActor
extension AppModel {
    /// Sessions just opened or restored take the name and pin saved for their conversation.
    func adoptLabels(_ list: [TerminalSession]) {
        var cache: [String: [String: SessionLabels.Label]] = [:]
        for s in list where !s.labelsAdopted {
            s.labelsAdopted = true
            guard let cid = s.claudeId else { continue }
            let all = cache[s.boardDir] ?? SessionLabels.load(s.boardDir)
            cache[s.boardDir] = all
            guard let l = all[cid] else { continue }
            if s.customName != l.name { s.customName = l.name }
            if s.pinned != l.pinned { s.pinned = l.pinned }
        }
    }

    /// Rename a session (nil or empty = Steerify's name again). Saved for its conversation and sent to the iPhone.
    func renameSession(_ s: TerminalSession, to name: String?) {
        s.customName = SessionLabels.clean(name)
        storeLabel(s)
    }

    func setPinned(_ s: TerminalSession, _ on: Bool) {
        guard s.pinned != on else { return }
        withAnimation(.easeInOut(duration: 0.2)) { s.pinned = on }
        storeLabel(s)
    }

    private func storeLabel(_ s: TerminalSession) {
        if let cid = s.claudeId { SessionLabels.save(s.boardDir, claudeId: cid, .init(name: s.customName, pinned: s.pinned)) }
        objectWillChange.send()
        persistSessions()
        publishStatus()
        scheduleBoardPublish()
    }

    /// From the iPhone (inbox): the session is found by its conversation id, live or not.
    func applyPhoneLabel(projectId: String, boardDir: String, claudeId: String, name: String?? = nil, pinned: Bool? = nil) -> Bool {
        if let s = sessions.first(where: { $0.projectId == projectId && $0.claudeId == claudeId }) {
            if let name { renameSession(s, to: name) }
            if let pinned { setPinned(s, pinned) }
            return true
        }
        // Closed on the Mac meanwhile: keep the label for when it is resumed.
        var l = SessionLabels.load(boardDir)[claudeId] ?? .init(name: nil, pinned: false)
        if let name { l.name = SessionLabels.clean(name) }
        if let pinned { l.pinned = pinned }
        SessionLabels.save(boardDir, claudeId: claudeId, l)
        return true
    }
}

/// Rename in place on the session row: a small field over the name, Return saves, Esc cancels.
struct SessionRenameField: View {
    @EnvironmentObject var model: AppModel
    let session: TerminalSession
    @Binding var editing: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Session name", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: S(12), weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.amber.opacity(0.7)))
            .focused($focused)
            .onAppear { text = session.customName ?? session.title; DispatchQueue.main.async { focused = true } }
            .onSubmit { model.renameSession(session, to: text); editing = false }
            .onExitCommand { editing = false }
            .onChange(of: focused) { _, f in if !f && editing { model.renameSession(session, to: text); editing = false } }
            .help("Return saves · Esc cancels · empty = Steerify's name")
    }
}

// MARK: - Test hook: `--label-demo "<n>=<name>,pin:<n>,close"` (background instances, after --flow-demo)
// Renames / pins the n-th session (1-based, in opening order) with the same code as the menu, then logs the order,
// the saved file and the rows the iPhone gets.
enum SessionLabelsDemo {
    @MainActor static func run(_ m: AppModel, _ arg: String) {
        guard CommandLine.arguments.contains("--background"), let p = m.project else { return }
        let list = m.sessions(of: p.id)
        for part in arg.split(separator: ",").map(String.init) {
            // From the iPhone: phone:<n>=<name> on a live session, closed:<name> on a conversation not open here.
            if part.hasPrefix("phone:"), let eq = part.firstIndex(of: "="), let n = Int(part[part.index(part.startIndex, offsetBy: 6)..<eq]), n >= 1, n <= list.count, let cid = list[n - 1].claudeId {
                _ = m.applyPhoneLabel(projectId: p.id, boardDir: p.boardDir, claudeId: cid, name: .some(String(part[part.index(after: eq)...])))
            } else if part.hasPrefix("closed:") {
                _ = m.applyPhoneLabel(projectId: p.id, boardDir: p.boardDir, claudeId: "closed-demo", name: .some(String(part.dropFirst(7))), pinned: true)
            } else if part.hasPrefix("pin:"), let n = Int(part.dropFirst(4)), n >= 1, n <= list.count { m.setPinned(list[n - 1], true) }
            // close: press "Close N done" (request r261124-081408: pinned sessions must stay open).
            else if part == "close" {
                let t = { (x: [TerminalSession]) in x.map { "\($0.pinned ? "📌" : "")\($0.title)" }.joined(separator: " | ") }
                FileHandle.standardError.write("[labels] close done: \(t(m.wrappedSessions(of: p.id)))\n".data(using: .utf8)!)
                m.closeWrapped(projectId: p.id)
                FileHandle.standardError.write("[labels] left open: \(t(m.sessions(of: p.id)))\n".data(using: .utf8)!)
            }
            else if let eq = part.firstIndex(of: "="), let n = Int(part[..<eq]), n >= 1, n <= list.count { m.renameSession(list[n - 1], to: String(part[part.index(after: eq)...])) }
        }
        let log = { (s: String) in FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
        log("[labels] order: " + m.orderedSessions(of: p.id).map { "\($0.pinned ? "📌" : "")\($0.title)" }.joined(separator: " | "))
        log("[labels] file: " + ((try? String(contentsOfFile: SessionLabels.file(p.boardDir), encoding: .utf8)) ?? "none"))
        for s in m.orderedSessions(of: p.id) { let r = m.phoneRow(s, project: p); log("[labels] phone: name=\(r["name"] ?? "") pinned=\(r["pinned"] ?? "") id=\(r["id"] ?? "")") }
    }
}
