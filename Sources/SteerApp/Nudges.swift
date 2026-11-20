import SwiftUI
import AppKit

/// An answer of yours (verdict, note, pick, agreed requirement) and what Steerify does with it.
struct Nudge: Identifiable, Equatable {
    enum Kind: Equatable { case noSession(resumable: Bool), waiting(String), sent(String) }
    var id: String { projectId + "|" + ref }
    let projectId: String
    let ref: String            // the item the next step is about ("test:…", "choice:…", "reqs:…")
    let title: String
    let reason: String         // "Refine", "Picked B", "Agreed"
    let intent: Intent
    let at: String             // when you answered (ISO)
    var kind: Kind
}

extension AppModel {
    static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()

    /// Your answers that ask for a next step, per project.
    func answers(_ p: Project) -> [(ref: String, title: String, reason: String, intent: Intent, at: String)] {
        let b = board(for: p)
        var out: [(String, String, String, Intent, String)] = []
        for s in b.ships {
            let v = b.verdict("ship:" + s.id)
            guard v.v == s.version, let at = v.at else { continue }
            switch b.effectivePick(s) {
            case "refine": out.append(("test:" + s.id, s.title, "Refine", .fix, at))
            case "broken": out.append(("test:" + s.id, s.title, "Broken", .fix, at))
            case "ok" where s.status != "live": out.append(("test:" + s.id, s.title, "OK → release", .release, at))
            default: break
            }
        }
        for d in b.decisions where b.isDecided(d) && !b.isBuilt(d) {
            let v = b.verdict(d.id)
            guard let at = v.at else { continue }
            let mixed = b.mix(d).compactMap { m in d.options.first { $0.id == m }?.label.components(separatedBy: " · ").first }
            // "__note" = you answered with a note only (no option): show the note, never the internal id.
            let reason: String
            if let opt = d.options.first(where: { $0.id == v.pickString }) {
                reason = "Picked " + opt.label + (mixed.isEmpty ? "" : " + mix " + mixed.joined(separator: ", "))
            } else {
                let note = v.note.trimmingCharacters(in: .whitespacesAndNewlines)
                reason = note.isEmpty ? "Answered" : "Your note: “\(note)”"
            }
            out.append(("choice:" + d.id, d.title, reason, .build, at))
        }
        // Requirement verdicts move their chapter.
        var chapters: [String: (String, String)] = [:]
        for r in b.requirements {
            let v = b.verdict("req:" + r.id)
            // Agreeing / confirming needs no work; only a requested change (or a written answer) does.
            guard let pick = v.pickString, pick == "change" || (!v.note.isEmpty && pick != "later"), let at = v.at else { continue }
            let key = "reqs:" + BoardFiles.slug(r.group)
            if (chapters[key]?.1 ?? "") < at { chapters[key] = (r.group, at) }
            _ = pick
        }
        for (k, v) in chapters { out.append((k, "Requirements: " + v.0, "Requirements answered", .resume, v.1)) }
        return out.map { (ref: $0.0, title: $0.1, reason: $0.2, intent: $0.3, at: $0.4) }
    }

    private var handled: [String: String] {
        get { Prefs.store.dictionary(forKey: "nudgeHandled") as? [String: String] ?? [:] }
        set { Prefs.store.set(newValue, forKey: "nudgeHandled") }
    }
    /// Only answers given after Steerify started doing this are acted on (no surprise pings on old items).
    private var baseline: String {
        if let b = Prefs.store.string(forKey: "nudgeBaseline") { return b }
        let now = BoardStore.now(); Prefs.store.set(now, forKey: "nudgeBaseline"); return now
    }

    func autoPing(_ p: Project) -> Bool { p.automation?.pingIdle ?? Prefs.store.object(forKey: "autoPing") as? Bool ?? true }
    func pingDelay(_ p: Project) -> TimeInterval { TimeInterval(p.automation?.delaySeconds ?? 30) }

    /// The live session that should hear about an answer: the item's own, else (requirements) its chapter's.
    func liveSession(for ref: String, in p: Project) -> TerminalSession? {
        sessions.first { $0.projectId == p.id && $0.covers(ref) && $0.running }
    }

    /// A request filed in any project (a request can be filed in one project and worked on another's board).
    func findRequest(_ id: String) -> BoardRequest? {
        for p in projects { if let r = RequestLog.load(p.boardDir).first(where: { $0.id == id }) { return r } }
        return nil
    }

