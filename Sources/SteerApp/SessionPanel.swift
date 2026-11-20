import SwiftUI

// MARK: - Short session names

enum SessionName {
    static let verbs: [String: String] = ["fix": "Fix", "release": "Ship", "plan": "Plan", "build": "Build", "check": "Check",
                                          "look": "Look", "resume": "Resume", "ship": "Release", "consolidate": "Tidy", "choose": "Decide"]
    private static let filler: Set<String> = ["the", "a", "an", "of", "on", "in", "for", "with", "and", "to", "from", "steerify", "chapter",
                                               "requirements", "release", "consolidate", "is", "are", "by", "at", "+"]

    /// "Multi-shot on prod: 5 bugs found while making the tutorial" + fix → "Fix · Multi-shot bugs"
    static func short(_ title: String, intent: String?) -> String {
        var t = title
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
        case .starting: return "warming up"
        case .ended: return "ended"
        }
    }
    var moodColor: Color {
        guard running else { return Brand.mute }
        if kind != .claude { return Brand.cream.opacity(0.6) }
        switch status { case .working: return Brand.green; case .waiting: return Brand.amber; case .idle: return Brand.cream.opacity(0.75); default: return Brand.mute }
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

    var body: some View {
        let outlook = model.outlook(session)
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                AutoIcon(title: session.item?.title ?? session.title, size: S(18))
                PulseDot(color: wrapped ? Brand.green : session.moodColor, pulsing: session.running && session.status == .working).scaleEffect(0.8).offset(x: 5, y: 5)
            }
            .opacity(wrapped && !selected ? 0.55 : 1)
            VStack(alignment: .leading, spacing: vertical ? 2 : 1) {
                if vertical {
                    // Column mode: verb + stage tag on their own small row, so the name keeps the full width.
                    let (verb, name) = splitTitle
                    let tag = wrapped ? nil : stage
                    if verb != nil || tag != nil {
                        HStack(spacing: 5) {
                            if let verb { Text(verb.uppercased()).font(Brand.label(8)).tracking(0.6).foregroundStyle(Brand.mute) }
                            if let tag { StageTag(tab: tag) }
                        }
                    }
                    Text(name).font(.system(size: S(12), weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Brand.ink.opacity(wrapped ? 0.45 : 0.85))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .strikethrough(wrapped && !selected, color: Brand.mute.opacity(0.6))
                } else {
                    HStack(spacing: 5) {
                        Text(session.title).font(.system(size: S(12), weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.white : Brand.ink.opacity(wrapped ? 0.45 : 0.85)).lineLimit(1)
                            .strikethrough(wrapped && !selected, color: Brand.mute.opacity(0.6))
                        if let stage, !wrapped { StageTag(tab: stage) }
                    }
                }
                if vertical || selected {
                    Text(subtitle(outlook) + (vertical && outlook == nil ? " · " + session.repo.name : ""))
                        .font(.system(size: S(10))).foregroundStyle(subtitleColor(outlook))
                        .lineLimit(vertical && outlook?.isDone == false ? 3 : 1).fixedSize(horizontal: false, vertical: true)
                }
            }
            if vertical { Spacer(minLength: 4) }
            if case .next? = outlook, hover || selected {
                Button { model.goOn(session) } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.system(size: S(15))).foregroundStyle(Brand.amber)
                }
                .buttonStyle(SteerButton()).pointerStyle(.link).help("Tell the session to take the next step it named")
            }
            if hover || selected {
                Button(action: close) { Image(systemName: "xmark").font(.system(size: S(8), weight: .bold)) }
                    .buttonStyle(SteerButton()).foregroundStyle(Brand.mute).help("Close session (⌘W)")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, vertical ? 8 : 5)
        .frame(maxWidth: vertical ? .infinity : nil, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Brand.panel2 : hover ? Color.white.opacity(0.04) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? session.moodColor.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: select)
        .pointerStyle(.link)
        .help(help(outlook))
    }

    /// "Tidy · Project ops" → ("Tidy", "Project ops"); a title without a known verb stays whole.
    private var splitTitle: (String?, String) {
        let parts = session.title.components(separatedBy: " · ")
        if parts.count > 1, SessionName.verbs.values.contains(parts[0]) { return (parts[0], parts.dropFirst().joined(separator: " · ")) }
        return (nil, session.title)
    }

    private func subtitle(_ o: SessionOutlook?) -> String {
        if !session.running { return "ended · close it" }
        if let o { return o.line }
        return wrapped ? "done · close it" : session.moodWord
    }
    private func subtitleColor(_ o: SessionOutlook?) -> Color {
        if wrapped { return Brand.green.opacity(0.8) }
        switch o { case .ask?: return Brand.amber; case .next?: return Brand.cream; default: return session.moodColor }
    }
    private func help(_ o: SessionOutlook?) -> String {
        let name = session.item?.title ?? session.repo.name
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

/// "✓ Close 2 done": every wrapped session in one click (the conversations stay resumable).
struct CloseWrappedButton: View {
    let count: Int
    let action: () -> Void
    var body: some View {
        if count > 0 {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: S(9), weight: .bold))
                    Text("Close \(count) done").font(.system(size: S(11), weight: .medium))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Brand.green.opacity(0.12)))
                .overlay(Capsule().stroke(Brand.green.opacity(0.35)))
                .foregroundStyle(Brand.green)
            }
            .buttonStyle(SteerButton()).pointerStyle(.link).fixedSize()
            .help("Close the sessions whose work is released or done. Their conversations stay resumable from the item.")
        }
    }
}

struct PulseDot: View {
    let color: Color
    var pulsing = false
    @State private var on = false
    var body: some View {
        ZStack {
            if pulsing { Circle().stroke(color.opacity(on ? 0 : 0.7), lineWidth: 2).frame(width: on ? 14 : 7, height: on ? 14 : 7) }
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .frame(width: 14, height: 14)
        .onAppear { if pulsing { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true } } }
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
