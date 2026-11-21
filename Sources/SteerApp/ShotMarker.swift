import SwiftUI
import AppKit

/// A mark on an attached screenshot: ⌘-click = a numbered dot, drag = a numbered rectangle.
/// Its badge (①, ②…) goes into the request text, so the words point at the picture.
struct ShotMark: Identifiable, Equatable {
    var id: Int { n }
    let n: Int
    let img: URL
    /// 0–1 from the top-left. A dot has zero width and height.
    let rect: CGRect
    var isDot: Bool { rect.width == 0 && rect.height == 0 }

    /// ① … ⑳, then (21), (22)…
    static func badge(_ n: Int) -> String {
        n >= 1 && n <= 20 ? String(UnicodeScalar(0x2460 + n - 1)!) : "(\(n))"
    }
    var badge: String { Self.badge(n) }
}

/// The picture you attached, big, at the top of the request: mark it while you write.
struct ShotMarker: View {
    let images: [URL]
    @Binding var shown: URL?
    @Binding var marks: [ShotMark]
    var onMark: (ShotMark) -> Void
    var onRemove: (URL) -> Void

    @State private var dragFrom: CGPoint?
    @State private var dragTo: CGPoint?
    @State private var cache: [URL: NSImage] = [:]

    private var current: URL? { shown.flatMap { images.contains($0) ? $0 : nil } ?? images.last }

    var body: some View {
        if let u = current {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("MARK IT").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.amber)
                    Text("⌘-click: a numbered dot · drag: an area · the number goes in the text")
                        .font(.system(size: S(11))).foregroundStyle(Brand.mute)
                    Spacer()
                    if images.count > 1 {
                        ForEach(Array(images.enumerated()), id: \.element) { i, im in
                            Button { shown = im } label: {
                                Text("\(i + 1)").font(.system(size: S(10.5), weight: .semibold, design: .monospaced))
                                    .foregroundStyle(im == u ? Color(hex: 0x1a1200) : Brand.cream)
                                    .frame(width: 20, height: 18)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(im == u ? Brand.amber : Color.clear))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(im == u ? Color.clear : Brand.line2))
                            }.buttonStyle(.plain).help("Show picture \(i + 1)")
                        }
                    }
                }
                picture(u)
            }
        }
    }

    private func picture(_ u: URL) -> some View {
        let img = cache[u] ?? load(u)
        return ZStack(alignment: .topTrailing) {
            Group {
                if let img {
                    Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .overlay { GeometryReader { g in canvas(u, g.size) } }
                } else {
                    Rectangle().fill(Brand.panel2).frame(height: 120)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: S(320))
            Button { onRemove(u) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, .black.opacity(0.7))
            }.buttonStyle(.plain).padding(6).help("Take this picture off the request")
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x0d0f13)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.line2))
    }

    /// Marks and gestures, in the picture's own frame (so 0–1 maps to the picture, not the letterbox).
    private func canvas(_ u: URL, _ size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
            ForEach(marks.filter { $0.img == u }) { m in markView(m, size) }
            if let a = dragFrom, let b = dragTo {
                let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                Rectangle().stroke(Brand.amber, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
            }
        }
        .frame(width: size.width, height: size.height)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .local)
                .onChanged { v in dragFrom = clamp(v.startLocation, size); dragTo = clamp(v.location, size) }
                .onEnded { v in
                    defer { dragFrom = nil; dragTo = nil }
                    let a = clamp(v.startLocation, size), b = clamp(v.location, size)
                    guard abs(a.x - b.x) > 6, abs(a.y - b.y) > 6, size.width > 0, size.height > 0 else { return }
                    onMark(ShotMark(n: 0, img: u, rect: CGRect(x: min(a.x, b.x) / size.width, y: min(a.y, b.y) / size.height,
                                                              width: abs(a.x - b.x) / size.width, height: abs(a.y - b.y) / size.height)))
                }
        )
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .local).onEnded { v in
                guard NSEvent.modifierFlags.contains(.command), size.width > 0, size.height > 0 else { return }
                let p = clamp(v.location, size)
                onMark(ShotMark(n: 0, img: u, rect: CGRect(x: p.x / size.width, y: p.y / size.height, width: 0, height: 0)))
            }
        )
        .pointerStyle(.rectSelection)
    }

    @ViewBuilder private func markView(_ m: ShotMark, _ size: CGSize) -> some View {
        let r = CGRect(x: m.rect.minX * size.width, y: m.rect.minY * size.height, width: m.rect.width * size.width, height: m.rect.height * size.height)
        let d: CGFloat = 20
        if m.isDot {
            badge(m.n, d).offset(x: r.minX - d / 2, y: r.minY - d / 2)
                .contextMenu { Button("Remove \(m.badge)") { marks.removeAll { $0 == m } } }
        } else {
            Rectangle().fill(Brand.amber.opacity(0.08)).overlay(Rectangle().stroke(Brand.amber, lineWidth: 2))
                .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY).allowsHitTesting(false)
            badge(m.n, d).offset(x: r.minX - d / 2, y: r.minY - d / 2)
                .contextMenu { Button("Remove \(m.badge)") { marks.removeAll { $0 == m } } }
        }
    }

    private func badge(_ n: Int, _ d: CGFloat) -> some View {
        Text("\(n)").font(.system(size: d * 0.58, weight: .bold, design: .rounded)).foregroundStyle(Color(hex: 0x1a1200))
            .frame(width: d, height: d)
            .background(Circle().fill(Brand.amber))
            .overlay(Circle().stroke(Color.black.opacity(0.55), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .help("\(ShotMark.badge(n)) in the text · right-click to remove")
    }

    private func clamp(_ p: CGPoint, _ s: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), s.width), y: min(max(p.y, 0), s.height))
    }

    private func load(_ u: URL) -> NSImage? {
        guard let i = RecentShots.thumb(u, px: 1800) ?? NSImage(contentsOf: u) else { return nil }
        DispatchQueue.main.async { cache[u] = i }
        return i
    }
}

