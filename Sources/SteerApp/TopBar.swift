import SwiftUI

/// The pixel ship wheel (same raster as the app icon), drawn natively.
struct PixelWheel: View {
    var size: CGFloat = 18
    private static let cells: [(Int, Int, Color)] = {
        var out: [(Int, Int, Color)] = []
        let c = 8.0
        for y in 0..<17 { for x in 0..<17 {
            let dx = Double(x) - c, dy = Double(y) - c, r = hypot(dx, dy), a = atan2(dy, dx)
            let k = (a / (.pi / 4)).rounded(), da = abs(a - k * .pi / 4) * r
            var col: Color? = nil
            if r <= 2.2 { col = Brand.amber }
            else if (r >= 4.6 && r <= 5.9) || (da < 0.55 && r <= 7.4) || (r > 7.4 && r <= 8.3 && da < 0.9) { col = Brand.cream }
            if let col { out.append((x, y, col)) }
        } }
        for (x, y) in [(7, 7), (8, 8), (7, 9)] { if let i = out.firstIndex(where: { $0.0 == x && $0.1 == y }) { out[i].2 = Color(hex: 0x1b1305) } }
        return out
    }()
    var body: some View {
        Canvas { ctx, sz in
            let cell = sz.width / 17
            for (x, y, col) in Self.cells {
                ctx.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell * 0.92, height: cell * 0.92)), with: .color(col))
            }
        }
        .frame(width: size, height: size)
    }
}

/// How much the top bar shows. Narrow windows (or a long project name) first drop the centre to the wheel alone
/// and the progress bar, then the "Next for you" title: the project name always stays whole.
enum TopBarDensity: Int, Comparable {
    case full, compact, minimal
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// `width`: the window's width. `updateReady`: Update sits next to the logo. `webBoard`: the web board button.
    static func of(width: CGFloat, name: String, updateReady: Bool, webBoard: Bool) -> TopBarDensity {
        let nameW = (name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: S(13), weight: .semibold)]).width
        // Left: traffic lights + switcher (avatar, name, progress, %, chevron). Right: Next for you, + Request, icons.
        let lights: CGFloat = 86
        let left = { (d: TopBarDensity) in lights + nameW + S(d == .full ? 172 : 100) }
        let right = { (d: TopBarDensity) in
            S(d == .minimal ? 120 : 290) + S(100) + S(webBoard ? 116 : 80) + 24
        }
        let centre = { (d: TopBarDensity) in (d == .full ? S(176) : S(30)) + (updateReady ? S(90) : 0) }
        // The centre item stays centred, so each side gets half of what it leaves.
        func fits(_ d: TopBarDensity) -> Bool { width >= centre(d) + 2 * max(left(d), right(d)) + 16 }
        return fits(.full) ? .full : fits(.compact) ? .compact : .minimal
    }
}

/// One thing worth your attention now, with why.
struct NextStep: Identifiable {
    var id: String { ref + "|" + reason }
    let ref: String
    let title: String
    let reason: String        // short pill text: "needs your answer", "new to test", "start its session"…
    let score: Int            // higher = sooner
    var urgent: Bool { score >= 50 }
}

