import Foundation

// MARK: - Feature names from the chapter titles (choice feature-areas, pick A)
//
// No model: plain words. A chapter's feature is the leading noun phrase of its title (before ":", "→", "·", "+",
// "with", "for"…), at most 3 words, without the project's own name, leading "New/One/Our…" or a version number.
// It is shortened to a phrase another chapter's title starts with ("Boosting Data Room" → Data Room) or to what
// chapters starting with the same word share ("Retouch review", "Retouch suite" → Retouch).

enum FeatureNames {
    struct Grouping { var areas: [SmartAreas.Area]; var items: [String: String]; var also: [String: [String]] }

    static let stop: Set<String> = ["a", "an", "the", "and", "or", "of", "for", "to", "in", "on", "with", "from", "by", "as", "at",
        "via", "into", "one", "every", "next", "new", "small", "its", "your", "my", "our", "their", "this", "that", "is", "are",
        "be", "not", "no", "vs", "about", "after", "before", "across", "without", "using", "than", "&"]
    /// Category words that say nothing about the product: never an area on their own.
    static let generic: Set<String> = ["feature", "development", "design", "testing", "test", "documentation", "doc", "feedback",
        "improvement", "enhancement", "bug", "fixe", "fix", "refinement", "misc", "other", "general", "core", "polish",
        "quality", "change", "update", "stuff", "thing", "work", "item"]
    static let preps: Set<String> = ["with", "for", "in", "via", "using", "from", "on", "to", "into", "without", "across", "as", "of", "by", "at"]
    static let rolling = "fixes & refinements"

