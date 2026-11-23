import SwiftUI

/// Notes you left on an older version leave the inputs once Claude delivers a new one (chapter "Processed notes leave
/// the inputs", 22 Nov). Nothing is deleted: the old answer moves to `choices[key].previous`, pins keep their `v`
/// (To test) or their `at` (choices, before `revisedAt`), and get_item returns them apart as `previous_notes`.
struct ProcessedNotes {
    struct Note {
        let n: Int                 // 1-based, same order as get_item's user_notes: card, tests by number, pinned
        let kind: String           // card | test | pin | note
        let text: String
        var test: Int? = nil
        var img: String? = nil
        var x: Double? = nil, y: Double? = nil
        var done: String? = nil    // what Claude did with it (the new delivery's notesDone[n-1])
    }
    let v: Int?                    // the version the notes were on (To test); nil for a choice
    let pick: String?
    let notes: [Note]
}

extension BoardStore {
    /// A To test answer is about to be written for `version`: an answer of an older version moves to `previous`
    /// (kept for the recap and get_item) and the entry starts clean. Same rule on the Mac, the phone inbox and the web.
    nonisolated static func startVersion(_ c: inout [String: Any], _ version: Int) {
        guard let old = c["v"] as? Int else { c["v"] = version; return }
        guard old != version else { return }
        var snap: [String: Any] = ["v": old]
        for k in ["pick", "note", "tests", "at"] { if let x = c[k], !(x is NSNull) { snap[k] = x } }
        if snap["pick"] != nil || snap["note"] != nil || snap["tests"] != nil {
            var prev = c["previous"] as? [[String: Any]] ?? []
            prev.append(snap)
            c["previous"] = prev
        }
        c["pick"] = nil; c["tests"] = nil; c["note"] = nil; c["v"] = version
    }

    /// A choice Claude revised after you answered: your old pick and note move to `previous`, the inputs start clean.
    nonisolated static func startRevision(_ c: inout [String: Any], revisedAt: String?) {
        guard let r = revisedAt, let at = c["at"] as? String, at < r else { return }
        var snap: [String: Any] = ["revisedAt": r, "at": at]
        for k in ["pick", "note", "mix"] { if let x = c[k], !(x is NSNull) { snap[k] = x } }
        if snap["pick"] != nil || snap["note"] != nil {
            var prev = c["previous"] as? [[String: Any]] ?? []
            prev.append(snap)
            c["previous"] = prev
        }
        c["pick"] = nil; c["note"] = nil; c["mix"] = nil
    }

