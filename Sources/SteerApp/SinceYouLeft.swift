import SwiftUI
import AppKit

// MARK: - "Since you left" (choice stay-on-top, option A): what moved while you were away, 2 lines per chapter,
// written on this Mac (Apple Intelligence when it is on, plain facts otherwise), then Where you left off.

struct ChapterNews: Identifiable {
    var id: String { chapter }
    let chapter: String
    let area: String
    let done: Int, total: Int
    let facts: [String]          // what happened, newest first
    var line1: String            // the summary (AI or plain)
    var ai = false
    let line2: String            // what waits on you / what is next
    let waiting: Bool
    let ref: String              // where "Open" goes
}

struct SinceBrief: Identifiable {
    var id: String { projectId + "@\(since.timeIntervalSince1970)" }
    let projectId: String
    let since: Date
    var chapters: [ChapterNews]
    let commits: Int
}

@MainActor
final class SinceYouLeft: ObservableObject {
    static let shared = SinceYouLeft()
    @Published var brief: SinceBrief?

    /// Away for less than this: no brief (a coffee is not "leaving").
    static let threshold: TimeInterval = 2 * 3600
    private static func key(_ id: String) -> String { "seen." + id }

    static func lastSeen(_ projectId: String) -> Date? {
        let t = Prefs.store.double(forKey: key(projectId))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    /// You are looking at this project now (or just stopped): news before this moment are not news anymore.
    static func markSeen(_ projectId: String?) {
        guard let projectId else { return }
        Prefs.store.set(Date().timeIntervalSince1970, forKey: key(projectId))
    }

    /// On open / coming back / switching project: build the brief if you were away long enough and something moved.
    func check(_ model: AppModel, force since: Date? = nil) {
        guard let p = model.project else { return }
        let seen = since ?? Self.lastSeen(p.id)
        Self.markSeen(p.id)
        guard let seen, since != nil || Date().timeIntervalSince(seen) >= Self.threshold else { return }
        var b = Self.build(model, p, since: seen)
        guard !b.chapters.isEmpty else { return }
        brief = b
        Task {
            for i in b.chapters.indices {
                let c = b.chapters[i]
                guard let s = await Self.summarise(c) else { continue }
                b.chapters[i].line1 = s; b.chapters[i].ai = true
                if brief?.id == b.id { brief = b }
            }
        }
    }
    func close() { if let id = brief?.projectId { Self.markSeen(id) }; brief = nil }

    // MARK: Facts

    static func build(_ model: AppModel, _ p: Project, since: Date) -> SinceBrief {
        let b = model.board(for: p)
        let iso = AppModel.iso, plain = ISO8601DateFormatter()
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) ?? plain.date(from: $0) } }
        var facts: [String: [(Date, String)]] = [:]
        func add(_ chapter: String?, _ d: Date?, _ what: String) {
            guard let d, d > since else { return }
            facts[chapter ?? "", default: []].append((d, what))
        }
        func short(_ s: String, _ n: Int = 46) -> String { s.count > n ? String(s.prefix(n - 1)) + "…" : s }

        for s in b.ships {
            add(model.chapterOf(ref: "test:" + s.id, title: s.title, in: b), date(s.updated),
                s.status == "live" ? "“\(short(s.title))” went live" : "delivered “\(short(s.title))”" + (s.version > 1 ? " (v\(s.version))" : ""))
        }
        for r in b.roadmap { add(r.track, date(r.doneAt), "done: " + short(r.text)) }
        var seenSession = Set<String>()
        for l in b.links.reversed() where seenSession.insert(l.claudeSession).inserted {
            guard !l.item.hasPrefix("test:") else { continue }      // deliveries already say it
            add(model.chapterOf(ref: l.item, title: l.title, in: b), date(l.started), "Claude: " + short(SessionName.short(l.title ?? l.item, intent: l.intent), 54))
        }
        // New choices: asked after you left (dates only → from that day on, when you were away a day or more).
        let newChoices = b.decisions.filter { d in
            guard !b.isDecided(d), !b.isParked(d), let a = d.revisedAt ?? d.added, let t = date(a) ?? day.date(from: String(a.prefix(10))) else { return false }
            return a.count > 10 ? t > since : t >= Calendar.current.startOfDay(for: since) && Date().timeIntervalSince(since) > 20 * 3600
        }

        let tracks = Dictionary(grouping: b.roadmap, by: \.track)
        let order = ["you": 0, "review": 1, "wip": 2, "todo": 3]
        var out: [ChapterNews] = []
        for (t, fs) in facts where !t.isEmpty {
            guard let items = tracks[t] else { continue }
            let sorted = fs.sorted { $0.0 > $1.0 }.map(\.1)
            var unique: [String] = []; for f in sorted where !unique.contains(f) { unique.append(f) }
            let toTest = b.ships.filter { model.chapterOf(ref: "test:" + $0.id, title: $0.title, in: b) == t && [.toTest, .retest].contains(b.shipState($0)) }.count
            let next = items.filter { $0.status != "done" }.sorted { (order[$0.status] ?? 9) < (order[$1.status] ?? 9) }.first
            let line2 = toTest > 0 ? "Waiting on you: \(toTest) to test" : next.map { "Next: " + short($0.text, 70) } ?? "Chapter complete"
            out.append(ChapterNews(chapter: t, area: items.first?.area ?? "", done: ChapterProgress(items).coreDone, total: ChapterProgress(items).core.count,
                                   facts: unique, line1: plainLine(unique), line2: line2, waiting: toTest > 0,
                                   ref: toTest > 0 ? "test:" + (b.ships.first { model.chapterOf(ref: "test:" + $0.id, title: $0.title, in: b) == t && [.toTest, .retest].contains(b.shipState($0)) }?.id ?? "")
                                       : "track:" + BoardFiles.slug(t)))
        }
        out.sort { ($0.waiting ? 0 : 1, -$0.facts.count) < ($1.waiting ? 0 : 1, -$1.facts.count) }
        // Things outside any chapter, then the new choices, as their own rows.
        let loose = (facts[""] ?? []).sorted { $0.0 > $1.0 }.map(\.1)
        if !loose.isEmpty {
            out.append(ChapterNews(chapter: "Outside the chapters", area: "", done: 0, total: 0, facts: loose, line1: plainLine(loose),
                                   line2: "\(loose.count) thing\(loose.count == 1 ? "" : "s") not linked to a chapter", waiting: false, ref: ""))
        }
        if !newChoices.isEmpty {
            out.append(ChapterNews(chapter: "New choices", area: "", done: 0, total: 0, facts: newChoices.map { "asked: " + short($0.title, 60) },
                                   line1: newChoices.prefix(2).map { "“" + short($0.title, 50) + "”" }.joined(separator: " · "),
                                   line2: "Waiting on you: \(newChoices.count) to decide", waiting: true, ref: "choice:" + newChoices[0].id))
        }
        return SinceBrief(projectId: p.id, since: since, chapters: out, commits: commitCount(p, since: since))
    }

    /// Plain summary when Apple Intelligence is off: the two newest facts.
    static func plainLine(_ fs: [String]) -> String {
        let head = fs.prefix(2).joined(separator: " · ")
        return fs.count > 2 ? head + " · +\(fs.count - 2) more" : head
    }

    static func summarise(_ c: ChapterNews) async -> String? {
        guard LocalAI.ready, c.total > 0, c.facts.count > 1 else { return nil }   // chapters only: the other rows stay plain facts
        let prompt = "Chapter: \(c.chapter)\nWhat happened while the owner was away (newest first):\n" + c.facts.prefix(12).map { "- " + $0 }.joined(separator: "\n")
        let key = "since|" + LocalAI.hash(prompt)
        guard let s = await LocalAI.ask(key: key, instructions: """
            You brief a product owner who was away, about one chapter of their project. \
            Answer with ONE plain sentence of at most 20 words: what moved, in past tense. \
            Only facts from the list. No preamble, no quotes, no markdown.
            """, prompt: prompt) else { return nil }
        let line = s.components(separatedBy: .newlines).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? s
        return line.trimmingCharacters(in: CharacterSet(charactersIn: " \"*-•"))
    }

    /// Code commits since you left, across the project's repos (board-only commits excluded when the board sits in a repo).
    static func commitCount(_ p: Project, since: Date) -> Int {
        let iso = ISO8601DateFormatter().string(from: since)
        return p.repos.filter(\.exists).reduce(0) { n, r in
            let proc = Process(), out = Pipe()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            var args = ["-C", r.path, "log", "--since=\(iso)", "--no-merges", "--pretty=%h", "--", "."]
            let b = URL(fileURLWithPath: p.boardDir).standardizedFileURL.path, rp = URL(fileURLWithPath: r.path).standardizedFileURL.path
            if b.hasPrefix(rp + "/") { args.append(":(exclude)" + String(b.dropFirst(rp.count + 1))) }
            proc.arguments = args; proc.standardOutput = out; proc.standardError = Pipe()
            guard (try? proc.run()) != nil else { return n }
            let d = out.fileHandleForReading.readDataToEndOfFile(); proc.waitUntilExit()
            return n + (String(data: d, encoding: .utf8) ?? "").split(separator: "\n").count
        }
    }
}

