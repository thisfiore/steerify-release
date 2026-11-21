import AppKit
import Foundation

// MARK: - Starts from the iPhone (choice mobile-offline-start: queue by default, cloud on demand)
//
// The iPhone can't run Claude Code. When you press ▶ there, it writes a start into the board's `starts.json`:
//   {"items":[{"id","ref":"road:<slug>"|"track:<slug>"|…,"intent":"plan"|"resume"|…,"note","target":"mac"|"cloud",
//              "at","from":"iphone","state":"queued"}]}
// The Mac starts every queued "mac" start as soon as it sees it: at launch, on wake, and on every board change
// (FSEvents, no polling). So "Mac asleep" simply means "queued until the Mac is back". Each start is marked
// started (with its Claude session) or failed (with why), so the phone can show what happened.
// "cloud" starts are not the Mac's job: the phone sends them to the cloud and the Mac leaves them alone.

enum StartQueue {
    static let fileName = "starts.json"
    static func file(_ boardDir: String) -> String { (boardDir as NSString).appendingPathComponent(fileName) }

    struct Entry { let id: String; let ref: String; let intent: String; let note: String; let target: String; let state: String; let at: String }

    static func load(_ boardDir: String) -> (raw: [String: Any], items: [Entry]) {
        guard let d = FileManager.default.contents(atPath: file(boardDir)),
              let raw = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return ([:], []) }
        let items = (raw["items"] as? [[String: Any]] ?? []).map { i in
            Entry(id: i["id"] as? String ?? "", ref: i["ref"] as? String ?? "", intent: i["intent"] as? String ?? "plan",
                  note: i["note"] as? String ?? "", target: i["target"] as? String ?? "mac", state: i["state"] as? String ?? "queued",
                  at: i["at"] as? String ?? "")
        }
        return (raw, items)
    }

    /// Changes one entry and writes the file back in its own style (2 spaces, as the phone writes it).
    static func update(_ boardDir: String, id: String, _ change: (inout [String: Any]) -> Void) {
        var (raw, _) = load(boardDir)
        var items = raw["items"] as? [[String: Any]] ?? []
        guard let i = items.firstIndex(where: { $0["id"] as? String == id }) else { return }
        change(&items[i])
        raw["items"] = items
        if let d = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: URL(fileURLWithPath: file(boardDir)), options: .atomic)
        }
    }

    static func now() -> String { ISO8601DateFormatter().string(from: Date()) }

    /// Adds one start (from the phone's inbox); the next board reload starts it.
    static func append(_ boardDir: String, _ entry: [String: Any]) {
        var (raw, _) = load(boardDir)
        var items = raw["items"] as? [[String: Any]] ?? []
        if items.contains(where: { $0["id"] as? String == entry["id"] as? String }) { return }
        items.append(entry)
        raw["items"] = items
        if let d = try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? d.write(to: URL(fileURLWithPath: file(boardDir)), options: .atomic)
        }
    }
}

@MainActor
extension AppModel {
    func startStartQueue() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.runStartQueue() }
        }
        NotificationCenter.default.addObserver(forName: .steerifyBoardReloaded, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.runStartQueue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.runStartQueue() }   // sessions restored first
    }

    /// Start every queued Mac start, oldest first. Same rule as scheduled tasks: real sessions only where boards may be written.
    func runStartQueue() {
        guard TaskClock.enabled else { return }
        for p in projects where FileManager.default.fileExists(atPath: StartQueue.file(p.boardDir)) {
            let queued = StartQueue.load(p.boardDir).items.filter { $0.state == "queued" && $0.target == "mac" }.sorted { $0.at < $1.at }
            for e in queued {
                // Mark first: the write below fires another board reload, which must not start it twice.
                StartQueue.update(p.boardDir, id: e.id) { $0["state"] = "starting" }
                guard let ref = ItemRef(ref: e.ref), BoardFiles.resolve(ref, in: p).title != nil else {
                    StartQueue.update(p.boardDir, id: e.id) { $0["state"] = "failed"; $0["why"] = "Not on this board: \(e.ref)" }
                    showToast("Couldn't start from your iPhone: \(e.ref) is not on the board", projectId: p.id)
                    continue
                }
                let intent = Intent(rawValue: e.intent) ?? .plan
                let brief = "Started from the iPhone" + (e.note.isEmpty ? "." : ". The user's note: \(e.note)")
                let s = start(projectId: p.id, item: ref, intent: intent, dry: CommandLine.arguments.contains("--dry-sessions"), extraBrief: brief, focus: false)
                StartQueue.update(p.boardDir, id: e.id) { x in
                    if let s {
                        x["state"] = "started"; x["started"] = StartQueue.now()
                        if let c = s.claudeId { x["session"] = c }
                    } else { x["state"] = "failed"; x["why"] = "No repo for this item on this Mac" }
                }
                let title = BoardFiles.resolve(ref, in: p).title ?? e.ref
                if s != nil {
                    showToast("Started from your iPhone: \(title)", projectId: p.id, ref: e.ref)
                    Notify.send("Started from your iPhone", title)
                } else {
                    showToast("Couldn't start “\(title)” from your iPhone: no repo on this Mac", projectId: p.id, ref: e.ref)
                }
            }
        }
    }
}
