import SwiftUI
import AppKit
import ImageIO

// Project icons: the favicon of one of the project's repos, pixelated on a tile in its brand colours
// (choice "project-icon-style" A). Found locally, no network, no setup. No favicon → today's pixel initials.
// Your own choice (initials, a picture, colours) lives in steerify.json → "icon", with the picture in the
// board's img/project-icon.png, so a teammate sees the same icon.

/// steerify.json → "icon". Absent = automatic (favicon if there is one).
struct IconConfig: Codable, Hashable {
    /// "initials" | "image" (img below) | nil = automatic
    var mode: String?
    /// Picture relative to the board folder (img/project-icon.png).
    var img: String?
    /// Two tile colours, "#rrggbb".
    var colors: [String]?
}

struct RGBA: Hashable {
    var r, g, b, a: Double
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    var hsb: (h: Double, s: Double, v: Double) {
        let ns = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        return (Double(ns.hueComponent), Double(ns.saturationComponent), Double(ns.brightnessComponent))
    }
    func dist(_ o: RGBA) -> Double { (abs(r - o.r) + abs(g - o.g) + abs(b - o.b)) * 255 / 3 }
    static func hsb(_ h: Double, _ s: Double, _ v: Double) -> RGBA {
        let ns = NSColor(hue: h, saturation: max(0, min(1, s)), brightness: max(0, min(1, v)), alpha: 1).usingColorSpace(.sRGB)!
        return RGBA(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent), a: 1)
    }
    init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(r: Double((v >> 16) & 0xff) / 255, g: Double((v >> 8) & 0xff) / 255, b: Double(v & 0xff) / 255, a: 1)
    }
    var hex: String { String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }
    init(_ c: Color) {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .gray
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent), a: 1)
    }
}

/// A square grid of pixels; nil = transparent (the tile shows through).
struct PixelGrid: Hashable {
    let n: Int
    let px: [RGBA?]
}

/// What a project's avatar shows.
struct ProjectIconLook: Hashable {
    /// 8×8 for small tiles (≤ 32 pt), 12×12 for bigger ones. nil = pixel initials.
    var small: PixelGrid?
    var large: PixelGrid?
    var colors: (RGBA, RGBA)?
    /// Where it came from, for the Projects window: "SB-website/public/favicon@3x.png", "your picture", "initials".
    var source: String
    /// The source picture at 128 px, what the board keeps (img/project-icon.png).
    var picture: CGImage?
    /// The tile colours come from the brand (false: neutral grey, nothing colourful found).
    var branded = false

    static func == (a: Self, b: Self) -> Bool { a.small == b.small && a.large == b.large && a.source == b.source && a.colors?.0 == b.colors?.0 && a.colors?.1 == b.colors?.1 }
    func hash(into h: inout Hasher) { h.combine(source); h.combine(small) }
}

/// Icons of every project, worked out in the background when the project list or a steerify.json changes.
@MainActor
final class ProjectIcons: ObservableObject {
    static let shared = ProjectIcons()
    @Published private(set) var looks: [String: ProjectIconLook] = [:]
    private var keys: [String: String] = [:]

    func look(_ projectId: String?) -> ProjectIconLook? { projectId.flatMap { looks[$0] } }

    func refresh(_ projects: [Project], force: Bool = false) {
        for p in projects {
            let key = "\(p.icon.map { "\($0.mode ?? "")|\($0.img ?? "")|\(($0.colors ?? []).joined())" } ?? "auto")|\(p.repos.map(\.path).joined(separator: ","))|\(p.boardDir)"
            if !force, keys[p.id] == key { continue }
            keys[p.id] = key
            let proj = p
            Task.detached(priority: .utility) {
                let look = IconMaker.look(for: proj)
                await MainActor.run { ProjectIcons.shared.looks[proj.id] = look }
            }
        }
    }
}

enum IconMaker {
    // MARK: Look

