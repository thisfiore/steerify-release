import SwiftUI
import AppKit

// The Projects window (⇧⌘P, "Manage projects…" in the switcher, Projects menu): every steered project in one
// list, dragged into the order the switcher and ⌥⌘1…9 follow; details on the right: name, folders, hide, remove.
// Order lives in workspaces.json (the list itself); hidden projects in the app's prefs; name and folders in the
// project's own steerify.json (it travels with the repo).

extension Prefs {
    static let hiddenProjects = "hiddenProjects"   // board folders kept out of the switcher
}

extension AppModel {
    /// Board folders hidden from the switcher, the sidebar and ⌥⌘1…9 (still in the Projects window).
    var hiddenBoards: Set<String> {
        Set(Prefs.store.stringArray(forKey: Prefs.hiddenProjects) ?? [])
    }
    func isHidden(_ p: Project) -> Bool { hiddenBoards.contains(p.boardDir) }

    /// The projects the switcher, the sidebar and ⌥⌘1…9 show, in the user's order.
    var switcherProjects: [Project] { let h = hiddenBoards; return projects.filter { !h.contains($0.boardDir) } }

    func setHidden(_ p: Project, _ hidden: Bool) {
        var h = hiddenBoards
        if hidden { h.insert(p.boardDir) } else { h.remove(p.boardDir) }
        Prefs.store.set(Array(h).sorted(), forKey: Prefs.hiddenProjects)
        objectWillChange.send()
        if hidden, selectedProjectId == p.id, let other = switcherProjects.first { selectedProjectId = other.id }
    }

    /// Drag in the Projects window: the new order is saved at once (workspaces.json).
    func moveProjects(from: IndexSet, to: Int) {
        projects.move(fromOffsets: from, toOffset: to)
        ProjectStore.save(projects.map(\.boardDir))
    }

    /// Takes a project off Steerify's list. Its folder and board stay on disk; its open sessions are closed.
    func removeProject(_ p: Project) {
        for s in sessions(of: p.id) { close(s) }
        projects.removeAll { $0.id == p.id }
        boards[p.id] = nil
        ProjectStore.save(projects.map(\.boardDir))
        if hiddenBoards.contains(p.boardDir) { setHidden(p, false) }
        if selectedProjectId == p.id { selectedProjectId = switcherProjects.first?.id ?? projects.first?.id }
        let dir = p.boardDir
        showToast("\(p.name) removed from Steerify. Its folder and board are still on disk.", undo: { [weak self] in
            guard let self, let back = ProjectStore.read(dir), !self.projects.contains(where: { $0.id == back.id }) else { return }
            self.projects.append(back)
            ProjectStore.save(self.projects.map(\.boardDir))
            self.selectedProjectId = back.id
        })
    }

    /// Rename: writes the new name into the project's steerify.json (only that line).
    func renameProject(_ p: Project, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != p.name else { return }
        editManifest(p) { ManifestText.setName($0, n) }
    }

    /// The icon: automatic (favicon, or initials), initials, or a picture of yours. Saved in steerify.json →
    /// "icon" (the picture in the board's img/project-icon.png), so a teammate sees the same icon.
    func setIcon(_ p: Project, mode: String?) {
        var v: [String: Any] = [:]
        if let mode { v["mode"] = mode }
        if let c = p.icon?.colors { v["colors"] = c }
        writeIcon(p, v.isEmpty ? nil : v)
    }

