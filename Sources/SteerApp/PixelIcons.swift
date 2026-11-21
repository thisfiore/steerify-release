import SwiftUI
import NaturalLanguage
import FoundationModels

/// A hand-drawn 10×10 pixel icon set, each with the words that describe it and a colour.
enum PixelArt {
    struct Icon { let rows: [String]; let words: [String]; let color: Color; let boost: Double }

    static let icons: [String: Icon] = [
        "bug": .init(rows: ["..#....#..", "...#..#...", "..######..", ".#.####.#.", "#.######.#", "..######..", ".#.####.#.", "#..####..#", "...####...", ".#..##..#."],
                     words: ["bug", "error", "crash", "fix", "broken", "issue"], color: Color(hex: 0xf87171), boost: 0.25),
        "image": .init(rows: ["##########", "#........#", "#.##.....#", "#.##...#.#", "#.....###.", "#....####.", "#.#.######", "#########.", "#........#", "##########"],
                       words: ["image", "photo", "picture", "shot", "visual", "gallery", "still"], color: Color(hex: 0x8fb0ff), boost: 0),
        "film": .init(rows: ["##########", "#.#....#.#", "##########", "#........#", "#...#....#", "#...##...#", "#...#....#", "##########", "#.#....#.#", "##########"],
                      words: ["video", "film", "movie", "reel", "clip", "seedance", "kling"], color: Color(hex: 0xc4a7ff), boost: 0),
        "mail": .init(rows: ["..........", "##########", "##......##", "#.#....#.#", "#..#..#..#", "#...##...#", "#........#", "#........#", "##########", ".........."],
                      words: ["email", "mail", "newsletter", "outreach", "inbox"], color: Color(hex: 0xffd27a), boost: 0),
        "money": .init(rows: ["....##....", "..######..", ".##.##.##.", ".##.##....", "..######..", "....##.##.", ".##.##.##.", "..######..", "....##....", ".........."],
                       words: ["money", "price", "cost", "invoice", "billing", "payment", "budget", "euro"], color: Color(hex: 0x4ade80), boost: 0),
        "chart": .init(rows: ["#.........", "#.......#.", "#......##.", "#...#..##.", "#..##.###.", "#..######.", "#.#######.", "#.#######.", "#.........", "##########"],
                       words: ["chart", "analytics", "data", "metrics", "report", "funnel", "okr", "stats"], color: Color(hex: 0x4ade80), boost: 0),
        "search": .init(rows: ["..####....", ".#....#...", "#......#..", "#......#..", "#......#..", ".#....#...", "..#####...", "......##..", ".......##.", "........##"],
                        words: ["search", "find", "research", "discover", "lookup", "match"], color: Color(hex: 0xf2e8cf), boost: 0),
        "lock": .init(rows: ["...####...", "..#....#..", "..#....#..", "..#....#..", ".########.", ".###..###.", ".###..###.", ".####.###.", ".########.", ".........."],
                      words: ["auth", "login", "password", "security", "permission", "access", "token"], color: Color(hex: 0xffb020), boost: 0),
        "server": .init(rows: ["##########", "#.#......#", "##########", "..........", "##########", "#.#......#", "##########", "..........", "##########", "#.#......#"],
                        words: ["server", "api", "backend", "deploy", "worker", "queue", "database", "infra"], color: Color(hex: 0x8fb0ff), boost: 0),
        "phone": .init(rows: ["..######..", "..#....#..", "..#....#..", "..#....#..", "..#....#..", "..#....#..", "..#....#..", "..#....#..", "..#.##.#..", "..######.."],
                       words: ["mobile", "phone", "app", "ios", "android", "device"], color: Color(hex: 0xf2e8cf), boost: 0),
        "globe": .init(rows: ["...####...", "..#.##.#..", ".#..##..#.", "##########", "#...##...#", "#...##...#", "##########", ".#..##..#.", "..#.##.#..", "...####..."],
                       words: ["website", "web", "landing", "site", "domain", "seo", "page"], color: Color(hex: 0x8fb0ff), boost: 0),
        "palette": .init(rows: ["...#####..", "..#.....#.", ".#.#..#..#", "#........#", "#.#......#", "#.....##.#", ".#...#..#.", "..#..#.#..", "...####...", ".........."],
                         words: ["design", "ui", "style", "colour", "color", "brand", "look", "layout", "pixel"], color: Color(hex: 0xff8fa0), boost: 0),
        "ship": .init(rows: ["....#.....", "....##....", "....###...", "....####..", "....#.....", "##########", ".########.", "..######..", "~.~.~.~.~.", ".........."],
                      words: ["release", "ship", "deploy", "launch", "live", "publish"], color: Color(hex: 0xD97757), boost: 0.1),
        "gear": .init(rows: ["....##....", ".#.####.#.", "..######..", ".###..###.", "####..####", "####..####", ".###..###.", "..######..", ".#.####.#.", "....##...."],
                      words: ["settings", "config", "setup", "automation", "engine", "process"], color: Color(hex: 0xa0a0a0), boost: 0),
        "terminal": .init(rows: ["##########", "#........#", "#.#......#", "#..#.....#", "#.#..###.#", "#........#", "##########", "..........", "..........", ".........."],
                          words: ["session", "terminal", "cli", "shell", "mcp", "command", "skill"], color: Color(hex: 0xffb020), boost: 0),
        "robot": .init(rows: ["....##....", "....#.....", ".########.", ".#......#.", ".#.#..#.#.", ".#......#.", ".#.####.#.", ".########.", "#.######.#", "..#....#.."],
                       words: ["ai", "model", "agent", "claude", "llm", "local", "inference"], color: Color(hex: 0xD97757), boost: 0),
        "sparkle": .init(rows: ["....#.....", "....#.....", "...###....", "#########.", "...###..#.", "....#..###", "....#...#.", "..........", ".#........", "###......."],
                         words: ["magic", "new", "idea", "feature", "generate", "creative", "inspiration"], color: Color(hex: 0xffd27a), boost: -0.05),
        "users": .init(rows: ["..##..##..", ".####.###.", ".####.###.", "..##..##..", "..........", ".####.####", "######.###", "######.###", "..........", ".........."],
                       words: ["team", "people", "users", "casting", "model", "partner", "client", "lead", "crm"], color: Color(hex: 0xf2e8cf), boost: 0),
        "doc": .init(rows: ["######....", "#....##...", "#....#.#..", "#....####.", "#.####..#.", "#.......#.", "#.#####.#.", "#.......#.", "#.####..#.", "#########."],
                     words: ["document", "requirement", "spec", "contract", "brief", "notes", "article"], color: Color(hex: 0xc4a7ff), boost: 0),
        "map": .init(rows: ["#..##..##.", "##.##.###.", "#.###.#.#.", "#.#.###.#.", "#.#..##.#.", "#.##.#..#.", "###..##.#.", "##.##.###.", "#..##..##.", ".........."],
                     words: ["roadmap", "plan", "planner", "chapter", "schedule", "strategy"], color: Color(hex: 0x4ade80), boost: 0),
        "flask": .init(rows: ["...####...", "....##....", "....##....", "....##....", "...#..#...", "..#....#..", ".#.####.#.", "#.######.#", "#.######.#", ".########."],
                       words: ["test", "qa", "check", "bench", "experiment", "trial", "review"], color: Color(hex: 0x8fb0ff), boost: 0.05),
        "shirt": .init(rows: ["..##..##..", ".###..###.", "##########", "##.####.##", "#..####..#", "...####...", "...####...", "...####...", "...####...", "...####..."],
                       words: ["fashion", "garment", "clothes", "retouch", "ecommerce", "product", "look", "collection", "wholesale"], color: Color(hex: 0xff8fa0), boost: 0),
        "cart": .init(rows: ["#.........", "##########", ".#.......#", ".#......#.", ".########.", ".#........", ".#########", "..........", "..#....#..", ".###..###."],
                      words: ["shop", "store", "cart", "order", "sales", "deal", "quote", "offer"], color: Color(hex: 0x4ade80), boost: 0),
        "bell": .init(rows: ["....##....", "...####...", "..######..", "..######..", "..######..", ".########.", "##########", "..........", "....##....", ".........."],
                      words: ["notification", "alert", "reminder", "notify", "ping", "toast"], color: Color(hex: 0xffb020), boost: 0),
        "book": .init(rows: ["####.####.", "#..#.#..#.", "#.##.##.#.", "#..#.#..#.", "#.##.##.#.", "#..#.#..#.", "#.##.##.#.", "#..#.#..#.", "####.####.", "....#....."],
                      words: ["tutorial", "training", "docs", "guide", "course", "learn", "lesson"], color: Color(hex: 0xffd27a), boost: 0),
        "bolt": .init(rows: [".....###..", "....###...", "...###....", "..######..", "....###...", "...###....", "..###.....", ".##.......", ".#........", ".........."],
                      words: ["performance", "fast", "speed", "cache", "flash", "quick", "optimize"], color: Color(hex: 0xffb020), boost: 0),
        "grid": .init(rows: ["###.###.##", "###.###.##", "###.###.##", "..........", "###.###.##", "###.###.##", "###.###.##", "..........", "###.###.##", "###.###.##"],
                      words: ["board", "grid", "dashboard", "format", "template", "slides", "presentation", "deck"], color: Color(hex: 0xc4a7ff), boost: 0),
        "megaphone": .init(rows: ["........#.", "......###.", "....#####.", "#.#######.", "#########.", "#.#######.", "..#.#####.", "..#...###.", "..##....#.", ".........."],
                           words: ["marketing", "campaign", "announce", "social", "instagram", "ads", "advertising"], color: Color(hex: 0xff8fa0), boost: 0),
        "cube": .init(rows: ["....##....", "..##..##..", "##......##", "#.##..##.#", "#...##...#", "#...#....#", "#...#....#", "##..#...##", "..##.###..", "....##...."],
                      words: ["package", "build", "app", "mac", "native", "swift", "bundle"], color: Color(hex: 0xf2e8cf), boost: 0),
    ]

