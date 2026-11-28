import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel? { didSet { flushOpened() } }
    /// URLs that arrive before the window (and its model) exist: a folder dropped on the Dock icon at launch.
    private var opened: [URL] = []
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
        // `--fake-update <version>`: the top bar as it looks when a downloaded update waits (screenshots).
        if let i = a0.firstIndex(of: "--fake-update"), i + 1 < a0.count { AppUpdater.shared.fake(a0[i + 1], m) }
        let panelOnly = a0.contains("--menubar")
        let whatsNew = a0.contains("--whats-new")   // the version badge's panel alone (with --fake-update: the update's)

        let manager = a0.contains("--projects")     // the Projects window (⇧⌘P) alone
        let host = whatsNew
            ? NSHostingController(rootView: AnyView((AppUpdater.shared.readyVersion.map { WhatsNewPanel(version: $0, titles: AppUpdater.shared.readyTitles, restart: {}, close: {}) } ?? WhatsNewPanel(close: {})).background(Brand.bg).preferredColorScheme(.dark)))
            : panelOnly
            ? NSHostingController(rootView: AnyView(MenuBarPanel().environmentObject(m)))
            : manager ? NSHostingController(rootView: AnyView(ProjectManagerView().environmentObject(m).preferredColorScheme(.dark).tint(Brand.amber)))
            : NSHostingController(rootView: AnyView(root))
        host.sceneBridgingOptions = [.toolbars, .title]
        host.sizingOptions = []                       // keep our size, not the content's ideal size
        // `--window-width <n>`: the main window at that width (top bar density shots).
        let mainW = a0.firstIndex(of: "--window-width").flatMap { $0 + 1 < a0.count ? Double(a0[$0 + 1]) : nil } ?? 1500
        // `--window-height <n>`: taller test shots (a whole To test card).
        let mainH = a0.firstIndex(of: "--window-height").flatMap { $0 + 1 < a0.count ? Double(a0[$0 + 1]) : nil } ?? 940
        let size = whatsNew ? NSSize(width: 380, height: 330) : panelOnly ? NSSize(width: 320, height: 760) : manager ? NSSize(width: 960, height: 620) : NSSize(width: mainW, height: mainH)
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.contentViewController = host
        w.setContentSize(size)
        w.toolbarStyle = .unifiedCompact
        w.isRestorable = false
        w.identifier = NSUserInterfaceItemIdentifier("main-test")   // the window questions attach to (FolderDrop.swift)
        w.orderFrontRegardless()
        testWindow = w
        // `--snapshot <file.png> [seconds]`: render the window (titlebar + toolbar included) to a PNG, then quit.
        let a = CommandLine.arguments
        if a.contains("--snapshot") || a.contains("--scroll-bench") || a.contains("--churn-bench") || a.contains("--switch-bench") {
            // Snapshot and speed runs render without ever showing: transparent, click-through (the window still lays
            // out and draws, so the timings hold; nothing appears over what you are doing).
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
        // Test hook: `--talk-run <run id> [seconds]`: the Session / Talk to Claude button of that task run (Tasks.swift).
        if let i = a.firstIndex(of: "--talk-run"), i + 1 < a.count {
            let id = a[i + 1], at = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 4
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                guard let pid = m.selectedProjectId, let p = m.projects.first(where: { $0.id == pid }),
                      let run = TaskStore.load(p.boardDir).runs.first(where: { $0.id == id }) else { NSLog("talk-run: no run \(id)"); return }
                NSLog("talk-run: \(id) → \(m.runTalk(projectId: pid, run: run))")
                m.talkAboutRun(projectId: pid, run: run)
            }
        }
        // Test hook: `--type-note "<placeholder>" "<text>" [wait|leave]` focuses the first note box with that
        // placeholder 3 s in and types the text through its field editor (as a person would). `wait` does nothing else;
        // `leave` switches to the Roadmap tab 0.1 s later (the box goes away before any debounce).
        if let i = a.firstIndex(of: "--type-note"), i + 2 < a.count {
            let ph = a[i + 1], text = a[i + 2], then = i + 3 < a.count ? a[i + 3] : "wait"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                func find(_ v: NSView) -> NSView? {
                    if let f = v as? NSTextField, f.isEditable, (f.placeholderString ?? "").hasPrefix(ph) { return f }
                    for s in v.subviews { if let hit = find(s) { return hit } }
                    return nil
                }
                guard let root = w.contentView, let field = find(root) else { NSLog("type-note: no field '\(ph)'"); return }
                w.makeFirstResponder(field)
                (w.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
                NSLog("type-note: typed into '\(ph)'")
                if then == "leave" { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { Prefs.store.set(BoardTab.road.rawValue, forKey: Prefs.boardTab) } }
            }
        }
        // Test hook: `--wheel-note <text prefix> <lines>`: a trackpad scroll over the note box whose text starts with
        // the prefix, sent through the window like a real one (hit-testing included). Logs what moved.
        if let i = a.firstIndex(of: "--wheel-note"), i + 2 < a.count, let lines = Double(a[i + 2]) {
            let prefix = a[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                func find(_ v: NSView) -> NSTextView? {
                    if let t = v as? NSTextView, t.string.hasPrefix(prefix) { return t }
                    for s in v.subviews { if let hit = find(s) { return hit } }
                    return nil
                }
                guard let root = w.contentView, let tv = find(root) else { NSLog("wheel-note: no note '\(prefix)'"); return }
                let r = tv.enclosingScrollView ?? tv
                let mid = r.convert(NSPoint(x: r.bounds.midX, y: r.bounds.midY), to: nil)
                let before = tv.visibleRect.minY
                let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-lines * 16), wheel2: 0, wheel3: 0)!
                ev.location = CGPoint(x: w.frame.minX + mid.x, y: (NSScreen.screens.first?.frame.height ?? 0) - (w.frame.minY + mid.y))
                if let e = NSEvent(cgEvent: ev) { w.sendEvent(e) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NSLog("wheel-note: box \(Int(r.bounds.height)) pt, text \(Int(tv.bounds.height)) pt, scrolled \(Int(before)) → \(Int(tv.visibleRect.minY))")
                }
            }
        }
        // Test hook: `--click <x> <y> [seconds]`: a real mouse click at that point of the window (points, from the
        // top-left of the content), as a person would (no Accessibility permission needed). Repeatable.
        // Test hook: `--cmd-click x y [seconds]`: a click with ⌘ held (pin a note, open ready to pin).
        for (i, s) in a.enumerated() where s == "--cmd-click" && i + 2 < a.count {
            guard let x = Double(a[i + 1]), let y = Double(a[i + 2]) else { continue }
            let at = (i + 3 < a.count ? Double(a[i + 3]) : nil) ?? 4
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { PerfBench.click(w, x: x, y: y, flags: .command) }
        }
        for (i, s) in a.enumerated() where s == "--click" && i + 2 < a.count {
            guard let x = Double(a[i + 1]), let y = Double(a[i + 2]) else { continue }
            let at = (i + 3 < a.count ? Double(a[i + 3]) : nil) ?? 4
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { PerfBench.click(w, x: x, y: y) }
        }
        // Test hook: `--keys <chars> [seconds]`: type these keys into the window (one every 0.6 s, "_" = Space), e.g.
        // `--preview test:x --keys __ 3` walks the full-screen preview with Space.
        if let i = a.firstIndex(of: "--keys"), i + 1 < a.count {
            let keys = Array(a[i + 1]), at = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 3
            for (n, k) in keys.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + at + Double(n) * 0.6) {
                    // "_" = space, ">" / "<" = the arrow keys.
                    let arrow = k == ">" ? 124 : k == "<" ? 123 : 0
                    let c = k == "_" ? " " : arrow > 0 ? String(UnicodeScalar(arrow == 124 ? NSRightArrowFunctionKey : NSLeftArrowFunctionKey)!) : String(k)
                    let code: UInt16 = k == "_" ? 49 : UInt16(arrow)
                    for t in [NSEvent.EventType.keyDown, .keyUp] {
                        if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: w.windowNumber, context: nil, characters: c, charactersIgnoringModifiers: c,
                                                    isARepeat: false, keyCode: code) { NSApp.postEvent(e, atStart: false) }
                    }
                }
            }
        }
        // Test hook: `--shot <file.png> [seconds]`: like --snapshot, but the window stays visible (an invisible window
        // is not redrawn after a click, so live changes need this one).
        if let i = a.firstIndex(of: "--shot"), i + 1 < a.count {
            let out = a[i + 1], at = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                let v = w.contentView?.superview ?? w.contentView!
                if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                NSApp.terminate(nil)
            }
        }
        // Test hook: `--press-update [seconds]` (with --background): press Update in the top bar (a click can't reach
        // the toolbar). With Claude sessions at work it asks first; the restart itself is only logged.
        if let i = a.firstIndex(of: "--press-update"), a.contains("--background") {
            let at = (i + 1 < a.count ? Double(a[i + 1]) : nil) ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { m.confirmRestartForUpdate() }
        }
        // Test hook: `--scroll-bench <out.json> [seconds]`: scroll the board list top → bottom → top in 60 pt steps,
        // timing each frame (layout + draw), then write {frames, avgMs, p95Ms, maxMs} and quit. The roadmap's scroll budget.
        if let i = a.firstIndex(of: "--scroll-bench"), i + 1 < a.count {
            let out = a[i + 1], at = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { PerfBench.scroll(w, out: out) }
        }
        // Test hook: `--switch-bench <out.json> <other project id> [seconds]`: switch to the other project and back 4 times,
        // timing each switch until the window has drawn it (the first one is cold: that board was never opened).
        if let i = a.firstIndex(of: "--switch-bench"), i + 2 < a.count {
            let out = a[i + 1], other = a[i + 2], at = (i + 3 < a.count ? Double(a[i + 3]) : nil) ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { PerfBench.switchProjects(w, m, to: other, out: out) }
        }
        // Test hook: `--churn-bench <out.json> [seconds]`: 120 changes of the app's shared state, then the mouse down the
        // board list, each timed until the window has drawn again. What the board costs while you work beside it.
        if let i = a.firstIndex(of: "--churn-bench"), i + 1 < a.count {
            let out = a[i + 1], at = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { PerfBench.churn(w, m, out: out) }
        }
        // Test hook: `--hold-switch-loader <project name> [seconds]`: show the switch loader and keep it (for --shot).
        if let i = a.firstIndex(of: "--hold-switch-loader"), i + 1 < a.count {
            let name = a[i + 1], at = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 4
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { SwitchLoader.shared.show(name, hold: true) }
        }
        SteerApp.applyTestArgs(m)
        m.startAutomation()
    }
    func applicationWillFinishLaunching(_ n: Notification) {
        Self.raiseFileLimit()
        // Steerify remembers its own state (project, tab, sizes); macOS window restoration would reopen
        // only the Settings window and skip the main one.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")  // (system key)
    }
    /// A Mac app starts with a soft limit of 256 open files. Each session holds a terminal and several pipes,
    /// so a restore of ~40 sessions used them all and the next one said "Process launch failed: forkFailed(24)"
    /// (EMFILE; request r261123-122630). Raise the soft limit as far as the system allows, before any session starts.
    static func raiseFileLimit() {
        var rl = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &rl) == 0 else { return }
        var maxFiles: Int32 = 0; var size = MemoryLayout<Int32>.size
        let perProc = sysctlbyname("kern.maxfilesperproc", &maxFiles, &size, nil, 0) == 0 ? rlim_t(maxFiles) : 10240
        let want = min(rl.rlim_max, perProc)
        guard want > rl.rlim_cur else { return }
        rl.rlim_cur = want
        _ = setrlimit(RLIMIT_NOFILE, &rl)
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
    /// Every URL the app is asked to open: steerify:// links, and folders dropped on the Dock icon or opened
    /// with Steerify from Finder (Info.plist declares public.folder). One place, so each is handled once.
    func application(_ app: NSApplication, open urls: [URL]) {
        opened += urls
        flushOpened()
    }
    private func flushOpened() {
        guard let m = model, !opened.isEmpty else { return }
        let urls = opened; opened = []
        MainActor.assumeIsolated {
            let folders = urls.filter(\.isFileURL).map(\.path)
            if !folders.isEmpty { m.openFolders(folders) }
            urls.filter { !$0.isFileURL }.forEach(m.handle)
        }
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
        if let i = CommandLine.arguments.firstIndex(of: "--outlook-check"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { SessionOutlookCheck.run(CommandLine.arguments[i + 1]) }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--resume-nudge-check"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { ResumeNudgeCheck.run(CommandLine.arguments[i + 1]) }
            exit(0)
        }
        // Test hook: `--process-check <file>`: one turn ending per paragraph block (separated by a line "---"),
        // prints rule vs Apple Intelligence verdict for each (ProcessCheck.swift).
        if let i = CommandLine.arguments.firstIndex(of: "--process-check"), i + 1 < CommandLine.arguments.count {
            let text = (try? String(contentsOfFile: CommandLine.arguments[i + 1], encoding: .utf8)) ?? ""
            let sem = DispatchSemaphore(value: 0)
            Task.detached {
                print("ai ready: \(LocalAI.ready)")
                for t in text.components(separatedBy: "\n---\n") where !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let v = await ProcessCheck.classify(t)
                    print("\(ProcessCheck.ruleVerdict(t).rawValue)\t\(v.rawValue)\t\(t.split(separator: "\n").last.map { String($0.prefix(90)) } ?? "")")
                }
                sem.signal()
            }
            sem.wait()
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--interrupted-scan") {
            let n = i + 1 < CommandLine.arguments.count ? Int(CommandLine.arguments[i + 1]) ?? 40 : 40
            InterruptedScan.run(n, root: i + 2 < CommandLine.arguments.count ? CommandLine.arguments[i + 2] : nil)
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--deploy-wake-check"), i + 1 < CommandLine.arguments.count {
            MainActor.assumeIsolated { DeployWakeCheck.run(CommandLine.arguments[i + 1]) }
            exit(0)
        }
        MainActor.assumeIsolated { MenuBarWatch.clearHiddenFlag(); MenuBarWatch.forgetTestCopy() }   // before the menu bar item exists
        SteerApp.main()
    }
}

