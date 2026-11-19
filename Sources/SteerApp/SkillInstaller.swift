import Foundation

/// Installs the built-in steerify skill for Claude Code (~/.claude/skills/steerify) from the app bundle.
/// Updates it when the bundled copy changes; leaves it alone if the user has edited it (marker line removed).
enum SkillInstaller {
    static let marker = "<!-- installed by Steerify; edit freely and remove this line to keep your version -->"

    static func install() {
        installKit()
        guard let src = Bundle.main.url(forResource: "SKILL", withExtension: "md", subdirectory: "skills/steerify"),
              let bundled = try? String(contentsOf: src, encoding: .utf8) else { return }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/steerify")
        let dst = dir.appendingPathComponent("SKILL.md")
        let wanted = bundled + "\n" + marker + "\n"
        if let current = try? String(contentsOf: dst, encoding: .utf8) {
            if current == wanted || !current.contains(marker) { return }   // up to date, or user-owned
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? wanted.write(to: dst, atomically: true, encoding: .utf8)
    }

    /// The prototype kit engine and its how-to (~/.claude/skills/steerify/kit): Steerify's own files, kept current.
    static func installKit() {
        guard let src = Bundle.main.url(forResource: "kit", withExtension: nil, subdirectory: "skills/steerify") else { return }
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/steerify/kit")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in (try? fm.contentsOfDirectory(atPath: src.path)) ?? [] {
            let a = src.appendingPathComponent(name), b = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: a), (try? Data(contentsOf: b)) != data else { continue }
            try? data.write(to: b, options: .atomic)
        }
    }
}
