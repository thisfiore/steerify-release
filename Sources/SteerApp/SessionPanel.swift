import SwiftUI

// MARK: - Short session names

enum SessionName {
    static let verbs: [String: String] = ["fix": "Fix", "release": "Ship", "plan": "Plan", "build": "Build", "check": "Check",
                                          "look": "Look", "resume": "Resume", "ship": "Release", "consolidate": "Tidy", "choose": "Decide",
                                          "intake": "New"]
    private static let filler: Set<String> = ["the", "a", "an", "of", "on", "in", "for", "with", "and", "to", "from", "steerify", "chapter",
                                               "requirements", "release", "consolidate", "is", "are", "by", "at", "+"]

    /// "Multi-shot on prod: 5 bugs found while making the tutorial" + fix → "Fix · Multi-shot bugs"
    static func short(_ title: String, intent: String?) -> String {
        var t = title
        // A request: its words are the subject ("Request: In steerify I clicked…" used to give "Request Read").
        if t.hasPrefix("Request: ") {
            let subject = requestWords(String(t.dropFirst(9)))
            return intent.flatMap { verbs[$0] }.map { "\($0) · \(subject)" } ?? subject
        }
        for p in ["Chapter: ", "Requirements: ", "Consolidate: ", "Release: ", "Release setup: ", "Steerify: "] where t.hasPrefix(p) { t = String(t.dropFirst(p.count)) }
        t = t.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
        // Before the colon is usually the subject; keep one telling word after it.
        let parts = t.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        // Stop at the first connecting word: "Session status from Claude Code hooks" → "Session status".
        let cut: Set<String> = ["from", "with", "in", "on", "for", "to", "via", "+", "—", "-", "after", "before", "while", "per", "vs"]
        var raw: [String] = []
        for w in parts[0].split(separator: " ").map(String.init) {
            if !raw.isEmpty && cut.contains(w.lowercased()) { break }
            raw.append(w)
        }
        var words = raw.filter { !filler.contains($0.lowercased()) }
        if parts.count > 1, words.count < 3,
           let extra = parts[1].split(separator: " ").map(String.init).first(where: { $0.count > 3 && !filler.contains($0.lowercased()) }) {
            words.append(extra)
        }
        var subject = ""
        for w in words where (subject + " " + w).count <= 20 { subject += subject.isEmpty ? w : " " + w }
        if subject.isEmpty { subject = String(t.prefix(18)) }
        guard let i = intent, let v = verbs[i] else { return subject }
        return "\(v) · \(subject)"
    }

    /// The first words of a request, without the way people start one ("In steerify I clicked …", "We should …").
    static func requestWords(_ text: String) -> String {
        let lead: Set<String> = ["in", "on", "steerify", "i", "we", "you", "it", "should", "would", "could", "can", "like", "to", "want",
                                 "please", "the", "a", "an", "just", "so", "think", "maybe", "also", "when", "if", "clicked", "click",
                                 "got", "get", "see", "saw", "there", "is", "are", "this", "that", "my", "let", "me", "make", "need", "and",
                                 "i'd", "i’d", "we'd", "we’d", "let's", "let’s", "i'm", "i’m", "have", "has", "had", "of", "for", "with"]
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        var words = first.replacingOccurrences(of: "[\u{2460}-\u{2473}\t]", with: " ", options: .regularExpression)
            .split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) }.filter { !$0.isEmpty }
        while let w = words.first, lead.contains(w.lowercased()), words.count > 2 { words.removeFirst() }
        var subject = ""
        for w in words {
            if !subject.isEmpty && subject.count + w.count + 1 > 24 { break }
            subject += subject.isEmpty ? w : " " + w
        }
        // No dangling "a", "the", "of" at the end.
        var tail = subject.split(separator: " ").map(String.init)
        while tail.count > 2, let w = tail.last, lead.contains(w.lowercased()) { tail.removeLast() }
        subject = tail.joined(separator: " ")
        if subject.isEmpty { subject = String(first.prefix(22)) }
        return subject.prefix(1).uppercased() + subject.dropFirst()
    }

    /// 2–4 words naming a request (Apple Intelligence). nil when it is off: the caller keeps the words.
    static func requestSubject(_ text: String) async -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 12 else { return nil }
        let rules = "You name requests for a project board. Answer only with a title of 2 to 4 words saying what the request is about "
            + "(the thing to change), like \"Tasks tab session label\" or \"Export orders to CSV\". No quotes, no period, "
            + "never the words Request, Issue or Steerify."
        guard let a = await LocalAI.ask(key: "rname|" + LocalAI.hash(clean), instructions: rules, prompt: String(clean.prefix(1500))) else { return nil }
        let t = (a.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’.*#").union(.whitespaces))
        guard (1...6).contains(t.split(separator: " ").count), t.count <= 40 else { return nil }
        return t
    }
}