    static func look(for p: Project) -> ProjectIconLook {
        let cfg = p.icon
        let custom = (cfg?.colors ?? []).compactMap(RGBA.init(hex:))
        let fixed = custom.count >= 2 ? (custom[0], custom[1]) : custom.count == 1 ? (custom[0], darker(custom[0])) : nil
        if cfg?.mode == "initials" {
            return ProjectIconLook(colors: fixed, source: "initials")
        }
        var all: [(path: String, label: String, theme: [RGBA])] = []
        if let img = cfg?.img {
            let path = URL(fileURLWithPath: img, relativeTo: URL(fileURLWithPath: p.boardDir, isDirectory: true)).standardizedFileURL.path
            all = [(path, "your picture", [])]
        } else {
            all = FaviconFinder.ranked(p.repos)
        }
        guard let k = all.firstIndex(where: { loadImage($0.path) != nil }), let src = loadImage(all[k].path),
              var made = make(src, theme: all[k].theme) else {
            return ProjectIconLook(colors: fixed, source: "initials")
        }
        let f = all[k]
        // A white or black mark with no colour of its own: take the brand colour from the project's other favicons.
        if !made.branded && fixed == nil {
            for o in all.dropFirst(k + 1).prefix(6) {
                guard let img = loadImage(o.path), let l = make(img, theme: o.theme), l.branded, let c = l.colors else { continue }
                if let again = make(src, theme: all[k].theme, extra: [c.0, c.1]) { made = again }
                break
            }
        }
        made.source = f.label
        if let fixed { made.colors = fixed }
        return made
    }

    static func loadImage(_ path: String) -> CGImage? {
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        var r = CGRect(origin: .zero, size: img.size)
        if let cg = img.cgImage(forProposedRect: &r, context: nil, hints: [.ctm: AffineTransform(scale: max(1, 128 / max(1, img.size.width)))]) { return cg }
        return nil
    }

    // MARK: Pixelate

