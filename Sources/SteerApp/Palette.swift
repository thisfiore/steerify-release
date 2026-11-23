import SwiftUI
import AppKit

// MARK: - ⌘K: one search over everything Steerify knows
//
// Sessions, To test, Choices, Requirements, Roadmap items, Chapters, Requests, past conversations,
// projects and commands. Results are grouped by kind, the words you typed are lit, and the row you
// are on is shown in full on the right. Tab narrows to one kind.

/// What a hit is. The order here is the order of the sections when nothing ranks higher.
enum PaletteKind: String, CaseIterable {
    case session, test, choice, req, road, chapter, request, talk, project, action

    var label: String {
        switch self {
        case .session: "Session"; case .test: "To test"; case .choice: "Choice"; case .req: "Requirement"
        case .road: "Roadmap"; case .chapter: "Chapter"; case .request: "Request"; case .talk: "Conversation"
        case .project: "Project"; case .action: "Command"
        }
    }
    var plural: String {
        switch self {
        case .session: "Sessions"; case .test: "To test"; case .choice: "Choices"; case .req: "Requirements"
        case .road: "Roadmap"; case .chapter: "Chapters"; case .request: "Requests"; case .talk: "Conversations"
        case .project: "Projects"; case .action: "Commands"
        }
    }
    var color: Color {
        switch self {
        case .session: Brand.claude; case .test: Brand.blue; case .choice: Brand.amber; case .req: Color(hex: 0xc4a7ff)
        case .road, .chapter: Brand.green; case .request: Brand.cream; case .talk: Brand.claude.opacity(0.8)
        case .project: Brand.cream; case .action: Brand.mute
        }
    }
    /// Pixel icon name, or an SF Symbol when prefixed with "sf:".
    var icon: String {
        switch self {
        case .session: "term"; case .test: "test"; case .choice: "choice"; case .req: "req"; case .road: "road"
        case .chapter: "sf:books.vertical.fill"; case .request: "sf:tray.and.arrow.down.fill"
        case .talk: "sf:arrow.uturn.backward"; case .project: "sf:square.grid.2x2.fill"; case .action: "sf:command"
        }
    }
}

/// The chips under the search field. Tab / ⇧Tab moves between them.
enum PaletteScope: String, CaseIterable {
    case all, sessions, test, choice, req, road, request, action

    var title: String {
        switch self {
        case .all: "All"; case .sessions: "Sessions"; case .test: "To test"; case .choice: "Choices"
        case .req: "Requirements"; case .road: "Roadmap"; case .request: "Requests"; case .action: "Commands"
        }
    }
    var kinds: [PaletteKind] {
        switch self {
        case .all: PaletteKind.allCases
        case .sessions: [.session, .talk]; case .test: [.test]; case .choice: [.choice]; case .req: [.req]
        case .road: [.chapter, .road]; case .request: [.request]; case .action: [.action, .project]
        }
    }
    var color: Color { self == .all ? Brand.cream : kinds[0].color }
}

struct PaletteFact: Hashable { let label: String; let value: String }
/// One line of the preview's list (a choice's options, a test's checks, a chapter's items).
struct PaletteLine: Hashable { let mark: String; let text: String; let on: Bool }

struct PaletteHit: Identifiable {
    let id: String
    let kind: PaletteKind
    let projectId: String
    let projectName: String
    var ref: String? = nil                 // board item ("test:<id>"…)
    var sessionId: UUID? = nil             // live session
    var link: SessionLink? = nil           // past conversation
    var run: (@MainActor (AppModel) -> Void)? = nil   // command
    let title: String
    let context: String                    // chapter, area, repo…
    let state: String
    let stateColor: Color
    let rank: Int                          // lower = more urgent
    var body: String = ""                  // the text behind it (what, why, objective…)
    var image: String? = nil               // relative to the board folder
    var boardDir: String = ""
    var facts: [PaletteFact] = []
    var lines: [PaletteLine] = []
    var linesTitle: String = ""
    var progress: (done: Int, total: Int)? = nil
    var shortcut: String? = nil
    /// Search keys, made once when the index is built (never per keystroke).
    var titleKey: String = ""
    var hay: String = ""
}

