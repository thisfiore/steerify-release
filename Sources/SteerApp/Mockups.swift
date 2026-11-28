import SwiftUI
import AppKit
import WebKit

// MARK: - Mockups: a feature's screens, hosted in Steerify like an artifact (choice mockup-host, pick C)
//
// <board>/mockups/<id>/mockup.json
//   { "id", "title", "chapter": "<exact chapter name>", "road"?: "<key result text>", "themes"?: ["dark","light"],
//     "versions": [ { "v": 1, "at": "2026-11-27", "note"?: "what changed",
//                     "screens": [ { "file": "v1/1-orders.html" | "proto": "protos/x.html?v=A", "caption", "device": "desktop"|"phone" } ] } ] }
// `file` is relative to the mockup's folder, `proto` to the board. Screens are HTML (the project kit) or pictures.
// The chapter shows a strip of the current version; a click opens the viewer (screens, device, theme, v1 ↔ vN,
// notes pinned on the screen, Looks right). Verdict + pins live in decisions.json under "mockup:<id>".

struct MockupScreen: Hashable {
    let path: String        // relative to the board folder, query kept (protos/x.html?v=A)
    let caption: String
    let device: String      // desktop | phone
    var focus: CGRect? = nil    // the part to check and decide on (0–1 of the screen, from the top-left)
    var focusLabel = ""         // what to look at there (≤ 6 words)
    var isHTML: Bool { path.split(separator: "?").first.map { $0.hasSuffix(".html") || $0.hasSuffix(".htm") } ?? false }
}

struct MockupVersion: Hashable {
    let v: Int; let at: String; let note: String
    let screens: [MockupScreen]
}

struct Mockup: Identifiable, Hashable {
    let id: String, title: String, chapter: String, road: String?
    let themes: [String]
    let versions: [MockupVersion]
    var current: MockupVersion? { versions.last }
    var ref: String { "mockup:" + id }

    nonisolated static func parse(_ j: [String: Any], folder: String) -> Mockup? {
        guard let id = j["id"] as? String ?? Optional(folder), !id.isEmpty else { return nil }
        let versions: [MockupVersion] = (j["versions"] as? [[String: Any]] ?? []).enumerated().compactMap { i, v in
            let screens: [MockupScreen] = (v["screens"] as? [[String: Any]] ?? []).compactMap { s in
                let path: String
                if let f = s["file"] as? String, !f.isEmpty { path = "mockups/\(folder)/" + f }
                else if let p = s["proto"] as? String ?? s["img"] as? String, !p.isEmpty { path = p }
                else { return nil }
                var f: CGRect? = nil
                if let r = (s["focus"] as? [Any])?.compactMap({ ($0 as? NSNumber)?.doubleValue }), r.count == 4, r[2] > 0, r[3] > 0 {
                    f = CGRect(x: max(0, r[0]), y: max(0, r[1]), width: min(r[2], 1 - max(0, r[0])), height: min(r[3], 1 - max(0, r[1])))
                }
                return MockupScreen(path: path, caption: s["caption"] as? String ?? "", device: s["device"] as? String == "phone" ? "phone" : "desktop",
                                    focus: f, focusLabel: s["focusLabel"] as? String ?? "")
            }
            return screens.isEmpty ? nil : MockupVersion(v: v["v"] as? Int ?? i + 1, at: v["at"] as? String ?? "", note: v["note"] as? String ?? "", screens: screens)
        }
        guard !versions.isEmpty else { return nil }
        let themes = (j["themes"] as? [String] ?? []).filter { ["dark", "light"].contains($0) }
        return Mockup(id: id, title: j["title"] as? String ?? id, chapter: j["chapter"] as? String ?? "", road: j["road"] as? String,
                      themes: themes, versions: versions.sorted { $0.v < $1.v })
    }

    /// Every mockup of a board folder (small JSON files; the app caches the list per board change).
    nonisolated static func load(_ boardDir: String) -> [Mockup] {
        let root = (boardDir as NSString).appendingPathComponent("mockups")
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: root)) ?? []).sorted().compactMap { f in
            guard let d = fm.contents(atPath: "\(root)/\(f)/mockup.json"),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
            return parse(j, folder: f)
        }
    }
}

