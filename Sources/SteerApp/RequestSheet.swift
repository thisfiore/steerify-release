import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Top bar, next to "Next for you": what you need to do, and what you want done.
struct NewRequestButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if model.project != nil {
            Button { model.requestOpen = true } label: {
                HStack(spacing: 6) {
                    Text("+ Request").font(.system(size: S(12), weight: .semibold))
                    Text("⌘N").font(.system(size: S(10), design: .monospaced)).opacity(0.7)
                }
                .foregroundStyle(Color(hex: 0x1a1200))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.amber))
            }
            .buttonStyle(SteerButton())
            .help("New request (⌘N): a fix, a tweak, a feature, a question. Steerify files it, Claude takes it from there.")
        }
    }
}

/// ⌘N: one sheet for anything. Type it, add screenshots; Steerify shows where it goes before any token is spent.
struct RequestSheet: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    @State private var text = ""
    @State private var images: [URL] = []
    @State private var context: String?
    @State private var contextTitle: String?
    @State private var triage = Triage(kind: .refine, kindWhy: "", chapter: nil, chapterWhy: "")
    @State private var refining: Task<Void, Never>?
    @State private var kindSet: RequestKind?          // your override
    @State private var chapterSet: String??           // your override (.some(nil) = "no chapter")
    @State private var dropping = false
    @State private var capturing = false
    @State private var clipboardHasImage = false
    @State private var recent: [BoardRequest] = []    // read once per project, not on every keystroke
    @State private var guess: ProjectGuess?           // ProjectGuess.swift: which project the text is about (menu bar, ⌃⌥N)
    @State private var handPicked = false             // you clicked a project: no more guessing
    @State private var guessing: Task<Void, Never>?
    @State private var shots: [URL] = []              // your latest screenshots (RecentShots.swift)
    @State private var shotThumbs: [URL: NSImage] = [:]
    @State private var shotWatch: DispatchSourceFileSystemObject?
    @State private var marks: [ShotMark] = []         // ShotMarker.swift: dots and areas on the pictures, ① in the text
    @State private var shown: URL?                    // the picture shown big
    @FocusState private var focused: Bool

    private var board: BoardStore { model.board(for: project) }
    private var kind: RequestKind { kindSet ?? triage.kind }
    private var chapter: String? { chapterSet ?? triage.chapter }
    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// A mark lives while its picture is attached and its badge is still in the text (delete ② in the text, the mark goes).
    private var liveMarks: [ShotMark] { marks.filter { images.contains($0.img) && text.contains($0.badge) } }
    /// Opened from outside a project (menu bar, ⌃⌥N): the project is a question, so it is guessed and named on the button.
    private var pickProject: Bool { model.requestPickProject && model.projects.count > 1 }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { close() }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("NEW REQUEST ·").font(Brand.label(10)).tracking(0.9).foregroundStyle(Brand.amber)
                    projectMenu
                    Spacer()
                    Text("⌘↩ send · Esc").font(.system(size: S(10.5), design: .monospaced)).foregroundStyle(Brand.mute)
                }
                if model.requestPickProject && model.projects.count > 1 { projectPills }
                if !images.isEmpty {
                    ShotMarker(images: images, shown: $shown, marks: Binding(get: { liveMarks }, set: { marks = $0 }),
                               onMark: addMark, onRemove: { u in images.removeAll { $0 == u } })
                }
                editor
                if !shots.isEmpty { RecentShotsStrip(shots: shots, thumbs: shotThumbs, images: $images, onMore: pickOlder) }
                attachments
                if let c = context { contextRow(c) }
                if empty {
                    Text("Type it: Steerify shows where it goes (fix, refinement, feature, question) before any token is spent.")
                        .font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                } else { thinks }
                actions
                if images.isEmpty { history }   // a picture to mark takes its room
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x14161b)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(dropping ? Brand.amber : Brand.line2, lineWidth: dropping ? 2 : 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
            .frame(width: 720)
            .padding(.top, 50)
            .onDrop(of: [.fileURL, .image], isTargeted: $dropping) { drop($0) }
        }
        .onAppear(perform: setUp)
        .onDisappear { shotWatch?.cancel(); shotWatch = nil }
        .onChange(of: project.id) { _, _ in projectChanged() }
        .onChange(of: text) { _, _ in retriage(); guessProject() }
        .onChange(of: images) { old, new in if let added = new.last(where: { !old.contains($0) }) { shown = added } }
        .onKeyPress(.escape) { close(); return .handled }
        .onExitCommand { close() }
    }

    // MARK: Parts

    /// The project in the header is a menu: a request can go to any project.
    private var projectMenu: some View {
        Menu {
            ForEach(model.projects) { p in
                Button { handPicked = true; model.requestProjectId = p.id } label: { if p.id == project.id { Label(p.name, systemImage: "checkmark") } else { Text(p.name) } }
            }
        } label: {
            HStack(spacing: 3) {
                Text(project.name.uppercased()).font(Brand.label(10)).tracking(0.9)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.foregroundStyle(Brand.amber)
        }
        .menuStyle(.button).buttonStyle(.plain).fixedSize()
        .help("Which project this request is for")
    }

    /// From ⌃⌥N or the menu bar you were somewhere else: say which project, one click.
    private var projectPills: some View {
        HStack(spacing: 6) {
            Text("FOR").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.mute)
            ForEach(model.projects) { p in
                let on = p.id == project.id
                Button { handPicked = true; model.requestProjectId = p.id } label: {
                    Text((on && guess?.projectId == p.id && !handPicked ? "✦ " : "") + p.name).font(.system(size: S(12), weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color(hex: 0x1a1200) : Brand.ink)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(on ? Brand.amber : Brand.panel))
                        .overlay(Capsule().stroke(on ? Color.clear : Brand.line2))
                }.buttonStyle(SteerButton())
            }
            if let g = guess, !handPicked, g.projectId == project.id {
                HStack(spacing: 4) {
                    if g.ai { Image(systemName: "apple.intelligence").font(.system(size: S(10))) }
                    Text("guessed · \(g.why)").lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: S(11))).foregroundStyle(Brand.blue).padding(.leading, 4)
                .help(g.ai ? "Guessed by Apple Intelligence, on this Mac. Click a project to choose it yourself." : "Guessed from the words. Click a project to choose it yourself.")
            }
            Spacer()
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: S(14))).scrollContentBackground(.hidden).focused($focused)
                .frame(height: S(92))
                .padding(6)
            if text.isEmpty {
                Text("A fix, a tweak, a feature, a question… one line is enough.")
                    .font(.system(size: S(14))).foregroundStyle(Brand.mute).padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x0d0f13)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Brand.amber.opacity(0.6) : Brand.line2))
    }

    private var attachments: some View {
        HStack(spacing: 8) {
            ForEach(images.filter { !shots.contains($0) }, id: \.self) { u in
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let img = NSImage(contentsOf: u) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) }
                        else { Rectangle().fill(Brand.panel2) }
                    }
                    .frame(width: 64, height: 42).clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Brand.line2))
                    Button { images.removeAll { $0 == u } } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white, .black.opacity(0.7))
                    }.buttonStyle(.plain).offset(x: 5, y: -5)
                }
            }
            if clipboardHasImage {
                smallButton("Paste image", "doc.on.clipboard") { pasteImage() }
            }
            smallButton(capturing ? "Select an area…" : "Capture…", "camera.viewfinder") { capture() }.disabled(capturing)
            Text(images.isEmpty ? "or drop screenshots here" : "\(images.count) screenshot\(images.count == 1 ? "" : "s") · drop more")
                .font(.system(size: S(11))).foregroundStyle(Brand.mute)
            Spacer()
        }
    }

    private func contextRow(_ c: String) -> some View {
        HStack(spacing: 8) {
            Text("LOOKING AT").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.mute)
            HStack(spacing: 5) {
                PixelIcon(name: ["test": "test", "choice": "choice", "road": "road", "track": "road", "req": "req", "reqs": "req"][String(c.split(separator: ":").first ?? "")] ?? "play", size: 9)
                    .foregroundStyle(Brand.cream)
                Text(contextTitle ?? c).lineLimit(1).truncationMode(.tail)
                Button { context = nil; contextTitle = nil; retriage() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Brand.mute).help("Not about this")
            }
            .font(.system(size: S(11.5))).foregroundStyle(Brand.ink)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().stroke(Brand.line2))
            Spacer()
        }
    }

    private var thinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("STEERIFY THINKS").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.mute)
                if triage.ai && kindSet == nil { Image(systemName: "apple.intelligence").font(.system(size: S(10))).foregroundStyle(Brand.blue).help("Read by Apple Intelligence, on this Mac") }
                pill(kind.label, kind.color, filled: true)
                Text("→").foregroundStyle(Brand.mute)
                Text(kind.destination(chapter)).font(.system(size: S(13), weight: .semibold)).foregroundStyle(.white)
                Spacer()
            }
            if !empty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kindSet == nil ? triage.kindWhy : "You changed it to \(kind.label.lowercased())")
                    Text(chapterSet == nil ? (triage.chapter.map { "About “\($0)” · " } ?? "") + triage.chapterWhy
                                           : chapter.map { "About “\($0)” · you picked it" } ?? "No chapter · Claude will place it")
                }
                .font(.system(size: S(11))).foregroundStyle(Brand.mute)
            }
            HStack(spacing: 6) {
                ForEach(RequestKind.allCases) { k in
                    Button { kindSet = k == triage.kind ? nil : k } label: { pill(k.label, k.color, filled: k == kind) }.buttonStyle(.plain).pointerStyle(.link).help(k.rule)
                }
                Spacer()
                Menu {
                    Button("No chapter (Claude places it)") { chapterSet = .some(nil) }
                    Divider()
                    ForEach(board.chapters.filter { !$0.draft && $0.name != RequestLog.fixesChapter }.reversed()) { c in
                        Button { chapterSet = .some(c.name) } label: {
                            if c.name == chapter { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                        }
                    }
                } label: {
                    Text(chapter.map { "About: \($0)" } ?? "About: no chapter").lineLimit(1).truncationMode(.tail)
                }
                .menuStyle(.borderlessButton).font(.system(size: S(11))).foregroundStyle(Brand.cream)
                .frame(minWidth: 60, maxWidth: 260, alignment: .trailing).layoutPriority(-1)
            }
            Text(nextLine).font(.system(size: S(11))).foregroundStyle(Brand.ink.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(kind.color.opacity(0.5)))
    }

    private var nextLine: String {
        switch kind {
        case .fix: return "Filed now as a key result of “\(RequestLog.fixesChapter)”" + (chapter.map { ", linked to “\($0)”" } ?? "") + ". Claude checks the code, fixes it and puts it in To test."
        case .refine: return "Filed now as a key result of “\(RequestLog.fixesChapter)”" + (chapter.map { ", linked to “\($0)”" } ?? "") + ". Claude makes the change and puts it in To test."
        case .feature: return "Claude checks the code and drafts a chapter (objective, key results, requirements, choices). Nothing lands on the roadmap without your OK."
        case .task: return "Not code: Claude sets it up on the Tasks tab (outcome, checks, once or on a schedule), runs it and hands you the result to check."
        case .question: return "Claude reads the code and turns it into a choice with options and mockups, on the Choices tab."
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Cancel") { close() }.buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
            Spacer()
            Button { send(fileOnly: true) } label: {
                Text("Just file it").font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.cream)
                    .padding(.horizontal, 10).padding(.vertical, 5).overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.line2))
            }
            .buttonStyle(SteerButton()).disabled(empty)
            .help("Saved and filed, no session (start it later from Recent requests)")
            ClaudeButton(title: (pickProject ? "File it in \(project.name)" : "File it + start Claude") + "  ⌘↩", prominent: true) { send(fileOnly: false) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(empty).opacity(empty ? 0.5 : 1)
        }
    }

    @ViewBuilder private var history: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Divider().overlay(Brand.line).padding(.bottom, 4)
                Text("RECENT REQUESTS · WHERE THEY WENT").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.mute)
                ForEach(recent) { r in RequestRow(project: project, r: r, onOpen: close) }
            }
        }
    }

    private func pill(_ t: String, _ c: Color, filled: Bool) -> some View {
        Text(t.uppercased()).font(Brand.label(8.5)).tracking(0.5)
            .foregroundStyle(filled ? Color(hex: 0x1a1200) : c)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(filled ? c : .clear))
            .overlay(Capsule().stroke(c))
    }

    private func smallButton(_ t: String, _ icon: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Label(t, systemImage: icon).font(.system(size: S(11))).foregroundStyle(Brand.cream)
                .padding(.horizontal, 8).padding(.vertical, 4).overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.line2))
        }.buttonStyle(SteerButton())
    }

    // MARK: Behaviour

    /// A new dot or area: next number, its badge at the end of the text, back to typing.
    private func addMark(_ m: ShotMark) {
        let n = (liveMarks.map(\.n).max() ?? 0) + 1
        let mark = ShotMark(n: n, img: m.img, rect: m.rect)
        marks.removeAll { $0.n == n }
        marks.append(mark)
        let sep = text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? "" : " "
        text += sep + mark.badge + " "
        focused = true
    }

    private func setUp() {
        text = model.requestSeed; model.requestSeed = ""
        if let k = model.requestKindSeed { kindSet = k; model.requestKindSeed = nil }
        focused = true
        lookContext()
        recent = Array(RequestLog.load(project.boardDir).prefix(5))
        let pb = NSPasteboard.general
        clipboardHasImage = pb.string(forType: .string) == nil && [.png, .tiff].contains(where: { pb.data(forType: $0) != nil })
        retriage()
        loadShots()
        shotWatch = RecentShots.watch { loadShots() }
        // Test hooks: `--request-img <png>` attaches a picture, `--request-send file|claude` sends after 2 s.
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--request-img"), i + 1 < a.count { images.append(URL(fileURLWithPath: a[i + 1])) }
        // `--request-mark "dot:x,y;rect:x,y,w,h"` (0–1) marks the last picture, as ⌘-click and drag would.
        if let i = a.firstIndex(of: "--request-mark"), i + 1 < a.count, let u = images.last {
            for part in a[i + 1].split(separator: ";") {
                let v = part.split(separator: ":").last?.split(separator: ",").compactMap { Double($0) } ?? []
                if v.count == 2 { addMark(ShotMark(n: 0, img: u, rect: CGRect(x: v[0], y: v[1], width: 0, height: 0))) }
                if v.count == 4 { addMark(ShotMark(n: 0, img: u, rect: CGRect(x: v[0], y: v[1], width: v[2], height: v[3]))) }
            }
        }
        // `--request-switch <project>`: another project takes the window 1 s in (the request must stay here).
        if let i = a.firstIndex(of: "--request-switch"), i + 1 < a.count {
            let other = a[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { model.selectedProjectId = other }
        }
        if let i = a.firstIndex(of: "--request-send"), i + 1 < a.count {
            let fileOnly = a[i + 1] == "file"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { send(fileOnly: fileOnly) }
        }
    }

    /// What you were looking at in this project: the item you last jumped to, else the item of the session on screen.
    private func lookContext() {
        context = nil; contextTitle = nil
        let f = model.focus.flatMap { $0.projectId == project.id ? $0.ref : nil }
        let s = model.current(of: project.id)?.item?.ref
        if let ref = f ?? s, let it = ItemRef(ref: ref) {
            context = ref
            contextTitle = BoardFiles.resolve(it, in: project).title ?? ref
        }
    }

    /// Another project picked: keep the text and pictures, redo context, chapter and kind for it.
    private func projectChanged() {
        lookContext(); chapterSet = nil
        recent = Array(RequestLog.load(project.boardDir).prefix(5))
        retriage()
        focused = true
    }

    /// Pick A of request-project-guess: the words answer at once, Apple Intelligence after a pause; unsure → the window's project.
    private func guessProject() {
        guard pickProject, !handPicked else { return }
        let ps = ProjectGuesser.profiles(model), asked = text
        let w = ProjectGuesser.words(asked, ps)
        apply(w.guess)
        guessing?.cancel()
        guard w.named == nil, !w.backed.isEmpty else { return }       // named, or nothing to choose from: no model call
        guessing = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, asked == text else { return }
            let read = await ProjectGuesser.ai(asked, ps)
            guard asked == text, !handPicked else { return }
            let final = ProjectGuesser.decide(w, model: read)
            if CommandLine.arguments.contains("--dry-sessions") {   // test copies: how the guess was made
                FileHandle.standardError.write("GUESS words=\(w.scores.prefix(3).map { "\($0.name):\(String(format: "%.1f", $0.score))" }) ai=\(String(describing: read.map { $0?.projectId ?? "unsure" })) final=\(final?.projectId ?? "none")\n".data(using: .utf8)!)
            }
            apply(final)
        }
    }

    private func apply(_ g: ProjectGuess?) {
        guess = g
        let target = g?.projectId ?? model.selectedProjectId ?? project.id
        if target != project.id { model.requestProjectId = target }
    }

    private func retriage() {
        let chs = board.chapters.filter { !$0.draft }.map { c in (name: c.name, items: board.roadmap.filter { $0.track == c.name }.map(\.text)) }
        let ctx = model.chapter(of: context, in: project)
        let lessons = TriageLessons.load(project.boardDir)
        let words = RequestTriage.classify(text, chapters: chs, context: ctx, lessons: lessons)
        triage = words
        // Apple Intelligence refines it once you pause typing (free, on this Mac); the word model stays if it is off.
        let asked = text
        refining?.cancel()
        refining = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, asked == text else { return }
            if let better = await RequestTriage.refine(asked, chapters: chs, context: ctx, words: words, lessons: lessons), asked == text { triage = better }
        }
    }

    /// Read the screenshot folder off the main thread; thumbnails are small and made once per file.
    private func loadShots() {
        let known = shotThumbs
        DispatchQueue.global(qos: .userInitiated).async {
            let list = RecentShots.list()
            var th: [URL: NSImage] = [:]
            for u in list { th[u] = known[u] ?? RecentShots.thumb(u) }
            DispatchQueue.main.async { shots = list; shotThumbs = th }
        }
    }

    /// "More…": any older screenshot, from the same folder.
    private func pickOlder() {
        let panel = NSOpenPanel()
        panel.directoryURL = RecentShots.folder
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Attach screenshots to the request"
        if panel.runModal() == .OK { images += panel.urls.filter { !images.contains($0) } }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func pasteImage() {
        if let paths = SteerTerminalView.paths(from: NSPasteboard.general, materialize: true) {
            images += paths.map { URL(fileURLWithPath: $0) }.filter { !images.contains($0) }
        }
        clipboardHasImage = false
    }

    private func capture() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Steerify/drops", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("Capture \(Int(Date().timeIntervalSince1970)).png")
        capturing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-x", out.path]
            try? p.run(); p.waitUntilExit()
            DispatchQueue.main.async {
                capturing = false
                if FileManager.default.fileExists(atPath: out.path) { images.append(out) }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Steerify/drops", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, pr) in providers.enumerated() {
            if pr.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = pr.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { d, _ in
                    guard let d, let u = URL(dataRepresentation: d, relativeTo: nil) else { return }
                    DispatchQueue.main.async { if !images.contains(u) { images.append(u) } }
                }
            } else if pr.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                _ = pr.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { d, _ in
                    guard let d, let rep = NSBitmapImageRep(data: d), let png = rep.representation(using: .png, properties: [:]) else { return }
                    let u = dir.appendingPathComponent("Drop \(Int(Date().timeIntervalSince1970))-\(i).png")
                    if (try? png.write(to: u)) != nil { DispatchQueue.main.async { images.append(u) } }
                }
            }
        }
        return true
    }

    private func send(fileOnly: Bool) {
        guard !empty else { return }
        let k = kind, ch = chapter
        // Marked pictures go as a copy with the dots and areas drawn in; the original stays as it was.
        let drops = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Steerify/drops", isDirectory: true)
        let live = liveMarks
        let sent = images.map { u in ShotBurn.burn(u, marks: live.filter { $0.img == u }, into: drops) ?? u }
        let id = model.fileRequest(projectId: project.id, text: text, kind: k, guess: triage.kind, chapter: ch, images: sent,
                                   context: context, contextTitle: contextTitle, fileOnly: fileOnly)
        close()
        guard id != nil else { model.showToast("Could not file the request"); return }
        let where_ = k == .fix || k == .refine ? "“\(RequestLog.fixesChapter)”" : k == .feature ? "a chapter draft" : k == .task ? "Tasks" : "a choice"
        let away = project.id != model.selectedProjectId ? "\(project.name) · " : ""   // filed elsewhere: say where, you stay here
        model.showToast(away + (fileOnly ? "Filed: \(k.label.lowercased()) → \(where_)" : "Filed: \(k.label.lowercased()) → \(where_) · Claude is on it"),
                        projectId: project.id)
    }

    private func close() { model.requestOpen = false }
}

