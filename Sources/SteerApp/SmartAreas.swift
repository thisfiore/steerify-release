import Foundation
import SwiftUI
import FoundationModels

// MARK: - Feature areas (choice feature-areas, pick A; request r261122-111239)
//
// The Roadmap area chips name the product's own features (SB: Data Room, Market Room, Partner, MCP…), found in the
// chapter titles: each chapter's feature is the leading noun phrase of its title, shortened to what it shares with other
// chapters ("Boosting Data Room with AI Local Engine" → Data Room, "Retouch suite" + "Retouch review" → Retouch).
// A name the titles keep coming back to inside a heading (MCP in "Partner MCP" and "Standards … MCP …") is an area too.
// Key results go to their chapter's feature; ones that name another area are tagged with it as well. Only key results
// of chapters without a feature (Fixes & refinements) need the on-device model, which picks one of the names.
// Your renames, merges and hides (right-click a chip) are kept apart and always win. Saved in the app's support folder.

struct SmartAreas: Codable, Equatable {
    struct Area: Codable, Equatable, Hashable { var key: String; var name: String }
    var at: Date
    var areas: [Area]
    /// Key result id (slug of its text) → area key (its chapter's feature).
    var items: [String: String]
    /// Key result id → other areas its text names (a Market Room key result about the MCP is under MCP too).
    var also: [String: [String]]? = nil
    /// 2 = feature names (this file); older files held invented category words and are redone.
    var v: Int? = nil
    static let version = 2

    /// The areas of a key result, first its own.
    func keys(_ id: String) -> [String] { (items[id].map { [$0] } ?? []) + (also?[id] ?? []) }
}

/// What you changed on the chips (right-click): kept across regroupings, applied on top.
struct AreaEdits: Codable, Equatable {
    var names: [String: String] = [:]
    var merged: [String: String] = [:]
    var hidden: [String] = []

    func apply(_ s: SmartAreas) -> SmartAreas {
        guard !(names.isEmpty && merged.isEmpty && hidden.isEmpty) else { return s }
        func to(_ k: String) -> String? {
            var k = k, seen: Set<String> = []
            while let n = merged[k], !seen.contains(k) { seen.insert(k); k = n }
            return hidden.contains(k) ? nil : k
        }
        var out = s
        out.items = s.items.compactMapValues { to($0) }
        out.also = s.also?.mapValues { Array(NSOrderedSet(array: $0.compactMap { to($0) }).array as! [String]) }
        for (id, ks) in out.also ?? [:] { out.also?[id] = ks.filter { $0 != out.items[id] } }
        out.areas = s.areas.filter { to($0.key) == $0.key }.map { SmartAreas.Area(key: $0.key, name: names[$0.key] ?? $0.name) }
        return out
    }
}

@MainActor
final class SmartAreaModel: ObservableObject {
    static let shared = SmartAreaModel()
    @Published private(set) var byProject: [String: SmartAreas] = [:]
    @Published private(set) var edits: [String: AreaEdits] = [:]
    @Published private(set) var running: Set<String> = []
    static let every: TimeInterval = 3600

