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
                BackInPort(lamps: brief.chapters.filter { $0.total > 0 }.map { $0.waiting ? .waiting : $0.done >= $0.total ? .done : .moved },
                           key: brief.id)
                    .aspectRatio(190.0 / 33.0, contentMode: .fit).frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) { LinearGradient(colors: [.clear, Brand.bg], startPoint: .top, endPoint: .bottom).frame(height: S(30)) }
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
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

// MARK: - Header art (choice since-header A, request r261121-234027)

/// "Back in port": the HarbourDawn world at dusk. The boat sails home from the right and docks at the pier; one pier
/// lamp per chapter that moved (amber blinking = waiting on you, green = chapter complete, cream = moved). Same palette
/// and pixel grid as the Set up welcome. ~10 frames/s while the window is active; a still, docked frame with Reduce
/// Motion or in the background, so it costs nothing there.
struct BackInPort: View {
    enum Lamp { case waiting, done, moved }
    let lamps: [Lamp]
    var key: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var active
    @State private var start = Date()

    private static let cols = 190, rows = 33, horizon = 22
    private static let boat = ["......#.......", "......##......", "......###.....", "......####....", "......#####...", "......#.......",
                               "##############", ".############.", "..##########.."]

    var body: some View {
        let still = reduceMotion || active == .inactive
        TimelineView(.animation(minimumInterval: 0.1, paused: still)) { tl in
            Canvas { ctx, size in draw(ctx, size, still ? 60 : tl.date.timeIntervalSince(start)) }
        }
        .onChange(of: key) { _, _ in start = Date() }
        .accessibilityHidden(true)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let cols = Self.cols, hz = Self.horizon
        let px = size.width / CGFloat(cols)
        let rows = Int((size.height / px).rounded(.up))
        var ctx = ctx
        // Keep the sea line where it is when the frame is shorter than the scene: crop the sky.
        let over = CGFloat(Self.rows) * px - size.height
        if over > 0 { ctx.translateBy(x: 0, y: -over) }
        func dot(_ x: Int, _ y: Int, _ c: Color, _ a: Double = 1) {
            guard x >= 0, x < cols, y >= 0, y < max(rows, Self.rows) else { return }
            ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px + 0.3, height: px + 0.3)), with: .color(c.opacity(a)))
        }
        let phase = Int(t / 0.6) % 8
        // dusk sky, banded
        let bands: [Color] = [Color(hex: 0x120e24), Color(hex: 0x1a1430), Color(hex: 0x2a1a3a), Color(hex: 0x40223e), Color(hex: 0x5e2c40), Color(hex: 0x7f3a42)]
        for (i, c) in bands.enumerated() {
            let y0 = hz * i / bands.count, y1 = hz * (i + 1) / bands.count
            ctx.fill(Path(CGRect(x: 0, y: CGFloat(y0) * px, width: size.width, height: CGFloat(y1 - y0) * px + 0.5)), with: .color(c))
        }
        for (x, y) in [(12, 3), (40, 6), (66, 2), (90, 8), (120, 4), (150, 7), (164, 2)] {
            dot(x, y, Brand.cream, (x + phase) % 3 == 0 ? 0.9 : 0.4)
        }
        for y in -3...3 { for x in -3...3 where x * x + y * y <= 9 { dot(30 + x, 6 + y, Brand.cream, 0.85) } }   // moon
        // sea
        ctx.fill(Path(CGRect(x: 0, y: CGFloat(hz) * px, width: size.width, height: CGFloat(Self.rows - hz) * px + over + 1)), with: .color(Color(hex: 0x0d1020)))
        for r in 0..<3 { for x in 0..<cols where (x + phase * (r + 1) + r * 3) % 7 < 4 { dot(x, hz + 2 + r * 3, r == 0 ? Brand.blue : Brand.line2, r == 0 ? 0.6 : 0.9) } }
        // pier, long enough for the lamps
        let shown = Array(lamps.prefix(12))
        let pierEnd = max(40, 6 + shown.count * 8 + 2)
        let wood = Color(hex: 0x8a5a2b), wood2 = Color(hex: 0x5c3b1c), post = Color(hex: 0x4a2f16)
        for x in 0..<pierEnd { dot(x, hz - 2, wood); dot(x, hz - 1, wood2) }
        for x in stride(from: 2, to: pierEnd, by: 6) { for y in hz..<(hz + 8) { dot(x, y, post) } }
        // one lamp per chapter that moved
        for (i, l) in shown.enumerated() {
            let x = 6 + i * 8, on = l != .waiting || phase % 4 < 2
            dot(x, hz - 4, post); dot(x, hz - 3, post)
            let c = l == .waiting ? Brand.amber : l == .done ? Brand.green : Brand.cream
            dot(x, hz - 5, c, on ? 1 : 0.25)
            if on { dot(x, hz - 6, c, 0.3); dot(x - 1, hz - 5, c, 0.2); dot(x + 1, hz - 5, c, 0.2) }
        }
        // lighthouse with its beam
        let lx = 176, base = hz - 1
        for y in 0..<14 { for i in 0..<4 { dot(lx + i, base - y, (y / 3) % 2 == 1 ? Brand.cream : Brand.claude) } }
        for i in -1...4 { dot(lx + i, base - 14, post) }
        for (x, y) in [(1, 15), (2, 15), (1, 16), (2, 16)] { dot(lx + x, base - y, Brand.amber) }
        let dir = phase < 4 ? -1 : 1
        for k in 3..<30 { dot(lx + 1 + dir * k, base - 16 + k / 10, Brand.amber, max(0, 0.38 - Double(k) * 0.012)) }
        // the boat sails home (≈ 6 s) and docks at the end of the pier
        let dock = pierEnd + 1, from = cols - 16
        let p = min(1, t / 6), eased = 1 - (1 - p) * (1 - p)
        let bx = from - Int(Double(from - dock) * eased)
        let by = hz - 10 + (phase % 4 < 2 ? 0 : 1)
        for (y, row) in Self.boat.enumerated() { for (x, ch) in row.enumerated() where ch == "#" { dot(bx + x, by + y, y < 6 ? Brand.cream : Brand.amber) } }
        if p < 1 { for k in stride(from: 1, to: 12, by: 2) { dot(bx + 14 + k, hz - 1 + (k / 2) % 2, Brand.cream, 0.5 - Double(k) * 0.04) } }
    }
}