    // MARK: Picking with Apple's on-device word model (NaturalLanguage), cached

    private static let embedding = NLEmbedding.wordEmbedding(for: .english)
    private static var cache: [String: String] = load()
    private static let cacheFile = ProjectStore.dir.appendingPathComponent("icons.json")
    private static let stop: Set<String> = ["the", "and", "for", "with", "from", "this", "that", "into", "per", "via", "new", "steerify", "nov", "one"]

    /// The icon that best fits a title ("Multi-shot on prod: 5 bugs" → bug). Instant after the first time.
    static func pick(_ title: String) -> String {
        if let c = cache[title] { return c }
        let words = title.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count > 2 && !stop.contains($0) }
        var best = ("sparkle", 9.0)
        for (name, icon) in icons {
            var score = 9.0
            for w in words {
                for form in Set([w, w.hasSuffix("s") ? String(w.dropLast()) : w, w.hasSuffix("es") ? String(w.dropLast(2)) : w]) {
                    for k in icon.words {
                        if form == k { score = min(score, 0) }
                        else if let e = embedding, e.contains(form), e.contains(k) { score = min(score, e.distance(between: form, and: k)) }
                    }
                }
            }
            score -= icon.boost
            if score < best.1 { best = (name, score) }
        }
        let name = best.1 < 0.95 ? best.0 : "sparkle"
        cache[title] = name
        save()
        return name
    }

    /// Apple Intelligence's on-device model, when it is on and ready: reads the whole title and picks from the set.
    /// Falls back silently (word model) on Macs without it. Results are cached like the rest.
    /// What is already known for this title (Apple Intelligence's pick, else the word model's), without working anything out.
    static func cached(_ title: String) -> String? { cache["ai|" + title] ?? cache[title] }
    /// Titles Apple Intelligence was already asked about without a usable answer (this run): not asked again on every appear.
    private static var refused = Set<String>()
    static func refine(_ title: String) async -> String? {
        if let c = cache["ai|" + title] { return c }
        if refused.contains(title) { return nil }
        refused.insert(title)
        guard #available(macOS 26, *), case .available = SystemLanguageModel.default.availability else { return nil }
        let names = icons.keys.sorted()
        let list = names.map { "\($0): \(icons[$0]!.words.prefix(4).joined(separator: ", "))" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: "You pick one icon for a software task. Answer with the icon name only, nothing else.")
        guard let r = try? await session.respond(to: "Icons:\n\(list)\n\nTask: \(title)\nIcon:") else { return nil }
        let answer = r.content.lowercased()
        guard let hit = names.first(where: { answer.contains($0) }) else { return nil }
        await MainActor.run { cache["ai|" + title] = hit; save() }
        return hit
    }

    private static func load() -> [String: String] {
        (try? Data(contentsOf: ProjectStore.dir.appendingPathComponent("icons.json"))).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }
    private static var saving = false
    private static func save() {
        guard !saving else { return }
        saving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            saving = false
            if let d = try? JSONEncoder().encode(cache) { try? d.write(to: cacheFile, options: .atomic) }
        }
    }
}