extension AppModel {
    /// Smart order: live sessions that need you, your answers without a session, fresh things to test,
    /// stuck refines, recent choices, active chapters. Old things sink (and do not count as "now").
    func nextSteps(_ p: Project) -> [NextStep] { TurnMemo.get("next:" + p.id) { computeNextSteps(p) } }
    private func computeNextSteps(_ p: Project) -> [NextStep] {
        let b = board(for: p)
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
        func age(_ s: String?) -> Double {               // days since
            guard let s else { return 99 }
            let d = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? day.date(from: String(s.prefix(10)))
            return d.map { -$0.timeIntervalSinceNow / 86400 } ?? 99
        }
        func fresh(_ base: Int, _ days: Double) -> Int { days < 1 ? base + 10 : days < 3 ? base + 5 : days > 14 ? 15 : base }
        var out: [NextStep] = []
        var seen = Set<String>()
        func add(_ n: NextStep) { if seen.insert(n.ref).inserted { out.append(n) } }

        for s in sessions(of: p.id) where s.running && s.status == .waiting {
            add(NextStep(ref: s.item?.ref ?? "session:\(s.id)", title: s.title, reason: "session needs your answer", score: 100))
        }
        for n in nudges where n.projectId == p.id {
            if case .noSession = n.kind { add(NextStep(ref: n.ref, title: n.title, reason: "\(n.reason.lowercased()) · start its session", score: 90)) }
        }
        for s in b.ships {
            switch b.shipState(s) {
            case .toTest: add(NextStep(ref: "test:" + s.id, title: s.title, reason: "new to test", score: fresh(80, age(s.updated))))
            case .retest: add(NextStep(ref: "test:" + s.id, title: s.title, reason: "re-test v\(s.version)", score: fresh(78, age(s.updated))))
            case .waiting where liveSession(for: "test:" + s.id, in: p) == nil:
                // Your verdict is given. Only if no session ever took it is the next move yours (start one);
                // once a session took it, it is Claude's turn (a new version comes back to To test), not ⌘J's.
                let v = b.verdict("ship:" + s.id)
                if b.takenBySession("test:" + s.id, since: v.at) {
                    add(NextStep(ref: "test:" + s.id, title: s.title, reason: "\(b.effectivePick(s) ?? "refine") · Claude took it, no new version yet", score: 10))
                } else {
                    add(NextStep(ref: "test:" + s.id, title: s.title, reason: "\(b.effectivePick(s) ?? "refine") · no session on it", score: fresh(70, age(v.at))))
                }
            default: break
            }
        }
        for c in b.chapters where c.draft {
            add(NextStep(ref: "track:" + BoardFiles.slug(c.name), title: "Draft chapter: " + c.name, reason: "chapter draft to approve", score: 65))
        }
        for d in b.decisions where !b.isDecided(d) && !b.isParked(d) {
            add(NextStep(ref: "choice:" + d.id, title: d.title, reason: "choice to make", score: fresh(60, age(d.revisedAt ?? d.added))))
        }
        // Roadmap items waiting on you count only when their area is moving now (a delivery in the last 3 days)
        // and they don't talk about a day that is already past ("arrives Mon 17 Nov"): those are stale.
        let movingAreas = Set(b.ships.filter { age($0.updated) < 3 }.map(\.area))
        for r in b.roadmap where r.status == "you" {
            let stale = Self.mentionsPastDay(r.text)
            let moving = movingAreas.contains(r.area) && !stale
            add(NextStep(ref: "road:" + r.id, title: r.text,
                         reason: stale ? "roadmap · probably outdated" : moving ? "roadmap · waiting on you" : "roadmap · quiet chapter",
                         score: moving ? 50 : stale ? 5 : 20))
        }
        for r in b.requirements where r.status == "question" && b.verdict("req:" + r.id).pickString == nil {
            add(NextStep(ref: "req:" + r.id, title: r.text, reason: "question for you", score: 30))
        }
        return out.sorted { $0.score > $1.score }
    }

    /// "Mon 17 Nov", "17 Nov", "Nov 17" earlier than today → the item is about something already past.
    static func mentionsPastDay(_ text: String) -> Bool {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let words = text.lowercased().replacingOccurrences(of: ",", with: " ").split(whereSeparator: { $0 == " " || $0 == "(" || $0 == ")" }).map(String.init)
        let cal = Calendar.current, now = Date()
        let year = cal.component(.year, from: now)
        for (i, w) in words.enumerated() {
            guard let m = months.firstIndex(where: { w.hasPrefix($0) }), w.count <= 9 else { continue }
            let day = [i > 0 ? words[i - 1] : "", i + 1 < words.count ? words[i + 1] : ""].compactMap { Int($0) }.first { (1...31).contains($0) }
            if let d = day, let date = cal.date(from: DateComponents(year: year, month: m + 1, day: d)),
               date < cal.startOfDay(for: now), now.timeIntervalSince(date) < 200 * 86400 { return true }
        }
        return false
    }

    /// Kept for the palette and older callers: the urgent next steps as (ref, title).
    func actionables(_ p: Project) -> [(ref: String, title: String)] {
        nextSteps(p).filter(\.urgent).map { (ref: $0.ref, title: $0.title) }
    }
}

