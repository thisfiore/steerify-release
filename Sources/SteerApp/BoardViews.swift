import SwiftUI
import AppKit
import ImageIO
import WebKit

// MARK: - Brand

enum Brand {
    static let bg = Color(hex: 0x07080a), panel = Color(hex: 0x111318), panel2 = Color(hex: 0x171a20)
    static let line = Color(hex: 0x23262e), line2 = Color(hex: 0x343944)
    static let ink = Color(hex: 0xece8dc), mute = Color(hex: 0x8f8a7d), cream = Color(hex: 0xf2e8cf)
    static let amber = Color(hex: 0xffb020), amberDim = Color(hex: 0x2a2110)
    static let green = Color(hex: 0x4ade80), red = Color(hex: 0xf87171), blue = Color(hex: 0x8fb0ff)
    /// Your turn on the board (a test, a choice, a release waits on you).
    static let violet = Color(hex: 0xc4a7ff)
    /// Label face: Silkscreen, the pixel font of the site (bundled, OFL). Its pixels sit on an 8-unit grid, so the
    /// size snaps to 8 / 12 / 16 pt (whole pixels on Retina); monospaced caps if the font could not be loaded.
    static func label(_ size: CGFloat = 10) -> Font {
        guard LabelFont.ready else { return .system(size: S(size), weight: .bold, design: .monospaced) }
        return .custom(LabelFont.name, fixedSize: LabelFont.snap(S(size)))
    }
}

/// The bundled pixel font (fonts/Silkscreen-*.ttf → Contents/Resources/fonts), registered for this process only.
enum LabelFont {
    static let name = "Silkscreen"
    static let ready: Bool = {
        let files = ["Silkscreen-Regular", "Silkscreen-Bold"]
        // The app bundle; `swift run` / test builds read the repo's fonts/ folder next to Sources/.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("fonts")
        var ok = false
        for f in files {
            let dev = repo.appendingPathComponent(f + ".ttf")
            guard let url = Bundle.main.url(forResource: f, withExtension: "ttf", subdirectory: "fonts")
                ?? (FileManager.default.fileExists(atPath: dev.path) ? dev : nil) else { continue }
            var err: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err) { ok = true }
            else if let e = err?.takeRetainedValue(), CFErrorGetCode(e) == CTFontManagerError.alreadyRegistered.rawValue { ok = true }
        }
        return ok && NSFont(name: name, size: 8) != nil
    }()
    /// Whole font pixels: 8 pt (labels up to ~11 pt before), 12 pt, then 16 pt.
    static func snap(_ pt: CGFloat) -> CGFloat { pt < 11.5 ? 8 : pt < 15.5 ? 12 : 16 }
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

/// 9×9 pixel icons, drawn natively (same set as the site).
struct PixelIcon: View {
    let name: String
    var size: CGFloat = 11
    static let maps: [String: [String]] = [
        "test": ["#########", "#.......#", "#......##", "#.....#.#", "##...#..#", "#.#.#...#", "#..#....#", "#.......#", "#########"],
        "choice": ["#.......#", "#.......#", ".#.....#.", "..#...#..", "...#.#...", "....#....", "....#....", "....#....", "....#...."],
        "req": [".#######.", ".#.....#.", ".#.###.#.", ".#.....#.", ".#.###.#.", ".#.....#.", ".#.##..#.", ".#.....#.", ".#######."],
        "road": [".#.......", ".######..", ".#######.", ".######..", ".#.......", ".#.......", ".#.......", ".#.......", "###......"],
        "term": ["#########", "#.......#", "#.#.....#", "#..#....#", "#.#..##.#", "#.......#", "#########", ".........", "........."],
        "play": [".#.......", ".##......", ".###.....", ".####....", ".#####...", ".####....", ".###.....", ".##......", ".#......."],
        "task": ["..####...", ".#....#.#", "#......##", "#.....###", "#........", "#.......#", "#.......#", ".#.....#.", "..#####.."],
        "ship": ["....#....", "...###...", "..#####..", "....#....", "....#....", "#########", ".#######.", "..#####..", "........."],
        "rocket": ["......###", ".....####", "....#..#.", "...#####.", ".######..", "..####...", ".#.##....", "#.#......", "#........"],
        "boat": ["....#....", "....##...", "....###..", "....####.", "....#####", "....#....", "#########", ".#######.", "..#####.."],
        "phone": ["..#####..", "..#...#..", "..#...#..", "..#...#..", "..#...#..", "..#...#..", "..#...#..", "..#.#.#..", "..#####.."],
    ]
    var body: some View {
        Canvas { ctx, sz in
            let cell = sz.width / 9
            for (y, row) in (Self.maps[name] ?? []).enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .foreground)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Board screen

enum BoardTab: String, CaseIterable { case ready, test, choice, req, road, task, release
    var title: String { ["ready": "READY", "test": "TO TEST", "choice": "CHOICES", "req": "REQUIREMENTS", "road": "ROADMAP", "task": "TASKS", "release": "RELEASE"][rawValue]! }
    var icon: String { self == .release ? "ship" : self == .ready ? "play" : rawValue }
    var color: Color { [.ready: Brand.amber, .test: Brand.blue, .choice: Brand.amber, .req: Color(hex: 0xc4a7ff), .road: Brand.green, .task: Brand.claude, .release: Brand.claude][self]! }
}

struct BoardScreen: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    @AppStorage(Prefs.boardTab, store: Prefs.store) private var tab: BoardTab = .test
    @State private var area: String? = {     // test hook: `--area <key>` opens the tab with that area filter
        let a = CommandLine.arguments
        return a.firstIndex(of: "--area").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil }
    }()
    @State private var state: String = {   // test hook: `--show decided` opens that filter
        let a = CommandLine.arguments
        return a.firstIndex(of: "--show").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } ?? "open"
    }()
    @AppStorage(Prefs.testLayout, store: Prefs.store) private var testLayout = "list"
    @State private var pendingScroll: AppModel.FocusRequest? = nil
    /// ★ Focus on, per tab (choice focus-filter-look: off by default, remembered per tab). Comma list of tab ids.
    @AppStorage("focusFilterTabs", store: Prefs.store) private var focusTabs = ""
    private var focusOn: Bool { !board.focus.isEmpty && focusTabs.split(separator: ",").contains { $0 == tab.rawValue } }
    private func setFocusOn(_ on: Bool) {
        var t = Set(focusTabs.split(separator: ",").map(String.init)); if on { t.insert(tab.rawValue) } else { t.remove(tab.rawValue) }
        focusTabs = t.sorted().joined(separator: ",")
    }
    private func focusOK(_ ref: String) -> Bool { !focusOn || board.inFocus(ref) }
    /// The roadmap item last asked for: stays open (chapter, Done) after the scroll, until the tab changes.
    @State private var revealRef: String? = nil
    @ObservedObject private var smart = SmartAreaModel.shared
    /// Roadmap areas = the product's features, from the chapter titles (choice feature-areas), once grouped.
    private var smartAreas: SmartAreas? { tab == .road ? smart.get(board.project.id) : nil }
    private var areaList: [(key: String, name: String)] { smartAreas.map { $0.areas.map { (key: $0.key, name: $0.name) } } ?? board.areas }
    /// A key result's areas: its chapter's feature, then the other areas its text names.
    private func roadAreas(_ r: RoadItem, _ sa: SmartAreas?? = nil) -> [String] { (sa ?? smartAreas).map { $0.keys(r.id) } ?? [r.area] }

    /// The chapter of a roadmap ref ("road:<id>" or "track:<slug>").
    private func roadTrack(of ref: String) -> String? {
        ref.hasPrefix("road:") ? board.roadmap.first { "road:" + $0.id == ref }?.track
        : ref.hasPrefix("track:") ? board.roadmap.first { "track:" + BoardFiles.slug($0.track) == ref }?.track : nil
    }
    private var roadSignature: String { "\(board.project.id)|\(board.roadmap.count)|\(Set(board.roadmap.map(\.track)).count)" }
    private func scroll(_ proxy: ScrollViewProxy) {
        guard let f = pendingScroll else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // The lazy list finds rows it has not built yet by the identity of its ForEach (chapter name, "road:<id>"),
            // not by an .id() inside them: go to the chapter first, then to the key result inside it.
            if tab == .road, let track = roadTrack(of: f.ref) {
                proxy.scrollTo(track, anchor: .top)
                if f.ref.hasPrefix("road:") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation { proxy.scrollTo(f.ref, anchor: .center) } }
                }
            } else {
                withAnimation { proxy.scrollTo(f.ref, anchor: .top) }
            }
            if pendingScroll == f { pendingScroll = nil }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The TabBar lives in ContentView, across the full window (board + sessions).
            if tab != .ready { NextStrip(board: board, openReady: { tab = .ready }, openTab: { tab = $0 }).padding(.top, 6).padding(.bottom, 4) }
            if tab == .release {
                ReleaseScreen(board: board)
            } else if tab == .ready {
                ReadyScreen(projectId: board.project.id)
            } else if tab == .task {
                TasksScreen(board: board)
            } else {
            FilterBar(board: board, tab: tab, area: $area, state: $state, counts: counts, areaCounts: areaCounts, areas: areaList,
                      smartAt: smartAreas?.at, smartRunning: smart.running.contains(board.project.id),
                      regroup: tab == .road ? { Task { await smart.refresh(board, force: true) } } : nil,
                      areaMenu: smartAreas == nil ? nil : AreaMenu(projectId: board.project.id),
                      focus: [.test, .choice, .req].contains(tab) && !board.focus.isEmpty
                        ? FocusChip(on: focusOn, count: focusCount, chapters: board.focus, toggle: { setFocusOn(!focusOn) }) : nil)
            if tab == .road { AutoConsolidateBar(board: board).id(board.project.id) }
            ScrollViewReader { proxy in
                ScrollView {
                    // The roadmap is lazy again, but in small rows: an open chapter is no longer one card taller than the
                    // window (the lazy list got stuck re-placing such a card for ever, 21 Nov 13:17: main thread 100%,
                    // +15 MB a second). Each chapter is a header, one row per key result and a footer (ChapterPiece),
                    // so only what is on screen is built and a change in the app redraws only that.
                    Group {
                        if tab == .road { LazyVStack(spacing: 0) { list } } else { LazyVStack(spacing: 10) { list } }
                    }
                    .padding(12)
                }
                // The list may only just have appeared (jump from Ready / Tasks / Release): scroll once it is there.
                .onAppear { scroll(proxy) }
                .onChange(of: pendingScroll) { _, _ in scroll(proxy) }
            }
        }
        }
        .background(Brand.bg)
        // Listened to here, not on the list: a jump from Ready, Tasks or Release (Where you left off,
        // Also waiting on you) must switch the tab even though no list is showing yet.
        .onChange(of: model.focus) { _, f in
            guard let f, f.projectId == board.project.id else { return }
            if f.ref.hasPrefix("test:") { testLayout = "list" }   // a jump to a card opens it in full
            let kind = String(f.ref.split(separator: ":").first ?? "")
            if let t = BoardTab(rawValue: kind == "track" ? "road" : kind == "reqs" ? "req" : kind) { tab = t }
            // After the tab switch (which resets the filter): show everything so the item is in the list.
            DispatchQueue.main.async {
                area = nil; state = "all"
                // A key result or a chapter: open its chapter first (it may be folded to one line), then scroll.
                if let track = roadTrack(of: f.ref) { ChapterFolds.shared.set(board.project.id, BoardFiles.slug(track), folded: false) }
                revealRef = f.ref
                pendingScroll = f
            }
        }
        .onChange(of: tab) { _, _ in state = "open"; area = nil; revealRef = nil }
        // The local AI regroups this project's roadmap now if due, then every hour while it is open.
        .task(id: board.project.id) { await smart.keepFresh(board) }
        // A chapter or key result added / renamed: regroup at once (plain words, instant; cached model answers).
        .task(id: roadSignature) { await smart.refresh(board) }
        // Once per roadmap visit (it was a task on every chapter).
        .task(id: "\(board.project.id)|\(tab.rawValue)") { if tab == .road { await board.refreshCommitProposals() } }
    }

    @ViewBuilder private var list: some View {
        switch tab {
        case .test:
            if testLayout == "grid" {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: S(290)), spacing: 10, alignment: .top)], spacing: 10) {
                    ForEach(ships) { ShipTile(board: board, item: $0).id("test:" + $0.id).flash("test:" + $0.id) }
                }
            } else {
                ForEach(ships) { ShipCard(board: board, item: $0).id("test:" + $0.id).flash("test:" + $0.id) }
            }
            if ships.isEmpty { EmptyBoard(projectId: board.project.id, title: state == "open" ? "NOTHING TO TEST" : "NOTHING HERE", line: "Claude is either working or sleeping.", kind: .test) }
        case .choice:
            ForEach(choices) { DecisionCard(board: board, d: $0).id("choice:" + $0.id).flash("choice:" + $0.id) }
            if choices.isEmpty { EmptyBoard(projectId: board.project.id, title: "NO OPEN CHOICES", line: "You are, briefly, unblocking no one.", kind: .choice) }
        case .req:
            ForEach(reqGroups, id: \.self) { g in ReqGroupView(board: board, group: g, items: reqs.filter { $0.group == g }) }
            if reqs.isEmpty { EmptyBoard(projectId: board.project.id, title: "NOTHING TO REVIEW", line: "Every requirement has an answer. Suspicious, but nice.", kind: .req) }
        case .release, .ready, .task:
            EmptyView()
        case .road:
            // Outdated key results: AutoConsolidateBar above the list (countdown, then the done scene).
            ForEach(roadTracks, id: \.self) { t in RoadTrackView(board: board, track: t, items: road.filter { $0.track == t }, reveal: revealRef) }
            if road.isEmpty { EmptyBoard(projectId: board.project.id, title: "ROADMAP CLEAR", line: "Either everything is done or nobody wrote it down.", kind: .road) }
        }
    }

    // Filtering (area + state), per tab. Each state is a function so the filter bar can show counts.
    private func inArea(_ a: [String], _ sel: String?) -> Bool { sel == nil || a.contains(sel!) }
    private var ships: [ShipItem] { focusFirst(shipsIn(state)) { "test:" + $0.id } }
    private var choices: [BoardDecision] { focusFirst(choicesIn(state)) { "choice:" + $0.id } }
    private var reqs: [Requirement] { focusFirst(reqsIn(state)) { "req:" + $0.id } }
    /// Items of the chapters in focus always on top, in the focus order; the rest keep their order (request r261123-130505).
    private func focusFirst<T>(_ xs: [T], _ ref: (T) -> String) -> [T] {
        guard !board.focus.isEmpty else { return xs }
        let rank = xs.map { board.focusChapter(of: ref($0)).flatMap(board.focusRank) ?? Int.max }
        return xs.indices.sorted { (rank[$0], $0) < (rank[$1], $1) }.map { xs[$0] }
    }
    private var road: [RoadItem] { roadIn(state) }

    func shipsIn(_ st: String, area sel: String?? = nil) -> [ShipItem] {
        board.ships.filter { s in
            guard inArea([s.area], sel ?? area), focusOK("test:" + s.id) else { return false }
            let x = board.shipState(s), pick = board.effectivePick(s)
            switch st {
            case "open": return x == .toTest || x == .retest
            case "refine": return x == .waiting && pick == "refine"
            case "broken": return x == .waiting && pick == "broken"
            case "ok": return x == .ok
            case "after": return x == .afterRelease
            default: return true
            }
        }
    }
    func choicesIn(_ st: String, area sel: String?? = nil) -> [BoardDecision] {
        board.decisions.filter { d in
            guard inArea(d.areas, sel ?? area), focusOK("choice:" + d.id) else { return false }
            switch st {
            case "open": return !board.isDecided(d) && !board.isParked(d)
            case "decided": return board.isDecided(d)
            case "parked": return board.isParked(d)
            default: return true
            }
        }.reversed()
    }
    func reqsIn(_ st: String, area sel: String?? = nil) -> [Requirement] {
        board.requirements.filter { r in
            guard inArea([r.area], sel ?? area), focusOK("req:" + r.id) else { return false }
            switch st {
            case "open": return board.isOpen(r)
            case "decide": return board.isOpen(r) && r.status == "question"
            case "confirm": return board.isOpen(r) && r.status != "question"
            case "agreed": return board.isConfirmed(r)
            default: return true
            }
        }
    }
    private var reqGroups: [String] {
        let all = Array((NSOrderedSet(array: reqsIn(state).map(\.group)).array as! [String]).reversed())
        // Groups holding focused requirements first, in the focus order (request r261123-130505).
        let focused = NSOrderedSet(array: reqs.filter { board.inFocus("req:" + $0.id) }.map(\.group)).array as! [String]
        return focused + all.filter { !focused.contains($0) }
    }
    func roadIn(_ st: String, area sel: String?? = nil) -> [RoadItem] {
        let sa = smartAreas, a = sel ?? area   // once, not per key result
        return board.roadmap.filter { r in
            guard a == nil || inArea(roadAreas(r, .some(sa)), a) else { return false }
            switch st {
            case "open": return r.status != "done"
            case "done": return r.status == "done"
            default: return true
            }
        }
    }
    /// Drafts first, then the chapter with the latest activity (choice chapter-order): a status change, a delivery,
    /// a session started on it. Ties keep the newest chapter first.
    private var roadTracks: [String] {
        let list = Array((NSOrderedSet(array: road.map(\.track)).array as! [String]).reversed())
        let drafts = Set(board.chapters.filter(\.draft).map(\.name))
        let act = board.chapterActivity()
        let rest = list.enumerated().filter { !drafts.contains($0.element) }
            .sorted { (act[$0.element] ?? "", $1.offset) > (act[$1.element] ?? "", $0.offset) }.map(\.element)
        // Chapters in focus first, in their order (request r261123-095911), then drafts, then the latest activity.
        let focused = board.focus.filter { list.contains($0) }
        return focused + (list.filter { drafts.contains($0) } + rest).filter { !focused.contains($0) }
    }

    /// Items of the focused chapters in the state and area shown now (the number on the ★ Focus chip).
    private var focusCount: Int {
        switch tab {
        case .test: board.ships.filter { board.inFocus("test:" + $0.id) && shipsInState($0, state) && inArea([$0.area], area) }.count
        case .choice: board.decisions.filter { board.inFocus("choice:" + $0.id) && choiceInState($0, state) && inArea($0.areas, area) }.count
        case .req: board.requirements.filter { board.inFocus("req:" + $0.id) && reqInState($0, state) && inArea([$0.area], area) }.count
        default: 0
        }
    }
    private func shipsInState(_ s: ShipItem, _ st: String) -> Bool {
        let x = board.shipState(s), pick = board.effectivePick(s)
        switch st {
        case "open": return x == .toTest || x == .retest
        case "refine": return x == .waiting && pick == "refine"
        case "broken": return x == .waiting && pick == "broken"
        case "ok": return x == .ok
        case "after": return x == .afterRelease
        default: return true
        }
    }
    private func choiceInState(_ d: BoardDecision, _ st: String) -> Bool {
        switch st {
        case "open": return !board.isDecided(d) && !board.isParked(d)
        case "decided": return board.isDecided(d)
        case "parked": return board.isParked(d)
        default: return true
        }
    }
    private func reqInState(_ r: Requirement, _ st: String) -> Bool {
        switch st {
        case "open": return board.isOpen(r)
        case "decide": return board.isOpen(r) && r.status == "question"
        case "confirm": return board.isOpen(r) && r.status != "question"
        case "agreed": return board.isConfirmed(r)
        default: return true
        }
    }

    private func count(_ st: String) -> Int {
        switch tab { case .test: shipsIn(st).count; case .choice: choicesIn(st).count; case .req: reqsIn(st).count; case .road: roadIn(st).count; case .release, .ready, .task: 0 }
    }
    private var counts: [String: Int] {
        Dictionary(uniqueKeysWithValues: FilterBar.states(tab).map { ($0.0, count($0.0)) })
    }
    /// Per area, in the state shown now ("" = all areas).
    /// One pass over the items of this state (was one full filter per area chip, on every app change).
    private var areaCounts: [String: Int] {
        var out: [String: Int] = ["": 0]
        func add(_ areas: [String]) { out["", default: 0] += 1; for a in Set(areas) { out[a, default: 0] += 1 } }
        switch tab {
        case .test: for s in shipsIn(state, area: .some(nil)) { add([s.area]) }
        case .choice: for d in choicesIn(state, area: .some(nil)) { add(d.areas) }
        case .req: for r in reqsIn(state, area: .some(nil)) { add([r.area]) }
        case .road: let sa = smartAreas; for r in roadIn(state, area: .some(nil)) { add(roadAreas(r, .some(sa))) }
        case .release, .ready, .task: break
        }
        return out
    }
}