    /// Run on every board change, every session state change and once a minute.
    func evaluateNudges() {
        let testCopy = CommandLine.arguments.contains("--background")
        let iso = Self.iso
        var list: [Nudge] = []
        var done = handled
        let base = baseline
        for p in projects {
            for a in answers(p) where a.at > base && a.at > (done[p.id + "|" + a.ref] ?? "") {
                let key = p.id + "|" + a.ref
                if let s = liveSession(for: a.ref, in: p) {
                    switch s.status {
                    case .idle:
                        let answeredAgo = -(iso.date(from: a.at)?.timeIntervalSinceNow ?? -999)
                        if autoPing(p) && !testCopy && answeredAgo >= pingDelay(p) {
                            s.view.send(txt: "/steerify \(a.intent.rawValue) \(a.ref)\r")
                            done[key] = a.at
                            recentPings.insert(Nudge(projectId: p.id, ref: a.ref, title: a.title, reason: a.reason, intent: a.intent,
                                                     at: a.at, kind: .sent(s.title)), at: 0)
                            recentPings = Array(recentPings.prefix(5))
                        } else if !autoPing(p) {
                            list.append(Nudge(projectId: p.id, ref: a.ref, title: a.title, reason: a.reason, intent: a.intent, at: a.at, kind: .waiting("idle · send it")))
                        }
                    case .waiting:
                        if notified.insert(key + a.at).inserted { Notify.send("Steerify · \(s.title)", "The session needs your answer before it can take your \(a.reason).") }
                        list.append(Nudge(projectId: p.id, ref: a.ref, title: a.title, reason: a.reason, intent: a.intent, at: a.at, kind: .waiting(s.title)))
                    default: break   // working / starting: it will be told when it stops
                    }
                } else if board(for: p).takenBySession(a.ref, since: a.at) {
                    continue      // a session already took this answer and ended: nothing to start, not yours to do
                } else {
                    let resumable = board(for: p).lastLink(a.ref).map { SessionLinks.resumable($0.claudeSession) } ?? false
                    list.append(Nudge(projectId: p.id, ref: a.ref, title: a.title, reason: a.reason, intent: a.intent, at: a.at, kind: .noSession(resumable: resumable)))
                }
            }
        }
        handled = done
        if list != nudges { nudges = list }
    }

    /// Act on a proposal: start (or resume) the session for that answer with its next step.
    func takeNudge(_ n: Nudge) {
        guard let p = projects.first(where: { $0.id == n.projectId }), var item = ItemRef(ref: n.ref) else { return }
        item = BoardFiles.resolve(item, in: p)
        if case .waiting = n.kind, let s = liveSession(for: n.ref, in: p) {
            selectedProjectId = p.id; selectedSession[p.id] = s.id
            if s.status == .idle { s.view.send(txt: "/steerify \(n.intent.rawValue) \(n.ref)\r"); markHandled(n) }
            return
        }
        start(projectId: p.id, item: item, intent: n.intent)
        markHandled(n)
    }

    func markHandled(_ n: Nudge) {
        var d = handled; d[n.id] = n.at; handled = d
        nudges.removeAll { $0.id == n.id }
    }
}

/// Answers about the same topic, handled by one combined session.
struct NudgeGroup: Identifiable {
    var id: String { key }
    let key: String            // track:<slug> when a roadmap chapter matches, else topic:<prefix>, else the item ref
    let title: String          // chapter or topic name
    let nudges: [Nudge]
}

