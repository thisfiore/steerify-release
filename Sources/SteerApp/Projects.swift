import Foundation
import AppKit

/// A folder or git repository that belongs to a project. Sessions start in one of these.
struct Repo: Codable, Hashable, Identifiable {
    var id: String { path }
    var name: String
    /// Absolute path on this Mac (resolved from the manifest's relative path).
    var path: String
    var git: String?
    var areas: [String] = []
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

/// One steered project, read from its workspace: a folder holding `steerify.json` + the board files.
struct Project: Hashable, Identifiable {
    var id: String
    var name: String
    /// The workspace folder: steerify.json, board.json, decisions.json, delivered.json, img/.
    var boardDir: String
    /// Port of the project's own web board (optional, legacy). 0 = none.
    var port: Int
    var repos: [Repo]
    var release: ReleaseConfig? = nil
    var automation: Automation? = nil
    /// steerify.json → "icon": your icon choice (nil = automatic, from the favicon).
    var icon: IconConfig? = nil
    /// steerify.json → "environments": where to test (Environments.swift). Empty = not set up yet.
    var environments: [TestEnv] = []
    /// steerify.json → "processes": the project's base processes, pinned under the sessions (Processes.swift).
    var processes: [ProcessSpec] = []
    var manifest: String { (boardDir as NSString).appendingPathComponent("steerify.json") }

    /// A repo by the name an item uses: repo name, folder name or git remote ("steerify" → steer-app).
    func resolveRepo(_ name: String) -> Repo? {
        let n = name.lowercased()
        return repos.first { $0.name.lowercased() == n }
            ?? repos.first { ($0.path as NSString).lastPathComponent.lowercased() == n }
            ?? repos.first { r in
                guard let g = r.git?.lowercased() else { return false }
                let base = (g as NSString).lastPathComponent.replacingOccurrences(of: ".git", with: "")
                return base == n
            }
    }
}

/// `steerify.json`, the file that makes a folder a Steerify workspace. It travels with the repo (GitHub).
/// Repo paths are relative to the workspace folder, so a teammate's clone works on any Mac;
/// `git` lets Steerify offer to clone a repo that is missing.
struct Manifest: Codable {
    struct R: Codable { var name: String; var path: String; var git: String?; var areas: [String]? }
    struct Web: Codable { var port: Int; var server: String? }
    var steerify: Int
    var id: String
    var name: String
    var repos: [R]
    var webBoard: Web?
    var note: String?
    var release: ReleaseConfig?
    var automation: Automation?
    var icon: IconConfig?
    var environments: [TestEnv]?
    var processes: [ProcessSpec]?
}

/// The app's own memory is only *which* workspaces you opened (workspaces.json in Application Support).
/// Everything about a project lives in the project.
enum ProjectStore {
    static let appName = "Steerify"

    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(appName)", isDirectory: true)
    }
    /// `STEERIFY_WORKSPACES=<file.json>` points a test copy at another list (demo boards, screenshots).
    static var file: URL {
        if let f = ProcessInfo.processInfo.environment["STEERIFY_WORKSPACES"], !f.isEmpty { return URL(fileURLWithPath: f) }
        return dir.appendingPathComponent("workspaces.json")
    }

    static func load() -> [Project] {
        var paths = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        if paths.isEmpty {
            paths = discover()
            save(paths)
        }
        return paths.compactMap(read)
    }