struct Empty: View {
    let text: String
    var body: some View { Text(text).font(.callout).italic().foregroundStyle(Brand.mute).padding(.vertical, 40) }
}

struct TabBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    @Binding var tab: BoardTab
    var body: some View {
        let sessionCounts = model.sessionCounts(projectId: board.project.id)
        HStack(spacing: 2) {
            ForEach(Array(BoardTab.allCases.enumerated()), id: \.element) { i, t in
                Button { tab = t } label: {
                    HStack(spacing: 8) {
                        PixelIcon(name: t.icon, size: S(15)).foregroundStyle(tab == t ? t.color : t.color.opacity(0.55))
                        Text(t.title).font(Brand.label(12)).tracking(0.9)
                        let n = badge(t)
                        if n > 0 { Text("\(n)").font(.system(size: S(11), weight: .bold)).foregroundStyle(Color(hex: 0x1a1200)).padding(.horizontal, 5).padding(.vertical, 1).background(RoundedRectangle(cornerRadius: 4).fill(t.color)) }
                        if let k = sessionCounts[t], k > 0 {
                            HStack(spacing: 2) { Image(systemName: "terminal").font(.system(size: S(9))); Text("\(k)").font(.system(size: S(10.5)).monospacedDigit()) }
                                .foregroundStyle(Brand.mute).help("\(k) session\(k == 1 ? "" : "s") on this tab")
                        }
                    }
                    .foregroundStyle(tab == t ? Brand.cream : Brand.mute)
                    .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(tab == t ? t.color : .clear).frame(height: 3) }
                    .contentShape(Rectangle())
                }.buttonStyle(SteerButton())
                .help("\(t.title.capitalized) (⌘\(i + 1)) · ⌘[ ⌘] previous / next tab")
            }
            Spacer(minLength: 12)
            // Toasts live here, top right above the sessions: never over the terminal you type in.
            if let t = model.toast {
                ToastView(toast: t, compact: true).frame(maxWidth: S(520), alignment: .trailing).layoutPriority(-1)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            PhoneStatusButton(project: board.project)   // green while the iPhone is connected; opens the pairing window
        }
        .padding(.horizontal, 8)

        .animation(.easeOut(duration: 0.2), value: model.toast)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
    /// What needs you: refine/broken + untested on To test, open choices, unreviewed requirements.
    private func badge(_ t: BoardTab) -> Int {
        switch t {
        case .ready: return model.groupedNudges(board.project.id).count + model.releasable(board.project.id).count
        case .test: return board.ships.filter { [.toTest, .retest].contains(board.shipState($0)) }.count
        case .choice: return board.decisions.filter { !board.isDecided($0) && !board.isParked($0) }.count
        case .req: return board.requirements.filter { $0.status == "question" && board.isOpen($0) }.count
        case .road: return 0
        case .task: return TaskStore.load(board.project.boardDir).runs.filter { $0.status == "done" || $0.status == "noresult" }.count
        case .release: return board.ships.filter { board.goesInRelease($0) }.count
        }
    }
}

struct FilterBar: View {
    @ObservedObject var board: BoardStore
    let tab: BoardTab
    @Binding var area: String?
    @Binding var state: String
    let counts: [String: Int]
    /// Items per area in the current state (nil key = every area), for the area chips.
    var areaCounts: [String: Int] = [:]
    var areas: [(key: String, name: String)] = []
    /// Set when the areas are the local AI's groups (choice smart-areas): when it last regrouped.
    var smartAt: Date? = nil
    var smartRunning = false
    var regroup: (() -> Void)? = nil
    /// Feature areas: right-click a chip to rename, merge or hide it (kept across regroupings).
    var areaMenu: AreaMenu? = nil
    /// "Only in Focus" checkbox, on the right; shown only when a chapter is in focus.
    var focus: FocusChip? = nil
    /// Chips shown before "+ N more".
    static let maxChips = 12

    static func states(_ tab: BoardTab) -> [(String, String)] {
        switch tab {
        case .test: [("open", "To test"), ("after", "After release"), ("refine", "Refine"), ("broken", "Broken"), ("ok", "OK"), ("all", "All")]
        case .choice: [("open", "Open"), ("decided", "Decided"), ("parked", "Parked"), ("all", "All")]
        case .req: [("open", "Open"), ("decide", "To decide"), ("confirm", "To confirm"), ("agreed", "Settled"), ("all", "All")]
        case .road: [("open", "Active"), ("done", "Done"), ("all", "All")]
        case .release, .ready, .task: [("all", "All")]
        }
    }
    private var states: [(String, String)] { Self.states(tab) }

    /// State segments on one quiet line; the areas as tags right under them (request r261121-105031), one click each.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            stateRow
            if areas.count > 1 { areaRow }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 10)
    }

    private var stateRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(states, id: \.0) { s in
                    let on = state == s.0, n = counts[s.0] ?? 0
                    Button { state = s.0 } label: {
                        HStack(spacing: 5) {
                            Text(s.1)
                            if n > 0 || on { Text("\(n)").monospacedDigit().foregroundStyle(on ? Color(hex: 0xffd27a).opacity(0.7) : Brand.mute) }
                        }
                        .font(.system(size: S(12), weight: on ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundStyle(on ? Color(hex: 0xffd27a) : n == 0 && s.0 != "all" ? Brand.mute : Brand.ink)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Brand.amberDim : .clear))
                        .contentShape(Rectangle())
                    }.buttonStyle(SteerButton())
                }
            }
            Spacer(minLength: 8)
            if let f = focus { focusChip(f) }
            if area != nil || state != "open" {
                Button("Clear") { area = nil; state = "open" }.buttonStyle(.link).pointerStyle(.link).font(.system(size: S(11.5)))
            }
            if tab == .test { LayoutSwitch() }
        }
    }

    /// "Only in Focus" checkbox on the right (request r261123-130505): focused items are always on top anyway,
    /// this hides the rest.
    private func focusChip(_ f: FocusChip) -> some View {
        Toggle(isOn: Binding(get: { f.on }, set: { if $0 != f.on { f.toggle() } })) {
            HStack(spacing: 4) {
                Text("Only in Focus")
                Text("\(f.count)").monospacedDigit().foregroundStyle(Brand.mute)
            }
            .font(.system(size: S(11.5)))
            .foregroundStyle(f.on ? Brand.amber : Brand.ink)
        }
        .toggleStyle(.checkbox)
        .help("Items of the chapters in focus are always on top. Tick to hide the rest: "
              + f.chapters.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " · "))
    }

    /// One tag per area: click to show only that area, click again (or All) to show everything.
    /// Feature areas: the 12 biggest (plus the one selected), the rest under "+ N more".
    private var areaRow: some View {
        let ranked = areaMenu == nil ? areas : areas.enumerated()
            .sorted { (areaCounts[$0.element.key] ?? 0, -$0.offset) > (areaCounts[$1.element.key] ?? 0, -$1.offset) }.map(\.element)
        let shown = areaMenu == nil ? ranked : ranked.enumerated().filter { $0.offset < Self.maxChips || $0.element.key == area }.map(\.element)
        let more = ranked.filter { a in !shown.contains { $0.key == a.key } }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                areaTag(nil, areaMenu == nil ? "All areas" : "All", areaCounts[""] ?? 0)
                ForEach(shown, id: \.key) { a in
                    areaTag(a.key, a.name, areaCounts[a.key] ?? 0)
                        .contextMenu { if let m = areaMenu { m.items(key: a.key, name: a.name, others: areas.filter { $0.key != a.key }) } }
                }
                if !more.isEmpty {
                    Menu {
                        ForEach(more, id: \.key) { a in Button("\(a.name)  \(areaCounts[a.key] ?? 0)") { area = a.key } }
                    } label: {
                        Text("+ \(more.count) more").font(.system(size: S(11))).foregroundStyle(Brand.ink)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .overlay(Capsule().stroke(Brand.line2, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("The other areas, smaller")
                }
                if smartAt != nil || smartRunning || regroup != nil { smartNote }
            }
            .padding(.leading, 2)
        }
    }
    /// Where these groups come from and when; click to regroup now.
    private var smartNote: some View {
        Button { regroup?() } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: S(9.5)))
                Text(smartRunning ? "Regrouping…" : smartAt == nil ? "Group by feature" : "From your chapter names")
            }
            .font(.system(size: S(10.5))).foregroundStyle(Brand.mute).padding(.leading, 4)
        }.buttonStyle(.plain).pointerStyle(.link).disabled(smartRunning || regroup == nil)
        .help("Areas are the features your chapter titles name. Key results of Fixes & refinements are sorted by the on-device model. Right-click a chip to rename, merge or hide it. Click to regroup now.")
    }
    private func areaTag(_ key: String?, _ name: String, _ n: Int) -> some View {
        let on = area == key
        return Button { area = on ? nil : key } label: {
            HStack(spacing: 4) {
                if key != nil { Text("#").foregroundStyle(on ? Color(hex: 0xffd27a).opacity(0.6) : Brand.mute) }
                Text(name)
                Text("\(n)").monospacedDigit().foregroundStyle(on ? Color(hex: 0xffd27a).opacity(0.7) : Brand.mute)
            }
            .font(.system(size: S(11), weight: on ? .semibold : .regular))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(on ? Color(hex: 0xffd27a) : n == 0 ? Brand.mute : Brand.ink)
            .background(Capsule().fill(on ? Brand.amberDim : .clear))
            .overlay(Capsule().stroke(on ? Color(hex: 0xffd27a).opacity(0.5) : Brand.line2))
            .contentShape(Capsule())
        }.buttonStyle(SteerButton())
        .help(key == nil ? "Every area" : on ? "Showing \(name) only · click to show every area" : "Show \(name) only")
    }
}