    /// RGBA8 pixels of `img` drawn into side×side (un-premultiplied, 0…1).
    static func pixels(_ img: CGImage, side: Int, crop: CGRect? = nil) -> [RGBA] {
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .high
            ctx.draw(crop.flatMap { img.cropping(to: $0) } ?? img, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return (0..<(side * side)).map { i in
            let a = Double(buf[i * 4 + 3]) / 255
            guard a > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
            return RGBA(r: min(1, Double(buf[i * 4]) / 255 / a), g: min(1, Double(buf[i * 4 + 1]) / 255 / a), b: min(1, Double(buf[i * 4 + 2]) / 255 / a), a: a)
        }
    }

    static func image(_ px: [RGBA], side: Int) -> CGImage? {
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        for (i, p) in px.enumerated() {
            buf[i * 4] = UInt8((p.r * p.a * 255).rounded()); buf[i * 4 + 1] = UInt8((p.g * p.a * 255).rounded())
            buf[i * 4 + 2] = UInt8((p.b * p.a * 255).rounded()); buf[i * 4 + 3] = UInt8((p.a * 255).rounded())
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        return buf.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// Clean the favicon (plain background keyed out, empty margins cropped), pixelate it, pick the tile colours.
    static func make(_ src: CGImage, theme: [RGBA], extra: [RGBA] = []) -> ProjectIconLook? {
        let S = 128
        var px = pixels(src, side: S)
        guard px.contains(where: { $0.a > 0.1 }) else { return nil }
        let original = image(px, side: S)   // what the board keeps: processing it again gives the same icon

        // 1. A plain background (a square, or an app-icon plate inside a transparent margin): find the first
        //    solid pixels met coming in from the edges; if they are one colour, key that colour out.
        var keyed: RGBA?
        let ring = Array(Set((0..<S).flatMap { [$0, (S - 1) * S + $0, $0 * S, $0 * S + S - 1] }))
        func flood(_ pass: (RGBA) -> Bool, _ hit: (Int) -> Void) -> [Bool] {
            var seen = [Bool](repeating: false, count: S * S), filled = seen, stack = ring
            while let i = stack.popLast() {
                if seen[i] { continue }; seen[i] = true
                guard pass(px[i]) else { hit(i); continue }
                filled[i] = true
                let x = i % S, y = i / S
                if x > 0 { stack.append(i - 1) }; if x < S - 1 { stack.append(i + 1) }
                if y > 0 { stack.append(i - S) }; if y < S - 1 { stack.append(i + S) }
            }
            return filled
        }
        var edge: [RGBA] = []
        _ = flood({ $0.a < 0.6 }) { i in edge.append(px[i]) }   // anti-aliased rims let the scan through
        if edge.count > S {
            let n = Double(edge.count)
            let avg = RGBA(r: edge.map(\.r).reduce(0, +) / n, g: edge.map(\.g).reduce(0, +) / n, b: edge.map(\.b).reduce(0, +) / n, a: 1)
            if Double(edge.filter({ $0.dist(avg) < 34 }).count) > n * 0.85 {
                let gone = flood({ $0.a < 0.6 || $0.dist(avg) < 46 }) { _ in }
                var out = px
                // the background showing through holes in the mark goes too (it is negative space)
                for i in 0..<(S * S) where gone[i] || px[i].dist(avg) < 30 { out[i].a = 0 }
                // A solid shape with nothing inside (a plain dot): keep it as it is.
                if out.filter({ $0.a > 0.5 }).count > S * S / 25 { px = out; keyed = avg }
            }
        }

        // 2. Crop to what is drawn, as a centred square with a 1 px margin.
        var minX = S, minY = S, maxX = -1, maxY = -1
        for i in 0..<(S * S) where px[i].a > 0.1 {
            minX = min(minX, i % S); maxX = max(maxX, i % S); minY = min(minY, i / S); maxY = max(maxY, i / S)
        }
        guard maxX >= 0 else { return nil }
        let side = min(S, max(maxX - minX, maxY - minY) + 3)
        let cx = (minX + maxX + 1) / 2, cy = (minY + maxY + 1) / 2
        let ox = max(0, min(S - side, cx - side / 2)), oy = max(0, min(S - side, cy - side / 2))
        let picture = original

        // 3. Pixelate with a box filter: each cell is the average of what it covers; enough ink → one solid
        //    pixel, too little → empty. Thin strokes survive, nothing is blurred.
        func grid(_ n: Int, ink: Double) -> PixelGrid {
            var cells: [RGBA?] = []
            for cy in 0..<n {
                for cx in 0..<n {
                    let x0 = ox + cx * side / n, x1 = max(x0 + 1, ox + (cx + 1) * side / n)
                    let y0 = oy + cy * side / n, y1 = max(y0 + 1, oy + (cy + 1) * side / n)
                    var a = 0.0, r = 0.0, g = 0.0, b = 0.0, k = 0.0
                    for y in y0..<min(y1, S) { for x in x0..<min(x1, S) {
                        let p = px[y * S + x]; k += 1
                        a += p.a; r += p.r * p.a; g += p.g * p.a; b += p.b * p.a
                    } }
                    cells.append(k == 0 || a / k < ink ? nil : RGBA(r: r / a, g: g / a, b: b / a, a: 1))
                }
            }
            return PixelGrid(n: n, px: cells)
        }
        let small = grid(8, ink: 0.3), large = grid(12, ink: 0.35)

        // 4. Tile colours: the manifest's theme colour, the keyed-out background, the favicon's own colours.
        let drawn = px.filter { $0.a > 0.5 }
        var cands: [RGBA] = []
        // the icon's own background is its brand colour, unless it is plain white or black
        // the icon's own background is its brand colour (a tint counts: cream, sand); plain black/grey/white don't
        let tinted = { (c: RGBA) in isBrand(c) || (c.hsb.s > 0.06 && c.hsb.v > 0.15 && c.hsb.v < 0.99) }
        if let keyed, tinted(keyed) { cands.append(keyed) }
        cands = theme.filter(isBrand) + cands + dominant(drawn) + extra
        let branded = !cands.isEmpty
        // a plain dark plate (an app icon) still belongs to the look, after the brand colours
        if let keyed, !tinted(keyed), !(keyed.hsb.s < 0.06 && keyed.hsb.v > 0.9) { cands.append(keyed) }
        var c1 = cands.first ?? RGBA(r: 0.17, g: 0.18, b: 0.22, a: 1)
        var c2 = cands.dropFirst().first { hueGap($0, c1) > 0.06 } ?? darker(c1)
        // The icon must stand out from the tile: same brightness → darken (or lighten) the tile.
        let li = drawn.isEmpty ? 1 : drawn.map(\.luminance).reduce(0, +) / Double(drawn.count)
        let lt = (c1.luminance + c2.luminance) / 2
        if abs(li - lt) < 0.28 {
            if li > 0.45 { c1 = shade(c1, v: 0.42); c2 = shade(c2, v: 0.26) }
            else { c1 = shade(c1, v: 0.95, s: 0.35); c2 = shade(c2, v: 0.78, s: 0.45) }
        }
        return ProjectIconLook(small: small, large: large, colors: (c1, c2), source: "", picture: picture, branded: branded)
    }

    static func isBrand(_ c: RGBA) -> Bool { let h = c.hsb; return h.s > 0.28 && h.v > 0.22 }
    static func hueGap(_ a: RGBA, _ b: RGBA) -> Double { let d = abs(a.hsb.h - b.hsb.h); return min(d, 1 - d) }
    static func darker(_ c: RGBA) -> RGBA { let h = c.hsb; return .hsb((h.h + 0.03).truncatingRemainder(dividingBy: 1), min(1, h.s * 1.1), h.v * 0.58) }
    static func shade(_ c: RGBA, v: Double, s: Double? = nil) -> RGBA { let h = c.hsb; return .hsb(h.h, s.map { min(h.s, $0) } ?? h.s, v) }

    /// The favicon's main colours, most present first (only saturated ones; greys don't make a brand).
    static func dominant(_ px: [RGBA]) -> [RGBA] {
        var buckets: [Int: (w: Double, r: Double, g: Double, b: Double)] = [:]
        for p in px {
            let h = p.hsb
            guard h.s > 0.28, h.v > 0.22 else { continue }
            let k = Int(h.h * 12) % 12, w = h.s * h.v
            var e = buckets[k] ?? (0, 0, 0, 0)
            e.w += w; e.r += p.r * w; e.g += p.g * w; e.b += p.b * w
            buckets[k] = e
        }
        let top = buckets.values.sorted { $0.w > $1.w }
        guard let best = top.first else { return [] }
        return top.filter { $0.w > best.w * 0.2 }.prefix(2).map { RGBA(r: $0.r / $0.w, g: $0.g / $0.w, b: $0.b / $0.w, a: 1) }
    }

    /// The board's copy of a picture: img/project-icon.png, 128 px.
    static func savePicture(_ img: CGImage, boardDir: String) -> String? {
        let rel = "img/project-icon.png"
        let url = URL(fileURLWithPath: boardDir).appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest) ? rel : nil
    }
}

/// Looks through the project's folders for its favicon: apple-touch-icon, manifest icons, <link rel=icon>,
/// favicon.*, app icons. Local files only. The first repo wins a tie; bigger pictures beat smaller ones.
enum FaviconFinder {
    static let skip: Set<String> = ["node_modules", "coverage", "dist", "build", "out", "Pods", "vendor", "DerivedData",
                                    "tmp", "temp", "test", "tests", "__tests__", "fixtures", "examples", "example", "samples",
                                    "storybook-static", "lcov-report", "venv", "site-packages", "target"]
    static let iconDirs: Set<String> = ["public", "static", "assets", "images", "img", "icons", "brand", "app", "www", "web", "site", "res"]

    struct Cand { var path: String; var score: Double }

    static func find(_ repos: [Repo]) -> (path: String, label: String, theme: [RGBA])? { ranked(repos).first }

    /// Every usable favicon, best first.
    static func ranked(_ repos: [Repo]) -> [(path: String, label: String, theme: [RGBA])] {
        var cands: [Cand] = [], theme: [RGBA] = []
        let fm = FileManager.default
        for (ri, repo) in repos.enumerated() where repo.exists {
            let others = Set(repos.map(\.path)).subtracting([repo.path])   // a repo inside this one is looked at as itself
            let root = URL(fileURLWithPath: repo.path)
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var seen = 0
            for case let url as URL in en {
                seen += 1; if seen > 40_000 { break }
                let depth = en.level
                let name = url.lastPathComponent, lower = name.lowercased()
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    if depth >= 5 || skip.contains(name) || lower.hasPrefix("_") || others.contains(url.standardizedFileURL.path) || fm.fileExists(atPath: url.appendingPathComponent("steerify.json").path) { en.skipDescendants() }
                    continue
                }
                let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
                let ext = url.pathExtension.lowercased()
                var base: Double?
                if parent.hasSuffix(".appiconset"), ext == "png" { base = 88 }
                else if ext == "icns" { base = 86 }
                else if lower.hasPrefix("apple-touch-icon"), ext == "png" { base = 95 }
                else if lower.hasPrefix("favicon"), ["png", "svg", "ico"].contains(ext) { base = ext == "png" ? 85 : ext == "svg" ? 80 : 76 }
                else if ["manifest.json", "site.webmanifest", "manifest.webmanifest"].contains(lower) {
                    let m = manifest(url); theme += m.theme
                    for ic in m.icons { cands.append(Cand(path: ic, score: 84 - Double(depth) * 2 - Double(ri) * 6 + sizeBonus(ic))) }
                } else if ["index.html", "_document.tsx", "layout.tsx", "app.html"].contains(lower), depth <= 4 {
                    for ic in linkIcons(url, root: root) { cands.append(Cand(path: ic, score: 93 - Double(depth) * 2 - Double(ri) * 6 + sizeBonus(ic))) }
                } else if ["icon.png", "logo192.png", "logo512.png", "app-icon.png", "appicon.png", "icon-512.png", "icon-192.png"].contains(lower),
                          iconDirs.contains(parent) || depth <= 1 { base = 70 }
                if let base { cands.append(Cand(path: url.path, score: base - Double(depth) * 2 - Double(ri) * 6 + sizeBonus(url.path))) }
            }
        }
        let best = cands.filter { fm.fileExists(atPath: $0.path) && sizeBonus($0.path) > -50 }.sorted { $0.score > $1.score }
        var seenPaths = Set<String>()
        return best.filter { seenPaths.insert($0.path).inserted }.map { b in
            let repo = repos.first { b.path.hasPrefix($0.path + "/") }
            let label = repo.map { $0.name + String(b.path.dropFirst($0.path.count)) } ?? (b.path as NSString).lastPathComponent
            return (b.path, label, theme)
        }
    }

    /// Bigger is better up to 256 px; under 16 px it is not worth it (-100).
    static func sizeBonus(_ path: String) -> Double {
        if path.lowercased().hasSuffix(".svg") { return 6 }
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return -100 }
        var w = 0
        for i in 0..<CGImageSourceGetCount(src) {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            w = max(w, props?[kCGImagePropertyPixelWidth] as? Int ?? 0)
        }
        return w < 16 ? -100 : min(Double(w), 256) / 32
    }