    /// Words of a text: letters / digits, with inner - ' (Multi-shot, E-com).
    static func words(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            let inner = (c == "-" || c == "'" || c == "’") && !cur.isEmpty && i + 1 < chars.count && (chars[i + 1].isLetter || chars[i + 1].isNumber)
            if c.isLetter || c.isNumber || inner || (c == "." && !cur.isEmpty && cur.last!.isNumber && i + 1 < chars.count && chars[i + 1].isNumber) {
                cur.append(c)
            } else {
                if !cur.isEmpty { out.append(cur); cur = "" }
                if c == "&" { out.append("&") }
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
    static func stem(_ w: String) -> String {
        let l = w.lowercased()
        return l.count > 4 && l.hasSuffix("s") && !l.hasSuffix("ss") ? String(l.dropLast()) : l
    }
    static func norm(_ ws: [String]) -> [String] { ws.map(stem) }
    static func isVersion(_ w: String) -> Bool {
        w.range(of: #"^v?\d+(\.\d+)*[a-z]?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func contains(_ h: [String], _ k: [String]) -> Int? {
        guard !k.isEmpty, h.count >= k.count else { return nil }
        for i in 0...(h.count - k.count) where Array(h[i..<(i + k.count)]) == k { return i }
        return nil
    }

    /// The leading noun phrase of a chapter title, as written (≤ 3 words).
    static func head(_ title: String, project: Set<String>) -> [String] {
        var t = title.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^\s*\d+[.)]\s*"#, with: "", options: .regularExpression)
        for sep in [":", " → ", " ↔ ", "·", " — ", " – ", " - ", ",", " + ", "=", " × "] {
            if let r = t.range(of: sep) { t = String(t[..<r.lowerBound]) }
        }
        // Split at prepositions: the first part that still has a word in it.
        var parts: [[String]] = [[]]
        for w in words(t) { if preps.contains(w.lowercased()) { parts.append([]) } else { parts[parts.count - 1].append(w) } }
        for p in parts {
            var ws = p.filter { !project.contains($0.lowercased()) }
            while let f = ws.first, stop.contains(f.lowercased()) || isVersion(f) { ws.removeFirst() }
            while let l = ws.last, stop.contains(l.lowercased()) || isVersion(l) { ws.removeLast() }
            // ≤ 3 words, "&" not counted (Research & Inspo, Formats & production standards).
            var n = 0, out: [String] = []
            for w in ws { if w != "&" { n += 1 }; if n > 3 { break }; out.append(w) }
            if !out.isEmpty { return out }
        }
        return []
    }

    static func display(_ ws: [String]) -> String {
        let s = ws.joined(separator: " ").replacingOccurrences(of: " & ", with: " & ")
        guard let f = s.first, f.isLowercase else { return s }
        // iPhone, eBay: a word with a capital inside stays as written.
        if let w = ws.first, w.dropFirst().contains(where: \.isUppercase) { return s }
        return f.uppercased() + s.dropFirst()
    }

    static func group(_ items: [(id: String, text: String, chapter: String)], project: Set<String>) -> Grouping {
        var chapters: [String] = []
        for it in items where !chapters.contains(it.chapter) { chapters.append(it.chapter) }
        var H: [String: [String]] = [:], Hn: [String: [String]] = [:]
        for c in chapters where c.trimmingCharacters(in: .whitespaces).lowercased() != rolling {
            let h = head(c, project: project)
            H[c] = h; Hn[c] = norm(h.filter { $0 != "&" })
        }
        // 1 · Each chapter's feature.
        var feat: [String: [String]] = [:]
        for c in chapters {
            guard let h = Hn[c], !h.isEmpty, !h.allSatisfy({ generic.contains($0) || stop.contains($0) }) else { continue }
            let others = chapters.compactMap { $0 == c ? nil : Hn[$0] }.filter { !$0.isEmpty }
            let inside = others.filter { $0.count < h.count && contains(h, $0) != nil && !$0.allSatisfy { generic.contains($0) } }
            var best = h
            if let longest = inside.max(by: { $0.count < $1.count }) {
                best = longest
            } else if !generic.contains(h[0]) {
                let same = others.filter { $0.first == h[0] }
                for o in same {
                    var k = 0
                    while k < min(best.count, o.count), best[k] == o[k] { k += 1 }
                    best = Array(best.prefix(k))
                }
            }
            feat[c] = best
        }
        var names: [[String]: String] = [:], order: [[String]] = []
        for c in chapters {
            guard let k = feat[c], names[k] == nil, let ws = H[c] else { continue }
            let plain = ws.filter { $0 != "&" }
            guard let i = contains(norm(plain), k) else { continue }
            // Keep "&" between the words it joined (Research & Inspo).
            let first = plain[i], last = plain[i + k.count - 1]
            if let a = ws.firstIndex(of: first), let b = ws[a...].firstIndex(of: last) { names[k] = display(Array(ws[a...b])) }
            else { names[k] = display(Array(plain[i..<(i + k.count)])) }
            order.append(k)
        }
        // 2 · A capitalised name inside a heading that recurs in ≥ 2 titles and ≥ 4 key results (MCP).
        let titleN = chapters.map { norm(words($0.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)).filter { $0 != "&" }) }
        let raw = items.map { words($0.text) }
        let textN = raw.map(norm)
        for c in chapters {
            guard let ws = H[c]?.filter({ $0 != "&" }) else { continue }
            for n in 1...2 where ws.count >= n {
                for i in 0...(ws.count - n) {
                    let g = Array(ws[i..<(i + n)]), k = norm(g)
                    guard names[k] == nil, g.allSatisfy({ $0.first?.isUppercase == true }),
                          !g.contains(where: { stop.contains($0.lowercased()) || generic.contains(stem($0)) }),
                          !names.keys.contains(where: { contains($0, k) != nil }) else { continue }
                    let df = titleN.filter { contains($0, k) != nil }.count
                    let m = textN.filter { contains($0, k) != nil }.count
                    if df >= 2, m >= 4 { names[k] = display(g); order.append(k) }
                }
            }
        }
        let areas = order.map { SmartAreas.Area(key: BoardFiles.slug(names[$0]!), name: names[$0]!) }
        let keyOf = Dictionary(order.enumerated().map { ($0.element, areas[$0.offset].key) }, uniquingKeysWith: { a, _ in a })
        // 3 · Key results: their chapter's feature; the areas their text names are tags too (a single word only when
        // written with a capital, so "video" in a sentence is not the Video area). Without a chapter feature, the
        // first area the text names (any case).
        var out: [String: String] = [:], also: [String: [String]] = [:]
        for (n, it) in items.enumerated() {
            var hits: [(pos: Int, len: Int, key: String, strict: Bool)] = []
            for k in order {
                guard let i = contains(textN[n], k) else { continue }
                // One word counts as a tag when it is an acronym (MCP) or capitalised mid-sentence (not "Video …" at the start).
                let w = raw[n][i], acronym = w.count >= 2 && w == w.uppercased() && w.contains(where: \.isLetter)
                hits.append((i, k.count, keyOf[k]!, k.count > 1 || acronym || (i > 0 && w.first?.isUppercase == true)))
            }
            hits.sort { ($0.pos, -$0.len) < ($1.pos, -$1.len) }
            let own = feat[it.chapter].flatMap { keyOf[$0] } ?? hits.first(where: { $0.len > 1 || $0.strict || $0.key.count >= 6 })?.key
            if let own { out[it.id] = own }
            let tags = hits.filter { $0.strict && $0.key != own }.map(\.key)
            if !tags.isEmpty { also[it.id] = Array(NSOrderedSet(array: tags).array as! [String]) }
        }
        let used = Set(out.values).union(also.values.flatMap { $0 })
        return Grouping(areas: areas.filter { used.contains($0.key) }, items: out, also: also)
    }
}