/// List (full cards) or Grid (picture + verdict) on the To test tab.
struct LayoutSwitch: View {
    @AppStorage(Prefs.testLayout, store: Prefs.store) private var layout = "list"
    var body: some View {
        HStack(spacing: 0) {
            seg("list", "rectangle.grid.1x2", "List: full cards")
            seg("grid", "square.grid.2x2", "Grid: picture and verdict only")
        }
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.line2))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
    private func seg(_ k: String, _ icon: String, _ help: String) -> some View {
        Button { layout = k } label: {
            Image(systemName: icon)
                .font(.system(size: S(11.5), weight: layout == k ? .semibold : .regular))
                .padding(.horizontal, 7).padding(.vertical, 4)
                .foregroundStyle(layout == k ? Color(hex: 0xffd27a) : Brand.ink)
                .background(layout == k ? Brand.amberDim : .clear)
        }.buttonStyle(SteerButton()).help(help)
    }
}

// MARK: - Shared bits

struct Pill: View {
    let text: String; let color: Color
    var body: some View {
        Text(text.uppercased()).font(Brand.label(8.5)).tracking(0.6).foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(0.7)))
    }
}

struct ActionButton: View {
    let title: String; var icon: String = "play"; var primary = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) { PixelIcon(name: icon, size: 9); Text(title).font(.system(size: S(11.5), weight: .semibold)) }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(primary ? Color(hex: 0x1a1200) : Brand.cream)
                .background(RoundedRectangle(cornerRadius: 6).fill(primary ? Brand.amber : .clear))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary ? Brand.amber : Brand.line2))
        }.buttonStyle(SteerButton())
    }
}

/// "● session" chip on a card: shows the live session for this item and jumps to it.
struct SessionChip: View {
    @EnvironmentObject var model: AppModel
    let projectId: String; let ref: String
    var body: some View {
        if let s = model.sessions.first(where: { $0.projectId == projectId && $0.covers(ref) && $0.running }) {
            Button { model.selectedSession[projectId] = s.id } label: {
                SessionStateBadge(session: s)
            }.buttonStyle(SteerButton()).help("Show this item's session")
        } else if let p = model.projects.first(where: { $0.id == projectId }),
                  let link = model.board(for: p).lastLink(ref), SessionLinks.resumable(link.claudeSession) {
            Button { model.resume(link, projectId: projectId) } label: {
                HStack(spacing: 4) { Image(systemName: "arrow.uturn.backward").font(.system(size: S(9), weight: .bold)); Text("Resume · \(Self.ago(link.started))").font(.system(size: S(11))) }
                    .foregroundStyle(Brand.cream)
            }.buttonStyle(SteerButton()).help("Reopen this item's Claude conversation (\(link.intent), \(link.repo))")
        }
    }
    private static let agoFormat: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static func ago(_ iso: String) -> String {
        guard let d = agoFormat.date(from: iso) else { return "earlier" }
        let m = Int(-d.timeIntervalSinceNow / 60)
        return m < 60 ? "\(max(m, 1)) min ago" : m < 1440 ? "\(m / 60) h ago" : "\(m / 1440) d ago"
    }
}

struct Card<Content: View>: View {
    var highlight: Color? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(highlight ?? Brand.line))
    }
}

private extension Array where Element == RoadItem {
    /// A row group's identity in the list: the ref of its first key result.
    var ref: String { "road:" + (first?.id ?? "") }
}

/// One row of an open roadmap chapter. The chapter looks like one card (same fill, one frame around it) but is laid
/// out as separate rows of the lazy list: a header (`.top`), its lines (`.middle`), a footer (`.bottom`).
struct ChapterPiece: ViewModifier {
    enum Part { case top, middle, bottom }
    let part: Part
    func body(content: Content) -> some View {
        let r: CGFloat = 9
        let shape = UnevenRoundedRectangle(topLeadingRadius: part == .top ? r : 0, bottomLeadingRadius: part == .bottom ? r : 0,
                                           bottomTrailingRadius: part == .bottom ? r : 0, topTrailingRadius: part == .top ? r : 0)
        content
            .padding(.horizontal, 12)
            .padding(.top, part == .top ? 12 : 4).padding(.bottom, part == .bottom ? 8 : 4)   // 8 pt between lines, as in a Card
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Brand.panel))
            // The frame: this row's share of it. The outline is drawn taller than the row where the chapter goes on,
            // and cut at the row's edge, so only the sides (and the rounded end) show and the rows join without a seam.
            .overlay(
                shape.stroke(Brand.line)
                    .padding(.top, part == .top ? 0 : -12).padding(.bottom, part == .bottom ? 0 : -12)
                    .mask(Rectangle().padding(.horizontal, -1).padding(.top, part == .top ? -1 : 0).padding(.bottom, part == .bottom ? -1 : 0))
            )
    }
}
extension View {
    func piece(_ part: ChapterPiece.Part = .middle) -> some View { modifier(ChapterPiece(part: part)) }
}

/// Note field that saves on Return or when focus leaves.
struct NoteField: View {
    let placeholder: String
    let initial: String
    /// true = take all the height it is given (the note box of a test row), click anywhere to write.
    var fill = false
    /// Bump it to put the cursor in the box (To refine on a test row).
    var focusTrigger = 0
    /// Amber frame: this box holds feedback Claude will act on.
    var marked = false
    let save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    init(placeholder: String, initial: String, fill: Bool = false, focusTrigger: Int = 0, marked: Bool = false, save: @escaping (String) -> Void) {
        self.placeholder = placeholder; self.initial = initial; self.fill = fill; self.focusTrigger = focusTrigger; self.marked = marked; self.save = save
    }
    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain).font(.system(size: S(12)))
            .lineLimit(fill ? 1...12 : 1...4)
            .padding(7)
            .frame(maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(marked ? Brand.amber.opacity(0.8) : Brand.line2, style: StrokeStyle(lineWidth: 1, dash: marked ? [] : [3, 2])))
            .focused($focused)
            .onChange(of: focusTrigger) { _, _ in focused = true }
            .onAppear { text = initial }
            .onChange(of: initial) { _, v in if !focused { text = v } }
            .onSubmit { flush() }
            .onChange(of: focused) { _, f in if !f { flush() } }
            // Typing saves by itself (0.6 s after the last key): a note is never lost because the user clicked a
            // verdict button (buttons don't take focus on macOS), switched item, or the board reloaded.
            .onChange(of: text) { _, _ in
                guard focused else { return }
                pending?.cancel()
                pending = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    if !Task.isCancelled { flush() }
                }
            }
            .onDisappear { flush() }
    }

    @State private var pending: Task<Void, Never>?
    private func flush() {
        pending?.cancel(); pending = nil
        if text != initial { save(text) }
    }
}

/// Image from the board folder, decoded at the size it is shown × the screen scale (sharp, small memory), cached.
struct BoardImage: View {
    let dir: String; let path: String; var height: CGFloat = 110
    /// true = show the whole picture (hero), false = fill and crop (thumbnails)
    var fit = false
    /// Show only this part of the picture (0–1 rect from the top-left): the feature, not the whole window.
    var focus: CGRect? = nil
    var onOpen: (() -> Void)? = nil
    @State private var image: NSImage?
    @State private var hover = false
    /// The box on screen (points), rounded up to 64 pt so a resize does not decode again on every pixel.
    @State private var box: CGSize = .zero
    nonisolated(unsafe) static let cache = NSCache<NSString, NSImage>()   // NSCache is thread-safe
    nonisolated(unsafe) static let sizes = NSCache<NSString, NSValue>()
    static var backing: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }
    /// Pixel size of the file on disk (not of the decoded picture).
    private var native: CGSize? { Self.sizes.object(forKey: full as NSString)?.sizeValue }
    /// A whole window shown small: its text is too small to read in the list.
    private var wholeWindow: Bool {
        guard fit, focus == nil, let n = native, n.width >= 2800, box.width > 0 else { return false }
        return box.width * Self.backing / n.width < 0.5
    }
    var body: some View {
        // The image never drives the layout: a fixed-height box, the picture fills it and is clipped.
        Rectangle().fill(fit ? Color.black : Brand.panel2)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { box = Self.bucket(g.size) }
                    .onChange(of: g.size) { _, v in box = Self.bucket(v) }
            })
            .overlay {
                if let image {
                    if fit {
                        // Never stretch a file past one point per pixel (it would go soft): show it smaller instead.
                        let s: CGFloat = 1
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .frame(maxWidth: (native?.width ?? 8000) * (focus?.width ?? 1) / s, maxHeight: (native?.height ?? 8000) * (focus?.height ?? 1) / s)
                            .overlay(alignment: .bottomLeading) {
                                if let n = native, n.width < 1000, focus == nil {
                                    badge("LOW-RES · \(Int(n.width)) px", help: "The delivered picture is only \(Int(n.width)) px wide. Sessions now deliver full-size pictures.")
                                } else if wholeWindow {
                                    badge("WHOLE WINDOW · click to read", help: "This picture is a whole window shown small. Sessions should crop it to the feature or add focus.")
                                }
                            }
                    }
                    else { Image(nsImage: image).resizable().interpolation(.high).scaledToFill() }
                }
            }
            .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(hover ? Brand.cream.opacity(0.35) : Brand.line, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            if hover && height >= 70 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: S(9), weight: .bold))
                    Text("Preview").font(.system(size: S(10.5), weight: .semibold))
                    Text("· ⌘-click to pin").font(.system(size: S(10))).opacity(0.75)
                }
                .foregroundStyle(Color(hex: 0x1a1200))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Brand.amber))
                .padding(6)
                .transition(.opacity)
            }
        }
        .scaleEffect(hover ? 1.015 : 1)
        .shadow(color: .black.opacity(hover ? 0.5 : 0), radius: hover ? 8 : 0, y: hover ? 4 : 0)
        .animation(.easeOut(duration: 0.14), value: hover)
        .onHover { hover = $0 }
        .pointerStyle(.zoomIn)
        .contentShape(Rectangle())
        .onTapGesture { if let onOpen { onOpen() } else { NSWorkspace.shared.open(URL(fileURLWithPath: full)) } }
        .help("Click: preview · ⌘-click: preview ready to pin a note")
        .task(id: "\(path)#\(Self.key(full))#\(focus.map { "\($0)" } ?? "")#\(box)") {
            guard box != .zero else { return }
            image = await Self.load(full, focus: focus, box: box, fill: !fit)
        }
    }
    private func badge(_ t: String, help: String) -> some View {
        Text(t).font(Brand.label(8.5)).foregroundStyle(Brand.mute)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.7))).padding(6)
            .help(help)
    }
    private static func bucket(_ s: CGSize) -> CGSize {
        CGSize(width: (s.width / 64).rounded(.up) * 64, height: (s.height / 64).rounded(.up) * 64)
    }
    private var full: String { path.hasPrefix("/") ? path : (dir as NSString).appendingPathComponent(path) }
    /// Cache key = path + modification date, so a re-delivered screenshot with the same name shows the new picture.
    nonisolated static func key(_ p: String) -> NSString {
        let m = (try? FileManager.default.attributesOfItem(atPath: p)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(p)#\(m)" as NSString
    }
    /// Decode only as many pixels as the box shows on this screen (never more than the file has):
    /// sharp on Retina, and a 4K whole-window shot does not cost 4K of memory in a thumbnail.
    static func load(_ p: String, focus: CGRect? = nil, box: CGSize? = nil, fill: Bool = false) async -> NSImage? {
        let scale = backing
        return await Task.detached(priority: .utility) { () -> NSImage? in
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil) else { return nil }
            var maxPx = 1800
            if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               var w = props[kCGImagePropertyPixelWidth] as? Int, var h = props[kCGImagePropertyPixelHeight] as? Int {
                if let o = props[kCGImagePropertyOrientation] as? Int, o >= 5 { swap(&w, &h) }
                sizes.setObject(NSValue(size: CGSize(width: w, height: h)), forKey: p as NSString)
                if let box, box.width > 8, box.height > 8 {
                    let f = focus ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                    let rw = CGFloat(w) * max(f.width, 0.02), rh = CGFloat(h) * max(f.height, 0.02)
                    let s = fill ? max(box.width / rw, box.height / rh) : min(box.width / rw, box.height / rh)
                    maxPx = Int((CGFloat(max(w, h)) * min(1, s * scale * 1.1)).rounded(.up))
                } else { maxPx = focus == nil ? 1800 : 5000 }
                maxPx = max(maxPx, 256)
            }
            let k = "\(key(p))#\(focus.map { "\($0)" } ?? "")#\(maxPx)" as NSString
            if let c = cache.object(forKey: k) { return c }
            guard var cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                        kCGImageSourceThumbnailMaxPixelSize: maxPx,
                                                                        kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
            if let f = focus?.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)), f.width > 0.02, f.height > 0.02,
               let c = cg.cropping(to: CGRect(x: f.minX * CGFloat(cg.width), y: f.minY * CGFloat(cg.height),
                                              width: f.width * CGFloat(cg.width), height: f.height * CGFloat(cg.height)).integral) { cg = c }
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            cache.setObject(img, forKey: k)
            return img
        }.value
    }
}

