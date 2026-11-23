import Foundation

/// Where a project is tested: steerify.json → "environments". Sessions put these exact addresses in their
/// To test links, so a link never points at a host Claude guessed (request r261120-150711: a link went to
/// a look-alike of the product's real host).
struct TestEnv: Codable, Hashable {
    var name: String          // "platform", "api", "local"…
    var url: String           // base address, e.g. https://platform.synthetic-brain.com
    var area: String?         // the board area it serves (links of that area start here)
    var note: String?         // e.g. "log in as the demo user"
}

enum TestEnvs {
    static func load(_ boardDir: String) -> [TestEnv] {
        struct M: Codable { var environments: [TestEnv]? }
        let mf = (boardDir as NSString).appendingPathComponent("steerify.json")
        guard let d = FileManager.default.contents(atPath: mf) else { return [] }
        return (try? JSONDecoder().decode(M.self, from: d))?.environments ?? []
    }

    /// One line per environment, for the session's environment (STEERIFY_ENVS) and for error messages.
    static func describe(_ envs: [TestEnv]) -> String {
        envs.map { e in "\(e.name)\(e.area.map { " (\($0))" } ?? ""): \(e.url)" }.joined(separator: "; ")
    }

    static func host(_ s: String) -> String? {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespaces)), let sch = u.scheme?.lowercased(),
              sch == "http" || sch == "https", let h = u.host?.lowercased(), !h.isEmpty else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    static func isLocal(_ h: String) -> Bool {
        h == "localhost" || h == "127.0.0.1" || h == "0.0.0.0" || h.hasSuffix(".local") || h.hasPrefix("192.168.") || h.hasPrefix("10.")
    }

    /// The name part of a domain, spelling-insensitive: platform.acme-corp.com and app.acmecorp.ai
    /// are both "syntheticbrain", so a look-alike host of the same product is caught; github.com is not.
    static func brand(_ h: String) -> String {
        let parts = h.split(separator: ".")
        let label = parts.count >= 2 ? parts[parts.count - 2] : parts.first ?? ""
        return label.filter { $0.isLetter || $0.isNumber }.lowercased()
    }

    /// Problems with the links of a delivery. A link to one of the project's own products (same name as one of
    /// its environments) on a host that is not an environment is wrong; local and outside links (GitHub, docs)
    /// are fine.
    static func problems(tests: [[String: Any]], area: String?, envs: [TestEnv]) -> [String] {
        let known = Set(envs.compactMap { host($0.url) })
        let brands = Set(known.filter { !isLocal($0) }.map(brand))
        guard !brands.isEmpty else { return [] }
        var out: [String] = []
        for (i, t) in tests.enumerated() {
            guard let u = t["url"] as? String, let h = host(u), !isLocal(h), !known.contains(h), brands.contains(brand(h)) else { continue }
            let mates = envs.filter { e in host(e.url).map { !isLocal($0) && brand($0) == brand(h) } ?? false }
            let same = mates.first { $0.area != nil && $0.area == area } ?? (mates.count == 1 ? mates.first : nil)
            out.append("test \(i + 1): \(h) is not one of this project's environments" + (same.map { "; did you mean \($0.url)?" } ?? ""))
        }
        return out
    }

    /// Why a test link does not lead to the feature (nil = it does). The Test it button must open the exact
    /// page / record / item under test, never a home page (request r261120-174139: a test linked to
    /// https://platform.synthetic-brain.com and the user had to find the feature by hand).
    /// Links Steerify can act on (AppModel.handle). Anything else does nothing when clicked.
    static let appActions: Set<String> = ["start", "new", "open", "since"]

    /// A link that does nothing at all when clicked: not a link, or a steerify:// action the app does not have
    /// (request r261121-103305: a test linked to steerify://request showed an enabled Test it that did nothing).
    /// The To test card hides its Test it button for these.
    static func dead(_ s: String) -> Bool {
        let raw = s.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, let u = URL(string: raw), let sch = u.scheme?.lowercased() else { return true }
        guard sch == "steerify" else { return false }
        let action = u.host ?? "", query = u.query ?? ""
        if !appActions.contains(action) { return true }
        if action == "start", !query.contains("item=") { return true }
        return false
    }

    static func generic(_ s: String, envs: [TestEnv] = []) -> String? {
        let raw = s.trimmingCharacters(in: .whitespaces)
        guard let u = URL(string: raw), let sch = u.scheme?.lowercased() else { return "nothing (not a valid link)" }
        let path = u.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let query = u.query ?? "", frag = u.fragment ?? ""
        switch sch {
        case "http", "https":
            guard let h = host(raw) else { return "nothing (not a valid link)" }
            if h == "github.com" || h.hasSuffix(".github.com") {
                return path.split(separator: "/").count <= 2 ? "a repository's front page, not the change" : nil
            }
            // An environment's own base address (with or without the trailing slash) is its home page.
            let bases = envs.compactMap { e -> String? in
                guard let eh = host(e.url), eh == h, let eu = URL(string: e.url) else { return nil }
                return eu.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            if query.isEmpty, frag.isEmpty, path.isEmpty || bases.contains(path) { return "the home page of \(h), not the feature" }
            return nil
        case "steerify":
            let action = u.host ?? ""
            if action.isEmpty { return "Steerify only, not the item" }
            if dead(raw) { return "nothing (Steerify has no \"\(action)\" link that leads to the item)" }
            if action == "open", !query.contains("item="), !query.contains("ref=") { return "the project, not the item" }
            return nil
        case "file":
            return raw.hasSuffix("/") ? "a folder, not the thing to look at" : nil
        default:
            return nil
        }
    }

    /// Links that answer 404 (or a server that does not answer at all) when Steerify tries them now.
    /// 404 → refused; unreachable → a warning (a local dev server may be stopped on purpose).
    static func reach(tests: [[String: Any]]) -> (broken: [String], down: [String]) {
        var broken: [String] = [], down: [String] = []
        for (i, t) in tests.enumerated() {
            guard let s = t["url"] as? String, let h = host(s), let url = URL(string: s) else { continue }
            // GitHub answers 404 to anyone not signed in on a private repo: Steerify cannot tell, so it does not refuse.
            if h == "github.com" || h.hasSuffix(".github.com") { continue }
            var req = URLRequest(url: url, timeoutInterval: 4)
            req.httpMethod = "GET"
            let sem = DispatchSemaphore(value: 0)
            var code: Int? = nil, failed = false
            URLSession.shared.dataTask(with: req) { _, resp, err in
                code = (resp as? HTTPURLResponse)?.statusCode; failed = err != nil && code == nil; sem.signal()
            }.resume()
            if sem.wait(timeout: .now() + 5) == .timedOut { failed = true }
            if code == 404 || code == 410 { broken.append("test \(i + 1): \(s) answers \(code!) (page not found)") }
            else if failed { down.append("test \(i + 1): \(s)") }
        }
        return (broken, down)
    }

    /// file:// URL for a link relative to the board folder (protos/x.html?v=B, img/…), when that file exists.
    /// The skill tells sessions to link prototypes this way; Steerify opens them from the board.
    static func boardFile(_ s: String, board: String) -> String? {
        let raw = s.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, !board.isEmpty, URL(string: raw)?.scheme == nil, !raw.hasPrefix("/") else { return nil }
        let file = String(raw.split(separator: "?", maxSplits: 1).first ?? "").components(separatedBy: "#")[0]
        guard !file.isEmpty, FileManager.default.fileExists(atPath: (board as NSString).appendingPathComponent(file)) else { return nil }
        return MockSnapshots.protoURL(raw, base: URL(fileURLWithPath: board, isDirectory: true)).absoluteString
    }

    /// Outside links in a delivery of a project with no environments yet: Claude must ask, not guess.
    static func unchecked(tests: [[String: Any]]) -> [String] {
        Array(Set(tests.compactMap { ($0["url"] as? String).flatMap(host) }.filter { !isLocal($0) && !$0.hasSuffix("github.com") })).sorted()
    }
}