@MainActor
enum PaletteIndex {
    static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    /// Letters and digits only: "Cash Flow", "cash-flow" and "cashflow" all read "cashflow".
    static func squash(_ s: String) -> String { String(String.UnicodeScalarView(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })) }
    private static func keyed(_ h: PaletteHit, _ extra: String) -> PaletteHit {
        var h = h
        h.titleKey = squash(fold(h.title))
        h.hay = squash(fold([h.title, h.context, h.kind.label, h.kind.plural, h.state, h.body, extra].joined(separator: " ")))
        return h
    }

    static func ago(_ iso: String) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        guard let d = f.date(from: iso) ?? g.date(from: iso) else { return "" }
        let m = Int(-d.timeIntervalSinceNow / 60)
        return m < 1 ? "now" : m < 60 ? "\(m) min ago" : m < 1440 ? "\(m / 60) h ago" : "\(m / 1440) d ago"
    }

    static func build(_ model: AppModel) -> [PaletteHit] {
        var out: [PaletteHit] = []
        for p in model.projects {
            let b = model.board(for: p)
            let live = model.sessions(of: p.id)

            for s in live {
                let h = PaletteHit(id: "s:\(s.id)", kind: .session, projectId: p.id, projectName: p.name, ref: s.item?.ref, sessionId: s.id,
                                   title: s.title, context: "\(s.repo.name) · \(s.kind == .claude ? "Claude Code" : "shell")",
                                   state: s.moodWord, stateColor: s.moodColor, rank: s.status == .waiting ? 0 : 1,
                                   facts: [PaletteFact(label: "Repo", value: s.repo.name), PaletteFact(label: "Works on", value: s.item?.title ?? s.item?.ref ?? "nothing tied")])
                out.append(keyed(h, s.item?.ref ?? ""))
            }

            for s in b.ships {
                let st = b.shipState(s)
                let (word, color, rank): (String, Color, Int) = switch st {
                case .toTest: ("to test", Brand.blue, 1); case .retest: ("re-test", Brand.blue, 1)
                case .waiting: ("waiting", Brand.amber, 4); case .ok: (s.status == "live" ? "live" : "ok", Brand.green, 6)
                case .afterRelease: ("after release", Brand.amber, 5)
                }
                let h = PaletteHit(id: "test:\(p.id):\(s.id)", kind: .test, projectId: p.id, projectName: p.name, ref: "test:" + s.id,
                                   title: s.title, context: "\(b.areaName(s.area)) · v\(s.version)", state: word, stateColor: color, rank: rank,
                                   body: s.what, image: s.shots.first?.img ?? s.tests.compactMap(\.img).first, boardDir: p.boardDir,
                                   facts: [PaletteFact(label: "Status", value: s.status.replacingOccurrences(of: "-", with: " ")),
                                           PaletteFact(label: "Updated", value: s.updated.map(ago) ?? "")].filter { !$0.value.isEmpty },
                                   lines: s.tests.prefix(6).map { PaletteLine(mark: "□", text: $0.label, on: false) }, linesTitle: "\(s.tests.count) to check")
                out.append(keyed(h, "\(s.id) \(s.area) \(s.tests.map(\.label).joined(separator: " "))"))
            }

            // Chapters by the request they came from, so a choice "From request r…" is found by its chapter's words.
            let chapterOf = Dictionary(b.chapters.compactMap { c in c.request.map { ($0, c.name + " " + (c.objective ?? "")) } }, uniquingKeysWith: { $0 + " " + $1 })
            for d in b.decisions {
                let why = BoardText.plain(d.why).replacingOccurrences(of: "**", with: "")
                let decided = b.isDecided(d), parked = b.isParked(d)
                let v = b.verdict(d.id)
                let picked = Set((v.pick as? [String]) ?? [v.pickString].compactMap { $0 }).union(b.mix(d))
                let fromChapter = chapterOf.keys.filter { why.contains($0) }.compactMap { chapterOf[$0] }.joined(separator: " ")
                let h = PaletteHit(id: "choice:\(p.id):\(d.id)", kind: .choice, projectId: p.id, projectName: p.name, ref: "choice:" + d.id,
                                   title: d.title, context: d.areas.map(b.areaName).joined(separator: ", "),
                                   state: parked ? "parked" : decided ? "decided" : "open", stateColor: decided ? Brand.green : parked ? Brand.mute : Brand.amber,
                                   rank: decided ? 6 : parked ? 8 : 2, body: why,
                                   image: d.gallery.first?.img ?? d.options.compactMap(\.shot).first, boardDir: p.boardDir,
                                   facts: v.note.isEmpty ? [] : [PaletteFact(label: "Your note", value: v.note)],
                                   lines: d.options.map { PaletteLine(mark: picked.contains($0.id) ? "✓" : $0.rec ? "★" : "·", text: $0.label, on: picked.contains($0.id)) },
                                   linesTitle: decided ? "Your pick" : "\(d.options.count) options")
                out.append(keyed(h, "\(d.id) \(d.tags.joined(separator: " ")) \(d.options.map { $0.label + " " + $0.points.joined(separator: " ") }.joined(separator: " ")) \(fromChapter)"))
            }

            for r in b.requirements {
                let settled = r.status == "agreed" || r.status == "rule"
                let h = PaletteHit(id: "req:\(p.id):\(r.id)", kind: .req, projectId: p.id, projectName: p.name, ref: "req:" + r.id,
                                   title: r.text, context: r.group, state: r.status, stateColor: settled ? Brand.green : r.status == "question" ? Brand.amber : Brand.blue,
                                   rank: r.status == "question" && b.isOpen(r) ? 3 : 7,
                                   facts: [PaletteFact(label: "Group", value: r.group), PaletteFact(label: "Source", value: r.src ?? "")].filter { !$0.value.isEmpty })
                out.append(keyed(h, r.id))
            }

            for c in b.chapters {
                let items = b.roadmap.filter { $0.track == c.name }
                let wip = items.contains { $0.status == "wip" }
                let cp = ChapterProgress(items), done = cp.coreDone
                let all = cp.coreReleased     // core released = the chapter is done
                let h = PaletteHit(id: "track:\(p.id):\(c.name)", kind: .chapter, projectId: p.id, projectName: p.name, ref: "track:" + BoardFiles.slug(c.name),
                                   title: c.name, context: b.areaName(c.area), state: c.draft ? "draft" : all ? "done" : wip ? "wip" : "todo",
                                   stateColor: c.draft ? Brand.blue : all ? Brand.green : wip ? Brand.amber : Brand.mute, rank: wip ? 3 : all ? 9 : 5,
                                   body: c.objective ?? "",
                                   lines: items.prefix(7).map { PaletteLine(mark: $0.status == "done" ? "✓" : $0.status == "wip" ? "▸" : "·", text: $0.text, on: $0.status == "wip") },
                                   linesTitle: items.count > 7 ? "First 7 of \(items.count)" : "Items", progress: (done, cp.core.count))
                out.append(keyed(h, "track"))
            }

            for r in b.roadmap {
                let h = PaletteHit(id: "road:\(p.id):\(r.track):\(r.id)", kind: .road, projectId: p.id, projectName: p.name, ref: "road:" + r.id,
                                   title: r.text, context: r.track, state: r.status,
                                   stateColor: r.status == "done" ? Brand.green : r.status == "wip" ? Brand.amber : r.status == "review" ? Brand.blue : Brand.mute,
                                   rank: r.status == "wip" ? 3 : r.status == "done" ? 9 : 5,
                                   facts: [PaletteFact(label: "Chapter", value: r.track), PaletteFact(label: "Done", value: r.doneAt.map(ago) ?? "")].filter { !$0.value.isEmpty })
                out.append(keyed(h, ""))
            }

            for q in RequestLog.load(p.boardDir) {
                let open = !["done", "approved", "discarded"].contains(q.status)
                let h = PaletteHit(id: "request:\(p.id):\(q.id)", kind: .request, projectId: p.id, projectName: p.name, ref: q.became.first ?? "request:" + q.id,
                                   title: q.short, context: "\(q.kind.label)\(q.fromPhone ? " · iPhone" : "") · \(ago(q.at))", state: q.status, stateColor: open ? q.kind.color : Brand.mute,
                                   rank: open ? 4 : 8, body: [q.text, q.note.map { "Claude: " + $0 } ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                                   image: q.imgs.first, boardDir: p.boardDir,
                                   facts: [PaletteFact(label: "About", value: q.chapter ?? q.contextTitle ?? ""),
                                           PaletteFact(label: "Became", value: q.became.joined(separator: ", "))].filter { !$0.value.isEmpty })
                out.append(keyed(h, q.id))
            }

            // Past conversations that are not open now: one per Claude session, latest 40.
            var seen = Set(live.compactMap(\.claudeId))
            for l in b.links.reversed() where !seen.contains(l.claudeSession) {
                seen.insert(l.claudeSession)
                if seen.count > 40 + live.count { break }
                let h = PaletteHit(id: "talk:\(p.id):\(l.claudeSession)", kind: .talk, projectId: p.id, projectName: p.name, ref: l.item, link: l,
                                   title: l.title ?? l.item, context: "\(l.intent) · \(l.repo) · \(ago(l.started))", state: "resume", stateColor: Brand.cream, rank: 8,
                                   facts: [PaletteFact(label: "About", value: l.item), PaletteFact(label: "Repo", value: l.repo), PaletteFact(label: "Started", value: ago(l.started))])
                out.append(keyed(h, "\(l.item) resume conversation"))
            }

            if p.id != model.selectedProjectId {
                let open = b.decisions.filter { !b.isDecided($0) && !b.isParked($0) }.count
                let toTest = b.ships.filter { [.toTest, .retest].contains(b.shipState($0)) }.count
                let h = PaletteHit(id: "project:\(p.id)", kind: .project, projectId: p.id, projectName: p.name,
                                   run: { $0.selectedProjectId = p.id },
                                   title: "Switch to \(p.name)", context: "\(toTest) to test · \(open) choices · \(live.count) sessions",
                                   state: "project", stateColor: Brand.cream, rank: 9, body: b.goal)
                out.append(keyed(h, "switch project \(p.id)"))
            }
        }
        out += commands(model)
        return out
    }

    /// Everything the menus do, findable by name.
    static func commands(_ model: AppModel) -> [PaletteHit] {
        let pid = model.selectedProjectId ?? "", pname = model.project?.name ?? ""
        func cmd(_ id: String, _ title: String, _ about: String, _ key: String?, _ words: String = "", _ run: @escaping @MainActor (AppModel) -> Void) -> PaletteHit {
            keyed(PaletteHit(id: "cmd:" + id, kind: .action, projectId: pid, projectName: pname, run: run, title: title, context: about,
                             state: key ?? "", stateColor: Brand.cream, rank: 9, body: about, shortcut: key), words)
        }
        func tab(_ t: BoardTab, _ n: Int) -> PaletteHit {
            cmd("tab-" + t.rawValue, "Go to \(t.title.capitalized)", "Board tab", "⌘\(n)", "tab show") { _ in Prefs.store.set(t.rawValue, forKey: Prefs.boardTab) }
        }
        return [
            cmd("request", "New request", "A fix, a refinement, a feature or a question: Steerify files it in the right place", "⌘N", "add ask idea bug") { $0.requestOpen = true },
            cmd("next", "Next thing for you", "Jump to the item that waits on you", "⌘J", "jump waiting") { $0.jumpNext() },
            cmd("claude", "New Claude session", "A free Claude Code session in this project", nil, "terminal start open") { _ = $0.newSession(.claude) },
            cmd("shell", "New shell", "A plain terminal in this project", nil, "terminal zsh") { _ = $0.newSession(.shell) },
            cmd("layout", "Sessions: tabs on top / list beside", "Switch how sessions are laid out", "⌘B", "toggle sidebar panel") { _ in
                let cur = SessionLayout(rawValue: Prefs.store.string(forKey: "sessionLayout") ?? "") ?? .list
                Prefs.store.set((cur == .tabs ? SessionLayout.list : .tabs).rawValue, forKey: "sessionLayout")
            },
            cmd("reload", "Reload board", "Read the board files again", "⌘R", "refresh") { $0.reloadBoard() },
            cmd("add", "Add project…", "Open another steered workspace", "⇧⌘O", "workspace folder") { $0.addWorkspace() },
            cmd("recipe", "New project from a recipe…", "A guided start for one build of the book AI Traction", nil, "recipe book template starter guided") { $0.recipesOpen = true },
            cmd("demo", "Try the demo project", "Tiny Todo: a small todo app with a real board", nil, "example sample tutorial") { $0.openDemo() },
            cmd("settings", "Settings…", "Text size, sessions, shortcuts", "⌘,", "preferences") { _ in NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) },
        ] + BoardTab.allCases.enumerated().map { tab($1, $0 + 1) }
    }

    static func words(_ q: String) -> [String] { fold(q).split(separator: " ").map { squash(String($0)) }.filter { !$0.isEmpty } }

    /// Every word must appear somewhere in the item (spaces and punctuation ignored).
    /// Best first: title matches, then the current project, then what is most urgent.
    static func search(_ all: [PaletteHit], _ q: String, current: String?) -> [PaletteHit] {
        let ws = words(q)
        if ws.isEmpty {
            return all.sorted { ($0.projectId == current ? 0 : 1, $0.rank) < ($1.projectId == current ? 0 : 1, $1.rank) }
        }
        let hits: [(PaletteHit, Int)] = all.compactMap { h in
            guard ws.allSatisfy({ h.hay.contains($0) }) else { return nil }
            let inTitle = ws.allSatisfy { h.titleKey.contains($0) }
            let score = (inTitle ? (h.titleKey.hasPrefix(ws[0]) ? 0 : 1) : 3) * 100 + (h.projectId == current ? 0 : 20) + h.rank
            return (h, score)
        }
        return hits.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// The title with the typed words lit.
    static func lit(_ text: String, _ query: String, base: Color, hi: Color = Brand.amber) -> AttributedString {
        var a = AttributedString(text)
        a.foregroundColor = base
        for w in fold(query).split(separator: " ") where w.count > 1 {
            var from = a.startIndex
            while from < a.endIndex, let r = a[from...].range(of: String(w), options: [.caseInsensitive, .diacriticInsensitive]) {
                a[r].foregroundColor = hi
                from = r.upperBound
            }
        }
        return a
    }

    /// A short piece of the body around the first typed word, when the title does not show the match.
    static func snippet(_ h: PaletteHit, _ query: String) -> String? {
        guard !h.body.isEmpty, let w = fold(query).split(separator: " ").first(where: { $0.count > 1 }).map(String.init) else { return nil }
        if h.title.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return nil }
        let flat = h.body.replacingOccurrences(of: "\n", with: " ")
        guard let r = flat.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let start = flat.index(r.lowerBound, offsetBy: -28, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(r.upperBound, offsetBy: 60, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end].trimmingCharacters(in: .whitespaces) + (end < flat.endIndex ? "…" : "")
    }
}