// MARK: - To test

struct ShipCard: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let item: ShipItem
    @State private var expanded = false

    var body: some View {
        let pick = board.shipPick(item)
        let state = board.shipState(item)
        let prev = board.previousVerdict(item)
        Card(highlight: state == .toTest || state == .retest ? Brand.blue.opacity(0.55) : nil) {
            // Header: the title, its state, then 2–4 short bullets. No gallery: each test shows its own picture.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title).font(.system(size: S(15.5), weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                switch state {
                case .toTest: Pill(text: "to test", color: Brand.blue)
                case .retest: Pill(text: "re-test", color: Brand.blue)
                case .waiting: Pill(text: (board.effectivePick(item) ?? "refine") + " · waiting on Claude", color: board.effectivePick(item) == "broken" ? Brand.red : Brand.amber)
                case .ok: Pill(text: "ok", color: Brand.green)
                case .afterRelease: Pill(text: "after release", color: Brand.amber)
                }
                KindPill(kind: item.kind)
                if item.status != "local" { Pill(text: item.status.replacingOccurrences(of: "-", with: " "), color: item.status == "live" ? Brand.green : Brand.mute) }
                Text("\(board.areaName(item.area)) · v\(item.version)").font(.system(size: S(11))).foregroundStyle(Brand.mute).fixedSize()
                SessionChip(projectId: board.project.id, ref: "test:" + item.id)
            }
            if let pn = board.processedNotes(item), let ov = pn.v {
                ProcessedRecap(notes: pn, title: pn.notes.isEmpty ? "New version v\(item.version). On v\(ov)"
                               : "New version v\(item.version) · your \(pn.notes.count) note\(pn.notes.count == 1 ? "" : "s") on v\(ov)")
            } else if let prev {
                (Text("New version v\(item.version). On v\(prev.v) you said ").foregroundStyle(Brand.mute)
                 + Text(prev.pick).bold().foregroundStyle(prev.pick == "ok" ? Brand.green : Brand.amber)
                 + Text(prev.note.isEmpty ? "." : ": “\(prev.note.prefix(160))\(prev.note.count > 160 ? "…" : "")”").foregroundStyle(Brand.ink.opacity(0.8)))
                    .font(.system(size: S(12))).fixedSize(horizontal: false, vertical: true)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Brand.blue.opacity(0.08)))
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(item.bullets.enumerated()), id: \.offset) { _, b in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle().fill(Brand.mute).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        Text(BoardText.attributed(b)).font(.system(size: S(12.5))).foregroundStyle(Brand.ink.opacity(0.9)).lineLimit(2)
                    }
                }
            }.help(BoardText.plain(item.what))
            KindLine(kind: item.kind, waits: state == .afterRelease, live: item.status == "live")

            if state == .toTest || state == .retest { ShotIssues(board: board, item: item) }
            let pinCount = board.pins("test:" + item.id).count
            let extra = galleryItems.count
            if pinCount > 0 || extra > 0 {
                HStack(spacing: 14) {
                    if pinCount > 0 {
                        Button { openPreview(0) } label: {
                            Label("\(pinCount) note\(pinCount == 1 ? "" : "s") on the pictures", systemImage: "mappin.and.ellipse").font(.system(size: S(11.5)))
                        }.buttonStyle(SteerButton()).foregroundStyle(Brand.amber)
                    }
                    // Screenshots no test shows: one quiet link, not a gallery on top of the card.
                    if extra > 0, !item.tests.isEmpty, let first = galleryItems.first, let j = images.firstIndex(of: first.path) {
                        Button { openPreview(j) } label: {
                            Label("\(extra) more picture\(extra == 1 ? "" : "s")", systemImage: "photo.on.rectangle").font(.system(size: S(11.5)))
                        }.buttonStyle(SteerButton()).foregroundStyle(Brand.mute)
                    }
                }
            }
            if item.tests.isEmpty {
                // Older deliveries without tests: one row per screenshot, same shape as a test row.
                ForEach(Array(galleryItems.enumerated()), id: \.offset) { k, g in
                    TestRowFrame(dir: board.project.boardDir, img: g.path, focus: g.focus, accent: Brand.line2,
                                 open: { if let j = images.firstIndex(of: g.path) { openPreview(j) } }) {
                        Text(g.caption.isEmpty ? "Screenshot \(k + 1)" : g.caption).font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(.white).lineLimit(4)
                        Spacer(minLength: 0)
                    }
                }
            }

            if !item.tests.isEmpty {
                let fb = board.testFeedback(item)
                let refines = board.testRefines(item)
                let checked = Set(fb.filter { $0.value.ok }.map(\.key)).union(refines).count
                let notes = refines.count
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        PixelIcon(name: "test", size: 10).foregroundStyle(Brand.blue)
                        Text("TESTS").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.blue)
                        Text("\(checked) of \(item.tests.count) checked").font(.system(size: S(11.5))).foregroundStyle(Brand.ink)
                        if notes > 0 { Text("· \(notes) to refine").font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.amber) }
                        Spacer()
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Brand.line)
                            Capsule().fill(notes > 0 ? Brand.amber : Brand.green).frame(width: g.size.width * CGFloat(checked) / CGFloat(max(item.tests.count, 1)))
                        }
                    }.frame(height: 4)
                }
                ForEach(Array(item.tests.enumerated()), id: \.offset) { i, t in
                    TestChapter(board: board, item: item, index: i, count: item.tests.count, test: t, feedback: fb[i],
                                refine: refines.contains(i), openPicture: { img in
                                    if let k = images.firstIndex(of: img) { openPreview(k) }
                                })
                }
            }

            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 6) {
                    section("CLAUDE TESTED", item.tested, Brand.green)
                    section("HOW TO TEST", item.howTo, Brand.cream)
                    section("KNOWN ISSUES", item.issues, Brand.amber)
                }.padding(.top, 4)
            } label: { Text("Details").font(.system(size: S(11.5))).foregroundStyle(Brand.mute) }

            let notes = board.shipNotes(item)
            NotesForClaude(notes: notes, pick: pick)
            HStack(spacing: 6) {
                verdictButton("ok", notes.isEmpty ? "✓ OK" : "✓ OK + notes", Brand.green, pick)
                verdictButton("refine", "↻ Refine", Brand.amber, pick)
                verdictButton("broken", "✕ Broken", Brand.red, pick)
                Spacer()
                if state == .waiting {
                    ActionButton(title: "Fix my notes", primary: true) { model.start(projectId: board.project.id, item: ref, intent: .fix) }
                }
                if (pick == "ok" && item.status != "live" && item.releases) || state == .afterRelease {
                    ActionButton(title: state == .afterRelease ? "Release to test" : notes.isEmpty ? "Release" : "Apply notes + release", icon: "ship", primary: true) { model.start(projectId: board.project.id, item: ref, intent: .release) }
                }
                ClaudeButton(title: "Open with Claude") { model.start(projectId: board.project.id, item: ref, intent: .look) }
            }
            // Note only: never re-write the verdict from an older render (OK pressed while the note was still saving).
            NoteField(placeholder: "Note for Claude (what to change)…", initial: board.shipNote(item), marked: !board.shipNote(item).isEmpty) { board.setShip(item, pick: nil, note: $0) }
        }
    }

    private var ref: ItemRef { var r = ItemRef(ref: "test:" + item.id)!; r.title = item.title; r.area = item.area; return r }

    /// Screenshots with their captions, then the per-test pictures labelled with the test.
    /// The tests show their own pictures big, so the gallery keeps only the screenshots no test already shows.
    private var galleryItems: [GalleryItem] {
        var seen = Set(item.tests.compactMap(\.img)), out: [GalleryItem] = []
        for sh in item.shots where seen.insert(sh.img).inserted { out.append(GalleryItem(path: sh.img, caption: sh.caption, focus: item.focus[sh.img])) }
        return out
    }
    /// Screenshots first, then the per-test thumbnails (no duplicates).
    private var images: [String] {
        var seen = Set<String>()
        return (item.shots.map(\.img) + item.tests.compactMap(\.img)).filter { seen.insert($0).inserted }
    }
    private func openPreview(_ i: Int) {
        model.preview = PreviewState(projectId: board.project.id, ref: "test:" + item.id, title: item.title,
                                     dir: board.project.boardDir, images: images, index: min(i, max(images.count - 1, 0)), version: item.version, startInNoteMode: NSEvent.modifierFlags.contains(.command))
    }

    /// The verdict your test answers point to (all checked, no notes → OK; any note → Refine).
    private var suggested: String? {
        guard board.shipPick(item) == nil, !item.tests.isEmpty else { return nil }
        let fb = board.testFeedback(item)
        if !board.testRefines(item).isEmpty { return "refine" }
        return fb.values.filter(\.ok).count == item.tests.count ? "ok" : nil
    }

    private func verdictButton(_ k: String, _ title: String, _ c: Color, _ pick: String?) -> some View {
        let sug = suggested == k
        return Button { board.setShip(item, pick: k) } label: {
            Text(sug ? title + "  · suggested" : title).font(.system(size: S(11.5), weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(pick == k ? Color.black : c)
                .background(RoundedRectangle(cornerRadius: 6).fill(pick == k ? c : sug ? c.opacity(0.15) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(c.opacity(sug ? 1 : 0.7), lineWidth: sug ? 1.5 : 1))
        }.buttonStyle(SteerButton())
    }

    @ViewBuilder private func section(_ h: String, _ lines: [String], _ c: Color) -> some View {
        if !lines.isEmpty {
            Text(h).font(Brand.label(9)).foregroundStyle(c)
            ForEach(lines, id: \.self) { Text("· " + $0).font(.system(size: S(12))).foregroundStyle(Brand.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Grid card (choice kit-demo, option A): the picture, the title, what to check, and the verdict right under it.
/// OK is final; Refine / Broken open the full card so the note goes with it.
/// Design / on your Mac / on stage-prod: what kind of test a card is (request r261121-235412).
struct KindPill: View {
    let kind: TestKind
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.icon).font(.system(size: S(9.5)))
            Text(kind.label.uppercased()).font(Brand.label(8.5)).tracking(0.6)
        }
        .foregroundStyle(kind.color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(kind.color.opacity(0.12)))
        .overlay(Capsule().stroke(kind.color.opacity(0.35)))
        .fixedSize()
        .help(kind.okDoes)
    }
}

/// One line under the bullets: what your OK does, or that the card waits for the release.
struct KindLine: View {
    let kind: TestKind
    var waits = false
    var live = false
    var body: some View {
        let text = waits ? TestKind.waitsLine : kind == .online && live ? "Live now · test it there · OK closes it" : kind.okDoes
        HStack(spacing: 7) {
            Image(systemName: waits ? "hourglass" : "arrow.right.circle").font(.system(size: S(10.5)))
            Text(text).font(.system(size: S(11.5)))
        }
        .foregroundStyle(waits ? Brand.amber : kind.color.opacity(0.9))
    }
}

struct ShipTile: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let item: ShipItem

    var body: some View {
        let pick = board.shipPick(item)
        let state = board.shipState(item)
        Card(highlight: state == .toTest || state == .retest ? Brand.blue.opacity(0.55) : nil) {
            if let img = picture {
                BoardImage(dir: board.project.boardDir, path: img, height: S(170), focus: item.focus[img], onOpen: openFull)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.black).frame(height: S(170))
                    .overlay(Text("No picture").font(.system(size: S(11))).foregroundStyle(Brand.mute))
                    .onTapGesture(perform: openFull)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button(action: openFull) {
                    Text(item.title).font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(SteerButton()).help("Open the full card")
                statePill(state)
            }
            KindPill(kind: item.kind)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "eye").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                Text(checkLine).font(.system(size: S(11.5))).foregroundStyle(Brand.ink.opacity(0.85)).lineLimit(2, reservesSpace: true)
            }
            HStack(spacing: 6) {
                verdict("ok", "✓ OK", Brand.green, pick)
                verdict("refine", "↻ Refine", Brand.amber, pick)
                verdict("broken", "✕ Broken", Brand.red, pick)
            }
            let notes = board.shipNotes(item)
            if !notes.isEmpty {
                Label("\(notes.count) note\(notes.count == 1 ? "" : "s") for Claude · " + notes.summary, systemImage: "text.bubble.fill")
                    .font(.system(size: S(11))).foregroundStyle(Brand.amber).lineLimit(1)
                    .help(notes.overall.isEmpty ? "Claude reads them whatever you press" : "“\(notes.overall)”")
            }
        }
    }

    /// First test picture (the feature), else the first screenshot.
    private var picture: String? { item.tests.compactMap(\.img).first ?? item.shots.first?.img }
    private var checkLine: String {
        if item.tests.count == 1, let c = item.tests[0].check { return c }
        if !item.tests.isEmpty { return "\(item.tests.count) tests · " + (item.tests[0].check ?? item.tests[0].label) }
        return item.howTo.first ?? "\(board.areaName(item.area)) · v\(item.version)"
    }
    @ViewBuilder private func statePill(_ s: BoardStore.ShipState) -> some View {
        switch s {
        case .toTest: Pill(text: "to test", color: Brand.blue)
        case .retest: Pill(text: "re-test", color: Brand.blue)
        case .waiting: Pill(text: board.effectivePick(item) ?? "refine", color: board.effectivePick(item) == "broken" ? Brand.red : Brand.amber)
        case .ok: Pill(text: "ok", color: Brand.green)
        case .afterRelease: Pill(text: "after release", color: Brand.amber)
        }
    }
    private func verdict(_ k: String, _ title: String, _ c: Color, _ pick: String?) -> some View {
        Button {
            board.setShip(item, pick: k)
            if k != "ok" { openFull() }      // the note belongs to the verdict: write it on the full card
        } label: {
            Text(title).font(.system(size: S(11.5), weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .foregroundStyle(pick == k ? Color.black : c)
                .background(RoundedRectangle(cornerRadius: 6).fill(pick == k ? c : .clear))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(c.opacity(0.7)))
        }.buttonStyle(SteerButton())
    }
    private func openFull() { model.focusItem(projectId: board.project.id, ref: "test:" + item.id) }
}

struct TestRow: View {
    @EnvironmentObject var model: AppModel
    let test: ShipTest; let projectId: String
    var feedback: (ok: Bool, note: String)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            PixelIcon(name: "test", size: 10).foregroundStyle(Brand.mute).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                // No Test it when the link leads nowhere (an app link Steerify cannot act on): the picture is the test.
                if let u0 = test.url, case let u = TestEnvs.boardFile(u0, board: model.projects.first { $0.id == projectId }?.boardDir ?? "") ?? u0, !TestEnvs.dead(u), let url = URL(string: u) {
                    Button(test.label) { if url.scheme == "steerify" { model.handle(url) } else { openTestLink(url) } }
                        .buttonStyle(.link).pointerStyle(.link).font(.system(size: S(12), weight: .medium))
                } else { Text(test.label).font(.system(size: S(12), weight: .medium)) }
                if let c = test.check { Text(c).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true) }
                if let f = feedback {
                    if !f.note.isEmpty {
                        Text("Your note: “\(f.note)”").font(.system(size: S(11.5))).foregroundStyle(Brand.amber).fixedSize(horizontal: false, vertical: true)
                    } else if f.ok {
                        Text("✓ You checked this").font(.system(size: S(11.5))).foregroundStyle(Brand.green)
                    }
                }
            }
        }
    }
}