// MARK: - Session status words

extension TerminalSession {
    var moodWord: String {
        guard running else { return "ended" }
        guard kind == .claude else { return "shell" }
        switch status {
        case .working: return "rowing"
        case .waiting: return "needs you"
        case .idle:
            let m = Int(-(statusAt ?? Date()).timeIntervalSinceNow / 60)
            return m < 1 ? "idle" : m < 60 ? "idle \(m)m" : "idle \(m / 60)h"
        case .starting: return stuck?.reason ?? "warming up"
        case .ended: return "ended"
        }
    }
    var moodColor: Color {
        guard running else { return Brand.mute }
        if kind != .claude { return Brand.cream.opacity(0.6) }
        if status == .starting, stuck != nil { return Brand.amber }
        switch status { case .working: return Brand.blue; case .waiting: return Brand.amber; case .idle: return Brand.cream.opacity(0.75); default: return Brand.mute }
    }
}

// MARK: - Layouts

enum SessionLayout: String, CaseIterable { case tabs, list
    var title: String { self == .tabs ? "Tabs on top" : "List beside" }
}

/// One session, curated: status dot (pulsing while rowing), short name, mood, close.
struct SessionChip2: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: TerminalSession
    let selected: Bool
    /// Through its cycle (released / done / ended): dimmed, "done", suggested for closing.
    var wrapped = false
    var vertical = false
    /// The board tab this session stands on, shown as a small tag (nil: hidden).
    var stage: BoardTab? = nil
    let select: () -> Void
    let close: () -> Void
    @State private var hover = false
    @State private var renaming = false

    var body: some View {
        let outlook = model.outlook(session)
        let turn = wrapped ? nil : model.yourTurn(session)
        let tone = turn != nil ? Brand.violet : session.moodColor
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                AutoIcon(title: session.item?.title ?? session.title, size: S(18))
                if wrapped {
                    DoneTick().offset(x: 5, y: 5)
                } else {
                    PulseDot(color: tone, pulsing: session.running && session.status == .working).scaleEffect(0.8).offset(x: 5, y: 5)
                }
            }
            .opacity(wrapped && !selected ? 0.55 : 1)
            VStack(alignment: .leading, spacing: vertical ? 2 : 1) {
                if vertical {
                    // Column mode: verb + stage tag on their own small row, so the name keeps the full width.
                    let (verb, name) = splitTitle
                    let tag = wrapped ? nil : stage
                    if verb != nil || tag != nil || session.pinned {
                        HStack(spacing: 5) {
                            if session.pinned { PinMark() }
                            if let verb { Text(verb.uppercased()).font(Brand.label(8)).tracking(0.6).foregroundStyle(Brand.mute).lineLimit(1).fixedSize() }
                            if let tag { StageTag(tab: tag) }
                        }
                    }
                    if renaming {
                        SessionRenameField(session: session, editing: $renaming)
                    } else {
                        Text(name).font(.system(size: S(12), weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.white : Brand.ink.opacity(wrapped ? 0.45 : 0.85))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            .strikethrough(wrapped && !selected, color: Brand.mute.opacity(0.6))
                    }
                } else {
                    HStack(spacing: 5) {
                        if session.pinned { PinMark() }
                        if renaming {
                            SessionRenameField(session: session, editing: $renaming).frame(width: S(150))
                        } else {
                            Text(session.title).font(.system(size: S(12), weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.white : Brand.ink.opacity(wrapped ? 0.45 : 0.85)).lineLimit(1)
                                .strikethrough(wrapped && !selected, color: Brand.mute.opacity(0.6))
                        }
                        if let stage, !wrapped { StageTag(tab: stage) }
                    }
                }
                if vertical, let turn {
                    // Column mode: the button gets its own row so the name keeps the full width.
                    // A long product name ("Ship Second-edition pages · 5") must never widen the column
                    // (request r261123-191258): "your turn" goes first, then the name truncates.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            turnButton(turn, fixed: true)
                            Text("your turn").font(.system(size: S(10))).foregroundStyle(Brand.violet.opacity(0.85)).lineLimit(1).fixedSize()
                        }
                        turnButton(turn, fixed: false)
                    }.padding(.top, 2)
                } else if vertical, session.stuck != nil, session.status == .starting, session.running {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.moodWord + " · " + whereName).font(.system(size: S(10))).foregroundStyle(Brand.amber)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        restartButton
                    }.padding(.top, 1)
                } else if vertical || selected {
                    Text(subtitle(outlook, turn) + (vertical && outlook == nil && turn == nil ? " · " + whereName : ""))
                        .font(.system(size: S(10))).foregroundStyle(subtitleColor(outlook, turn))
                        .lineLimit(vertical && outlook?.isDone == false ? 3 : 1).fixedSize(horizontal: false, vertical: true)
                }
            }
            if vertical { Spacer(minLength: 4) }
            if !vertical, let turn { turnButton(turn) }
            if !vertical, session.stuck != nil, session.status == .starting, session.running { restartButton }
            // Hover controls keep their space when hidden (opacity, not if): showing them must never
            // narrow the chip, rewrap the name or push the neighbours.
            let showControls = hover || selected
            if case .next? = outlook {
                Button { model.goOn(session) } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: S(15))).foregroundStyle(Brand.amber)
                }
                .buttonStyle(SteerButton()).pointerStyle(.link).help("Tell the session to take the next step it named")
                .opacity(showControls ? 1 : 0).allowsHitTesting(showControls)
            }
            Button(action: close) { Image(systemName: "xmark").font(.system(size: S(8), weight: .bold)) }
                .buttonStyle(SteerButton()).foregroundStyle(Brand.mute).help("Close session (⌘W)")
                .opacity(showControls ? 1 : 0).allowsHitTesting(showControls)
        }
        .padding(.horizontal, 10).padding(.vertical, vertical ? 8 : 5)
        .frame(maxWidth: vertical ? .infinity : nil, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Brand.panel2 : hover ? Color.white.opacity(0.04) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? (wrapped ? Brand.mute : tone).opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: select)
        .pointerStyle(.link)
        .help(help(outlook, turn))
        .contextMenu { labelMenu }
    }

    /// A session stuck on warming up: start it again, same chat (StuckStart.swift).
    private var restartButton: some View {
        Button { model.restartStuck(session) } label: {
            Label("Restart", systemImage: "arrow.clockwise").font(.system(size: S(10.5), weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Brand.amber)).foregroundStyle(Color.black)
        }
        .buttonStyle(SteerButton()).pointerStyle(.link).help("Start this session again, on the same chat")
    }

    /// Right-click: rename and pin (kept for the conversation, shared with the iPhone).
    @ViewBuilder private var labelMenu: some View {
        if session.kind == .claude, session.claudeId != nil {
            Button("Rename…") { renaming = true }
            if session.customName != nil { Button("Use Steerify's name") { model.renameSession(session, to: nil) } }
            Button(session.pinned ? "Unpin" : "Pin to top") { model.setPinned(session, !session.pinned) }
            Divider()
        }
        Button("Close session") { close() }
    }

    /// "Test →", "Answer →", "Release →": opens the board item that waits on you.
    private func turnButton(_ turn: BoardTurn, fixed: Bool = true) -> some View {
        let ship = shipOf(turn)
        return Button {
            // A release waits: the product's ship sheet (choice ship-by-product), like every other ship button.
            if let ship, let p = model.projects.first(where: { $0.id == session.projectId }) {
                model.selectedProjectId = p.id
                model.askShip(projectId: p.id, product: ship.product.id, highlight: String(turn.ref.dropFirst("release:".count)))
            } else { model.focusItem(projectId: session.projectId, ref: turn.ref) }
        } label: {
            HStack(spacing: 3) {
                Text(ship?.title ?? turn.verb).font(.system(size: S(10.5), weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "arrow.right").font(.system(size: S(8), weight: .bold)).fixedSize()
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Brand.violet.opacity(0.14)))
            .overlay(Capsule().stroke(Brand.violet.opacity(0.5)))
            .foregroundStyle(Brand.violet)
        }
        .buttonStyle(SteerButton()).pointerStyle(.link).fixedSize(horizontal: fixed, vertical: true)
        .help(ship.map { "Your turn: ship \($0.product.name) with its \($0.count) ready item\($0.count == 1 ? "" : "s")" } ?? "Your turn: open it on \(turn.tab.title.capitalized)")
    }

    /// "Release" turn → the product it ships ("Ship Mac app · 3").
    private func shipOf(_ turn: BoardTurn) -> (product: ReleaseProduct, title: String, count: Int)? {
        guard turn.ref.hasPrefix("release:"), let p = model.projects.first(where: { $0.id == session.projectId }) else { return nil }
        let id = String(turn.ref.dropFirst("release:".count))
        guard let s = model.board(for: p).ships.first(where: { $0.id == id }) else { return nil }
        return model.shipLabel(s, in: p)
    }

    /// "Tidy · Project ops" → ("Tidy", "Project ops"); a title without a known verb stays whole.
    private var splitTitle: (String?, String) {
        let parts = session.title.components(separatedBy: " · ")
        if parts.count > 1, SessionName.verbs.values.contains(parts[0]) { return (parts[0], parts.dropFirst().joined(separator: " · ")) }
        return (nil, session.title)
    }

    /// Where the session works: its repo. A task works across the project (not one repo), so it names the project.
    private var whereName: String {
        stage == .task ? (model.projects.first { $0.id == session.projectId }?.name ?? session.repo.name) : session.repo.name
    }

    private func subtitle(_ o: SessionOutlook?, _ t: BoardTurn?) -> String {
        if !session.running { return "ended · close it" }
        if let t { return "your turn · " + t.tab.title.capitalized.replacingOccurrences(of: "To Test", with: "To test") }
        if model.handedOff(session) { return "shipping · in the release" }
        if wrapped && model.isReleased(session) { return "released · close it" }
        if let o { return o.line }
        return wrapped ? "done · close it" : session.moodWord
    }
    private func subtitleColor(_ o: SessionOutlook?, _ t: BoardTurn?) -> Color {
        if wrapped { return model.isReleased(session) ? Brand.green.opacity(0.8) : Brand.mute }
        if t != nil { return Brand.violet }
        if model.handedOff(session) { return Brand.blue }
        switch o { case .ask?: return Brand.amber; case .next?: return Brand.cream; default: return session.moodColor }
    }
    private func help(_ o: SessionOutlook?, _ t: BoardTurn?) -> String {
        let name = session.item?.title ?? session.repo.name
        if let t { return name + "\nYour turn on \(t.tab.title.capitalized): \(t.verb) opens it. The session stays until it is through." }
        switch o {
        case .ask(let t)?: return name + "\nAsks you: " + t
        case .next(let t)?: return name + "\nNext step: " + t + "\nGo on sends it to the session."
        case .takenOver(let by)?: return "Done: \(by) took over this work. Close it — the conversation stays resumable from its item."
        case .onBoard(let w)?: return "Done: what it waits on is on \(w). Close it — the conversation stays resumable from its item."
        case .nothing?: return "Done: nothing left to do. Close it — the conversation stays resumable from its item."
        case nil: return wrapped ? "Done: released / finished. Close it — the conversation stays resumable from its item." : name
        }
    }
}