// MARK: - The brief

struct SinceYouLeftSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var since = SinceYouLeft.shared
    let brief: SinceBrief
    let project: Project

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { since.close() }
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(brief.chapters) { row($0) }
                        ResumeChapters(project: project, compact: true).padding(.top, 10)
                    }.padding(18)
                }
                footer
            }
            .frame(maxWidth: 760, maxHeight: 700)
            .background(RoundedRectangle(cornerRadius: 14).fill(Brand.bg))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.amber.opacity(0.35)))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
            .padding(30)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SINCE YOU LEFT").font(Brand.label(11)).tracking(1.4).foregroundStyle(Brand.amber)
                Text("\(project.name) · \(Self.away(brief.since))").font(.system(size: S(18), weight: .bold)).foregroundStyle(.white)
                let moved = brief.chapters.filter { $0.total > 0 }.count
                Text([moved > 0 ? "\(moved) chapter\(moved == 1 ? "" : "s") moved" : nil,
                      brief.commits > 0 ? "\(brief.commits) commit\(brief.commits == 1 ? "" : "s")" : nil,
                      waitingCount > 0 ? "\(waitingCount) waiting on you" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: S(12))).foregroundStyle(Brand.mute)
            }
            Spacer()
            if brief.chapters.contains(where: \.ai) {
                Label("Written on this Mac", systemImage: "apple.intelligence").font(.system(size: S(10.5))).foregroundStyle(Brand.blue)
                    .help("Summaries by Apple Intelligence, on-device. Nothing leaves your Mac.")
            }
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    private var waitingCount: Int { brief.chapters.filter(\.waiting).count }

    private func row(_ c: ChapterNews) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AutoIcon(title: c.chapter, size: S(34), tile: true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(c.chapter.replacingOccurrences(of: "\\s*\\(.*\\)$", with: "", options: .regularExpression))
                        .font(.system(size: S(13.5), weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    if c.total > 0 {
                        PixelProgress(fraction: Double(c.done) / Double(max(c.total, 1)), blocks: 8, working: false).frame(width: S(64))
                        Text("\(c.done)/\(c.total)").font(.system(size: S(10.5), weight: .semibold).monospacedDigit()).foregroundStyle(Brand.green)
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: c.ai ? "apple.intelligence" : "clock.arrow.circlepath").font(.system(size: S(10))).foregroundStyle(c.ai ? Brand.blue : Brand.mute)
                    Text(c.line1).font(.system(size: S(12.5))).foregroundStyle(Brand.ink.opacity(0.9)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }.help(c.facts.joined(separator: "\n"))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: c.waiting ? "hand.raised.fill" : "arrow.right").font(.system(size: S(10))).foregroundStyle(c.waiting ? Brand.amber : Brand.mute)
                    Text(c.line2).font(.system(size: S(12), weight: c.waiting ? .semibold : .regular)).foregroundStyle(c.waiting ? Brand.amber : Brand.cream.opacity(0.85)).lineLimit(1)
                }
            }
            if !c.ref.isEmpty {
                ActionButton(title: c.waiting ? "Go" : "Open", primary: c.waiting) {
                    since.close()
                    model.focusItem(projectId: project.id, ref: c.ref.hasPrefix("track:") ? (firstOpen(c).map { "road:" + $0 } ?? c.ref) : c.ref)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.waiting ? Brand.amber.opacity(0.35) : Brand.line))
    }

    private func firstOpen(_ c: ChapterNews) -> String? {
        model.board(for: project).roadmap.first { $0.track == c.chapter && $0.status != "done" }?.id
    }

    private var footer: some View {
        HStack {
            Text("Shown when you come back after 2 h or more").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
            Spacer()
            Button { since.close() } label: {
                Text("Got it").font(.system(size: S(13), weight: .bold)).foregroundStyle(Color(hex: 0x1a1200))
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Brand.amber))
            }.buttonStyle(SteerButton()).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Brand.line).frame(height: 1) }
    }

    static func away(_ d: Date) -> String {
        let m = Int(-d.timeIntervalSinceNow / 60)
        if m < 120 { return "\(max(m, 1)) min away" }
        if m < 48 * 60 { return "\(m / 60) h away" }
        return "\(m / 1440) days away"
    }
}