// MARK: - Choices

// The choice card lives in Decide.swift (DecisionCard: a guided decision, not a gallery).

/// HTML mockups stay HTML: a web view is created only while a mockup is open.
struct MockView: NSViewRepresentable {
    let dir: String; let option: BoardOption
    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView()
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        if let p = option.proto {
            w.loadFileURL(MockSnapshots.protoURL(p, base: base), allowingReadAccessTo: base)
        } else if let html = option.mockHTML {
            w.loadHTMLString("<html><head><meta name=viewport content='width=device-width'><style>html,body{margin:0;height:100%;background:#000;color:#e5e5e5;font:12px -apple-system}body>*{height:100%}</style></head><body>\(html)</body></html>", baseURL: base)
        }
        return w
    }
    func updateNSView(_ w: WKWebView, context: Context) {}
}

// MARK: - Requirements

struct ReqGroupView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let group: String; let items: [Requirement]
    @State private var showSettled = CommandLine.arguments.contains("--show-settled")   // test hook: settled lists open

    var body: some View {
        let all = board.requirements.filter { $0.group == group }
        let settled = all.filter(board.isConfirmed)
        let questions = items.filter { $0.status == "question" && board.isOpen($0) }
        let proposals = items.filter { $0.status != "question" && board.isOpen($0) }
        let others = items.filter { !board.isOpen($0) && !board.isConfirmed($0) }          // change / later
        let shipped = board.roadChapter(for: group)
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("REQUIREMENTS CHAPTER").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.mute)
                    Text(group).font(.system(size: S(14), weight: .semibold)).foregroundStyle(.white)
                    HStack(spacing: 10) {
                        count(settled.count, "settled", Brand.green)
                        count(all.filter { $0.status == "question" && board.isOpen($0) }.count, "to decide", Brand.amber)
                        count(all.filter { $0.status != "question" && board.isOpen($0) }.count, "to confirm", Brand.blue)
                        if let sh = shipped {
                            Text("· roadmap \(sh.done)/\(sh.total) done").font(.system(size: S(11))).foregroundStyle(sh.done * 5 >= sh.total * 4 ? Brand.green : Brand.mute)
                        }
                    }
                }
                Spacer()
                SessionChip(projectId: board.project.id, ref: "reqs:" + BoardFiles.slug(group))
                ClaudeButton(title: "Verify with Claude") { start(.consolidate) }
                    .help("Claude checks the code against each open requirement: built ones become ‘built ✓’, missing ones become roadmap items, questions become choices")
            }

            if !questions.isEmpty {
                sectionTitle("TO DECIDE", Brand.amber)
                ForEach(questions) { r in questionRow(r).id("req:" + r.id).flash("req:" + r.id) }
            }

            if !proposals.isEmpty {
                HStack {
                    sectionTitle("PROPOSED · TO CONFIRM", Brand.blue)
                    Spacer()
                    let isShipped = shipped.map { $0.total > 0 && $0.done * 5 >= $0.total * 4 } ?? false
                    if isShipped, let sh = shipped {
                        ActionButton(title: "Shipped (\(sh.done)/\(sh.total)) · confirm all \(proposals.count)", icon: "test", primary: true) { confirm(proposals) }
                            .help("Its roadmap chapter “\(sh.name)” is done: confirm these proposals in one go (Undo in the message)")
                    } else {
                        Button("Confirm all \(proposals.count)") { confirm(proposals) }
                            .buttonStyle(SteerButton()).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.green)
                    }
                }
                ForEach(proposals) { r in proposalRow(r).id("req:" + r.id).flash("req:" + r.id) }
            }

            ForEach(others) { r in proposalRow(r).id("req:" + r.id) }

            if !settled.isEmpty {
                Button { showSettled.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showSettled ? "chevron.down" : "chevron.right").font(.system(size: S(9), weight: .bold))
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.green)
                        Text("\(settled.count) settled").font(.system(size: S(11.5), weight: .semibold))
                    }.foregroundStyle(Brand.mute)
                }.buttonStyle(SteerButton())
                if showSettled {
                    ForEach(settled) { r in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark").font(.system(size: S(10), weight: .bold)).foregroundStyle(Brand.green).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.text).font(.system(size: S(12))).foregroundStyle(Brand.ink.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                                FeatureStrip(board: board, req: r, compact: true)
                                // Why it is settled, in plain sight (also the tooltip): "chapter approved …", "OK on To test · …".
                                if let ev = r.evidence, !ev.isEmpty {
                                    Text(ev).font(.system(size: S(10.5))).foregroundStyle(Brand.mute).lineLimit(1).truncationMode(.tail)
                                }
                            }
                            Spacer(minLength: 6)
                            Text(r.status == "built" ? "built" : r.status == "rule" ? "rule" : "agreed").font(.system(size: S(10.5))).foregroundStyle(Brand.green.opacity(0.8))
                        }.id("req:" + r.id).help(r.evidence ?? "")
                    }
                }
            }
        }
    }

    private func count(_ n: Int, _ label: String, _ c: Color) -> some View {
        Text("\(n) \(label)").font(.system(size: S(11), weight: n > 0 ? .semibold : .regular)).foregroundStyle(n > 0 ? c : Brand.mute)
    }
    private func sectionTitle(_ t: String, _ c: Color) -> some View {
        Text(t).font(Brand.label(9)).tracking(0.8).foregroundStyle(c).padding(.top, 4)
    }

    private func questionRow(_ r: Requirement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text("?").font(.system(size: S(13), weight: .heavy, design: .monospaced)).foregroundStyle(Color(hex: 0x1a1200))
                    .frame(width: S(20), height: S(20)).background(RoundedRectangle(cornerRadius: 4).fill(Brand.amber))
                Text(r.text).font(.system(size: S(13), weight: .medium)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            }
            FeatureStrip(board: board, req: r)
            HStack(spacing: 8) {
                ClaudeButton(title: "Make it a choice", prominent: true) {
                    var x = ItemRef(ref: "req:" + r.id)!; x.title = String(r.text.prefix(60)); x.area = r.area
                    model.start(projectId: board.project.id, item: x, intent: .choose)
                }.help("Claude turns this question into a choice with options and mockups on the Choices tab")
                verdictButton(r, "agree", "✓ Fine as is", Brand.green)
                verdictButton(r, "later", "Later", Brand.mute)
                Spacer()
                SessionChip(projectId: board.project.id, ref: "req:" + r.id)
            }
            NoteField(placeholder: "Or answer it here…", initial: board.verdict("req:" + r.id).note) { board.setRequirement(r, pick: "change", note: $0) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.amberDim.opacity(0.45)))
    }

    private func proposalRow(_ r: Requirement) -> some View {
        let v = board.verdict("req:" + r.id).pickString
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.text).font(.system(size: S(12.5))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                FeatureStrip(board: board, req: r)
            }
            Spacer(minLength: 8)
            if v == "change" { Text("you asked a change").font(.system(size: S(10.5))).foregroundStyle(Brand.amber) }
            if v == "later" { Text("later").font(.system(size: S(10.5))).foregroundStyle(Brand.mute) }
            verdictButton(r, "agree", "✓", Brand.green)
            verdictButton(r, "change", "✎", Brand.amber)
            verdictButton(r, "later", "Later", Brand.mute)
        }
        .padding(.vertical, 3)
    }

    private func verdictButton(_ r: Requirement, _ k: String, _ title: String, _ c: Color) -> some View {
        let v = board.verdict("req:" + r.id).pickString
        return Button(title) { board.setRequirement(r, pick: k) }
            .buttonStyle(SteerButton()).font(.system(size: S(11), weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(v == k ? Color.black : c)
            .background(RoundedRectangle(cornerRadius: 5).fill(v == k ? c : .clear))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(c.opacity(0.6)))
            .help(k == "agree" ? "Agree" : k == "change" ? "Ask a change (write it in the chapter session)" : "Decide later")
    }

    private func confirm(_ rs: [Requirement]) {
        board.setRequirements(rs, pick: "agree")
        let ids = rs
        model.showToast("\(rs.count) requirement\(rs.count == 1 ? "" : "s") confirmed in “\(group)”", undo: { [board] in
            board.clearRequirements(ids)
        })
    }

    private func start(_ intent: Intent) {
        var x = ItemRef(ref: "reqs:" + BoardFiles.slug(group))!; x.title = "Requirements: " + group; x.area = items.first?.area
        model.start(projectId: board.project.id, item: x, intent: intent)
    }
}

// MARK: - Roadmap

