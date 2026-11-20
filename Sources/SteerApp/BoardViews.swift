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
    /// Label face: monospaced caps, the in-app stand-in for the pixel font.
    static func label(_ size: CGFloat = 10) -> Font { .system(size: S(size), weight: .bold, design: .monospaced) }
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
    @State private var area: String? = nil
    @State private var state: String = {   // test hook: `--show decided` opens that filter
        let a = CommandLine.arguments
        return a.firstIndex(of: "--show").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } ?? "open"
    }()
    @AppStorage(Prefs.testLayout, store: Prefs.store) private var testLayout = "list"

    var body: some View {
        VStack(spacing: 0) {
            // The TabBar lives in ContentView, across the full window (board + sessions).
            if tab != .ready { NextStrip(board: board, openReady: { tab = .ready }).padding(.top, 6).padding(.bottom, 4) }
            if tab == .release {
                ReleaseScreen(board: board)
            } else if tab == .ready {
                ReadyScreen(projectId: board.project.id)
            } else if tab == .task {
                TasksScreen(board: board)
            } else {
            FilterBar(board: board, tab: tab, area: $area, state: $state, counts: counts)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) { list }
                        .padding(12)
                }
                .onChange(of: model.focus) { _, f in
                    guard let f, f.projectId == board.project.id else { return }
                    if f.ref.hasPrefix("test:") { testLayout = "list" }   // a jump to a card opens it in full
                    let kind = String(f.ref.split(separator: ":").first ?? "")
                    if let t = BoardTab(rawValue: kind == "track" ? "road" : kind == "reqs" ? "req" : kind) { tab = t }
                    // After the tab switch (which resets the filter): show everything so the item is in the list.
                    DispatchQueue.main.async { area = nil; state = "all" }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation { proxy.scrollTo(f.ref, anchor: .top) } }
                }
            }
        }
        }
        .background(Brand.bg)
        .onChange(of: tab) { _, _ in state = "open" }
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
            if ships.isEmpty { EmptyBoard(projectId: board.project.id, title: state == "open" ? "NOTHING TO TEST" : "NOTHING HERE", line: "Claude is either working or sleeping.") }
        case .choice:
            ForEach(choices) { DecisionCard(board: board, d: $0).id("choice:" + $0.id).flash("choice:" + $0.id) }
            if choices.isEmpty { EmptyBoard(projectId: board.project.id, title: "NO OPEN CHOICES", line: "You are, briefly, unblocking no one.") }
        case .req:
            ForEach(reqGroups, id: \.self) { g in ReqGroupView(board: board, group: g, items: reqs.filter { $0.group == g }) }
            if reqs.isEmpty { EmptyBoard(projectId: board.project.id, title: "NOTHING TO REVIEW", line: "Every requirement has an answer. Suspicious, but nice.") }
        case .release, .ready, .task:
            EmptyView()
        case .road:
            let allProps = roadTracks.flatMap { board.consolidation(track: $0) }.filter(\.sure)
            if !allProps.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checklist").foregroundStyle(Brand.amber)
                    Text("\(allProps.count) key result\(allProps.count == 1 ? "" : "s") look outdated: their deliveries were already approved or sent back.")
                        .font(.system(size: S(12))).foregroundStyle(Brand.ink)
                    Spacer()
                    ActionButton(title: "Consolidate all", icon: "test", primary: true) {
                        board.applyRoad(allProps); model.showToast("\(allProps.count) key results brought up to date")
                    }
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Brand.amberDim.opacity(0.7)))
            }
            ForEach(roadTracks, id: \.self) { t in RoadTrackView(board: board, track: t, items: road.filter { $0.track == t }) }
                .task { await board.refreshCommitProposals() }
            if road.isEmpty { EmptyBoard(projectId: board.project.id, title: "ROADMAP CLEAR", line: "Either everything is done or nobody wrote it down.") }
        }
    }

    // Filtering (area + state), per tab. Each state is a function so the filter bar can show counts.
    private func inArea(_ a: [String]) -> Bool { area == nil || a.contains(area!) }
    private var ships: [ShipItem] { shipsIn(state) }
    private var choices: [BoardDecision] { choicesIn(state) }
    private var reqs: [Requirement] { reqsIn(state) }
    private var road: [RoadItem] { roadIn(state) }

    func shipsIn(_ st: String) -> [ShipItem] {
        board.ships.filter { s in
            guard inArea([s.area]) else { return false }
            let x = board.shipState(s), pick = board.effectivePick(s)
            switch st {
            case "open": return x == .toTest || x == .retest
            case "refine": return x == .waiting && pick == "refine"
            case "broken": return x == .waiting && pick == "broken"
            case "ok": return x == .ok
            default: return true
            }
        }
    }
    func choicesIn(_ st: String) -> [BoardDecision] {
        board.decisions.filter { d in
            guard inArea(d.areas) else { return false }
            switch st {
            case "open": return !board.isDecided(d) && !board.isParked(d)
            case "decided": return board.isDecided(d)
            case "parked": return board.isParked(d)
            default: return true
            }
        }.reversed()
    }
    func reqsIn(_ st: String) -> [Requirement] {
        board.requirements.filter { r in
            guard inArea([r.area]) else { return false }
            switch st {
            case "open": return board.isOpen(r)
            case "decide": return board.isOpen(r) && r.status == "question"
            case "confirm": return board.isOpen(r) && r.status != "question"
            case "agreed": return board.isConfirmed(r)
            default: return true
            }
        }
    }
    private var reqGroups: [String] { Array(NSOrderedSet(array: reqs.map(\.group)).array as! [String]).reversed() }
    func roadIn(_ st: String) -> [RoadItem] {
        board.roadmap.filter { r in
            guard inArea([r.area]) else { return false }
            switch st {
            case "open": return r.status != "done"
            case "done": return r.status == "done"
            default: return true
            }
        }
    }
    private var roadTracks: [String] {
        let list = Array((NSOrderedSet(array: road.map(\.track)).array as! [String]).reversed())
        let drafts = Set(board.chapters.filter(\.draft).map(\.name))
        return list.filter { drafts.contains($0) } + list.filter { !drafts.contains($0) }
    }

    private func count(_ st: String) -> Int {
        switch tab { case .test: shipsIn(st).count; case .choice: choicesIn(st).count; case .req: reqsIn(st).count; case .road: roadIn(st).count; case .release, .ready, .task: 0 }
    }
    private var counts: [String: Int] {
        Dictionary(uniqueKeysWithValues: FilterBar.states(tab).map { ($0.0, count($0.0)) })
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
        }
        .padding(.horizontal, 8)
        .animation(.easeOut(duration: 0.2), value: model.toast)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }
    /// What needs you: refine/broken + untested on To test, open choices, unreviewed requirements.
    private func badge(_ t: BoardTab) -> Int {
        switch t {
        case .ready: return model.groupedNudges(board.project.id).count
        case .test: return board.ships.filter { [.toTest, .retest].contains(board.shipState($0)) }.count
        case .choice: return board.decisions.filter { !board.isDecided($0) && !board.isParked($0) }.count
        case .req: return board.requirements.filter { $0.status == "question" && board.isOpen($0) }.count
        case .road: return 0
        case .task: return TaskStore.load(board.project.boardDir).runs.filter { $0.status == "done" || $0.status == "noresult" }.count
        case .release: return board.ships.filter { board.shipState($0) == .ok && $0.status != "live" }.count
        }
    }
}

