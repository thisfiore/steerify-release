import SwiftUI
import AppKit

// MARK: - Roadmap chapter order (choice roadmap-chapter-order, request r261123-222632-fb248902)

extension Prefs {
    /// Chapter order per project: lines "projectId=mode" (activity | name | created).
    static let roadOrder = "roadOrder"
    /// Browser for test links: the app's path, "" = the system default (request r261124-145319-fbb8c4c0).
    static let testBrowser = "testBrowser"
}

enum RoadOrder: String, CaseIterable, Identifiable {
    case activity, name, created
    var id: String { rawValue }
    var title: String { ["activity": "Latest activity", "name": "Name / number", "created": "Created"][rawValue]! }
    var short: String { ["activity": "Activity", "name": "Name", "created": "Created"][rawValue]! }
    var help: String {
        ["activity": "The chapter with the latest status change, delivery or session first",
         "name": "By name, numbers in order: Ch 1, Ch 2 … Ch 10; chapters without a number after",
         "created": "Oldest chapter first, the order they were added"][rawValue]!
    }

    static func mode(_ projectId: String, in stored: String) -> RoadOrder {
        for line in stored.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0] == projectId { return RoadOrder(rawValue: String(kv[1])) ?? .activity }
        }
        return .activity
    }
    static func set(_ m: RoadOrder, _ projectId: String, in stored: String) -> String {
        var lines = stored.split(separator: "\n").map(String.init).filter { !$0.hasPrefix(projectId + "=") }
        if m != .activity { lines.append(projectId + "=" + m.rawValue) }
        return lines.joined(separator: "\n")
    }

    /// Natural order: a numbered chapter ("Ch 2 · …", "3. …", "Chapter 10") before an unnumbered one; numbers compare
    /// as numbers (Finder's order), so Ch 2 comes before Ch 10.
    static func nameLess(_ a: String, _ b: String) -> Bool {
        let na = numbered(a), nb = numbered(b)
        if na != nb { return na }
        return a.localizedStandardCompare(b) == .orderedAscending
    }
    static func numbered(_ s: String) -> Bool { s.range(of: #"^\D{0,10}\d"#, options: .regularExpression) != nil }
}

/// Sort menu at the end of the Roadmap filter line, remembered per project.
struct RoadOrderMenu: View {
    let projectId: String
    @AppStorage(Prefs.roadOrder, store: Prefs.store) private var stored = ""
    var body: some View {
        let mode = RoadOrder.mode(projectId, in: stored)
        Menu {
            ForEach(RoadOrder.allCases) { m in
                Button { stored = RoadOrder.set(m, projectId, in: stored) } label: {
                    if m == mode { Label(m.title, systemImage: "checkmark") } else { Text(m.title) }
                }.help(m.help)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: S(10)))
                Text("Sort: " + mode.short).font(.system(size: S(11.5)))
            }
            .foregroundStyle(mode == .activity ? Brand.ink : Color(hex: 0xffd27a))
        }
        .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
        .help("Chapter order: \(mode.help). ★ Focus and drafts stay on top.")
    }
}

// MARK: - Browser for test links (request r261124-145319-fbb8c4c0)

enum TestBrowser {
    /// Browsers installed on this Mac (anything that opens https), system default first.
    static func installed() -> [URL] {
        let probe = URL(string: "https://example.com")!
        var all = NSWorkspace.shared.urlsForApplications(toOpen: probe)
        if let d = NSWorkspace.shared.urlForApplication(toOpen: probe) { all.removeAll { $0 == d }; all.insert(d, at: 0) }
        // Real browsers only: apps in an Applications folder (not test copies in caches / node_modules), minus apps
        // that take https links without being browsers (terminals, automation tools).
        all = all.filter { u in
            let p = u.path, id = Bundle(url: u)?.bundleIdentifier ?? ""
            return (p.hasPrefix("/Applications/") || p.contains("/System/Applications/") || p.hasPrefix(NSHomeDirectory() + "/Applications/"))
                && !notBrowsers.contains(id)
        }
        var seen = Set<String>()
        return all.filter { seen.insert(name($0)).inserted }
    }
    static let notBrowsers: Set<String> = ["com.googlecode.iterm2", "org.latenitefilms.CommandPost", "com.apple.Terminal",
                                           "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "net.kovidgoyal.kitty"]
    static func name(_ app: URL) -> String { FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "") }
    static func icon(_ app: URL) -> NSImage {
        let i = NSWorkspace.shared.icon(forFile: app.path); i.size = NSSize(width: 16, height: 16); return i
    }
    /// The browser picked in Settings, if it is still installed.
    static var chosen: URL? {
        guard let p = Prefs.store.string(forKey: Prefs.testBrowser), !p.isEmpty, FileManager.default.fileExists(atPath: p) else { return nil }
        return URL(fileURLWithPath: p)
    }
    static var systemDefault: URL? { NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) }
}

/// Right-click on a test link: open it in one of the installed browsers.
struct OpenInMenu: View {
    let url: URL
    var body: some View {
        if url.scheme == "steerify" { EmptyView() } else {
            ForEach(TestBrowser.installed(), id: \.self) { app in
                Button { openTestLink(url, in: app) } label: { Label { Text("Open in " + TestBrowser.name(app)) } icon: { Image(nsImage: TestBrowser.icon(app)) } }
            }
            Divider()
            Button("Copy link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) }
        }
    }
}

/// Settings → Behaviour → Test links.
struct TestBrowserRow: View {
    @AppStorage(Prefs.testBrowser, store: Prefs.store) private var path = ""
    @State private var apps: [URL] = []
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtIcon(name: "globe", size: 28, tile: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Open test links in").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.ink)
                Text("The browser for links on To test cards and choices. Right-click a link to open it in another one.")
                    .font(.system(size: 11.5)).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Picker("", selection: $path) {
                Text("System default" + (TestBrowser.systemDefault.map { " (\(TestBrowser.name($0)))" } ?? "")).tag("")
                ForEach(apps, id: \.self) { a in Text(TestBrowser.name(a)).tag(a.path) }
                if !path.isEmpty, !apps.contains(where: { $0.path == path }) { Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent).tag(path) }
            }
            .labelsHidden().frame(width: 200)
        }
        .padding(12)
        .onAppear { apps = TestBrowser.installed() }
    }
}
