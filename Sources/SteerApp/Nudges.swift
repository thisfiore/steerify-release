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
        sessions.first { $0.projectId == p.id && $0.covers(ref) && $0.running } ?? originSession(for: ref, in: p)
    }

    /// The live session that asked a choice (its `from`: the request / item it was started from), so your pick goes
    /// straight back to it instead of waiting for Set sail.
    func originSession(for ref: String, in p: Project) -> TerminalSession? {
        guard ref.hasPrefix("choice:"), let o = board(for: p).originKey(of: ref) else { return nil }
        return sessions.first { $0.projectId == p.id && $0.covers(o) && $0.running }
    }

    /// Choices asked by the same origin that you have not answered yet: they are built together, so the asking session
    /// is pinged once you have answered all of them.
    func openSiblings(of ref: String, in p: Project) -> [String] {
        let b = board(for: p)
        guard let o = b.originKey(of: ref) else { return [] }
        return b.decisions.filter { "choice:" + $0.id != ref && $0.origin == o && !b.isDecided($0) && !b.verdict($0.id).parked && $0.built == nil }
            .map { "choice:" + $0.id }
    }

    /// A request filed in any project (a request can be filed in one project and worked on another's board).
    func findRequest(_ id: String) -> BoardRequest? {
        for p in projects { if let r = RequestLog.load(p.boardDir).first(where: { $0.id == id }) { return r } }
        return nil
    }

    /// Run on every board change, every session state change and once a minute.
    func evaluateNudges() {
        let testCopy = CommandLine.arguments.contains("--background") && !CommandLine.arguments.contains("--origin-ping-demo")
        let iso = Self.iso
        var list: [Nudge] = []
        var done = handled
        let base = baseline
        // Answers ready for an idle session, sent as one line per session (several picks of one request = one ping).
        var outbox: [ObjectIdentifier: (s: TerminalSession, p: Project, items: [(ref: String, title: String, reason: String, intent: Intent, at: String)])] = [:]
        for p in projects {
            for a in answers(p) where a.at > base && a.at > (done[p.id + "|" + a.ref] ?? "") {
                let key = p.id + "|" + a.ref
                let direct = sessions.first { $0.projectId == p.id && $0.covers(a.ref) && $0.running }
                if direct == nil, originSession(for: a.ref, in: p) != nil, !openSiblings(of: a.ref, in: p).isEmpty {
                    continue      // the asking session hears about it once its other choices are answered too
                }
                if let s = direct ?? originSession(for: a.ref, in: p) {
                    switch s.status {
                    case .idle:
                        if autoPing(p) && !testCopy {
                            outbox[ObjectIdentifier(s), default: (s, p, [])].items.append(a)
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
        for (_, box) in outbox {
            let (s, p, items) = box
            // Wait the delay after your last answer (time to change your mind), then one line for all of them.
            guard let newest = items.map(\.at).max(), -(iso.date(from: newest)?.timeIntervalSinceNow ?? -999) >= pingDelay(p) else { continue }
            let first = items[0]
            let rest = items.dropFirst().map { "\($0.intent.rawValue) \($0.ref)" }
            let line = "/steerify \(first.intent.rawValue) \(first.ref)" + (rest.isEmpty ? "" : " (also: " + rest.joined(separator: ", ") + ")")
            NSLog("steerify ping → \(s.title): \(line)")
            s.view.send(txt: line + "\r")
            for a in items {
                done[p.id + "|" + a.ref] = a.at
                if !s.covers(a.ref) {   // the session now owns it (status, later notes, resume from the item)
                    s.alsoRefs.append(a.ref)
                    if let cid = s.claudeId {
                        SessionLinks.append(SessionLink(item: a.ref, claudeSession: cid, intent: a.intent.rawValue, repo: s.repo.name,
                                                        title: s.title, started: BoardStore.now(), dir: s.workdir), in: p.boardDir)
                    }
                }
                recentPings.insert(Nudge(projectId: p.id, ref: a.ref, title: a.title, reason: a.reason, intent: a.intent,
                                         at: a.at, kind: .sent(s.title)), at: 0)
            }
            recentPings = Array(recentPings.prefix(5))
        }
        handled = done
        if list != nudges { nudges = list }
        flushDeployWakes()
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
        // OK → release is not work to build: it waits in READY TO RELEASE (releasable), one release for many items.
        let mine = nudges.filter { $0.projectId == projectId && $0.intent != .release }
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

// MARK: - Ready to release (request r261121-095606, choice ready-release-vs-build)

extension AppModel {
    /// Approved on To test (OK), not live yet: what the next release takes. Oldest OK first.
    func releasable(_ projectId: String) -> [ShipItem] {
        guard let p = projects.first(where: { $0.id == projectId }) else { return [] }
        let b = board(for: p)
        return b.ships.filter { b.shipState($0) == .ok && $0.status != "live" }
            .sorted { (b.verdict("ship:" + $0.id).at ?? "") < (b.verdict("ship:" + $1.id).at ?? "") }
    }

    /// Items you unticked: they stay approved and wait for a later release.
    func releaseSkipped(_ projectId: String) -> Set<String> {
        Set(Prefs.store.stringArray(forKey: "releaseSkip." + projectId) ?? [])
    }
    func setReleaseSkipped(_ projectId: String, _ ids: Set<String>) {
        Prefs.store.set(Array(ids).sorted(), forKey: "releaseSkip." + projectId)
        objectWillChange.send()
    }

    /// One session that releases the ticked items together, briefed with your release note.
    func startRelease(projectId: String, items: [ShipItem], skipped: [ShipItem], note: String) {
        guard let p = projects.first(where: { $0.id == projectId }), !items.isEmpty else { return }
        let flow = WorkFlow.of(p)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var brief = "Release only these \(items.count) approved item\(items.count == 1 ? "" : "s") together, as one release (branches: \(flow.title)):\n"
            + items.map { "- test:\($0.id) — \($0.title)" }.joined(separator: "\n")
        if !skipped.isEmpty {
            brief += "\n\nLeave these out (they stay approved and wait for a later release; do not ship their changes):\n"
                + skipped.map { "- test:\($0.id) — \($0.title)" }.joined(separator: "\n")
        }
        if !note.isEmpty { brief += "\n\nThe user's release note (follow it: version, what to include or hide, who gets it):\n" + note }
        if items.count == 1 && flow != .main {
            // One feature on its own branch / PR: its own release, in its own thread.
            var x = ItemRef(ref: "test:" + items[0].id)!; x.title = items[0].title; x.area = items[0].area
            start(projectId: p.id, item: x, intent: .release, extraBrief: note.isEmpty ? nil : "Release note from the user: " + note)
        } else {
            var x = ItemRef(ref: "release:" + p.id)!; x.title = "Release: " + p.name
            start(projectId: p.id, item: x, intent: .ship, extraBrief: brief, also: items.map { "test:" + $0.id })
        }
        let refs = Set(items.map { "test:" + $0.id })
        nudges.filter { $0.projectId == p.id && refs.contains($0.ref) }.forEach(markHandled)
    }
}

/// Above every other tab: one thin line ("2 ready to build · Open"); the full cards live in the READY tab.
struct NudgeStrip: View {
    @EnvironmentObject var model: AppModel
    let projectId: String
    var open: () -> Void = {}

    var body: some View {
        let groups = model.groupedNudges(projectId)
        let rel = model.releasable(projectId).count
        let sent = model.recentPings.filter { $0.projectId == projectId }
        if groups.isEmpty && rel == 0, let last = sent.first, case .sent(let to) = last.kind {
            Text("Sent your \(last.reason) to “\(to)”").font(.system(size: S(12))).foregroundStyle(Brand.green)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 8)
        } else if !groups.isEmpty || rel > 0 {
            HStack(spacing: 8) {
                if rel > 0 {
                    PixelIcon(name: "rocket", size: S(10)).foregroundStyle(Brand.green)
                    Text("\(rel) to release").font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.cream)
                }
                if rel > 0 && !groups.isEmpty { Text("·").foregroundStyle(Brand.mute) }
                if !groups.isEmpty {
                    PixelIcon(name: "boat", size: S(10)).foregroundStyle(Brand.amber)
                    Text("\(groups.count) to build").font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.cream)
                    Text("· " + groups.prefix(2).map(\.title).joined(separator: " · ") + (groups.count > 2 ? " …" : ""))
                        .font(.system(size: S(11.5))).foregroundStyle(Brand.mute).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Button("Open ⌘1", action: open)
                    .buttonStyle(SteerButton()).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.amber)
                    .help("The READY tab: what to release, what to build")
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
    private var project: Project? { model.projects.first { $0.id == projectId } }

    var body: some View {
        let groups = model.groupedNudges(projectId)
        let rel = model.releasable(projectId)
        let sent = model.recentPings.filter { $0.projectId == projectId }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !rel.isEmpty, let p = project {
                    HStack(spacing: 10) {
                        Text("READY TO RELEASE").font(Brand.label(10)).tracking(0.9).foregroundStyle(Brand.green)
                        Text("you said OK · not live yet").font(.system(size: S(11))).foregroundStyle(Brand.mute)
                    }
                    ReleaseReadyCard(project: p, items: rel)
                        .padding(.bottom, groups.isEmpty ? 0 : 10)
                }
                if !groups.isEmpty {
                    HStack(spacing: 10) {
                        Text("READY TO BUILD").font(Brand.label(10)).tracking(0.9).foregroundStyle(Brand.amber)
                        Text("your picks and notes · Claude reads them first").font(.system(size: S(11))).foregroundStyle(Brand.mute)
                        Spacer()
                        if groups.count > 1 {
                            ActionButton(title: "Start all · \(groups.count) sessions", primary: true) { groups.forEach(model.takeGroup) }
                        }
                    }
                    ForEach(groups) { card($0) }
                } else if !rel.isEmpty {
                    EmptyView()
                } else if let p = project, model.whereYouLeftOff(p).isEmpty && model.nextSteps(p).isEmpty {
                    EmptyBoard(projectId: projectId, title: "NOTHING READY", line: "Answer a choice or a test and it lands here.", kind: .ready)
                } else {
                    // Nothing answered yet: a small scene and what lands here, then where you left off below.
                    HStack(spacing: 16) {
                        TabScene(kind: .ready, height: 72).frame(width: S(230))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NOTHING ANSWERED YET").font(Brand.label(10)).tracking(1).foregroundStyle(Brand.cream)
                            Text("Pick a choice or send a test back: it lands here, ready for Claude.").font(.system(size: S(12))).foregroundStyle(Brand.mute)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel.opacity(0.6)))
                }
                if let p = project, !groups.isEmpty || !rel.isEmpty || !(model.whereYouLeftOff(p).isEmpty && model.nextSteps(p).isEmpty) {
                    LeftOffSection(project: p).padding(.top, groups.isEmpty && rel.isEmpty ? 6 : 18)
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
                     subtitle: many ? "\(g.nudges.count) answers · 1 session" : (resumable ? "resume its conversation" : "Claude starts, briefed"),
                     icon: "boat") { model.takeGroup(g) }
                .help(many ? "One Claude session for all of these, briefed with every answer" : "A Claude session on it, already briefed")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Brand.amberDim, Brand.panel], startPoint: .leading, endPoint: .trailing)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.amber.opacity(0.45)))
    }
}

/// READY TO RELEASE: every approved change in one card. Tick what goes in, add a release note, one session ships it.
/// The tip follows how the project uses git (release.flow): on main one release is the simple way; with
/// worktrees / pull requests each feature can also ship on its own.
struct ReleaseReadyCard: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    let items: [ShipItem]
    @State private var note = ""

    private var flow: WorkFlow { WorkFlow.of(project) }
    private var noteKey: String { "releaseNote." + project.id }
    private var tip: String {
        switch flow {
        case .main: return "You work on main: these changes are already together. One release with all of them is the simple way. Untick what should wait."
        case .worktree: return "Each feature is on its own branch: ship one on its own, or all together in one session (merged oldest first)."
        case .pr: return "Each feature is its own pull request: merge and ship one, or all together in one session (oldest first)."
        }
    }

    var body: some View {
        let skip = model.releaseSkipped(project.id)
        let picked = items.filter { !skip.contains($0.id) }
        let left = items.filter { skip.contains($0.id) }
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                PixelIcon(name: "rocket", size: S(24)).foregroundStyle(Brand.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(items.count) approved change\(items.count == 1 ? "" : "s")").font(.system(size: S(15), weight: .bold)).foregroundStyle(.white)
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: S(9.5)))
                        Text(flow.short).font(.system(size: S(10.5), design: .monospaced))
                    }
                    .foregroundStyle(Brand.cream).padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Brand.panel2)).overlay(Capsule().stroke(Brand.line))
                    .help("Branches: " + flow.title + ". " + flow.note)
                }
                Spacer(minLength: 8)
                PixelCTA(title: picked.count == items.count ? (flow == .main ? "Release all \(items.count)" : "Ship all \(items.count)")
                                                             : "Release \(picked.count) of \(items.count)",
                         subtitle: picked.count == 1 && flow != .main ? "its own release" : "one release · 1 session",
                         color: Brand.green, icon: "rocket") {
                    model.startRelease(projectId: project.id, items: picked, skipped: left, note: note)
                    note = ""; Prefs.store.removeObject(forKey: noteKey)
                }
                .disabled(picked.isEmpty).opacity(picked.isEmpty ? 0.4 : 1)
                .help("One Claude session releases the ticked items, following the release setup and your note")
            }
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "lightbulb").font(.system(size: S(10.5))).foregroundStyle(Brand.amber).padding(.top, 1)
                Text(tip).font(.system(size: S(11.5))).foregroundStyle(Brand.cream).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel2))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.line))
            ForEach(items) { s in row(s, on: !skip.contains(s.id)) }
            VStack(alignment: .leading, spacing: 4) {
                Text("RELEASE NOTE · OPTIONAL").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.mute)
                TextField("For Claude: major or minor? Leave something out? Hide a half-done feature behind a flag? Only for some users?",
                          text: $note, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: S(12))).foregroundStyle(Brand.ink)
                    .lineLimit(2...6)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Brand.bg.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.line))
                    .onChange(of: note) { _, v in Prefs.store.set(v, forKey: noteKey) }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Brand.green.opacity(0.12), Brand.panel], startPoint: .leading, endPoint: .trailing)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.green.opacity(0.45)))
        .onAppear { if note.isEmpty { note = Prefs.store.string(forKey: noteKey) ?? "" } }
    }

    private func row(_ s: ShipItem, on: Bool) -> some View {
        let at = model.board(for: project).verdict("ship:" + s.id).at.flatMap { AppModel.iso.date(from: $0) }
        return HStack(spacing: 9) {
            Button {
                var skip = model.releaseSkipped(project.id)
                if on { skip.insert(s.id) } else { skip.remove(s.id) }
                model.setReleaseSkipped(project.id, skip)
            } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: S(13)))
                    .foregroundStyle(on ? Brand.green : Brand.mute)
            }
            .buttonStyle(SteerButton()).help(on ? "Leave it for a later release" : "Put it in this release")
            Text(s.title).font(.system(size: S(12.5), weight: .medium)).foregroundStyle(on ? Brand.ink : Brand.mute).lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture { model.openCombo(projectId: project.id, ref: "test:" + s.id, startNew: false) }
            if !on { Text("waits").font(.system(size: S(10.5))).foregroundStyle(Brand.amber) }
            Spacer(minLength: 6)
            if let at { Text("OK " + at.formatted(.dateTime.day().month(.abbreviated))).font(.system(size: S(11))).foregroundStyle(Brand.mute) }
            if flow != .main {
                Button("Ship") { model.startRelease(projectId: project.id, items: [s], skipped: [], note: note) }
                    .buttonStyle(SteerButton()).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.green)
                    .help("Release just this feature (its branch / pull request)")
            }
        }
        .padding(.vertical, 1)
    }
}
