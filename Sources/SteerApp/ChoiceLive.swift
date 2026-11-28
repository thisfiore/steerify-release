import SwiftUI
import AppKit
import WebKit

// MARK: - A choice's prototypes, live and as big as the window
//
// "Open it live" on a choice: the prototype fills the window, big A / B / C tabs on top (← → or 1–4 switch at once,
// no click into the page first), and the option's title, pros and cons, Choose and the note float on the right.

struct ChoiceLiveOpen: Identifiable {
    let id = UUID()
    let projectId: String
    let decision: String
    var option: String          // option id, or "today"
}

/// A web view that never takes the keyboard: ← → stay with Steerify (the page still gets clicks and scrolling).
final class KeylessWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}

/// A click in the page that asks for a note: ⌘-click anywhere, or a plain tap on a scheme box (`.node`, `[data-note]`).
struct LiveNoteSpot: Equatable { let x: Double; let y: Double; let label: String }

struct ChoiceLiveWeb: NSViewRepresentable {
    let dir: String; let url: String
    var onNote: ((LiveNoteSpot) -> Void)? = nil
    /// Reports note clicks; a plain click elsewhere stays with the prototype (click-through, data-tap).
    static let script = """
        document.addEventListener('click', e => {
          const item = e.target.closest('.node,[data-note]');
          if (!e.metaKey && !item) return;
          e.preventDefault(); e.stopPropagation();
          const label = item ? ((item.dataset.note || item.querySelector('b')?.innerText || item.innerText) || '').trim().split('\\n')[0].slice(0, 60) : '';
          window.webkit.messageHandlers.steerNote.postMessage({ x: e.clientX / innerWidth, y: e.clientY / innerHeight, label });
        }, true);
        const st = document.createElement('style');
        st.textContent = '.node,[data-note]{cursor:copy}';
        document.documentElement.appendChild(st);
        """
    func makeNSView(context: Context) -> KeylessWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        cfg.userContentController.add(context.coordinator, name: "steerNote")
        let w = KeylessWebView(frame: .zero, configuration: cfg)
        w.setValue(false, forKey: "drawsBackground")
        load(w, context.coordinator)
        return w
    }
    func updateNSView(_ w: KeylessWebView, context: Context) {
        context.coordinator.onNote = onNote
        if context.coordinator.url != url { load(w, context.coordinator) }
    }
    static func dismantleNSView(_ w: KeylessWebView, coordinator: Coord) {
        w.configuration.userContentController.removeScriptMessageHandler(forName: "steerNote")
    }
    /// Test hook (--live-tap): the open live page, to fire a click inside it.
    nonisolated(unsafe) static weak var current: WKWebView?
    private func load(_ w: WKWebView, _ c: Coord) {
        Self.current = w
        c.url = url
        let base = URL(fileURLWithPath: dir, isDirectory: true)
        w.loadFileURL(MockSnapshots.protoURL(url, base: base), allowingReadAccessTo: base)
    }
    func makeCoordinator() -> Coord { Coord() }
    final class Coord: NSObject, WKScriptMessageHandler {
        var url = ""
        var onNote: ((LiveNoteSpot) -> Void)?
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let b = m.body as? [String: Any], let x = (b["x"] as? NSNumber)?.doubleValue, let y = (b["y"] as? NSNumber)?.doubleValue else { return }
            let spot = LiveNoteSpot(x: max(0, min(1, x)), y: max(0, min(1, y)), label: b["label"] as? String ?? "")
            DispatchQueue.main.async { self.onNote?(spot) }
        }
    }
}

