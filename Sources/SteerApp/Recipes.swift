import SwiftUI
import AppKit
import CryptoKit

// Recipes: a guided start for people who are not technical (request r261122-184838, the book AI Traction v2).
// A recipe is a starter folder: plain files to fill in, a cover picture of what you get, the skills it needs and the
// first message for Claude (recipe.json, next to the START-HERE.md that also works with Claude Code alone).
//   choice recipe-source = repo:          recipes come from a public repo (index.json + one folder per recipe +
//                                          skills/), cloned into Steerify's cache; a local folder works too (tests).
//   choice recipe-skills = per-project:   starting a recipe copies only the skills it needs into the new project's
//                                          .claude/skills; nothing touches the reader's other projects.
//   choice recipe-guided-screen = A:      a recipe project opens on its checklist (files ✓ when filled), the steps
//                                          ahead, and the picture of what you get; Set up unlocks at the required files
//                                          and sends the recipe's first message for you.

struct Recipe: Decodable, Identifiable, Equatable {
    struct File: Decodable, Equatable, Identifiable {
        let path: String
        let hint: String
        var required: Bool = true
        var folder: Bool? = nil
        var template: String? = nil
        var id: String { path }
        var isFolder: Bool { folder == true || path.hasSuffix("/") }
    }
    let id: String
    let name: String
    var book: String? = nil
    var build: Int? = nil
    var chapter: Int? = nil
    var line: String = ""
    var youGet: String = ""
    var who: String = ""
    var cover: String? = nil
    var draft: Bool? = nil
    var steps: [String] = []
    var files: [File] = []
    var skills: [String] = []
    var optionalSkills: [String]? = nil
    var start: String? = nil
    var firstMessage: String = ""
    var page: String? = nil

    /// Where this recipe lives on disk (the library copy, or the reader's project).
    var folder: URL = URL(fileURLWithPath: "/")
    enum CodingKeys: String, CodingKey { case id, name, book, build, chapter, line, youGet, who, cover, draft, steps, files, skills, optionalSkills, start, firstMessage, page }

    var coverURL: URL? { cover.map { folder.appendingPathComponent($0) } }
    var place: String {
        [build.map { "BUILD \($0)" }, chapter.map { "CHAPTER \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    static func read(_ folder: URL) -> Recipe? {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent("recipe.json")),
              var r = try? JSONDecoder().decode(Recipe.self, from: d) else { return nil }
        r.folder = folder
        return r
    }

    /// The recipe a project was started from (recipe.json at the top of its first folder).
    static func of(_ p: Project) -> Recipe? {
        guard let repo = p.repos.first(where: \.exists) else { return nil }
        return read(URL(fileURLWithPath: repo.path, isDirectory: true))
    }

    // MARK: State of the reader's files

    /// Filled = a folder with something in it besides its README, or a file changed from the recipe's blank copy.
    func filled(_ f: File) -> Bool {
        let url = folder.appendingPathComponent(f.path)
        let fm = FileManager.default
        if f.isFolder {
            let items = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
            return items.contains { !$0.hasPrefix(".") && !$0.lowercased().hasPrefix("readme") }
        }
        guard let d = fm.contents(atPath: url.path),
              !String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let t = f.template else { return true }
        return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() != t
    }

    /// What is in a filled folder, said short ("17 files").
    func count(_ f: File) -> String? {
        guard f.isFolder else { return nil }
        let items = ((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(f.path).path)) ?? [])
            .filter { !$0.hasPrefix(".") && !$0.lowercased().hasPrefix("readme") }
        return items.isEmpty ? nil : "\(items.count) file\(items.count == 1 ? "" : "s")"
    }

    /// The skills not installed for this project (its own .claude/skills, or the Mac's ~/.claude/skills).
    func missingSkills() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
        let own = folder.appendingPathComponent(".claude/skills")
        return skills.filter { k in
            ![own, home].contains { fm.fileExists(atPath: $0.appendingPathComponent(k).appendingPathComponent("SKILL.md").path) }
        }
    }

    /// The setup session's brief: the recipe's first message is the reader's first request.
    var setupBrief: String {
        "This project was started from the recipe \"\(name)\"\(chapter.map { " (\(book ?? "the book"), Chapter \($0))" } ?? ""). "
            + "Its recipe.json and START-HERE.md are in the project folder. Follow the steerify skill's Recipe setup: "
            + "the reader is not technical and has filled the recipe's files; treat the message below as their first request "
            + "(the skills it names are installed in .claude/skills), and put every question and proposal on the board.\n\n"
            + "The reader's first message:\n" + firstMessage
    }
}

