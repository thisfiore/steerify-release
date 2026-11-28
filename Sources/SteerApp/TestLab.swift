import AppKit
import SwiftUI
import Foundation

/// Steerify Lab: one test project whose board is reset to a prepared case before each test (choice test-case-home,
/// request r261127-184321). A case lives in the board of the project under test:
///
///     <board>/cases/<id>/case.json   {"title": "Ship with 2 ok items", "item": "test:x", "note": "…"}
///     <board>/cases/<id>/board/      board files copied over an empty Lab board (board.json, delivered.json, img/…)
///
/// A To test link `steerify://case?project=<p>&id=<id>&build=dev|prod` resets the Lab to that case and opens its
/// item, in the build the test is for: dev = Steerify Dev (the repo's build/Steerify.app, before release),
/// prod = the installed release (after release). Your real boards are never touched.
enum TestLab {
    static let id = "steerify-lab"
    static let name = "Steerify Lab"
    static let devBundle = "com.frenkfiore.steerify.dev"
    static let prodBundle = "com.frenkfiore.steerify"

    struct Case { let id: String; let title: String; let item: String?; let dir: String }

    /// `STEERIFY_LAB_DIR=<dir>` puts the Lab elsewhere (test copies).
    static var folder: URL {
        if let d = ProcessInfo.processInfo.environment["STEERIFY_LAB_DIR"], !d.isEmpty {
            return URL(fileURLWithPath: d, isDirectory: true).appendingPathComponent(id)
        }
        return ProjectStore.dir.appendingPathComponent("Lab/\(id)", isDirectory: true)
    }
    static var boardDir: String { folder.appendingPathComponent(".steerify").path }

    static func caseDir(board: String, id: String) -> String {
        ((board as NSString).appendingPathComponent("cases") as NSString).appendingPathComponent(id)
    }

    static func load(board: String, id: String) -> Case? {
        guard !id.isEmpty, !id.contains("/"), !id.contains("..") else { return nil }
        let dir = caseDir(board: board, id: id)
        guard let d = FileManager.default.contents(atPath: (dir as NSString).appendingPathComponent("case.json")),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        let item = (j["item"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Case(id: id, title: j["title"] as? String ?? id, item: item, dir: dir)
    }

    /// The Lab board, emptied and filled with the case. Returns the Lab's board folder.
    static func reset(to c: Case, takenIds: Set<String>) throws -> String {
        let fm = FileManager.default
        let board = boardDir
        try fm.createDirectory(atPath: board, withIntermediateDirectories: true)
        // Everything but steerify.json goes (the project stays registered, its watcher keeps working).
        for f in (try? fm.contentsOfDirectory(atPath: board)) ?? [] where f != "steerify.json" {
            try? fm.removeItem(atPath: (board as NSString).appendingPathComponent(f))
        }
        let manifest = """
            {
             "steerify": 1,
             "id": "\(id)",
             "name": "\(name)",
             "lab": true,
             "case": \(String(decoding: (try? JSONSerialization.data(withJSONObject: c.id, options: .fragmentsAllowed)) ?? Data("\"\"".utf8), as: UTF8.self)),
             "repos": [
              {
               "name": "\(id)",
               "path": ".."
              }
             ]
            }

            """
        try manifest.write(toFile: (board as NSString).appendingPathComponent("steerify.json"), atomically: true, encoding: .utf8)
        try BoardTemplate.create(in: folder.path, takenIds: takenIds.subtracting([id]))   // empty board files
        // The case's files over the empty board.
        let src = (c.dir as NSString).appendingPathComponent("board")
        if let en = fm.enumerator(atPath: src) {
            while let rel = en.nextObject() as? String {
                let from = (src as NSString).appendingPathComponent(rel), to = (board as NSString).appendingPathComponent(rel)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: from, isDirectory: &isDir)
                if isDir.boolValue { try fm.createDirectory(atPath: to, withIntermediateDirectories: true); continue }
                if rel == "steerify.json" { continue }
                try? fm.removeItem(atPath: to)
                try fm.copyItem(atPath: from, toPath: to)
            }
        }
        return board
    }

    /// Which Steerify this is.
    static var runningBuild: String {
        let b = Bundle.main.bundleIdentifier ?? ""
        if b == devBundle || Bundle.main.bundleURL.path.hasSuffix("/build/Steerify.app") { return "dev" }
        return b == prodBundle ? "prod" : "dev"     // `swift run` has no bundle id: a dev build
    }

    /// The app for a build: Steerify Dev from the project's repo (build/Steerify.app), the release from
    /// wherever macOS has it installed.
    static func app(for build: String, project: Project?) -> URL? {
        let fm = FileManager.default
        if build == "dev" {
            for r in project?.repos ?? [] {
                let p = (r.path as NSString).appendingPathComponent("build/Steerify.app")
                if fm.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
            }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: devBundle)
        }
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: prodBundle), !u.path.contains("/build/") { return u }
        return fm.fileExists(atPath: "/Applications/Steerify.app") ? URL(fileURLWithPath: "/Applications/Steerify.app") : nil
    }
}

