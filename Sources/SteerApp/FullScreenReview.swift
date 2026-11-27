import AppKit
import SwiftUI
import Vision

/// Full-screen review (chapter "Mac full screen: focused review, Space to the next", request r261127-171842).
/// Space walks the pictures of an item, then opens the next item of the same kind that waits on you;
/// each picture opens zoomed on the part under test (choice mac-fullscreen-focus, option A).
extension PreviewState {
    /// The preview of one board item (a test or a choice), as a click on its card opens it.
    @MainActor static func item(_ ref: String, board: BoardStore, walk: [String] = []) -> PreviewState? {
        let p = board.project
        if let s = board.ships.first(where: { "test:" + $0.id == ref }) {
            var seen = Set<String>()
            let imgs = (s.shots.map(\.img) + s.tests.compactMap(\.img)).filter { seen.insert($0).inserted }
            guard !imgs.isEmpty else { return nil }
            // Open on the first test still to answer (its picture), else the first picture.
            let fb = board.testFeedback(s)
            let first = s.tests.indices.first { fb[$0]?.ok != true && !board.testRefines(s).contains($0) }
            let idx = first.flatMap { s.tests[$0].img }.flatMap { imgs.firstIndex(of: $0) } ?? 0
            return PreviewState(projectId: p.id, ref: ref, title: s.title, dir: p.boardDir, images: imgs, index: idx,
                                version: s.version, walk: walk)
        }
        if let d = board.decisions.first(where: { "choice:" + $0.id == ref }) {
            let imgs: @MainActor () -> [String] = {
                d.gallery.map(\.img) + d.options.compactMap { $0.shot ?? MockSnapshots.shared.picture(for: $0, boardDir: p.boardDir) }
            }
            let now = imgs()
            guard !now.isEmpty else { return nil }
            // Start on the first option picture (the gallery is context).
            let firstOption = d.options.lazy.compactMap { $0.shot ?? MockSnapshots.shared.picture(for: $0, boardDir: p.boardDir) }.first
            return PreviewState(projectId: p.id, ref: ref, title: d.title, dir: p.boardDir, images: now,
                                index: firstOption.flatMap { now.firstIndex(of: $0) } ?? 0, version: nil, refresh: imgs, walk: walk)
        }
        return nil
    }

    /// Items of the same kind that wait on you, in the tab's order (focused chapters first).
    @MainActor static func waiting(like ref: String, board: BoardStore) -> [String] {
        var refs: [String]
        if ref.hasPrefix("test:") {
            refs = board.ships.filter { let x = board.shipState($0); return x == .toTest || x == .retest }.map { "test:" + $0.id }
        } else if ref.hasPrefix("choice:") {
            refs = board.decisions.filter { !board.isDecided($0) && !board.isParked($0) }.reversed().map { "choice:" + $0.id }
        } else { return [] }
        if !board.focus.isEmpty {
            let rank = refs.map { board.focusChapter(of: $0).flatMap(board.focusRank) ?? Int.max }
            refs = refs.indices.sorted { (rank[$0], $0) < (rank[$1], $1) }.map { refs[$0] }
        }
        return refs
    }

    /// The walk this preview belongs to: fixed when the first item opens, so "item 2 of 7" stays put while you answer.
    @MainActor func walkList(board: BoardStore) -> [String] {
        if !walk.isEmpty { return walk.contains(ref) ? walk : [ref] + walk }
        let w = Self.waiting(like: ref, board: board)
        return w.contains(ref) ? w : [ref] + w
    }

    /// The next item of the walk that still waits on you (after this one, then from the top); nil = all answered.
    @MainActor func nextRef(board: BoardStore) -> String? {
        let w = walkList(board: board), live = Set(Self.waiting(like: ref, board: board))
        let i = w.firstIndex(of: ref) ?? -1
        let after = w[(i + 1)...].first { live.contains($0) } ?? w[..<max(i, 0)].first { live.contains($0) }
        if let after { return after }
        // Something new landed while you were walking: take it too.
        return Self.waiting(like: ref, board: board).first { $0 != ref && !w.contains($0) }
    }
}