// MARK: - The library (choice recipe-source: a public repo)

@MainActor
final class RecipeLibrary: ObservableObject {
    static let shared = RecipeLibrary()
    static let sourceKey = "recipesSource"
    /// The public recipes repo. STEERIFY_RECIPES (or the setting) can point at another repo or a local folder.
    static let defaultSource = "https://github.com/thisfiore/ai-traction-recipes.git"

    enum State: Equatable { case idle, loading, ready, failed(String) }
    @Published var state: State = .idle
    @Published var recipes: [Recipe] = []
    private(set) var root: URL?

    static var source: String {
        ProcessInfo.processInfo.environment["STEERIFY_RECIPES"]
            ?? Prefs.store.string(forKey: sourceKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultSource
    }

    nonisolated static var cache: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Steerify/recipes", isDirectory: true)
    }

    func load(force: Bool = false) {
        if state == .loading || (state == .ready && !force) { return }
        state = .loading
        let src = Self.source
        Task.detached {
            let result = Self.fetch(src)
            await MainActor.run {
                switch result {
                case .success(let dir):
                    self.root = dir
                    self.recipes = Self.list(dir)
                    self.state = self.recipes.isEmpty ? .failed("No recipes in \(src)") : .ready
                case .failure(let e):
                    self.state = .failed(e.message)
                }
            }
        }
    }

    struct FetchError: Error { let message: String }

    /// A local folder is read where it is; a repo is cloned once into the cache, then pulled.
    nonisolated static func fetch(_ src: String) -> Result<URL, FetchError> {
        let expanded = (src as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
            return .success(URL(fileURLWithPath: expanded, isDirectory: true))
        }
        let dir = cache.appendingPathComponent(BoardTemplate.slug(src), isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let hasClone = fm.fileExists(atPath: dir.appendingPathComponent(".git").path)
        let args = hasClone ? ["-C", dir.path, "pull", "--ff-only", "--quiet"]
                            : ["clone", "--depth", "1", "--quiet", src, dir.path]
        let (ok, err) = git(args)
        if ok || (hasClone && fm.fileExists(atPath: dir.appendingPathComponent("index.json").path)) {
            return .success(dir)   // offline: the last copy still works
        }
        return .failure(FetchError(message: "Couldn't get the recipes (\(err.isEmpty ? src : err))"))
    }

    nonisolated private static func git(_ args: [String]) -> (Bool, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"   // a missing or private repo fails instead of asking for a password
        p.environment = env
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return (false, error.localizedDescription) }
        p.waitUntilExit()
        let e = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let line = e.split(separator: "\n").last.map(String.init) ?? ""
        return (p.terminationStatus == 0, line)
    }

    nonisolated static func list(_ dir: URL) -> [Recipe] {
        struct Index: Decodable { struct Item: Decodable { let id: String }; let recipes: [Item] }
        let ids: [String]
        if let d = try? Data(contentsOf: dir.appendingPathComponent("index.json")),
           let ix = try? JSONDecoder().decode(Index.self, from: d) {
            ids = ix.recipes.map(\.id)
        } else {
            ids = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        }
        return ids.compactMap { Recipe.read(dir.appendingPathComponent($0, isDirectory: true)) }
    }

    /// The pack's copy of a skill (skills/<name> in the recipes repo).
    func skillSource(_ name: String) -> URL? {
        guard let root else { return nil }
        let u = root.appendingPathComponent("skills/\(name)", isDirectory: true)
        return FileManager.default.fileExists(atPath: u.appendingPathComponent("SKILL.md").path) ? u : nil
    }
}

// MARK: - Start a project from a recipe

