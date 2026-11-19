import Foundation

// MARK: - Session flow (request r261119-094953)
//
// 1. Active sessions first: the tabs are ordered needs you → rowing → warming up → idle → wrapped / ended.
// 2. Wrapped sessions: the work is through its cycle (released, done, ended) → dimmed, "done", one click closes them all.
//    Closing never loses anything: the Claude conversation stays resumable from the item.
// 3. One feature, one conversation: design (choice) → dev (road) → test → release share the same Claude session,
//    so the context is not rebuilt at every step. The thread of an item is the roadmap key result it belongs to.

extension BoardStore {
    /// The road refs ("road:<slug>") an item belongs to.
    func roads(of ref: String) -> Set<String> {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return [] }
        let (kind, id) = (parts[0], parts[1])
        func roadRef(_ textOrSlug: String) -> String? {
            let s = BoardFiles.slug(textOrSlug)
            return roadmap.first { $0.id == s || $0.id == textOrSlug || $0.text == textOrSlug }.map { "road:" + $0.id }
        }
        switch kind {
        case "road": return [ref]
        case "test": return Set(ships.first { $0.id == id }?.roads.compactMap(roadRef) ?? [])
        case "choice": return Set(ships.filter { $0.choices.contains(id) }.flatMap { $0.roads.compactMap(roadRef) })
        case "request":
            let became = RequestLog.load(project.boardDir).first { $0.id == id }?.became ?? []
            var out = Set(became.filter { $0.hasPrefix("road:") })
            for b in became where !b.hasPrefix("road:") && !b.hasPrefix("track:") { out.formUnion(roads(of: b)) }
            if let r = roadmap.first(where: { $0.request == id }) { out.insert("road:" + r.id) }
            return out
        default: return []
        }
    }

    /// Every board item of the same feature as `ref`: its key result(s), the deliveries for them, the choices they built,
    /// the requests that became them. Includes `ref` itself.
    func thread(of ref: String) -> Set<String> { memoized("thread:" + ref) { computeThread(of: ref) } }
    private func computeThread(of ref: String) -> Set<String> {
        let roads = roads(of: ref)
        var out: Set<String> = [ref]
        // Same origin (the request or item that asked them) → same piece of work: the origin and all its choices.
        let origin = ref.hasPrefix("choice:") ? decisions.first { "choice:" + $0.id == ref }?.origin : ref
        if let origin {
            let siblings = decisions.filter { $0.origin == origin }.map { "choice:" + $0.id }
            if !siblings.isEmpty { out.insert(origin); out.formUnion(siblings) }
        }
        guard !roads.isEmpty else { return out }
        out.formUnion(roads)
        for s in ships where !roads.isDisjoint(with: Set(s.roads.compactMap { r in
            roadmap.first { $0.id == BoardFiles.slug(r) || $0.text == r }.map { "road:" + $0.id } })) {
            out.insert("test:" + s.id)
            out.formUnion(s.choices.map { "choice:" + $0 })
        }
        for r in roadmap where roads.contains("road:" + r.id) { if let q = r.request { out.insert("request:" + q) } }
        return out
    }

    /// Is this item through its cycle? Released (live), done, request closed, choice built and its delivery live.
    func isFinished(_ ref: String) -> Bool {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let id = parts[1]
        switch parts[0] {
        case "test": return ships.first { $0.id == id }?.status == "live"
        case "road": return roadmap.first { $0.id == id }?.status == "done"
        case "choice":
            guard let d = decisions.first(where: { $0.id == id }), isBuilt(d) else { return false }
            let built = ships.filter { $0.choices.contains(id) }
            return !built.isEmpty && built.allSatisfy { $0.status == "live" }
        case "request":
            guard let r = RequestLog.load(project.boardDir).first(where: { $0.id == id }) else { return false }
            if ["done", "discarded"].contains(r.status) { return true }
            let roads = r.became.filter { $0.hasPrefix("road:") }
            return !roads.isEmpty && roads.allSatisfy(isFinished)
        case "track":
            let items = roadmap.filter { BoardFiles.slug($0.track) == id }
            return !items.isEmpty && items.allSatisfy { $0.status == "done" }
        default: return false
        }
    }

    /// Latest Claude conversation started for any item of the thread (newest first).
    func lastLink(inThread refs: Set<String>) -> SessionLink? {
        links.filter { refs.contains($0.item) }.max { $0.started < $1.started }
    }
}

