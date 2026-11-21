import SwiftUI

/// A chapter you were working on, from real activity (sessions, deliveries, work in progress).
struct ChapterResume: Identifiable {
    var id: String { track }
    let track: String
    let area: String
    let done: Int, total: Int
    let lastAt: Date?
    let lastWhat: String
    let next: String?
}

extension AppModel {
    func whereYouLeftOff(_ p: Project, limit: Int = 3) -> [ChapterResume] {
        let b = board(for: p)
        let iso = AppModel.iso, plain = ISO8601DateFormatter()
        func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) ?? plain.date(from: $0) } }
        let tracks = Dictionary(grouping: b.roadmap, by: \.track)
        func trackOf(ref: String, title: String?) -> String? { chapterOf(ref: ref, title: title, in: b) }
        var last: [String: (Date, String)] = [:]
        func note(_ t: String?, _ d: Date?, _ what: String) {
            guard let t, let d else { return }
            if d > (last[t]?.0 ?? .distantPast) { last[t] = (d, what) }
        }
        for l in b.links { note(trackOf(ref: l.item, title: l.title), date(l.started), SessionName.short(l.title ?? l.item, intent: l.intent)) }
        for s in sessions where s.projectId == p.id { if let r = s.item?.ref { note(trackOf(ref: r, title: s.item?.title), s.statusAt ?? Date(), s.title + " · " + s.moodWord) } }
        for s in b.ships { note(trackOf(ref: "test:" + s.id, title: s.title), date(s.updated), "delivered “\(s.title.prefix(40))\(s.title.count > 40 ? "…" : "")”") }
        // Chapters with work in progress count too, a little behind real activity.
        for (t, items) in tracks where items.contains(where: { $0.status == "wip" }) && last[t] == nil {
            note(t, Date().addingTimeInterval(-3 * 86400), "in progress: " + (items.first { $0.status == "wip" }?.text.prefix(40) ?? ""))
        }
        let order = ["wip": 0, "you": 1, "review": 2, "todo": 3]
        return last.compactMap { t, v -> ChapterResume? in
            guard let items = tracks[t] else { return nil }
            guard items.contains(where: { $0.status != "done" }) else { return nil }
            let core = ChapterProgress(items)          // progress = the core; extras never make it look behind
            let done = core.coreDone
            let next = items.filter { $0.status != "done" }.sorted { (order[$0.status] ?? 9) < (order[$1.status] ?? 9) }.first?.text
            return ChapterResume(track: t, area: items.first?.area ?? "", done: done, total: core.core.count, lastAt: v.0, lastWhat: v.1, next: next)
        }
        .sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
        .prefix(limit).map { $0 }
    }

    /// The roadmap chapter a board item belongs to (track ref, key result, delivery's road, or the session title).
    func chapterOf(ref: String, title: String?, in b: BoardStore) -> String? {
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "track": if let t = b.roadmap.first(where: { BoardFiles.slug($0.track) == parts[1] })?.track { return t }
        case "road": if let t = b.roadmap.first(where: { $0.id == parts[1] })?.track { return t }
        case "test":
            if let s = b.ships.first(where: { $0.id == parts[1] }), let r = s.roads.first,
               let t = b.roadmap.first(where: { $0.text == r || $0.id == BoardFiles.slug(r) })?.track { return t }
        default: break
        }
        guard let t = title else { return nil }
        let clean = t.replacingOccurrences(of: "^(Chapter|Requirements|Consolidate|Release): ", with: "", options: .regularExpression)
        return b.roadChapter(for: clean.components(separatedBy: ":").first ?? clean)?.name ?? b.roadChapter(for: clean)?.name
    }

    func resumeChapter(_ c: ChapterResume, in p: Project) {
        var x = ItemRef(ref: "track:" + BoardFiles.slug(c.track))!; x.title = "Chapter: " + c.track; x.area = c.area
        start(projectId: p.id, item: x, intent: .resume)
    }
}

/// "Where you left off": the chapters you were really on, visual, one big way back in.
struct ResumeChapters: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    var compact = false
    var limit = 3
    var showHeader = true

    var body: some View {
        let list = model.whereYouLeftOff(project, limit: compact ? 2 : limit)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if showHeader { Text("WHERE YOU LEFT OFF").font(Brand.label(9.5)).tracking(1).foregroundStyle(Brand.amber) }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, c in card(c, hero: i == 0) }
            }
        }
    }

    private func card(_ c: ChapterResume, hero: Bool) -> some View {
        let live = model.sessions.first { $0.projectId == project.id && $0.covers("track:" + BoardFiles.slug(c.track)) && $0.running }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                AutoIcon(title: c.track, size: S(hero ? 46 : 34), tile: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.track.replacingOccurrences(of: "\\s*\\(\\d+ \\w+\\)$", with: "", options: .regularExpression))
                        .font(.system(size: S(hero ? 15 : 13), weight: .bold)).foregroundStyle(.white).lineLimit(2)
                    HStack(spacing: 8) {
                        PixelProgress(fraction: c.total == 0 ? 0 : Double(c.done) / Double(c.total), blocks: 12, working: true).frame(width: S(110))
                        Text("\(c.done)/\(c.total)").font(.system(size: S(11), weight: .semibold).monospacedDigit()).foregroundStyle(Brand.green)
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("LAST").font(Brand.label(8.5)).foregroundStyle(Brand.mute).frame(width: S(34), alignment: .leading)
                    Text(c.lastWhat).font(.system(size: S(11.5))).foregroundStyle(Brand.ink.opacity(0.85)).lineLimit(1)
                    if let d = c.lastAt { Text("· " + SessionChip.ago(AppModel.iso.string(from: d))).font(.system(size: S(11))).foregroundStyle(Brand.mute) }
                }
                if let n = c.next {
                    HStack(spacing: 6) {
                        Text("NEXT").font(Brand.label(8.5)).foregroundStyle(Brand.amber).frame(width: S(34), alignment: .leading)
                        Text(n).font(.system(size: S(11.5), weight: .medium)).foregroundStyle(Brand.cream).lineLimit(1)
                    }
                }
            }
            HStack {
                if hero {
                    PixelCTA(title: live == nil ? "Resume chapter" : "Back to it", subtitle: live == nil ? "Claude checks the state, then the next step" : "its session is open") {
                        if let live { model.selectedSession[project.id] = live.id } else { model.resumeChapter(c, in: project) }
                    }
                } else {
                    ClaudeButton(title: live == nil ? "Resume chapter" : "Back to its session") {
                        if let live { model.selectedSession[project.id] = live.id } else { model.resumeChapter(c, in: project) }
                    }
                }
                Spacer()
                Button("Open on the roadmap") {
                    if let first = model.board(for: project).roadmap.first(where: { $0.track == c.track && $0.status != "done" }) {
                        model.focusItem(projectId: project.id, ref: "road:" + first.id)
                    }
                }.buttonStyle(SteerButton()).font(.system(size: S(11))).foregroundStyle(Brand.mute)
            }
        }
        .padding(hero ? 16 : 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(hero ? Brand.panel2 : Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(hero ? Brand.amber.opacity(0.4) : Brand.line))
    }
}