    /// The notes of the version before `version` (the one Claude just processed), numbered like get_item's user_notes.
    nonisolated static func previousNotes(entry c: [String: Any], version: Int, testLabels: [String] = [], done: [String] = []) -> ProcessedNotes? {
        let old: [String: Any]? = {
            if let v = c["v"] as? Int, v < version { return c }
            return (c["previous"] as? [[String: Any]] ?? []).filter { ($0["v"] as? Int ?? 0) < version }
                .max { ($0["v"] as? Int ?? 0) < ($1["v"] as? Int ?? 0) }
        }()
        let pins = (c["pins"] as? [[String: Any]] ?? []).filter { ($0["v"] as? Int).map { $0 < version } ?? false }
        guard let ov = (old?["v"] as? Int) ?? pins.compactMap({ $0["v"] as? Int }).max() else { return nil }
        var notes: [ProcessedNotes.Note] = []
        func add(_ kind: String, _ text: String, test: Int? = nil, pin: [String: Any]? = nil) {
            let n = notes.count + 1
            let d = n <= done.count ? done[n - 1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            notes.append(.init(n: n, kind: kind, text: text, test: test, img: pin?["img"] as? String,
                               x: pin?["x"] as? Double, y: pin?["y"] as? Double, done: d.isEmpty ? nil : d))
        }
        if let old {
            if let n = (old["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { add("card", n) }
            let tests = (old["tests"] as? [String: Any] ?? [:]).compactMap { k, v -> (Int, String)? in
                guard let i = Int(k), let d = v as? [String: Any] else { return nil }
                let note = ((d["note"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard (d["refine"] as? Bool ?? false) || !note.isEmpty else { return nil }
                return (i, note)
            }.sorted { $0.0 < $1.0 }
            for (i, note) in tests {
                let label = i < testLabels.count ? testLabels[i] : ""
                add("test", note.isEmpty ? "marked To refine" + (label.isEmpty ? "" : " (\(label))") : note, test: i + 1)
            }
        }
        for p in pins where (p["v"] as? Int) == ov {
            let t = ((p["note"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { add("pin", t, pin: p) }
        }
        let pick = old.flatMap { $0["pick"] as? String }
        guard !notes.isEmpty || pick != nil else { return nil }
        return ProcessedNotes(v: ov, pick: pick, notes: notes)
    }

    /// Your answer to a choice before Claude's last revision of it: the note and the pins left before `revisedAt`.
    nonisolated static func previousChoiceNotes(entry c: [String: Any], revisedAt: String?) -> ProcessedNotes? {
        guard let r = revisedAt else { return nil }
        let old: [String: Any]? = {
            if let at = c["at"] as? String, at < r, c["pick"] != nil || c["note"] != nil { return c }
            return (c["previous"] as? [[String: Any]] ?? []).last
        }()
        var notes: [ProcessedNotes.Note] = []
        if let n = (old?["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            notes.append(.init(n: 1, kind: "note", text: n))
        }
        for p in c["pins"] as? [[String: Any]] ?? [] {
            guard let at = p["at"] as? String, at < r else { continue }
            let t = ((p["note"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { notes.append(.init(n: notes.count + 1, kind: "pin", text: t, img: p["img"] as? String, x: p["x"] as? Double, y: p["y"] as? Double)) }
        }
        let pick: String? = old.flatMap { o in (o["pick"] as? String) ?? (o["pick"] as? [String])?.joined(separator: ", ") }
        guard !notes.isEmpty || pick != nil else { return nil }
        return ProcessedNotes(v: nil, pick: pick, notes: notes)
    }

    /// The recap at the top of a new To test version.
    func processedNotes(_ s: ShipItem) -> ProcessedNotes? {
        guard s.version > 1, let c = choiceMap["ship:" + s.id] else { return nil }
        return Self.previousNotes(entry: c, version: s.version, testLabels: s.tests.map(\.label), done: s.notesDone)
    }

    /// The recap at the top of a revised choice.
    func processedNotes(_ d: BoardDecision) -> ProcessedNotes? {
        guard let c = choiceMap[d.id] else { return nil }
        return Self.previousChoiceNotes(entry: c, revisedAt: d.revisedAt)
    }

    /// Claude revised the choice after you answered it: your answer is processed, the inputs start clean.
    func answerProcessed(_ d: BoardDecision) -> Bool {
        guard let r = d.revisedAt, let at = verdict(d.id).at else { return false }
        return at < r
    }
}

extension ProcessedNotes {
    /// For get_item: the processed notes, apart from the ones to act on.
    var json: [String: Any] {
        var out: [String: Any] = ["notes": notes.map { n -> [String: Any] in
            var x: [String: Any] = ["n": n.n, "kind": n.kind, "note": n.text]
            if let t = n.test { x["test"] = t }
            if let img = n.img { x["img"] = img; x["x"] = n.x ?? 0; x["y"] = n.y ?? 0 }
            if let d = n.done { x["done"] = d }
            return x
        }]
        if let v { out["v"] = v }
        if let pick { out["pick"] = pick }
        return out
    }
}

/// ① “first words of the note…” · processed — one line per old note, folded after 3.
struct ProcessedRecap: View {
    let notes: ProcessedNotes
    let title: String
    @State private var open = false

    static func circled(_ n: Int) -> String {
        n >= 1 && n <= 20 ? String(UnicodeScalar(0x2460 + n - 1)!) : "\(n)."
    }

    var body: some View {
        let shown = open ? notes.notes : Array(notes.notes.prefix(3))
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.system(size: S(11))).foregroundStyle(Brand.green)
                Text(title).font(.system(size: S(11.5), weight: .medium)).foregroundStyle(Brand.mute)
                if let p = notes.pick, notes.notes.isEmpty {
                    Text("you said " + p).font(.system(size: S(11.5))).foregroundStyle(p == "ok" ? Brand.green : Brand.amber)
                }
            }
            ForEach(shown, id: \.n) { n in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.circled(n.n)).font(.system(size: S(12))).foregroundStyle(Brand.mute)
                    if n.kind == "pin" { Image(systemName: "mappin").font(.system(size: S(9.5))).foregroundStyle(Brand.mute) }
                    (Text(n.test.map { "Test \($0): " } ?? "").foregroundStyle(Brand.mute)
                     + Text("“\(Self.firstWords(n.text))”").foregroundStyle(Brand.ink.opacity(0.75))
                     + Text(" · processed").foregroundStyle(Brand.green.opacity(0.85))
                     + Text(n.done.map { " — \($0)" } ?? "").foregroundStyle(Brand.ink.opacity(0.9)))
                        .font(.system(size: S(12))).lineLimit(1).truncationMode(.tail)
                }.help(n.text + (n.done.map { "\n→ " + $0 } ?? ""))
            }
            if notes.notes.count > 3 {
                Button(open ? "Show less" : "+ \(notes.notes.count - 3) more") { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }
                    .buttonStyle(SteerButton()).font(.system(size: S(11))).foregroundStyle(Brand.blue)
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Brand.blue.opacity(0.08)))
    }

    static func firstWords(_ s: String, max: Int = 70) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ")
        guard one.count > max else { return one }
        let cut = one.prefix(max)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + "…"
    }
}
