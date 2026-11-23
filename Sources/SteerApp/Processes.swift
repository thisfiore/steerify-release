import SwiftUI
import AppKit

/// One base process of a project (steerify.json → "processes"): a dev server, a watcher, a worker.
/// `{"name": "web", "repo": "steer-app", "command": "npm run dev", "autostart": true}`
struct ProcessSpec: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var repo: String?
    var command: String
    var autostart: Bool?
}

/// The process shells, pinned at the bottom of the sessions panel. Kept apart from the Claude sessions:
/// they are not saved / restored as sessions, never ranked by board tab, and survive switching project.
@MainActor
final class ProcessHub: ObservableObject {
    static let shared = ProcessHub()

    /// "<project>/<name>" → its shell (also once it exited: the logs stay readable).
    @Published private(set) var shells: [String: TerminalSession] = [:]
    /// "<project>/<name>" → the last exit code.
    @Published private(set) var exits: [String: Int32] = [:]
    /// Per project: the process whose terminal is shown instead of the selected session (nil = the session).
    @Published var shown: [String: String] = [:]
    private var autostarted: Set<String> = []

    private func key(_ p: Project, _ name: String) -> String { p.id + "/" + name }
    func shell(_ p: Project, _ name: String) -> TerminalSession? { shells[key(p, name)] }
    func isRunning(_ p: Project, _ name: String) -> Bool { shell(p, name)?.running == true }
    func exitCode(_ p: Project, _ name: String) -> Int32? { exits[key(p, name)] }
    func shownShell(_ p: Project) -> TerminalSession? { shown[p.id].flatMap { shell(p, $0) } }

    /// Choice pt-start: the autostart processes start when their project opens (once per app run).
    /// Test copies (--background) never start the processes unless asked (`--processes`): ports would clash with yours.
    func autostart(_ p: Project, force: Bool = false) {
        guard force || !CommandLine.arguments.contains("--background"), !autostarted.contains(p.id) else { return }
        autostarted.insert(p.id)
        for spec in p.processes where spec.autostart == true && !isRunning(p, spec.name) { start(spec, in: p) }
    }

    func start(_ spec: ProcessSpec, in p: Project) {
        guard let repo = spec.repo.flatMap({ p.resolveRepo($0) }) ?? p.repos.first else { return }
        let k = key(p, spec.name)
        let s = TerminalSession(project: p, repo: repo, kind: .shell)
        s.title = spec.name
        s.shellCommand = spec.command
        s.onExit = { [weak self] code in Task { @MainActor in self?.exits[k] = code; self?.objectWillChange.send() } }
        exits[k] = nil
        shells[k] = s
        _ = s.view   // the view starts the process
    }

    /// Ctrl-C first (the whole foreground group: npm and the server it spawned), then a hard stop.
    func stop(_ spec: ProcessSpec, in p: Project, then: (() -> Void)? = nil) {
        guard let s = shell(p, spec.name), s.running else { then?(); return }
        s.view.send(txt: "\u{03}")
        var waited = 0.0
        func check() {
            if !s.running || waited >= 3 {
                if s.running { s.terminate() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { then?() }
                return
            }
            waited += 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: check)
        }
        check()
    }

    func restart(_ spec: ProcessSpec, in p: Project) {
        stop(spec, in: p) { [weak self] in
            self?.start(spec, in: p)
            if self?.shown[p.id] == spec.name { self?.objectWillChange.send() }
        }
    }
}

/// The PROCESSES block at the bottom of the sessions column.
struct ProcessesSection: View {
    @ObservedObject var hub = ProcessHub.shared
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(Brand.line).frame(height: 1).padding(.bottom, 4)
            Text("PROCESSES").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute)
            ForEach(project.processes) { spec in ProcessRow(spec: spec, project: project) }
        }
    }
}

struct ProcessRow: View {
    @ObservedObject var hub = ProcessHub.shared
    let spec: ProcessSpec
    let project: Project
    @State private var hover = false

    var body: some View {
        let shell = hub.shell(project, spec.name)
        let selected = hub.shown[project.id] == spec.name
        HStack(spacing: 6) {
            if let shell { ProcessDot(session: shell, exit: hub.exitCode(project, spec.name)) } else { Circle().strokeBorder(Brand.mute, lineWidth: 1).frame(width: 7, height: 7) }
            VStack(alignment: .leading, spacing: 0) {
                Text(spec.name).font(.system(size: S(11.5), weight: .medium)).lineLimit(1)
                Text(spec.command).font(.system(size: S(9.5), design: .monospaced)).foregroundStyle(Brand.mute).lineLimit(1)
            }
            Spacer(minLength: 2)
            if hub.isRunning(project, spec.name) {
                iconButton("arrow.clockwise", "Restart") { hub.restart(spec, in: project) }
                iconButton("stop.fill", "Stop") { hub.stop(spec, in: project) }
            } else {
                iconButton("play.fill", "Start") { hub.start(spec, in: project); hub.shown[project.id] = spec.name }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color(nsColor: Theme.terminalBg) : hover ? Color.white.opacity(0.04) : .clear))
        .foregroundStyle(selected ? Brand.cream : Brand.cream.opacity(0.8))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if shell != nil { hub.shown[project.id] = spec.name } }
        .help(shell == nil ? "Not started: ▶ to start" : "Show its logs")
    }

    private func iconButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: S(9))) }
            .buttonStyle(SteerButton()).foregroundStyle(Brand.mute).help(help)
    }
}

/// Green = running, grey = stopped, red = it exited with an error.
struct ProcessDot: View {
    @ObservedObject var session: TerminalSession
    let exit: Int32?
    var body: some View {
        let c: Color = session.running ? Brand.green : (exit ?? 0) != 0 ? Brand.red : Brand.mute
        Circle().fill(c).frame(width: 7, height: 7)
    }
}