struct RoadTrackView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let track: String; let items: [RoadItem]
    @State private var consolidating = CommandLine.arguments.contains("--consolidate-open")   // test hook: panels open
    @State private var showArchived = false
    /// Done rows are folded by default (nil = auto: open only when the list shows no open row, e.g. the Done filter).
    @State private var showDone: Bool? = nil
    /// Chapters folded to one line, remembered per project (your focus: what you keep open stays open).
    /// The click flips this view's own state (what redraws the row); ChapterFolds only remembers it. Driving the fold from
    /// outside the view (@AppStorage, then a shared store) saved it but the roadmap list never redrew the row (21 Nov).
    @State private var foldedNow: (on: Bool, rev: Int)? = nil
    /// The item the board was asked to show (⌘K, a link from another tab): its chapter opens, and so does Done or the
    /// archive when the item is in there, so the list can scroll to it.
    let reveal: String?
    init(board: BoardStore, track: String, items: [RoadItem], reveal: String? = nil) {
        self.board = board; self.track = track; self.items = items; self.reveal = reveal
    }
    private var collapsed: Bool {
        let slug = BoardFiles.slug(track)
        if let f = foldedNow, f.rev == ChapterFolds.shared.rev(board.project.id, slug) { return f.on }
        return ChapterFolds.shared.isFolded(board.project.id, slug)
    }
    private func setCollapsed(_ on: Bool) {
        let slug = BoardFiles.slug(track)
        ChapterFolds.shared.set(board.project.id, slug, folded: on)
        foldedNow = (on, ChapterFolds.shared.rev(board.project.id, slug))
    }
    private var revealed: RoadItem? { reveal.flatMap { r in items.first { "road:" + $0.id == r } } }
    @ObservedObject private var snaps = MockSnapshots.shared
    private var info: Chapter? { board.chapters.first { $0.name == track } }
    private func media(_ r: RoadItem) -> FeatureMedia { board.media(road: r, snaps: snaps.version) }
    /// Every row keeps a picture column when any row of the chapter has pictures, so they line up as a grid.
    private var picColumn: Bool { board.roadmap.contains { $0.track == track && !media($0).pics.isEmpty } }
    private static var ctaWidth: CGFloat { S(165) }

    /// Rows that show the same delivery / pictures sit together and show them once.
    private func groups(_ rows: [RoadItem]) -> [[RoadItem]] {
        var order: [String] = [], by: [String: [RoadItem]] = [:], out: [[RoadItem]] = []
        for r in rows {
            let k = media(r).groupKey
            if k.isEmpty { order.append("#" + r.id); by["#" + r.id] = [r]; continue }
            if by[k] == nil { order.append(k) }
            by[k, default: []].append(r)
        }
        for k in order { out.append(by[k]!) }
        return out
    }

    @ViewBuilder private func rowList(_ rows: [RoadItem]) -> some View {
        let slot = picColumn
        // Identity = the ref the board scrolls to ("road:<id>"): see BoardScreen.scroll.
        ForEach(groups(rows), id: \.ref) { g in
            if g.count == 1 { row(g[0], slot: slot).piece() } else { group(g, slot: slot).piece() }
        }
    }

    /// Key results delivered together: one frame, the pictures once in the column, the tests once below.
    @ViewBuilder private func group(_ g: [RoadItem], slot: Bool) -> some View {
        let m = media(g[0])
        let allDone = g.allSatisfy { $0.status == "done" }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(g) { row($0, slot: slot, inGroup: true) }
            FeatureTestLine(board: board, media: m, compact: allDone, shared: g.count)
                .padding(.leading, S(26)).padding(.top, 2).padding(.bottom, 4)
        }
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel2.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.line.opacity(0.8)))
        .overlay(alignment: .topTrailing) {
            if slot {
                FeatureThumbs(board: board, media: m, title: g[0].text, shared: g.count)
                    .padding(.top, 5).padding(.trailing, 6 + Self.ctaWidth + 10)
            }
        }
        .padding(.horizontal, -6)
    }
    private var rolling: Bool { track == RequestLog.fixesChapter }
    /// Rolling chapter: done fixes older than a week are archived (folded away), so it never grows forever.
    private func archived(_ r: RoadItem) -> Bool {
        guard rolling, r.status == "done", let d = r.doneAt else { return false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(d.prefix(10))).map { Date().timeIntervalSince($0) > 7 * 86400 } ?? false
    }
    @State private var selected = Set<String>()

    @ViewBuilder private func consolidatePanel(_ all: [RoadItem]) -> some View {
        let props = board.consolidation(track: track)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CONSOLIDATE").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.amber)
                Text(props.isEmpty ? "The board has no new evidence for this chapter." : "What the board already proves:")
                    .font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                Spacer()
            }
            Text("Checks To test verdicts · commits (21 days) · sessions on this chapter (7 days)" + (LocalAI.ready ? " · Local AI" : ""))
                .font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
            ForEach(props) { p in
                HStack(alignment: .top, spacing: 8) {
                    Toggle("", isOn: Binding(get: { selected.contains(p.id) }, set: { if $0 { selected.insert(p.id) } else { selected.remove(p.id) } }))
                        .toggleStyle(.checkbox).labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(Self.label(p.from)).foregroundStyle(Brand.mute)
                            Image(systemName: "arrow.right").font(.system(size: S(9), weight: .bold)).foregroundStyle(Brand.mute)
                            Text(Self.label(p.to)).foregroundStyle(Self.color(p.to)).fontWeight(.semibold)
                            if p.fromCommit { Pill(text: "from a commit", color: Brand.blue) } else if p.fromSession { Pill(text: "from a session", color: Brand.blue) } else if !p.sure { Pill(text: "likely", color: Brand.blue) }
                        }.font(.system(size: S(11)))
                        Text(p.item).font(.system(size: S(12.5))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                        Text(p.evidence).font(.system(size: S(11))).foregroundStyle(Brand.mute).lineLimit(1)
                    }
                }
            }
            HStack(spacing: 8) {
                if !props.isEmpty {
                    let chosen = props.filter { selected.contains($0.id) }
                    ActionButton(title: "Apply \(chosen.count)", icon: "test", primary: true) {
                        board.applyRoad(chosen); consolidating = false
                        model.showToast("\(chosen.count) key result\(chosen.count == 1 ? "" : "s") updated in “\(track)”")
                    }.disabled(chosen.isEmpty)
                }
                ClaudeButton(title: "Verify the rest with Claude") {
                    var x = ItemRef(ref: "track:" + BoardFiles.slug(track))!; x.title = "Consolidate: " + track; x.area = all.first?.area
                    model.start(projectId: board.project.id, item: x, intent: .consolidate)
                    consolidating = false
                }.help("A Claude session checks git history, code and deploys for each open key result and updates them, with evidence")
                Spacer()
                Button("Close") { consolidating = false }.buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel2))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.amber.opacity(0.4)))
    }

    private static let order = ["done", "review", "wip", "you", "todo"]
    private static func color(_ s: String) -> Color { ["done": Brand.green, "review": Brand.blue, "wip": Brand.amber, "you": Brand.amber][s] ?? Brand.line2 }
    private static func label(_ s: String) -> String { ["done": "done", "review": "in review", "wip": "in progress", "you": "waiting on you", "todo": "to do"][s] ?? s }

    var body: some View {
        let all = board.roadmap.filter { $0.track == track }
        let done = all.filter { $0.status == "done" }.count
        let prog = ChapterProgress(all)
        let ref = "track:" + BoardFiles.slug(track)
        // The scroll id sits on its own anchor, above both shapes of the chapter: each branch carrying the same .id
        // kept the lazy list showing the open card after a fold (21 Nov, "collapse chapter is not working").
        Color.clear.frame(height: 0).id(ref)
        // Several rows of the lazy list, not one card: see ChapterPiece.
        if collapsed { compact(all, prog).flash(ref).padding(.bottom, 10) } else { full(all, done: done, prog) }
    }

    /// The chapter on one line: icon, title, progress, what is moving. Click to open it again.
    @ViewBuilder private func compact(_ all: [RoadItem], _ prog: ChapterProgress) -> some View {
        let open = all.filter { $0.status != "done" }
        let moving = open.filter { ["wip", "review", "you"].contains($0.status) }.count
        // A real button (a tap gesture on the row did not always open it), the session chip beside it, not inside.
        HStack(spacing: 10) {
            Button { setCollapsed(false) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right").font(.system(size: S(9), weight: .bold)).foregroundStyle(Brand.mute)
                    AutoIcon(title: track, size: S(18), tile: true)
                    Text(track).font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(Brand.cream).lineLimit(1)
                    if info?.draft == true { Pill(text: "draft", color: Brand.green) }
                    Spacer(minLength: 8)
                    if moving > 0 { Text("\(moving) moving").font(.system(size: S(11))).foregroundStyle(Brand.amber) }
                    Text(rolling ? "\(open.count) open" : "\(prog.coreDone)/\(prog.core.count) core").font(.system(size: S(11)).monospacedDigit())
                        .foregroundStyle(prog.coreReleased && !rolling ? Brand.green : Brand.mute)
                    ProgressView(value: Double(all.count - open.count), total: Double(max(all.count, 1))).progressViewStyle(.linear).tint(Brand.green).frame(width: S(60))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open this chapter")
            FocusStar(board: board, chapter: track)
            SessionChip(projectId: board.project.id, ref: "track:" + BoardFiles.slug(track))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.line))
    }

    @ViewBuilder private func full(_ all: [RoadItem], done: Int, _ prog: ChapterProgress) -> some View {
            // Header: icon + title + objective get the full width; progress and actions share one line below.
            HStack(alignment: .top, spacing: 12) {
                AutoIcon(title: track, size: S(30), tile: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info?.draft == true ? "NEW CHAPTER · DRAFT" : rolling ? "ROLLING CHAPTER · FIXES FROM YOUR REQUESTS" : "CHAPTER")
                        .font(Brand.label(8.5)).tracking(0.8).foregroundStyle(info?.draft == true ? Brand.green : Brand.mute)
                    Text(track).font(.system(size: S(14.5), weight: .semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    if let o = info?.objective, !o.isEmpty {
                        Text(o).font(.system(size: S(12))).foregroundStyle(Brand.ink.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                    }
                    FeatureStrip(board: board, chapter: track)
                }
                Spacer(minLength: 0)
                FocusStar(board: board, chapter: track)
                Button { setCollapsed(true) } label: {
                    Image(systemName: "chevron.up").font(.system(size: S(10), weight: .bold)).foregroundStyle(Brand.mute)
                        .padding(5).contentShape(Rectangle())
                }.buttonStyle(SteerButton()).help("Fold this chapter to one line (remembered)")
            }
            .piece(.top).flash("track:" + BoardFiles.slug(track))
            HStack(alignment: .center, spacing: 14) {
                okrHeader(prog)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SessionChip(projectId: board.project.id, ref: "track:" + BoardFiles.slug(track))
                if info?.draft != true { actions(all, done: done) }
            }
            .piece()
            if prog.coreReleased && !rolling && info?.draft != true { releasedBanner(prog).piece() }
            if !rolling { kindsPanel(all).piece() }
            if info?.draft == true { draftPanel(all).piece() }
            if consolidating { consolidatePanel(all).task { await board.refreshCommitProposals(force: true) }.piece() }
            // A draft lists what it adds inside its green box; nothing else of it is on the roadmap yet.
            if info?.draft != true {
            Divider().overlay(Brand.line).piece()
            let open = items.filter { $0.status != "done" }
            if rolling || prog.extras.isEmpty {
                rowList(open)
            } else {
                let openCore = open.filter(\.isCore), openExtras = open.filter { !$0.isCore }
                if !openCore.isEmpty {
                    sectionHeader("CORE · \(prog.coreDone)/\(prog.core.count)", color: Brand.cream).piece()
                    rowList(openCore)
                }
                if !openExtras.isEmpty {
                    sectionHeader("EXTRAS · \(prog.extrasDone)/\(prog.extras.count) · TESTS, TUTORIALS, ENHANCEMENTS, LATER", color: Brand.mute).piece()
                    rowList(openExtras.sorted { Self.kindOrder($0.kind) < Self.kindOrder($1.kind) })
                }
            }
            doneSection(all)
            }
            // Footer: closes the frame, then the gap to the next chapter.
            Color.clear.frame(height: 0).piece(.bottom).padding(.bottom, 10)
    }

    /// OKR header: the core is the headline (ring + bar); extras sit below, thinner and quieter, never holding the chapter back.
    @ViewBuilder private func okrHeader(_ p: ChapterProgress) -> some View {
        let released = p.coreReleased
        HStack(alignment: .center, spacing: 12) {
            if !p.extras.isEmpty && !rolling {
                ZStack {
                    Circle().stroke(Brand.line, lineWidth: S(4))
                    Circle().trim(from: 0, to: p.fraction).stroke(Brand.green, style: StrokeStyle(lineWidth: S(4), lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        if released { Image(systemName: "checkmark").font(.system(size: S(13), weight: .heavy)).foregroundStyle(Brand.green) }
                        else { Text("\(p.coreDone)/\(p.core.count)").font(.system(size: S(11.5), weight: .bold).monospacedDigit()).foregroundStyle(Brand.cream) }
                        Text("CORE").font(Brand.label(6.5)).tracking(0.5).foregroundStyle(Brand.mute)
                    }
                }
                .frame(width: S(46), height: S(46))
                .help(released ? "Core released: every core key result is done" : "Core key results done: the chapter's objective is met when this ring is full")
            }
            VStack(alignment: .leading, spacing: 5) {
                progressBar(p.core)
                HStack(spacing: 12) {
                    let label = p.extras.isEmpty || rolling ? "\(p.coreDone)/\(p.core.count) done · \(Int(p.fraction * 100))%"
                                                            : released ? "Core released · 100%" : "Core \(Int(p.fraction * 100))% · \(p.coreDone)/\(p.core.count)"
                    Text(label).font(.system(size: S(11), weight: .semibold).monospacedDigit())
                        .foregroundStyle(released ? Brand.green : Brand.ink)
                    ForEach(Self.order.filter { $0 != "done" }, id: \.self) { st in
                        let n = p.core.filter { $0.status == st }.count
                        if n > 0 {
                            HStack(spacing: 4) {
                                Circle().fill(Self.color(st)).frame(width: 7, height: 7)
                                Text("\(n) \(Self.label(st))").font(.system(size: S(11))).foregroundStyle(Brand.ink.opacity(0.7))
                            }
                        }
                    }
                }
                if !p.extras.isEmpty && !rolling {
                    progressBar(p.extras, height: 3).opacity(0.55).padding(.top, 3)
                    Text("Extras \(p.extrasDone)/\(p.extras.count) · tests, tutorials, enhancements, later: they never hold the chapter back")
                        .font(.system(size: S(10.5))).foregroundStyle(Brand.mute).lineLimit(1)
                }
            }
        }
    }

    /// The moment the objective is met: every core key result is done. Extras left are polish, not debt.
    @ViewBuilder private func releasedBanner(_ p: ChapterProgress) -> some View {
        let left = p.extrasOpen
        HStack(spacing: 10) {
            Image(systemName: "flag.checkered").font(.system(size: S(15), weight: .semibold)).foregroundStyle(Brand.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Core released" + (p.releasedOn.map { " · " + Self.day($0) } ?? ""))
                    .font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(Brand.green)
                Text(left == 0 ? "Objective met. Nothing promised is left." : "Objective met. \(left) extra\(left == 1 ? "" : "s") left to polish, none blocking.")
                    .font(.system(size: S(11))).foregroundStyle(Brand.ink.opacity(0.75))
            }
            Spacer()
            Text("CHAPTER LIVE").font(Brand.label(8)).tracking(0.7).foregroundStyle(Brand.green)
                .padding(.horizontal, 6).padding(.vertical, 3).overlay(RoundedRectangle(cornerRadius: 4).stroke(Brand.green.opacity(0.7)))
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.green.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.green.opacity(0.45)))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    /// Core vs extras: Claude's proposal to keep or undo, or (nothing tagged yet) one button to ask Claude.
    @ViewBuilder private func kindsPanel(_ all: [RoadItem]) -> some View {
        let proposed = all.filter(\.kindProposed)
        if !proposed.isEmpty {
            let extras = proposed.filter { !$0.isCore }.count
            HStack(spacing: 10) {
                Text("CLAUDE TAGGED").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.claude)
                Text("\(proposed.count - extras) core · \(extras) extra\(extras == 1 ? "" : "s") · the bar above already counts them")
                    .font(.system(size: S(11.5))).foregroundStyle(Brand.ink.opacity(0.8)).lineLimit(1)
                Spacer()
                Button { kinds(keep: true) } label: {
                    Text("Keep").font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Color(hex: 0x1a1200))
                        .padding(.horizontal, 10).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 6).fill(Brand.green))
                }.buttonStyle(SteerButton()).help("Keep Claude's tags; right-click any row later to change one")
                Button("Undo") { kinds(keep: false) }.buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                    .help("Drop Claude's tags: back to the guess from the words")
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.claude.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.claude.opacity(0.45)))
        } else if info?.draft != true, all.count >= 3, all.contains(where: { $0.status != "done" }), all.allSatisfy(\.kindGuessed) {
            HStack(spacing: 8) {
                Text("Core vs extras guessed from the words").font(.system(size: S(11))).foregroundStyle(Brand.mute)
                Button {
                    var x = ItemRef(ref: "track:" + BoardFiles.slug(track))!; x.title = "Core vs extras: " + track; x.area = all.first?.area
                    model.start(projectId: board.project.id, item: x, intent: .tag)
                } label: {
                    Text("Tag with Claude").font(.system(size: S(11), weight: .semibold)).foregroundStyle(Brand.claude)
                }.buttonStyle(.plain).pointerStyle(.link)
                    .help("Claude reads the chapter and proposes which key results are core and which are extras; you keep or undo")
                Spacer()
            }
        }
    }

    private func kinds(keep: Bool) {
        let r = SteerifyMCP.call(keep ? "keep_kinds" : "undo_kinds", ["chapter": track], board: board.project.boardDir)
        board.reload()
        model.showToast(r.1 ? r.0 : keep ? "Core vs extras kept for “\(track)”" : "Claude's tags undone for “\(track)”")
    }

    private static func day(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return iso }
        let o = DateFormatter(); o.dateFormat = "d MMM"; return o.string(from: d)
    }

    private func sectionHeader(_ t: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(t).font(Brand.label(8.5)).tracking(0.8).lineLimit(1)
            Rectangle().fill(Brand.line).frame(height: 1)
        }.foregroundStyle(color).padding(.top, 4)
    }

    private static func kindOrder(_ k: String) -> Int { ["core": 0, "test": 1, "tutorial": 2, "enhancement": 3, "later": 4][k] ?? 5 }
    private static func kindColor(_ k: String) -> Color { ["tutorial": Brand.violet, "enhancement": Brand.blue, "test": Brand.ink.opacity(0.7)][k] ?? Brand.mute }

    /// One bar, coloured by status (done first), so the share already done reads at a glance.
    private func progressBar(_ all: [RoadItem], height: CGFloat = 6) -> some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(Self.order, id: \.self) { st in
                    let n = all.filter { $0.status == st }.count
                    if n > 0 {
                        RoundedRectangle(cornerRadius: 2).fill(Self.color(st))
                            .frame(width: max(4, (g.size.width - 8) * CGFloat(n) / CGFloat(max(all.count, 1))))
                    }
                }
            }
        }.frame(height: height)
    }

    @ViewBuilder private func actions(_ all: [RoadItem], done: Int) -> some View {
        let props = board.consolidation(track: track)
        HStack(spacing: 6) {
            Button { consolidating.toggle(); if consolidating { selected = Set(props.filter(\.sure).map(\.id)) } } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checklist").font(.system(size: S(11), weight: .semibold))
                    Text("Consolidate").font(.system(size: S(11.5), weight: .semibold))
                    if !props.isEmpty { Text("\(props.count)").font(.system(size: S(10), weight: .bold)).foregroundStyle(Color(hex: 0x1a1200)).padding(.horizontal, 4).background(Capsule().fill(Brand.amber)) }
                }
                .foregroundStyle(Brand.cream).padding(.horizontal, 9).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.line2))
            }.buttonStyle(SteerButton()).help("Bring this chapter up to date: what the board already proves, then Claude for the rest")
            if done < all.count {
                Button { markAll(all) } label: {
                    Image(systemName: "checkmark.seal").font(.system(size: S(12), weight: .semibold))
                        .foregroundStyle(Brand.green).padding(.horizontal, 8).padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.green.opacity(0.5)))
                }.buttonStyle(SteerButton()).help("Mark chapter done: every key result → done (Undo in the message)")
            }
            ActionButton(title: "Resume", primary: true) {
                var x = ItemRef(ref: "track:" + BoardFiles.slug(track))!; x.title = "Chapter: " + track; x.area = all.first?.area
                model.start(projectId: board.project.id, item: x, intent: .resume)
            }.help("Resume this chapter: Claude reads it, checks the code (state of the art) and picks the next step")
        }
        .fixedSize()
    }

    /// What is already done in the chapter, always shown (the list filter only hides it from the open rows).
    @ViewBuilder private func doneSection(_ all: [RoadItem]) -> some View {
        let doneItems = all.filter { $0.status == "done" }
        let old = doneItems.filter(archived)
        let wanted = revealed.flatMap { $0.status == "done" ? $0 : nil }
        let showArchived = self.showArchived || wanted.map(archived) == true
        let shown = doneItems.filter { showArchived || !archived($0) }
        let showDone = wanted != nil || (self.showDone ?? !items.contains { $0.status != "done" })
        if !doneItems.isEmpty {
            Button { withAnimation(.easeOut(duration: 0.15)) { self.showDone = !showDone } } label: {
                HStack(spacing: 6) {
                    Image(systemName: showDone ? "chevron.down" : "chevron.right").font(.system(size: S(9), weight: .bold))
                    Text("DONE · \(doneItems.count)").font(Brand.label(8.5)).tracking(0.8)
                    Rectangle().fill(Brand.line).frame(height: 1)
                }.foregroundStyle(Brand.green).contentShape(Rectangle())
            }.buttonStyle(.plain).pointerStyle(.link).padding(.top, 4)
                .help(showDone ? "Fold what is done" : "Show what is done")
                .piece()
            if showDone {
                rowList(shown)
                if !old.isEmpty {
                    Button { self.showArchived.toggle() } label: {
                        Text(showArchived ? "Hide archived" : "\(old.count) archived · done more than a week ago")
                            .font(.system(size: S(11))).foregroundStyle(Brand.mute)
                    }.buttonStyle(.plain).pointerStyle(.link).piece()
                }
            }
        }
    }

    @ViewBuilder private func row(_ r: RoadItem, slot: Bool = false, inGroup: Bool = false) -> some View {
        let isDone = r.status == "done"
        let m = media(r)
        HStack(alignment: .top, spacing: 10) {
            Button { set(r, isDone ? "todo" : "done") } label: { statusMark(r.status) }
                .buttonStyle(SteerButton()).padding(.top, isDone ? 1 : 2)
                .help(isDone ? "Done · click to reopen" : "Click: mark as done · right-click: any status")
                .contextMenu { statusMenu(r) }
            let extra = !r.isCore && !rolling
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if extra { kindTag(r) }
                    Text(r.text).font(.system(size: S(isDone || extra ? 11.5 : 12.5))).foregroundStyle(isDone ? Brand.mute : extra ? Brand.ink.opacity(0.7) : Brand.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let f = r.forChapter {
                    Button { model.focusItem(projectId: board.project.id, ref: "track:" + BoardFiles.slug(f)) } label: {
                        Text("↳ \(f)").font(.system(size: S(10.5))).foregroundStyle(Brand.mute).lineLimit(1)
                    }.buttonStyle(.plain).pointerStyle(.link).help("The chapter this fix belongs to")
                }
                if !inGroup { FeatureTestLine(board: board, media: m, compact: isDone).padding(.top, 2) }
            }
            Spacer(minLength: 8)
            if slot {
                if !inGroup && !m.pics.isEmpty { FeatureThumbs(board: board, media: m, title: r.text) }
                else { Color.clear.frame(width: FeatureThumbs.width, height: 1) }
            }
            HStack(spacing: 10) {
            if !isDone && r.status != "todo" {
                Text(Self.label(r.status)).font(.system(size: S(10.5))).foregroundStyle(Self.color(r.status))
            }
            SessionChip(projectId: board.project.id, ref: "road:" + r.id)
            if isDone {
                Menu { statusMenu(r); Divider(); Menu("Kind") { kindMenu(r) } } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(Brand.mute).pointerStyle(.link)
            } else {
                Menu {
                    Button("Check the code, then plan") { start(r, .plan) }
                    Button("Build it") { start(r, .build) }
                    Button("Just look") { start(r, .look) }
                    Divider()
                    Menu("Mark as") { statusMenu(r) }
                    Menu("Kind") { kindMenu(r) }
                } label: { HStack(spacing: 4) { PixelIcon(name: "play", size: 8); Text("Start") } }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: S(11))).pointerStyle(.link)
            }
            }
            .frame(width: slot ? Self.ctaWidth : nil, alignment: .trailing)
        }
        .padding(.vertical, isDone ? 1 : 3)
        .contentShape(Rectangle())
        .contextMenu { Section("Kind") { kindMenu(r) }; Section("Mark as") { statusMenu(r) } }
        .id("road:" + r.id).flash("road:" + r.id)
    }

    private func kindTag(_ r: RoadItem) -> some View {
        Text(r.kind.uppercased()).font(Brand.label(7.5)).tracking(0.5).foregroundStyle(Self.kindColor(r.kind))
            .padding(.horizontal, 4).padding(.vertical, 1.5)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Self.kindColor(r.kind).opacity(0.45)))
            .opacity(r.kindGuessed ? 0.75 : 1)
            .overlay(alignment: .topTrailing) { if r.kindProposed { Circle().fill(Brand.claude).frame(width: 4, height: 4).offset(x: 2, y: -2) } }
            .help(r.kindProposed ? "Proposed by Claude · Keep or Undo on the chapter, or right-click to change"
                  : r.kindGuessed ? "Guessed from the words · right-click to change" : "An extra: it never holds the chapter back · right-click to change")
    }

    @ViewBuilder private func kindMenu(_ r: RoadItem) -> some View {
        ForEach(RoadItem.kinds, id: \.self) { k in
            Button { setKind(r, k) } label: {
                let t = k == "core" ? "Core: needed for the objective" : k == "later" ? "Later: an idea, not promised" : k.capitalized
                if r.kind == k { Label(t + (r.kindGuessed ? " (guessed)" : ""), systemImage: "checkmark") } else { Text(t) }
            }
        }
    }

    private func setKind(_ r: RoadItem, _ k: String) {
        guard k != r.kindTag else { return }
        let before = board.setRoadKind([(r.text, k)])
        model.showToast("“\(r.text.prefix(50))\(r.text.count > 50 ? "…" : "")” → \(k)", undo: { [board] in board.setRoadKind(before) })
    }

    /// A chapter Claude drafted from a feature request: nothing is on the roadmap until you say so.
    @ViewBuilder private func draftPanel(_ all: [RoadItem]) -> some View {
        let reqs = board.requirements.filter { $0.group == track }
        let req = info?.request.flatMap { id in RequestLog.cached(board.project.boardDir).first { $0.id == id } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("DRAFTED BY CLAUDE").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.green)
                if let req { Text("from your request “\(req.short)”").font(.system(size: S(11))).foregroundStyle(Brand.mute).lineLimit(1) }
                Spacer()
            }
            Text("Adds \(all.count) key result\(all.count == 1 ? "" : "s")" + (reqs.isEmpty ? "" : " and \(reqs.count) requirement\(reqs.count == 1 ? "" : "s")") + ", all new:")
                .font(.system(size: S(11.5))).foregroundStyle(Brand.ink.opacity(0.8))
            draftList("KEY RESULTS", all.map { ($0.isCore ? nil : $0.kind, $0.text) })
            if !reqs.isEmpty { draftList("REQUIREMENTS", reqs.map { (nil, $0.text) }) }
            HStack(spacing: 8) {
                Button { decide(true, req) } label: {
                    Text("Add to roadmap").font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Color(hex: 0x1a1200))
                        .padding(.horizontal, 10).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 6).fill(Brand.green))
                }.buttonStyle(SteerButton())
                ClaudeButton(title: "Discuss with Claude") {
                    if let req { model.startRequestSession(projectId: board.project.id, id: req.id) }
                    else { var x = ItemRef(ref: "track:" + BoardFiles.slug(track))!; x.title = "Chapter: " + track; x.area = all.first?.area
                           model.start(projectId: board.project.id, item: x, intent: .look) }
                }.help("Back to the session that drafted it: tell it what to change")
                Spacer()
                Button("Discard") { decide(false, req) }.buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.green.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.green.opacity(0.5)))
    }

    /// What a draft adds, one "+" row each (an extra shows its kind).
    private func draftList(_ title: String, _ rows: [(String?, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Brand.label(8)).tracking(0.8).foregroundStyle(Brand.mute)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("+").font(.system(size: S(12), weight: .bold)).foregroundStyle(Brand.green)
                    if let k = r.0 {
                        Text(k.uppercased()).font(Brand.label(7.5)).tracking(0.5).foregroundStyle(Self.kindColor(k))
                            .padding(.horizontal, 4).padding(.vertical, 1.5)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Self.kindColor(k).opacity(0.45)))
                    }
                    Text(r.1).font(.system(size: S(12))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func decide(_ approve: Bool, _ req: BoardRequest?) {
        let dir = board.project.boardDir, name = track
        let r = SteerifyMCP.call(approve ? "approve_chapter" : "discard_chapter", ["name": name], board: dir)
        if r.1 { model.showToast(r.0); return }
        if let req {
            RequestLog.edit(dir, id: req.id) { x in
                x["status"] = approve ? "approved" : "discarded"
                if approve { x["became"] = Array(NSOrderedSet(array: (x["became"] as? [String] ?? []) + ["track:" + BoardFiles.slug(name)])) }
            }
        }
        board.reload()
        model.showToast(approve ? "“\(name)” is on the roadmap" : "Draft “\(name)” discarded")
    }

    @ViewBuilder private func statusMenu(_ r: RoadItem) -> some View {
        ForEach(["done", "review", "wip", "you", "todo"], id: \.self) { st in
            Button { set(r, st) } label: {
                if r.status == st { Label(Self.label(st).capitalized, systemImage: "checkmark") } else { Text(Self.label(st).capitalized) }
            }
        }
    }

    private func set(_ r: RoadItem, _ st: String) {
        guard st != r.status else { return }
        let before = board.setRoad([(r.text, st)])
        model.showToast("“\(r.text.prefix(50))\(r.text.count > 50 ? "…" : "")” → \(Self.label(st))", undo: { [board] in board.setRoad(before) })
    }

    private func markAll(_ all: [RoadItem]) {
        let open = all.filter { $0.status != "done" }
        let before = board.setRoad(open.map { ($0.text, "done") })
        model.showToast("“\(track)” done · \(open.count) key result\(open.count == 1 ? "" : "s") marked", undo: { [board] in board.setRoad(before) })
    }

    /// Key-result mark: ✓ done, half for in progress, eye for review, ! for waiting on you, empty to do.
    @ViewBuilder private func statusMark(_ s: String) -> some View {
        let c = Self.color(s)
        switch s {
        case "done": Image(systemName: "checkmark.square.fill").foregroundStyle(c)
        case "wip": Image(systemName: "square.lefthalf.filled").foregroundStyle(c)
        case "review": Image(systemName: "eye.square").foregroundStyle(c)
        case "you": Image(systemName: "exclamationmark.square.fill").foregroundStyle(c)
        default: Image(systemName: "square").foregroundStyle(Brand.mute)
        }
    }

    private func start(_ r: RoadItem, _ i: Intent) {
        var x = ItemRef(ref: "road:" + r.id)!; x.title = r.text; x.area = r.area
        model.start(projectId: board.project.id, item: x, intent: i)
    }
}