extension AppModel {
    /// steerify://case?project=<p>&id=<case>&build=dev|prod
    func openCase(projectId: String, caseId: String, build: String?, url: URL) {
        let owner = projects.first { $0.id == projectId }
        // The test is for another build: hand the link to that app (without `build`, so it never bounces back).
        if let b = build, b == "dev" || b == "prod", b != TestLab.runningBuild, !CommandLine.arguments.contains("--background") {
            guard let app = TestLab.app(for: b, project: owner) else {
                showToast(b == "dev" ? "No Steerify Dev build: run scripts/bundle.sh first" : "Steerify (release) isn't installed on this Mac")
                return
            }
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let kept = (c?.queryItems ?? []).filter { $0.name != "build" }
            c?.queryItems = kept
            guard let fwd = c?.url else { return }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.open([fwd], withApplicationAt: app, configuration: cfg) { [weak self] _, err in
                if let err { DispatchQueue.main.async { self?.showToast("Couldn't open \(app.lastPathComponent): \(err.localizedDescription)") } }
            }
            return
        }
        guard let owner else { showToast("Case \(caseId): project \(projectId) isn't open in this Steerify"); return }
        guard let c = TestLab.load(board: owner.boardDir, id: caseId) else {
            showToast("No case \(caseId) in \(owner.name) (cases/\(caseId)/case.json)"); return
        }
        do {
            let board = try TestLab.reset(to: c, takenIds: Set(projects.map(\.id)))
            if let i = projects.firstIndex(where: { $0.id == TestLab.id }) {
                boards[TestLab.id]?.reread()
                if let p = ProjectStore.read(board) { projects[i] = p }
            } else if let p = ProjectStore.read(board) {
                projects.append(p)
                ProjectStore.save(projects.map(\.boardDir))
            }
            selectedProjectId = TestLab.id
            if let item = c.item { focusItem(projectId: TestLab.id, ref: item) }
            showToast("Steerify Lab · \(c.title)", projectId: TestLab.id, ref: c.item)
        } catch {
            showToast("Couldn't prepare case \(caseId): \(error.localizedDescription)")
        }
    }
}

/// Where one test runs, for the smart Test button (request r261127-184321): the label says it.
enum TestWhere: Equatable {
    case devBuild, prodCase, local, prod, app, file, picture
    case vague(String)