/// Top bar, right: "Next for you", compact like a session name (⌘J walks the list; the full title is in the tooltip).
struct NextUp: View {
    @EnvironmentObject var model: AppModel
    var density: TopBarDensity = .full
    /// "new to test" → "TEST", "session needs your answer" → "ANSWER"…: one short word for the pill.
    static func tag(_ reason: String) -> String {
        let r = reason.lowercased()
        if r.contains("answer") { return "ANSWER" }
        if r.contains("re-test") { return "RE-TEST" }
        if r.contains("to test") { return "TEST" }
        if r.contains("no session") || r.contains("start its session") { return "START" }
        if r.contains("draft") { return "DRAFT" }
        if r.contains("choice") { return "CHOICE" }
        if r.contains("question") { return "QUESTION" }
        if r.contains("roadmap") { return "ROADMAP" }
        return String(reason.uppercased().prefix(8))
    }
    var body: some View {
        if let p = model.project {
            let list = model.nextSteps(p).filter(\.urgent)
            let n = list.isEmpty ? nil : list[model.nextIndex % list.count]
            Button { model.jumpNext() } label: {
                HStack(spacing: 6) {
                    PixelIcon(name: "play", size: 8).foregroundStyle(n == nil ? Brand.mute : Brand.amber)
                    if let n {
                        Text(Self.tag(n.reason)).font(Brand.label(8.5)).tracking(0.5).foregroundStyle(Brand.amber).lineLimit(1)
                        if density < .minimal {
                        Text(SessionName.short(n.title.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "“", with: "").replacingOccurrences(of: "”", with: ""), intent: nil)).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(Brand.ink).frame(maxWidth: S(150), alignment: .leading)
                        }
                        if list.count > 1 {
                            Text("\(list.count)").font(.system(size: S(9.5), weight: .bold)).foregroundStyle(Color(hex: 0x1a1200))
                                .padding(.horizontal, 4).background(Capsule().fill(Brand.amber))
                        }
                    } else if density < .minimal {
                        Text("All quiet").foregroundStyle(Brand.mute)
                    }
                    Text("⌘J").font(.system(size: S(9.5), design: .monospaced)).foregroundStyle(Brand.mute)
                }
                .font(.system(size: S(11.5)))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.05)))
                .overlay(Capsule().stroke(Brand.line2))
                .fixedSize()
            }
            .buttonStyle(SteerButton())
            .disabled(n == nil)
            .help(n.map { "\($0.reason.capitalized): \($0.title)\n\(list.count) waiting on you · ⌘J walks the list" } ?? "Nothing waits on you")
        }
    }
}

/// Top bar, center: our mark, "Steerify", and a small "beta v0.x". Click the version: what's new in it.
/// After an update the same panel opens once by itself.
struct Wordmark: View {
    /// Compact: the wheel alone (it opens the same What's new panel; the name and version are in its tooltip).
    var compact = false
    static let version: String = {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let parts = v.split(separator: ".")
        return parts.count > 2 && parts[2] == "0" ? parts.prefix(2).joined(separator: ".") : v
    }()
    @State private var open = false
    @State private var hover = false
    var body: some View {
        HStack(spacing: 7) {
            if compact {
                Button { open.toggle() } label: { PixelWheel(size: 16).padding(3).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .help("Steerify beta v\(Self.version) · what's new")
                    .popover(isPresented: $open, arrowEdge: .bottom) { WhatsNewPanel(close: { open = false }) }
            } else {
            PixelWheel(size: 16)
            Text("Steerify").font(.system(size: S(13), weight: .semibold)).foregroundStyle(Brand.cream)
            Button { open.toggle() } label: {
                Text("beta v\(Self.version)").font(.system(size: S(9.5), design: .monospaced))
                    .foregroundStyle(hover || open ? Brand.cream : Brand.mute)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(Capsule().stroke(hover || open ? Brand.amber.opacity(0.7) : Brand.line2))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0; if $0 { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            .help("What's new in v\(Self.version)")
            .popover(isPresented: $open, arrowEdge: .bottom) { WhatsNewPanel(close: { open = false }) }
            }
        }
        .fixedSize()
        .onAppear {
            if WhatsNew.shouldShowAfterUpdate() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { open = true } }
        }
    }
}

/// The release notes bundled with this build (Resources/whats-new.md, written by release.sh from the board).
enum WhatsNew {
    static let full = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    static let allNotes = URL(string: "https://github.com/thisfiore/steerify-release/releases")!
    static func notes(_ version: String) -> URL { URL(string: "https://github.com/thisfiore/steerify-release/releases/tag/v\(version)")! }

    /// Titles from an appcast item's description (<li>…</li>, written by release.sh).
    static func titles(fromHTML html: String?) -> [String] {
        guard let html else { return [] }
        let re = try! NSRegularExpression(pattern: "<li>(.*?)</li>", options: [.dotMatchesLineSeparators])
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
            Range(m.range(at: 1), in: html).map {
                String(html[$0]).replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
            }
        }
    }

    /// Feature titles: the bold part of each "- **Title** — what" line.
    static let titles: [String] = {
        guard let url = Bundle.main.url(forResource: "whats-new", withExtension: "md"),
              let md = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return md.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("- **"), let end = line.range(of: "**", range: line.index(line.startIndex, offsetBy: 4)..<line.endIndex)
            else { return nil }
            return String(line[line.index(line.startIndex, offsetBy: 4)..<end.lowerBound])
        }.reversed()   // newest first
    }()

