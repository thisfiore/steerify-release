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
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                AutoIcon(title: session.item?.title ?? session.title, size: S(18))
                PulseDot(color: wrapped ? Brand.green : session.moodColor, pulsing: session.running && session.status == .working).scaleEffect(0.8).offset(x: 5, y: 5)
            }
            .opacity(wrapped && !selected ? 0.55 : 1)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(session.title).font(.system(size: S(12), weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Brand.ink.opacity(wrapped ? 0.45 : 0.85)).lineLimit(1)
                        .strikethrough(wrapped && !selected, color: Brand.mute.opacity(0.6))
                    if let stage, !wrapped { StageTag(tab: stage) }
                }
                if vertical || selected {
                    Text((wrapped ? (session.running ? "done · close it" : "ended · close it") : session.moodWord) + (vertical ? " · " + session.repo.name : ""))
                        .font(.system(size: S(10))).foregroundStyle(wrapped ? Brand.green.opacity(0.8) : session.moodColor).lineLimit(1)
                }
            }
            if vertical { Spacer(minLength: 4) }
            if hover || selected {
                Button(action: close) { Image(systemName: "xmark").font(.system(size: S(8), weight: .bold)) }
                    .buttonStyle(SteerButton()).foregroundStyle(Brand.mute).help("Close session (⌘W)")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, vertical ? 7 : 5)
        .frame(maxWidth: vertical ? .infinity : nil, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Brand.panel2 : hover ? Color.white.opacity(0.04) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? session.moodColor.opacity(0.5) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: select)
        .pointerStyle(.link)
        .help(wrapped ? "Done: released / finished. Close it — the conversation stays resumable from its item."
                      : (session.item?.title ?? session.repo.name))
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
