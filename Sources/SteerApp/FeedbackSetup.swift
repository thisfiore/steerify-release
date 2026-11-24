import Foundation

/// MCP `feedback_setup`: what the Feedback standard needs that Claude can't do with files alone (standards/feedback/INSTALL.md).
///   {title?}                → registers the project's inbox on the relay once (secret → Keychain, steerify.json → feedback)
///   {brand?}                → the form, widget and roadmap page in the product's look (logo path → inline image)
///   {areas?, hide?}         → which chapters the public roadmap shows
/// Returns the links, the widget snippet and the endpoint for agents. Safe to call again: it only does what is missing.
enum FeedbackSetup {
    static let relay = "https://relay.steerify.dev"

    static func run(_ a: [String: Any], board: String) -> (String, Bool) {
        let manifest = (board as NSString).appendingPathComponent("steerify.json")
        func load() -> [String: Any] {
            ((FileManager.default.contents(atPath: manifest)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["feedback"] as? [String: Any] ?? [:]
        }
        var fb = load()
        let url = ((fb["url"] as? String) ?? relay).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var done: [String] = []

        // 1. The inbox, once.
        if (fb["inbox"] as? String ?? "").isEmpty {
            let title = (a["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (fb["title"] as? String) ?? URL(fileURLWithPath: board).deletingLastPathComponent().lastPathComponent
            guard let (d, code) = http("POST", url + "/v1/feedback/register", json: ["title": title]), code == 200,
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let slug = o["slug"] as? String, let secret = o["secret"] as? String else {
                return ("Inbox not registered: the relay did not answer (\(url)). Try again in a minute.", true)
            }
            let k = Process(); k.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            k.arguments = ["add-generic-password", "-U", "-s", "steerify-feedback", "-a", slug, "-l", "Steerify feedback · \(title)", "-w", secret]
            k.standardOutput = FileHandle.nullDevice; k.standardError = FileHandle.nullDevice
            try? k.run(); k.waitUntilExit()
            guard k.terminationStatus == 0 else { return ("Inbox \(slug) registered but the secret could not go into the Keychain.", true) }
            fb["inbox"] = slug; fb["title"] = title
            done.append("inbox \(slug) registered")
        }
        let slug = fb["inbox"] as? String ?? ""

        // 2. Public chapters.
        if let areas = a["areas"] as? [String] { fb["areas"] = areas; done.append("public areas: " + areas.joined(separator: ", ")) }
        if let hide = a["hide"] as? [String] { fb["hide"] = hide; done.append("hidden: \(hide.count) words") }

        // 3. The brand: kept in steerify.json (logo as a path) and sent to the relay (logo inline).
        if var brand = a["brand"] as? [String: Any] {
            fb["brand"] = brand
            if let logo = brand["logo"] as? String, !logo.hasPrefix("https:"), !logo.hasPrefix("data:") {
                let f = URL(fileURLWithPath: board).appendingPathComponent(logo)
                let types = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp", "gif": "image/gif", "svg": "image/svg+xml"]
                guard let type = types[f.pathExtension.lowercased()], let d = FileManager.default.contents(atPath: f.path) else {
                    return ("logo: \(logo) not found in the board folder (copy it to img/brand/ first) or not an image", true)
                }
                guard d.count < 280_000 else { return ("logo: \(logo) is \(d.count / 1000) KB; use one under 280 KB (an svg, or a smaller png)", true) }
                brand["logo"] = "data:\(type);base64," + d.base64EncodedString()
            }
            guard let secret = FeedbackInbox.secret(slug) else { return ("No secret for \(slug) in the Keychain: this Mac did not register the inbox.", true) }
            guard let (d, code) = http("PUT", url + "/v1/feedback/\(slug)/brand", json: ["brand": brand], secret: secret), code == 200 else {
                return ("Brand not saved: the relay refused it.", true)
            }
            let kept = (((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["brand"] as? [String: Any])?.keys.sorted() ?? []
            let dropped = brand.keys.filter { !kept.contains($0) }.sorted()
            fb["brand"] = (fb["brand"] as? [String: Any] ?? [:]).filter { kept.contains($0.key) }
            done.append("brand saved (\(kept.joined(separator: ", ")))" + (dropped.isEmpty ? "" : "; dropped as not valid: " + dropped.joined(separator: ", ")))
        }

        let w = JSONFile.edit(manifest, key: "feedback", value: fb)
        if w.1 { return w }
        let lines = [
            done.isEmpty ? "Already set up: \(slug)" : done.map { "✓ " + $0 }.joined(separator: "\n"),
            "",
            "Form (share it):  \(url)/f/\(slug)",
            "Roadmap (public): \(url)/roadmap/\(slug)",
            "Widget:           <script src=\"\(url)/w.js\" data-inbox=\"\(slug)\" defer></script>",
            "Agents / MCP:     POST \(url)/v1/feedback/\(slug)  {kind: bug|feature|question, title, text, page, version, source: person|agent, agent, name, email, context}",
            "Reports land in Ready › New requests (Steerify pulls them when it comes to the front).",
        ]
        return (lines.joined(separator: "\n"), false)
    }

    /// One synchronous request (the MCP server answers one call at a time).
    static func http(_ method: String, _ url: String, json: Any, secret: String? = nil) -> (Data, Int)? {
        guard let u = URL(string: url), let body = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        var r = URLRequest(url: u, timeoutInterval: 30)
        r.httpMethod = method; r.httpBody = body
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Steerify", forHTTPHeaderField: "User-Agent")
        if let secret { r.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization") }
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var out: (Data, Int)?
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            if let d, let h = resp as? HTTPURLResponse { out = (d, h.statusCode) }
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }
}
