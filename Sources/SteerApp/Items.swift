import Foundation

/// A board item a session can start from: `test:<id>`, `choice:<id>`, `road:<slug>`, `req:<id>`.
struct ItemRef: Hashable {
    let kind: String
    let id: String
    var title: String?
    var area: String?

    var ref: String { "\(kind):\(id)" }
    static let kinds = ["test", "choice", "road", "req", "track", "reqs", "release", "request", "setup", "task", "past"]

    init?(ref: String) {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, Self.kinds.contains(parts[0]), !parts[1].isEmpty else { return nil }
        kind = parts[0]; id = parts[1]
    }
}

/// What a session is asked to do with its item. Mirrors the intents of the steerify skill.
enum Intent: String, CaseIterable {
    case fix, release, plan, build, check, look, resume, ship, consolidate, choose, intake
    case tag                      // track:<slug>: Claude proposes core vs extras for every key result (you keep or undo)
    case run                      // task:<id>: reach the task's outcome, hand in the result (Tasks.swift)
    case initialize = "init"     // setup:<project>: Claude reads the project, interviews you, drafts the board
}

/// Reads just enough of a project's board files to title an item and pick the repo to start in.
/// Works on the current board format and on older ones (missing keys are simply skipped).
enum BoardFiles {
    static func json(_ dir: String, _ name: String) -> Any? {
        guard let d = FileManager.default.contents(atPath: (dir as NSString).appendingPathComponent(name)) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    static func slug(_ s: String) -> String {
        // Roadmap ids are slugs of the item text and are compared in loops all over the app: each text is slugged once.
        if let hit = slugs.object(forKey: s as NSString) { return hit as String }
        let out = makeSlug(s)
        slugs.setObject(out as NSString, forKey: s as NSString)
        return out
    }
    private static let slugs: NSCache<NSString, NSString> = { let c = NSCache<NSString, NSString>(); c.countLimit = 20_000; return c }()
    private static func makeSlug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return String(String(kept).split(separator: "-").joined(separator: "-").prefix(48))
    }

    /// Fills title + area from the board, if the item exists.
    static func resolve(_ ref: ItemRef, in project: Project) -> ItemRef {
        var r = ref
        let board = json(project.boardDir, "board.json") as? [String: Any] ?? [:]
        switch ref.kind {
        case "test":
            let del = json(project.boardDir, "delivered.json")
            let items = (del as? [String: Any])?["items"] as? [[String: Any]] ?? (del as? [[String: Any]] ?? [])
            if let it = items.first(where: { $0["id"] as? String == ref.id }) {
                r.title = it["title"] as? String; r.area = it["area"] as? String
            }
        case "choice":
            if let d = (board["decisions"] as? [[String: Any]])?.first(where: { $0["id"] as? String == ref.id }) {
                r.title = d["title"] as? String; r.area = (d["areas"] as? [String])?.first
            }
        case "road":
            for t in board["tracks"] as? [[String: Any]] ?? [] {
                for item in t["items"] as? [[Any]] ?? [] {
                    if let text = item.first as? String, slug(text) == ref.id {
                        r.title = text; r.area = t["area"] as? String
                        if let a = (item.count > 2 ? item[2] as? [String: Any] : nil)?["area"] as? String, !a.isEmpty { r.area = a }
                    }
                }
            }
        case "release":
            r.title = "Release: " + project.name
        case "setup":
            r.title = "Setup: " + project.name
        case "task":
            if let t = TaskStore.load(project.boardDir).tasks.first(where: { $0.id == ref.id }) { r.title = t.title; r.area = t.area }
        case "request":
            if let q = RequestLog.load(project.boardDir).first(where: { $0.id == ref.id }) { r.title = "Request: " + (q.title ?? q.short); r.area = q.area }
        case "track":
            if let t = (board["tracks"] as? [[String: Any]] ?? []).first(where: { slug(str($0["name"])) == ref.id }) {
                r.title = "Chapter: " + str(t["name"]); r.area = t["area"] as? String
            }
        case "reqs":
            if let g = (board["requirements"] as? [[String: Any]] ?? []).first(where: { slug(str($0["h"])) == ref.id }) {
                r.title = "Requirements: " + str(g["h"]); r.area = g["area"] as? String
            }
        case "req":
            for g in board["requirements"] as? [[String: Any]] ?? [] {
                if let it = (g["items"] as? [[String: Any]])?.first(where: { $0["id"] as? String == ref.id }) {
                    r.title = it["text"] as? String; r.area = g["area"] as? String
                }
            }
        default: break
        }
        return r
    }

    /// The repo of the item's area (board.json areas[area].repo), else the project's first repo.
    static func repo(for area: String?, in project: Project) -> Repo? {
        if let area, let r = project.repos.first(where: { $0.areas.contains(area) && $0.exists }) { return r }
        if let area,
           let areas = (json(project.boardDir, "board.json") as? [String: Any])?["areas"] as? [String: Any],
           let name = (areas[area] as? [String: Any])?["repo"] as? String,
           let r = project.repos.first(where: { $0.name == name }) {
            return r
        }
        return project.repos.first
    }
}


private func str(_ v: Any?) -> String { (v as? String) ?? (v.map { "\($0)" } ?? "") }