    /// True once per new version that has notes; a first install only remembers the version.
    static func shouldShowAfterUpdate() -> Bool {
        guard !CommandLine.arguments.contains("--background") else { return false }
        let key = "lastSeenVersion", seen = Prefs.store.string(forKey: key)
        Prefs.store.set(full, forKey: key)
        return seen != nil && seen != full && !titles.isEmpty
    }
}

/// What's new in a version: this one (the version badge) or the one waiting to be installed ("Restart to update").
struct WhatsNewPanel: View {
    var version = WhatsNew.full
    var titles = WhatsNew.titles
    /// Set for a downloaded update: the panel offers to restart into it.
    var restart: (() -> Void)? = nil
    let close: () -> Void
    @State private var all = false
    var body: some View {
        let list = titles
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PixelWheel(size: 18)
                Text(restart == nil ? "What's new in v\(version)" : "Ready to install: v\(version)")
                    .font(.system(size: S(14), weight: .semibold)).foregroundStyle(Brand.cream)
            }
            if list.isEmpty {
                Text(restart != nil ? "The notes are on GitHub." : AppUpdater.isDevBuild ? "Dev build: notes come with a release." : "Small fixes and polish.")
                    .font(.system(size: S(12))).foregroundStyle(Brand.mute)
            } else {
                let rows = VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array((all ? list : Array(list.prefix(8))).enumerated()), id: \.offset) { _, t in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Circle().fill(Brand.amber).frame(width: 5, height: 5).offset(y: -2)
                            Text(t).font(.system(size: S(12))).foregroundStyle(Brand.cream).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if list.count > 8 && !all {
                        Button("+ \(list.count - 8) more") { all = true }.buttonStyle(.plain)
                            .font(.system(size: S(11.5))).foregroundStyle(Brand.amber)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if all { ScrollView { rows }.frame(height: 320) } else { rows }
            }
            Divider()
            HStack(spacing: 14) {
                Button("Release notes ↗") { NSWorkspace.shared.open(WhatsNew.notes(version)); close() }
                Button("All versions ↗") { NSWorkspace.shared.open(WhatsNew.allNotes); close() }
                Spacer()
                if let restart {
                    Button { close(); restart() } label: {
                        Text("Restart now").foregroundStyle(Color(hex: 0x1a1200)).font(.system(size: S(11.5), weight: .semibold))
                            .padding(.horizontal, 9).padding(.vertical, 3).background(Capsule().fill(Brand.amber))
                    }
                } else if AppUpdater.shared.enabled {
                    Button("Check for updates") { close(); AppUpdater.shared.checkForUpdates() }
                }
            }
            .buttonStyle(.plain).font(.system(size: S(11.5))).foregroundStyle(Brand.amber)
        }
        .padding(16).frame(width: 380)
    }
}