/// Where the feature is on a picture when the delivery did not say, all on the Mac (Apple Vision, nothing leaves it):
/// 1. the words of the test (label + what to check) read on the picture → the area around them;
/// 2. else objectness saliency, when it finds one clear part of the picture.
/// Kept only when it is clearly a part of the picture, not all of it.
enum FocusGuess {
    @MainActor private static var memo: [String: CGRect?] = [:]

    @MainActor static func rect(for path: String, words: String = "") async -> CGRect? {
        let key = path + "|" + words
        if let m = memo[key] { return m }
        let r = await Task.detached(priority: .userInitiated) { guess(path, words: words) }.value
        memo[key] = r
        return r
    }

    /// Words worth looking for: 4+ letters, not the usual verbs of a test ("open", "click", "should"…).
    nonisolated static func keywords(_ text: String) -> Set<String> {
        let skip: Set<String> = ["open", "click", "show", "shows", "should", "with", "from", "that", "this", "there", "where",
                                 "then", "when", "your", "into", "same", "look", "looks", "check", "see", "every", "nothing", "under"]
        return Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 4 && !skip.contains($0) })
    }

    nonisolated private static func guess(_ path: String, words: String) -> CGRect? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        func topLeft(_ b: CGRect) -> CGRect { CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height) }
        func usable(_ r: CGRect) -> CGRect? {
            let area = r.width * r.height
            return area < 0.6 && area > 0.02 ? r : nil
        }
        // 1. The test's words on the picture.
        let want = keywords(words)
        if !want.isEmpty {
            let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: img).perform([req])
            var hits: [(box: CGRect, words: Set<String>)] = []
            for o in req.results ?? [] {
                guard let t = o.topCandidates(1).first?.string.lowercased() else { continue }
                let m = want.filter { t.contains($0) }
                if !m.isEmpty { hits.append((topLeft(o.boundingBox), m)) }
            }
            // The words show up in many places (a logo, a list): take the densest spot, the one with the most
            // different words of the test near each other.
            var hit: CGRect?, score = 0
            for c in hits {
                let near = hits.filter { abs($0.box.midX - c.box.midX) < 0.25 && abs($0.box.midY - c.box.midY) < 0.22 }
                let n = Set(near.flatMap(\.words)).count
                if n > score { score = n; hit = near.dropFirst().reduce(near[0].box) { $0.union($1.box) } }
            }
            if let h = hit {
                // The words are small: take the area around them (a third of the picture at least), centred on them.
                var r = h
                let w = max(r.width + 0.16, 0.34), hgt = max(r.height + 0.16, 0.34)
                r = CGRect(x: r.midX - w / 2, y: r.midY - hgt / 2, width: w, height: hgt)
                r.origin.x = min(max(r.minX, 0), 1 - min(r.width, 1)); r.origin.y = min(max(r.minY, 0), 1 - min(r.height, 1))
                if let u = usable(r.intersection(unit)) { return u }
            }
        }
        // 2. One clear object (objectness saliency).
        let req = VNGenerateObjectnessBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: img).perform([req])
        guard let objs = (req.results?.first as? VNSaliencyImageObservation)?.salientObjects, objs.count == 1 else { return nil }
        return usable(topLeft(objs[0].boundingBox).insetBy(dx: -0.04, dy: -0.04).intersection(unit))
    }
}

/// A picture's pixel size from its header (no decoding), remembered.
enum ImageSize {
    @MainActor private static var memo: [String: CGSize?] = [:]
    @MainActor static func of(_ path: String) -> CGSize? {
        if let m = memo[path] { return m }
        var out: CGSize?
        if let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
           let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int {
            out = CGSize(width: w, height: h)
        }
        memo[path] = out
        return out
    }
}