enum RecipeInstall {
    /// Copies the recipe into `dest` (a new folder) and its skills into `dest/.claude/skills`. Returns what failed.
    @MainActor static func create(_ r: Recipe, at dest: URL) -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            let items = (try? fm.contentsOfDirectory(atPath: dest.path))?.filter { !$0.hasPrefix(".") } ?? []
            if !items.isEmpty { return "\(dest.lastPathComponent) already has files in it: pick a new folder" }
            try? fm.removeItem(at: dest)
        }
        do {
            try fm.copyItem(at: r.folder, to: dest)
            try? fm.removeItem(at: dest.appendingPathComponent(".git"))
        } catch { return "Couldn't copy the recipe: \(error.localizedDescription)" }
        let missing = installSkills(r.skills, into: dest)
        return missing.isEmpty ? nil : "Skills not found in the pack: " + missing.joined(separator: ", ")
    }

    /// Copies the named skills from the pack into the project's .claude/skills. Returns the ones it couldn't find.
    @MainActor @discardableResult
    static func installSkills(_ names: [String], into project: URL) -> [String] {
        let fm = FileManager.default
        let target = project.appendingPathComponent(".claude/skills", isDirectory: true)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        var missing: [String] = []
        for k in names {
            let to = target.appendingPathComponent(k, isDirectory: true)
            if fm.fileExists(atPath: to.appendingPathComponent("SKILL.md").path) { continue }
            guard let from = RecipeLibrary.shared.skillSource(k) else { missing.append(k); continue }
            do { try fm.copyItem(at: from, to: to) } catch { missing.append(k) }
        }
        return missing
    }

    /// Where the new project goes: a save panel, "My content engine" in Documents by default.
    @MainActor static func pickDestination(_ r: Recipe) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Start “\(r.name)”"
        panel.message = "Your project's folder: you fill its files, Claude works in it."
        panel.prompt = "Start here"
        panel.nameFieldLabel = "Project name:"
        panel.nameFieldStringValue = "My " + r.name.replacingOccurrences(of: "The ", with: "").lowercased()
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

extension AppModel {
    /// Starts a new project from a recipe: copy it with its skills, steer the folder, open it on its checklist.
    func startRecipe(_ r: Recipe, at given: URL? = nil) {
        guard let dest = given ?? RecipeInstall.pickDestination(r) else { return }
        if let err = RecipeInstall.create(r, at: dest) {
            showToast(err)
            if !FileManager.default.fileExists(atPath: dest.appendingPathComponent("recipe.json").path) { return }
        }
        recipesOpen = false
        addWorkspace(folder: dest.standardizedFileURL.path)
    }
}

// MARK: - The gallery: pick a recipe

struct RecipeGallery: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var lib = RecipeLibrary.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { model.recipesOpen = false }
            VStack(alignment: .leading, spacing: S(14)) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("START FROM A RECIPE").font(Brand.label(13)).tracking(1.4).foregroundStyle(Brand.cream)
                        Text("A ready folder for one build of the book AI Traction. You fill a few plain files; Claude asks, proposes and builds; you decide.")
                            .font(.system(size: S(12.5))).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button { model.recipesOpen = false } label: { Image(systemName: "xmark").foregroundStyle(Brand.mute) }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction).help("Close")
                }
                switch lib.state {
                case .ready:
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: S(250)), spacing: S(14))], spacing: S(14)) {
                            ForEach(lib.recipes) { r in RecipeCard(recipe: r) { model.startRecipe(r) } }
                        }
                    }
                case .failed(let why):
                    VStack(spacing: 10) {
                        Text(why).font(.system(size: S(12.5))).foregroundStyle(Brand.red).multilineTextAlignment(.center)
                        ActionButton(title: "Try again", icon: "play") { lib.load(force: true) }
                    }.frame(maxWidth: .infinity, minHeight: S(200))
                default:
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Getting the recipes…").foregroundStyle(Brand.mute) }
                        .frame(maxWidth: .infinity, minHeight: S(200))
                }
                Text("Steerify is independent and open source, not affiliated with Anthropic.")
                    .font(.system(size: S(10.5))).foregroundStyle(Brand.mute.opacity(0.8))
            }
            .padding(S(24))
            .frame(width: S(860), height: S(620))
            .background(RoundedRectangle(cornerRadius: 16).fill(Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.line2))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 14)
        }
        .onAppear { lib.load() }
    }
}

struct RecipeCard: View {
    let recipe: Recipe
    let pick: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: pick) {
            VStack(alignment: .leading, spacing: 0) {
                RecipeCover(url: recipe.coverURL).frame(height: S(150)).clipped()
                VStack(alignment: .leading, spacing: S(6)) {
                    HStack {
                        Text(recipe.place).font(Brand.label(9.5)).tracking(1).foregroundStyle(Brand.amber)
                        Spacer()
                        if recipe.draft == true { Text("DRAFT").font(Brand.label(8.5)).foregroundStyle(Brand.mute)
                            .padding(.horizontal, 5).padding(.vertical, 1).overlay(RoundedRectangle(cornerRadius: 4).stroke(Brand.line2)) }
                    }
                    Text(recipe.name).font(.system(size: S(15), weight: .bold)).foregroundStyle(.white)
                    Text(recipe.line).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text("\(recipe.files.filter(\.required).count) files to fill · \(recipe.skills.count) skills")
                        .font(.system(size: S(10.5))).foregroundStyle(Brand.ink.opacity(0.7))
                }
                .padding(S(12))
                .frame(maxWidth: .infinity, minHeight: S(140), alignment: .topLeading)
            }
            .background(Brand.panel2)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(hover ? Brand.amber : Brand.line))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Start a project from this recipe")
    }
}