/// Draws a PixelArt icon in its colour, on an optional dark tile.
struct ArtIcon: View {
    let name: String
    var size: CGFloat = 16
    var tile = false
    var body: some View {
        let icon = PixelArt.icons[name] ?? PixelArt.icons["sparkle"]!
        Canvas { ctx, sz in
            let inset = tile ? sz.width * 0.16 : 0
            let n = CGFloat(max(icon.rows.count, icon.rows.map(\.count).max() ?? 1))
            let cell = (sz.width - 2 * inset) / n
            for (y, row) in icon.rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    ctx.fill(Path(CGRect(x: inset + CGFloat(x) * cell, y: inset + CGFloat(y) * cell, width: cell * 0.92, height: cell * 0.92)), with: .color(icon.color))
                }
            }
        }
        .frame(width: size, height: size)
        .background { if tile { RoundedRectangle(cornerRadius: size * 0.22).fill(icon.color.opacity(0.12)).overlay(RoundedRectangle(cornerRadius: size * 0.22).stroke(icon.color.opacity(0.35))) } }
    }
}

/// Icon for anything with a title.
struct AutoIcon: View {
    let title: String
    var size: CGFloat = 16
    var tile = false
    @State private var name: String?
    var body: some View {
        ArtIcon(name: name ?? PixelArt.cached(title) ?? "sparkle", size: size, tile: tile)
            .task(id: title) {
                // Only set when it changes: a row scrolling back into view must not redraw for the same icon.
                let now = PixelArt.cached(title) ?? PixelArt.pick(title)                  // instant: remembered, else word model
                if name != now { name = now }
                if let better = await PixelArt.refine(title), better != name { name = better }  // Apple Intelligence, when ready
            }
    }
}
