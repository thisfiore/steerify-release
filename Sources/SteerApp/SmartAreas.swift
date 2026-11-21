import Foundation
import SwiftUI
import FoundationModels

// MARK: - Smart areas (choice smart-areas, pick "auto"): the local AI regroups the roadmap by itself, every hour.
//
// The board's own areas (board.json → areas) map parts to repos and stay as Claude wrote them. These groups are only
// for finding things: Apple Intelligence names 4–8 areas from the chapters, then puts every key result in one.
// Saved per project in the app's support folder (never in the board, so no commits, no clashes with sessions).
// Without the on-device model nothing changes: the Roadmap filter uses the board's areas.

struct SmartAreas: Codable, Equatable {
    struct Area: Codable, Equatable, Hashable { var key: String; var name: String }
    var at: Date
    var areas: [Area]
    /// Key result id (slug of its text) → area key.
    var items: [String: String]
}

@MainActor
final class SmartAreaModel: ObservableObject {
    static let shared = SmartAreaModel()
    @Published private(set) var byProject: [String: SmartAreas] = [:]
    @Published private(set) var running: Set<String> = []
    static let every: TimeInterval = 3600

    private static func file(_ projectId: String) -> URL {
        let d = ProjectStore.dir.appendingPathComponent("smart-areas", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent(projectId + ".json")
    }
    func get(_ projectId: String) -> SmartAreas? {
        if let s = byProject[projectId] { return s }
        guard let d = try? Data(contentsOf: Self.file(projectId)),
              let s = try? JSONDecoder().decode(SmartAreas.self, from: d) else { return nil }
        byProject[projectId] = s
        return s
    }

    /// Regroup when the last run is older than an hour (or `force`). One project at a time; the model is shared.
    func refresh(_ board: BoardStore, force: Bool = false) async {
        let pid = board.project.id
        if !force, let s = get(pid), Date().timeIntervalSince(s.at) < Self.every { return }
        guard LocalAI.ready, !running.contains(pid) else { return }
        let items = board.roadmap.map { (id: $0.id, text: $0.text, chapter: $0.track) }
        guard items.count >= 6 else { return }
        running.insert(pid); defer { running.remove(pid) }
        guard let s = await Self.regroup(items, previous: get(pid)) else { return }
        byProject[pid] = s
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: Self.file(pid), options: .atomic) }
    }

    /// Keeps a project regrouped while its board is open: now if due, then every hour.
    func keepFresh(_ board: BoardStore) async {
        while !Task.isCancelled {
            await refresh(board)
            try? await Task.sleep(for: .seconds(Self.every))
        }
    }

    // MARK: The two model steps

    /// Category words that say nothing about this product: never an area.
    nonisolated static let generic: Set<String> = ["features", "feature", "development", "design", "testing", "tests", "documentation", "docs",
        "feedback", "user management", "users", "improvements", "enhancements", "bugs", "fixes", "misc", "other", "general", "core",
        "deployment", "infrastructure", "backend", "frontend", "ui", "ux", "user experience", "user interface", "performance", "quality"]

    nonisolated static func regroup(_ items: [(id: String, text: String, chapter: String)], previous: SmartAreas?) async -> SmartAreas? {
        // 1 · Name the areas from the chapters (a few key results each, so it sees what they hold).
        var chapters: [String] = []
        for it in items where !chapters.contains(it.chapter) { chapters.append(it.chapter) }
        let menu = String(chapters.map { c in
            "- \(c): " + items.filter { $0.chapter == c }.prefix(4).map { String($0.text.prefix(70)) }.joined(separator: "; ")
        }.joined(separator: "\n").prefix(6500))
        let keep = previous.map { "Current areas (keep a name when it still fits): " + $0.areas.map(\.name).joined(separator: ", ") + "\n\n" } ?? ""
        var names: [String] = []
        for attempt in 0..<2 where names.count < 3 {
            guard let a = await LocalAI.ask(key: "areas2|\(attempt)|" + LocalAI.hash(keep + menu), instructions: """
                You organise a product's roadmap into areas, so its owner can filter it.
                An area is a PART OF THE PRODUCT that key results change: a screen, a tab, a panel, a flow, a page, a tool.
                Name each area with words that appear in the chapters below (1 to 3 words), the way the owner would say it.
                Never use generic categories such as Features, Design, Development, Testing, Documentation, Feedback, Deployment, User management.
                Give between 4 and 8 areas that together cover every chapter. One area name per line, nothing else.
                """, prompt: keep + "Chapters and some of their key results:\n" + menu, temperature: attempt == 0 ? 0.2 : 0.6) else { return nil }
            for line in a.split(whereSeparator: \.isNewline) {
                let n = line.trimmingCharacters(in: CharacterSet(charactersIn: " -*•0123456789.)\t\"")).trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty, n.count <= 32, !generic.contains(n.lowercased()),
                      !names.contains(where: { $0.lowercased() == n.lowercased() }) else { continue }
                names.append(n)
            }
        }
        names = Array(names.prefix(8))
        guard names.count >= 3 else { return nil }
        let areas = names.map { SmartAreas.Area(key: BoardFiles.slug($0), name: $0) }

        // 2a · A key result that names an area goes there (the first one it names): plain words beat the model.
        var map: [String: String] = [:]
        for it in items { if let k = named(it.text, areas) { map[it.id] = k } }
        // 2b · The rest, 10 at a time; the answer can only be one of the area names.
        let rest = items.filter { map[$0.id] == nil }
        for start in stride(from: 0, to: rest.count, by: 10) {
            let batch = Array(rest[start..<min(start + 10, rest.count)])
            let rows = batch.enumerated().map { "k\($0.offset + 1): \($0.element.text.prefix(120)) (chapter: \($0.element.chapter.prefix(50)))" }.joined(separator: "\n")
            guard let picks = await pick(key: "areapick|" + LocalAI.hash(names.joined(separator: "|") + rows), fields: batch.indices.map { "k\($0 + 1)" },
                                         choices: names, instructions: """
                For each key result, pick the area a person would open to find it. The chapter is a hint, not the answer.
                Areas: \(names.joined(separator: ", ")).
                """, prompt: "Key results:\n" + rows) else { continue }
            for (i, it) in batch.enumerated() {
                if let n = picks["k\(i + 1)"], let a = areas.first(where: { $0.name == n }) { map[it.id] = a.key }
            }
        }
        guard !map.isEmpty else { return nil }
        // What the model skipped goes where most of its chapter went.
        for it in items where map[it.id] == nil {
            let mates = items.filter { $0.chapter == it.chapter }.compactMap { map[$0.id] }
            if let top = Dictionary(grouping: mates, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key { map[it.id] = top }
        }
        let used = Set(map.values)
        return SmartAreas(at: Date(), areas: areas.filter { used.contains($0.key) }, items: map)
    }

    /// The area whose name the text says first ("New request from the menu bar…" → Request), if any.
    nonisolated static func named(_ text: String, _ areas: [SmartAreas.Area]) -> String? {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        func stem(_ w: String) -> String { w.count > 4 && w.hasSuffix("s") ? String(w.dropLast()) : w }
        var best: (pos: Int, key: String)? = nil
        for a in areas {
            let parts = a.name.lowercased().split { !$0.isLetter && !$0.isNumber }.map { stem(String($0)) }
            guard let first = parts.first, first.count >= 3 else { continue }
            if let i = words.firstIndex(where: { stem($0) == first }), best == nil || i < best!.pos { best = (i, a.key) }
        }
        return best?.key
    }

    /// One constrained answer per field, each one of `choices` (guided generation: the model cannot answer anything else).
    nonisolated static func pick(key: String, fields: [String], choices: [String], instructions: String, prompt: String) async -> [String: String]? {
        if let c = LocalAI.cached(key), let d = c.data(using: .utf8), let m = try? JSONDecoder().decode([String: String].self, from: d) { return m }
        guard LocalAI.ready, #available(macOS 26, *) else { return nil }
        let out: [String: String]? = await LocalAI.Gate.shared.run {
            let choice = DynamicGenerationSchema(name: "Area", anyOf: choices)
            let root = DynamicGenerationSchema(name: "Picks", properties: fields.map {
                DynamicGenerationSchema.Property(name: $0, schema: DynamicGenerationSchema(referenceTo: "Area"))
            })
            guard let schema = try? GenerationSchema(root: root, dependencies: [choice]) else { return nil }
            let s = LanguageModelSession(instructions: instructions)
            guard let r = try? await s.respond(to: prompt, schema: schema, options: GenerationOptions(temperature: 0)) else { return nil }
            var m: [String: String] = [:]
            for f in fields { if let v = try? r.content.value(String.self, forProperty: f) { m[f] = v } }
            return m.isEmpty ? nil : m
        }
        if let out, let d = try? JSONEncoder().encode(out), let s = String(data: d, encoding: .utf8) { LocalAI.remember(key, s) }
        return out
    }
}