    static func manifest(_ url: URL) -> (icons: [String], theme: [RGBA]) {
        guard let d = try? Data(contentsOf: url), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return ([], []) }
        if o["manifest_version"] != nil { return ([], []) }   // a browser extension, not the site
        let dir = url.deletingLastPathComponent()
        var icons: [String] = []
        if let arr = o["icons"] as? [[String: Any]] {
            icons = arr.compactMap { $0["src"] as? String }.map { resolve($0, from: dir, root: dir) }
        } else if let dict = o["icons"] as? [String: String] {   // browser extension manifests
            icons = dict.values.map { resolve($0, from: dir, root: dir) }
        }
        let theme = ["theme_color", "background_color"].compactMap { (o[$0] as? String).flatMap(RGBA.init(hex:)) }
        return (icons, theme)
    }

    static func linkIcons(_ url: URL, root: URL) -> [String] {
        guard let t = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let re = try! NSRegularExpression(pattern: #"<link[^>]*rel=["'](?:shortcut icon|icon|apple-touch-icon)["'][^>]*>"#, options: .caseInsensitive)
        let href = try! NSRegularExpression(pattern: #"href=["'{]+([^"'}]+)["'}]"#)
        let dir = url.deletingLastPathComponent()
        return re.matches(in: t, range: NSRange(t.startIndex..., in: t)).compactMap { m in
            let tag = String(t[Range(m.range, in: t)!])
            guard let h = href.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)), let r = Range(h.range(at: 1), in: tag) else { return nil }
            let v = String(tag[r])
            guard !v.hasPrefix("http"), !v.hasPrefix("data:") else { return nil }
            // "/favicon.png" is served from public/ (or static/) next to the page, or from the repo's root
            if v.hasPrefix("/") {
                for base in [dir, dir.appendingPathComponent("public"), dir.deletingLastPathComponent().appendingPathComponent("public"),
                             root.appendingPathComponent("public"), root.appendingPathComponent("static"), root] {
                    let p = base.appendingPathComponent(String(v.dropFirst())).standardizedFileURL.path
                    if FileManager.default.fileExists(atPath: p) { return p }
                }
                return nil
            }
            return resolve(v, from: dir, root: root)
        }
    }

    static func resolve(_ v: String, from dir: URL, root: URL) -> String {
        let clean = v.split(separator: "?").first.map(String.init) ?? v
        if clean.hasPrefix("/") { return dir.appendingPathComponent(String(clean.dropFirst())).standardizedFileURL.path }
        return URL(fileURLWithPath: clean, relativeTo: dir).standardizedFileURL.path
    }
}