/// A pinned session: a small amber pin before its name.
struct PinMark: View {
    var body: some View {
        Image(systemName: "pin.fill").font(.system(size: S(8.5), weight: .bold)).foregroundStyle(Brand.amber)
            .rotationEffect(.degrees(30)).help("Pinned: always on top (right-click to unpin)")
    }
}

/// "✓ Close 2 done": every wrapped session in one click (the conversations stay resumable).
struct CloseWrappedButton: View {
    let count: Int
    let action: () -> Void
    var body: some View {
        if count > 0 {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: S(9), weight: .bold)).foregroundStyle(Brand.green)
                    Text("Close \(count) done").font(.system(size: S(11), weight: .medium)).foregroundStyle(Brand.ink.opacity(0.75))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.04)))
                .overlay(Capsule().stroke(Brand.line2))
            }
            .buttonStyle(SteerButton()).pointerStyle(.link).fixedSize()
            .help("Close the sessions whose work is released or done. Their conversations stay resumable from the item.")
        }
    }
}

/// Done: a small green tick on a dark disc instead of the status dot.
struct DoneTick: View {
    var body: some View {
        Image(systemName: "checkmark").font(.system(size: S(6.5), weight: .heavy)).foregroundStyle(Brand.green)
            .frame(width: S(11), height: S(11))
            .background(Circle().fill(Color(hex: 0x0b0c0f)))
            .overlay(Circle().stroke(Brand.green.opacity(0.5), lineWidth: 1))
    }
}

