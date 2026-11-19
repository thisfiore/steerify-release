import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var testWindow: NSWindow?

    /// Test copies (`--background`) are never activated, and SwiftUI only presents its window on activation:
    /// build the same window here and put it on screen without taking focus.
    @MainActor private func openTestWindow() {
        let a0 = CommandLine.arguments
        if let i = a0.firstIndex(of: "--tab"), i + 1 < a0.count { Prefs.store.set(a0[i + 1], forKey: Prefs.boardTab) }
        let m = AppModel()
        model = m
        let root = ContentView()
            .environmentObject(m)
            .frame(minWidth: 980, minHeight: 600)
            .preferredColorScheme(.dark)
            .tint(Brand.amber)
        let panelOnly = a0.contains("--menubar")
        let host = panelOnly
            ? NSHostingController(rootView: AnyView(MenuBarPanel().environmentObject(m)))
            : NSHostingController(rootView: AnyView(root))
        host.sceneBridgingOptions = [.toolbars, .title]
        host.sizingOptions = []                       // keep our size, not the content's ideal size
        let size = panelOnly ? NSSize(width: 320, height: 760) : NSSize(width: 1500, height: 940)
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.contentViewController = host
        w.setContentSize(size)
        w.toolbarStyle = .unifiedCompact
        w.isRestorable = false
        w.orderFrontRegardless()
        testWindow = w
        // `--snapshot <file.png> [seconds]`: render the window (titlebar + toolbar included) to a PNG, then quit.
        let a = CommandLine.arguments
        if a.contains("--snapshot") {
            // Snapshot runs render without ever showing: transparent, click-through (cacheDisplay still draws it).
            w.alphaValue = 0
            w.ignoresMouseEvents = true
        }
        if let i = a.firstIndex(of: "--snapshot"), i + 1 < a.count {
            let out = a[i + 1]
            let delay = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let v = w.contentView?.superview ?? w.contentView!
                if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                NSApp.terminate(nil)
            }
        }
        SteerApp.applyTestArgs(m)
        m.startAutomation()
    }
    func applicationWillFinishLaunching(_ n: Notification) {
        // Steerify remembers its own state (project, tab, sizes); macOS window restoration would reopen
        // only the Settings window and skip the main one.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")  // (system key)
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        SkillInstaller.install()
        SessionHooks.install()          // hooks + this copy's MCP config, before any session (restored ones too) starts
        // Test runs (`--background`) stay out of the Dock and the app switcher.
        NSApp.setActivationPolicy(CommandLine.arguments.contains("--background") ? .accessory : .regular)
        // Test runs (`--background`) must never take focus from what the user is doing.
        if !CommandLine.arguments.contains("--background") { NSApp.activate(ignoringOtherApps: true) }
        else { MainActor.assumeIsolated { openTestWindow() } }
    }
    func applicationWillTerminate(_ n: Notification) {
        MainActor.assumeIsolated { model?.shutdown() }
    }
    /// Closing the window never quits: sessions keep running, Steerify stays in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool {
        CommandLine.arguments.contains("--background")
    }

    /// Dock click with no window → bring the main window back.
    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { MainActor.assumeIsolated { AppModel.reopenWindow?() } }
        return true
    }

    /// ⌘Q with Claude sessions at work: ask first (their conversations can be resumed, the running step is lost).
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard let m = model, !m.quittingForUpdate, !CommandLine.arguments.contains("--background") else { return .terminateNow }
            let working = m.sessions.filter { $0.kind == .claude && $0.running && $0.status == .working }.count
            guard working > 0 else { return .terminateNow }
            let a = NSAlert()
            a.messageText = "\(working) session\(working == 1 ? " is" : "s are") still rowing"
            a.informativeText = "Quitting stops \(working == 1 ? "it" : "them") mid-step. Conversations come back when you reopen Steerify, the running step doesn't."
            a.addButton(withTitle: "Keep working")
            a.addButton(withTitle: "Quit anyway")
            return a.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
        }
    }
}

/// One binary, two modes: `Steerify --mcp` is the MCP server for Claude sessions; otherwise the app.
@main
enum SteerifyMain {
    static func main() {
        if CommandLine.arguments.contains("--mcp") { SteerifyMCP.run() }
        if let i = CommandLine.arguments.firstIndex(of: "--local-ai-check"), i + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[i + 1]
            Task { @MainActor in await LocalAICheck.run(dir) }
            dispatchMain()
        }
        SteerApp.main()
    }
}

