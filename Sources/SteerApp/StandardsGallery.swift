import SwiftUI
import AppKit

// Standards (choice standards-shape A: one gallery for Recipes + Standards, with categories, tags and search).
// A recipe starts a new project; a standard adds something to the project you have, installed by a briefed Claude
// session. Each standard is a folder in the steerify skill: standards/<id>/standard.json (what the card shows) +
// INSTALL.md (what Claude follows). The app ships them and copies them to ~/.claude/skills/steerify/standards.

struct Standard: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    var line: String = ""
    var category: String = "Other"
    var tags: [String] = []
    var icon: String? = nil
    var youGet: [String] = []
    var changes: [String] = []
    var steps: [String] = []
    /// A key path in steerify.json that exists once it is installed (e.g. "feedback.inbox").
    var installed: String? = nil
    var page: String? = nil
    var folder: URL = URL(fileURLWithPath: "/")
    enum CodingKeys: String, CodingKey { case id, name, line, category, tags, icon, youGet, changes, steps, installed, page }

    /// The guide Claude follows: the copy in ~/.claude (what sessions read), else the shipped one.
    var guide: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/steerify/standards/\(id)/INSTALL.md")
        return FileManager.default.fileExists(atPath: home.path) ? home.path : folder.appendingPathComponent("INSTALL.md").path
    }

    func isInstalled(in p: Project) -> Bool {
        guard let key = installed, let d = FileManager.default.contents(atPath: p.manifest),
              var o: Any = try? JSONSerialization.jsonObject(with: d) else { return false }
        for k in key.split(separator: ".") {
            guard let next = (o as? [String: Any])?[String(k)] else { return false }
            o = next
        }
        return !((o as? String)?.isEmpty ?? false)
    }

    var haystack: String { ([name, line, category] + tags + youGet + changes).joined(separator: " ").lowercased() }
}

enum StandardLibrary {
    /// Shipped in the app (Resources/skills/steerify/standards); STEERIFY_STANDARDS points a test copy at a folder;
    /// a development build reads the repo's copy.
    static var root: URL? {
        if let e = ProcessInfo.processInfo.environment["STEERIFY_STANDARDS"] { return URL(fileURLWithPath: e) }
        if let b = Bundle.main.url(forResource: "standards", withExtension: nil, subdirectory: "skills/steerify") { return b }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("skills/steerify/standards")
        if FileManager.default.fileExists(atPath: repo.path) { return repo }
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/steerify/standards")
        return FileManager.default.fileExists(atPath: home.path) ? home : nil
    }

    static func all() -> [Standard] {
        guard let root else { return [] }
        struct Index: Decodable { struct Item: Decodable { let id: String }; let standards: [Item] }
        let ids = (try? Data(contentsOf: root.appendingPathComponent("index.json"))).flatMap { try? JSONDecoder().decode(Index.self, from: $0) }?.standards.map(\.id)
            ?? ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
        return ids.compactMap { id in
            let f = root.appendingPathComponent(id, isDirectory: true)
            guard let d = try? Data(contentsOf: f.appendingPathComponent("standard.json")), var s = try? JSONDecoder().decode(Standard.self, from: d) else { return nil }
            s.folder = f
            return s
        }
    }
}

extension AppModel {
    /// Install = a request on the board ("Install: Feedback from your users") + a Claude session briefed with the guide.
    func installStandard(_ s: Standard, in p: Project) {
        let id = RequestLog.newId() + "-std"
        RequestLog.edit(p.boardDir, id: id, create: true) { r in
            r["at"] = RequestLog.now(); r["text"] = "Install the \(s.name) standard"; r["title"] = "Install: \(s.name)"
            r["kind"] = "feature"; r["status"] = "working"; r["became"] = [String](); r["client"] = "standard"; r["source"] = "standard:" + s.id
        }
        var item = ItemRef(ref: "request:" + id)!
        item.title = "Install: " + s.name
        let brief = """
            INSTALL THE STANDARD "\(s.name)" in this project (request \(id); the user pressed Install in Steerify's Standards gallery, so it is approved: do not draft a chapter).
            Follow \(s.guide) step by step, in order. Check what is already there before each step; skip what does not apply and say why.
            What the user was told they get: \(s.youGet.joined(separator: "; ")).
            What you may change: \(s.changes.joined(separator: "; ")).
            Questions only the user can answer (where a button goes, which chapters are public) go on the board as choices. Finish with one To test card and update_request \(id).
            """
        if CommandLine.arguments.contains("--dry-sessions") { FileHandle.standardError.write(("BRIEF\n" + brief + "\n").data(using: .utf8)!) }
        recipesOpen = false
        start(projectId: p.id, item: item, intent: .install, dry: CommandLine.arguments.contains("--dry-sessions"), extraBrief: brief)
    }
}

// MARK: - Cards

struct StandardCard: View {
    @EnvironmentObject var model: AppModel
    let standard: Standard
    let project: Project?
    @State private var hover = false