extension AppModel {
    /// Answers that belong to one piece of work become one group (one session):
    /// 1. same origin: choices asked by the same request / item ("From request r…", `from`), that request itself,
    ///    and deliveries that built those choices;
    /// 2. same roadmap chapter, or the same title topic ("New request: …").
    /// A group is named after its chapter, else its request, else its topic.
    func groupedNudges(_ projectId: String) -> [NudgeGroup] {
        guard let p = projects.first(where: { $0.id == projectId }) else { return [] }
        let b = board(for: p)
        let mine = nudges.filter { $0.projectId == projectId }
        guard !mine.isEmpty else { return [] }

        // Keys each answer is connected by; answers sharing any key are merged (union–find).
        var keys: [[String]] = []
        for n in mine {
            var k = [n.ref]
            if let o = b.originKey(of: n.ref) { k.append(o) }
            let clean = n.title.replacingOccurrences(of: "^(Requirements|Chapter): ", with: "", options: .regularExpression)
            let prefix = clean.split(separator: ":", maxSplits: 1).count > 1 ? String(clean.split(separator: ":")[0]).trimmingCharacters(in: .whitespaces) : nil
            if let ch = b.roadChapter(for: prefix ?? clean) { k.append("track:" + BoardFiles.slug(ch.name)) }
            else if let prefix, mine.filter({ $0.title.hasPrefix(prefix + ":") }).count > 1 { k.append("topic:" + BoardFiles.slug(prefix)) }
            keys.append(k)
        }
        var parent = Array(mine.indices)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        var owner: [String: Int] = [:]
        for (i, ks) in keys.enumerated() {
            for k in ks {
                if let j = owner[k] { parent[find(i)] = find(j) } else { owner[k] = i }
            }
        }

        var order: [Int] = [], members: [Int: [Int]] = [:]
        for i in mine.indices {
            let r = find(i)
            if members[r] == nil { order.append(r) }
            members[r, default: []].append(i)
        }
        return order.map { r in
            let idx = members[r]!
            let ns = idx.map { mine[$0] }
            let all = Set(idx.flatMap { keys[$0] })
            if ns.count == 1, all.allSatisfy({ !$0.hasPrefix("track:") && !$0.hasPrefix("topic:") }) {
                return NudgeGroup(key: ns[0].ref, title: ns[0].title, nudges: ns)
            }
            // Name: a chapter (on this board) > the origin request > a topic > the first answer.
            if let req = all.sorted().first(where: { $0.hasPrefix("request:") }) {
                let id = String(req.dropFirst("request:".count))
                let q = findRequest(id)
                let track = (q?.became ?? []).first { $0.hasPrefix("track:") }
                    .flatMap { t in Set(b.roadmap.map(\.track)).first { "track:" + BoardFiles.slug($0) == t } }
                let text = q.map { $0.text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces) }
                let title = track ?? text.map { $0.count > 60 ? String($0.prefix(57)) + "…" : $0 } ?? ns[0].title
                return NudgeGroup(key: req, title: title, nudges: ns)
            }
            if let t = all.sorted().first(where: { $0.hasPrefix("track:") }),
               let name = Set(b.roadmap.map(\.track)).first(where: { "track:" + BoardFiles.slug($0) == t }) {
                return NudgeGroup(key: t, title: name, nudges: ns)
            }
            if let t = all.sorted().first(where: { $0.hasPrefix("topic:") }) {
                let clean = ns[0].title.replacingOccurrences(of: "^(Requirements|Chapter): ", with: "", options: .regularExpression)
                return NudgeGroup(key: t, title: String(clean.split(separator: ":")[0]).trimmingCharacters(in: .whitespaces), nudges: ns)
            }
            return NudgeGroup(key: ns[0].ref, title: ns[0].title, nudges: ns)
        }
    }

    /// One session for the whole group: briefed with every answer, linked to every item.
    func takeGroup(_ g: NudgeGroup) {
        guard let first = g.nudges.first else { return }
        if g.nudges.count == 1 { takeNudge(first); return }
        guard let p = projects.first(where: { $0.id == first.projectId }) else { return }
        let lines = g.nudges.map { "- \($0.ref) — \($0.reason): \($0.title)" }.joined(separator: "\n")
        let anchor: ItemRef = {
            if g.key.hasPrefix("track:"), var r = ItemRef(ref: g.key) { r.title = "Chapter: " + g.title; r.area = nil; return r }
            var r = ItemRef(ref: first.ref)!; r.title = g.title; return r
        }()
        var brief = "Act on these answers of the user together, as one piece of work (same topic: \(g.title)). Read each item's verdict and note with get_item first, plan once, then build:\n\(lines)"
        if g.key.hasPrefix("request:"), let q = findRequest(String(g.key.dropFirst("request:".count))) {
            brief += "\n\nThey all come from one request of the user (\(g.key)): \"\(q.text)\". Keep the work connected to it; finish with update_request."
        }
        if let s = start(projectId: p.id, item: anchor, intent: .build, extraBrief: brief, also: g.nudges.map(\.ref) + (g.key.hasPrefix("request:") ? [g.key] : [])) {
            s.title = SessionName.short(g.title, intent: "build")
        }
        g.nudges.forEach(markHandled)
    }
}

/// Above every other tab: one thin line ("2 ready to build · Open"); the full cards live in the READY tab.
struct NudgeStrip: View {
    @EnvironmentObject var model: AppModel
    let projectId: String
    var open: () -> Void = {}