    static func save(_ workspaces: [String]) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try? enc.encode(workspaces).write(to: file, options: .atomic)
    }

    /// Reads one workspace folder (or its steerify.json).
    static func read(_ path: String) -> Project? {
        let folder = path.hasSuffix("steerify.json") ? (path as NSString).deletingLastPathComponent : path
        let mf = (folder as NSString).appendingPathComponent("steerify.json")
        guard let data = FileManager.default.contents(atPath: mf),
              let m = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        let repos = m.repos.map { r in
            Repo(name: r.name,
                 path: URL(fileURLWithPath: r.path, relativeTo: URL(fileURLWithPath: folder, isDirectory: true)).standardizedFileURL.path,
                 git: r.git, areas: r.areas ?? [])
        }
        return Project(id: m.id, name: m.name, boardDir: folder, port: m.webBoard?.port ?? 0, repos: repos,
                       release: m.release, automation: m.automation, icon: m.icon, environments: m.environments ?? [], processes: m.processes ?? [])
    }

    /// First run: workspaces already on this Mac.
    static func discover() -> [String] {
        let home = NSHomeDirectory()
        return [String]()
            .filter { FileManager.default.fileExists(atPath: "\($0)/steerify.json") }
    }

    /// "Add project…": pick any folder, or make a new empty one in the panel.
    @MainActor static func pickFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Steer this folder"
        panel.message = "Choose your project's folder, or click New Folder to start an empty one"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.standardizedFileURL.path
    }

    /// The board folder of a picked folder: the folder itself (a board), its `.steerify/`, or nil (no board yet).
    static func boardFolder(in folder: String) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: (folder as NSString).appendingPathComponent("steerify.json")) { return folder }
        let hidden = (folder as NSString).appendingPathComponent(".steerify")
        if fm.fileExists(atPath: (hidden as NSString).appendingPathComponent("steerify.json")) { return hidden }
        return nil
    }

    /// Opens the board of any folder, creating `<folder>/.steerify` the first time. Returns the board folder.
    static func openOrCreate(_ folder: String, takenIds: Set<String>) -> String? {
        if let b = boardFolder(in: folder) { return b }
        return try? BoardTemplate.create(in: folder, takenIds: takenIds)
    }
}

