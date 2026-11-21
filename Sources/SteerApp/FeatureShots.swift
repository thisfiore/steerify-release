import SwiftUI
import AppKit

// MARK: - Pictures of a feature, on its roadmap / requirement row
//
// A key result or a requirement shows the pictures of its feature where it is listed:
// the design first (the picked option of its choices), replaced by the test screenshots once a
// delivery names it, and the test buttons of that delivery stay there for good.

struct FeatureMedia {
    /// "tested" when a delivery brought pictures, else "design".
    var phase: String
    var design: [(ref: String, pic: GalleryItem)]
    var tested: [(ref: String, pic: GalleryItem)]
    var ships: [ShipItem]
    var tests: [(ship: ShipItem, test: ShipTest)]
    var isEmpty: Bool { design.isEmpty && tested.isEmpty && ships.isEmpty }
    /// What the row shows: the test pictures once there are any, else the design.
    var pics: [(ref: String, pic: GalleryItem)] { tested.isEmpty ? design : tested }
    /// Rows with the same key show the same pictures and tests: they are grouped and shown once.
    var groupKey: String { isEmpty ? "" : (ships.map(\.id) + pics.map(\.pic.path)).joined(separator: "|") }
}

extension BoardStore {
    func ships(forRoad r: RoadItem) -> [ShipItem] {
        // Index built once per board: road text and its slug → deliveries (was a slug of every delivery's text per row).
        let ix: [String: [Int]] = memoized("shipsByRoad", durable: true) {
            var m: [String: [Int]] = [:]
            for (i, s) in ships.enumerated() {
                for rd in s.roads {
                    for k in Set(["t:" + rd, "s:" + BoardFiles.slug(rd)]) where m[k]?.last != i { m[k, default: []].append(i) }
                }
            }
            return m
        }
        let hits = Set((ix["t:" + r.text] ?? []) + (ix["s:" + r.id] ?? []))
        return ships.indices.filter(hits.contains).map { ships[$0] }
    }
    func ships(forReq id: String) -> [ShipItem] { ships.filter { $0.reqs.contains(id) } }

    /// The option(s) you picked (plus the mix), else none: an unanswered choice has no design yet.
    func pickedOptions(_ d: BoardDecision) -> [BoardOption] {
        guard isDecided(d) else { return [] }
        let c = verdict(d.id)
        var ids: [String] = (c.pick as? [String]) ?? (c.pickString.map { [$0] } ?? [])
        if let mix = (choiceMapEntry(d.id)?["mix"] as? [String]) { ids += mix }
        return ids.compactMap { id in d.options.first { $0.id == id } }
    }

    func media(road r: RoadItem, snaps: Int) -> FeatureMedia {
        memoized("media:road:\(r.id)#\(snaps)", durable: true) {
            let linked = ships(forRoad: r)
            var choiceIds = Set(thread(of: "road:" + r.id).filter { $0.hasPrefix("choice:") }.map { String($0.dropFirst(7)) })
            // Choices of the request this key result came from, only when the request made just this one item
            // (a request drafted into a whole chapter shows its choices on the chapter, not on every row).
            let ownRequest = r.request.flatMap { q in roadmap.filter { $0.request == q }.count == 1 ? "request:" + q : nil }
            for d in decisions where d.origin == "road:" + r.id || (ownRequest != nil && d.origin == ownRequest) { choiceIds.insert(d.id) }
            // The thread also pulls in choices asked from the chapter's request: keep only those tied to this row.
            let chapterOrigins = Set(chapters.filter { $0.name == r.track }.compactMap { $0.request.map { "request:" + $0 } } + ["track:" + BoardFiles.slug(r.track)])
            let built = Set(linked.flatMap(\.choices))
            choiceIds = choiceIds.filter { id in built.contains(id) || !chapterOrigins.contains(decisions.first { $0.id == id }?.origin ?? "") }
            return build(linked, choiceIds)
        }
    }