/// One line of the request history: what you asked, where it went, what it is now.
struct RequestRow: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    let r: BoardRequest
    var onOpen: () -> Void = {}

    var body: some View {
        let st = model.requestState(r, in: project)
        HStack(spacing: 8) {
            Text(r.kind.label.uppercased()).font(Brand.label(8)).foregroundStyle(r.kind.color).frame(width: 74, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.short).font(.system(size: S(12))).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.tail)
                Text(whereLine).font(.system(size: S(10.5))).foregroundStyle(Brand.mute).lineLimit(1)
            }
            Spacer(minLength: 6)
            if !r.imgs.isEmpty { Label("\(r.imgs.count)", systemImage: "photo").font(.system(size: S(10.5))).foregroundStyle(Brand.mute) }
            Text(st.0).font(.system(size: S(10.5), weight: .semibold)).foregroundStyle(st.1)
            if r.status == "filed" && model.board(for: project).lastLink("request:" + r.id) == nil {
                Button { onOpen(); model.startRequestSession(projectId: project.id, id: r.id) } label: {
                    HStack(spacing: 3) { ClaudeSpark(size: S(10), color: Brand.claude); Text("Start") }.font(.system(size: S(11)))
                }.buttonStyle(SteerButton()).foregroundStyle(Brand.claude).help("Start the briefed Claude session for this request")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .pointerStyle(.link)
        .help(r.note ?? r.text)
    }

    private var whereLine: String {
        let b = model.board(for: project)
        var parts: [String] = []
        if let ch = b.chapters.first(where: { $0.request == r.id }) { parts.append("→ chapter “\(ch.name)”") }
        else if r.kind == .fix || r.kind == .refine { parts.append("→ \(RequestLog.fixesChapter)" + (r.chapter.map { " · \($0)" } ?? "")) }
        else if let c = r.chapter { parts.append("→ " + c) }
        if let n = r.note, !n.isEmpty { parts.append(n) }
        parts.append(SessionChip.ago(r.at))
        return parts.joined(separator: " · ")
    }

    /// Its live session, else what it became on the board, else its conversation.
    private func open() {
        onOpen()
        let ref = "request:" + r.id
        if let s = model.sessions.first(where: { $0.projectId == project.id && $0.covers(ref) && $0.running }) {
            model.selectedSession[project.id] = s.id
        }
        let b = model.board(for: project)
        if let ch = b.chapters.first(where: { $0.request == r.id }) { model.focusItem(projectId: project.id, ref: "track:" + BoardFiles.slug(ch.name)); return }
        if let target = r.became.last(where: { ItemRef(ref: $0) != nil }) { model.openCombo(projectId: project.id, ref: target, startNew: false); return }
        if let link = b.lastLink(ref) { model.resume(link, projectId: project.id) }
    }
}