/// A new, empty board for a folder that has never been steered: `<folder>/.steerify/` with steerify.json,
/// board.json, decisions.json, delivered.json, deliver.mjs, README.md and img/ship. The folder is the project's
/// one repo (path ".."); its git remote is recorded so a teammate's clone can find it.
enum BoardTemplate {
    static func slug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let parts = folded.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        let joined = parts.joined(separator: "-")
        return joined.isEmpty ? "project" : String(joined.prefix(40))
    }

    /// "my-shop_app" → "My shop app".
    static func displayName(_ folderName: String) -> String {
        let words = folderName.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").map(String.init)
        guard let first = words.first else { return folderName }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    /// `origin` from .git/config, read as a file (no git process on the main thread).
    static func gitRemote(_ folder: String) -> String? {
        guard let cfg = try? String(contentsOfFile: (folder as NSString).appendingPathComponent(".git/config"), encoding: .utf8)
        else { return nil }
        var inOrigin = false
        for raw in cfg.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inOrigin = line == "[remote \"origin\"]"; continue }
            if inOrigin, line.hasPrefix("url") , let eq = line.firstIndex(of: "=") {
                return line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    @discardableResult
    static func create(in folder: String, takenIds: Set<String>, today: Date = Date()) throws -> String {
        let fm = FileManager.default
        let folderName = (folder as NSString).lastPathComponent
        let name = displayName(folderName)
        var id = slug(folderName), n = 2
        while takenIds.contains(id) { id = "\(slug(folderName))-\(n)"; n += 1 }
        let repoName = folderName
        let area = "main"

        let board = (folder as NSString).appendingPathComponent(".steerify")
        try fm.createDirectory(atPath: (board as NSString).appendingPathComponent("img/ship"), withIntermediateDirectories: true)

        func q(_ v: String) -> String {
            String(decoding: (try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data("\"\"".utf8), as: UTF8.self)
        }
        func writeText(_ file: String, _ text: String) throws {
            let path = (board as NSString).appendingPathComponent(file)
            guard !fm.fileExists(atPath: path) else { return }
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }

        let git = gitRemote(folder).map { ",\n   \"git\": \(q($0))" } ?? ""
        let day = ISO8601DateFormatter.string(from: today, timeZone: .current, formatOptions: [.withFullDate])

        // Same layout as JSON.stringify(x, null, 1), the style every board file keeps.
        try writeText("board.json", """
            {
             "updated": \(q(day)),
             "goal": "",
             "areas": {
              \(q(area)): {
               "name": \(q(name)),
               "repo": \(q(repoName))
              }
             },
             "tags": {},
             "decisions": [],
             "requirements": [],
             "tracks": [],
             "facts": {},
             "links": []
            }

            """)
        try writeText("decisions.json", "{\n \"choices\": {}\n}\n")
        try writeText("delivered.json", "{\n \"items\": []\n}\n")
        try writeText("deliver.mjs", deliverScript)
        try writeText("README.md", """
            # \(name): the Steerify board

            Steerify keeps this project's board here (`.steerify/`): choices, roadmap, requirements and the To test tab.
            Claude Code sessions started from Steerify read and write these files.

            - Area: `\(area)` (the whole folder). Add more areas in `board.json` when the project has parts.
            - Deliver finished work with `node .steerify/deliver.mjs '<json>'`.
            - Add this project's own rules below (test data, how to run it, how to deploy): they win over the defaults.

            """)
        // steerify.json last: a half-made board is never picked up as a project.
        try writeText("steerify.json", """
            {
             "steerify": 1,
             "id": \(q(id)),
             "name": \(q(name)),
             "repos": [
              {
               "name": \(q(repoName)),
               "path": "..",
               "areas": [\(q(area))]\(git)
              }
             ]
            }

            """)
        return board
    }

    /// The To test helper every board carries (same contract as Steerify's own board).
    static let deliverScript = #"""
    #!/usr/bin/env node
    // Add finished work to the board's "To test" tab. Any Claude session runs this after testing its own work:
    //
    //   node .steerify/deliver.mjs '<json>'      (or a path to a .json file)
    //
    // json: { "title", "area": "<a key of board.json areas>", "status": "local|needs-deploy|live", "kind": "design|local|stage|prod",
    //         "what": "- 2–4 bullets\n- ≤ 6 words each" (one per line, what changed for the user, no prose),
    //         "tested": ["what Claude tested + result"], "howTo": ["step"], "links": [{ "label", "url" }],
    //         "issues": ["known limits"], "repos": ["repo"], "id"?: "update-this-id", "road"?: "<roadmap item text>",
    //         "tests": [{ "label", "url", "check", "img": "img/ship/<id>-t<n>.png" }],
    //         "shots": [{ "img": "img/ship/<id>-1.png", "caption" }] }
    // Same id → the item is updated and the verdict asked again. "keepVerdict": true keeps the verdict
    // (bookkeeping only, e.g. status → live after an approved deploy).
    import { readFile, writeFile } from 'node:fs/promises';
    import { existsSync } from 'node:fs';
    import { join, dirname } from 'node:path';
    import { fileURLToPath } from 'node:url';
    import { execFileSync } from 'node:child_process';

    const dir = dirname(fileURLToPath(import.meta.url));
    const FILE = join(dir, 'delivered.json');
    const arg = process.argv[2];
    if (!arg) { console.error('usage: deliver.mjs <json | file.json>'); process.exit(1); }
    const item = JSON.parse(existsSync(arg) ? await readFile(arg, 'utf8') : arg);
    if (!item.id && !item.title) { console.error('missing title'); process.exit(1); }
    const areas = Object.keys(JSON.parse(await readFile(join(dir, 'board.json'), 'utf8')).areas || {});

    const data = existsSync(FILE) ? JSON.parse(await readFile(FILE, 'utf8')) : { items: [] };
    const slug = (s) => s.toLowerCase().normalize('NFD').replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-').slice(0, 48);
    const now = new Date().toISOString();
    const id = item.id || slug(item.title);
    const prev = data.items.find((x) => x.id === id);
    // A re-delivery by id (e.g. status → live) keeps what the previous version said.
    for (const k of ['title', 'area', 'what']) if (!item[k] && prev?.[k]) item[k] = prev[k];
    for (const k of ['title', 'area', 'what']) if (!item[k]) { console.error(`missing ${k}`); process.exit(1); }
    if (!areas.includes(item.area)) { console.error(`area must be one of: ${areas.join('|')}`); process.exit(1); }
    const next = { status: 'local', tested: [], howTo: [], links: [], issues: [], repos: [], ...prev, ...item, id, updated: now, added: prev?.added || now };
    const keep = item.keepVerdict && prev;
    delete next.keepVerdict;
    next.version = keep ? prev.version : (prev?.version || 0) + 1;
    data.items = [next, ...data.items.filter((x) => x.id !== id)];
    await writeFile(FILE, JSON.stringify(data, null, 1) + '\n');

    const git = (...a) => execFileSync('git', a, { cwd: dir, stdio: 'pipe' }).toString();
    let note = 'not a git repo, saved only';
    try {
      git('rev-parse', '--is-inside-work-tree');
      git('add', 'delivered.json');
      git('commit', '-q', '-m', `To test: ${next.title}`, '--', 'delivered.json');
      note = 'committed';
      try { git('push', '-q'); note = 'pushed'; } catch { /* no remote yet */ }
    } catch (e) { if (note !== 'not a git repo, saved only') note = `git: ${String(e.stderr || e.message).trim().slice(0, 200)}`; }
    console.log(`${prev ? 'updated' : 'added'} "${next.title}" (${id}, v${next.version}) · ${note}`);

    """#
}