struct PulseDot: View {
    let color: Color
    var pulsing = false
    var body: some View {
        if pulsing {
            // Stepped ring (4 frames, ~3 per second) instead of a repeatForever animation: that one redrew the
            // whole window 60 times a second for every working session (25–30% CPU with the app untouched).
            TimelineView(.periodic(from: .now, by: 0.35)) { t in
                dot(step: Int(t.date.timeIntervalSinceReferenceDate / 0.35) % 4)
            }
        } else { dot(step: nil) }
    }
    private func dot(step: Int?) -> some View {
        ZStack {
            if let step {
                let d = 7 + CGFloat(step) * 7 / 3
                Circle().stroke(color.opacity(0.7 * (1 - Double(step) / 3)), lineWidth: 2).frame(width: d, height: d)
            }
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
    }
}

/// "+" menu: guided Claude session, Claude / shell in a repo.
struct NewSessionButton: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    var body: some View {
        Menu {
            Button("Guided session with Claude  ⌘T") { model.newSession(.claude) }
            Section("Claude in") { ForEach(project.repos.filter(\.exists)) { r in Button(r.name) { model.newSession(.claude, repo: r) } } }
            Section("Shell in") { ForEach(project.repos.filter(\.exists)) { r in Button(r.name) { model.newSession(.shell, repo: r) } } }
        } label: { Image(systemName: "plus").font(.system(size: S(11), weight: .bold)) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(Brand.cream).pointerStyle(.link).help("New session")
    }
}
