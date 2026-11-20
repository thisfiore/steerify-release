import Foundation

// MARK: - Which project is a request for? (choice request-project-guess, pick A)
//
// From the menu bar or ⌃⌥N you are not "in" a project, and forgetting to click the right FOR pill puts the request on the
// wrong board. Steerify guesses as you type: a project named in the text wins; otherwise the words that only one project
// uses (its chapters, key results, areas, repos, goal); Apple Intelligence then reads it like a person would.
// Not sure → no guess (the window's project stays, and the send button names it). A click on a pill always wins.

struct ProjectGuess: Equatable {
    let projectId: String
    let why: String
    var ai = false
}

enum ProjectGuesser {
    /// What Steerify knows about a project, as words and as a short description for the model.
    struct Profile: Sendable {
        let id: String
        let name: String
        let nameWords: Set<String>
        let words: [String: Int]     // stemmed word → how often the board uses it
        let total: Int
        let about: String
    }

    @MainActor static func profiles(_ model: AppModel) -> [Profile] {
        model.projects.map { p in
            let b = model.board(for: p)
            let chapters = b.chapters.filter { !$0.draft && $0.name != RequestLog.fixesChapter }
            let items = b.roadmap.filter { $0.track != RequestLog.fixesChapter }.map(\.text)
            let areas = b.areas.map(\.name)
            let repos = p.repos.map(\.name)
            let text = ([p.name, b.goal] + areas + repos + chapters.map(\.name) + items).joined(separator: " ")
            let about = [b.goal.isEmpty ? nil : "goal: " + String(b.goal.prefix(160)),
                         areas.isEmpty ? nil : "areas: " + areas.prefix(8).joined(separator: ", "),
                         repos.isEmpty ? nil : "repos: " + repos.prefix(6).joined(separator: ", "),
                         chapters.isEmpty ? nil : "chapters: " + chapters.suffix(6).map(\.name).joined(separator: "; ")]
                .compactMap { $0 }.joined(separator: " · ")
            var counts: [String: Int] = [:]
            for w in RequestTriage.words(text) { counts[RequestTriage.stem(w), default: 0] += 1 }
            return Profile(id: p.id, name: p.name, nameWords: Set(RequestTriage.words(p.name).map(RequestTriage.stem)),
                           words: counts, total: max(1, counts.values.reduce(0, +)), about: about)
        }
    }

    /// The words' view: a project named in the text, else each project's score from the words only it (or few) use.
    struct Words {
        var named: ProjectGuess?
        var scores: [(id: String, name: String, score: Double, hits: [String])] = []
        /// A guess from the words alone: clearly ahead of the next project.
        var guess: ProjectGuess? {
            if let named { return named }
            guard let best = scores.first, best.score >= 2 else { return nil }
            let second = scores.count > 1 ? scores[1].score : 0
            guard best.score >= max(second * 1.8, second + 1) else { return nil }
            return ProjectGuess(projectId: best.id, why: best.hits.prefix(3).map { "“\($0)”" }.joined(separator: ", "))
        }
        /// Far ahead (3+ and 3× the next): tested, these are right even where the model is wrong.
        var strong: Bool {
            guard let best = scores.first, named == nil else { return false }
            return best.score >= 3 && best.score >= 3 * (scores.count > 1 ? scores[1].score : 0)
        }
        /// Projects the words give some reason for (the model may only pick among these).
        var backed: [String] { scores.filter { $0.score >= 1 && $0.score >= (scores.first?.score ?? 0) * 0.5 }.map(\.id) }
    }

    /// Free and instant.
    static func words(_ text: String, _ ps: [Profile]) -> Words {
        guard ps.count > 1 else { return Words() }
        let mine = Set(RequestTriage.words(text).map(RequestTriage.stem))
        let low = " " + text.lowercased() + " "
        // Named: "in Blink …", "the Acme board" (whole name, or all its words).
        let named = ps.filter { p in
            low.range(of: "\\b" + NSRegularExpression.escapedPattern(for: p.name.lowercased()) + "\\b", options: .regularExpression) != nil
                || (p.nameWords.count > 1 && p.nameWords.isSubset(of: mine))
        }
        var w = Words()
        if named.count == 1 { w.named = ProjectGuess(projectId: named[0].id, why: "names “\(named[0].name)”") }
        // Each shared word counts by the share of its use that falls in this project (rate per board size, so a big
        // board does not win by size); a word every project uses says nothing.
        let rate: (Profile, String) -> Double = { p, x in Double(p.words[x] ?? 0) / Double(p.total) }
        w.scores = ps.map { p in
            var sc = 0.0, hits: [(String, Double)] = []
            for x in mine where p.words[x] != nil {
                let users = ps.filter { $0.words[x] != nil }
                guard users.count < ps.count else { continue }
                let share = rate(p, x) / users.reduce(0) { $0 + rate($1, x) }
                sc += share; hits.append((x, share))
            }
            return (p.id, p.name, sc, hits.sorted { $0.1 > $1.1 }.map(\.0))
        }.sorted { $0.score > $1.score }
        return w
    }

    /// The final guess. A wrong project is worse than none: a named project wins; the model only picks among projects the
    /// words back, and when it disagrees with a clear word guess (or is unsure) there is no guess. Model off → the words.
    static func decide(_ w: Words, model: ProjectGuess??) -> ProjectGuess? {
        if let n = w.named { return n }
        guard let m = model else { return w.guess }                 // Apple Intelligence off / no answer
        if w.strong, let g = w.guess { return g }                   // the words are overwhelming: the small model can't overrule them
        guard let pick = m, w.backed.contains(pick.projectId) else { return nil }
        if let g = w.guess, g.projectId != pick.projectId { return nil }
        let hits = w.scores.first { $0.id == pick.projectId }?.hits.prefix(2).map { "“\($0)”" } ?? []
        return ProjectGuess(projectId: pick.projectId, why: hits.isEmpty ? pick.why : hits.joined(separator: ", "), ai: true)
    }

    /// Apple Intelligence reads the request against each project's description. nil = off or unsure.
    /// Asked twice, the projects listed in opposite orders: the small model leans to the first one it reads,
    /// so only an answer that survives the reversal counts. Off → nil; disagree or unsure → .some(nil).
    static func ai(_ text: String, _ ps: [Profile]) async -> ProjectGuess?? {
        guard let a = await ask(text, ps) else { return nil }
        guard let pa = a else { return .some(nil) }
        guard let b = await ask(text, Array(ps.prefix(12).reversed())) else { return nil }
        return .some(b?.projectId == pa.projectId ? pa : nil)
    }

    private static func ask(_ text: String, _ ps: [Profile]) async -> ProjectGuess?? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ps.count > 1, clean.count >= 12, LocalAI.ready else { return nil }
        let list = Array(ps.prefix(12))
        let menu = list.map { "- \($0.name): \($0.about)" }.joined(separator: "\n")
        // Name, not a number, at temperature 0: tested on the real boards, numbers flip with the order, names mostly don't.
        guard let a = await LocalAI.ask(key: "proj2|" + LocalAI.hash(menu + clean), instructions:
            "You route a request to the software project it is about. Answer with the project's name only, or 'unsure'.",
            prompt: "Projects:\n\(menu)\n\nRequest: \(clean.prefix(1500))\n\nProject:", temperature: 0) else { return nil }
        let low = a.lowercased()
        let hit = list.filter { low.contains($0.name.lowercased()) }
        guard hit.count == 1 else { return .some(nil) }                 // unsure, or several
        return ProjectGuess(projectId: hit[0].id, why: "reads like \(hit[0].name)", ai: true)
    }
}