/// The marks drawn into a copy of the picture at full size, so Claude (and the history) see exactly what you marked.
enum ShotBurn {
    static func burn(_ u: URL, marks: [ShotMark], into dir: URL) -> URL? {
        guard !marks.isEmpty,
              let src = CGImageSourceCreateWithURL(u as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Flip to top-left origin, like the 0–1 marks.
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        let unit = max(CGFloat(max(w, h)) / 1600, 1)
        let amber = CGColor(red: 1, green: 0.69, blue: 0.125, alpha: 1)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        for m in marks {
            let r = CGRect(x: m.rect.minX * CGFloat(w), y: m.rect.minY * CGFloat(h), width: m.rect.width * CGFloat(w), height: m.rect.height * CGFloat(h))
            if !m.isDot {
                ctx.setFillColor(amber.copy(alpha: 0.08)!); ctx.fill(r)
                ctx.setStrokeColor(amber); ctx.setLineWidth(4 * unit); ctx.stroke(r)
            }
            let d = 30 * unit
            let c = CGRect(x: r.minX - d / 2, y: r.minY - d / 2, width: d, height: d)
            ctx.setFillColor(amber); ctx.fillEllipse(in: c)
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.6)); ctx.setLineWidth(2 * unit); ctx.strokeEllipse(in: c)
            let s = NSAttributedString(string: "\(m.n)", attributes: [
                .font: NSFont.systemFont(ofSize: d * 0.58, weight: .bold),
                .foregroundColor: NSColor(red: 0.1, green: 0.07, blue: 0, alpha: 1)])
            let ts = s.size()
            s.draw(at: CGPoint(x: c.midX - ts.width / 2, y: c.midY - ts.height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let out = ctx.makeImage() else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(u.deletingPathExtension().lastPathComponent + " marked \(Int(Date().timeIntervalSince1970)).png")
        guard let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]), (try? png.write(to: dest)) != nil else { return nil }
        return dest
    }
}