    func pickIconPicture(_ p: Project) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use as icon"
        panel.message = "A logo or favicon for \(p.name). It is pixelated like the others."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        useIconPicture(p, url)
    }

    /// A picture as the icon: cleaned and saved to the board (img/project-icon.png), colours taken from it.
    func useIconPicture(_ p: Project, _ url: URL) {
        guard AppModel.mayWriteBoards else { return }
        guard let img = IconMaker.loadImage(url.path), let look = IconMaker.make(img, theme: []), let pic = look.picture,
              let rel = IconMaker.savePicture(pic, boardDir: p.boardDir) else {
            showToast("Couldn't use that picture"); return
        }
        var v: [String: Any] = ["mode": "image", "img": rel]
        v["colors"] = look.colors.map { [$0.0.hex, $0.1.hex] }   // a new picture brings its own colours
        writeIcon(p, v)
    }

    /// Your two tile colours (nil = back to the favicon's own).
    func setIconColors(_ p: Project, _ colors: [String]?) {
        var v: [String: Any] = [:]
        if let m = p.icon?.mode { v["mode"] = m }
        if let i = p.icon?.img { v["img"] = i }
        if let colors { v["colors"] = colors }
        writeIcon(p, v.isEmpty ? nil : v)
    }

    private func writeIcon(_ p: Project, _ v: [String: Any]?) {
        guard AppModel.mayWriteBoards else { return }
        let (msg, failed) = JSONFile.edit(p.manifest, key: "icon", value: v)
        if failed { showToast("Couldn't save the icon: \(msg)"); return }
        reloadManifest(p.id)
    }

    /// A missing folder found elsewhere on this Mac: its path in steerify.json points there now.
    func locateRepo(_ r: Repo, in p: Project) {
        guard let folder = Self.pickFolder(prompt: "Use this folder", message: "Where is \(r.name) on this Mac?") else { return }
        editManifest(p) { ManifestText.setRepoPath($0, repo: r.name, path: ManifestText.relative(folder, from: p.boardDir)) }
    }

    /// Another folder (repo) for the project: sessions can start there too.
    func addFolder(to p: Project) {
        guard let folder = Self.pickFolder(prompt: "Add folder", message: "Add a folder or repository to \(p.name)") else { return }
        let name = (folder as NSString).lastPathComponent
        guard !p.repos.contains(where: { $0.path == folder || $0.name == name }) else {
            showToast("\(name) is already one of \(p.name)'s folders"); return
        }
        editManifest(p) { ManifestText.addRepo($0, name: name, path: ManifestText.relative(folder, from: p.boardDir),
                                                git: BoardTemplate.gitRemote(folder)) }
    }

    /// A missing repo with a git remote: clone it where steerify.json expects it.
    func cloneRepo(_ r: Repo, in p: Project) {
        guard let url = r.git else { return }
        showToast("Cloning \(r.name)…")
        let dest = r.path, pid = p.id
        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["clone", url, dest]
            let err = Pipe(); proc.standardError = err; proc.standardOutput = Pipe()
            var ok = false
            do { try proc.run(); proc.waitUntilExit(); ok = proc.terminationStatus == 0 } catch {}
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n").last.map(String.init) ?? ""
            let done = ok
            await MainActor.run {
                self.reloadManifest(pid)
                self.showToast(done ? "\(r.name) cloned" : "Couldn't clone \(r.name): \(msg)")
            }
        }
    }

    private func editManifest(_ p: Project, _ change: (String) -> String?) {
        guard let text = try? String(contentsOfFile: p.manifest, encoding: .utf8), let next = change(text) else {
            showToast("Couldn't change \(p.name)'s steerify.json"); return
        }
        guard next != text else { return }
        do { try next.write(toFile: p.manifest, atomically: true, encoding: .utf8) }
        catch { showToast("Couldn't write \(p.name)'s steerify.json"); return }
        reloadManifest(p.id)
    }

    static func pickFolder(prompt: String, message: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = prompt
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.standardizedFileURL.path
    }
}

/// Small, surgical edits to steerify.json as text: the file keeps its own indentation and key order
/// (it is committed with the project; a re-encode would reformat every line).
enum ManifestText {
    private static let str = #""(?:[^"\\]|\\.)*""#

