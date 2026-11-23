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
                HStack(spacing: 6) {
                    if board.isBuilt(d) {
                        Label("Built", systemImage: "checkmark").font(.system(size: S(11.5), weight: .medium)).foregroundStyle(Brand.green)
                    } else {
                        ActionButton(title: "Build my pick", primary: true) { model.start(projectId: board.project.id, item: ref, intent: .build) }
                    }
                    Button("Change") { load(); withAnimation(.easeOut(duration: 0.18)) { reopened = true } }
                        .buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
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

            HStack(spacing: 6) {
                if decided && !board.isBuilt(d) { ActionButton(title: "Build my pick", primary: true) { model.start(projectId: board.project.id, item: ref, intent: .build) } }
                ClaudeButton(title: "Ask Claude") { model.start(projectId: board.project.id, item: ref, intent: .look) }
                Spacer()
                Button(board.isParked(d) ? "Recover" : "Park for later") { board.setParked(d, !board.isParked(d)) }
                    .buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
            }
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

    /// One tab per option: letter, short name, a mark when it is suggested / chosen / blended in.
    private var optionTabs: some View {
        HStack(spacing: 8) {
            ForEach(d.options) { o in
                let on = stage?.id == o.id
                let chosen = d.multi ? draftPicks.contains(o.id) : draftPick == o.id
                let mixed = !d.multi && draftMix.contains(o.id)
                Button { withAnimation(.easeOut(duration: 0.15)) { focus = o.id } } label: {
                    HStack(spacing: 8) {
                        Text(Self.letter(o, in: d)).font(.system(size: S(15), weight: .heavy, design: .rounded))
                            .foregroundStyle(chosen ? Color(hex: 0x1a1200) : on ? Brand.cream : Brand.mute)
                            .frame(width: S(28), height: S(28))
                            .background(RoundedRectangle(cornerRadius: 7).fill(chosen ? Brand.amber : mixed ? Brand.blue.opacity(0.85) : on ? Brand.line2 : Brand.panel2))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.name(o)).font(.system(size: S(12), weight: on ? .semibold : .medium)).foregroundStyle(on ? .white : Brand.ink.opacity(0.8)).lineLimit(1)
                            Text(chosen ? (d.multi ? "picked" : "your choice") : mixed ? "blended in" : o.rec ? "suggested" : " ")
                                .font(.system(size: S(10), weight: .semibold)).foregroundStyle(chosen ? Brand.amber : mixed ? Brand.blue : Brand.blue.opacity(0.8))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 9).fill(on ? Brand.panel2 : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? Brand.cream.opacity(0.45) : Brand.line, lineWidth: on ? 1.5 : 1))
                    .contentShape(Rectangle())
                }.buttonStyle(SteerButton())
            }
        }
    }

    /// The option on the stage: its picture big, what it means, one button to choose it.
    private func stageView(_ o: BoardOption) -> some View {
        let chosen = d.multi ? draftPicks.contains(o.id) : draftPick == o.id
        let mixed = !d.multi && draftMix.contains(o.id)
        let pic = visual(o)
        let noted = !board.pins(d, option: o, picture: pic).isEmpty
        let i = d.options.firstIndex(of: o) ?? 0
        return HStack(alignment: .top, spacing: 16) {
            Group {
                if let v = pic {
                    BoardImage(dir: board.project.boardDir, path: v, height: S(360), fit: true, onOpen: { openPreview(v) })
                } else if o.mockHTML != nil || o.proto != nil {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black).frame(height: S(360))
                        .overlay(VStack(spacing: 8) { ProgressView().controlSize(.small); Text("Drawing the mockup…").font(.system(size: S(11))).foregroundStyle(Brand.mute) })
                } else {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black).frame(height: S(200))
                        .overlay(Text(Self.letter(o, in: d)).font(.system(size: S(90), weight: .heavy, design: .rounded)).foregroundStyle(Brand.line2))
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("OPTION \(Self.letter(o, in: d))").font(Brand.label(9.5)).tracking(1).foregroundStyle(Brand.mute)
                    if o.rec { Pill(text: "suggested", color: Brand.blue) }
                }
                Text(Self.name(o)).font(.system(size: S(15.5), weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(o.points, id: \.self) { p in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Circle().fill(Brand.cream.opacity(0.5)).frame(width: 4, height: 4).offset(y: -2)
                            Text(p).font(.system(size: S(12.5))).foregroundStyle(Brand.ink.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .textSelection(.enabled)
                Spacer(minLength: 4)
                Button { choose(o) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: chosen ? "checkmark.circle.fill" : "hand.point.up.left.fill").font(.system(size: S(12), weight: .bold))
                        Text(Self.chooseTitle(Self.letter(o, in: d), multi: d.multi, chosen: chosen, notes: noted)).font(.system(size: S(13.5), weight: .bold))
                    }
                    .foregroundStyle(chosen ? Brand.amber : Color(hex: 0x1a1200))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 8).fill(chosen ? Brand.amberDim : Brand.amber))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.amber, lineWidth: chosen ? 1.5 : 0))
                }.buttonStyle(SteerButton()).help(chosen ? "Click again to unselect" : "Make this your answer")
                if !d.multi, draftPick != nil, !chosen {
                    Button { toggleMix(o) } label: {
                        Text(mixed ? "✓ Blended into your choice" : "+ Blend into my choice").font(.system(size: S(12), weight: .semibold))
                            .foregroundStyle(mixed ? Color.black : Brand.blue)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(mixed ? Brand.blue : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.blue.opacity(0.7)))
                    }.buttonStyle(SteerButton()).help("Take something from this option too; say what in the note")
                }
                HStack(spacing: 10) {
                    if o.mockHTML != nil || o.proto != nil { Button("Open it live") { mock = o }.buttonStyle(.link).pointerStyle(.link) }
                    Spacer()
                    if d.options.count > 1 {
                        Button { focus = d.options[(i + d.options.count - 1) % d.options.count].id } label: { Image(systemName: "chevron.left") }.buttonStyle(SteerButton()).help("Previous option")
                        Text("\(i + 1) / \(d.options.count)").font(.system(size: S(11)).monospacedDigit()).foregroundStyle(Brand.mute)
                        Button { focus = d.options[(i + 1) % d.options.count].id } label: { Image(systemName: "chevron.right") }.buttonStyle(SteerButton()).help("Next option")
                    }
                }.font(.system(size: S(11.5))).foregroundStyle(Brand.cream)
            }
            .frame(width: S(270))
            .frame(minHeight: S(200), alignment: .top)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel2))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(chosen ? Brand.amber.opacity(0.8) : mixed ? Brand.blue.opacity(0.8) : Brand.line, lineWidth: chosen || mixed ? 1.5 : 1))
    }

    /// All options at once, one row each: a radio (or a checkbox for `multi`), letter, name, suggested; the points as
    /// bullets; the option's small mock as numbered steps. Click a row to choose it; "+ Blend in" on the others.
    private var optionList: some View {
        VStack(spacing: 8) {
            ForEach(d.options) { o in
                let chosen = d.multi ? draftPicks.contains(o.id) : draftPick == o.id
                let mixed = !d.multi && draftMix.contains(o.id)
                let steps = Self.mockSteps(o)
                HStack(alignment: .top, spacing: 12) {
                    Group {
                        if d.multi {
                            Image(systemName: chosen ? "checkmark.square.fill" : "square")
                        } else {
                            Image(systemName: chosen ? "largecircle.fill.circle" : mixed ? "plus.circle.fill" : "circle")
                        }
                    }
                    .font(.system(size: S(17), weight: .medium))
                    .foregroundStyle(chosen ? Brand.amber : mixed ? Brand.blue : Brand.mute)
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(Self.letter(o, in: d)).font(.system(size: S(12), weight: .heavy, design: .rounded))
                                .foregroundStyle(chosen ? Color(hex: 0x1a1200) : Brand.cream)
                                .frame(width: S(22), height: S(22))
                                .background(RoundedRectangle(cornerRadius: 6).fill(chosen ? Brand.amber : mixed ? Brand.blue.opacity(0.85) : Brand.line2))
                            Text(Self.name(o)).font(.system(size: S(14), weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                            if o.rec { Pill(text: "suggested", color: Brand.blue) }
                            if chosen { Pill(text: d.multi ? "picked" : "your choice", color: Brand.amber) }
                            if mixed { Pill(text: "blended in", color: Brand.blue) }
                            Spacer(minLength: 0)
                        }
                        if !o.points.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(o.points, id: \.self) { p in
                                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                                        Circle().fill(Brand.cream.opacity(0.5)).frame(width: 4, height: 4).offset(y: -2)
                                        Text(p).font(.system(size: S(12.5))).foregroundStyle(Brand.ink.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                                    }
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
                    }
                    if !d.multi, draftPick != nil, !chosen {
                        Button { toggleMix(o) } label: {
                            Text(mixed ? "✓ Blended in" : "+ Blend in").font(.system(size: S(11), weight: .semibold))
                                .foregroundStyle(mixed ? Color.black : Brand.blue)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(mixed ? Brand.blue : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.blue.opacity(0.7)))
                        }.buttonStyle(SteerButton()).help("Take something from this option too; say what in the note")
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(chosen ? Brand.amberDim.opacity(0.6) : Brand.panel2))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(chosen ? Brand.amber.opacity(0.8) : mixed ? Brand.blue.opacity(0.8) : Brand.line, lineWidth: chosen || mixed ? 1.5 : 1))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { choose(o) } }
                .pointerStyle(.link)
                .help(chosen ? "Click again to unselect" : "Make this your answer")
            }
        }
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
    private func answerBar(_ decided: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("YOUR ANSWER").font(Brand.label(9)).tracking(0.9).foregroundStyle(Brand.amber)
                Text(summary).font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(canSave ? Brand.cream : Brand.mute).lineLimit(1)
                Spacer()
            }
            TextField(!draftMix.isEmpty ? "What to take from each? (e.g. A's layout with B's colours)" : draftPick == nil && draftPicks.isEmpty ? "None fits? Say it in your own words…" : "Anything to add for Claude? (optional)", text: $draftNote, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: S(12.5))).lineLimit(1...6)
                .focused($noteFocused)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(noteFocused ? Brand.amber.opacity(0.7) : Brand.line2))
                .onSubmit { if NSEvent.modifierFlags.contains(.command) { done() } }
            HStack(spacing: 8) {
                Button(action: done) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: S(11), weight: .bold))
                        Text(decided && !changed ? "Decided" : "Done").font(.system(size: S(13), weight: .bold))
                    }
                    .foregroundStyle(canSave && changed ? Color(hex: 0x1a1200) : Brand.mute)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(canSave && changed ? Brand.amber : Brand.panel2))
                }
                .buttonStyle(SteerButton()).disabled(!canSave || !changed)
                .keyboardShortcut(.return, modifiers: noteFocused ? .command : [.command, .shift])
                .help("Save your answer (⌘↩ while typing)")
                Text(changed ? "Not saved yet" : decided ? "Saved · Claude can build it" : "Choose an option or write your answer").font(.system(size: S(11))).foregroundStyle(changed ? Brand.amber : Brand.mute)
                Spacer()
                if changed && (savedPick != nil || !savedNote.isEmpty || !savedPicks.isEmpty) {
                    Button("Undo changes") { draftPick = savedPick; draftPicks = savedPicks; draftMix = savedMix; draftNote = savedNote }
                        .buttonStyle(SteerButton()).font(.system(size: S(11))).foregroundStyle(Brand.mute)
                }
            }
        }
        .padding(12)
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
