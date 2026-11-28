import SwiftUI
import AppKit

/// What is open in the preview: the images of one board item and where we are.
struct PreviewState: Identifiable {
    let id = UUID()
    let projectId: String
    let ref: String                 // the item ("test:<id>", "choice:<id>"): pins are saved on it
    let title: String
    let dir: String                 // board folder (images are relative to it)
    var images: [String]
    var index: Int
    var version: Int?
    var startInNoteMode = false
    /// The item's pictures as they are now. A choice's option pictures are drawn off-screen on first ask, so on the
    /// first open only some exist: the preview asks again whenever a drawing lands (→ reaches B, C as they appear).
    var refresh: (@MainActor () -> [String])? = nil
    /// The items Space walks through (same kind, waiting on you), fixed when the first one opened.
    var walk: [String] = []
}

/// Full-window preview: ← / → between the item's images, pinch / ⌘+ / ⌘− / double-click to zoom, drag to pan,
/// N (or the pin button) to drop a note on the picture. Notes are stored with the item, so its session reads them.
struct PreviewOverlay: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    @State var state: PreviewState

    @State private var image: NSImage?
    @State private var focusTestNote = 0
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var basePan: CGSize = .zero
    @State private var pinMode = false
    @State private var draft: CGPoint?          // relative point of a note being written
    @State private var draftText = ""
    // The note being written saves itself as it is typed (0.5 s after the last key, and whenever it is left:
    // Esc, another picture, another click, closing). draftImg = the picture it is on; draftSaved = already a pin.
    @State private var draftImg = ""
    @State private var draftSaved = false
    @State private var draftTask: Task<Void, Never>?
    @State private var openPin: Pin?
    @FocusState private var focused: Bool
    @FocusState private var draftFocused: Bool
    // Not remembered: a hidden panel used to stick across every preview (one stray "I" and the test, its ✓ and
    // the verdict were gone for good). Each preview opens with it; I / the sidebar button hide it for this one only.
    @State private var showPanel = true
    // Focus on the feature (choice mac-fullscreen-focus, A): the part of the picture under test, from the delivery's
    // focus or Apple Vision on the Mac. The picture opens zoomed on it; F shows the whole picture (kept per preview).
    @State private var featureRect: CGRect?
    @State private var whole = false
    @State private var canvasSize: CGSize = .zero
    // Choices whose option pictures are tall (phone shots) open with every option side by side; C toggles.
    @State private var compare: Bool?
    @State private var userMoved = false     // you zoomed / panned this picture yourself: focus leaves it alone

    private var img: String { state.images[state.index] }
    /// Pins on this picture, minus the one still being written (it shows as the draft).
    private var pins: [Pin] { board.pins(state.ref).filter { $0.img == img && !isDraft($0) } }
    private func isDraft(_ p: Pin) -> Bool { guard let d = draft, draftSaved else { return false }; return p.img == draftImg && p.x == d.x && p.y == d.y }
    private func same(_ a: Pin?, _ b: Pin) -> Bool { a.map { $0.img == b.img && $0.x == b.x && $0.y == b.y } ?? false }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea().onTapGesture { if !pinMode { close() } }
            VStack(spacing: 0) {
                toolbar
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        if comparing, let d = decision {
                            compareView(d)
                        } else {
                            GeometryReader { geo in
                                canvas(in: geo.size)
                                    .onAppear { canvasSize = geo.size }
                                    .onChange(of: geo.size) { _, s in canvasSize = s; applyFocus() }
                            }
                            .clipped()
                            if state.images.count > 1 { strip }
                        }
                    }
                    if showPanel { panel }
                }
            }
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear { focused = true; pinMode = state.startInNoteMode; load() }
        .onChange(of: state.index) { _, _ in resetView(); load() }
        .onReceive(MockSnapshots.shared.$version) { _ in refreshImages() }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.space) {
            // Space in a note box types a space; elsewhere: next picture, then the next item waiting on you.
            if NSApp.keyWindow?.firstResponder is NSText || draft != nil { return .ignored }
            spaceNext(); return .handled
        }
        .onKeyPress(.escape) { if draft != nil { finishDraft() } else { close() }; return .handled }
        .onChange(of: draftText) { _, _ in
            guard draft != nil else { return }
            draftTask?.cancel()
            draftTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled { writeDraft() }
            }
        }
        .onDisappear { finishDraft() }
        .onKeyPress(characters: CharacterSet(charactersIn: "+=-0nifc")) { k in
            // Typing in a note box (the test note, a pinned note) must never zoom or hide the panel.
            if NSApp.keyWindow?.firstResponder is NSText { return .ignored }
            switch k.characters {
            case "+", "=": setZoom(zoom * 1.25)
            case "-": setZoom(zoom / 1.25)
            case "0": resetView()
            case "n": if draft == nil { pinMode.toggle() } else { return .ignored }
            case "i": if draft == nil { showPanel.toggle() } else { return .ignored }
            case "f": if draft == nil, featureRect != nil { toggleWhole() } else { return .ignored }
            case "c": if draft == nil, decision != nil, optionPictures.count > 1 { compare = !comparing } else { return .ignored }
            default: return .ignored
            }
            return .handled
        }
    }

    // MARK: Pieces

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(state.title).font(.system(size: S(13), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            progress
            Spacer()
            walkPosition
            if featureRect != nil && !comparing {
                Button { toggleWhole() } label: {
                    Label(whole ? "Focus" : "Whole", systemImage: whole ? "scope" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: S(11.5), weight: .semibold))
                }.foregroundStyle(whole ? Brand.cream : Brand.amber)
                .help(whole ? "Zoom on the part under test (F)" : "Show the whole picture (F)")
            }
            if decision != nil && optionPictures.count > 1 {
                Button { compare = !comparing } label: {
                    Label(comparing ? "One by one" : "Side by side", systemImage: comparing ? "rectangle" : "rectangle.split.3x1")
                        .font(.system(size: S(11.5), weight: .semibold))
                }.help("Compare every option (C)")
            }
            if !comparing {
                Divider().frame(height: 16)
                Button { setZoom(zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out (−)")
                Text("\(Int(zoom * 100))%").font(.system(size: S(11)).monospacedDigit()).foregroundStyle(Brand.mute).frame(width: 44)
                Button { setZoom(zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in (+)")
                Button("Fit") { resetView() }.help("Fit (0)")
            }
            Divider().frame(height: 16)
            Button { withAnimation(.easeOut(duration: 0.15)) { showPanel.toggle() } } label: {
                if showPanel { Image(systemName: "sidebar.right") }
                else { Label("Test & notes", systemImage: "sidebar.right").font(.system(size: S(11.5), weight: .semibold)) }
            }
                .foregroundStyle(showPanel ? Brand.amber : Brand.cream)
                .help(showPanel ? "Hide notes and actions (I)" : "Show notes and actions (I)")
            Button { close() } label: { Image(systemName: "xmark") }.help("Close (Esc)")
        }
        .buttonStyle(SteerButton()).foregroundStyle(Brand.cream)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Brand.bg.opacity(0.9))
    }

    // MARK: Where you are (test i of n · option B of 3 · item k of m) and what comes next

    private struct Seg { let on: Bool; let color: Color }

    /// One segment per test (green = OK, amber = to refine) or per option (amber = your pick); the current one is outlined.
    @ViewBuilder private var progress: some View {
        if let s = ship, !s.tests.isEmpty {
            let fb = board.testFeedback(s), refs = board.testRefines(s)
            let cur = s.tests.firstIndex { $0.img == img }
            HStack(spacing: 8) {
                segments(s.tests.indices.map { i in
                    Seg(on: i == cur, color: refs.contains(i) ? Brand.amber : fb[i]?.ok == true ? Brand.green : Brand.line2)
                })
                Text(cur.map { "TEST \($0 + 1) OF \(s.tests.count)" } ?? "\(s.tests.count) TESTS · SCREENSHOT")
                    .font(Brand.label(10)).foregroundStyle(cur == nil ? Brand.mute : Brand.blue)
            }
        } else if let d = decision, !d.options.isEmpty {
            let o = option(d), picked = pickedIds(d)
            HStack(spacing: 8) {
                segments(d.options.map { x in Seg(on: x.id == o?.id, color: picked.contains(x.id) ? Brand.amber : Brand.line2) })
                Text(o.map { "OPTION \(DecisionCard.letter($0, in: d)) OF \(d.options.count)" } ?? "\(d.options.count) OPTIONS")
                    .font(Brand.label(10)).foregroundStyle(o == nil ? Brand.mute : Brand.cream)
            }
        } else {
            Text("\(state.index + 1) / \(state.images.count)").font(Brand.label(10)).foregroundStyle(Brand.mute)
        }
    }

    private func segments(_ xs: [Seg]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(xs.enumerated()), id: \.offset) { _, x in
                RoundedRectangle(cornerRadius: 2).fill(x.color)
                    .frame(width: xs.count > 8 ? 12 : 22, height: 5)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(x.on ? Color.white : .clear, lineWidth: 1.5).padding(-1.5))
            }
        }
    }

    private func pickedIds(_ d: BoardDecision) -> Set<String> {
        let v = board.verdict(d.id)
        return d.multi ? Set((v.pick as? [String]) ?? []) : Set([v.pickString].compactMap { $0 })
    }

    private var walk: [String] { state.walkList(board: board) }
    private var next: String? { state.nextRef(board: board) }

    /// "2 of 7 to test · ␣ next" on the toolbar.
    @ViewBuilder private var walkPosition: some View {
        let w = walk
        if w.count > 1, let i = w.firstIndex(of: state.ref) {
            HStack(spacing: 6) {
                Text("\(i + 1) of \(w.count) \(state.ref.hasPrefix("test:") ? "to test" : "choices")")
                    .font(.system(size: S(11)).monospacedDigit()).foregroundStyle(Brand.mute)
                keyCap("space")
                Text(onLast ? "next item" : "next").font(.system(size: S(11))).foregroundStyle(Brand.mute)
            }
        }
    }

    private func keyCap(_ t: String) -> some View {
        Text(t).font(.system(size: S(9.5), weight: .semibold, design: .monospaced)).foregroundStyle(Brand.cream)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Brand.line2))
    }

    /// Space goes to the next item from here (the last picture, or a choice shown side by side).
    private var onLast: Bool { comparing || state.index >= state.images.count - 1 }

    private func title(of ref: String) -> String {
        board.ships.first { "test:" + $0.id == ref }?.title ?? board.decisions.first { "choice:" + $0.id == ref }?.title ?? ref
    }

    /// The next item, at the bottom of the side panel.
    @ViewBuilder private var nextCard: some View {
        if let n = next {
            let w = walk
            Button { open(n) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) { header("NEXT", Brand.amber); keyCap("space") }
                    Text(title(of: n)).font(.system(size: S(13), weight: .semibold)).foregroundStyle(Brand.cream)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if let k = w.firstIndex(of: n) {
                        Text("\(k + 1) of \(w.count) \(n.hasPrefix("test:") ? "to test" : "choices")")
                            .font(.system(size: S(11))).foregroundStyle(Brand.mute)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Brand.amberDim))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.amber.opacity(0.8)))
                .contentShape(Rectangle())
            }.buttonStyle(SteerButton()).help("Open the next one (Space on the last picture)")
        } else if walk.count > 1 {
            Text("Nothing else waits on you here").font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
        }
    }

    private func spaceNext() {
        if !onLast { step(1); return }
        if let n = next { open(n) } else { model.showToast(state.ref.hasPrefix("test:") ? "Nothing else to test" : "No other choice waits on you") }
    }

    private func open(_ ref: String) {
        finishDraft()
        guard let s = PreviewState.item(ref, board: board, walk: walk) else { return }
        model.preview = s
    }

    // MARK: Side by side (tall option pictures)

    /// Option pictures of a choice, in option order.
    private var optionPictures: [(o: BoardOption, img: String)] {
        guard let d = decision else { return [] }
        return d.options.compactMap { o in (o.shot ?? MockSnapshots.shared.picture(for: o, boardDir: state.dir)).map { (o, $0) } }
    }
    private var comparing: Bool {
        if let c = compare { return c }
        // Default on when every option picture is tall (a phone screen) and they fit side by side.
        let ps = optionPictures
        guard decision != nil, (2...4).contains(ps.count) else { return false }
        return ps.allSatisfy { p in
            let full = p.img.hasPrefix("/") ? p.img : (state.dir as NSString).appendingPathComponent(p.img)
            guard let sz = ImageSize.of(full) else { return false }
            return sz.height > sz.width * 1.2
        }
    }

    private func compareView(_ d: BoardDecision) -> some View {
        let picked = pickedIds(d)
        return HStack(alignment: .top, spacing: 18) {
            ForEach(optionPictures, id: \.o.id) { p in
                let on = picked.contains(p.o.id)
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Text(DecisionCard.letter(p.o, in: d)).font(.system(size: S(13), weight: .heavy, design: .monospaced))
                            .foregroundStyle(on ? Color(hex: 0x1a1200) : Brand.amber)
                            .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 5).fill(on ? Brand.amber : Brand.amberDim))
                        Text(DecisionCard.name(p.o)).font(.system(size: S(13), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        if p.o.rec { Pill(text: "suggested", color: Brand.blue) }
                    }
                    BoardImage(dir: state.dir, path: p.img, height: max(canvasSize.height - 140, 300), onOpen: {
                        if let i = state.images.firstIndex(of: p.img) { compare = false; state.index = i }
                    })
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Brand.amber : Brand.line, lineWidth: on ? 2 : 1))
                    Button { choose(p.o, in: d) } label: {
                        Text(on ? "✓ Chosen" : "Choose \(DecisionCard.letter(p.o, in: d))").font(.system(size: S(12.5), weight: .bold))
                            .foregroundStyle(on ? Brand.amber : Color(hex: 0x1a1200))
                            .frame(maxWidth: 220).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Brand.amberDim : Brand.amber))
                    }.buttonStyle(SteerButton())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GeometryReader { g in Color.clear.onAppear { canvasSize = g.size }.onChange(of: g.size) { _, s in canvasSize = s } })
    }

    // MARK: Focus on the feature

    /// The part of this picture under test: the delivery's focus, else Apple Vision's guess (on the Mac).
    private func findFocus() {
        let path = img, said = ship?.focus[path]
        featureRect = said
        applyFocus()
        guard said == nil else { return }
        let full = path.hasPrefix("/") ? path : (state.dir as NSString).appendingPathComponent(path)
        Task { @MainActor in
            let words = ship.flatMap { s in s.tests.first { $0.img == path }.map { $0.label + " " + ($0.check ?? "") } } ?? ""
            let r = await FocusGuess.rect(for: full, words: words)
            guard img == path, featureRect == nil else { return }
            featureRect = r
            applyFocus()
        }
    }

    /// Zoom and pan so the feature fills the stage (with air around it), unless you asked for the whole picture.
    private func applyFocus() {
        guard let r = featureRect, !whole, !userMoved, image != nil, canvasSize.width > 0 else { return }
        let fit = fitted(in: canvasSize)
        guard fit.width > 0, r.width > 0, r.height > 0 else { return }
        let z = min(min(canvasSize.width / (r.width * fit.width), canvasSize.height / (r.height * fit.height)) * 0.94, 4)
        guard z > 1.25 else { return }     // a nudge crops more than it shows: keep the whole picture
        let cx = (r.midX - 0.5) * fit.width, cy = (r.midY - 0.5) * fit.height
        zoom = z; baseZoom = z
        pan = CGSize(width: -cx * z, height: -cy * z); basePan = pan
    }

    private func toggleWhole() {
        whole.toggle()
        withAnimation(.easeOut(duration: 0.2)) {
            if whole { zoom = 1; baseZoom = 1; pan = .zero; basePan = .zero } else { applyFocus() }
        }
    }

    private func canvas(in size: CGSize) -> some View {
        let fit = fitted(in: size)
        return ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(zoom > 2 ? .none : .high)
                    .frame(width: fit.width, height: fit.height)
                    .overlay {
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(pins.enumerated()), id: \.offset) { i, p in
                                marker(i + 1, selected: same(openPin, p))
                                    .position(x: p.x * fit.width, y: p.y * fit.height)
                                    .onTapGesture { finishDraft(); openPin = same(openPin, p) ? nil : p }
                            }
                            if let d = draft {
                                marker(pins.count + 1, selected: true).position(x: d.x * fit.width, y: d.y * fit.height)
                            }
                        }
                        .frame(width: fit.width, height: fit.height)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if !pinMode { zoom > 1 ? resetView() : setZoom(2) } }
                    .onTapGesture { loc in
                        // ⌘-click drops a note right there; in "Add note" mode a plain click does too.
                        guard pinMode || NSEvent.modifierFlags.contains(.command) else { return }
                        finishDraft()
                        // Rounded like the saved pin, so the draft and its pin are the same spot.
                        draft = CGPoint(x: round3(min(max(loc.x / fit.width, 0), 1)), y: round3(min(max(loc.y / fit.height, 0), 1)))
                        draftImg = img; draftText = ""; draftSaved = false; openPin = nil
                        if showPanel { DispatchQueue.main.async { draftFocused = true } }
                    }
                    .pointerStyle(pinMode ? .rectSelection : (zoom > 1 ? .grabIdle : .zoomIn))
                    .scaleEffect(zoom)
                    .offset(pan)
                    .gesture(DragGesture()
                        .onChanged { g in pan = CGSize(width: basePan.width + g.translation.width, height: basePan.height + g.translation.height) }
                        .onEnded { _ in basePan = pan; userMoved = true })
                    .simultaneousGesture(MagnifyGesture()
                        .onChanged { g in zoom = min(max(baseZoom * g.magnification, 0.5), 8) }
                        .onEnded { _ in baseZoom = zoom; userMoved = true })
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottom) { if showPanel { hint } else { noteBox } }
        .overlay(alignment: .leading) { arrow(-1) }
        .overlay(alignment: .trailing) { arrow(1) }
    }

    @ViewBuilder private var noteBox: some View {
        if draft != nil {
            HStack(spacing: 8) {
                Text("Note \(pins.count + 1)").font(Brand.label(10)).foregroundStyle(Brand.amber)
                TextField("What should change here?", text: $draftText).textFieldStyle(.plain).font(.system(size: S(13)))
                    .onSubmit(finishDraft)
                savedMark
                Button { discardDraft() } label: { Image(systemName: "trash") }.foregroundStyle(Brand.mute).help("Delete this note")
            }
            .padding(12).frame(maxWidth: 620)
            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.amber))
            .padding(.bottom, 16)
        } else if let p = openPin {
            HStack(alignment: .top, spacing: 10) {
                Text(p.note).font(.system(size: S(13))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Delete") { board.removePin(state.ref, p); openPin = nil }.foregroundStyle(Brand.red)
            }
            .buttonStyle(SteerButton())
            .padding(12).frame(maxWidth: 620)
            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.line2))
            .padding(.bottom, 16)
        } else if !pinMode && pins.isEmpty {
            Text("⌘-click on the picture to pin a note").font(.system(size: S(11.5))).foregroundStyle(Brand.mute).padding(.bottom, 14)
        } else if pinMode {
            Text("Click where the note goes · Esc to stop").font(.system(size: S(12))).foregroundStyle(Brand.amber).padding(.bottom, 16)
        }
    }

    private func arrow(_ dir: Int) -> some View {
        let enabled = state.images.indices.contains(state.index + dir)
        return Button { step(dir) } label: {
            Image(systemName: dir < 0 ? "chevron.left" : "chevron.right").font(.system(size: S(22), weight: .semibold))
                .frame(width: 44, height: 80).contentShape(Rectangle())
        }
        .buttonStyle(SteerButton()).foregroundStyle(enabled ? Brand.cream : .clear).disabled(!enabled)
        .padding(.horizontal, 8)
    }

    /// Bottom hint on the picture while the side panel holds the notes.
    @ViewBuilder private var hint: some View {
        if pinMode || draft != nil {
            Text(draft != nil ? "Write the note on the right · it saves as you type" : "Click where the note goes · Esc to stop")
                .font(.system(size: S(12))).foregroundStyle(Brand.amber).padding(.bottom, 14)
        } else if pins.isEmpty {
            Text("⌘-click on the picture to pin a note").font(.system(size: S(11.5))).foregroundStyle(Brand.mute).padding(.bottom, 14)
        }
    }

    // MARK: Side panel: what this picture is, its notes, and the item's actions

    private var ship: ShipItem? { state.ref.hasPrefix("test:") ? board.ships.first { "test:" + $0.id == state.ref } : nil }
    private var decision: BoardDecision? { state.ref.hasPrefix("choice:") ? board.decisions.first { "choice:" + $0.id == state.ref } : nil }
    private var itemRef: ItemRef? {
        guard var r = ItemRef(ref: state.ref) else { return nil }
        r.title = state.title; r.area = ship?.area ?? decision?.areas.first
        return r
    }

    private var panel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if let s = ship { aboutShip(s) } else if let d = decision { aboutOption(d) }
                notesSection
                if let s = ship { shipActions(s) } else if let d = decision { choiceActions(d) }
                nextCard
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: S(330))
        .frame(maxHeight: .infinity)
        .background(Brand.bg)
        .overlay(alignment: .leading) { Rectangle().fill(Brand.line).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { }
    }

    private func header(_ t: String, _ c: Color = Brand.mute) -> some View {
        Text(t).font(Brand.label(9)).tracking(0.9).foregroundStyle(c)
    }

    // This picture, for a test item: its test (what to check, ✓ / note) or the screenshot's caption.
    @ViewBuilder private func aboutShip(_ s: ShipItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let i = s.tests.firstIndex(where: { $0.img == img }) {
                let t = s.tests[i], fb = board.testFeedback(s)[i]
                header("TEST \(i + 1) OF \(s.tests.count)", Brand.blue)
                Text(t.label).font(.system(size: S(14), weight: .semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                if let c = t.check {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "eye").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                        Text(c).font(.system(size: S(12))).foregroundStyle(Brand.ink.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                let ok = fb?.ok == true, note = fb?.note ?? ""
                let flagged = board.testRefines(s).contains(i)
                NoteField(placeholder: flagged ? "What should change? Claude reads it" : "What is wrong with this test?", initial: note,
                          focusTrigger: focusTestNote, marked: flagged) { board.setTest(s, index: i, note: $0) }
                TestAnswerPair(ok: ok, refine: flagged,
                               onOK: { board.setTest(s, index: i, ok: !ok) },
                               onRefine: {
                                   if flagged && note.isEmpty { board.setTest(s, index: i, refine: false) }
                                   else { if !flagged { board.setTest(s, index: i, refine: true) }; focusTestNote += 1 }
                               }, full: true)
            } else {
                header("SCREENSHOT")
                let cap = s.shots.first { $0.img == img }?.caption ?? ""
                Text(cap.isEmpty ? s.title : cap).font(.system(size: S(13))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The option this picture shows, for a choice.
    private func option(_ d: BoardDecision) -> BoardOption? {
        d.options.first { $0.shot == img || MockSnapshots.shared.picture(for: $0, boardDir: state.dir) == img }
    }

    @ViewBuilder private func aboutOption(_ d: BoardDecision) -> some View {
        if let o = option(d) {
            let picks = Set((board.verdict(d.id).pick as? [String]) ?? [])
            let chosen = d.multi ? picks.contains(o.id) : board.verdict(d.id).pickString == o.id
            let L = DecisionCard.letter(o, in: d)
            let noted = !board.pins(d, option: o, picture: img).isEmpty
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    header("OPTION \(L)")
                    if o.rec { Pill(text: "suggested", color: Brand.blue) }
                }
                Text(DecisionCard.name(o)).font(.system(size: S(15), weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                ForEach(o.points, id: \.self) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle().fill(Brand.cream.opacity(0.5)).frame(width: 4, height: 4).offset(y: -2)
                        Text(p).font(.system(size: S(12))).foregroundStyle(Brand.ink.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                PixelCTA(title: DecisionCard.chooseTitle(L, multi: d.multi, chosen: chosen, notes: noted),
                         icon: chosen ? "check" : "choice", fullWidth: true, selected: chosen) { choose(o, in: d) }
                .help(chosen ? "Click again to unselect" : noted ? "Make this your answer; Claude builds it with your notes" : "Make this your answer")
                .padding(.top, 4)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header("CONTEXT")
                Text(d.title).font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // Notes pinned on this picture: list, select, delete, and the one being written.
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                header("NOTES ON THIS PICTURE", Brand.amber)
                if !pins.isEmpty { Text("\(pins.count)").font(Brand.label(9)).foregroundStyle(Brand.amber) }
                Spacer()
            }
            ForEach(Array(pins.enumerated()), id: \.offset) { i, p in
                let on = same(openPin, p)
                HStack(alignment: .top, spacing: 8) {
                    marker(i + 1, selected: on).scaleEffect(zoom)
                    // Click to edit: saves as it is typed, like every other note.
                    PinNoteText(note: p.note) { t in board.setPinNote(state.ref, p, note: t) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { board.removePin(state.ref, p); if on { openPin = nil } } label: { Image(systemName: "trash").font(.system(size: S(10.5))) }
                        .buttonStyle(SteerButton()).foregroundStyle(Brand.mute).help("Delete this note")
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? Brand.amberDim : Brand.panel))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Brand.amber.opacity(0.7) : Brand.line))
                .contentShape(Rectangle())
                .onTapGesture { openPin = on ? nil : p }
            }
            if draft != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Note \(pins.count + 1)").font(Brand.label(9.5)).foregroundStyle(Brand.amber)
                    TextField("What should change here?", text: $draftText, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: S(12.5))).lineLimit(1...5)
                        .focused($draftFocused)
                        .onSubmit(finishDraft)
                    HStack(spacing: 10) {
                        savedMark
                        Spacer()
                        Button { discardDraft() } label: { Image(systemName: "trash").font(.system(size: S(10.5))) }
                            .foregroundStyle(Brand.mute).help("Delete this note")
                    }.buttonStyle(SteerButton())
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.amber))
            } else {
                Button { pinMode.toggle() } label: {
                    HStack(spacing: 6) { Image(systemName: "mappin.and.ellipse"); Text(pinMode ? "Click the picture…" : "Add a note on the picture") }
                        .font(.system(size: S(12), weight: .semibold))
                        .foregroundStyle(pinMode ? Color(hex: 0x1a1200) : Brand.amber)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(pinMode ? Brand.amber : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.amber.opacity(0.8)))
                }.buttonStyle(SteerButton()).help("N, or ⌘-click anywhere on the picture")
            }
        }
    }

    // The item's verdict, note and next step, for a test.
    private func shipActions(_ s: ShipItem) -> some View {
        let pick = board.shipPick(s)
        return VStack(alignment: .leading, spacing: 8) {
            header("YOUR VERDICT · v\(s.version)", Brand.cream)
            let notes = board.shipNotes(s)
            NotesForClaude(notes: notes, pick: pick)
            // The verdict is the main call to action: OK full width and large, Refine / Broken smaller under it.
            verdictButton(s, "ok", notes.isEmpty ? "✓ OK" : "✓ OK + notes", Brand.green, pick, large: true)
            HStack(spacing: 6) {
                verdictButton(s, "refine", "↻ Refine", Brand.amber, pick)
                verdictButton(s, "broken", "✕ Broken", Brand.red, pick)
            }
            NoteField(placeholder: "Note for Claude (what to change)…", initial: board.shipNote(s), marked: !board.shipNote(s).isEmpty) { board.setShip(s, pick: nil, note: $0) }
            if let r = itemRef {
                // Optional next steps, set apart from the verdict: full width, one per line.
                VStack(alignment: .leading, spacing: 8) {
                    if board.shipState(s) == .waiting {
                        ActionButton(title: "Fix my notes", primary: true, large: true) { close(); model.start(projectId: state.projectId, item: r, intent: .fix) }
                    }
                    if pick == "ok" && s.status != "live" {
                        if let ship = model.shipLabel(s, in: board.project) {
                            ActionButton(title: ship.title, icon: "ship", primary: true, large: true) { close(); model.askShip(item: s, in: board.project) }
                        } else {
                            ActionButton(title: board.shipNotes(s).isEmpty ? "Release" : "Apply notes + release", icon: "ship", primary: true, large: true) { close(); model.start(projectId: state.projectId, item: r, intent: .release) }
                        }
                    }
                    ClaudeButton(title: "Open with Claude", large: true) { close(); model.start(projectId: state.projectId, item: r, intent: .look) }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
                .padding(.top, 8)
            }
        }
    }

    private func verdictButton(_ s: ShipItem, _ k: String, _ title: String, _ c: Color, _ pick: String?, large: Bool = false) -> some View {
        let r: CGFloat = large ? 8 : 6
        return Button { board.setShip(s, pick: k) } label: {
            Text(title).font(.system(size: S(large ? 13.5 : 11.5), weight: large ? .bold : .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, large ? 9 : 6)
                .foregroundStyle(pick == k ? Color.black : c)
                .background(RoundedRectangle(cornerRadius: r).fill(pick == k ? c : .clear))
                .overlay(RoundedRectangle(cornerRadius: r).stroke(c.opacity(0.7)))
                .contentShape(Rectangle())
        }.buttonStyle(SteerButton())
    }

    // The answer so far, its note and next step, for a choice.
    private func choiceActions(_ d: BoardDecision) -> some View {
        let v = board.verdict(d.id)
        let picked: String = {
            if d.multi { return d.options.filter { ((v.pick as? [String]) ?? []).contains($0.id) }.map { DecisionCard.letter($0, in: d) }.joined(separator: ", ") }
            return d.options.first { $0.id == v.pickString }.map { DecisionCard.letter($0, in: d) + " · " + DecisionCard.name($0) } ?? ""
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                header("YOUR ANSWER", Brand.cream)
                Text(picked.isEmpty ? "nothing chosen yet" : picked).font(.system(size: S(12), weight: .semibold))
                    .foregroundStyle(picked.isEmpty ? Brand.mute : Brand.cream).lineLimit(1)
            }
            NoteField(placeholder: picked.isEmpty ? "None fits? Say it in your own words…" : "Anything to add for Claude? (optional)", initial: v.note) { t in
                if d.multi { board.setChoiceMulti(d, picks: (v.pick as? [String]) ?? [], note: t) }
                else { board.setChoice(d, pick: v.pickString ?? (t.isEmpty ? nil : "__note"), note: t) }
            }
            if let r = itemRef {
                VStack(alignment: .leading, spacing: 8) {
                    if board.isDecided(d) && !board.isBuilt(d) {
                        ActionButton(title: DecisionCard.buildTitle(d, board: board), primary: true, large: true) { close(); model.start(projectId: state.projectId, item: r, intent: .build) }
                    }
                    ClaudeButton(title: "Discuss this with Claude", large: true) { close(); model.start(projectId: state.projectId, item: r, intent: .look) }
                }.padding(.top, 4)
            }
        }
    }

    private func choose(_ o: BoardOption, in d: BoardDecision) {
        let v = board.verdict(d.id)
        if d.multi {
            var picks = ((v.pick as? [String]) ?? []).filter { $0 != "__note" }
            if let k = picks.firstIndex(of: o.id) { picks.remove(at: k) } else { picks.append(o.id) }
            board.setChoiceMulti(d, picks: d.options.map(\.id).filter(picks.contains), note: v.note)
        } else if v.pickString == o.id {
            board.setChoice(d, pick: "__note", note: v.note, mix: [])
        } else {
            board.setChoice(d, pick: o.id, note: v.note, mix: board.mix(d).filter { $0 != o.id })
            let n = board.pins(d, option: o, picture: img).count
            model.showToast("“\(d.title.prefix(48))” · \(DecisionCard.letter(o, in: d))" + (n > 0 ? " + \(n) note\(n == 1 ? "" : "s")" : "") + " chosen")
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(state.images.enumerated()), id: \.offset) { i, p in
                    BoardImage(dir: state.dir, path: p, height: 54, onOpen: { state.index = i })
                        .frame(width: 86)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(i == state.index ? Brand.amber : .clear, lineWidth: 2))
                        .overlay(alignment: .topTrailing) {
                            let n = board.pins(state.ref).filter { $0.img == p }.count
                            if n > 0 { Text("\(n)").font(.system(size: S(9), weight: .bold)).foregroundStyle(Color(hex: 0x1a1200)).padding(.horizontal, 4).background(Brand.amber).padding(3) }
                        }
                }
            }.padding(10)
        }
        .background(Brand.bg.opacity(0.9))
    }

    /// Numbered square pin; stays the same size on screen whatever the zoom.
    private func marker(_ n: Int, selected: Bool) -> some View {
        Text("\(n)").font(.system(size: S(11), weight: .heavy, design: .monospaced))
            .foregroundStyle(Color(hex: 0x1a1200))
            .frame(width: 20, height: 20)
            .background(Rectangle().fill(Brand.amber))
            .overlay(Rectangle().stroke(selected ? Color.white : Color.black.opacity(0.6), lineWidth: 2))
            .shadow(color: .black.opacity(0.6), radius: 3)
            .scaleEffect(1 / zoom)
    }

    // MARK: Logic

    private func fitted(in size: CGSize) -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else { return size }
        let s = min(size.width / image.size.width, size.height / image.size.height)
        return CGSize(width: image.size.width * s, height: image.size.height * s)
    }

    private func load() {
        let full = img.hasPrefix("/") ? img : (state.dir as NSString).appendingPathComponent(img)
        image = nil
        Task.detached(priority: .userInitiated) {
            let i = NSImage(contentsOfFile: full)
            await MainActor.run { image = i; findFocus() }
        }
    }

    /// New option pictures landed: take them in, staying on the picture being looked at.
    private func refreshImages() {
        guard let r = state.refresh else { return }
        let now = r()
        guard !now.isEmpty, now != state.images else { return }
        let current = img
        state.images = now
        state.index = now.firstIndex(of: current) ?? min(state.index, now.count - 1)
    }

    private func step(_ d: Int) { if state.images.indices.contains(state.index + d) { state.index += d } }
    private func setZoom(_ z: CGFloat) { userMoved = true; zoom = min(max(z, 0.5), 8); baseZoom = zoom }
    private func resetView() { userMoved = false; zoom = 1; baseZoom = 1; pan = .zero; basePan = .zero; openPin = nil; finishDraft() }
    private func close() { finishDraft(); model.preview = nil }
    private func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    /// Write the note being typed to the board: a new pin the first time, the same pin after; empty = no pin.
    private func writeDraft() {
        draftTask?.cancel(); draftTask = nil
        guard let d = draft else { return }
        let t = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let spot = Pin(img: draftImg, x: d.x, y: d.y, note: t, at: nil)
        if t.isEmpty {
            if draftSaved { board.removePin(state.ref, spot); draftSaved = false }
        } else if draftSaved {
            board.setPinNote(state.ref, spot, note: t)
        } else {
            let opt = board.decisions.first { "choice:" + $0.id == state.ref }.flatMap { option($0)?.id }
            board.addPin(state.ref, img: draftImg, x: d.x, y: d.y, note: t, version: state.version, option: opt)
            draftSaved = true
        }
    }
    /// Done writing (↩, Esc, another click, another picture, closing): keep what was typed.
    private func finishDraft() {
        guard draft != nil else { return }
        writeDraft()
        draft = nil; draftText = ""; draftSaved = false
    }
    /// The trash on the note being written: nothing stays.
    private func discardDraft() {
        draftText = ""; writeDraft()
        draft = nil; draftSaved = false
    }
    private var savedMark: some View {
        Text(draftSaved ? "Saved" : (draftText.trimmingCharacters(in: .whitespaces).isEmpty ? "Saves as you type" : "Saving…"))
            .font(.system(size: S(11))).foregroundStyle(Brand.mute)
    }
}

/// A pinned note's text, editable in place: saves 0.5 s after the last key and when it loses focus.
private struct PinNoteText: View {
    let note: String
    let save: (String) -> Void
    @State private var text = ""
    @State private var pending: Task<Void, Never>?
    @FocusState private var focused: Bool
    var body: some View {
        TextField("Note", text: $text, axis: .vertical)
            .textFieldStyle(.plain).font(.system(size: S(12))).foregroundStyle(Brand.ink).lineLimit(1...8)
            .focused($focused)
            .onAppear { text = note }
            .onChange(of: note) { _, v in if !focused { text = v } }
            .onSubmit { flush() }
            .onChange(of: focused) { _, f in if !f { flush() } }
            .onChange(of: text) { _, _ in
                guard focused else { return }
                pending?.cancel()
                pending = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    if !Task.isCancelled { flush() }
                }
            }
            .onDisappear { flush() }
    }
    private func flush() {
        pending?.cancel(); pending = nil
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty && t != note { save(t) }      // emptied by mistake: keep the note (the trash deletes it)
    }
}