/// The recipe's picture of what you get (the book's build illustration).
struct RecipeCover: View {
    let url: URL?
    var body: some View {
        GeometryReader { g in
            if let url, let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: g.size.width, height: g.size.height).clipped()
            } else {
                Rectangle().fill(Brand.amberDim)
            }
        }
    }
}

// MARK: - A recipe project before setup (choice recipe-guided-screen A)

struct RecipeModal: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let recipe: Recipe
    @State private var tick = 0
    @State private var installing = false
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()   // files filled in TextEdit show ✓

    private var p: Project { board.project }
    private var started: Bool { board.lastLink("setup:" + p.id) != nil }

    var body: some View {
        let _ = tick
        let toGo = recipe.files.filter { $0.required && !recipe.filled($0) }.count
        let missing = recipe.missingSkills()
        ZStack {
            Color.black.opacity(0.55)
            HStack(alignment: .top, spacing: 0) {
                // What you get: the picture first, then in words (pick A + note: people see what the recipe makes).
                VStack(alignment: .leading, spacing: S(12)) {
                    RecipeCover(url: recipe.coverURL).frame(height: S(230)).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("WHAT YOU GET").font(Brand.label(10)).tracking(1.2).foregroundStyle(Brand.amber)
                    Text(recipe.youGet.isEmpty ? recipe.line : recipe.youGet)
                        .font(.system(size: S(12.5))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        Button("Read START-HERE") { open(recipe.start ?? "START-HERE.md") }
                        if let page = recipe.page, let u = URL(string: page) { Button("The build in the book ↗") { NSWorkspace.shared.open(u) } }
                    }
                    .buttonStyle(.plain).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.amber)
                }
                .padding(S(20))
                .frame(width: S(330))
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Brand.panel2)

                VStack(alignment: .leading, spacing: S(12)) {
                    HStack(spacing: 8) {
                        Text(recipe.name).font(.system(size: S(21), weight: .bold)).foregroundStyle(.white)
                        Spacer()
                        pill(recipe.place.isEmpty ? "RECIPE" : recipe.place, Brand.amber)
                        if missing.isEmpty { pill("SKILLS ✓ \(recipe.skills.count)", Brand.green) }
                        else { pill("\(missing.count) SKILLS MISSING", Brand.red) }
                    }
                    path(filling: toGo > 0)
                    if !missing.isEmpty {
                        HStack {
                            Text("Claude needs \(missing.count) skill\(missing.count == 1 ? "" : "s") of the AI Traction pack for this recipe.")
                                .font(.system(size: S(11.5))).foregroundStyle(Brand.ink)
                            Spacer()
                            ActionButton(title: installing ? "Installing…" : "Install for this project", icon: "play", primary: true) { install(missing) }
                        }
                        .padding(S(10)).background(RoundedRectangle(cornerRadius: 8).fill(Brand.red.opacity(0.08)))
                    }
                    Text("YOUR FILES").font(Brand.label(10)).tracking(1.2).foregroundStyle(Brand.mute)
                    ScrollView {
                        VStack(spacing: S(6)) { ForEach(recipe.files) { f in row(f) } }
                    }
                    Rectangle().fill(Brand.line).frame(height: 1)
                    HStack(alignment: .center) {
                        Text("Short is fine; empty is not. Use invented material for the first tests.")
                            .font(.system(size: S(11))).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(action: setUp) {
                            HStack(spacing: S(8)) {
                                ClaudeSpark(size: S(14), color: .white)
                                Text(started ? "Resume setup" : toGo > 0 ? "Set up · \(toGo) file\(toGo == 1 ? "" : "s") to go" : "Set up with Claude")
                                    .font(.system(size: S(14.5), weight: .semibold))
                            }
                            .foregroundStyle(.white).padding(.horizontal, S(20)).padding(.vertical, S(10))
                            .background(RoundedRectangle(cornerRadius: 9).fill(Brand.claude.opacity(toGo > 0 || !missing.isEmpty ? 0.45 : 1)))
                        }
                        .buttonStyle(SteerButton())
                        .disabled((toGo > 0 || !missing.isEmpty) && !started)
                        .keyboardShortcut(.defaultAction)
                        .help(toGo > 0 ? "Fill the files marked ○ first" : "Claude reads your files and starts with the interview")
                    }
                    Button("Skip, start with an empty board") {
                        ProjectSetup.skip(p.id)
                        NotificationCenter.default.post(name: .setupSkipped, object: nil)
                    }
                    .buttonStyle(.plain).font(.system(size: S(11))).foregroundStyle(Brand.mute).underline()
                }
                .padding(S(22))
            }
            .frame(width: S(900), height: S(600))
            .background(Brand.panel)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Brand.line2))
            .shadow(color: .black.opacity(0.7), radius: 40, y: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.bg)
        .onReceive(timer) { _ in tick += 1 }
        .onAppear {
            RecipeLibrary.shared.load()   // the pack's skills, for "Install for this project"
            // test hook, as SetupModal: `--setup-start` presses Set up after 1.5 s (with `--dry-sessions`: echoes the command)
            if CommandLine.arguments.contains("--background"), CommandLine.arguments.contains("--setup-start") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { setUp() }
            }
        }
    }

    private func pill(_ s: String, _ c: Color) -> some View {
        Text(s).font(Brand.label(9)).tracking(0.8).foregroundStyle(c)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 999).stroke(c.opacity(0.6)))
    }

    /// The steps ahead; the first one is where you are until the files are filled.
    private func path(filling: Bool) -> some View {
        let steps = recipe.steps.isEmpty ? ["Fill your files", "Interview", "Roadmap", "To test"] : recipe.steps
        return HStack(spacing: 5) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                if i > 0 { Text("→").font(.system(size: S(10))).foregroundStyle(Brand.mute) }
                let on = filling ? i == 0 : i == 1
                Text("\(i + 1) \(s)").font(.system(size: S(10.5), weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Brand.amber : Brand.mute)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 999).fill(on ? Brand.amberDim : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 999).stroke(on ? Brand.amber : Brand.line2))
                    .lineLimit(1).fixedSize()
            }
        }
    }

    private func row(_ f: Recipe.File) -> some View {
        let done = recipe.filled(f)
        return HStack(spacing: S(10)) {
            Text(done ? "✓" : f.required ? "○" : "·").font(.system(size: S(13), weight: .bold))
                .foregroundStyle(done ? Brand.green : Brand.mute).frame(width: S(14))
            Text(f.path).font(.system(size: S(12.5), weight: .semibold, design: .monospaced)).foregroundStyle(done ? Brand.ink : .white)
            Text(done ? (recipe.count(f) ?? f.hint) : f.hint).font(.system(size: S(11))).foregroundStyle(Brand.mute).lineLimit(1)
            Spacer(minLength: 4)
            if !f.required && !done { Text("optional").font(.system(size: S(10))).foregroundStyle(Brand.mute) }
            Button(f.isFolder ? "Show" : "Open") { open(f.path) }
                .buttonStyle(.plain).font(.system(size: S(11), weight: .semibold)).foregroundStyle(Brand.amber)
                .help(f.isFolder ? "Opens the folder in Finder: drop your files in it" : "Opens the file in TextEdit")
        }
        .padding(.horizontal, S(10)).padding(.vertical, S(7))
        .background(RoundedRectangle(cornerRadius: 8).fill(done ? Brand.green.opacity(0.05) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.line))
    }

    /// Plain files open in TextEdit (no code editor for a reader who isn't technical); folders and tables as usual.
    private func open(_ rel: String) {
        let url = recipe.folder.appendingPathComponent(rel)
        let ext = url.pathExtension.lowercased()
        if ["md", "txt"].contains(ext), let te = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: te, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func install(_ names: [String]) {
        installing = true
        let lib = RecipeLibrary.shared
        func go() {
            let left = RecipeInstall.installSkills(names, into: recipe.folder)
            installing = false
            tick += 1
            if !left.isEmpty { model.showToast("Not in the pack: " + left.joined(separator: ", ")) }
        }
        if lib.state == .ready { go() }
        else {
            lib.load()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { go() }
        }
    }

    private func setUp() {
        PastConversations.link(p, board: board)
        model.start(projectId: p.id, item: ProjectSetup.ref(p), intent: .initialize, dry: CommandLine.arguments.contains("--dry-sessions"),
                    extraBrief: recipe.setupBrief)
    }
}