    /// A whole chapter: the design of its own choices (asked from its request), then the newest test pictures of its key results.
    func media(chapter name: String, snaps: Int) -> FeatureMedia {
        memoized("media:track:\(name)#\(snaps)", durable: true) {
            let items = roadmap.filter { $0.track == name }
            let linked = ships.filter { s in s.roads.contains { rd in items.contains { $0.text == rd || $0.id == BoardFiles.slug(rd) } } }
            let origins = Set(chapters.filter { $0.name == name }.compactMap { $0.request.map { "request:" + $0 } } + ["track:" + BoardFiles.slug(name)])
            let ids = Set(decisions.filter { origins.contains($0.origin ?? "") }.map(\.id))
            var m = build(linked, ids)
            m.tests = []   // the rows keep their own test buttons
            m.tested = []  // …and their own test pictures: the chapter shows only the design it picked
            return m
        }
    }

    func media(req r: Requirement, snaps: Int) -> FeatureMedia {
        memoized("media:req:\(r.id)#\(snaps)", durable: true) {
            let linked = ships(forReq: r.id)
            var choiceIds = Set(linked.flatMap(\.choices))
            for d in decisions where d.origin == "req:" + r.id || d.why.contains("requirement \(r.id)") { choiceIds.insert(d.id) }
            return build(linked, choiceIds)
        }
    }

    private func build(_ linked: [ShipItem], _ choiceIds: Set<String>) -> FeatureMedia {
        let newest = linked.sorted { ($0.updated ?? "") > ($1.updated ?? "") }
        var seen = Set<String>()
        var design: [(String, GalleryItem)] = []
        for d in decisions where choiceIds.contains(d.id) {
            for o in pickedOptions(d) {
                if let p = o.shot ?? MockSnapshots.shared.picture(for: o, boardDir: project.boardDir), seen.insert(p).inserted {
                    design.append(("choice:" + d.id, GalleryItem(path: p, caption: "\(d.title) · \(o.label)")))
                }
            }
        }
        var tested: [(String, GalleryItem)] = []
        var tests: [(ShipItem, ShipTest)] = []
        for s in newest {
            for t in s.tests {
                if let i = t.img, seen.insert(i).inserted { tested.append(("test:" + s.id, GalleryItem(path: i, caption: t.label, focus: s.focus[i]))) }
                if let u = t.url, !TestEnvs.dead(u) { tests.append((s, t)) }
            }
            for sh in s.shots where seen.insert(sh.img).inserted {
                tested.append(("test:" + s.id, GalleryItem(path: sh.img, caption: sh.caption, focus: s.focus[sh.img])))
            }
        }
        return FeatureMedia(phase: tested.isEmpty ? "design" : "tested",
                            design: design.map { (ref: $0.0, pic: $0.1) }, tested: tested.map { (ref: $0.0, pic: $0.1) },
                            ships: newest, tests: tests.map { (ship: $0.0, test: $0.1) })
    }
}