    var body: some View {
        let done = project.map { standard.isInstalled(in: $0) } ?? false
        VStack(alignment: .leading, spacing: 0) {
            StandardCover(icon: standard.icon).frame(height: S(110)).clipped()
            VStack(alignment: .leading, spacing: S(6)) {
                HStack {
                    Text(standard.category.uppercased()).font(Brand.label(9.5)).tracking(1).foregroundStyle(Brand.amber)
                    Spacer()
                    if done { Text("INSTALLED").font(Brand.label(8.5)).foregroundStyle(Brand.green)
                        .padding(.horizontal, 5).padding(.vertical, 1).overlay(RoundedRectangle(cornerRadius: 4).stroke(Brand.green.opacity(0.6))) }
                }
                Text(standard.name).font(.system(size: S(15), weight: .bold)).foregroundStyle(.white)
                Text(standard.line).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(standard.youGet.prefix(4), id: \.self) { g in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Image(systemName: "checkmark").font(.system(size: S(8), weight: .bold)).foregroundStyle(Brand.green)
                            Text(g).font(.system(size: S(11))).foregroundStyle(Brand.ink.opacity(0.85)).lineLimit(1)
                        }
                    }
                }
                TagRow(tags: standard.tags)
                Spacer(minLength: 0)
                HStack {
                    if let p = project {
                        Button { model.installStandard(standard, in: p) } label: {
                            HStack(spacing: 4) { ClaudeSpark(size: S(10), color: done ? Brand.claude : .black); Text(done ? "Check with Claude" : "Install with Claude") }
                                .font(.system(size: S(11.5), weight: .semibold))
                        }
                        .buttonStyle(SteerButton()).foregroundStyle(done ? Brand.claude : .black)
                        .padding(.horizontal, done ? 0 : 8).padding(.vertical, done ? 0 : 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(done ? Color.clear : Brand.claude))
                        .help(done ? "Already in \(p.name): Claude checks every step and fixes what is missing" : "Claude adds it to \(p.name), step by step, and puts it on To test")
                    } else {
                        Text("Open a project to install it").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                    }
                    Spacer()
                    Text("Claude changes: \(standard.changes.count)").font(.system(size: S(10))).foregroundStyle(Brand.mute)
                        .help(standard.changes.joined(separator: "\n"))
                }
            }
            .padding(S(12))
            .frame(maxWidth: .infinity, minHeight: S(230), alignment: .topLeading)
        }
        .background(Brand.panel2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(hover ? Brand.amber : Brand.line))
        .onHover { hover = $0 }
    }
}

struct TagRow: View {
    let tags: [String]
    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.prefix(5), id: \.self) { t in
                    Text(t).font(.system(size: S(9.5), weight: .medium)).foregroundStyle(Brand.mute)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(Capsule().stroke(Brand.line2))
                }
            }.lineLimit(1)
        }
    }
}

/// A small pixel beach: the standard's sprite (the crab for Feedback) by the sea.
struct StandardCover: View {
    let icon: String?
    private static let crab = [".c.....c.", "rr.....rr", "rr.rrr.rr", ".rrrrrrr.", "..rrrrr..", ".r.r.r.r."]
    private static let lighthouse = ["..lll..", ".lllll.", "..www..", "..rrr..", "..www..", ".rrrrr.", ".wwwww.", ".rrrrr.", ".wwwww.", "rrrrrrr", "wwwwwww"]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let px: CGFloat = 4, cols = Int(size.width / px), rows = Int(size.height / px)
                func dot(_ x: Int, _ y: Int, _ c: Color) { ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px - 0.4, height: px - 0.4)), with: .color(c)) }
                func sprite(_ s: [String], _ x0: Int, _ y0: Int, _ pal: [Character: Color]) {
                    for (y, row) in s.enumerated() { for (x, ch) in row.enumerated() { if let c = pal[ch] { dot(x0 + x, y0 + y, c) } } }
                }
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x0d1016)))
                for (i, (x, y)) in [(5, 3), (17, 6), (29, 2), (44, 5), (58, 3), (71, 7), (86, 2)].enumerated() where x < cols {
                    dot(x, y, Brand.cream.opacity((Int(t * 2) + i) % 4 == 0 ? 0.25 : 0.8))
                }
                let ph = Int(t * 2.5), sea = rows - 9
                for r in 0..<2 { for x in 0..<cols where (x + ph * (r + 1) + r * 3) % 7 < 4 { dot(x, sea + r * 2, (r == 0 ? Brand.blue : Brand.line2).opacity(0.7)) } }
                for y in (rows - 4)..<rows { for x in 0..<cols { dot(x, y, (x + y) % 5 == 0 ? Color(hex: 0x4f4229) : Color(hex: 0x6b5a3a)) } }
                sprite(Self.lighthouse, cols - 14, rows - 15, ["l": Brand.amber, "w": Brand.cream, "r": Brand.red])
                let walk = Int(t * 3) % max(cols - 30, 1)
                sprite(Self.crab, 6 + walk, rows - 10, ["r": Color(hex: 0xe0533d), "c": Brand.cream])
            }
        }
    }
}