struct SteerApp: App {
    /// Test hooks (--project, --tab, --palette, --focus, --settings, --open-shells, --selftest-write).
    @MainActor static func applyTestArgs(_ m: AppModel) {
        // Test hook: `open Steerify.app --args --open-shells N` opens N shell sessions (perf measuring).
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--project"), i + 1 < a.count, m.projects.contains(where: { $0.id == a[i + 1] }) { m.selectedProjectId = a[i + 1] }
        // Test hook: `--add-folder <path>` adds any folder as a project, as Add project… does after the panel.
        if let i = a.firstIndex(of: "--add-folder"), i + 1 < a.count { m.addWorkspace(folder: a[i + 1]) }
        if let i = a.firstIndex(of: "--palette"), i + 1 < a.count { m.paletteSeed = a[i + 1]; m.paletteOpen = true }
        // Test hook: `--request "<text>"` opens the New request sheet with that text typed in.
        if let i = a.firstIndex(of: "--request"), i + 1 < a.count { m.requestSeed = a[i + 1]; m.requestOpen = true }
        // `--request-pick` opens it as ⌃⌥N does (project pills); `--request-for <id>` picks another project 1.5 s in.
        if a.contains("--request-pick") { m.requestPickProject = true }
        if let i = a.firstIndex(of: "--request-for"), i + 1 < a.count { let id = a[i + 1]; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { m.requestProjectId = id } }
        if let i = a.firstIndex(of: "--focus"), i + 1 < a.count, let p = m.project {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { m.openCombo(projectId: p.id, ref: a[i + 1], startNew: false) }
        }
        if a.contains("--settings") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) } }
        if let i = a.firstIndex(of: "--tab"), i + 1 < a.count { Prefs.store.set(a[i + 1], forKey: "boardTab") }
        // Test hook: `--preview test:<id>` opens the preview of that item's pictures.
        if let i = a.firstIndex(of: "--preview"), i + 1 < a.count, let p = m.project {
            let b = m.board(for: p), ref = a[i + 1]
            if let s = b.ships.first(where: { "test:" + $0.id == ref }) {
                let imgs = s.shots.map(\.img) + s.tests.compactMap(\.img)
                m.preview = PreviewState(projectId: p.id, ref: ref, title: s.title, dir: p.boardDir, images: imgs,
                                         index: a.firstIndex(of: "--preview-index").flatMap { $0 + 1 < a.count ? Int(a[$0 + 1]) : nil }.map { min($0, max(imgs.count - 1, 0)) } ?? 0, version: s.version)
            } else if let d = b.decisions.first(where: { "choice:" + $0.id == ref }) {
                // Choices: the option pictures (shots, or drawn mockups once rendered), 2 s in so mockups can render.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let imgs = d.gallery.map(\.img) + d.options.compactMap { $0.shot ?? MockSnapshots.shared.picture(for: $0, boardDir: p.boardDir) }
                    if !imgs.isEmpty { m.preview = PreviewState(projectId: p.id, ref: ref, title: d.title, dir: p.boardDir, images: imgs, index: 0, version: nil) }
                }
            }
        }
        // Self-test of the writer on a scratch workspace: `--selftest-write <dir>` writes 3 verdicts and quits.
        if let i = a.firstIndex(of: "--selftest-write"), i + 1 < a.count, let p = ProjectStore.read(a[i + 1]) {
            let b = BoardStore(project: Project(id: p.id, name: p.name, boardDir: p.boardDir, port: 0, repos: p.repos))
            if let s = b.ships.first { b.setShip(s, pick: "refine", note: "selftest note") }
            if let d = b.decisions.first(where: { !b.isDecided($0) }) { b.setChoice(d, pick: d.options.first?.id) }
            if let r = b.requirements.first(where: { $0.status != "rule" }) { b.setRequirement(r, pick: "agree") }
            if let s = b.ships.first, let img = s.shots.first?.img { b.addPin("test:" + s.id, img: img, x: 0.25, y: 0.4, note: "selftest pin") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.terminate(nil) }
        }
        // `--deploy <repo>` presses that repo's Deploy on the Release tab 2.5 s in.
        if let i = a.firstIndex(of: "--deploy"), i + 1 < a.count, let p = m.project, let r = p.repos.first(where: { $0.name == a[i + 1] }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { m.deploy(r, in: p) }
        }
        if let i = a.firstIndex(of: "--flow-demo"), i + 1 < a.count { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SessionFlowDemo.run(m, a[i + 1]) } }
        if let i = a.firstIndex(of: "--open-shells"), i + 1 < a.count, let n = Int(a[i + 1]) {
            for k in 0..<n { m.newSession(.shell, repo: m.project?.repos[k % max(1, m.project?.repos.count ?? 1)]) }
        }
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @AppStorage(Prefs.fontPreset, store: Prefs.store) private var preset: String = Prefs.Size.medium.rawValue
    @AppStorage(Prefs.boardTab, store: Prefs.store) private var boardTab: BoardTab = .test
    @AppStorage("menuBarShown", store: Prefs.store) private var menuBarShown = true

    var body: some Scene {
        Window(ProjectStore.appName, id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 600)
                .preferredColorScheme(.dark)
                .tint(Brand.amber)
                .id(preset)                                   // rebuild the UI at the new text size
                .onChange(of: preset) { _, _ in model.applyFonts() }
                .onOpenURL { model.handle($0) }
                .onAppear {
                    delegate.model = model
                    model.restoreSessions()
                    model.watchForUpdates()
                    model.startAutomation()
                    SteerApp.applyTestArgs(model)
                    if !CommandLine.arguments.contains("--background") { GlobalHotKey.install(model) }
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultLaunchBehavior(.presented)          // always open the main window at launch (fresh installs too)
        .commands {
            CommandMenu("Projects") {
                ForEach(0..<9, id: \.self) { i in
                    Button(i < model.projects.count ? model.projects[i].name : "Project \(i + 1)") { model.select(index: i) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
                        .disabled(i >= model.projects.count)
                }
                Divider()
                Button("Reload board") { model.reloadBoard() }.keyboardShortcut("r", modifiers: .command)
                Button("Restart to Update") { model.restartForUpdate() }.keyboardShortcut("r", modifiers: [.command, .option])
                Button("Add project…") { model.addWorkspace() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Show steerify.json") { if let p = model.project { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.manifest)]) } }
            }
            CommandGroup(after: .sidebar) {
                Button("Sessions: Tabs on Top / List Beside") {
                    let cur = SessionLayout(rawValue: Prefs.store.string(forKey: "sessionLayout") ?? "") ?? .tabs
                    Prefs.store.set((cur == .tabs ? SessionLayout.list : .tabs).rawValue, forKey: "sessionLayout")
                }.keyboardShortcut("b", modifiers: .command)
            }
            CommandMenu("Board") {
                Button("Search Sessions and Items…") { model.paletteOpen.toggle() }.keyboardShortcut("k", modifiers: .command)
                Button("Next Thing for You") { model.jumpNext() }.keyboardShortcut("j", modifiers: .command)
                Divider()
                ForEach(Array(BoardTab.allCases.enumerated()), id: \.offset) { i, t in
                    Button(t.title.capitalized) { boardTab = t }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
                Divider()
                Button("Next Tab") { boardTab = BoardTab.allCases[(BoardTab.allCases.firstIndex(of: boardTab)! + 1) % BoardTab.allCases.count] }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Previous Tab") { boardTab = BoardTab.allCases[(BoardTab.allCases.firstIndex(of: boardTab)! + BoardTab.allCases.count - 1) % BoardTab.allCases.count] }
                    .keyboardShortcut("[", modifiers: .command)
                Divider()
                Button("Next Session") { model.cycleSession(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Session") { model.cycleSession(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            }
            // ⌘W closes the current terminal session (never the app). Replaces the standard Close.
            CommandGroup(replacing: .saveItem) {
                Button("Close Session") { model.closeCurrent() }
                    .keyboardShortcut("w", modifiers: .command)
                    .disabled(model.project.flatMap { model.current(of: $0.id) } == nil)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Request…") { model.requestOpen = true }.keyboardShortcut("n", modifiers: .command)
                    .disabled(model.project == nil)
                Divider()
                Button("New Claude session") { model.newSession(.claude) }.keyboardShortcut("t", modifiers: .command)
                Button("New shell") { model.newSession(.shell) }.keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w", modifiers: [.command, .shift])
            }
        }
        // Menu bar: status + what waits on you. Never for test copies (no second icon on the user's bar).
        MenuBarExtra(isInserted: Binding(get: { menuBarShown && !CommandLine.arguments.contains("--background") },
                                         set: { menuBarShown = $0 })) {
            MenuBarPanel().environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView().environmentObject(model).tint(Brand.amber).id(preset)
        }
}
}
