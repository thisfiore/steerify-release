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
    @State private var openPin: Pin?
    @FocusState private var focused: Bool
    @FocusState private var draftFocused: Bool
    // Not remembered: a hidden panel used to stick across every preview (one stray "I" and the test, its ✓ and
    // the verdict were gone for good). Each preview opens with it; I / the sidebar button hide it for this one only.
    @State private var showPanel = true

    private var img: String { state.images[state.index] }
    private var pins: [Pin] { board.pins(state.ref).filter { $0.img == img } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea().onTapGesture { if !pinMode { close() } }
            VStack(spacing: 0) {
                toolbar
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        GeometryReader { geo in canvas(in: geo.size) }
                            .clipped()
                        if state.images.count > 1 { strip }
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
        .onKeyPress(.escape) { if draft != nil { draft = nil } else { close() }; return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "+=-0ni")) { k in
            // Typing in a note box (the test note, a pinned note) must never zoom or hide the panel.
            if NSApp.keyWindow?.firstResponder is NSText { return .ignored }
            switch k.characters {
            case "+", "=": setZoom(zoom * 1.25)
            case "-": setZoom(zoom / 1.25)
            case "0": resetView()
            case "n": if draft == nil { pinMode.toggle() } else { return .ignored }
            case "i": if draft == nil { showPanel.toggle() } else { return .ignored }
            default: return .ignored
            }
            return .handled
        }
    }

    // MARK: Pieces

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(state.title).font(.system(size: S(13), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Text("\(state.index + 1) / \(state.images.count)").font(Brand.label(10)).foregroundStyle(Brand.mute)
            Spacer()
            Button { setZoom(zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out (−)")
            Text("\(Int(zoom * 100))%").font(.system(size: S(11)).monospacedDigit()).foregroundStyle(Brand.mute).frame(width: 44)
            Button { setZoom(zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in (+)")
            Button("Fit") { resetView() }.help("Fit (0)")
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

    private func canvas(in size: CGSize) -> some View {
        let fit = fitted(in: size)
        return ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(zoom > 2 ? .none : .high)
                    .frame(width: fit.width, height: fit.height)
                    .overlay {
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(pins.enumerated()), id: \.offset) { i, p in
                                marker(i + 1, selected: openPin == p)
                                    .position(x: p.x * fit.width, y: p.y * fit.height)
                                    .onTapGesture { openPin = (openPin == p) ? nil : p }
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
                        draft = CGPoint(x: min(max(loc.x / fit.width, 0), 1), y: min(max(loc.y / fit.height, 0), 1))
                        draftText = ""; openPin = nil
                        if showPanel { DispatchQueue.main.async { draftFocused = true } }
                    }
                    .pointerStyle(pinMode ? .rectSelection : (zoom > 1 ? .grabIdle : .zoomIn))
                    .scaleEffect(zoom)
                    .offset(pan)
                    .gesture(DragGesture()
                        .onChanged { g in pan = CGSize(width: basePan.width + g.translation.width, height: basePan.height + g.translation.height) }
                        .onEnded { _ in basePan = pan })
                    .simultaneousGesture(MagnifyGesture()
                        .onChanged { g in zoom = min(max(baseZoom * g.magnification, 0.5), 8) }
                        .onEnded { _ in baseZoom = zoom })
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
                    .onSubmit(saveDraft)
                Button("Save", action: saveDraft).keyboardShortcut(.return, modifiers: [])
                Button("Cancel") { draft = nil }
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
            Text(draft != nil ? "Write the note on the right · Esc to cancel" : "Click where the note goes · Esc to stop")
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
                Button { choose(o, in: d) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: chosen ? "checkmark.circle.fill" : "hand.point.up.left.fill").font(.system(size: S(12), weight: .bold))
                        Text(DecisionCard.chooseTitle(L, multi: d.multi, chosen: chosen, notes: noted)).font(.system(size: S(13.5), weight: .bold))
                    }
                    .foregroundStyle(chosen ? Brand.amber : Color(hex: 0x1a1200))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(chosen ? Brand.amberDim : Brand.amber))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.amber, lineWidth: chosen ? 1.5 : 0))
                }.buttonStyle(SteerButton()).help(chosen ? "Click again to unselect" : noted ? "Make this your answer; Claude builds it with your notes" : "Make this your answer")
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
                let on = openPin == p
                HStack(alignment: .top, spacing: 8) {
                    marker(i + 1, selected: on).scaleEffect(zoom)
                    Text(p.note).font(.system(size: S(12))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
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
                        .onSubmit(saveDraft)
                    HStack {
                        Button("Save", action: saveDraft).keyboardShortcut(.return, modifiers: [])
                        Button("Cancel") { draft = nil }.foregroundStyle(Brand.mute)
                        Spacer()
                    }.buttonStyle(SteerButton()).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.amber)
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
            HStack(spacing: 6) {
                verdictButton(s, "ok", notes.isEmpty ? "✓ OK" : "✓ OK + notes", Brand.green, pick)
                verdictButton(s, "refine", "↻ Refine", Brand.amber, pick)
                verdictButton(s, "broken", "✕ Broken", Brand.red, pick)
            }
            NoteField(placeholder: "Note for Claude (what to change)…", initial: board.shipNote(s), marked: !board.shipNote(s).isEmpty) { board.setShip(s, pick: nil, note: $0) }
            if let r = itemRef {
                VStack(alignment: .leading, spacing: 6) {
                    if board.shipState(s) == .waiting {
                        ActionButton(title: "Fix my notes", primary: true) { close(); model.start(projectId: state.projectId, item: r, intent: .fix) }
                    }
                    if pick == "ok" && s.status != "live" {
                        ActionButton(title: board.shipNotes(s).isEmpty ? "Release" : "Apply notes + release", icon: "ship", primary: true) { close(); model.start(projectId: state.projectId, item: r, intent: .release) }
                    }
                    ClaudeButton(title: "Open with Claude") { close(); model.start(projectId: state.projectId, item: r, intent: .look) }
                }.padding(.top, 2)
            }
        }
    }

    private func verdictButton(_ s: ShipItem, _ k: String, _ title: String, _ c: Color, _ pick: String?) -> some View {
        Button { board.setShip(s, pick: k) } label: {
            Text(title).font(.system(size: S(11.5), weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .foregroundStyle(pick == k ? Color.black : c)
                .background(RoundedRectangle(cornerRadius: 6).fill(pick == k ? c : .clear))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(c.opacity(0.7)))
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
                VStack(alignment: .leading, spacing: 6) {
                    if board.isDecided(d) && !board.isBuilt(d) {
                        ActionButton(title: "Build my pick", primary: true) { close(); model.start(projectId: state.projectId, item: r, intent: .build) }
                    }
                    ClaudeButton(title: "Ask Claude") { close(); model.start(projectId: state.projectId, item: r, intent: .look) }
                }.padding(.top, 2)
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
            await MainActor.run { image = i }
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
    private func setZoom(_ z: CGFloat) { zoom = min(max(z, 0.5), 8); baseZoom = zoom }
    private func resetView() { zoom = 1; baseZoom = 1; pan = .zero; basePan = .zero; openPin = nil; draft = nil }
    private func close() { model.preview = nil }

    private func saveDraft() {
        guard let d = draft else { return }
        let t = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let opt = board.decisions.first { "choice:" + $0.id == state.ref }.flatMap { option($0)?.id }
        if !t.isEmpty { board.addPin(state.ref, img: img, x: d.x, y: d.y, note: t, version: state.version, option: opt) }
        draft = nil; draftText = ""
    }
}
