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

    /// Outside links in a delivery of a project with no environments yet: Claude must ask, not guess.
    static func unchecked(tests: [[String: Any]]) -> [String] {
        Array(Set(tests.compactMap { ($0["url"] as? String).flatMap(host) }.filter { !isLocal($0) && !$0.hasSuffix("github.com") })).sorted()
    }
}