    static func quote(_ v: String) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data("\"\"".utf8), as: UTF8.self)
    }

    /// The project's `"name"`: the first one before `"repos"`.
    static func setName(_ text: String, _ name: String) -> String? {
        let limit = text.range(of: "\"repos\"")?.lowerBound ?? text.endIndex
        guard let r = text.range(of: #""name"\s*:\s*"# + str, options: .regularExpression, range: text.startIndex..<limit) else { return nil }
        return text.replacingCharacters(in: r, with: "\"name\": \(quote(name))")
    }

    /// The `"path"` of the repo named `repo` (the first `"path"` after its `"name"` inside `"repos"`).
    static func setRepoPath(_ text: String, repo: String, path: String) -> String? {
        guard let reposAt = text.range(of: "\"repos\""),
              let nameAt = text.range(of: #""name"\s*:\s*"# + NSRegularExpression.escapedPattern(for: quote(repo)),
                                      options: .regularExpression, range: reposAt.upperBound..<text.endIndex) else { return nil }
        let objEnd = text.range(of: "}", range: nameAt.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        // "path" may come before "name" in the object: look back to its opening brace too.
        let objStart = text.range(of: "{", options: .backwards, range: reposAt.upperBound..<nameAt.lowerBound)?.upperBound ?? nameAt.lowerBound
        guard let p = text.range(of: #""path"\s*:\s*"# + str, options: .regularExpression, range: objStart..<objEnd) else { return nil }
        return text.replacingCharacters(in: p, with: "\"path\": \(quote(path))")
    }

    /// Appends `{name, path, git?}` to `"repos"`, indented like the file.
    static func addRepo(_ text: String, name: String, path: String, git: String?) -> String? {
        guard let reposAt = text.range(of: #""repos"\s*:\s*\["#, options: .regularExpression) else { return nil }
        // Unit of indentation: the leading spaces of the `"repos"` line.
        let lineStart = text[..<reposAt.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let unit = String(text[lineStart..<reposAt.lowerBound].prefix { $0 == " " || $0 == "\t" })
        let i1 = unit + unit, i2 = unit + unit + unit
        // Matching `]` of the repos array (strings skipped).
        var depth = 0, inStr = false, esc = false
        var close: String.Index?
        var i = text.index(before: reposAt.upperBound)
        while i < text.endIndex {
            let c = text[i]
            if inStr { if esc { esc = false } else if c == "\\" { esc = true } else if c == "\"" { inStr = false } }
            else if c == "\"" { inStr = true }
            else if c == "[" { depth += 1 }
            else if c == "]" { depth -= 1; if depth == 0 { close = i; break } }
            i = text.index(after: i)
        }
        guard let close else { return nil }
        var fields = ["\(i2)\"name\": \(quote(name))", "\(i2)\"path\": \(quote(path))"]
        if let git { fields.append("\(i2)\"git\": \(quote(git))") }
        let obj = "\(i1){\n" + fields.joined(separator: ",\n") + "\n\(i1)}"
        let inside = text[text.index(after: text.index(before: reposAt.upperBound))..<close]
        if inside.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.replacingCharacters(in: text.index(before: reposAt.upperBound)..<text.index(after: close),
                                            with: "[\n\(obj)\n\(unit)]")
        }
        guard let lastBrace = text.range(of: "}", options: .backwards, range: reposAt.upperBound..<close) else { return nil }
        return text.replacingCharacters(in: lastBrace.lowerBound..<lastBrace.upperBound, with: "},\n\(obj)")
    }

    /// `folder` relative to the board folder ("..", "../../SB-Local"), as steerify.json keeps repo paths.
    static func relative(_ folder: String, from base: String) -> String {
        let a = URL(fileURLWithPath: base).standardizedFileURL.pathComponents
        let b = URL(fileURLWithPath: folder).standardizedFileURL.pathComponents
        var n = 0
        while n < a.count, n < b.count, a[n] == b[n] { n += 1 }
        let parts = Array(repeating: "..", count: a.count - n) + b[n...]
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }
}

/// ⇧⌘P: the Projects window.
struct ProjectManagerView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: String?
    @State private var confirmRemove: Project?

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: S(290))
            Rectangle().fill(Brand.line).frame(width: 1)
            if let p = model.projects.first(where: { $0.id == (selection ?? model.selectedProjectId) }) ?? model.projects.first {
                ProjectDetails(project: p, confirmRemove: $confirmRemove).id(p.id)
            } else {
                Text("No projects yet").foregroundStyle(Brand.mute).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Brand.bg)
        .frame(minWidth: 820, minHeight: 520)
        .alert("Remove \(confirmRemove?.name ?? "") from Steerify?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
               presenting: confirmRemove) { p in
            Button("Remove", role: .destructive) {
                if selection == p.id { selection = nil }
                model.removeProject(p)
            }
            Button("Cancel", role: .cancel) {}
        } message: { p in
            let n = model.sessions(of: p.id).count
            Text("It only leaves Steerify's list. The folder and its board stay on disk; Add project… brings it back."
                 + (n > 0 ? " Its \(n) open session\(n == 1 ? "" : "s") will be closed." : ""))
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PROJECTS").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute)
                Spacer()
                Text("drag to reorder").font(.system(size: S(10))).foregroundStyle(Brand.mute.opacity(0.7))
            }.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            List(selection: Binding(get: { selection ?? model.selectedProjectId }, set: { selection = $0 })) {
                ForEach(model.projects) { p in
                    row(p).tag(p.id)
                }
                .onMove { model.moveProjects(from: $0, to: $1) }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Rectangle().fill(Brand.line).frame(height: 1)
            HStack(spacing: 6) {
                Button { model.addWorkspace(); selection = model.selectedProjectId } label: { Label("Add project…", systemImage: "plus") }
                Spacer()
                Button {
                    if let p = model.projects.first(where: { $0.id == (selection ?? model.selectedProjectId) }) { confirmRemove = p }
                } label: { Image(systemName: "minus") }.help("Remove from Steerify…")
            }
            .buttonStyle(SteerButton()).font(.system(size: S(12))).foregroundStyle(Brand.ink)
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .background(Brand.panel)
    }

    private func row(_ p: Project) -> some View {
        let hidden = model.isHidden(p)
        let key = model.switcherProjects.firstIndex(where: { $0.id == p.id }).flatMap { $0 < 9 ? "⌥⌘\($0 + 1)" : nil }
        return HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal").font(.system(size: S(10))).foregroundStyle(Brand.mute.opacity(0.6))
            PixelAvatar(name: p.name, size: S(24), projectId: p.id)
            Text(p.name).font(.system(size: S(12.5), weight: .medium)).foregroundStyle(Brand.ink).lineLimit(1)
            Spacer(minLength: 4)
            if hidden { Text("hidden").font(.system(size: S(10))).foregroundStyle(Brand.mute) }
            else if let key { Text(key).font(.system(size: S(10))).foregroundStyle(Brand.mute) }
        }
        .opacity(hidden ? 0.5 : 1)
        .padding(.vertical, 3)
    }
}

