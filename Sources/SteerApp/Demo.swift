import Foundation

/// "Try the demo project": Tiny Todo, a small todo app with a real board (a delivery to test, a choice, a roadmap).
/// The app carries a frozen copy (Resources/demo/tiny-todo, from `scripts/demo-freeze.mjs`); the first time it is
/// copied to Application Support/Steerify/Demo/tiny-todo and made a git repo, so sessions can work on it like any project.
enum DemoProject {
    static let id = "tiny-todo"

    /// The bundled copy (the app), or the repo's demo/ folder (a `swift run` build).
    static var source: URL? {
        let fm = FileManager.default
        if let r = Bundle.main.resourceURL?.appendingPathComponent("demo/tiny-todo"), fm.fileExists(atPath: r.path) { return r }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../demo/tiny-todo").standardizedFileURL
        return fm.fileExists(atPath: repo.path) ? repo : nil
    }

    /// `STEERIFY_DEMO_DIR=<dir>` installs it elsewhere (test copies).
    static var folder: URL {
        if let d = ProcessInfo.processInfo.environment["STEERIFY_DEMO_DIR"], !d.isEmpty { return URL(fileURLWithPath: d, isDirectory: true).appendingPathComponent("tiny-todo") }
        return ProjectStore.dir.appendingPathComponent("Demo/tiny-todo", isDirectory: true)
    }

    /// The demo's folder, copied (once) from the bundled copy. nil when the app has no demo inside.
    static func install() -> String? {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent(".steerify/steerify.json").path) { return folder.path }
        guard let src = source else { return nil }
        try? fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? fm.copyItem(at: src, to: folder)) != nil else { return nil }
        try? fm.removeItem(at: folder.appendingPathComponent(".frozen"))
        git(["init", "-q", "-b", "main"])
        git(["add", "-A"])
        git(["-c", "user.name=Steerify", "-c", "user.email=demo@steerify.dev", "commit", "-q", "-m", "Tiny Todo: the Steerify demo project"])
        return folder.path
    }

    private static func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = folder
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}

extension AppModel {
    /// Opens Tiny Todo (installing it the first time) and selects it.
    func openDemo() {
        if let p = projects.first(where: { $0.id == DemoProject.id }) { selectedProjectId = p.id; return }
        guard let folder = DemoProject.install() else { showToast("The demo project isn't in this build"); return }
        addWorkspace(folder: folder)
        if project?.id == DemoProject.id { showToast("Tiny Todo: a demo with a real board. Look around.", projectId: DemoProject.id) }
    }
}