extension BoardStore {
    /// Latest activity per chapter (ISO or date strings, compared as text): key results' status changes,
    /// deliveries linked to them, sessions started on the chapter or one of its key results.
    func chapterActivity() -> [String: String] { memoized("chapterActivity", durable: true) { computeChapterActivity() } }
    private func computeChapterActivity() -> [String: String] {
        var out: [String: String] = [:]
        func bump(_ t: String, _ s: String?) { if let s, !s.isEmpty, s > out[t] ?? "" { out[t] = s } }
        var trackOf: [String: String] = [:]
        for r in roadmap { trackOf[r.id] = r.track; trackOf[r.text] = r.track; bump(r.track, r.movedAt) }
        for s in ships { for rd in s.roads { if let t = trackOf[rd] ?? trackOf[BoardFiles.slug(rd)] { bump(t, s.updated) } } }
        let bySlug = Dictionary(chapters.map { (BoardFiles.slug($0.name), $0.name) }, uniquingKeysWith: { a, _ in a })
        for l in links {
            if l.item.hasPrefix("track:"), let t = bySlug[String(l.item.dropFirst(6))] { bump(t, l.started) }
            else if l.item.hasPrefix("road:"), let t = trackOf[String(l.item.dropFirst(5))] { bump(t, l.started) }
        }
        return out
    }
}