struct SteerApp: App {
    /// Test hooks (--project, --tab, --palette, --focus, --settings, --open-shells, --selftest-write).
    @MainActor static func applyTestArgs(_ m: AppModel) {
        // Test hook: `open Steerify.app --args --open-shells N` opens N shell sessions (perf measuring).
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--project"), i + 1 < a.count, m.projects.contains(where: { $0.id == a[i + 1] }) { m.selectedProjectId = a[i + 1] }
        if a.contains("--requests-list") { m.requestsListOpen = true }   // Board › All Requests… (RequestsList.swift)
        // `--drop <folder>`: as if the folder were dropped on the window (`--drop-answer new|add` skips the question).
        if let i = a.firstIndex(of: "--drop"), i + 1 < a.count {
            let f = a[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { m.dropFolders([f]) }
        }
        // Test hook: `--cmd-n-type <text> [seconds]`: ⌘N while the keyboard is where it is (the terminal, usually), then
        // the text lands wherever the keyboard went, as typing would (only into a text view: never into a terminal).
        if let i = a.firstIndex(of: "--cmd-n-type"), i + 1 < a.count {
            let text = a[i + 1], at = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 5
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                let w = { NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.identifier?.rawValue == "main-test" } }
                NSLog("cmd-n-type: before ⌘N the keyboard is in \(w()?.firstResponder.map { String(describing: type(of: $0)) } ?? "nothing")")
                m.requestOpen = true
                for t in [0.02, 0.05, 0.1, 0.2] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        NSLog("cmd-n-type: \(Int(t * 1000)) ms after ⌘N the keyboard is in \(w()?.firstResponder.map { String(describing: type(of: $0)) } ?? "nothing")")
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let r = w()?.firstResponder
                    NSLog("cmd-n-type: after ⌘N the keyboard is in \(r.map { String(describing: type(of: $0)) } ?? "nothing")")
                    (r as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
                }
            }
        }
        // `--test-persist`: sessions saved / restored in the test settings, as a real restart does (test windows skip the main window's onAppear).
        if a.contains("--test-persist") { m.restoreSessions() }
        // `--resume-demo`: the "stopped when Steerify quit" modal with invented sessions (screenshots; Resume sends nothing).
        if a.contains("--resume-demo") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ResumeInterrupted.shared.showDemo() } }
        if a.contains("--resume-demo-sail") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { ResumeInterrupted.shared.resume(m) } }
        // `--test-persist --resume-auto`: presses Resume on the real modal (quit → reopen → resume round trip, no clicking).
        if a.contains("--resume-auto") { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if ResumeInterrupted.shared.open { ResumeInterrupted.shared.resume(m) } } }
        // Test hook: `--add-folder <path>` adds any folder as a project, as Add project… does after the panel.
        if let i = a.firstIndex(of: "--add-folder"), i + 1 < a.count { m.addWorkspace(folder: a[i + 1]) }
        // Test hooks: `--recipes-open` shows the recipe gallery; `--recipe-start <id> <folder>` starts that recipe there.
        if a.contains("--recipes-open") { m.recipesOpen = true }
        if a.contains("--standards-open") { m.galleryTab = "standards"; m.recipesOpen = true }
        // `--install-standard <id>` (with --dry-sessions): as if Install were pressed on that standard, 2 s in.
        if let i = a.firstIndex(of: "--install-standard"), i + 1 < a.count, let s = StandardLibrary.all().first(where: { $0.id == a[i + 1] }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if let p = m.project { m.installStandard(s, in: p) } }
        }
        // "How technical are you?": asked on first launch until answered (`--level-open` shows it in tests).
        if a.contains("--level-open") || (Level.chosen == nil && !a.contains("--background")) { m.levelOpen = true }
        if let i = a.firstIndex(of: "--recipe-start"), i + 2 < a.count {
            let (rid, dest) = (a[i + 1], a[i + 2])
            RecipeLibrary.shared.load()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if let r = RecipeLibrary.shared.recipes.first(where: { $0.id == rid }) { m.startRecipe(r, at: URL(fileURLWithPath: dest)) }
                else { NSLog("recipe-start: no recipe \(rid) (\(RecipeLibrary.shared.state))") }
            }
        }
        // Test hook: `--projects-do "move:3:0,rename:<id>:<name>,hide:<id>,show:<id>,remove:<id>,icon:<id>:auto|initials|<picture>,iconcolors:<id>:#a;#b|none"` runs those Projects
        // window actions 1 s in, in order (same functions as the window's buttons and drag).
        if let i = a.firstIndex(of: "--projects-do"), i + 1 < a.count {
            let steps = a[i + 1].split(separator: ",").map { $0.split(separator: ":", maxSplits: 2).map(String.init) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                for s in steps {
                    let p = s.count > 1 ? m.projects.first { $0.id == s[1] } : nil
                    switch s[0] {
                    case "move": if s.count == 3, let f = Int(s[1]), let t = Int(s[2]) { m.moveProjects(from: [f], to: t) }
                    case "rename": if let p, s.count == 3 { m.renameProject(p, to: s[2]) }
                    case "hide": if let p { m.setHidden(p, true) }
                    case "show": if let p { m.setHidden(p, false) }
                    case "remove": if let p { m.removeProject(p) }
                    case "icon": if let p, s.count == 3 {
                        switch s[2] {
                        case "auto": m.setIcon(p, mode: nil)
                        case "initials": m.setIcon(p, mode: "initials")
                        default: m.useIconPicture(p, URL(fileURLWithPath: s[2]))
                        }
                    }
                    case "iconcolors": if let p, s.count == 3 { m.setIconColors(p, s[2] == "none" ? nil : s[2].split(separator: ";").map(String.init)) }
                    default: NSLog("projects-do: unknown step \(s)")
                    }
                }
            }
        }
        // Test hook: `--demo` presses "Try the demo project" 1 s in.
        if a.contains("--demo") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { m.openDemo() } }
        if let i = a.firstIndex(of: "--palette"), i + 1 < a.count { m.paletteSeed = a[i + 1]; m.paletteOpen = true }
        // Test hook: `--toast "<text>"` shows that toast 2 s in (with Open + Undo), to check where it sits.
        if let i = a.firstIndex(of: "--toast"), i + 1 < a.count {
            let text = a[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { m.showToast(text, projectId: m.project?.id, ref: "road:x", undo: {}) }
        }
        // Test hooks (request r261123-100223): `--claude-adds <project> <ref> [s]` acts as if a Claude session of that
        // project added a choice / chapter (the MCP "focus" message); `--next-list [s]` opens the ⌘J list;
        // `--jump-next [s]` presses ⌘J.
        if let i = a.firstIndex(of: "--claude-adds"), i + 2 < a.count, let p = m.projects.first(where: { $0.id == a[i + 1] }) {
            let at = (i + 3 < a.count ? Double(a[i + 3]) : nil) ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { m.testUI(["action": "focus", "ref": a[i + 2], "message": "New choice: test", "board": p.boardDir]) }
        }
        if let i = a.firstIndex(of: "--next-list") {
            let at = (i + 1 < a.count ? Double(a[i + 1]) : nil) ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { m.nextListOpen = true }
        }
        // `--next-list-shot <png> [s]`: the ⌘J list rendered on its own (a popover is its own window: --shot misses it).
        if let i = a.firstIndex(of: "--next-list-shot"), i + 1 < a.count {
            let at = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 4
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                let r = ImageRenderer(content: NextAcrossList(close: {}).environmentObject(m).background(Brand.panel).preferredColorScheme(.dark))
                r.scale = 4
                if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t) {
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[i + 1]))
                }
            }
        }
        if let i = a.firstIndex(of: "--jump-next") {
            let at = (i + 1 < a.count ? Double(a[i + 1]) : nil) ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { m.jumpNext() }
        }
        // Test hook: `--request "<text>"` opens the New request sheet with that text typed in.
        if let i = a.firstIndex(of: "--request"), i + 1 < a.count { m.requestSeed = a[i + 1]; m.requestOpen = true }
        // `--request-pick` opens it as ⌃⌥N does (project pills); `--request-for <id>` picks another project 1.5 s in.
        if a.contains("--request-pick") { m.requestPickProject = true }
        if let i = a.firstIndex(of: "--request-for"), i + 1 < a.count { let id = a[i + 1]; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { m.requestProjectId = id } }
        // Test hook: `--show-item <ref> [seconds]`: the board goes to that item (tab, scroll, flash); no session is opened.
        if let i = a.firstIndex(of: "--show-item"), i + 1 < a.count, let p = m.project {
            let at = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { m.focusItem(projectId: p.id, ref: a[i + 1]) }
        }
        // Test hook: `--live-tap <x> <y> [meta] [seconds]`: a click inside the live prototype at x/y (0–1), ⌘ held with "meta".
        if let i = a.firstIndex(of: "--live-tap"), i + 2 < a.count, let x = Double(a[i + 1]), let y = Double(a[i + 2]) {
            let meta = i + 3 < a.count && a[i + 3] == "meta"
            let at = a.firstIndex(of: "--live-tap-at").flatMap { $0 + 1 < a.count ? Double(a[$0 + 1]) : nil } ?? 4.5
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                ChoiceLiveWeb.current?.evaluateJavaScript("""
                    (() => { const X = \(x) * innerWidth, Y = \(y) * innerHeight; const el = document.elementFromPoint(X, Y);
                      el && el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, clientX: X, clientY: Y, metaKey: \(meta) })); return el ? el.className : 'none' })()
                    """) { r, e in NSLog("live-tap → \(String(describing: r)) \(String(describing: e))") }
            }
        }
        // Test hook: `--open-live <choice id> [option]`: a choice's prototypes live, full window (ChoiceLive.swift).
        if let i = a.firstIndex(of: "--open-live"), i + 1 < a.count, let p = m.project {
            let opt = i + 2 < a.count && !a[i + 2].hasPrefix("--") ? a[i + 2] : "A"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { m.choiceLive = ChoiceLiveOpen(projectId: p.id, decision: a[i + 1], option: opt) }
        }
        // Test hook: `--open-mockup <id> [screen]`: the mockup viewer on that screen (Mockups.swift).
        if let i = a.firstIndex(of: "--open-mockup"), i + 1 < a.count {
            let screen = (i + 2 < a.count ? Int(a[i + 2]) : nil) ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let p = m.projects.first(where: { m.board(for: $0).mockup(a[i + 1]) != nil }) else { return }
                m.selectedProjectId = p.id
                m.mockupOpen = MockupOpen(projectId: p.id, mockup: a[i + 1], screen: screen)
            }
        }
        // Test hook: `--open-url <steerify://…> [seconds]`: as if the link was clicked (e.g. a Lab case, TestLab.swift).
        if let i = a.firstIndex(of: "--open-url"), i + 1 < a.count, let u = URL(string: a[i + 1]) {
            let at = (i + 2 < a.count ? Double(a[i + 2]) : nil) ?? 1
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { m.handle(u) }
        }
        if let i = a.firstIndex(of: "--focus"), i + 1 < a.count, let p = m.project {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { m.openCombo(projectId: p.id, ref: a[i + 1], startNew: false) }
        }
        // Test hook: `--settings-snapshot <file.png> <pane>`: the Settings window on that page, rendered off screen, then quit.
        if let i = a.firstIndex(of: "--settings-snapshot"), i + 1 < a.count {
            let out = a[i + 1]
            if i + 2 < a.count { Prefs.store.set(a[i + 2], forKey: "settingsPane") }
            let host = NSHostingView(rootView: SettingsView().environmentObject(m).tint(Brand.amber))
            let sw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            sw.contentView = host; sw.alphaValue = 0; sw.ignoresMouseEvents = true; sw.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                NSApp.terminate(nil)
            }
        }
        if a.contains("--settings") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) } }
        if let i = a.firstIndex(of: "--tab"), i + 1 < a.count { Prefs.store.set(a[i + 1], forKey: "boardTab") }
        // Test hook: `--preview test:<id>` opens the preview of that item's pictures (`--preview-note`: in note mode).
        if let i = a.firstIndex(of: "--preview"), i + 1 < a.count, let p = m.project {
            let b = m.board(for: p), ref = a[i + 1]
            if let s = b.ships.first(where: { "test:" + $0.id == ref }) {
                let imgs = s.shots.map(\.img) + s.tests.compactMap(\.img)
                m.preview = PreviewState(projectId: p.id, ref: ref, title: s.title, dir: p.boardDir, images: imgs,
                                         index: a.firstIndex(of: "--preview-index").flatMap { $0 + 1 < a.count ? Int(a[$0 + 1]) : nil }.map { min($0, max(imgs.count - 1, 0)) } ?? 0, version: s.version,
                                         startInNoteMode: a.contains("--preview-note"))
            } else if let d = b.decisions.first(where: { "choice:" + $0.id == ref }) {
                // Choices: the option pictures (shots, or drawn mockups). Opened like a click on the card: at once, with
                // whatever is drawn, then B, C… join as they render (`refresh`). Nothing drawn yet: try again in 1 s.
                let imgs: @MainActor () -> [String] = { d.gallery.map(\.img) + d.options.compactMap { $0.shot ?? MockSnapshots.shared.picture(for: $0, boardDir: p.boardDir) } }
                @MainActor func open(_ tries: Int) {
                    let now = imgs()
                    if !now.isEmpty { m.preview = PreviewState(projectId: p.id, ref: ref, title: d.title, dir: p.boardDir, images: now, index: 0, version: nil, refresh: imgs) }
                    else if tries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { open(tries - 1) } }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { open(8) }
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
        // `--processes [name]`: a test copy starts its project's autostart processes (and shows one's logs).
        if let i = a.firstIndex(of: "--processes"), let p = m.project {
            ProcessHub.shared.autostart(p, force: true)
            if i + 1 < a.count, !a[i + 1].hasPrefix("--") {
                let name = a[i + 1]   // that one starts too (as ▶ would), even when it is not autostart
                if let spec = p.processes.first(where: { $0.name == name }), !ProcessHub.shared.isRunning(p, name) { ProcessHub.shared.start(spec, in: p) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ProcessHub.shared.shown[p.id] = name }
            }
        }
        if a.contains("--origin-ping-demo") { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { OriginPingDemo.run(m) } }
        if let i = a.firstIndex(of: "--ship-handoff-demo"), i + 1 < a.count {
            let stop = i + 2 < a.count && !a[i + 2].hasPrefix("--") ? a[i + 2] : "live"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ShipHandoffDemo.run(m, a[i + 1], stop: stop) }
        }
        if let i = a.firstIndex(of: "--shells-demo"), i + 1 < a.count { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ShellsDemo.run(m, a[i + 1]) } }
        if let i = a.firstIndex(of: "--flow-demo"), i + 1 < a.count { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SessionFlowDemo.run(m, a[i + 1]) } }
        // Test hook: `--stuck-demo <item ref>` opens a dry session (claude never starts): 20 s later its card says why + Restart.
        if let i = a.firstIndex(of: "--stuck-demo"), i + 1 < a.count, let p = m.project {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if let u = URL(string: "steerify://start?project=\(p.id)&item=\(a[i + 1])&intent=build&dry=1") { m.handle(u) }
            }
            // `--stuck-restart`: press Restart 26 s in; the log says how many sessions there are and their state.
            if a.contains("--stuck-restart") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 26) {
                    guard let s = m.sessions.first(where: { $0.stuck != nil }) else { NSLog("stuck-check: none stuck"); return }
                    let old = s.id
                    m.restartStuck(s)
                    NSLog("stuck-check: \(m.sessions.count) session(s), new=\(m.sessions.first?.id != old), mood=\(m.sessions.first?.moodWord ?? "-"), title=\(m.sessions.first?.title ?? "-")")
                }
            }
        }
        if let i = a.firstIndex(of: "--label-demo"), i + 1 < a.count { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { SessionLabelsDemo.run(m, a[i + 1]) } }
        if let i = a.firstIndex(of: "--open-shells"), i + 1 < a.count, let n = Int(a[i + 1]) {
            for k in 0..<n { m.newSession(.shell, repo: m.project?.repos[k % max(1, m.project?.repos.count ?? 1)]) }
        }
        // Test hook: `--cmdk-check [out.png]` opens ⌘K 4 s in (a terminal holds the keyboard by then), logs who has the
        // keyboard 0.4 s later, types "abc" as keys would, logs the palette's field text and quits.
        if a.contains("--cmdk-check") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                NSLog("cmdk-check: before = \(String(describing: NSApp.keyWindow?.firstResponder.map { type(of: $0) }))")
                m.paletteOpen.toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let r = NSApp.keyWindow?.firstResponder
                    NSLog("cmdk-check: after = \(String(describing: r.map { type(of: $0) }))")
                    (r as? NSTextView)?.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSLog("cmdk-check: field = '\((NSApp.keyWindow?.firstResponder as? NSTextView)?.string ?? "<none>")'")
                        if let i = a.firstIndex(of: "--cmdk-check"), i + 1 < a.count, a[i + 1].hasSuffix(".png"),
                           let v = NSApp.keyWindow?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                            v.cacheDisplay(in: v.bounds, to: rep)
                            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[i + 1]))
                        }
                        NSApp.terminate(nil)
                    }
                }
            }
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
                .onAppear {
                    delegate.model = model
                    model.restoreSessions()
                    model.watchForUpdates()
                    AppUpdater.shared.start(model)
                    model.startAutomation()
                    SteerApp.applyTestArgs(model)
                    if !CommandLine.arguments.contains("--background") { GlobalHotKey.install(model) }
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultLaunchBehavior(.presented)          // always open the main window at launch (fresh installs too)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
                    .disabled(AppUpdater.isDevBuild)
            }
            FeedbackCommands()      // Help → Report a Bug… / Ask for a Feature… / Ask a Question…
            CommandMenu("Projects") {
                ForEach(0..<9, id: \.self) { i in
                    let list = model.switcherProjects
                    Button(i < list.count ? list[i].name : "Project \(i + 1)") { model.select(index: i) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [.command, .option])
                        .disabled(i >= list.count)
                }
                Divider()
                ManageProjectsButton()
                Button("Reload board") { model.reloadBoard() }.keyboardShortcut("r", modifiers: .command)
                Button("Restart to Update") { model.confirmRestartForUpdate() }.keyboardShortcut("r", modifiers: [.command, .option])
                Button("Add project…") { model.addWorkspace() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("New Project from a Recipe…") { model.galleryTab = "recipes"; model.recipesOpen = true }
                Button("Add a Standard to This Project…") { model.galleryTab = "standards"; model.recipesOpen = true }.disabled(model.project == nil)
                Button("Try the Demo Project") { model.openDemo() }
                Button("Show steerify.json") { if let p = model.project { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.manifest)]) } }
            }
            CommandGroup(after: .sidebar) {
                Button("Sessions: Tabs on Top / List Beside") {
                    let cur = SessionLayout(rawValue: Prefs.store.string(forKey: "sessionLayout") ?? "") ?? .list
                    Prefs.store.set((cur == .tabs ? SessionLayout.list : .tabs).rawValue, forKey: "sessionLayout")
                }.keyboardShortcut("b", modifiers: .command)
            }
            CommandMenu("Board") {
                Button("Search Sessions and Items…") { model.paletteOpen.toggle() }.keyboardShortcut("k", modifiers: .command)
                Button("Next Thing for You") { model.jumpNext() }.keyboardShortcut("j", modifiers: .command)
                Button("All Requests…") { model.requestsListOpen.toggle() }.keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.project == nil)
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
        // ⇧⌘P: Projects window (order, hide, remove, rename, folders).
        Window("Projects", id: "projects") {
            ProjectManagerView().environmentObject(model).preferredColorScheme(.dark).tint(Brand.amber).id(preset)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentMinSize)
        // Menu bar: status + what waits on you. Never for test copies (no second icon on the user's bar).
        MenuBarExtra(isInserted: Binding(get: { menuBarShown && MenuBarWatch.allowed },
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