/// Right side of the Projects window: one project.
private struct ProjectDetails: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    @Binding var confirmRemove: Project?
    @State private var name = ""

    var body: some View {
        let p = model.projects.first { $0.id == project.id } ?? project
        let hidden = model.isHidden(p)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    PixelAvatar(name: p.name, size: S(60), projectId: p.id)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name).font(.system(size: S(20), weight: .bold)).foregroundStyle(.white)
                        Text(Self.tilde(p.boardDir)).font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.mute)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                }
                field("Name") {
                    TextField("Project name", text: $name)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: S(320))
                        .onSubmit { model.renameProject(p, to: name) }
                    if name.trimmingCharacters(in: .whitespaces) != p.name && !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Rename") { model.renameProject(p, to: name) }.buttonStyle(SteerButton())
                            .font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.amber)
                    }
                }
                field("Folders") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(p.repos) { r in folder(r, in: p) }
                        Button { model.addFolder(to: p) } label: { Label("Add a folder…", systemImage: "plus") }
                            .buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                    }
                }
                field("Icon") { IconField(project: p) }
                field("Switcher") {
                    Toggle(isOn: Binding(get: { !hidden }, set: { model.setHidden(p, !$0) })) {
                        Text(hidden ? "Hidden: not in the switcher or ⌥⌘1…9" : "Shown in the switcher")
                            .font(.system(size: S(12))).foregroundStyle(Brand.ink)
                    }.toggleStyle(.switch).controlSize(.small)
                }
                Rectangle().fill(Brand.line).frame(height: 1).padding(.top, 6)
                HStack(spacing: 10) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.manifest)]) }
                    Button(hidden ? "Show in switcher" : "Hide from switcher") { model.setHidden(p, !hidden) }
                    Spacer()
                    Button { confirmRemove = p } label: { Text("Remove from Steerify…").foregroundStyle(Brand.red) }
                }
                .buttonStyle(.bordered).controlSize(.regular)
                Text("Remove only takes it off the list. The folder and the board stay on disk.")
                    .font(.system(size: S(11))).foregroundStyle(Brand.mute)
            }
            .padding(.horizontal, 26).padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { name = p.name }
        .onChange(of: p.name) { _, n in name = n }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).frame(width: S(80), alignment: .leading)
            content()
        }
    }

    private func folder(_ r: Repo, in p: Project) -> some View {
        let ok = r.exists
        return HStack(spacing: 8) {
            Image(systemName: ok ? "folder.fill" : "folder.badge.questionmark")
                .foregroundStyle(ok ? Brand.mute : Brand.amber)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).font(.system(size: S(12), weight: .semibold, design: .monospaced)).foregroundStyle(Brand.ink)
                Text(Self.tilde(r.path)).font(.system(size: S(10.5), design: .monospaced)).foregroundStyle(Brand.mute)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if ok {
                Image(systemName: "checkmark").font(.system(size: S(10), weight: .bold)).foregroundStyle(Brand.green)
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.path)]) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(SteerButton()).foregroundStyle(Brand.mute).help("Show in Finder")
            } else {
                Text("missing").font(.system(size: S(10.5), weight: .semibold)).foregroundStyle(Brand.amber)
                if r.git != nil { Button("Clone") { model.cloneRepo(r, in: p) }.buttonStyle(.bordered).controlSize(.small) }
                Button("Locate…") { model.locateRepo(r, in: p) }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel2))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(ok ? Brand.line : Brand.amber.opacity(0.4)))
        .frame(maxWidth: S(460))
    }

    static func tilde(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

extension AppModel {
    /// Set by the menu bar label (alive as long as the app; it can open SwiftUI windows): opens the Projects window.
    static var openProjects: (() -> Void)?
    func openProjectsWindow() { Self.openProjects?() }
}

/// "Manage Projects…" (⇧⌘P) in the Projects menu.
struct ManageProjectsButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Manage Projects…") { open() }
            .keyboardShortcut("p", modifiers: [.command, .shift])
    }
    private func open() { openWindow(id: "projects"); NSApp.activate(ignoringOtherApps: true) }
}