/// Amber flash on the item ⌘K just opened.
struct Flash: ViewModifier {
    @EnvironmentObject var model: AppModel
    let ref: String
    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.amber.opacity(0.8), lineWidth: 1.5)
            .opacity(model.highlightRef == ref ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: model.highlightRef))
    }
}
extension View { func flash(_ ref: String) -> some View { modifier(Flash(ref: ref)) } }


/// One test of a To test item: the picture first and big (cropped to the feature when the delivery says where),
/// a short title, one line of what you should see, one row of actions (Test it · Looks right · note).
struct TestChapter: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let item: ShipItem
    let index: Int
    let count: Int
    let test: ShipTest
    let feedback: (ok: Bool, note: String)?
    var refine = false
    let openPicture: (String) -> Void
    @State private var focusNote = 0

    var body: some View {
        let ok = feedback?.ok == true
        // To refine counts as feedback even before you write a word (Claude then looks at the picture again).
        let note = feedback?.note ?? ""
        let flagged = refine || !note.isEmpty
        let accent: Color = flagged ? Brand.amber : ok ? Brand.green : Brand.line2
        TestRowFrame(dir: board.project.boardDir, img: test.img, focus: test.img.flatMap { item.focus[$0] }, accent: accent.opacity(ok || flagged ? 0.6 : 1),
                     open: { if let img = test.img { openPicture(img) } }) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: S(12), weight: .heavy, design: .monospaced))
                    .foregroundStyle(ok || flagged ? Color(hex: 0x1a1200) : Brand.cream)
                    .frame(width: S(22), height: S(22))
                    .background(RoundedRectangle(cornerRadius: 6).fill(flagged ? Brand.amber : ok ? Brand.green : Color.black.opacity(0.8)))
                    .help(count > 1 ? "Test \(index + 1) of \(count)" : "")
                Text(test.label).font(.system(size: S(14), weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let c = test.check {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "eye").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                    Text(c).font(.system(size: S(12))).foregroundStyle(Brand.ink.opacity(0.85)).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }.help(c)
            }
            HStack(spacing: 6) {
                // No Test it when the link leads nowhere (an app link Steerify cannot act on): the picture is the test.
                if let u0 = test.url, case let u = TestEnvs.boardFile(u0, board: board.project.boardDir) ?? u0, !TestEnvs.dead(u), let url = URL(string: u) {
                    // A link that does not reach the feature (older deliveries) says so instead of looking like a test.
                    let vague = TestEnvs.generic(u, envs: TestEnvs.load(board.project.boardDir))
                    Button { if url.scheme == "steerify" { model.handle(url) } else { openTestLink(url) } } label: {
                        HStack(spacing: 5) {
                            if vague != nil { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: S(10.5))) }
                            Text(vague == nil ? "Test it" : "Home page only").font(.system(size: S(12.5), weight: .bold))
                            Image(systemName: "arrow.up.right").font(.system(size: S(10.5), weight: .bold))
                        }
                            .lineLimit(1).fixedSize()
                            .foregroundStyle(vague == nil ? .white : Brand.amber).padding(.horizontal, 11).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(vague == nil ? Color(hex: 0x3b6ff5) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(vague == nil ? .clear : Brand.amber.opacity(0.7)))
                    }.buttonStyle(SteerButton()).help(vague.map { "This link opens \($0): \(u)\nSend it back with Refine to get a direct link." } ?? u)
                }
            }
            // The note box is always there and takes the rest of the row: writing a note is one click.
            NoteField(placeholder: flagged ? "What should change? Claude reads it" : "What is off?", initial: note, fill: true,
                      focusTrigger: focusNote, marked: flagged) { board.setTest(item, index: index, note: $0) }
            // Under the note box: Looks right | To refine (request r261122-095541). One or the other, never both.
            TestAnswerPair(ok: ok, refine: flagged,
                           onOK: { board.setTest(item, index: index, ok: !ok) },
                           onRefine: {
                               if flagged && note.isEmpty { board.setTest(item, index: index, refine: false) }
                               else { if !flagged { board.setTest(item, index: index, refine: true) }; focusNote += 1 }
                           }, full: true)
        }
    }
}

/// Over the verdict buttons: every note you left goes to Claude, whatever you press (request r261122-095541).
struct NotesForClaude: View {
    let notes: BoardStore.ShipNotes
    let pick: String?
    var body: some View {
        if !notes.isEmpty {
            let what = pick == "ok" ? "OK + notes: Claude applies them before it releases"
                : pick == nil ? "Claude reads them whether you press OK or Refine"
                : "Claude applies every one of them"
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "text.bubble.fill").font(.system(size: S(11))).foregroundStyle(Brand.amber)
                (Text("\(notes.count) note\(notes.count == 1 ? "" : "s") for Claude").bold().foregroundStyle(Brand.amber)
                 + Text(" · " + notes.summary).foregroundStyle(Brand.ink.opacity(0.85))
                 + Text("\n" + what).foregroundStyle(Brand.mute))
                    .font(.system(size: S(11.5))).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Brand.amber.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.amber.opacity(0.45)))
        }
    }
}

/// Looks right | To refine: the answer to one test, as one segmented pair.
struct TestAnswerPair: View {
    let ok: Bool
    let refine: Bool
    let onOK: () -> Void
    let onRefine: () -> Void
    var full = false
    var body: some View {
        HStack(spacing: 0) {
            seg("Looks right", ok ? "checkmark.circle.fill" : "checkmark.circle", Brand.green, on: ok && !refine, action: onOK)
            Rectangle().fill(Brand.line2).frame(width: 1, height: S(26))
            seg("To refine", refine ? "pencil.circle.fill" : "pencil.circle", Brand.amber, on: refine, action: onRefine)
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(refine ? Brand.amber.opacity(0.8) : ok ? Brand.green.opacity(0.8) : Brand.line2))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .fixedSize(horizontal: !full, vertical: true)
    }
    private func seg(_ t: String, _ icon: String, _ c: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) { Image(systemName: icon); Text(t) }
                .lineLimit(1).fixedSize()
                .font(.system(size: S(12), weight: .semibold))
                .foregroundStyle(on ? Color.black : c)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: full ? .infinity : nil)
                .background(on ? c : .clear)
                .contentShape(Rectangle())
        }.buttonStyle(SteerButton())
    }
}

/// One row of a To test card: the picture on the left (65%, fixed height, cropped to the feature),
/// what to do on the right. Every row has the same height, whatever the picture.
struct TestRowFrame<Side: View>: View {
    let dir: String
    let img: String?
    let focus: CGRect?
    let accent: Color
    let open: () -> Void
    @ViewBuilder let side: Side
    static var height: CGFloat { S(250) }

    var body: some View {
        GeometryReader { g in
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let img {
                        BoardImage(dir: dir, path: img, height: g.size.height, fit: true, focus: focus, onOpen: open)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Color.black)
                            .overlay(Text("No picture for this test").font(.system(size: S(11))).foregroundStyle(Brand.mute))
                    }
                }
                .frame(width: max(0, (g.size.width - 14) * 0.65), height: g.size.height)
                VStack(alignment: .leading, spacing: 8) { side }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(height: Self.height)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel2))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent))
    }
}


/// Text cut to N lines with a "more / less" toggle.
struct ClampedText: View {
    let text: AttributedString
    var lines = 3
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).lineLimit(open ? nil : lines).fixedSize(horizontal: false, vertical: true)
            if text.characters.count > 220 {
                Button(open ? "less" : "more") { open.toggle() }.buttonStyle(.link).pointerStyle(.link).font(.system(size: S(11)))
            }
        }
    }
}


/// ● working · ◐ idle · ! needs you · ○ ended (from Claude Code hooks).
struct SessionStateBadge: View {
    @ObservedObject var session: TerminalSession
    var body: some View {
        let st = session.kind == .claude ? session.status : (session.running ? .working : .ended)
        let c: Color = st == .working ? Brand.green : st == .waiting ? Brand.amber : st == .idle ? Brand.cream : Brand.mute
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7).opacity(st == .idle ? 0.7 : 1)
            Text(session.kind == .claude ? st.label : "shell").font(.system(size: S(11)))
        }.foregroundStyle(c)
    }
}

/// Right-click on a feature-area chip: rename, merge into another, hide; your edits survive every regrouping.
struct AreaMenu {
    let projectId: String
    @MainActor @ViewBuilder func items(key: String, name: String, others: [(key: String, name: String)]) -> some View {
        Button("Rename…") { rename(key: key, name: name) }
        Menu("Merge into") {
            ForEach(others, id: \.key) { o in Button(o.name) { SmartAreaModel.shared.merge(projectId, key, into: o.key) } }
        }
        Button("Hide") { SmartAreaModel.shared.hide(projectId, key) }
        if SmartAreaModel.shared.edits(projectId) != AreaEdits() {
            Divider()
            Button("Undo all my area changes") { SmartAreaModel.shared.resetEdits(projectId) }
        }
    }
    @MainActor private func rename(key: String, name: String) {
        let a = NSAlert()
        a.messageText = "Rename area"
        a.informativeText = "Kept when the areas are regrouped."
        let f = NSTextField(string: name); f.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        a.accessoryView = f
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = f
        if a.runModal() == .alertFirstButtonReturn { SmartAreaModel.shared.rename(projectId, key, to: f.stringValue) }
    }
}

// MARK: - Chapter focus (request r261123-095911)

/// What the filter bar needs to draw the ★ Focus chip.
struct FocusChip { let on: Bool; let count: Int; let chapters: [String]; let toggle: () -> Void }

/// ★ on a chapter header: put it in focus (up to 3, in order: the number is its place) or take it off.
struct FocusStar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let chapter: String
    var body: some View {
        let rank = board.focusRank(chapter)
        Button {
            let on = rank == nil
            board.setFocus(chapter, on: on) { err in
                if let err { model.showToast(err, projectId: board.project.id) }
                else { model.showToast(on ? "★ In focus: “\(chapter)”" : "Out of focus: “\(chapter)”", projectId: board.project.id) }
            }
            if on, board.focus.count >= BoardStore.maxFocus {
                model.showToast("\(BoardStore.maxFocus) chapters are in focus already: take one off first", projectId: board.project.id)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: rank == nil ? "star" : "star.fill").font(.system(size: S(11), weight: .bold))
                if let rank { Text("\(rank)").font(.system(size: S(10.5), weight: .bold)).monospacedDigit() }
            }
            .foregroundStyle(rank == nil ? Brand.mute : Brand.amber)
            .padding(.horizontal, 5).padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(SteerButton())
        .help(rank.map { "In focus (\($0) of \(board.focus.count)): first on the Roadmap, ★ Focus on the tabs · click to take it off" }
              ?? "Put this chapter in focus (up to \(BoardStore.maxFocus)): first on the Roadmap, ★ Focus filter on the tabs")
    }
}

/// Opens a test link. A local page with a query (protos/x.html?v=B) goes to the browser directly: Finder drops the
/// query of a file URL, and the prototype would open on its first variant.
func openTestLink(_ url: URL) {
    if url.isFileURL, url.query != nil, let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) {
        NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
    } else {
        NSWorkspace.shared.open(url)
    }
}
