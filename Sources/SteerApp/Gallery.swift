import SwiftUI
import AppKit
import WebKit
import CryptoKit

// MARK: - Gallery: one big hero visual + a filmstrip

struct GalleryItem: Hashable { let path: String; let caption: String; var focus: CGRect? = nil }

/// Visuals are the point of a card: the hero is shown large and uncropped, the filmstrip below
/// swaps the hero on hover and opens the preview on click (⌘-click opens it ready to pin a note).
struct Gallery: View {
    let dir: String
    let items: [GalleryItem]
    var heroHeight: CGFloat = 340
    let open: (Int) -> Void
    @State private var hero = 0

    var body: some View {
        if !items.isEmpty {
            let i = min(hero, items.count - 1)
            VStack(alignment: .leading, spacing: 8) {
                BoardImage(dir: dir, path: items[i].path, height: S(heroHeight), fit: true, focus: items[i].focus, onOpen: { open(i) })
                HStack(spacing: 8) {
                    if !items[i].caption.isEmpty {
                        Text(items[i].caption).font(.system(size: S(12))).foregroundStyle(Brand.ink.opacity(0.85)).lineLimit(2)
                    }
                    Spacer()
                    if items.count > 1 { Text("\(i + 1) / \(items.count)").font(Brand.label(9.5)).foregroundStyle(Brand.mute) }
                }
                if items.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.offset) { k, it in
                                BoardImage(dir: dir, path: it.path, height: S(72), focus: it.focus, onOpen: { open(k) })
                                    .frame(width: S(118))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(k == i ? Brand.cream.opacity(0.7) : .clear, lineWidth: 1.5))
                                    .onHover { if $0 { hero = k } }
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Pictures of HTML mockups (rendered once, cached on disk)

/// Choices often carry their mockups as HTML. To show them as real visuals, Steerify renders each one
/// off-screen once (WebKit, one page at a time), saves a PNG in Caches and forgets the web view when idle.
@MainActor
final class MockSnapshots: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = MockSnapshots()
    @Published private(set) var version = 0

    private struct Job { let key: String; let html: String?; let file: URL?; let base: URL; let out: URL }
    private var queue: [Job] = []
    private var running: Job?
    private var web: WKWebView?
    private var idle: DispatchWorkItem?
    private var queued = Set<String>()

    static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Steerify/mocks", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Absolute path of the picture for this option's mockup; nil (and rendering queued) if not there yet.
    func picture(for option: BoardOption, boardDir: String) -> String? {
        let base = URL(fileURLWithPath: boardDir, isDirectory: true)
        var html: String? = nil, file: URL? = nil, seed = ""
        if let proto = option.proto {
            file = Self.protoURL(proto, base: base)
            // Redraw when the prototype or its project kit (kit/*.css, data.js…) changes.
            let fm = FileManager.default
            let kit = base.appendingPathComponent("kit")
            let kitFiles = ((try? fm.contentsOfDirectory(atPath: kit.path)) ?? []).map { kit.appendingPathComponent($0).path }
            let m = ([file!.path] + kitFiles).map { (try? fm.attributesOfItem(atPath: $0)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0 }.max() ?? 0
            seed = "proto:\(proto)#\(m)"
        } else if let h = option.mockHTML {
            html = h; seed = "v3:\(option.simple):html:\(h)"
        } else { return nil }
        let key = SHA256.hash(data: Data((boardDir + seed).utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let out = Self.dir.appendingPathComponent("\(key).png")
        if FileManager.default.fileExists(atPath: out.path) { return out.path }
        if !queued.contains(key) {
            queued.insert(key)
            let page = html.map { Self.page($0, simple: option.simple, boardDir: boardDir) }
            queue.append(Job(key: key, html: page, file: file, base: base, out: out))
            next()
        }
        return nil
    }

    private func next() {
        guard running == nil, !queue.isEmpty else { return }
        idle?.cancel()
        let job = queue.removeFirst()
        running = job
        let w = web ?? {
            let v = WKWebView(frame: NSRect(x: 0, y: 0, width: Self.W, height: Self.H))
            v.navigationDelegate = self
            web = v
            return v
        }()
        if let f = job.file {
            w.loadFileURL(f, allowingReadAccessTo: job.base)
        } else if let h = job.html {
            w.loadHTMLString(h, baseURL: job.base)
        }
    }

    /// A prototype path relative to the board folder, keeping its query (`protos/x.html?v=B` opens variant B).
    nonisolated static func protoURL(_ proto: String, base: URL) -> URL {
        let parts = proto.split(separator: "?", maxSplits: 1).map(String.init)
        let file = URL(fileURLWithPath: parts[0], relativeTo: base).absoluteURL
        guard parts.count > 1, var c = URLComponents(url: file, resolvingAgainstBaseURL: false) else { return file }
        c.percentEncodedQuery = parts[1]
        return c.url ?? file
    }

    /// The board's own stylesheet (mockups use its classes), cached per board folder.
    private var css: [String: String] = [:]
    static let W: CGFloat = 400, H: CGFloat = 250     // the board's mockup box (16:10), rendered at 3×

    static func page(_ mock: String, simple: Bool, boardDir: String) -> String {
        let styles = shared.boardCSS(boardDir)
        return """
        <html><head><meta charset=utf-8><style>\(styles)
        html,body{margin:0;padding:0;width:\(Int(W))px;height:\(Int(H))px;overflow:hidden;background:#000}
        .mock{width:\(Int(W))px;height:\(Int(H))px;margin:0;border:0;border-radius:0;aspect-ratio:auto}
        .mock.simple{min-height:\(Int(H))px}
        </style></head><body><div class="mock\(simple ? " simple" : "")">\(mock)</div></body></html>
        """
    }

    private func boardCSS(_ dir: String) -> String {
        if let c = css[dir] { return c }
        let html = (try? String(contentsOfFile: (dir as NSString).appendingPathComponent("index.html"), encoding: .utf8)) ?? ""
        var out = ""
        var rest = html[...]
        while let a = rest.range(of: "<style>"), let b = rest.range(of: "</style>", range: a.upperBound..<rest.endIndex) {
            out += rest[a.upperBound..<b.lowerBound] + "\n"
            rest = rest[b.upperBound...]
        }
        css[dir] = out
        return out
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)        // let web fonts and images settle
            let cfg = WKSnapshotConfiguration()
            cfg.rect = CGRect(x: 0, y: 0, width: Self.W, height: Self.H)
            cfg.snapshotWidth = NSNumber(value: Double(Self.W * 3))     // 3× for a crisp picture
            webView.takeSnapshot(with: cfg) { [weak self] img, _ in
                guard let self else { return }
                if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]), let job = self.running {
                    try? png.write(to: job.out)
                }
                self.finish()
            }
        }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.finish() } }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.finish() } }

    private func finish() {
        running = nil
        version += 1
        if queue.isEmpty {
            // Free WebKit's memory once the queue is done.
            let work = DispatchWorkItem { [weak self] in self?.web = nil }
            idle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
        }
        next()
    }
}