extension AppModel {
    /// Finished: the process ended, or Claude is idle and every item it covers is through its cycle.
    func isWrapped(_ s: TerminalSession) -> Bool {
        if !s.running { return true }
        guard s.kind == .claude, s.status == .idle,
              let p = projects.first(where: { $0.id == s.projectId }), let item = s.item else { return false }
        let b = board(for: p)
        let refs = [item.ref] + s.alsoRefs
        return refs.allSatisfy(b.isFinished)
    }

    /// Tabs in the order that matters: needs you, rowing, warming up, idle, shells, wrapped. Stable inside a group.
    func orderedSessions(of projectId: String) -> [TerminalSession] {
        func rank(_ s: TerminalSession) -> Int {
            if isWrapped(s) { return 9 }
            if s.kind != .claude { return 5 }
            switch s.status { case .waiting: return 0; case .working: return 1; case .starting: return 2; case .idle: return 3; case .ended: return 9 }
        }
        return sessions(of: projectId).enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    func wrappedSessions(of projectId: String) -> [TerminalSession] { sessions(of: projectId).filter(isWrapped) }

    /// "Close N done": the conversations stay resumable from their items.
    func closeWrapped(projectId: String) {
        for s in wrappedSessions(of: projectId) { close(s) }
    }

    /// A live session already working on the same feature (thread), other than the item itself.
    func liveThreadSession(projectId: String, ref: String) -> TerminalSession? {
        guard let p = projects.first(where: { $0.id == projectId }) else { return nil }
        let refs = board(for: p).thread(of: ref)
        guard refs.count > 1 else { return nil }
        return sessions.first { $0.projectId == projectId && $0.kind == .claude && $0.running && refs.contains(where: $0.covers) }
    }
}

// MARK: - Test hook: `--flow-demo ref1,ref2,…[;status,…]` (background instances only)
// Prints each ref's thread + finished state, dry-starts them in order (same feature → same session),
// then sets the given hook statuses on the resulting sessions so the tab order and "done" state can be seen.
enum SessionFlowDemo {
    static func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
    @MainActor static func run(_ m: AppModel, _ arg: String) {
        guard CommandLine.arguments.contains("--background"), let p = m.project else { return }
        let parts = arg.split(separator: ";").map(String.init)
        let refs = parts[0].split(separator: ",").map(String.init)
        let statuses = parts.count > 1 ? parts[1].split(separator: ",").map(String.init) : []
        let b = m.board(for: p)
        for r in refs {
            log("[flow] \(r) finished=\(b.isFinished(r)) thread=\(b.thread(of: r).sorted())")
        }
        for r in refs {
            guard let ref = ItemRef(ref: r) else { continue }
            let before = m.sessions.count
            let s = m.start(projectId: p.id, item: ref, intent: m.naturalIntent(BoardFiles.resolve(ref, in: p), in: p), dry: true)
            log("[flow] start \(r) → \(m.sessions.count > before ? "new session" : "continued in \(s?.title ?? "-")")")
        }
        for (s, st) in zip(m.sessions(of: p.id), statuses) {
            if st == "ended" { s.running = false; s.status = .ended } else if let v = SessionStatus(rawValue: st) { s.status = v; s.statusAt = Date().addingTimeInterval(-600) }
        }
        m.sessionsChanged()
        log("[flow] order: " + m.orderedSessions(of: p.id).map { "\($0.title)\(m.isWrapped($0) ? " (done)" : "")" }.joined(separator: " | "))
    }
}