/// Under a roadmap / requirement row: a few pictures (design → tests) and the delivery's test buttons.
struct FeatureStrip: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    @ObservedObject private var snaps = MockSnapshots.shared
    var road: RoadItem? = nil
    var req: Requirement? = nil
    var chapter: String? = nil
    var compact = false
    @State private var showDesign = false

    var body: some View {
        let m = road.map { board.media(road: $0, snaps: snaps.version) } ?? req.map { board.media(req: $0, snaps: snaps.version) }
            ?? chapter.map { board.media(chapter: $0, snaps: snaps.version) }
        if let m, !m.isEmpty {
            let useDesign = m.tested.isEmpty || (showDesign && !m.design.isEmpty)
            let pics = useDesign ? m.design : m.tested
            VStack(alignment: .leading, spacing: 5) {
                if !pics.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(pics.prefix(compact ? 3 : 4).enumerated()), id: \.offset) { i, p in
                            BoardImage(dir: board.project.boardDir, path: p.pic.path, height: S(compact ? 46 : 64), focus: p.pic.focus) { open(pics, i) }
                                .frame(width: S(compact ? 80 : 112))
                                .help(p.pic.caption)
                        }
                        if pics.count > (compact ? 3 : 4) {
                            Button("+\(pics.count - (compact ? 3 : 4))") { open(pics, compact ? 3 : 4) }
                                .buttonStyle(SteerButton()).font(.system(size: S(11), weight: .semibold)).foregroundStyle(Brand.mute)
                        }
                        phaseTag(useDesign ? "DESIGN" : "TESTED", useDesign ? Brand.amber : Brand.blue)
                        if !m.design.isEmpty && !m.tested.isEmpty {
                            Button(useDesign ? "show tests" : "show design") { showDesign.toggle() }
                                .buttonStyle(.link).font(.system(size: S(10.5))).pointerStyle(.link)
                                .help(useDesign ? "Back to the screenshots of the tests" : "The design you picked, before it was built")
                        }
                    }
                }
                if !m.ships.isEmpty && chapter == nil { testButtons(m) }
            }
            .padding(.top, 3)
        }
    }

    private func phaseTag(_ t: String, _ c: Color) -> some View {
        Text(t).font(Brand.label(7.5)).tracking(0.6).foregroundStyle(c)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(c.opacity(0.5), lineWidth: 1))
    }

    /// The tests of the delivery (each opens the exact page under test) + a jump to its To test card.
    @ViewBuilder private func testButtons(_ m: FeatureMedia) -> some View {
        let shown = m.tests.prefix(compact ? 2 : 4)
        HStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, t in
                if let u = t.test.url, !TestEnvs.dead(u), let url = URL(string: u) {
                    Button { if url.scheme == "steerify" { model.handle(url) } else { NSWorkspace.shared.open(url) } } label: {
                        HStack(spacing: 4) { PixelIcon(name: "test", size: 8); Text(t.test.label).lineLimit(1) }
                    }
                    .buttonStyle(SteerButton()).font(.system(size: S(11))).foregroundStyle(Brand.ink.opacity(0.85))
                    .help(t.test.check ?? u)
                }
            }
            if m.tests.count > shown.count {
                Text("+\(m.tests.count - shown.count)").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
            }
            if let s = m.ships.first {
                let pick = board.effectivePick(s)
                Button { model.focusItem(projectId: board.project.id, ref: "test:" + s.id) } label: {
                    Text(pick == "ok" ? "✓ tested v\(s.version)" : pick == nil ? "To test v\(s.version) →" : "\(pick!) · v\(s.version) →")
                }
                .buttonStyle(.link).font(.system(size: S(10.5))).pointerStyle(.link)
                .foregroundStyle(pick == "ok" ? Brand.green : pick == nil ? Brand.blue : Brand.amber)
                .help("Open “\(s.title)” on To test")
            }
        }
    }

    private func open(_ pics: [(ref: String, pic: GalleryItem)], _ i: Int) {
        let p = pics[min(i, pics.count - 1)]
        // Pins land on the item the picture belongs to (its To test card or its choice).
        let same = pics.filter { $0.ref == p.ref }.map(\.pic.path)
        let ship = board.ships.first { "test:" + $0.id == p.ref }
        model.preview = PreviewState(projectId: board.project.id, ref: p.ref, title: road?.text ?? req?.text ?? chapter ?? "",
                                     dir: board.project.boardDir, images: same, index: same.firstIndex(of: p.pic.path) ?? 0,
                                     version: ship?.version, startInNoteMode: NSEvent.modifierFlags.contains(.command))
    }
}