extension BoardStore {
    var mockups: [Mockup] { memoized("mockups") { Mockup.load(project.boardDir) } }
    func mockups(chapter: String) -> [Mockup] { mockups.filter { $0.chapter == chapter } }
    func mockup(_ id: String) -> Mockup? { mockups.first { $0.id == id } }
    /// "ok" when the user said Looks right on this version.
    func mockupVerdict(_ m: Mockup) -> (ok: Bool, note: String) {
        let c = choiceMap[m.ref] ?? [:]
        let ok = c["pick"] as? String == "ok" && (c["v"] as? Int) == m.current?.v
        return (ok, c["note"] as? String ?? "")
    }
    /// Pins on a version of the mockup (on any of its screens).
    func mockupPins(_ m: Mockup, version: Int) -> [Pin] { pins(m.ref).filter { ($0.v ?? version) == version } }
}

/// What is open in the mockup viewer.
struct MockupOpen: Identifiable {
    let id = UUID()
    let projectId: String
    let mockup: String
    var screen = 0
    var note = false        // opened with ⌘-click: ready to pin a note
}

/// A screen's thumbnail: the picture itself, or the HTML drawn once off-screen (MockSnapshots).
struct MockupThumb: View {
    @ObservedObject var board: BoardStore
    @ObservedObject private var snaps = MockSnapshots.shared
    let screen: MockupScreen
    var height: CGFloat = 64
    var cropped = false         // show only the focus part (the chapter strip), not the whole screen
    var open: () -> Void
    var body: some View {
        let _ = snaps.version
        if !screen.isHTML {
            BoardImage(dir: board.project.boardDir, path: screen.path, height: height, focus: cropped ? screen.focus : nil, onOpen: open)
        } else if let pic = MockSnapshots.shared.picture(for: BoardOption(id: screen.path, label: "", rec: false, points: [], mockHTML: nil, shot: nil, proto: screen.path), boardDir: board.project.boardDir) {
            BoardImage(dir: board.project.boardDir, path: pic, height: height, focus: cropped ? screen.focus : nil, onOpen: open)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(Brand.panel2).frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .overlay(ProgressView().controlSize(.small))
                .onTapGesture(perform: open)
        }
    }
}

/// On a chapter: one line per mockup (current version), its screens as thumbnails. A click opens the viewer.
struct MockupStrip: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let chapter: String
    var body: some View {
        let list = board.mockups(chapter: chapter)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(list) { m in
                    if let cur = m.current {
                        let verdict = board.mockupVerdict(m)
                        let pins = board.mockupPins(m, version: cur.v).count
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("MOCKUP · v\(cur.v)").font(Brand.label(7.5)).tracking(0.6).foregroundStyle(Brand.amber)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Brand.amber.opacity(0.5), lineWidth: 1))
                                Text(m.title).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.cream).lineLimit(1)
                                Text("\(cur.screens.count) screen\(cur.screens.count == 1 ? "" : "s")").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                                if pins > 0 { Text("\(pins) note\(pins == 1 ? "" : "s")").font(.system(size: S(10.5))).foregroundStyle(Brand.amber) }
                                if verdict.ok { Text("✓ looks right").font(.system(size: S(10.5), weight: .semibold)).foregroundStyle(Brand.green) }
                            }
                            HStack(spacing: 6) {
                                ForEach(Array(cur.screens.prefix(5).enumerated()), id: \.offset) { i, s in
                                    MockupThumb(board: board, screen: s, cropped: true) { open(m, i) }
                                        .frame(width: S(s.device == "phone" ? 40 : 112))
                                        .help(s.caption)
                                }
                                if cur.screens.count > 5 {
                                    Button("+\(cur.screens.count - 5)") { open(m, 5) }
                                        .buttonStyle(SteerButton()).font(.system(size: S(11), weight: .semibold)).foregroundStyle(Brand.mute)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
    private func open(_ m: Mockup, _ i: Int) {
        model.mockupOpen = MockupOpen(projectId: board.project.id, mockup: m.id, screen: i, note: NSEvent.modifierFlags.contains(.command))
    }
}

/// A live mockup screen: a web view on the HTML (scaled to fit by the kit's proto.js), light or dark.
struct MockupWeb: NSViewRepresentable {
    let dir: String; let path: String; let dark: Bool
    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.setValue(false, forKey: "drawsBackground")
        load(w, context.coordinator)
        return w
    }
    func updateNSView(_ w: WKWebView, context: Context) {
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if context.coordinator.path != path { load(w, context.coordinator) }
    }
    private func load(_ w: WKWebView, _ c: Coord) {
        c.path = path
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.loadFileURL(MockSnapshots.protoURL(path, base: base), allowingReadAccessTo: base)
    }
    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var path = "" }
    static func dismantleNSView(_ w: WKWebView, coordinator: Coord) { w.stopLoading() }
}

