import SwiftUI
import SwiftTerm
import AppKit

// MARK: - Terminal overlay (choice terminal-overlay-look, option A, from request r261125-112354)
//
// ① A recap card on top of a Claude session's terminal: a title and two bullets of where the session is, made on the
//   Mac from the latest turns (Apple Intelligence when on, else Claude's own last words). It shows when you come back
//   to a session you left more than 5 minutes ago (switching sessions or coming back to the app), refreshes after
//   every turn, and fades on the first key you type (or ✕).
// ② Your 3 latest screenshots (last hour) float above the prompt: one click pastes the file, like a drop.
// Both can be turned off in Settings → Behaviour.

struct SessionRecap: Equatable {
    let title: String
    let bullets: [String]
    let ai: Bool
    let at: Date?
}

enum SessionRecaps {
    nonisolated(unsafe) private static var memoStore: [String: SessionRecap] = [:]
    private static let memoLock = NSLock()
    private static func memo(_ k: String) -> SessionRecap? { memoLock.lock(); defer { memoLock.unlock() }; return memoStore[k] }
    private static func memo(_ k: String, _ v: SessionRecap) { memoLock.lock(); memoStore[k] = v; memoLock.unlock() }

    /// Title + 2 bullets of the session's latest turns; nil when there is no transcript or nothing said yet.
    static func recap(_ claudeId: String) async -> SessionRecap? {
        guard let url = SessionSummaries.transcript(claudeId) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int) ?? 0
        let at = attrs?[.modificationDate] as? Date
        let key = "recap2|\(claudeId)|\(size / 2048)"          // a new recap every ~2 KB of conversation (each turn)
        if let m = memo(key) { return m }
        if let c = LocalAI.cached(key), let r = parse(c, at: at) { memo(key, r); return r }
        guard let x = await Task.detached(priority: .utility, operation: { SessionSummaries.extract(url) }).value else { return nil }
        var parts: [String] = []
        if let a = realAsk(x.asks) { parts.append("LATEST ASK: " + String(a.prefix(700))) }
        for r in x.replies.suffix(3) { parts.append("CLAUDE: " + String(r.prefix(1400))) }
        if let ai = await LocalAI.ask(key: key,
            instructions: """
            You recap a Claude Code work session for its owner, who is coming back to it and needs the context at a glance.
            Answer in exactly three lines, plain text, no markdown:
            TITLE: the state of the work now, max 9 words, specific (e.g. "Overlay built, waiting on your test"), never "Session recap"
            - what was just done, concrete, max 14 words
            - what it waits on or the next step, max 14 words
            """,
            prompt: parts.joined(separator: "\n\n")), let r = parse(ai, at: at) {
            memo(key, r); return r
        }
        guard let r = fallback(x, at: at) else { return nil }
        memo(key, r); return r
    }

    /// "TITLE: …\n- …\n- …" → a recap (tolerant: a title line without the label, bullets with • or -).
    static func parse(_ s: String, at: Date?, ai: Bool = true) -> SessionRecap? {
        let lines = s.replacingOccurrences(of: "**", with: "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        let title = first.replacingOccurrences(of: "^(TITLE|Title|title)\\s*:\\s*", with: "", options: .regularExpression)
        let bullets = lines.dropFirst().map { $0.replacingOccurrences(of: "^([-•*]|\\d+[.)])\\s*", with: "", options: .regularExpression)
                .replacingOccurrences(of: "^(CLAUDE|LATEST ASK|Claude|Latest ask)\\s*:\\s*", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }.prefix(2)
        guard !title.isEmpty, !bullets.isEmpty else { return nil }
        // A generic title ("Session recap") says nothing: the first bullet takes its place.
        if title.range(of: "^(session\\s+)?(recap|summary)\\.?$", options: [.regularExpression, .caseInsensitive]) != nil {
            return SessionRecap(title: clip(bullets.first!, 80), bullets: Array(bullets.dropFirst()).map { clip($0, 130) }, ai: ai, at: at)
        }
        return SessionRecap(title: clip(title, 80), bullets: bullets.map { clip($0, 130) }, ai: ai, at: at)
    }

    /// Without the on-device model: the first lines of Claude's last reply, and what you last asked.
    static func fallback(_ x: (asks: [String], replies: [String]), at: Date?) -> SessionRecap? {
        var lines: [String] = []
        if let r = x.replies.last {
            let t = r.replacingOccurrences(of: "\\*\\*|`|^#+ ", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
            lines = t.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("|") && !$0.hasPrefix("```") }
                .map { $0.replacingOccurrences(of: "^([-•*]|\\d+[.)])\\s*", with: "", options: .regularExpression) }
        }
        if let a = realAsk(x.asks) { lines.append("You asked: " + SessionSummaries.plain(a, max: 110)) }
        guard var title = lines.first else { return nil }
        // The first sentence only: a title cut mid-word ("I'll …") reads badly.
        if let r = title.range(of: "[.!?:](\\s|$)", options: .regularExpression), title.distance(from: title.startIndex, to: r.lowerBound) >= 12 {
            title = String(title[..<r.lowerBound])
        }
        let bullets = Array(lines.dropFirst().prefix(2))
        guard !bullets.isEmpty else { return nil }
        return SessionRecap(title: clip(title, 80), bullets: bullets.map { clip($0, 130) }, ai: false, at: at)
    }

    /// The last thing you typed, not a pasted-image marker ("[Image: original …]", "[Image #1]").
    static func realAsk(_ asks: [String]) -> String? {
        asks.reversed().lazy.map { $0.replacingOccurrences(of: "\\[Image[^\\]]*\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) }.first { $0.count >= 4 }
    }

    private static func clip(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n - 1)) + "…" : s }
}

/// When each session was last on screen, and when the app was left: "coming back" = away for more than 5 minutes.
@MainActor
enum RecapAway {
    static let after: TimeInterval = 5 * 60
    static var lastSeen: [UUID: Date] = [:]
    static var appLeft: Date?
    /// Screenshots you closed (✕) per session: hidden until a newer one lands.
    static var shotsDismissed: [UUID: Date] = [:]
    static var pasted: [UUID: Set<URL>] = [:]
}

struct TerminalOverlayLayer: View {
    @ObservedObject var session: TerminalSession
    @AppStorage(Prefs.terminalOverlay, store: Prefs.store) private var on = true

    @State private var recap: SessionRecap?
    @State private var showRecap = false
    @State private var keyMonitor: Any?
    @State private var shots: [URL] = []
    @State private var thumbs: [URL: NSImage] = [:]
    @State private var shotWatch: DispatchSourceFileSystemObject?
    @State private var tick = 0
    @State private var promptRows: Int?     // rows from the prompt box's top rule to the bottom (grows as you type)

    var body: some View {
        GeometryReader { geo in
            if on, session.kind == .claude {
                // As many screenshots as fit the terminal's width (it can be a narrow column beside the board).
                let fit: Int = max(1, Int((geo.size.width - 28 + 8) / (S(92) + 8)))
                let pad: CGFloat = bottomPad(geo.size.height)
                VStack(spacing: 0) {
                    if showRecap, let r = recap { card(r).transition(.opacity.combined(with: .move(edge: .top))) }
                    Spacer(minLength: 0)
                    if !visibleShots.isEmpty { shotsRow(Array(visibleShots.prefix(fit))).transition(.opacity) }
                }
                .padding(.horizontal, 14).padding(.top, 10)
                .padding(.bottom, pad)
                .animation(.easeOut(duration: 0.12), value: promptRows)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.2), value: showRecap)
        .animation(.easeOut(duration: 0.2), value: visibleShots)
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            guard on, !visibleShots.isEmpty, let t = session.view as? SteerTerminalView else { return }
            let n = Self.promptRows(t.terminalStateSnapshot().visibleRows.map(\.text))
            if n != promptRows { promptRows = n }
        }
        .onAppear { appeared() }
        .onDisappear { disappeared() }
        .onChange(of: session.status) { _, s in if s == .idle || s == .waiting { Task { await load() } } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in RecapAway.appLeft = Date() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if let left = RecapAway.appLeft, Date().timeIntervalSince(left) > RecapAway.after { comeBack() }
            loadShots()
        }
    }

    // MARK: ① Recap

    private func card(_ r: SessionRecap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WHERE THIS SESSION IS · \(session.title.uppercased())")
                .font(Brand.label(8.5)).tracking(1.1).foregroundStyle(Brand.amber).lineLimit(1)
            Text(r.title).font(.system(size: S(14), weight: .semibold)).foregroundStyle(Brand.cream).lineLimit(2)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(r.bullets, id: \.self) { b in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(Brand.mute)
                        Text(b).foregroundStyle(Brand.ink).lineLimit(2)
                    }
                    .font(.system(size: S(12.5)))
                }
            }
            HStack {
                Spacer()
                Text(age(r)).font(.system(size: S(10))).foregroundStyle(Brand.mute)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x171a20).opacity(0.97)))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9).fill(Brand.amber).frame(width: 3) }
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.line2))
        .overlay(alignment: .topTrailing) {
            Button { hideRecap() } label: { Image(systemName: "xmark").font(.system(size: S(9), weight: .bold)) }
                .buttonStyle(SteerButton()).foregroundStyle(Brand.mute).padding(9).help("Hide the recap")
        }
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .onTapGesture { hideRecap() }
    }

    private func age(_ r: SessionRecap) -> String {
        var s = r.ai ? "recap on this Mac" : "Claude's last words"
        if let at = r.at { let f = DateFormatter(); f.dateFormat = "HH:mm"; s += " · last turn \(f.string(from: at))" }
        return s + " · fades when you type"
    }

    private func appeared() {
        let away = RecapAway.lastSeen[session.id].map { Date().timeIntervalSince($0) > RecapAway.after } ?? true
        RecapAway.lastSeen[session.id] = Date()
        Task { await load(); if away { show() } }
        startShots()
    }

    private func disappeared() {
        RecapAway.lastSeen[session.id] = Date()
        stopMonitor()
        shotWatch?.cancel(); shotWatch = nil
    }

    private func comeBack() { Task { await load(); show() } }

    private func load() async {
        // Test copies (`--background`) can point the recap at a real transcript: STEERIFY_RECAP_TRANSCRIPT=<conversation id>.
        let test = CommandLine.arguments.contains("--background") ? ProcessInfo.processInfo.environment["STEERIFY_RECAP_TRANSCRIPT"] : nil
        guard let id = test ?? session.claudeId, session.kind == .claude else { return }
        if let r = await SessionRecaps.recap(id) { recap = r }
    }

    private func show() {
        guard on, recap != nil else { return }
        showRecap = true
        guard keyMonitor == nil else { return }
        let view = session.view
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.window === view.window, view.window?.firstResponder === view { MainActor.assumeIsolated { hideRecap() } }
            return e
        }
    }

    private func hideRecap() { showRecap = false; stopMonitor() }
    private func stopMonitor() { if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil } }

    // MARK: ② Recent screenshots

    private var visibleShots: [URL] {
        _ = tick
        let since = RecapAway.shotsDismissed[session.id] ?? .distantPast
        return shots.filter { created($0) > since }
    }

    private func shotsRow(_ list: [URL]) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Text("RECENT SCREENSHOTS · CLICK TO PASTE").font(Brand.label(8)).tracking(0.9).foregroundStyle(Brand.mute)
                    .lineLimit(1).truncationMode(.head)
                Button { RecapAway.shotsDismissed[session.id] = Date(); tick += 1 } label: {
                    Image(systemName: "xmark").font(.system(size: S(8), weight: .bold))
                }.buttonStyle(SteerButton()).foregroundStyle(Brand.mute).help("Hide until your next screenshot")
            }
            HStack(spacing: 8) {
                ForEach(list, id: \.self) { u in shot(u) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func shot(_ u: URL) -> some View {
        let done = RecapAway.pasted[session.id]?.contains(u) == true
        return Button { paste(u) } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let t = thumbs[u] { Image(nsImage: t).resizable().aspectRatio(contentMode: .fill) }
                    else { Rectangle().fill(Brand.panel2) }
                }
                .frame(width: S(92), height: S(58)).clipped()
                .overlay(alignment: .bottomLeading) {
                    Text(RecentShotsStrip.time(u)).font(.system(size: S(9.5), design: .monospaced)).foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1).background(.black.opacity(0.6)).padding(3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(done ? Brand.amber : Brand.line2, lineWidth: done ? 2 : 1))
                if done {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Color(hex: 0x1a1200), Brand.amber).padding(3)
                }
            }
            .frame(width: S(92), height: S(58))
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
        }
        .buttonStyle(.plain).pointerStyle(.link)
        .help(done ? "Pasted · click to paste it again" : "Paste \(u.lastPathComponent) into the prompt")
    }

    private func paste(_ u: URL) {
        guard let t = session.view as? SteerTerminalView else { return }
        t.pasteText(SteerTerminalView.escape(u.path) + " ")
        t.window?.makeFirstResponder(t)
        RecapAway.pasted[session.id, default: []].insert(u)
        tick += 1
    }

    private func startShots() {
        guard on, session.kind == .claude else { return }
        loadShots()
        if shotWatch == nil {
            shotWatch = RecentShots.watch { loadShots(); DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { loadShots() } }
        }
    }

    private func loadShots() {
        guard on, session.kind == .claude else { return }
        let known = thumbs
        DispatchQueue.global(qos: .userInitiated).async {
            let list = RecentShots.list(limit: 3, within: 3600)
            var th: [URL: NSImage] = [:]
            for u in list { th[u] = known[u] ?? RecentShots.thumb(u) }
            DispatchQueue.main.async { shots = list; thumbs = th }
        }
    }

    private func created(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast }

    /// Above the prompt box as it is now: it grows with what you type, so the strip moves up with it.
    private func bottomPad(_ height: CGFloat) -> CGFloat {
        guard let n = promptRows, let t = session.view as? SteerTerminalView else { return promptHeight }
        let rows = max(t.terminalDimensions.rows, 1)
        let rowHeight = height / CGFloat(rows)
        return max(promptHeight, rowHeight * CGFloat(n) + 6)
    }

    /// Claude Code draws the prompt box between two "────" rules near the bottom: rows from the upper one to the end.
    static func promptRows(_ lines: [String]) -> Int? {
        let rows = lines.count
        var rules: [Int] = []
        for r in stride(from: rows - 1, through: max(0, rows - 40), by: -1) {
            if lines[r].hasPrefix("──────") { rules.append(r); if rules.count == 2 { break } }
        }
        guard rules.count == 2 else { return nil }
        return rows - rules[1]
    }

    /// Claude Code's prompt box + status line (~5 rows) stay uncovered at the bottom.
    private var promptHeight: CGFloat {
        let f = NSFont.monospacedSystemFont(ofSize: Prefs.size.terminal, weight: .regular)
        return ceil((f.ascender - f.descender + f.leading) * 5) + 10
    }
}