/// Projects window → Icon: where it comes from, how it looks at each size, and your override.
private struct IconField: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var icons = ProjectIcons.shared
    let project: Project
    @State private var c1 = Color.gray
    @State private var c2 = Color.gray
    @State private var save: Task<Void, Never>?

    private var mode: String { project.icon?.mode ?? "auto" }

    var body: some View {
        let look = icons.look(project.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                PixelAvatar(name: project.name, size: S(60), projectId: project.id)
                PixelAvatar(name: project.name, size: S(24), projectId: project.id)
                PixelAvatar(name: project.name, size: 20, projectId: project.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sourceLine(look)).font(.system(size: S(11.5))).foregroundStyle(Brand.ink)
                    if mode == "auto" && look?.small == nil {
                        Text("No favicon found in its folders").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                    }
                }
            }
            HStack(spacing: 8) {
                Picker("", selection: Binding(get: { mode == "image" ? "image" : mode }, set: { m in
                    switch m {
                    case "auto": model.setIcon(project, mode: nil)
                    case "initials": model.setIcon(project, mode: "initials")
                    default: model.pickIconPicture(project)
                    }
                })) {
                    Text("Automatic").tag("auto")
                    Text("Initials").tag("initials")
                    Text("Picture…").tag("image")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: S(260))
                if mode == "image" {
                    Button("Change…") { model.pickIconPicture(project) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                Text("Colours").font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                ColorPicker("", selection: $c1, supportsOpacity: false).labelsHidden()
                ColorPicker("", selection: $c2, supportsOpacity: false).labelsHidden()
                if project.icon?.colors != nil {
                    Button("From the icon") { model.setIconColors(project, nil) }.buttonStyle(SteerButton())
                        .font(.system(size: S(11))).foregroundStyle(Brand.mute)
                }
            }
            Text("Saved in steerify.json, so your team sees the same icon.")
                .font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
        }
        .onAppear { load(look) }
        .onChange(of: look) { _, l in load(l) }
        .onChange(of: c1) { _, _ in queueSave() }
        .onChange(of: c2) { _, _ in queueSave() }
    }

    private func sourceLine(_ l: ProjectIconLook?) -> String {
        switch mode {
        case "initials": return "Pixel initials"
        case "image": return "Your picture"
        default: return l?.small != nil ? "From \(l!.source)" : "Pixel initials"
        }
    }

    /// The pickers show what the tile uses now (yours, or the favicon's).
    private func load(_ l: ProjectIconLook?) {
        save?.cancel()
        let cur = currentHex(l)
        c1 = RGBA(hex: cur[0]).map(\.color) ?? .gray
        c2 = RGBA(hex: cur[1]).map(\.color) ?? .gray
    }

    private func currentHex(_ l: ProjectIconLook?) -> [String] {
        if let c = project.icon?.colors, c.count >= 2 { return c }
        if let c = l?.colors { return [c.0.hex, c.1.hex] }
        return ["#888888", "#444444"]
    }

    /// Picker drags fire many times: save once it settles.
    private func queueSave() {
        let next = [RGBA(c1).hex, RGBA(c2).hex]
        guard next != currentHex(icons.look(project.id)) else { return }
        save?.cancel()
        save = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            model.setIconColors(project, next)
        }
    }
}