    var body: some View {
        let groups = model.groupedNudges(projectId)
        let sent = model.recentPings.filter { $0.projectId == projectId }
        if groups.isEmpty, let last = sent.first, case .sent(let to) = last.kind {
            Text("Sent your \(last.reason) to “\(to)”").font(.system(size: S(12))).foregroundStyle(Brand.green)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 8)
        } else if !groups.isEmpty {
            HStack(spacing: 8) {
                PixelIcon(name: "play", size: S(9)).foregroundStyle(Brand.amber)
                Text("\(groups.count) ready to build").font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.cream)
                Text("· " + groups.prefix(2).map(\.title).joined(separator: " · ") + (groups.count > 2 ? " …" : ""))
                    .font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                Button("Open ⌘1", action: open)
                    .buttonStyle(SteerButton()).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.amber)
                    .help("The READY tab: every answer, Set sail, Start all")
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Brand.amberDim.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.amber.opacity(0.3)))
            .contentShape(Rectangle()).onTapGesture(perform: open)
            .padding(.horizontal, 12).padding(.top, 8)
        }
    }
}

/// The READY tab: your answers that wait for a session, one card per topic, with every answer.
struct ReadyScreen: View {
    @EnvironmentObject var model: AppModel
    let projectId: String
    @State private var open = Set<String>()

    var body: some View {
        let groups = model.groupedNudges(projectId)
        let sent = model.recentPings.filter { $0.projectId == projectId }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !groups.isEmpty {
                    HStack(spacing: 10) {
                        Text("YOU ANSWERED · READY TO BUILD").font(Brand.label(10)).tracking(0.9).foregroundStyle(Brand.amber)
                        Text("Claude reads your picks and notes first").font(.system(size: S(11))).foregroundStyle(Brand.mute)
                        Spacer()
                        if groups.count > 1 {
                            ActionButton(title: "Start all · \(groups.count) sessions", primary: true) { groups.forEach(model.takeGroup) }
                        }
                    }
                    ForEach(groups) { card($0) }
                } else {
                    EmptyBoard(projectId: projectId, title: "NOTHING READY", line: "Answer a choice or a test and it lands here.")
                }
                if !sent.isEmpty {
                    Text("SENT TO A SESSION").font(Brand.label(9)).tracking(0.9).foregroundStyle(Brand.mute).padding(.top, 8)
                    ForEach(sent) { n in
                        if case .sent(let to) = n.kind {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane").font(.system(size: S(10))).foregroundStyle(Brand.green)
                                Text(n.reason).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.cream)
                                Text("· \(n.title) → “\(to)”").font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func card(_ g: NudgeGroup) -> some View {
        let many = g.nudges.count > 1
        let resumable = !many && { if case .noSession(true) = g.nudges[0].kind { return true }; return false }()
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(many ? "\(g.nudges.count) ANSWERS" : "1 ANSWER").font(Brand.label(9)).tracking(0.9).foregroundStyle(Brand.amber)
                Text(g.title).font(.system(size: S(15), weight: .bold)).foregroundStyle(.white).lineLimit(2)
                let shown = open.contains(g.key) ? g.nudges : Array(g.nudges.prefix(4))
                ForEach(shown) { n in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: S(9), weight: .bold)).foregroundStyle(Brand.green)
                        Text(n.reason).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.cream).lineLimit(1)
                        let what = n.title.split(separator: ":", maxSplits: 1).count > 1 && many ? String(n.title.split(separator: ":", maxSplits: 1)[1]).trimmingCharacters(in: .whitespaces) : n.title
                        if what != g.title { Text("· " + what).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(1) }
                        Spacer(minLength: 0)
                        Button { model.markHandled(n) } label: { Image(systemName: "xmark").font(.system(size: S(8), weight: .bold)) }
                            .buttonStyle(SteerButton()).foregroundStyle(Brand.mute.opacity(0.7)).help("Not now")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if let p = model.projects.first(where: { $0.id == n.projectId }) { model.openCombo(projectId: p.id, ref: n.ref, startNew: false) } }
                }
                if g.nudges.count > 4 {
                    Button(open.contains(g.key) ? "less" : "+\(g.nudges.count - 4) more") { if open.contains(g.key) { open.remove(g.key) } else { open.insert(g.key) } }
                        .buttonStyle(.link).font(.system(size: S(11)))
                }
            }
            Spacer(minLength: 8)
            PixelCTA(title: resumable ? "Back to it" : "Set sail",
                     subtitle: many ? "\(g.nudges.count) answers · 1 session" : (resumable ? "resume its conversation" : "Claude starts, briefed")) { model.takeGroup(g) }
                .help(many ? "One Claude session for all of these, briefed with every answer" : "A Claude session on it, already briefed")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Brand.amberDim, Brand.panel], startPoint: .leading, endPoint: .trailing)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.amber.opacity(0.45)))
    }
}