struct FilterBar: View {
    @ObservedObject var board: BoardStore
    let tab: BoardTab
    @Binding var area: String?
    @Binding var state: String
    let counts: [String: Int]

    static func states(_ tab: BoardTab) -> [(String, String)] {
        switch tab {
        case .test: [("open", "To test"), ("refine", "Refine"), ("broken", "Broken"), ("ok", "OK"), ("all", "All")]
        case .choice: [("open", "Open"), ("decided", "Decided"), ("parked", "Parked"), ("all", "All")]
        case .req: [("open", "Open"), ("decide", "To decide"), ("confirm", "To confirm"), ("agreed", "Settled"), ("all", "All")]
        case .road: [("open", "Active"), ("done", "Done"), ("all", "All")]
        case .release, .ready, .task: [("all", "All")]
        }
    }
    private var states: [(String, String)] { Self.states(tab) }

    /// One quiet line (choice board-nav-filters, A): state segments, then the area menu. No box, no labels.
    var body: some View {
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
            if area != nil || state != "open" {
                Button("Clear") { area = nil; state = "open" }.buttonStyle(.link).pointerStyle(.link).font(.system(size: S(11.5)))
            }
            if board.areas.count > 1 {
                Menu {
                    Button("All areas") { area = nil }
                    Divider()
                    ForEach(board.areas, id: \.key) { a in
                        Button { area = a.key } label: { if area == a.key { Label(a.name, systemImage: "checkmark") } else { Text(a.name) } }
                    }
                } label: {
                    Text("Area: " + (board.areas.first { $0.key == area }?.name ?? "All")).font(.system(size: S(12)))
                        .foregroundStyle(area == nil ? Brand.ink : Color(hex: 0xffd27a))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Show one area only")
            }
            if tab == .test { LayoutSwitch() }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
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

/// Note field that saves on Return or when focus leaves.
struct NoteField: View {
    let placeholder: String
    let initial: String
    /// true = take all the height it is given (the note box of a test row), click anywhere to write.
    var fill = false
    let save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    init(placeholder: String, initial: String, fill: Bool = false, save: @escaping (String) -> Void) {
        self.placeholder = placeholder; self.initial = initial; self.fill = fill; self.save = save
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
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.line2, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            .focused($focused)
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
                }
                if item.status != "local" { Pill(text: item.status.replacingOccurrences(of: "-", with: " "), color: item.status == "live" ? Brand.green : Brand.mute) }
                Text("\(board.areaName(item.area)) · v\(item.version)").font(.system(size: S(11))).foregroundStyle(Brand.mute).fixedSize()
                SessionChip(projectId: board.project.id, ref: "test:" + item.id)
            }
            if let prev {
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
                let checked = fb.values.filter { $0.ok || !$0.note.isEmpty }.count
                let notes = fb.values.filter { !$0.note.isEmpty }.count
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        PixelIcon(name: "test", size: 10).foregroundStyle(Brand.blue)
                        Text("TESTS").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.blue)
                        Text("\(checked) of \(item.tests.count) checked").font(.system(size: S(11.5))).foregroundStyle(Brand.ink)
                        if notes > 0 { Text("· \(notes) with feedback").font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.amber) }
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
                                openPicture: { img in
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

            HStack(spacing: 6) {
                verdictButton("ok", "✓ OK", Brand.green, pick)
                verdictButton("refine", "↻ Refine", Brand.amber, pick)
                verdictButton("broken", "✕ Broken", Brand.red, pick)
                Spacer()
                if state == .waiting {
                    ActionButton(title: "Fix my notes", primary: true) { model.start(projectId: board.project.id, item: ref, intent: .fix) }
                }
                if pick == "ok" && item.status != "live" {
                    ActionButton(title: "Release", icon: "ship", primary: true) { model.start(projectId: board.project.id, item: ref, intent: .release) }
                }
                ClaudeButton(title: "Open with Claude") { model.start(projectId: board.project.id, item: ref, intent: .look) }
            }
            NoteField(placeholder: "Note for Claude (what to change)…", initial: board.shipNote(item)) { board.setShip(item, pick: pick ?? "refine", note: $0) }
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
        if fb.values.contains(where: { !$0.note.isEmpty }) { return "refine" }
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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "eye").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                Text(checkLine).font(.system(size: S(11.5))).foregroundStyle(Brand.ink.opacity(0.85)).lineLimit(2, reservesSpace: true)
            }
            HStack(spacing: 6) {
                verdict("ok", "✓ OK", Brand.green, pick)
                verdict("refine", "↻ Refine", Brand.amber, pick)
                verdict("broken", "✕ Broken", Brand.red, pick)
            }
            if !board.shipNote(item).isEmpty {
                Text("“\(board.shipNote(item))”").font(.system(size: S(11))).foregroundStyle(Brand.amber).lineLimit(1)
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
                if let u = test.url, let url = URL(string: u) {
                    Button(test.label) { if url.scheme == "steerify" { model.handle(url) } else { NSWorkspace.shared.open(url) } }
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
            Text(r.text).font(.system(size: S(12.5))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
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
    @State private var showDone = true
    private var info: Chapter? { board.chapters.first { $0.name == track } }
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
            ForEach(props) { p in
                HStack(alignment: .top, spacing: 8) {
                    Toggle("", isOn: Binding(get: { selected.contains(p.id) }, set: { if $0 { selected.insert(p.id) } else { selected.remove(p.id) } }))
                        .toggleStyle(.checkbox).labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(Self.label(p.from)).foregroundStyle(Brand.mute)
                            Image(systemName: "arrow.right").font(.system(size: S(9), weight: .bold)).foregroundStyle(Brand.mute)
                            Text(Self.label(p.to)).foregroundStyle(Self.color(p.to)).fontWeight(.semibold)
                            if p.fromCommit { Pill(text: "from a commit", color: Brand.blue) } else if !p.sure { Pill(text: "likely", color: Brand.blue) }
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
        let pct = all.isEmpty ? 0 : Double(done) / Double(all.count)
        Card {
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
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    progressBar(all)
                    HStack(spacing: 12) {
                        Text("\(done)/\(all.count) done · \(Int(pct * 100))%").font(.system(size: S(11), weight: .semibold).monospacedDigit())
                            .foregroundStyle(done == all.count && !all.isEmpty ? Brand.green : Brand.ink)
                        ForEach(Self.order.filter { $0 != "done" }, id: \.self) { st in
                            let n = all.filter { $0.status == st }.count
                            if n > 0 {
                                HStack(spacing: 4) {
                                    Circle().fill(Self.color(st)).frame(width: 7, height: 7)
                                    Text("\(n) \(Self.label(st))").font(.system(size: S(11))).foregroundStyle(Brand.ink.opacity(0.7))
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SessionChip(projectId: board.project.id, ref: "track:" + BoardFiles.slug(track))
                if info?.draft != true { actions(all, done: done) }
            }
            if info?.draft == true { draftPanel(all) }
            if consolidating { consolidatePanel(all).task { await board.refreshCommitProposals(force: true) } }
            Divider().overlay(Brand.line)
            let open = items.filter { $0.status != "done" }
            ForEach(open) { row($0) }
            doneSection(all)
        }
        .id("track:" + BoardFiles.slug(track)).flash("track:" + BoardFiles.slug(track))
    }

    /// One bar, coloured by status (done first), so the share already done reads at a glance.
    private func progressBar(_ all: [RoadItem]) -> some View {
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
        }.frame(height: 6)
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
        let shown = doneItems.filter { showArchived || !archived($0) }
        if !doneItems.isEmpty {
            Button { withAnimation(.easeOut(duration: 0.15)) { showDone.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: showDone ? "chevron.down" : "chevron.right").font(.system(size: S(9), weight: .bold))
                    Text("DONE · \(doneItems.count)").font(Brand.label(8.5)).tracking(0.8)
                    Rectangle().fill(Brand.line).frame(height: 1)
                }.foregroundStyle(Brand.green).contentShape(Rectangle())
            }.buttonStyle(.plain).pointerStyle(.link).padding(.top, 4)
                .help(showDone ? "Fold what is done" : "Show what is done")
            if showDone {
                ForEach(shown) { row($0) }
                if !old.isEmpty {
                    Button { showArchived.toggle() } label: {
                        Text(showArchived ? "Hide archived" : "\(old.count) archived · done more than a week ago")
                            .font(.system(size: S(11))).foregroundStyle(Brand.mute)
                    }.buttonStyle(.plain).pointerStyle(.link)
                }
            }
        }
    }

    @ViewBuilder private func row(_ r: RoadItem) -> some View {
        let isDone = r.status == "done"
        HStack(alignment: .top, spacing: 10) {
            Button { set(r, isDone ? "todo" : "done") } label: { statusMark(r.status) }
                .buttonStyle(SteerButton()).padding(.top, isDone ? 1 : 2)
                .help(isDone ? "Done · click to reopen" : "Click: mark as done · right-click: any status")
                .contextMenu { statusMenu(r) }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.text).font(.system(size: S(isDone ? 11.5 : 12.5))).foregroundStyle(isDone ? Brand.mute : Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let f = r.forChapter {
                    Button { model.focusItem(projectId: board.project.id, ref: "track:" + BoardFiles.slug(f)) } label: {
                        Text("↳ \(f)").font(.system(size: S(10.5))).foregroundStyle(Brand.mute).lineLimit(1)
                    }.buttonStyle(.plain).pointerStyle(.link).help("The chapter this fix belongs to")
                }
            }
            Spacer(minLength: 8)
            if !isDone && r.status != "todo" {
                Text(Self.label(r.status)).font(.system(size: S(10.5))).foregroundStyle(Self.color(r.status))
            }
            SessionChip(projectId: board.project.id, ref: "road:" + r.id)
            if isDone {
                Menu { statusMenu(r) } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(Brand.mute).pointerStyle(.link)
            } else {
                Menu {
                    Button("Check the code, then plan") { start(r, .plan) }
                    Button("Build it") { start(r, .build) }
                    Button("Just look") { start(r, .look) }
                    Divider()
                    Menu("Mark as") { statusMenu(r) }
                } label: { HStack(spacing: 4) { PixelIcon(name: "play", size: 8); Text("Start") } }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: S(11))).pointerStyle(.link)
            }
        }
        .padding(.vertical, isDone ? 1 : 3)
        .id("road:" + r.id).flash("road:" + r.id)
    }

    /// A chapter Claude drafted from a feature request: nothing is on the roadmap until you say so.
    @ViewBuilder private func draftPanel(_ all: [RoadItem]) -> some View {
        let reqs = board.requirements.filter { $0.group == track }
        let req = info?.request.flatMap { id in RequestLog.load(board.project.boardDir).first { $0.id == id } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("DRAFTED BY CLAUDE").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.green)
                if let req { Text("from your request “\(req.short)”").font(.system(size: S(11))).foregroundStyle(Brand.mute).lineLimit(1) }
                Spacer()
            }
            Text("\(all.count) key results · \(reqs.count) requirements proposed" + (reqs.isEmpty ? "" : " (Requirements tab)"))
                .font(.system(size: S(11.5))).foregroundStyle(Brand.blue)
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
    let openPicture: (String) -> Void

    var body: some View {
        let ok = feedback?.ok == true
        let note = feedback?.note ?? ""
        let accent: Color = !note.isEmpty ? Brand.amber : ok ? Brand.green : Brand.line2
        TestRowFrame(dir: board.project.boardDir, img: test.img, focus: test.img.flatMap { item.focus[$0] }, accent: accent.opacity(ok || !note.isEmpty ? 0.6 : 1),
                     open: { if let img = test.img { openPicture(img) } }) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: S(12), weight: .heavy, design: .monospaced))
                    .foregroundStyle(ok || !note.isEmpty ? Color(hex: 0x1a1200) : Brand.cream)
                    .frame(width: S(22), height: S(22))
                    .background(RoundedRectangle(cornerRadius: 6).fill(ok ? Brand.green : !note.isEmpty ? Brand.amber : Color.black.opacity(0.8)))
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
                if let u = test.url, let url = URL(string: u) {
                    // A link that does not reach the feature (older deliveries) says so instead of looking like a test.
                    let vague = TestEnvs.generic(u, envs: TestEnvs.load(board.project.boardDir))
                    Button { if url.scheme == "steerify" { model.handle(url) } else { NSWorkspace.shared.open(url) } } label: {
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
                Button { board.setTest(item, index: index, ok: !ok) } label: {
                    HStack(spacing: 5) { Image(systemName: ok ? "checkmark.circle.fill" : "checkmark.circle"); Text("Looks right") }
                        .lineLimit(1).fixedSize()
                        .font(.system(size: S(12), weight: .semibold))
                        .foregroundStyle(ok ? Color.black : Brand.green)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(ok ? Brand.green : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.green.opacity(0.7)))
                }.buttonStyle(SteerButton())
            }
            // The note box is always there and takes the rest of the row: writing a note is one click.
            NoteField(placeholder: "What is off?", initial: note, fill: true) { board.setTest(item, index: index, note: $0) }
        }
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
