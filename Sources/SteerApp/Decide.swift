import SwiftUI
import AppKit

// MARK: - Choices as a guided decision (choice vis-standard: "a beautiful and simple decision making guided experience")
//
// Not a gallery of tiles: one option at a time on a big stage, tabs to move between them, one button to choose,
// then a short answer bar (blend others in, a note, Done). Decided choices fold into one line with their pick.

extension BoardFiles {
    /// `focus` on a delivered picture: [x, y, w, h] or {x, y, w, h}, 0–1 from the top-left.
    static func focusRect(_ v: Any?) -> CGRect? {
        func d(_ x: Any?) -> Double? { (x as? NSNumber)?.doubleValue }
        if let a = v as? [Any], a.count == 4, let x = d(a[0]), let y = d(a[1]), let w = d(a[2]), let h = d(a[3]) {
            return CGRect(x: x, y: y, width: w, height: h)
        }
        if let o = v as? [String: Any], let x = d(o["x"]), let y = d(o["y"]), let w = d(o["w"] ?? o["width"]), let h = d(o["h"] ?? o["height"]) {
            return CGRect(x: x, y: y, width: w, height: h)
        }
        return nil
    }
}

struct DecisionCard: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    let d: BoardDecision
    @State private var focus: String?            // the option on the stage
    @State private var draftPick: String?
    @State private var draftPicks = Set<String>()
    @State private var draftMix = Set<String>()
    @State private var draftNote = ""
    @State private var loaded = false
    @State private var reopened = false
    @State private var mock: BoardOption?
    @State private var showWhy = false
    @FocusState private var noteFocused: Bool
    @ObservedObject private var snaps = MockSnapshots.shared

    // Claude revised the choice after your answer: that answer is processed (recap above), the inputs start clean.
    private var processed: Bool { board.answerProcessed(d) }
    private var savedPick: String? { processed ? nil : board.verdict(d.id).pickString }
    private var savedPicks: Set<String> { processed ? [] : Set((board.verdict(d.id).pick as? [String]) ?? []) }
    private var savedMix: Set<String> { processed ? [] : Set(board.mix(d)) }
    private var savedNote: String { processed ? "" : board.verdict(d.id).note }
    /// Folded (decided) cards load their drafts only when opened: writing five states as each card scrolls into view
    /// laid it out twice (Choices scroll budget). Not loaded = nothing changed.
    private var changed: Bool { loaded && ((d.multi ? draftPicks != savedPicks : (draftPick != savedPick || draftMix != savedMix)) || draftNote != savedNote) }
    private var canSave: Bool { (d.multi ? !draftPicks.isEmpty : draftPick != nil) || !draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// First setup's choices (`setup-…`): the why is Claude's snapshot of the project, one fact per line: show it whole.
    private var whole: Bool { d.id.hasPrefix("setup-") }
    private var stage: BoardOption? { d.options.first { $0.id == focus } ?? d.options.first { $0.rec } ?? d.options.first }
    /// A logic decision (scope, order, yes/no: `simple`, no picture or prototype): nothing to look at, so no tabs and no
    /// empty stage. Every option is one row of a list you choose from, its points and steps laid out side by side.
    private var listed: Bool { d.options.allSatisfy { ($0.simple || $0.mockHTML == nil) && $0.shot == nil && $0.proto == nil } }

    var body: some View {
        let decided = board.isDecided(d)
        Group {
            if decided && !reopened && !changed { folded } else { guided(decided) }
        }
        .popover(item: $mock) { o in MockView(dir: board.project.boardDir, option: o).frame(width: 1080, height: 709) }
        // Start drawing every option's picture now (not only the one shown), so Preview has B and C at once.
        .onAppear { if !decided { load(); _ = images } }
        .onChange(of: board.loadedAt) { _, _ in
            guard loaded else { if !board.isDecided(d) { load() }; return }
            if !changed || (!noteFocused && draftPick == savedPick) { draftPick = savedPick; draftPicks = savedPicks; draftMix = savedMix; draftNote = savedNote }
        }
    }

    private func load() {
        guard !loaded else { return }
        draftPick = savedPick; draftPicks = savedPicks; draftMix = savedMix; draftNote = savedNote
        // Nothing answered yet: the suggested option starts picked, so one Save (⌘↩) agrees with it.
        if !d.multi, savedPick == nil, savedNote.isEmpty, !board.isDecided(d), let rec = d.options.first(where: { $0.rec }) { draftPick = rec.id }
        focus = (savedPick != "__note" ? savedPick : nil) ?? stage?.id
        loaded = true
    }

    // MARK: Folded (decided)

    private var folded: some View {
        let pick = d.options.first { $0.id == savedPick }
        let picks = d.options.filter { savedPicks.contains($0.id) }
        return HStack(alignment: .center, spacing: 14) {
            if let o = pick ?? picks.first, let v = visual(o) {
                BoardImage(dir: board.project.boardDir, path: v, height: S(78), fit: true, onOpen: { openPreview(v) }).frame(width: S(124))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Brand.panel2).frame(width: S(124), height: S(78))
                    .overlay(Image(systemName: "text.quote").font(.system(size: S(18))).foregroundStyle(Brand.mute))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Pill(text: "decided", color: Brand.green)
                    ForEach(d.areas, id: \.self) { Text(board.areaName($0)).font(.system(size: S(11))).foregroundStyle(Brand.mute) }
                }
                Text(d.title).font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Group {
                    if let pick {
                        Text("You chose ").foregroundStyle(Brand.mute) + Text(pick.label).bold().foregroundStyle(Brand.cream)
                            + Text(savedMix.isEmpty ? "" : " + " + savedMix.compactMap { id in d.options.first { $0.id == id }.map { Self.letter($0, in: d) } }.sorted().joined(separator: " + ")).foregroundStyle(Brand.blue)
                    } else if !picks.isEmpty {
                        Text("You chose ").foregroundStyle(Brand.mute) + Text(picks.map(\.label).joined(separator: ", ")).bold().foregroundStyle(Brand.cream)
                    } else {
                        Text("Answered in your own words").foregroundStyle(Brand.mute)
                    }
                }.font(.system(size: S(12))).lineLimit(1)
                if !savedNote.isEmpty {
                    Text("“\(savedNote)”").font(.system(size: S(11.5))).italic().foregroundStyle(Brand.ink.opacity(0.75)).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                SessionChip(projectId: board.project.id, ref: "choice:" + d.id)
                if board.isBuilt(d) {
                    HStack(spacing: 6) {
                        Label("Built", systemImage: "checkmark").font(.system(size: S(11.5), weight: .medium)).foregroundStyle(Brand.green)
                        Button("Change") { load(); withAnimation(.easeOut(duration: 0.18)) { reopened = true } }
                            .buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                    }
                } else {
                    // Picked, not built: building it is the main call to action, as big as "Your choice".
                    HStack(alignment: .center, spacing: 8) {
                        Button("Change") { load(); withAnimation(.easeOut(duration: 0.18)) { reopened = true } }
                            .buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                        VStack(spacing: 6) {
                            ActionButton(title: Self.buildTitle(d, board: board), primary: true, large: true) { model.start(projectId: board.project.id, item: ref, intent: .build) }
                            ClaudeButton(title: "Discuss this with Claude", large: true) { model.start(projectId: board.project.id, item: ref, intent: .look) }
                        }.frame(width: S(250))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.line))
    }

    // MARK: Guided (open)

    private func guided(_ decided: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1 · The question
            HStack(spacing: 6) {
                Pill(text: board.isParked(d) ? "parked" : decided ? "decided" : "your call", color: decided ? Brand.green : Brand.amber)
                ForEach(d.areas, id: \.self) { Text(board.areaName($0)).font(.system(size: S(11))).foregroundStyle(Brand.mute) }
                if let a = d.added { Text("· asked \(a.prefix(10))").font(.system(size: S(11))).foregroundStyle(Brand.mute) }
                Spacer()
                SessionChip(projectId: board.project.id, ref: "choice:" + d.id)
                if reopened { Button("Close") { withAnimation { reopened = false } }.buttonStyle(SteerButton()).font(.system(size: S(11))).foregroundStyle(Brand.mute) }
            }
            Text(d.title).font(.system(size: S(18), weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if !d.why.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(BoardText.attributed(d.why)).font(.system(size: S(12.5))).foregroundStyle(Brand.ink.opacity(0.85))
                        .lineLimit(showWhy || whole ? nil : 3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if !whole, BoardText.plain(d.why).count > 240 {
                        Button(showWhy ? "less" : "more") { showWhy.toggle() }.buttonStyle(.link).pointerStyle(.link).font(.system(size: S(11)))
                    }
                }
            }
            if !decided, let pn = board.processedNotes(d) {
                ProcessedRecap(notes: pn, title: pn.notes.isEmpty ? "Revised after your answer" : "Revised after your \(pn.notes.count) note\(pn.notes.count == 1 ? "" : "s")")
            }
            if !d.gallery.isEmpty {
                Gallery(dir: board.project.boardDir, items: d.gallery.map { GalleryItem(path: $0.img, caption: $0.caption) },
                        heroHeight: 220, open: { openPreview(d.gallery[$0].img) })
            }

            steps
            if listed {
                optionList
            } else {
                optionTabs
                if let o = stage { stageView(o) }
            }
            answerBar(decided)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(decided ? Brand.line : Brand.amber.opacity(0.45)))
    }

    /// 1 Look · 2 Choose · 3 Done: where you are in the decision.
    private var steps: some View {
        let chosen = d.multi ? !draftPicks.isEmpty : draftPick != nil
        let at = !chosen && draftNote.isEmpty ? 0 : (changed ? 1 : 2)
        return HStack(spacing: 0) {
            ForEach(Array(["Look at the \(d.options.count) options", d.multi ? "Pick the ones you want" : "Choose one (blend others in)", "Done"].enumerated()), id: \.offset) { i, t in
                HStack(spacing: 6) {
                    Text(i < at ? "✓" : "\(i + 1)").font(.system(size: S(10.5), weight: .heavy, design: .monospaced))
                        .foregroundStyle(i <= at ? Color(hex: 0x1a1200) : Brand.mute)
                        .frame(width: S(18), height: S(18))
                        .background(Circle().fill(i < at ? Brand.green : i == at ? Brand.amber : Brand.panel2))
                    Text(t).font(.system(size: S(11.5), weight: i == at ? .semibold : .regular)).foregroundStyle(i == at ? Brand.cream : Brand.mute)
                }
                if i < 2 { Rectangle().fill(Brand.line2).frame(width: S(26), height: 1).padding(.horizontal, 8) }
            }
            Spacer()
        }
    }

    /// One pixel tab per option, the same look as Open live (choice card mockup, option bar A): big pixel letter,
    /// short name, a mark when it is suggested / chosen / blended in. The option on the stage is filled amber.
    private var optionTabs: some View {
        HStack(spacing: 8) {
            ForEach(d.options) { o in
                let on = stage?.id == o.id
                let chosen = d.multi ? draftPicks.contains(o.id) : draftPick == o.id
                let mixed = !d.multi && draftMix.contains(o.id)
                let ink = on ? Color(hex: 0x1a1200) : Brand.cream
                let mark = chosen ? (d.multi ? "✓ PICKED" : "✓ YOUR CHOICE") : mixed ? "BLENDED IN" : o.rec ? "SUGGESTED" : nil
                Button { withAnimation(.easeOut(duration: 0.15)) { focus = o.id } } label: {
                    HStack(spacing: 12) {
                        Text(Self.letter(o, in: d)).font(.system(size: S(24), weight: .black, design: .monospaced)).foregroundStyle(ink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.name(o)).font(.system(size: S(13), weight: on ? .bold : .semibold)).foregroundStyle(on ? ink : Brand.ink.opacity(0.85)).lineLimit(1)
                            if let mark {
                                Text(mark).font(.system(size: S(8.5), weight: .heavy, design: .monospaced)).tracking(0.8)
                                    .foregroundStyle(on ? ink.opacity(0.7) : chosen ? Brand.amber : mixed ? Brand.blue : Brand.blue.opacity(0.85))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: S(54))
                    .background(PixelBox(step: 3).fill(on ? Brand.amber : Brand.panel2))
                    .overlay(PixelBox(step: 3).stroke(on ? .clear : chosen ? Brand.amber : mixed ? Brand.blue : Brand.line2, lineWidth: chosen || mixed ? 1.5 : 1))
                    .contentShape(Rectangle())
                }.buttonStyle(SteerButton())
            }
        }
    }

    /// The option on the stage (choice card mockup, body A): its picture full width, then one strip under it with
    /// the name, the points, Open live, ‹ 1/2 › and the Choose button. No empty column beside the picture.
    private func stageView(_ o: BoardOption) -> some View {
        let chosen = d.multi ? draftPicks.contains(o.id) : draftPick == o.id
        let mixed = !d.multi && draftMix.contains(o.id)
        let pic = visual(o)
        let noted = !board.pins(d, option: o, picture: pic).isEmpty
        let i = d.options.firstIndex(of: o) ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if let v = pic {
                    BoardImage(dir: board.project.boardDir, path: v, height: S(380), fit: true,
                               onOpen: {
                                   // A prototype opens live (a picture zoom adds nothing); ⌘-click still opens the picture to pin a note.
                                   if o.proto != nil && !NSEvent.modifierFlags.contains(.command) { model.choiceLive = ChoiceLiveOpen(projectId: board.project.id, decision: d.id, option: o.id) } else { openPreview(v) }
                               }, openLabel: o.proto != nil ? "Open live" : "Preview")
                } else if o.mockHTML != nil || o.proto != nil {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black).frame(height: S(380))
                        .overlay(VStack(spacing: 8) { ProgressView().controlSize(.small); Text("Drawing the mockup…").font(.system(size: S(11))).foregroundStyle(Brand.mute) })
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black).frame(height: S(160))
                        .overlay(Text(Self.letter(o, in: d)).font(.system(size: S(80), weight: .black, design: .monospaced)).foregroundStyle(Brand.line2))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)

            Rectangle().fill(Brand.line).frame(height: 1)

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.name(o)).font(.system(size: S(15.5), weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { ForEach(o.points, id: \.self) { p in Text(p).lineLimit(1).fixedSize() } }
                        VStack(alignment: .leading, spacing: 4) { ForEach(o.points, id: \.self) { p in Text(p).fixedSize(horizontal: false, vertical: true) } }
                    }
                    .font(.system(size: S(12.5))).foregroundStyle(Brand.ink.opacity(0.88)).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    if o.mockHTML != nil || o.proto != nil { Button("Open it live") { model.choiceLive = ChoiceLiveOpen(projectId: board.project.id, decision: d.id, option: o.id) }.buttonStyle(.link).pointerStyle(.link) }
                    if d.options.count > 1 {
                        Button { focus = d.options[(i + d.options.count - 1) % d.options.count].id } label: { Image(systemName: "chevron.left") }.buttonStyle(SteerButton()).help("Previous option")
                        Text("\(i + 1) / \(d.options.count)").font(.system(size: S(11)).monospacedDigit()).foregroundStyle(Brand.mute)
                        Button { focus = d.options[(i + 1) % d.options.count].id } label: { Image(systemName: "chevron.right") }.buttonStyle(SteerButton()).help("Next option")
                    }
                }.font(.system(size: S(11.5))).foregroundStyle(Brand.cream).fixedSize()
                VStack(spacing: 6) {
                    PixelCTA(title: Self.chooseTitle(Self.letter(o, in: d), multi: d.multi, chosen: chosen, notes: noted),
                             icon: chosen ? "check" : "choice", selected: chosen) { choose(o) }
                        .help(chosen ? "Click again to unselect" : "Make this your answer")
                    if !d.multi, draftPick != nil, !chosen {
                        Button { toggleMix(o) } label: {
                            Text(mixed ? "✓ Blended in" : "+ Blend into my choice").font(.system(size: S(11.5), weight: .semibold))
                                .foregroundStyle(mixed ? Color.black : Brand.blue)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(mixed ? Brand.blue : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.blue.opacity(0.7)))
                        }.buttonStyle(SteerButton()).help("Take something from this option too; say what in the note")
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel2))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(chosen ? Brand.amber.opacity(0.8) : mixed ? Brand.blue.opacity(0.8) : Brand.line, lineWidth: chosen || mixed ? 1.5 : 1))
    }

    /// All options at once, one row each: a radio (or a checkbox for `multi`), letter, name, suggested; the points as
    /// bullets; the option's small mock as numbered steps. Click a row to choose it; "+ Blend in" on the others.
    /// Simple options side by side (up to 3 a row, same height): compared at a glance, not read down a list.
    private var optionList: some View {
        let per = d.options.count == 4 ? 2 : min(3, max(1, d.options.count))
        let rows = stride(from: 0, to: d.options.count, by: per).map { Array(d.options[$0..<min($0 + per, d.options.count)]) }
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row) { o in listCard(o) }
                    if row.count < per { ForEach(0..<(per - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) } }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One simple option (choice card mockup, consistent with the option bar): the pixel tab on top (big letter,
    /// name, suggested / your choice), the points and steps under it, flush left. Click anywhere to choose it.
    @ViewBuilder private func listCard(_ o: BoardOption) -> some View {
        let chosen = d.multi ? draftPicks.contains(o.id) : draftPick == o.id
        let mixed = !d.multi && draftMix.contains(o.id)
        let steps = Self.mockSteps(o)
        let ink = chosen ? Color(hex: 0x1a1200) : Brand.cream
        let mark = chosen ? (d.multi ? "✓ PICKED" : "✓ YOUR CHOICE") + (o.rec ? " · SUGGESTED" : "") : mixed ? "BLENDED IN" : o.rec ? "SUGGESTED" : nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(Self.letter(o, in: d)).font(.system(size: S(24), weight: .black, design: .monospaced)).foregroundStyle(ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.name(o)).font(.system(size: S(14), weight: .bold)).foregroundStyle(chosen ? ink : .white).lineLimit(2)
                    if let mark {
                        Text(mark).font(.system(size: S(8.5), weight: .heavy, design: .monospaced)).tracking(0.8).lineLimit(1)
                            .foregroundStyle(chosen ? ink.opacity(0.7) : mixed ? Brand.blue : Brand.blue.opacity(0.85))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: S(54))
            .background(PixelBox(step: 3).fill(chosen ? Brand.amber : Color.black.opacity(0.25)))
            .overlay(PixelBox(step: 3).stroke(chosen ? .clear : mixed ? Brand.blue : Brand.line2, lineWidth: mixed ? 1.5 : 1))

            VStack(alignment: .leading, spacing: 10) {
                if !o.points.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(o.points, id: \.self) { p in
                            Text(p).font(.system(size: S(12.5))).foregroundStyle(Brand.ink.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !steps.isEmpty {
                    // In a row with arrows when it fits, else one step per line.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                                if i > 0 { Image(systemName: "arrow.right").font(.system(size: S(9), weight: .bold)).foregroundStyle(Brand.mute) }
                                stepChip(s).fixedSize()
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                                HStack(spacing: 6) {
                                    Text("\(i + 1)").font(.system(size: S(9.5), weight: .heavy, design: .monospaced)).foregroundStyle(Brand.mute).frame(width: S(12))
                                    stepChip(s)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if !d.multi, draftPick != nil, !chosen {
                    Button { toggleMix(o) } label: {
                        Text(mixed ? "✓ Blended in" : "+ Blend in").font(.system(size: S(11), weight: .semibold))
                            .foregroundStyle(mixed ? Color.black : Brand.blue)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(mixed ? Brand.blue : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.blue.opacity(0.7)))
                    }.buttonStyle(SteerButton()).help("Take something from this option too; say what in the note")
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(8).padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(chosen ? Brand.amberDim.opacity(0.5) : Brand.panel2))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(chosen ? Brand.amber.opacity(0.8) : mixed ? Brand.blue.opacity(0.8) : Brand.line, lineWidth: chosen || mixed ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { choose(o) } }
        .pointerStyle(.link)
        .help(chosen ? "Click again to unselect" : "Make this your answer")
    }

    private func stepChip(_ s: String) -> some View {
        Text(s).font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.ink.opacity(0.85)).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.3)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.line2))
    }

    /// A simple option's mock as steps: each top-level line of text (`<div class='kr'>…</div>`, `<br>`) is one step.
    static func mockSteps(_ o: BoardOption) -> [String] {
        guard let h = o.mockHTML else { return [] }
        let split = h.replacingOccurrences(of: "</(div|li|p|tr)>|<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        let lines = BoardText.plain(split).replacingOccurrences(of: "**", with: "")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .map { $0.replacingOccurrences(of: #"^\d+\s*[·.)]\s*"#, with: "", options: .regularExpression) }   // the arrows give the order
        // A single glyph (✓ / ✎) is decoration, not a step.
        return lines.filter { $0.count > 2 }.prefix(5).map { $0.count > 46 ? String($0.prefix(45)) + "…" : $0 }
    }

    /// Your answer, in words, with the note and Done.
    /// Your answer (choice card mockup, answer A): one row. The note (at most 620 pt wide), then the one pixel CTA:
    /// Save while something changed, Build once saved; Discuss and Park together on the right, quiet.
    private func answerBar(_ decided: Bool) -> some View {
        let buildNext = decided && !changed && !board.isBuilt(d)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("YOUR ANSWER").font(Brand.label(9)).tracking(0.9).foregroundStyle(Brand.amber)
                Text(summary).font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(canSave ? Brand.cream : Brand.mute).lineLimit(1)
                if changed { Text("· not saved yet").font(.system(size: S(11))).foregroundStyle(Brand.amber) }
                if changed && (savedPick != nil || !savedNote.isEmpty || !savedPicks.isEmpty) {
                    Button("Undo") { draftPick = savedPick; draftPicks = savedPicks; draftMix = savedMix; draftNote = savedNote }
                        .buttonStyle(SteerButton()).font(.system(size: S(11))).foregroundStyle(Brand.mute)
                }
                Spacer()
            }
            HStack(alignment: .center, spacing: 12) {
                TextField(!draftMix.isEmpty ? "What to take from each? (e.g. A's layout with B's colours)" : draftPick == nil && draftPicks.isEmpty ? "None fits? Say it in your own words…" : "Add a note for Claude (optional)…", text: $draftNote, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: S(12.5))).lineLimit(1...6)
                    .focused($noteFocused)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(noteFocused ? Brand.amber.opacity(0.7) : Brand.line2))
                    .onSubmit { if NSEvent.modifierFlags.contains(.command) { done() } }
                    .frame(maxWidth: S(620))
                if buildNext {
                    PixelCTA(title: Self.buildTitle(d, board: board), color: Brand.claude, icon: "claude") { model.start(projectId: board.project.id, item: ref, intent: .build) }
                        .help("Start Claude on your answer")
                } else {
                    PixelCTA(title: decided && !changed ? "Saved" : Self.saveTitle(pick: d.multi ? !draftPicks.isEmpty : draftPick != nil, note: !draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                             icon: "check", shortcut: "⌘↩") { done() }
                        .disabled(!canSave || !changed)
                        .keyboardShortcut(.return, modifiers: noteFocused ? .command : [.command, .shift])
                        .help("Save your answer (⌘↩ while typing)")
                }
                Spacer(minLength: 0)
                ClaudeButton(title: "Discuss") { model.start(projectId: board.project.id, item: ref, intent: .look) }
                    .help("Talk this choice through with Claude")
                Button(board.isParked(d) ? "Recover" : "Park") { board.setParked(d, !board.isParked(d)) }
                    .buttonStyle(SteerButton()).font(.system(size: S(12))).foregroundStyle(Brand.mute)
                    .help(board.isParked(d) ? "Back to the open choices" : "Park for later")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.amberDim.opacity(canSave ? 0.55 : 0.25)))
    }

    private var summary: String {
        let L = { (id: String) in d.options.first { $0.id == id }.map { Self.letter($0, in: d) + " · " + Self.name($0) } ?? id }
        if d.multi { return draftPicks.isEmpty ? (draftNote.isEmpty ? "nothing picked yet" : "your own words") : d.options.filter { draftPicks.contains($0.id) }.map { L($0.id) }.joined(separator: ", ") }
        guard let p = draftPick else { return draftNote.isEmpty ? "nothing chosen yet" : "your own words" }
        let mix = d.options.filter { draftMix.contains($0.id) }.map { Self.letter($0, in: d) }
        return L(p) + (mix.isEmpty ? "" : "  + " + mix.joined(separator: " + "))
    }

    // MARK: Actions

    private func choose(_ o: BoardOption) {
        if d.multi { if draftPicks.contains(o.id) { draftPicks.remove(o.id) } else { draftPicks.insert(o.id) }; return }
        if draftPick == o.id { draftPick = nil; draftMix.removeAll() } else { draftPick = o.id; draftMix.remove(o.id) }
    }
    private func toggleMix(_ o: BoardOption) { if draftMix.contains(o.id) { draftMix.remove(o.id) } else { draftMix.insert(o.id) } }

    private func done() {
        guard canSave else { return }
        noteFocused = false
        if d.multi {
            board.setChoiceMulti(d, picks: d.options.map(\.id).filter(draftPicks.contains), note: draftNote)
            model.showToast("“\(d.title.prefix(48))” · \(draftPicks.count) picked")
        } else {
            let pick = draftPick ?? "__note"
            board.setChoice(d, pick: pick, note: draftNote, mix: d.options.map(\.id).filter { draftMix.contains($0) && $0 != pick })
            draftPick = pick
            model.showToast("“\(d.title.prefix(48))” · decided")
        }
        withAnimation(.easeOut(duration: 0.2)) { reopened = false }
    }

    // MARK: Helpers

    private var ref: ItemRef { var r = ItemRef(ref: "choice:" + d.id)!; r.title = d.title; r.area = d.areas.first; return r }

    /// "Choose A", or "Choose A + Notes" when notes are pinned on its picture: they go to Claude with the pick.
    static func chooseTitle(_ L: String, multi: Bool, chosen: Bool, notes: Bool) -> String {
        let t = chosen ? (multi ? "Picked" : "Your choice") : multi ? "Pick \(L)" : "Choose \(L)"
        return notes ? t + " + Notes" : t
    }

    /// The answer bar's save button: says what gets saved ("Save choice with note").
    static func saveTitle(pick: Bool, note: Bool) -> String {
        !pick && note ? "Save my answer" : note ? "Save choice with note" : "Save choice"
    }
    /// The build button names the saved answer: "Build A with note", "Build A + C", "Build my answer".
    static func buildTitle(_ d: BoardDecision, board: BoardStore) -> String {
        let v = board.verdict(d.id)
        let note = !v.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let ids: [String] = d.multi ? ((v.pick as? [String]) ?? []) : (v.pickString.map { [$0] + board.mix(d) } ?? [])
        let letters = d.options.filter { ids.contains($0.id) }.map { letter($0, in: d) }
        guard !letters.isEmpty else { return note ? "Build my answer" : "Build my pick" }
        return "Build " + letters.joined(separator: " + ") + (note ? " with note" : "")
    }

    /// "A · Typed blocks" → "A"; labels without a letter get one from their place.
    static func letter(_ o: BoardOption, in d: BoardDecision) -> String {
        let head = o.label.components(separatedBy: " · ").first ?? ""
        if head.count <= 2, o.label.contains(" · ") { return head }
        let i = d.options.firstIndex(of: o) ?? 0
        return String(UnicodeScalar(UInt8(65 + min(i, 25))))
    }
    static func name(_ o: BoardOption) -> String {
        let parts = o.label.components(separatedBy: " · ")
        return parts.count > 1 && parts[0].count <= 2 ? parts.dropFirst().joined(separator: " · ") : o.label
    }

    private func visual(_ o: BoardOption) -> String? {
        _ = snaps.version
        return o.shot ?? MockSnapshots.shared.picture(for: o, boardDir: board.project.boardDir)
    }
    private var images: [String] { d.gallery.map(\.img) + d.options.compactMap { visual($0) } }
    private func openPreview(_ img: String) {
        model.preview = PreviewState(projectId: board.project.id, ref: "choice:" + d.id, title: d.title,
                                     dir: board.project.boardDir, images: images, index: images.firstIndex(of: img) ?? 0, version: nil,
                                     startInNoteMode: NSEvent.modifierFlags.contains(.command),
                                     refresh: { [self] in images })
    }
}