    private static func file(_ projectId: String, _ suffix: String = "") -> URL {
        let d = ProjectStore.dir.appendingPathComponent("smart-areas", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent(projectId + suffix + ".json")
    }
    /// The areas as computed (no edits).
    func raw(_ projectId: String) -> SmartAreas? {
        if let s = byProject[projectId] { return s }
        guard let d = try? Data(contentsOf: Self.file(projectId)),
              let s = try? JSONDecoder().decode(SmartAreas.self, from: d), s.v == SmartAreas.version else { return nil }
        byProject[projectId] = s
        return s
    }
    /// The areas as shown: with your renames, merges and hides.
    func get(_ projectId: String) -> SmartAreas? { raw(projectId).map { edits(projectId).apply($0) } }

    func edits(_ projectId: String) -> AreaEdits {
        if let e = edits[projectId] { return e }
        let e = (try? Data(contentsOf: Self.file(projectId, ".edits"))).flatMap { try? JSONDecoder().decode(AreaEdits.self, from: $0) } ?? AreaEdits()
        edits[projectId] = e
        return e
    }
    func edit(_ projectId: String, _ change: (inout AreaEdits) -> Void) {
        var e = edits(projectId); change(&e); edits[projectId] = e
        if let d = try? JSONEncoder().encode(e) { try? d.write(to: Self.file(projectId, ".edits"), options: .atomic) }
    }
    func rename(_ pid: String, _ key: String, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        edit(pid) { if n.isEmpty || n == raw(pid)?.areas.first(where: { $0.key == key })?.name { $0.names[key] = nil } else { $0.names[key] = n } }
    }
    func merge(_ pid: String, _ key: String, into target: String) { guard key != target else { return }; edit(pid) { $0.merged[key] = target } }
    func hide(_ pid: String, _ key: String) { edit(pid) { if !$0.hidden.contains(key) { $0.hidden.append(key) } } }
    func resetEdits(_ pid: String) { edit(pid) { $0 = AreaEdits() } }

    /// Regroup when the roadmap changed or the last run is older than an hour (or `force`).
    func refresh(_ board: BoardStore, force: Bool = false) async {
        let pid = board.project.id
        let items = board.roadmap.map { (id: $0.id, text: $0.text, chapter: $0.track) }
        let sig = LocalAI.hash(items.map { $0.id + "|" + $0.chapter }.joined(separator: "\n"))
        if !force, raw(pid) != nil, lastSig[pid] == sig, let s = raw(pid), Date().timeIntervalSince(s.at) < Self.every { return }
        guard !running.contains(pid), items.count >= 3 else { return }
        running.insert(pid); defer { running.remove(pid) }
        let words = Set(FeatureNames.words(board.project.name) + [board.project.id.lowercased()])
        // Plain words first (instant), shown at once; then the on-device model sorts what no name covers.
        let g = FeatureNames.group(items, project: words)
        guard !g.areas.isEmpty else { return }
        lastSig[pid] = sig
        save(pid, SmartAreas(at: Date(), areas: g.areas, items: g.items, also: g.also.isEmpty ? nil : g.also, v: SmartAreas.version))
        if let s = await Self.sortRest(g, items) { save(pid, s) }
    }
    private var lastSig: [String: String] = [:]
    private func save(_ pid: String, _ s: SmartAreas) {
        byProject[pid] = s
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: Self.file(pid), options: .atomic) }
    }

    /// Keeps a project grouped while its board is open: now, then every hour (the view also calls `refresh` when the
    /// roadmap changes, so no polling).
    func keepFresh(_ board: BoardStore) async {
        while !Task.isCancelled {
            await refresh(board)
            try? await Task.sleep(for: .seconds(Self.every))
        }
    }

    /// Key results of chapters without a feature that name none: the on-device model picks one, 10 at a time.
    /// nil = nothing to sort or no model.
    nonisolated static func sortRest(_ grouping: FeatureNames.Grouping, _ items: [(id: String, text: String, chapter: String)]) async -> SmartAreas? {
        var g = grouping
        let rest = items.filter { g.items[$0.id] == nil }
        guard !rest.isEmpty, LocalAI.ready else { return nil }
        do {
            let names = g.areas.map(\.name)
            for start in stride(from: 0, to: rest.count, by: 10) {
                let batch = Array(rest[start..<min(start + 10, rest.count)])
                let rows = batch.enumerated().map { "k\($0.offset + 1): \($0.element.text.prefix(140))" }.joined(separator: "\n")
                guard let picks = await pick(key: "featpick|" + LocalAI.hash(names.joined(separator: "|") + rows), fields: batch.indices.map { "k\($0 + 1)" },
                                             choices: names + ["Other"], instructions: """
                    For each key result of a product roadmap, pick the feature of the product it changes.
                    Features: \(names.joined(separator: ", ")). Answer Other when none of them fits.
                    """, prompt: "Key results:\n" + rows) else { continue }
                for (i, it) in batch.enumerated() {
                    if let n = picks["k\(i + 1)"], let a = g.areas.first(where: { $0.name == n }) { g.items[it.id] = a.key }
                }
            }
        }
        return SmartAreas(at: Date(), areas: g.areas, items: g.items, also: g.also.isEmpty ? nil : g.also, v: SmartAreas.version)
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