    static func of(_ raw: String?, item: ShipItem, envs: [TestEnv]) -> TestWhere {
        guard let raw, !raw.isEmpty, !TestEnvs.dead(raw), let u = URL(string: raw), let sch = u.scheme?.lowercased() else { return .picture }
        if let why = TestEnvs.generic(raw, envs: envs) { return .vague(why) }
        switch sch {
        case "steerify":
            guard u.host == "case" else { return .app }
            let build = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "build" }?.value
            if build == "prod" { return .prodCase }
            if build == "dev" { return .devBuild }
            return item.kind == .online ? .prodCase : .devBuild
        case "http", "https":
            let h = u.host ?? ""
            return h == "localhost" || h == "127.0.0.1" || h.hasSuffix(".local") ? .local : .prod
        case "file": return .file
        default: return .app
        }
    }

    var label: String {
        switch self {
        case .devBuild: "Test Dev Build"
        case .prodCase: "Test Prod Case"
        case .local: "Test local"
        case .prod: "Test on prod"
        case .app: "Test in Steerify"
        case .file: "Open the file"
        case .picture: "Check on the picture"
        case .vague: "Home page only"
        }
    }
    var icon: String {
        switch self {
        case .devBuild: "hammer.fill"
        case .prodCase: "checkmark.seal.fill"
        case .local: "laptopcomputer"
        case .prod: "globe"
        case .app: "arrow.up.right"
        case .file: "doc"
        case .picture: "photo"
        case .vague: "exclamationmark.triangle.fill"
        }
    }
    /// Small text after the label: what exactly it opens.
    static func detail(_ raw: String?) -> String {
        guard let raw, let u = URL(string: raw) else { return "" }
        if u.scheme == "steerify", u.host == "case" {
            let id = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value ?? ""
            return "Lab case “\(id)”"
        }
        if u.scheme?.hasPrefix("http") == true {
            let p = u.path == "/" ? "" : u.path
            return (u.host ?? "") + (u.port.map { ":\($0)" } ?? "") + p + (u.fragment.map { "#" + $0 } ?? "")
        }
        if u.isFileURL { return u.lastPathComponent }
        return ""
    }
}

/// The Test button of one test: full width, and its label says where the test runs. No link that leads
/// anywhere → "Check on the picture" (opens the picture), the last resort.
struct SmartTestButton: View {
    @EnvironmentObject var model: AppModel
    let url: URL?
    let raw: String?
    let place: TestWhere
    let openPicture: (() -> Void)?

    var body: some View {
        let detail = TestWhere.detail(raw)
        switch place {
        case .picture, .vague: plain(detail)
        default:
            PixelCTA(title: place.label, subtitle: detail.isEmpty ? nil : detail,
                     color: { if case .prodCase = place { return Brand.green }; if case .prod = place { return Brand.green }; return Brand.blue }(),
                     icon: "test", fullWidth: true) { open() }
                .help(help)
                .contextMenu { if let url { OpenInMenu(url: url) } }
        }
    }

    private func open() {
        if place == .picture { openPicture?(); return }
        guard let url else { return }
        if url.scheme == "steerify" { model.handle(url) } else { openTestLink(url) }
    }

    private func plain(_ detail: String) -> some View {
        Button { open() } label: {
            HStack(spacing: 7) {
                Image(systemName: place.icon).font(.system(size: S(11), weight: .bold))
                Text(place.label).font(.system(size: S(13), weight: .bold))
                if !detail.isEmpty {
                    Text("· " + detail).font(.system(size: S(11))).opacity(0.75).lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .foregroundStyle(fg)
            .background(RoundedRectangle(cornerRadius: 8).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(stroke, style: StrokeStyle(lineWidth: 1, dash: place == .picture ? [4, 3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(SteerButton())
        .disabled(place == .picture && openPicture == nil)
        .help(help)
        .contextMenu { if let url, place != .picture { OpenInMenu(url: url) } }
    }

    private var help: String {
        switch place {
        case .devBuild: "Resets Steerify Lab to this case and opens it in Steerify Dev (before release)\n\(raw ?? "")"
        case .prodCase: "Resets Steerify Lab to this case and opens it in the installed Steerify (after release)\n\(raw ?? "")"
        case .picture: "No case or link could be prepared: check it on the picture"
        case .vague(let why): "This link opens \(why): \(raw ?? "")\nSend it back with Refine to get a direct link."
        default: raw ?? ""
        }
    }
    private var bg: Color {
        switch place {
        case .prodCase, .prod: Brand.green
        case .picture, .vague: .clear
        default: Color(hex: 0x3b6ff5)
        }
    }
    private var fg: Color {
        switch place {
        case .prodCase, .prod: Color(hex: 0x06210f)
        case .picture, .vague: Brand.amber
        default: .white
        }
    }
    private var stroke: Color {
        switch place {
        case .picture, .vague: Brand.amber.opacity(0.7)
        default: .clear
        }
    }
}