// MARK: - View

private enum PaletteRow: Identifiable {
    case header(PaletteKind, Int)
    case hit(PaletteHit, Int)            // index among selectable rows
    case more(PaletteKind, Int)
    var id: String {
        switch self { case .header(let k, _): "h:" + k.rawValue; case .hit(let h, _): h.id; case .more(let k, _): "m:" + k.rawValue }
    }
}

/// ⌘K. ↩ opens (item on the board + its session), ⌘↩ starts a session, Tab narrows to one kind, Esc closes.
struct PaletteView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var scope: PaletteScope = .all
    @State private var index: [PaletteHit] = []
    @State private var matched: [PaletteHit] = []      // every match of the query, any kind
    @State private var rows: [PaletteRow] = []
    @State private var flat: [PaletteHit] = []         // selectable rows, in order
    @State private var sel = 0
    @State private var byKey = false                   // only keyboard moves scroll the list (hover must not)
    @FocusState private var focused: Bool

    private var selected: PaletteHit? { flat[safe: sel] }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { close() }
                VStack(spacing: 0) {
                    field
                    chips
                    Divider().overlay(Brand.line)
                    HStack(spacing: 0) {
                        list.frame(maxWidth: .infinity)
                        Divider().overlay(Brand.line)
                        preview.frame(width: min(S(360), geo.size.width * 0.34))
                    }
                    .frame(height: min(S(470), geo.size.height - S(230)))
                    Divider().overlay(Brand.line)
                    footer
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x101216)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.line2))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.7), radius: 40, y: 16)
                .frame(width: min(S(940), geo.size.width - 60))
                .padding(.top, max(40, geo.size.height * 0.09))
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            index = PaletteIndex.build(model)
            query = model.paletteSeed; model.paletteSeed = ""
            if let i = CommandLine.arguments.firstIndex(of: "--palette-scope"), i + 1 < CommandLine.arguments.count,
               let s = PaletteScope(rawValue: CommandLine.arguments[i + 1]) { scope = s }      // test hook
            refresh(); grabFocus()
        }
        .onChange(of: query) { _, _ in refresh() }
        .onChange(of: scope) { _, _ in refresh() }
        .onKeyPress(.downArrow) { byKey = true; sel = min(sel + 1, max(flat.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { byKey = true; sel = max(sel - 1, 0); return .handled }
        .onKeyPress(.tab) { step(NSEvent.modifierFlags.contains(.shift) ? -1 : 1); return .handled }
        .onKeyPress(.escape) { if query.isEmpty && scope == .all { close() } else if query.isEmpty { scope = .all } else { query = "" }; return .handled }
    }

    // MARK: Pieces

    private var field: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: S(17), weight: .semibold)).foregroundStyle(Brand.amber)
            TextField(scope == .all ? "Search everything: sessions, tests, choices, roadmap, requests, commands…" : "Search \(scope.title.lowercased())…", text: $query)
                .textFieldStyle(.plain).font(.system(size: S(19), weight: .medium)).foregroundStyle(.white).focused($focused)
                .onSubmit { open(selected, start: NSEvent.modifierFlags.contains(.command)) }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.mute) }.buttonStyle(.plain).pointerStyle(.link)
            }
            key("ESC")
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PaletteScope.allCases, id: \.self) { s in
                    let n = count(s), on = s == scope
                    Button { scope = s; focused = true } label: {
                        HStack(spacing: 6) {
                            if s != .all { icon(s.kinds[0].icon, size: S(9)).foregroundStyle(on ? Color.black : s.color) }
                            Text(s.title.uppercased()).font(Brand.label(9.5)).tracking(0.7)
                            Text("\(n)").font(.system(size: S(10), weight: .semibold).monospacedDigit()).opacity(0.75)
                        }
                        .foregroundStyle(on ? Color.black : n == 0 ? Brand.mute.opacity(0.5) : Brand.ink)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(PixelBox().fill(on ? s.color : Brand.panel2))
                    }
                    .buttonStyle(.plain).pointerStyle(.link)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) { key("TAB"); Text("narrow").font(.system(size: S(10.5))).foregroundStyle(Brand.mute) }
            }
            .padding(.horizontal, 18).padding(.bottom, 12)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { r in
                        switch r {
                        case .header(let k, let n): header(k, n)
                        case .hit(let h, let i):
                            row(h, selected: i == sel).id(i)
                                .onTapGesture { open(h, start: NSEvent.modifierFlags.contains(.command)) }
                                .onHover { if $0, sel != i { byKey = false; sel = i } }
                        case .more(let k, let n):
                            Button { if let s = PaletteScope.allCases.first(where: { $0 != .all && $0.kinds.contains(k) }) { scope = s } } label: {
                                Text("+ \(n) more \(k.plural.lowercased())").font(.system(size: S(11), weight: .medium)).foregroundStyle(k.color)
                                    .padding(.leading, 56).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).pointerStyle(.link)
                        }
                    }
                    if flat.isEmpty { empty }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: sel) { _, v in if byKey { proxy.scrollTo(v) } }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            PixelIcon(name: "choice", size: S(26)).foregroundStyle(Brand.line2)
            Text(query.isEmpty ? "Nothing here yet." : "Nothing matches “\(query)”\(scope == .all ? "" : " in \(scope.title.lowercased())").")
                .font(.system(size: S(13))).foregroundStyle(Brand.mute)
            if scope != .all, count(.all) > 0 {
                Button("Search everything (\(count(.all)))") { scope = .all }.buttonStyle(.link).pointerStyle(.link)
            } else if !query.isEmpty {
                Button("File it as a new request") { let q = query; close(); model.requestSeed = q; model.requestOpen = true }.buttonStyle(.link).pointerStyle(.link)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 70)
    }

    private func header(_ k: PaletteKind, _ n: Int) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(k.color).frame(width: 6, height: 6)
            Text(k.plural.uppercased()).font(Brand.label(9)).tracking(1).foregroundStyle(k.color)
            Text("\(n)").font(.system(size: S(10)).monospacedDigit()).foregroundStyle(Brand.mute)
            Rectangle().fill(Brand.line).frame(height: 1)
        }
        .padding(.leading, 18).padding(.trailing, 12).padding(.top, 12).padding(.bottom, 5)
    }

    private func row(_ h: PaletteHit, selected: Bool) -> some View {
        HStack(spacing: 11) {
            tile(h, size: S(28))
            VStack(alignment: .leading, spacing: 2) {
                Text(PaletteIndex.lit(h.title, query, base: selected ? .white : Brand.ink))
                    .font(.system(size: S(13), weight: .medium)).lineLimit(1)
                HStack(spacing: 5) {
                    if h.kind != .action && h.kind != .project && h.projectId != model.selectedProjectId {
                        Text(h.projectName).font(.system(size: S(10.5), weight: .semibold)).foregroundStyle(Brand.cream.opacity(0.85))
                        Text("·").foregroundStyle(Brand.mute)
                    }
                    if let s = PaletteIndex.snippet(h, query) {
                        Text(PaletteIndex.lit(s, query, base: Brand.mute)).lineLimit(1)
                    } else {
                        Text(h.context).foregroundStyle(Brand.mute).lineLimit(1)
                    }
                }
                .font(.system(size: S(11)))
            }
            Spacer(minLength: 8)
            if let badge = sessionBadge(h) { Text(badge.0).font(.system(size: S(10.5), weight: .medium)).foregroundStyle(badge.1) }
            if let k = h.shortcut { key(k) } else if !h.state.isEmpty { Pill(text: h.state, color: h.stateColor) }
        }
        .padding(.leading, 12).padding(.trailing, 12).padding(.vertical, 6)
        .background(alignment: .leading) {
            if selected {
                ZStack(alignment: .leading) { h.kind.color.opacity(0.11); Rectangle().fill(h.kind.color).frame(width: 3) }
            }
        }
        .contentShape(Rectangle())
        .pointerStyle(.link)
    }

    @ViewBuilder private func tile(_ h: PaletteHit, size: CGFloat) -> some View {
        if h.kind == .project {
            PixelAvatar(name: h.projectName, size: size, projectId: h.projectId)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22).fill(h.kind.color.opacity(0.14))
                .overlay(icon(h.kind.icon, size: size * 0.42).foregroundStyle(h.kind.color))
                .frame(width: size, height: size)
        }
    }

    @ViewBuilder private func icon(_ name: String, size: CGFloat) -> some View {
        if name.hasPrefix("sf:") { Image(systemName: String(name.dropFirst(3))).font(.system(size: size * 1.05, weight: .semibold)) }
        else { PixelIcon(name: name, size: size) }
    }

    private var preview: some View {
        ScrollView {
            if let h = selected {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        tile(h, size: S(34))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.kind.label.uppercased()).font(Brand.label(9.5)).tracking(1).foregroundStyle(h.kind.color)
                            Text(h.projectName).font(.system(size: S(11))).foregroundStyle(Brand.mute)
                        }
                        Spacer()
                        if h.shortcut == nil, !h.state.isEmpty { Pill(text: h.state, color: h.stateColor) }
                    }
                    Text(PaletteIndex.lit(h.title, query, base: .white)).font(.system(size: S(15), weight: .semibold))
                        .lineLimit(5).fixedSize(horizontal: false, vertical: true)
                    if !h.context.isEmpty { Text(h.context).font(.system(size: S(11.5))).foregroundStyle(Brand.cream.opacity(0.8)) }
                    if let p = h.progress, p.total > 0 {
                        HStack(spacing: 8) {
                            PixelProgress(fraction: Double(p.done) / Double(p.total), blocks: 14)
                            Text("\(p.done)/\(p.total)").font(.system(size: S(11), weight: .bold).monospacedDigit()).foregroundStyle(Brand.green)
                        }
                    }
                    if let img = h.image {
                        BoardImage(dir: h.boardDir, path: img, height: S(150)).clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.line))
                    }
                    if !h.body.isEmpty {
                        Text(PaletteIndex.lit(String(h.body.prefix(520)), query, base: Brand.ink.opacity(0.8))).font(.system(size: S(12)))
                            .lineSpacing(2).lineLimit(9).fixedSize(horizontal: false, vertical: true)
                    }
                    if !h.lines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(h.linesTitle.uppercased()).font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.mute)
                            ForEach(Array(h.lines.enumerated()), id: \.offset) { _, l in
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Text(l.mark).font(.system(size: S(11), weight: .bold, design: .monospaced))
                                        .foregroundStyle(l.on ? h.kind.color : l.mark == "✓" ? Brand.green : Brand.mute).frame(width: 12)
                                    Text(PaletteIndex.lit(l.text, query, base: l.on ? .white : Brand.ink.opacity(0.75)))
                                        .font(.system(size: S(11.5), weight: l.on ? .semibold : .regular)).lineLimit(2)
                                }
                            }
                        }
                    }
                    if !h.facts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(h.facts, id: \.self) { f in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(f.label.uppercased()).font(Brand.label(8.5)).tracking(0.6).foregroundStyle(Brand.mute).frame(width: S(64), alignment: .leading)
                                    Text(f.value).font(.system(size: S(11.5))).foregroundStyle(Brand.ink.opacity(0.85)).lineLimit(3)
                                }
                            }
                        }
                    }
                    actions(h)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    PixelIcon(name: "term", size: S(22)).foregroundStyle(Brand.line2)
                    Text("Pick a row to see it here.").font(.system(size: S(12))).foregroundStyle(Brand.mute)
                }.frame(maxWidth: .infinity).padding(.top, 90)
            }
        }
        .background(Color(hex: 0x0b0c0f))
    }

    @ViewBuilder private func actions(_ h: PaletteHit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) { key("↩"); Text(primary(h)).font(.system(size: S(11.5), weight: .medium)).foregroundStyle(Brand.ink) }
            if let s = secondary(h) {
                HStack(spacing: 7) { key("⌘↩"); Image(systemName: "sparkle").font(.system(size: S(10))).foregroundStyle(Brand.claude)
                    Text(s).font(.system(size: S(11.5), weight: .medium)).foregroundStyle(Brand.ink) }
            }
        }
        .padding(.top, 4)
    }

    private func primary(_ h: PaletteHit) -> String {
        switch h.kind {
        case .session: "Show this session"
        case .talk: "Resume this conversation"
        case .project: "Switch project"
        case .action: "Run"
        default: sessionBadge(h) == nil ? "Open on the board" : "Open on the board, with its session"
        }
    }
    private func secondary(_ h: PaletteHit) -> String? {
        guard ![.session, .talk, .project, .action].contains(h.kind), let ref = h.ref, let item = ItemRef(ref: ref),
              let p = model.projects.first(where: { $0.id == h.projectId }) else { return nil }
        return "Start a session: \(model.naturalIntent(item, in: p).rawValue)"
    }

    private var footer: some View {
        HStack(spacing: 16) {
            hint("↑↓", "move"); hint("↩", "open"); hint("⌘↩", "start a session"); hint("TAB", "one kind"); hint("ESC", query.isEmpty ? "close" : "clear")
            Spacer()
            Text("\(flat.count) of \(count(scope))").font(.system(size: S(11)).monospacedDigit()).foregroundStyle(Brand.mute)
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(Color(hex: 0x0b0c0f))
    }

    private func key(_ k: String) -> some View {
        Text(k).font(.system(size: S(9.5), weight: .bold, design: .monospaced)).foregroundStyle(Brand.cream)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(Brand.panel2))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Brand.line2))
    }
    private func hint(_ k: String, _ t: String) -> some View {
        HStack(spacing: 5) { key(k); Text(t).font(.system(size: S(11))).foregroundStyle(Brand.mute) }
    }

    private func sessionBadge(_ h: PaletteHit) -> (String, Color)? {
        guard ![.session, .talk, .project, .action].contains(h.kind), let ref = h.ref else { return nil }
        if model.sessions.contains(where: { $0.projectId == h.projectId && $0.covers(ref) && $0.running }) { return ("● session", Brand.green) }
        if let p = model.projects.first(where: { $0.id == h.projectId }), model.board(for: p).lastLink(ref) != nil { return ("↺ resume", Brand.cream) }
        return nil
    }

    // MARK: Logic

    private func count(_ s: PaletteScope) -> Int {
        guard !query.isEmpty || s != .all else { return index.count }
        return matched.reduce(0) { $0 + (s.kinds.contains($1.kind) ? 1 : 0) }
    }

    private func step(_ d: Int) {
        let all = PaletteScope.allCases, i = all.firstIndex(of: scope) ?? 0
        scope = all[(i + d + all.count) % all.count]
    }

    /// Rebuild the rows once per keystroke or scope change (never during drawing).
    private func refresh() {
        matched = PaletteIndex.search(index, query, current: model.selectedProjectId)
        let inScope = matched.filter { scope.kinds.contains($0.kind) }
        var out: [PaletteRow] = [], sel: [PaletteHit] = []
        func add(_ h: PaletteHit) { out.append(.hit(h, sel.count)); sel.append(h) }

        if scope != .all {
            // One kind: a plain ranked list (chapters before their items on the roadmap).
            for k in scope.kinds {
                let hs = inScope.filter { $0.kind == k }
                guard !hs.isEmpty else { continue }
                if scope.kinds.count > 1 { out.append(.header(k, hs.count)) }
                hs.prefix(120).forEach(add)
            }
        } else if query.isEmpty {
            // Nothing typed: what is alive and what waits on you, then the commands.
            let order: [(PaletteKind, Int, (PaletteHit) -> Bool)] = [
                (.session, 8, { _ in true }), (.test, 5, { $0.rank <= 1 }), (.choice, 5, { $0.rank <= 2 }),
                (.chapter, 4, { $0.rank <= 3 }), (.request, 3, { $0.rank <= 4 }), (.action, 4, { _ in true }), (.project, 6, { _ in true }),
            ]
            for (k, cap, keep) in order {
                let hs = inScope.filter { $0.kind == k && keep($0) }
                guard !hs.isEmpty else { continue }
                out.append(.header(k, hs.count)); hs.prefix(cap).forEach(add)
                if hs.count > cap { out.append(.more(k, hs.count - cap)) }
            }
        } else {
            // Typed: sections in the order of their best match, a few rows each.
            var seen: [PaletteKind] = []
            for h in inScope where !seen.contains(h.kind) { seen.append(h.kind) }
            for k in seen {
                let hs = inScope.filter { $0.kind == k }
                let cap = seen.count == 1 ? 60 : k == seen[0] ? 6 : 4
                out.append(.header(k, hs.count)); hs.prefix(cap).forEach(add)
                if hs.count > cap { out.append(.more(k, hs.count - cap)) }
            }
        }
        rows = out; flat = sel; self.sel = 0
    }

    private func open(_ h: PaletteHit?, start: Bool) {
        guard let h else { return }
        close()
        if let run = h.run { run(model); return }
        if h.kind == .session, let sid = h.sessionId {
            model.selectedProjectId = h.projectId
            model.selectedSession[h.projectId] = sid
            if let ref = h.ref { model.focusItem(projectId: h.projectId, ref: ref) }
            return
        }
        if h.kind == .talk, let l = h.link {
            model.selectedProjectId = h.projectId
            model.resume(l, projectId: h.projectId); return
        }
        guard let ref = h.ref else { return }
        model.openCombo(projectId: h.projectId, ref: ref, startNew: start)
    }

    private func close() { model.paletteOpen = false }

    /// The terminal (an AppKit view) usually holds the keyboard when ⌘K is pressed, and SwiftUI won't take focus
    /// from it while the palette is still being laid out. Release it, then focus the field on the next turns.
    private func grabFocus() {
        let win = { NSApp.keyWindow ?? NSApp.mainWindow }
        win()?.makeFirstResponder(nil)
        focused = true
        for delay in [0.0, 0.05, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard model.paletteOpen else { return }
                if !(win()?.firstResponder is NSTextView) { win()?.makeFirstResponder(nil) }
                focused = true
            }
        }
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