/// The pictures of a feature as a small column between the title and the buttons of a row:
/// you see they exist; a click opens them big. Blue edge = tests, amber = the design picked.
struct FeatureThumbs: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let media: FeatureMedia
    var title: String
    var shared = 1
    static var width: CGFloat { S(124) }

    var body: some View {
        let pics = media.pics
        let tint = media.tested.isEmpty ? Brand.amber : Brand.blue
        HStack(spacing: S(4)) {
            ForEach(Array(pics.prefix(2).enumerated()), id: \.offset) { i, p in
                BoardImage(dir: board.project.boardDir, path: p.pic.path, height: S(36), focus: p.pic.focus) { open(pics, i) }
                    .frame(width: S(58))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(tint.opacity(0.55), lineWidth: 1))
                    .overlay {
                        if i == 1 && pics.count > 2 {
                            Text("+\(pics.count - 2)").font(.system(size: S(11), weight: .bold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.55)))
                                .allowsHitTesting(false)
                        }
                    }
                    .help((media.tested.isEmpty ? "Design you picked · " : "Tested · ") + p.pic.caption
                          + (shared > 1 ? " · shared by \(shared) key results" : ""))
                    .contextMenu {
                        if !media.design.isEmpty && !media.tested.isEmpty {
                            Button("Show the design you picked") { open(media.design, 0) }
                        }
                        Button("Open the pictures") { open(pics, i) }
                    }
            }
        }
        .frame(width: Self.width, alignment: .leading)
    }

    private func open(_ pics: [(ref: String, pic: GalleryItem)], _ i: Int) {
        guard !pics.isEmpty else { return }
        let p = pics[min(i, pics.count - 1)]
        let same = pics.filter { $0.ref == p.ref }.map(\.pic.path)
        let ship = board.ships.first { "test:" + $0.id == p.ref }
        model.preview = PreviewState(projectId: board.project.id, ref: p.ref, title: title,
                                     dir: board.project.boardDir, images: same, index: same.firstIndex(of: p.pic.path) ?? 0,
                                     version: ship?.version, startInNoteMode: NSEvent.modifierFlags.contains(.command))
    }
}

/// The test buttons of a feature's delivery + the jump to its To test card, on one quiet line.
struct FeatureTestLine: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let media: FeatureMedia
    var compact = false
    var shared = 1

    var body: some View {
        if !media.ships.isEmpty {
            let shown = media.tests.prefix(compact ? 2 : 4)
            HStack(spacing: 6) {
                if shared > 1 {
                    Text("\(shared) KEY RESULTS · ONE DELIVERY").font(Brand.label(7.5)).tracking(0.5).foregroundStyle(Brand.mute)
                }
                ForEach(Array(shown.enumerated()), id: \.offset) { _, t in
                    if let u = t.test.url, !TestEnvs.dead(u), let url = URL(string: u) {
                        Button { if url.scheme == "steerify" { model.handle(url) } else { NSWorkspace.shared.open(url) } } label: {
                            HStack(spacing: 4) { PixelIcon(name: "test", size: 8); Text(t.test.label).lineLimit(1) }
                        }
                        .buttonStyle(SteerButton()).font(.system(size: S(11))).foregroundStyle(Brand.ink.opacity(0.85))
                        .help(t.test.check ?? u)
                    }
                }
                if media.tests.count > shown.count {
                    Text("+\(media.tests.count - shown.count)").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                }
                if let s = media.ships.first {
                    let pick = board.effectivePick(s)
                    Button { model.focusItem(projectId: board.project.id, ref: "test:" + s.id) } label: {
                        Text(pick == "ok" ? "✓ tested v\(s.version)" : pick == nil ? "To test v\(s.version) →" : "\(pick!) · v\(s.version) →")
                    }
                    .buttonStyle(.link).font(.system(size: S(10.5))).pointerStyle(.link)
                    .foregroundStyle(pick == "ok" ? Brand.green : pick == nil ? Brand.blue : Brand.amber)
                    .help("Open “\(s.title)” on To test")
                }
            }
        }
    }
}