/// Full-window viewer, like a Claude artifact: the screen big and live, the other screens below, notes on the right.
/// N = drop a note on the screen; ← / → between screens; Esc closes.
struct MockupViewer: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    @State var open: MockupOpen
    @State private var version: Int? = nil
    @State private var device: String? = nil
    @State private var dark = true
    @State private var noteMode = false
    /// ⌘ held: a click on the screen pins a note, like everywhere in Steerify (test mockup-host, note on test 3).
    @State private var cmdDown = false
    @State private var flagsMonitor: Any?
    @State private var zoomed = false
    @State private var draft: CGPoint? = nil
    @State private var draftText = ""
    @State private var overall = ""
    @FocusState private var focused: Bool
    @FocusState private var draftFocused: Bool

    private var mockup: Mockup? { board.mockup(open.mockup) }
    private func shown(_ m: Mockup) -> MockupVersion { m.versions.first { $0.v == version } ?? m.current! }
    private func screens(_ m: Mockup) -> [MockupScreen] {
        let all = shown(m).screens
        guard let d = device else { return all }
        let f = all.filter { $0.device == d }
        return f.isEmpty ? all : f
    }
    private func list(_ m: Mockup) -> [MockupScreen] { screens(m) }
    private func devices(_ m: Mockup) -> [String] { Array(Set(shown(m).screens.map(\.device))).sorted() }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea().onTapGesture { if !noteMode { close() } }
            if let m = mockup, m.current != nil {
                let list = screens(m)
                let i = min(open.screen, list.count - 1)
                VStack(spacing: 0) {
                    toolbar(m)
                    HStack(spacing: 0) {
                        VStack(spacing: 10) {
                            GeometryReader { g in canvas(m, list[i], in: g.size) }
                            strip(m, list, current: i)
                        }
                        .padding(14)
                        panel(m, list, current: i)
                    }
                }
                .background(Brand.bg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.line2))
                .padding(.horizontal, 40).padding(.vertical, 28)
            } else {
                Text("This mockup is gone from the board.").foregroundStyle(Brand.mute)
            }
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear {
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { e in
                cmdDown = e.modifierFlags.contains(.command); return e
            }
        }
        .onDisappear { if let m = flagsMonitor { NSEvent.removeMonitor(m) }; flagsMonitor = nil }
        .onAppear { focused = true; noteMode = open.note; overall = mockup.map { board.mockupVerdict($0).note } ?? ""; if mockup?.themes.first == "light" { dark = false } }
        .onKeyPress(.escape) { if draft != nil { draft = nil; draftText = "" } else { close() }; return .handled }
        .onKeyPress(.leftArrow) { if NSApp.keyWindow?.firstResponder is NSText { return .ignored }; step(-1); return .handled }
        .onKeyPress(.rightArrow) { if NSApp.keyWindow?.firstResponder is NSText { return .ignored }; step(1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "nz")) { k in
            if NSApp.keyWindow?.firstResponder is NSText { return .ignored }
            if k.characters == "z" { zoomed.toggle(); if zoomed { noteMode = false; draft = nil } }
            else { noteMode.toggle(); if noteMode { zoomed = false } }
            return .handled
        }
        .onChange(of: open.screen) { _, _ in zoomed = CommandLine.arguments.contains("--mockup-zoom") }
        .task { if CommandLine.arguments.contains("--mockup-zoom") { zoomed = true } }
    }

    // MARK: Pieces

    private func toolbar(_ m: Mockup) -> some View {
        let v = shown(m)
        let verdict = board.mockupVerdict(m)
        let devs = devices(m)
        return HStack(spacing: 10) {
            Text(m.title).font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Text("MOCKUP · v\(v.v)").font(Brand.label(8)).tracking(0.6).foregroundStyle(Brand.amber)
            Text("\(v.screens.count) screen\(v.screens.count == 1 ? "" : "s")").font(.system(size: S(11))).foregroundStyle(Brand.mute)
            Spacer()
            if devs.count > 1 {
                seg(["desktop": "Desktop", "phone": "Phone"], order: ["desktop", "phone"], on: device ?? "", any: true) { device = $0; open.screen = 0 }
            }
            if m.themes.count > 1 {
                seg(["dark": "Dark", "light": "Light"], order: ["dark", "light"], on: dark ? "dark" : "light") { dark = $0 == "dark" }
            }
            if m.versions.count > 1 {
                Menu("v\(v.v)" + (v.v == m.current?.v ? " · latest" : "")) {
                    ForEach(m.versions.reversed(), id: \.v) { x in
                        Button("v\(x.v)" + (x.at.isEmpty ? "" : " · \(x.at.prefix(10))") + (x.note.isEmpty ? "" : " · \(x.note)")) { version = x.v; open.screen = 0 }
                    }
                }.menuStyle(.borderlessButton).fixedSize().help("Compare with an earlier version")
            }
            if list(m).indices.contains(open.screen), list(m)[open.screen].focus != nil {
                Button { zoomed.toggle(); if zoomed { noteMode = false; draft = nil } } label: {
                    Label(zoomed ? "Whole screen" : "Zoom on the key part", systemImage: zoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
                        .font(.system(size: S(11.5), weight: .semibold))
                }
                .foregroundStyle(zoomed ? Brand.amber : Brand.cream).help("Z")
            }
            Button { noteMode.toggle(); if noteMode { zoomed = false } } label: {
                Label(noteMode ? "Click the screen…" : "Note", systemImage: "mappin.and.ellipse").font(.system(size: S(11.5), weight: .semibold))
            }
            .foregroundStyle(noteMode ? Brand.amber : Brand.cream).help("Pin a note on the screen: ⌘-click it (or N, then click)")
            if v.v == m.current?.v {
                Button {
                    board.setMockup(m.id, version: v.v, pick: verdict.ok ? nil : "ok")
                    if !verdict.ok { model.showToast("Mockup approved: \(m.title)", projectId: board.project.id, ref: m.ref) }
                } label: {
                    Text(verdict.ok ? "✓ Looks right" : "Looks right").font(.system(size: S(11.5), weight: .bold))
                        .foregroundStyle(verdict.ok ? Brand.green : Brand.bg)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(verdict.ok ? Brand.green.opacity(0.15) : Brand.green))
                }
                .buttonStyle(.plain).help(verdict.ok ? "Undo: not approved yet" : "The mockup is right: Claude can build it")
            }
            Button { close() } label: { Image(systemName: "xmark") }.help("Close (Esc)")
        }
        .buttonStyle(SteerButton()).foregroundStyle(Brand.cream)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Brand.panel)
    }

    private func seg(_ labels: [String: String], order: [String], on: String, any: Bool = false, pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 3) {
            ForEach(order, id: \.self) { k in
                let sel = on == k || (any && on.isEmpty && k == order[0])
                Button(labels[k] ?? k) { pick(k) }
                    .buttonStyle(.plain).font(.system(size: S(11), weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .foregroundStyle(sel ? .white : Brand.mute)
                    .background(RoundedRectangle(cornerRadius: 4).fill(sel ? Brand.panel2 : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(sel ? Brand.mute : Brand.line2))
            }
        }
    }

    /// The screen at its device's shape (desktop 16:10, phone 390×844), as large as fits, with its pins.
    private func canvas(_ m: Mockup, _ s: MockupScreen, in size: CGSize) -> some View {
        let ratio: CGFloat = s.device == "phone" ? 390.0 / 844.0 : 16.0 / 10.0
        let w = min(size.width, size.height * ratio), h = w / ratio
        let v = shown(m).v
        let pins = board.mockupPins(m, version: v).filter { $0.img == s.path }
        let all = board.mockupPins(m, version: v)
        return ZStack(alignment: .topLeading) {
            Group {
                if s.isHTML, let z = zoom(s, w, h) {
                    // Zoom = a bigger page, moved so the key part fills the box (the kit re-fits it: sharp, no blur).
                    MockupWeb(dir: board.project.boardDir, path: s.path, dark: dark)
                        .frame(width: w * z.k, height: h * z.k)
                        .offset(x: -z.x, y: -z.y)
                        .frame(width: w, height: h, alignment: .topLeading)
                } else if s.isHTML { MockupWeb(dir: board.project.boardDir, path: s.path, dark: dark) }
                else { BoardImage(dir: board.project.boardDir, path: s.path, height: h, fit: true, focus: zoomed ? s.focus : nil) }
            }
            .frame(width: w, height: h)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: s.device == "phone" ? 26 : 6))
            .overlay(RoundedRectangle(cornerRadius: s.device == "phone" ? 26 : 6).stroke(s.device == "phone" ? Brand.mute : Brand.line2, lineWidth: s.device == "phone" ? 3 : 1))
            // The key part: everything else dimmed, an amber frame and what to check there.
            if let f = s.focus {
                // The frame follows the zoom: the key part stays marked, whatever else fits around it.
                let z = s.isHTML ? zoom(s, w, h) : nil
                let k = z?.k ?? 1, ox = z?.x ?? 0, oy = z?.y ?? 0
                let r = CGRect(x: f.minX * w * k - ox, y: f.minY * h * k - oy, width: f.width * w * k, height: f.height * h * k)
                Path { p in p.addRect(CGRect(x: 0, y: 0, width: w, height: h)); p.addRoundedRect(in: r, cornerSize: CGSize(width: 6, height: 6)) }
                    .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true)).allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 6).stroke(Brand.amber, lineWidth: 2)
                    .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY).allowsHitTesting(false)
                Text(s.focusLabel.isEmpty ? "CHECK THIS" : s.focusLabel.uppercased())
                    .font(Brand.label(8.5)).tracking(0.7).foregroundStyle(Color(hex: 0x1a1204))
                    .padding(.horizontal, 6).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 3).fill(Brand.amber))
                    .fixedSize()
                    .position(x: min(max(r.minX + 60, 60), w - 60), y: r.minY > 22 ? r.minY - 12 : r.maxY + 12)
                    .allowsHitTesting(false)
            }
            // ⌘-click (or Note mode): a click on the screen drops a note there; otherwise the web view stays clickable.
            if (noteMode || cmdDown) && !zoomed {
                Color.white.opacity(0.001).frame(width: w, height: h)
                    .onTapGesture(coordinateSpace: .local) { p in
                        draft = CGPoint(x: max(0, min(1, p.x / w)), y: max(0, min(1, p.y / h))); draftText = ""; draftFocused = true
                    }
                    .pointerStyle(.rectSelection)
            }
            if !zoomed { ForEach(Array(pins.enumerated()), id: \.offset) { _, p in
                let n = (all.firstIndex(of: p) ?? 0) + 1
                marker(n).position(x: p.x * w, y: p.y * h).help(p.note)
            } }
            if let d = draft { marker(all.count + 1, draft: true).position(x: d.x * w, y: d.y * h) }
        }
        .frame(width: w, height: h)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Zoom factor and offset for the screen's key part, or nil when not zoomed.
    private func zoom(_ s: MockupScreen, _ w: CGFloat, _ h: CGFloat) -> (k: CGFloat, x: CGFloat, y: CGFloat)? {
        guard zoomed, let f = s.focus else { return nil }
        let k = max(1, min(1 / f.width, 1 / f.height) * 0.9)
        let cx = f.midX * w * k - w / 2, cy = f.midY * h * k - h / 2
        return (k, min(max(cx, 0), w * k - w), min(max(cy, 0), h * k - h))
    }

    private func marker(_ n: Int, draft: Bool = false) -> some View {
        Text("\(n)").font(.system(size: S(10.5), weight: .heavy)).foregroundStyle(Color(hex: 0x1a1204))
            .frame(width: S(20), height: S(20))
            .background(Circle().fill(Brand.amber))
            .overlay(Circle().stroke(Brand.amber.opacity(draft ? 0.9 : 0.35), lineWidth: draft ? 4 : 3).padding(-2))
    }

    private func strip(_ m: Mockup, _ list: [MockupScreen], current: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(list.enumerated()), id: \.offset) { k, s in
                VStack(alignment: .leading, spacing: 3) {
                    MockupThumb(board: board, screen: s, height: S(58)) { open.screen = k; draft = nil }
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(k == current ? Brand.amber : .clear, lineWidth: 1.5))
                    Text("\(k + 1) · \(s.caption)").font(.system(size: S(10))).foregroundStyle(k == current ? Brand.cream : Brand.mute).lineLimit(1)
                }
                .frame(width: S(s.device == "phone" ? 60 : 130))
            }
            Spacer(minLength: 0)
        }
    }

    private func panel(_ m: Mockup, _ list: [MockupScreen], current: Int) -> some View {
        let v = shown(m)
        let pins = board.mockupPins(m, version: v.v)
        return VStack(alignment: .leading, spacing: 10) {
            Text("SCREEN \(current + 1) / \(list.count)").font(Brand.label(8)).tracking(0.7).foregroundStyle(Brand.mute)
            Text(list[current].caption.isEmpty ? "—" : list[current].caption).font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(Brand.cream)
                .fixedSize(horizontal: false, vertical: true)
            if list[current].focus != nil {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).stroke(Brand.amber, lineWidth: 1.5).frame(width: 12, height: 9)
                    Text(list[current].focusLabel.isEmpty ? "Check the framed part" : list[current].focusLabel)
                        .font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.amber)
                }
            }
            if !v.note.isEmpty {
                Text("v\(v.v): \(v.note)").font(.system(size: S(11))).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(Brand.line)
            if draft != nil {
                Text("NOTE \(pins.count + 1) · ON THIS SCREEN").font(Brand.label(8)).tracking(0.7).foregroundStyle(Brand.amber)
                TextField("What should change here?", text: $draftText, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: S(12))).lineLimit(2...5)
                    .padding(7).background(RoundedRectangle(cornerRadius: 6).fill(Brand.panel2))
                    .focused($draftFocused)
                    .onSubmit { saveDraft(m, list[current], v.v) }
                HStack {
                    Button("Save note") { saveDraft(m, list[current], v.v) }.disabled(draftText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { draft = nil; draftText = "" }.foregroundStyle(Brand.mute)
                }.buttonStyle(SteerButton()).font(.system(size: S(11.5)))
            }
            Text(pins.isEmpty ? "NOTES · none yet (⌘-click the screen)" : "NOTES · \(pins.count)").font(Brand.label(8)).tracking(0.7).foregroundStyle(Brand.mute)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(pins.enumerated()), id: \.offset) { n, p in
                        let k = list.firstIndex { $0.path == p.img }
                        HStack(alignment: .top, spacing: 7) {
                            marker(n + 1).scaleEffect(0.85)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.note).font(.system(size: S(11.5))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                                Text(k.map { "screen \($0 + 1)" } ?? "other screen").font(.system(size: S(10))).foregroundStyle(Brand.mute)
                            }
                            Spacer(minLength: 0)
                            Button { board.editPins(m.ref) { l in l.removeAll { ($0["img"] as? String) == p.img && ($0["x"] as? Double) == p.x && ($0["y"] as? Double) == p.y } } } label: {
                                Image(systemName: "trash").font(.system(size: S(10)))
                            }.buttonStyle(SteerButton()).foregroundStyle(Brand.mute).help("Remove this note")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if let k { open.screen = k } }
                    }
                }
            }
            Spacer(minLength: 0)
            Text("NOTE FOR CLAUDE").font(Brand.label(8)).tracking(0.7).foregroundStyle(Brand.mute)
            TextField("Anything about the whole mockup", text: $overall, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: S(12))).lineLimit(2...4)
                .padding(7).background(RoundedRectangle(cornerRadius: 6).fill(Brand.panel2))
                .onSubmit { saveOverall(m) }
            if overall != board.mockupVerdict(m).note {
                Button("Save note") { saveOverall(m) }.buttonStyle(SteerButton()).font(.system(size: S(11.5)))
            }
        }
        .padding(14)
        .frame(width: S(260))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Brand.panel)
    }

    private func saveDraft(_ m: Mockup, _ s: MockupScreen, _ v: Int) {
        let t = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let d = draft, !t.isEmpty else { return }
        board.addPin(m.ref, img: s.path, x: d.x, y: d.y, note: t, version: v)
        draft = nil; draftText = ""; noteMode = false
    }
    private func saveOverall(_ m: Mockup) {
        let c = board.mockupVerdict(m)
        board.setMockup(m.id, version: m.current?.v ?? 1, pick: c.ok ? "ok" : nil, note: overall)
    }
    private func step(_ d: Int) {
        guard let m = mockup else { return }
        let n = screens(m).count
        if (0..<n).contains(open.screen + d) { open.screen += d; draft = nil }
    }
    private func close() { model.mockupOpen = nil }
}