struct ChoiceLiveViewer: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    @State var open: ChoiceLiveOpen
    @State private var note = ""
    @State private var showPanel = true
    /// The panel opens for a moment on each option, then folds to one line so it never hides the screen; hover opens it.
    @State private var hovering = false
    @State private var fresh = true
    @State private var freshTask: Task<Void, Never>?
    @State private var hoverTask: Task<Void, Never>?
    /// Always open now that it sits bottom right (it hid the screen only at the top); I hides it.
    private var expanded: Bool { true }
    @FocusState private var focused: Bool
    @FocusState private var noteFocused: Bool
    /// A note being written on a spot of the prototype (⌘-click, or a tap on a scheme box).
    @State private var spot: LiveNoteSpot?
    @State private var spotText = ""
    @FocusState private var spotFocused: Bool

    private var d: BoardDecision? { board.decisions.first { $0.id == open.decision } }

    /// Tabs: Today (when the prototype has it) then every option with a prototype or a mock.
    private func tabs(_ d: BoardDecision) -> [String] {
        let hasToday = d.options.first(where: { $0.proto != nil }).flatMap { o -> Bool? in
            let file = (board.project.boardDir as NSString).appendingPathComponent(String(o.proto!.split(separator: "?")[0]))
            return (try? String(contentsOfFile: file, encoding: .utf8))?.contains("data-v=\"today\"")
        } ?? false
        return (hasToday ? ["today"] : []) + d.options.filter { $0.proto != nil || $0.mockHTML != nil }.map(\.id)
    }
    private func url(_ d: BoardDecision, _ tab: String) -> String? {
        if tab == "today", let p = d.options.first(where: { $0.proto != nil })?.proto {
            return String(p.split(separator: "?")[0]) + "?v=today&bare"
        }
        guard let o = d.options.first(where: { $0.id == tab }), let p = o.proto else { return nil }
        return p + (p.contains("?") ? "&" : "?") + "bare"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea().onTapGesture { close() }
            if let d {
                let list = tabs(d)
                VStack(spacing: 0) {
                    header(d, list)
                    // Details float at the bottom right: the top and the middle of the screen stay visible.
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let u = url(d, open.option) {
                                GeometryReader { g in
                                    ZStack(alignment: .topLeading) {
                                        ChoiceLiveWeb(dir: board.project.boardDir, url: u, onNote: { s in spot = s; spotText = ""; spotFocused = true })
                                        notesLayer(d, size: g.size)
                                    }
                                }
                            } else if let o = d.options.first(where: { $0.id == open.option }) {
                                MockView(dir: board.project.boardDir, option: o)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(14)
                        if showPanel && expanded && spot == nil, let o = d.options.first(where: { $0.id == open.option }) {
                            panel(d, o).padding(.bottom, 26).padding(.trailing, 26).transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if showPanel, open.option == "today", spot == nil { todayPanel.padding(26) }
                    }
                }
                .background(Brand.bg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.line2))
                .padding(.horizontal, 18).padding(.vertical, 14)
            }
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onChange(of: open.option) { _, _ in showFresh() }
        .onAppear {
            showFresh()
            focused = true
            note = d.map { board.verdict($0.id).note } ?? ""
        }
        .onKeyPress(.escape) {
            if spot != nil { spot = nil; focused = true } else if noteFocused { noteFocused = false; focused = true } else { close() }
            return .handled
        }
        .onKeyPress(.leftArrow) { if noteFocused || spotFocused { return .ignored }; step(-1); return .handled }
        .onKeyPress(.rightArrow) { if noteFocused || spotFocused { return .ignored }; step(1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "1234i")) { k in
            if noteFocused || spotFocused { return .ignored }
            if k.characters == "i" { withAnimation(.easeOut(duration: 0.15)) { showPanel.toggle() }; return .handled }
            guard let d, let n = Int(k.characters), tabs(d).indices.contains(n - 1) else { return .ignored }
            open.option = tabs(d)[n - 1]; return .handled
        }
    }

    // MARK: Pieces

    private func header(_ d: BoardDecision, _ list: [String]) -> some View {
        HStack(spacing: 14) {
            Text(d.title).font(.system(size: S(14), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, t in
                    let on = open.option == t
                    let o = d.options.first { $0.id == t }
                    Button { open.option = t } label: {
                        // The pixel CTA's font and corners (design system: one pixel button for every main action).
                        HStack(spacing: 7) {
                            Text(t == "today" ? "TODAY" : DecisionCard.letter(o!, in: d))
                                .font(.system(size: S(t == "today" ? 12 : 17), weight: .black, design: .monospaced)).tracking(1)
                            if o?.rec == true {
                                Text("SUGGESTED").font(.system(size: S(8.5), weight: .bold, design: .monospaced)).tracking(0.6).opacity(0.75)
                                    .fixedSize()
                            }
                        }
                        .lineLimit(1).fixedSize()
                        .foregroundStyle(on ? Color(hex: 0x1a1200) : t == "today" ? Brand.blue : Brand.cream)
                        .frame(minWidth: S(48), minHeight: S(34)).padding(.horizontal, 12)
                        .background(PixelBox(step: 2).fill(on ? (t == "today" ? Brand.blue : Brand.amber) : Brand.panel2))
                        .overlay(PixelBox(step: 2).stroke(on ? .clear : Brand.line2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("\(i + 1) · \(t == "today" ? "how it is now" : o.map(DecisionCard.name) ?? "")")
                }
            }
            Spacer(minLength: 12)
            if showPanel, let o = d.options.first(where: { $0.id == open.option }) {
                compactPanel(d, o, (board.verdict(d.id).pick as? String) == o.id && board.isDecided(d))
            }
            Text("← →").font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.mute)
            Button { withAnimation(.easeOut(duration: 0.15)) { showPanel.toggle() } } label: { Image(systemName: "sidebar.right") }
                .foregroundStyle(showPanel ? Brand.amber : Brand.cream).help("Show / hide the details (I)")
            Button { close() } label: { Image(systemName: "xmark") }.help("Close (Esc)")
        }
        .buttonStyle(SteerButton()).foregroundStyle(Brand.cream)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Brand.panel)
    }

    private var todayPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.blue)
            Text("How it is now. → for the options.").font(.system(size: S(12.5))).foregroundStyle(Brand.ink)
        }
        .padding(14).frame(width: S(300), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.panel.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.line2))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
    }

    /// The option's facts and the answer, floating over the prototype.
    private func panel(_ d: BoardDecision, _ o: BoardOption) -> some View {
        let v = board.verdict(d.id)
        let picked = (v.pick as? String) == o.id && board.isDecided(d)
        return fullPanel(d, o, picked).onHover(perform: hover)
    }

    /// Hover on the strip or the panel keeps it open; leaving closes it after a beat (room to move between them).
    private func hover(_ h: Bool) {
        hoverTask?.cancel()
        if h { withAnimation(.easeOut(duration: 0.15)) { hovering = true }; return }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.2)) { hovering = false } }
        }
    }

    private func compactPanel(_ d: BoardDecision, _ o: BoardOption, _ picked: Bool) -> some View {
        let pros = o.points.filter { $0.hasPrefix("✓") }.count, cons = o.points.filter { $0.hasPrefix("✕") }.count
        return HStack(spacing: 10) {
            Text(DecisionCard.letter(o, in: d)).font(.system(size: S(15), weight: .heavy, design: .rounded)).foregroundStyle(Brand.amber)
            Text(DecisionCard.name(o)).font(.system(size: S(12.5), weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if pros + cons > 0 {
                Text("✓\(pros)").font(.system(size: S(11), weight: .bold)).foregroundStyle(Brand.green)
                Text("✕\(cons)").font(.system(size: S(11), weight: .bold)).foregroundStyle(Brand.red)
            }
            PixelCTA(title: picked ? "Your choice" : "Choose \(DecisionCard.letter(o, in: d))", small: true,
                     icon: picked ? "check" : "choice", selected: picked) { choose(d, o) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Brand.panel.opacity(0.95)))
        .overlay(Capsule().stroke(Brand.line2))
        .onHover(perform: hover)
        .help("Hover for pros, cons, note and Choose")
    }

    private func fullPanel(_ d: BoardDecision, _ o: BoardOption, _ picked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("OPTION " + DecisionCard.letter(o, in: d)).font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute)
                if o.rec { Pill(text: "suggested", color: Brand.blue) }
                if picked { Pill(text: "your choice", color: Brand.amber) }
            }
            Text(DecisionCard.name(o)).font(.system(size: S(18), weight: .bold)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(o.points, id: \.self) { p in
                    let pro = p.hasPrefix("✓"), con = p.hasPrefix("✕")
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(pro ? "✓" : con ? "✕" : "•").font(.system(size: S(12.5), weight: .bold))
                            .foregroundStyle(pro ? Brand.green : con ? Brand.red : Brand.mute)
                        Text(pro || con ? String(p.dropFirst()).trimmingCharacters(in: .whitespaces) : p)
                            .font(.system(size: S(13))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Divider().overlay(Brand.line)
            TextField("Note for Claude (optional)", text: $note, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: S(12.5))).lineLimit(2...4)
                .padding(8).background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel2))
                .focused($noteFocused)
            PixelCTA(title: picked ? "Keep \(DecisionCard.letter(o, in: d))" : "Choose \(DecisionCard.letter(o, in: d))",
                     icon: picked ? "check" : "choice", fullWidth: true) { choose(d, o) }
        }
        .padding(16).frame(width: S(320), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.panel.opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.line2))
        .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
    }

    /// The page a note is pinned on (the option's prototype, without the viewer's `bare`).
    private func pinImg(_ d: BoardDecision) -> String? {
        guard let u = url(d, open.option) else { return nil }
        return u.replacingOccurrences(of: "&bare", with: "").replacingOccurrences(of: "?bare", with: "")
    }

    /// Notes already pinned on this option's prototype (numbered), and the one being written.
    @ViewBuilder private func notesLayer(_ d: BoardDecision, size: CGSize) -> some View {
        let img = pinImg(d) ?? ""
        let pins = board.pins("choice:" + d.id).filter { $0.img == img }
        ForEach(Array(pins.enumerated()), id: \.offset) { i, p in
            pinMark(i + 1).position(x: p.x * size.width, y: p.y * size.height).help(p.note)
        }
        if let s = spot {
            pinMark(pins.count + 1, live: true).position(x: s.x * size.width, y: s.y * size.height)
            spotEditor(d, s)
                .frame(width: S(300))
                .position(x: min(max(s.x * size.width + S(165), S(160)), size.width - S(160)),
                          y: min(max(s.y * size.height + S(60), S(60)), size.height - S(70)))
        }
    }

    private func pinMark(_ n: Int, live: Bool = false) -> some View {
        Text("\(n)").font(.system(size: S(10.5), weight: .heavy)).foregroundStyle(Color(hex: 0x1a1204))
            .frame(width: S(20), height: S(20)).background(Circle().fill(Brand.amber))
            .overlay(Circle().stroke(Brand.amber.opacity(live ? 0.9 : 0.35), lineWidth: live ? 4 : 3).padding(-2))
            .allowsHitTesting(false)
    }

    private func spotEditor(_ d: BoardDecision, _ s: LiveNoteSpot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.label.isEmpty ? "NOTE HERE" : "NOTE ON “\(s.label.uppercased())”").font(Brand.label(8.5)).tracking(0.7).foregroundStyle(Brand.amber).lineLimit(1)
            TextField("What should change?", text: $spotText, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: S(12.5))).lineLimit(1...4)
                .padding(8).background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel2))
                .focused($spotFocused)
                .onSubmit { saveSpot(d) }
            HStack {
                Button("Save note") { saveSpot(d) }.disabled(spotText.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") { spot = nil; focused = true }.foregroundStyle(Brand.mute)
                Spacer()
                Text("⏎").font(.system(size: S(10), design: .monospaced)).foregroundStyle(Brand.mute)
            }
            .buttonStyle(SteerButton()).font(.system(size: S(11.5)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.amber.opacity(0.6)))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
    }

    private func saveSpot(_ d: BoardDecision) {
        let t = spotText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s = spot, !t.isEmpty, let img = pinImg(d) else { return }
        let text = s.label.isEmpty ? t : "On “\(s.label)”: " + t
        board.addPin("choice:" + d.id, img: img, x: s.x, y: s.y, note: text, option: open.option == "today" ? nil : open.option)
        model.showToast("Note pinned on \(open.option == "today" ? "Today" : "option " + open.option)", projectId: board.project.id, ref: "choice:" + d.id)
        spot = nil; spotText = ""; focused = true
    }

    private func choose(_ d: BoardDecision, _ o: BoardOption) {
        board.setChoice(d, pick: o.id, note: note)
        model.showToast("You chose \(DecisionCard.letter(o, in: d)) · \(DecisionCard.name(o))", projectId: board.project.id, ref: "choice:" + d.id)
        close()
    }

    private func showFresh() {
        withAnimation(.easeOut(duration: 0.15)) { fresh = true }
        freshTask?.cancel()
        freshTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.25)) { fresh = false } }
        }
    }

    private func step(_ dir: Int) {
        guard let d else { return }
        let list = tabs(d)
        guard let i = list.firstIndex(of: open.option) else { return }
        open.option = list[(i + dir + list.count) % list.count]
    }
    private func close() { model.choiceLive = nil }
}
