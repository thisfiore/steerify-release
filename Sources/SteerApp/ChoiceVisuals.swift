import Foundation

/// A choice is answered by looking: every option of a non-simple choice must show its result (a prototype, a picture,
/// a high-level mockup or a logical scheme), not words in a box. Checked in `ask_choice` so the session fixes it before the user ever sees it.
enum ChoiceVisuals {
    /// Markup that draws something (a picture, a vector, a background image) rather than only text in boxes.
    static func drawsSomething(_ html: String) -> Bool {
        let h = html.lowercased()
        return ["<img", "<svg", "<canvas", "<video", "url("].contains { h.contains($0) }
    }

    private static func count(_ pattern: String, _ s: String) -> Int {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?
            .numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s)) ?? 0
    }

    /// What a mock shows: a picture, a logical scheme (parts joined by arrows), a high-level mockup
    /// (a laid-out screen: many elements carrying short labels), or only words in a box or two.
    enum Kind: String { case picture, scheme, wireframe, words }
    static func kind(_ html: String) -> Kind {
        if drawsSomething(html) { return .picture }
        let elements = count("<(div|span|section|li|button|p|b|i|s|small|h\\d)\\b", html)
        let nodes = count("class=\"[^\"]*\\b(box|node|step|card)\\b", html)
            + count("style=\"[^\"]*border:\\s*\\d", html)                       // boxes drawn with inline styles
        // a connector stands between parts: an arrow starting its own text run, or an arrow / line element
        // (an arrow inside a box's sentence, "brief → v2", is still words)
        let connectors = count(">\\s*[→←↓↑⟶⇢➜➝↳↘↗]|class=\"[^\"]*\\b(arr|arrow|line|edge)\\b", html)
        if nodes >= 2 && connectors >= 1 { return .scheme }        // parts joined by arrows
        let layout = count("display:\\s*(flex|grid)|grid-template|width:\\s*\\d|height:\\s*\\d|border(-radius)?:|background:", html)
        let text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let perElement = Double(text.count) / Double(max(elements, 1))   // a mockup is many short labels, not prose
        if elements >= 8 && layout >= 4 && perElement <= 25 { return .wireframe }   // laid out with inline styles
        if elements >= 15 && perElement <= 20 { return .wireframe }                 // laid out with the kit's classes
        return .words
    }

    /// nil when fine, otherwise the message for Claude (what is wrong, per option, and how to fix it).
    static func problems(_ d: [String: Any], board: String) -> String? {
        let simpleChoice = d["simple"] as? Bool ?? false
        let fm = FileManager.default
        var out: [String] = []
        for o in d["options"] as? [[String: Any]] ?? [] {
            let id = o["id"] as? String ?? "?"
            for key in ["proto", "shot"] {
                guard let p = o[key] as? String, !p.isEmpty, !p.hasPrefix("http") else { continue }
                let file = String(p.split(separator: "?").first ?? "")
                if !fm.fileExists(atPath: (board as NSString).appendingPathComponent(file)) {
                    out.append("option \(id): \(key) \(file) does not exist in the board folder")
                }
            }
            if simpleChoice || (o["simple"] as? Bool ?? false) { continue }
            if o["proto"] != nil || o["shot"] != nil { continue }
            if kind(o["mock"] as? String ?? "") != .words { continue }
            out.append("option \(id): only words in a box, nothing to look at")
        }
        guard !out.isEmpty else { return nil }
        return "Choice not added: " + out.joined(separator: "; ") + ".\n"
            + "Show what the user would see after picking each option: a live prototype (proto: protos/<id>.html?v=A, "
            + "built with the board's kit/) or a high-level mockup of the screen (a laid-out wireframe in the mock) for "
            + "screens and flows; example pictures (shot: img/choices/<id>-A.png, the same input and what each option "
            + "makes of it) for what a tool does to an image, video, document or export; a logical scheme (steps or "
            + "parts joined by arrows) for how something works. Only a scope / naming / yes-no choice with nothing to "
            + "look at may set simple: true and keep a text mock."
    }
}
