import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Folders dragged into Steerify become projects:
// - on the Dock icon (or Finder "Open With"): a new project, like Add project… with that folder already picked;
// - on the window with no project yet (the welcome screen): the same;
// - on the window with a project open: asks "New project" or "Add to <project>".
// A folder that is already a project (its board, or one of its folders) just opens that project.
// Terminals keep their own drop (they paste the path): AppKit hands the drop to the terminal view first.

extension AppModel {
    /// The project a folder already belongs to: its board is in it, or it is one of the project's folders.
    func projectOwning(_ folder: String) -> Project? {
        let f = URL(fileURLWithPath: folder).standardizedFileURL.path
        if let b = ProjectStore.boardFolder(in: f), let p = projects.first(where: { $0.boardDir == b }) { return p }
        return projects.first { p in p.boardDir == f || p.repos.contains { URL(fileURLWithPath: $0.path).standardizedFileURL.path == f } }
    }

    /// Folders from the Dock icon or Finder: each one becomes a project (or opens the one it already is).
    func openFolders(_ paths: [String]) {
        for f in Self.folders(paths) {
            if let p = projectOwning(f) { selectedProjectId = p.id; showToast("\(p.name) is already steered", projectId: p.id) }
            else { addWorkspace(folder: f) }
        }
        if !CommandLine.arguments.contains("--background") { NSApp.activate(ignoringOtherApps: true) }
    }

    /// Folders dropped on the window. With a project open, a new folder asks: its own project, or one more
    /// folder of the open project.
    func dropFolders(_ paths: [String]) {
        let list = Self.folders(paths)
        guard !list.isEmpty else { showToast("Drop a folder to start a project"); return }
        dropNext(list[...])
    }

    /// One folder at a time: the question (a sheet on the window) waits for its answer before the next folder.
    private func dropNext(_ rest: ArraySlice<String>) {
        guard let f = rest.first else { return }
        let more = rest.dropFirst()
        if let p = projectOwning(f) {
            selectedProjectId = p.id
            showToast("\(p.name) is already steered", projectId: p.id)
            return dropNext(more)
        }
        guard let current = project else { addWorkspace(folder: f); return dropNext(more) }
        Self.askNewOrAdd(folder: f, project: current) { [weak self] answer in
            guard let self else { return }
            switch answer {
            case .new: self.addWorkspace(folder: f)
            case .add: self.addFolder(f, to: current)
            case .cancel: return
            }
            self.dropNext(more)
        }
    }

    enum DropAnswer { case new, add, cancel }

    private static func askNewOrAdd(folder: String, project: Project, done: @escaping (DropAnswer) -> Void) {
        if let a = CommandLine.arguments.firstIndex(of: "--drop-answer"), a + 1 < CommandLine.arguments.count {
            return done(["add": .add, "new": .new][CommandLine.arguments[a + 1]] ?? .cancel)   // tests: no question
        }
        // Finder keeps the focus during a drag: bring Steerify forward so the question is seen.
        if !CommandLine.arguments.contains("--background") { NSApp.activate(ignoringOtherApps: true) }
        DropQuestion.shared.ask = .init(folder: folder, project: project, done: done)
    }

    /// Only real folders: files and packages (.app, .bundle) are left out.
    static func folders(_ paths: [String]) -> [String] {
        paths.compactMap { raw in
            let p = URL(fileURLWithPath: raw).standardizedFileURL.path   // as Add project… keeps it
            var dir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: p, isDirectory: &dir), dir.boolValue,
                  !NSWorkspace.shared.isFilePackage(atPath: p) else { return nil }
            return p
        }
    }
}

/// The whole window takes dropped folders; while one hovers, an amber frame says what will happen.
struct FolderDropTarget: ViewModifier {
    @EnvironmentObject var model: AppModel
    @State private var over = forceHover
    @ObservedObject private var question = DropQuestion.shared
    static let forceHover = CommandLine.arguments.contains("--drop-hover")   // the drag highlight, for screenshots

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $over) { providers in
                load(providers) { model.dropFolders($0) }
                return true
            }
            .overlay { if let q = question.ask { DropQuestionCard(ask: q).id(q.id) } }
            .overlay {
                if over {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.amber, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                        Text(model.project == nil ? "Drop the folder to start a project" : "Drop a folder: new project, or add it to \(model.project!.name)")
                            .font(.system(size: S(13), weight: .semibold)).foregroundStyle(Brand.bg)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Brand.amber))
                            .padding(.bottom, 24)
                    }
                    .padding(6)
                    .allowsHitTesting(false)
                }
            }
    }

    private func load(_ providers: [NSItemProvider], done: @escaping ([String]) -> Void) {
        var paths: [String] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { lock.lock(); paths.append(url.path); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(paths) }
    }
}

extension View {
    func folderDropTarget() -> some View { modifier(FolderDropTarget()) }
}

/// The open question of a drop: "New project" or "Add to <project>" (one at a time).
@MainActor final class DropQuestion: ObservableObject {
    static let shared = DropQuestion()
    struct Ask: Identifiable {
        let id = UUID()
        let folder: String
        let project: Project
        let done: (AppModel.DropAnswer) -> Void
    }
    @Published var ask: Ask?
    func answer(_ a: AppModel.DropAnswer) {
        guard let q = ask else { return }
        ask = nil
        q.done(a)
    }
}

struct DropQuestionCard: View {
    let ask: DropQuestion.Ask
    private var name: String { (ask.folder as NSString).lastPathComponent }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { DropQuestion.shared.answer(.cancel) }
            VStack(alignment: .leading, spacing: 14) {
                Text("NEW FOLDER").font(Brand.label(11)).tracking(1.4).foregroundStyle(Brand.amber)
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(Brand.amber)
                    Text(name).font(.system(size: S(17), weight: .semibold)).foregroundStyle(Brand.cream)
                }
                Text(ask.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.mute).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 12) {
                    choice(title: "New project", line: "\(name) gets its own board", icon: "ship", primary: true) { DropQuestion.shared.answer(.new) }
                    choice(title: "Add to \(ask.project.name)", line: "One more folder of this project", icon: "folder.badge.plus", primary: false) { DropQuestion.shared.answer(.add) }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { DropQuestion.shared.answer(.cancel) }
                        .buttonStyle(.plain).font(.system(size: S(12))).foregroundStyle(Brand.mute)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(22)
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 14).fill(Brand.bg))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.amber.opacity(0.35)))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
        }
    }

    private func choice(title: String, line: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                if icon.contains(".") { Image(systemName: icon).font(.system(size: S(16))).foregroundStyle(Brand.cream).frame(height: 18) }
                else { PixelIcon(name: icon, size: 18) }
                Text(title).font(.system(size: S(14), weight: .semibold)).foregroundStyle(Brand.cream).lineLimit(1)
                Text(line).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(primary ? Brand.amber.opacity(0.12) : Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(primary ? Brand.amber : Color.white.opacity(0.12), lineWidth: primary ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(DefaultKey(on: primary))
    }
}

/// Return picks the suggested answer (New project).
private struct DefaultKey: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.keyboardShortcut(.defaultAction) } else { content }
    }
}
