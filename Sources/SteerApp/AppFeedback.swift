import AppKit
import SwiftUI

// MARK: - Report a bug / Ask for a feature, inside Steerify (choice app-feedback A)
//
// Steerify uses its own feedback standard first: a sheet in the app (beta pill → What's new, Help menu) files a
// Bug · Feature · Question on Steerify's own feedback inbox on the relay (the same open endpoint as the web form,
// no account, no secret). It lands on Steerify's board as a Request; the reporter gets a follow link.
// What is sent is shown before sending: version + macOS + tab, a screenshot of the window (on for bugs, off
// otherwise, unticked in one click), name / email only if typed.
// Pixel art all along: a crab on the sand (bug), a lighthouse and a shooting star (feature), a gull (question);
// Send rolls the note into a bottle, throws it to sea and the lighthouse flashes when it lands. Every report
// moves you up the crew (Deckhand → Bosun → …).
//
// Test hooks: `--feedback bug|feature|question` opens it; `--feedback-freeze <0…1|sent>` holds the send scene;
// `--feedback-send <title>` fills the title and presses Send (a real request on Steerify's board).

enum FeedbackKind: String, CaseIterable, Identifiable {
    case bug, feature, question
    var id: String { rawValue }
    var label: String { ["bug": "Bug", "feature": "Feature", "question": "Question"][rawValue]! }
    var headline: String { ["bug": "Spotted a bug?", "feature": "Wish for a feature?", "question": "Got a question?"][rawValue]! }
    var hint: String {
        ["bug": "Tell us what broke. We read every one, and you'll see it move to fixed.",
         "feature": "Make a wish. Good ones end up on the roadmap, with your name on the request.",
         "question": "Ask anything about Steerify. The answer comes back to you."][rawValue]!
    }
    var titlePrompt: String {
        ["bug": "What went wrong, in one line", "feature": "What you'd like Steerify to do", "question": "Your question, in one line"][rawValue]!
    }
    var color: Color { ["bug": Color(hex: 0xe0533d), "feature": Brand.amber, "question": Brand.blue][rawValue]! }
}

@MainActor
final class AppFeedback: ObservableObject {
    static let shared = AppFeedback()
    /// Steerify's own inbox on the relay (steer-app/.steerify/steerify.json → feedback.inbox). Public: anyone may file.
    static let inbox = "steerify-4cfac6"
    static let relay = URL(string: "https://relay.steerify.dev")!
    static let github = URL(string: "https://github.com/thisfiore/steerify-release/issues/new")!

    /// nil = closed.
    @Published var kind: FeedbackKind?
    /// The window as it was when the sheet opened (taken before the sheet covers it).
    private(set) var shot: NSImage?
    private(set) var tab = ""

    func open(_ k: FeedbackKind) {
        NSApp.activate(ignoringOtherApps: !CommandLine.arguments.contains("--background"))
        if kind == nil { shot = Self.captureWindow(); tab = Self.currentTab() }
        kind = k
    }
    func close() { kind = nil; shot = nil }

    static var version: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v) · macOS \(os.majorVersion).\(os.minorVersion)"
    }
    static func currentTab() -> String {
        let raw = Prefs.store.string(forKey: Prefs.boardTab) ?? ""
        return BoardTab(rawValue: raw).map { $0.title.capitalized } ?? ""
    }
    static func captureWindow() -> NSImage? {
        // The board window: the main one, else the biggest titled window (never a popover or the menu bar item).
        let titled = NSApp.windows.filter { $0.styleMask.contains(.titled) && $0.contentView != nil && $0.frame.width > 500 }
        guard let w = NSApp.mainWindow.flatMap({ titled.contains($0) ? $0 : nil }) ?? titled.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              let v = w.contentView?.superview ?? w.contentView,
              let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        let img = NSImage(size: v.bounds.size); img.addRepresentation(rep)
        return img
    }
    /// JPEG data URL, at most 1600 px wide (the relay keeps up to ~3 MB).
    static func dataURL(_ img: NSImage) -> String? {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, 1600 / CGFloat(cg.width))
        let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let small = ctx.makeImage(),
              let jpg = NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return "data:image/jpeg;base64," + jpg.base64EncodedString()
    }

    struct Sent { let id: String; let follow: URL? }
    enum SendError: LocalizedError {
        case relay(String)
        var errorDescription: String? { if case .relay(let s) = self { return s }; return nil }
    }
    static func send(kind: FeedbackKind, title: String, text: String, page: String, name: String, email: String, shot: String?) async throws -> Sent {
        var body: [String: Any] = ["kind": kind.rawValue, "title": title, "text": text, "page": page, "version": version,
                                   "name": name, "email": email, "source": "person"]
        if let shot { body["shot"] = shot }
        var r = URLRequest(url: relay.appendingPathComponent("v1/feedback/\(inbox)"))
        r.httpMethod = "POST"; r.timeoutInterval = 30
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue("Steerify", forHTTPHeaderField: "User-Agent")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let id = j["id"] as? String else {
            throw SendError.relay((j["error"] as? String).map { "The relay said: \($0)" } ?? "The relay didn't answer.")
        }
        return Sent(id: id, follow: (j["follow"] as? String).flatMap(URL.init(string:)))
    }

    // The crew: every report sent moves you up.
    static var sentCount: Int { Prefs.store.integer(forKey: "feedbackSent") }
    static func countOne() { Prefs.store.set(sentCount + 1, forKey: "feedbackSent") }
    static func rank(_ n: Int) -> (name: String, next: Int?) {
        let ladder: [(Int, String)] = [(1, "Deckhand"), (3, "Bosun"), (6, "Navigator"), (10, "First Mate"), (20, "Captain's Friend")]
        let cur = ladder.last { n >= $0.0 }?.1 ?? "Stowaway"
        return (cur, ladder.first { n < $0.0 }?.0)
    }
}

/// Help menu: Report a Bug… · Ask for a Feature… · Ask a Question…
struct FeedbackCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .help) {
            Divider()
            Button("Report a Bug…") { AppFeedback.shared.open(.bug) }
            Button("Ask for a Feature…") { AppFeedback.shared.open(.feature) }
            Button("Ask a Question…") { AppFeedback.shared.open(.question) }
        }
    }
}

/// The two buttons in the What's new panel (beta pill).
struct FeedbackButtons: View {
    var close: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HELP US BUILD IT").font(Brand.label(8)).tracking(1).foregroundStyle(Brand.mute)
            HStack(spacing: 8) {
                button(.bug, "Report a bug")
                button(.feature, "Ask for a feature")
            }
        }
    }
    private func button(_ k: FeedbackKind, _ title: String) -> some View {
        Button { close(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { AppFeedback.shared.open(k) } } label: {
            HStack(spacing: 6) {
                FeedbackGlyph(kind: k, size: S(12))
                Text(title).font(.system(size: S(11.5), weight: .semibold)).foregroundStyle(Brand.cream)
            }
            .padding(.horizontal, 9).padding(.vertical, 6).frame(maxWidth: .infinity)
            .background(PixelBox(step: 2).fill(Brand.panel2))
            .overlay(PixelBox(step: 2).stroke(k.color.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).pointerStyle(.link)
    }
}

// MARK: - Pixel bits

private struct Pix {
    let ctx: GraphicsContext; let px: CGFloat
    func dot(_ x: Int, _ y: Int, _ c: Color) {
        ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px - 0.4, height: px - 0.4)), with: .color(c))
    }
    /// A sprite: each character maps to a colour (". " = nothing).
    func sprite(_ rows: [String], _ x0: Int, _ y0: Int, _ pal: [Character: Color]) {
        for (y, row) in rows.enumerated() { for (x, ch) in row.enumerated() { if let c = pal[ch] { dot(x0 + x, y0 + y, c) } } }
    }
}

private enum Sprites {
    static let crabA = [".c.....c.", "rr.....rr", "rr.rrr.rr", ".rrrrrrr.", "..rrrrr..", ".r.r.r.r."]
    static let crabB = [".c.....c.", "rr.....rr", "rr.rrr.rr", ".rrrrrrr.", "..rrrrr..", "r.r...r.r"]
    static let gullA = ["c.......c", ".c.....c.", "..ccacc..", "...ccc...", "....c...."]
    static let gullB = [".........", ".........", "..ccacc..", "ccccccccc", "....c...."]
    static let ask = [".aaa.", "a...a", "....a", "...a.", "..a..", ".....", "..a.."]
    static let lighthouse = ["..lll..", ".lllll.", "..www..", "..rrr..", "..www..", ".rrrrr.", ".wwwww.", ".rrrrr.", ".wwwww.", "rrrrrrr", "wwwwwww"]
    static let bottleUp = [".k.", ".g.", "ggg", "gsg", "gsg", "ggg"]
    static let bottleLie = ["....gg..", ".ggggggk", "gssssgg.", ".gggggg."]
    static let scroll = ["sss", "s.s", "sss"]
}

private let sand = Color(hex: 0x6b5a3a), sandDark = Color(hex: 0x4f4229), glass = Color(hex: 0x7fd1c1), cork = Color(hex: 0x8a5a2b)

private func sky(_ p: Pix, cols: Int, t: Double) {
    for (i, (x, y)) in [(5, 3), (17, 7), (29, 2), (44, 5), (58, 3), (71, 8), (86, 2), (99, 6), (112, 3), (127, 7), (138, 4)].enumerated() where x < cols {
        let on = (Int(t * 2) + i) % 4 != 0
        p.dot(x, y, Brand.cream.opacity(on ? 0.85 : 0.25))
    }
}
private func sea(_ p: Pix, cols: Int, top: Int, t: Double, from x0: Int = 0, rows n: Int = 3) {
    let ph = Int(t * 2.5)
    for r in 0..<n {
        for x in x0..<cols where (x + ph * (r + 1) + r * 3) % 7 < 4 { p.dot(x, top + r * 3, (r == 0 ? Brand.blue : Brand.line2).opacity(r == 0 ? 0.6 : 0.85)) }
    }
}

/// The scene above the form, one per kind.
private struct KindScene: View {
    let kind: FeedbackKind
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let p = Pix(ctx: ctx, px: 4)
                let cols = Int(size.width / 4), rows = Int(size.height / 4)
                sky(p, cols: cols, t: t)
                switch kind {
                case .bug:
                    // the sand, and a crab scuttling along it (it stops now and then to wave a claw)
                    // the sea far back, then a wide beach the crab walks on
                    sea(p, cols: cols, top: rows - 15, t: t, rows: 2)
                    for x in 0..<cols {
                        for y in (rows - 9)..<rows { p.dot(x, y, (x * 7 + y * 3) % 11 == 0 ? sandDark : sand.opacity(y == rows - 9 ? 0.55 : 0.9)) }
                        if (x + Int(t * 2.5)) % 9 < 5 { p.dot(x, rows - 10, Brand.cream.opacity(0.35)) }   // foam at the edge
                    }
                    for (sx, sy) in [(14, 3), (52, 2), (97, 4)] where sx < cols { p.dot(sx, rows - sy, Brand.cream.opacity(0.7)); p.dot(sx + 1, rows - sy, Color(hex: 0xe8a0a0)) }   // shells
                    let walk = (sin(t * 0.7) + 1) / 2
                    let cx = 6 + Int(walk * Double(cols - 20))
                    let moving = abs(cos(t * 0.7)) > 0.25
                    let frame = moving && Int(t * 8) % 2 == 0 ? Sprites.crabA : Sprites.crabB
                    p.sprite(frame, cx, rows - 8, ["r": kind.color, "c": Brand.cream])
                    if !moving { p.dot(cx + 4, rows - 13, Brand.amber); p.dot(cx + 4, rows - 12, Brand.amber); p.dot(cx + 4, rows - 10, Brand.amber) }
                case .feature:
                    // a lighthouse sweeping its beam, and a shooting star every few seconds: make a wish
                    sea(p, cols: cols, top: rows - 9, t: t)
                    let lx = cols - 24, ly = rows - 20
                    for x in (lx - 3)...(lx + 9) { p.dot(x, rows - 9, Color(hex: 0x3a3f4a)); p.dot(x + 1, rows - 8, Color(hex: 0x2a2e36)) }
                    p.sprite(Sprites.lighthouse, lx, ly, ["l": Brand.amber, "w": Brand.cream, "r": Color(hex: 0xe0533d)])
                    // the beam: a cone that widens with distance, sweeping slowly over the water
                    let a = .pi + sin(t * 0.8) * 0.22
                    for d in 3..<72 {
                        let spread = d / 9
                        for s in -spread...spread {
                            let x = lx + 3 + Int(cos(a) * Double(d)), y = ly + 1 + Int(sin(a) * Double(d)) + s
                            if x >= 0 && y >= 0 && y < rows - 9 { p.dot(x, y, Brand.amber.opacity(0.42 * (1 - Double(d) / 72) * (s == 0 ? 1 : 0.6))) }
                        }
                    }
                    let cyc = t.truncatingRemainder(dividingBy: 4.5)
                    if cyc < 1.1 {
                        let k = cyc / 1.1, sx = 10 + Int(k * Double(cols - 50)), sy = 2 + Int(k * 9)
                        for tail in 0..<7 { p.dot(sx - tail, sy - tail / 2, Brand.cream.opacity(1 - Double(tail) / 7)) }
                    }
                case .question:
                    // a gull crossing the sky with a question mark in tow
                    sea(p, cols: cols, top: rows - 9, t: t)
                    let k = (t * 0.09).truncatingRemainder(dividingBy: 1)
                    let gx = Int(k * Double(cols + 24)) - 12, gy = 9 + Int(sin(t * 1.6) * 3)
                    p.sprite(Int(t * 5) % 2 == 0 ? Sprites.gullA : Sprites.gullB, gx, gy, ["c": Brand.cream, "a": Brand.amber])
                    p.sprite(Sprites.ask, gx - 9, gy - 3 + Int(sin(t * 3) * 1.4), ["a": kind.color])
                }
            }
        }
        .frame(height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x0b0d12)))
        .accessibilityHidden(true)
    }
}

/// Send: the note rolls into a bottle, the bottle flies out to sea, drifts to the lighthouse, the lamp flashes.
private struct BottleScene: View {
    /// 0…1, see `progress` in the sheet.
    let progress: (Date) -> Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate, k = progress(tl.date)
            Canvas { ctx, size in
                let p = Pix(ctx: ctx, px: 4)
                let cols = Int(size.width / 4), rows = Int(size.height / 4), top = rows - 10
                sky(p, cols: cols, t: t)
                // shore on the left
                for y in (top - 1)..<rows { for x in 0..<(12 + (y - top) * 2) { p.dot(x, y, (x * 7 + y * 3) % 11 == 0 ? sandDark : sand) } }
                sea(p, cols: cols, top: top + 1, t: t, from: 20)
                // the lighthouse far out
                let lx = cols - 16, ly = top - 11
                for x in (lx - 2)...(lx + 8) { p.dot(x, top, Color(hex: 0x3a3f4a)) }
                let lit = k >= 0.9
                p.sprite(Sprites.lighthouse, lx, ly, ["l": lit ? Brand.amber : Brand.cream.opacity(0.4), "w": Brand.cream, "r": Color(hex: 0xe0533d)])
                if lit {
                    let f = (k - 0.9) / 0.1
                    for i in 0..<14 {
                        let ang = Double(i) / 14 * 2 * .pi, d = 2 + f * 9
                        p.dot(lx + 3 + Int(cos(ang) * d), ly + Int(sin(ang) * d * 0.7), (i % 2 == 0 ? Brand.amber : Brand.cream).opacity(1 - f * 0.6))
                    }
                    for d in stride(from: 4.0, to: 46.0, by: 1.0) { p.dot(lx + 3 - Int(d), ly + Int(d * 0.08), Brand.amber.opacity(0.4 * (1 - d / 46))) }
                }
                let bx0 = 8, by0 = top - 7
                switch k {
                case ..<0.22:   // the note rolls down into the bottle, the cork goes on
                    let f = k / 0.22
                    p.sprite(Sprites.bottleUp, bx0, by0, ["g": glass, "s": Brand.cream.opacity(f > 0.7 ? 1 : 0), "k": f > 0.85 ? cork : .clear])
                    if f <= 0.7 { p.sprite(Sprites.scroll, bx0, by0 - 8 + Int(f / 0.7 * 7), ["s": Brand.cream]) }
                case ..<0.45:   // thrown: an arc out over the water
                    let f = (k - 0.22) / 0.23
                    let x = bx0 + Int(f * 22), y = by0 - Int(sin(f * .pi) * 12) + Int(f * 6)
                    p.sprite(Int(f * 6) % 2 == 0 ? Sprites.bottleUp : Sprites.bottleLie, x, y, ["g": glass, "s": Brand.cream, "k": cork])
                case ..<0.52:   // splash
                    let f = (k - 0.45) / 0.07, sx = bx0 + 24
                    for i in 0..<10 { let ang = Double(i) / 10 * .pi; p.dot(sx + Int(cos(ang) * (2 + f * 5)), top - Int(sin(ang) * (1 + f * 4)), Brand.blue.opacity(1 - f)) }
                    p.sprite(Sprites.bottleLie, sx - 3, top - 2, ["g": glass, "s": Brand.cream, "k": cork])
                default:        // drifting to the lighthouse, bobbing
                    let f = min(1, (k - 0.52) / 0.38)
                    let x = bx0 + 21 + Int(f * Double(lx - bx0 - 33)), bob = Int(t * 3) % 2
                    p.sprite(Sprites.bottleLie, x, top - 2 + bob, ["g": glass, "s": Brand.cream, "k": cork])
                }
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x0b0d12)))
        .accessibilityHidden(true)
    }
}

/// The kind as a 9×9 glyph (tabs, buttons).
struct FeedbackGlyph: View {
    let kind: FeedbackKind
    var size: CGFloat = 12
    private static let maps: [FeedbackKind: [String]] = [
        .bug: ["#.......#", "##.....##", "##.###.##", ".#######.", "..#####..", ".#.#.#.#.", ".........", ".........", "........."],
        .feature: ["....#....", "....#....", "...###...", "#########", ".#######.", "..#####..", "..##.##..", ".##...##.", ".#.....#."],
        .question: [".#####...", "##...##..", ".....##..", "....##...", "...##....", "...##....", ".........", "...##....", "...##...."],
    ]
    var body: some View {
        Canvas { ctx, sz in
            let c = sz.width / 9
            for (y, row) in (Self.maps[kind] ?? []).enumerated() { for (x, ch) in row.enumerated() where ch == "#" {
                ctx.fill(Path(CGRect(x: CGFloat(x) * c, y: CGFloat(y) * c, width: c, height: c)), with: .color(kind.color))
            } }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - The sheet

/// Put once over the window (Views.swift): shows the sheet while `AppFeedback.shared.kind` is set.
struct AppFeedbackHost: View {
    @ObservedObject private var fb = AppFeedback.shared
    var body: some View {
        ZStack {
            if let k = fb.kind {
                Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { }
                FeedbackSheet(kind: k).id("feedback")
            }
        }
        .onAppear {
            let a = CommandLine.arguments
            if let i = a.firstIndex(of: "--feedback"), i + 1 < a.count, let k = FeedbackKind(rawValue: a[i + 1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { AppFeedback.shared.open(k) }
            }
        }
    }
}

private struct FeedbackSheet: View {
    @ObservedObject private var fb = AppFeedback.shared
    let kind: FeedbackKind
    @State private var title = ""
    @State private var text = ""
    @State private var name = Prefs.store.string(forKey: "feedbackName") ?? ""
    @State private var email = Prefs.store.string(forKey: "feedbackEmail") ?? ""
    @State private var withInfo = true
    @State private var withShot: Bool? = nil
    @State private var phase: Phase = .writing
    @State private var startedAt = Date()
    @State private var doneAt: Date?
    @State private var sent: AppFeedback.Sent?
    @State private var failure: String?
    @FocusState private var focused: Bool
    enum Phase { case writing, sending, sent }

    private var shotOn: Bool { (withShot ?? (kind == .bug)) && fb.shot != nil }
    private var page: String { withInfo && !fb.tab.isEmpty ? "Tab \(fb.tab)" : "" }
    private var canSend: Bool { title.trimmingCharacters(in: .whitespaces).count >= 3 }
    private var freeze: String? { let a = CommandLine.arguments; return a.firstIndex(of: "--feedback-freeze").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch phase {
            case .writing: form
            case .sending: sending
            case .sent: thanks
            }
        }
        .padding(18)
        .frame(width: 580)
        .background(RoundedRectangle(cornerRadius: 14).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.line2))
        .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        .onExitCommand { if phase != .sending { fb.close() } }
        .onAppear {
            NSApp.keyWindow?.makeFirstResponder(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--feedback-send"), i + 1 < args.count {   // test hook: fill the title and press Send
                title = args[i + 1]; text = "Sent by the test hook (--feedback-send)."
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { send() }
            }
            if let f = freeze {   // test hook: hold the send scene / the thank-you
                title = "Roadmap freezes when I switch project"
                if f == "sent" { phase = .sent; sent = .init(id: "fbtest", follow: URL(string: "https://relay.steerify.dev/roadmap/\(AppFeedback.inbox)")) }
                else if let k = Double(f) { phase = .sending; startedAt = Date().addingTimeInterval(-k * 3.0); doneAt = k >= 0.9 ? Date().addingTimeInterval(-100) : nil }
            }
        }
    }

    // MARK: writing

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.headline.uppercased()).font(Brand.label(16)).foregroundStyle(Brand.cream)
                Spacer()
                Button { fb.close() } label: { Image(systemName: "xmark").foregroundStyle(Brand.mute) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).help("Close (esc)")
            }
            KindScene(kind: kind)
            HStack(spacing: 6) {
                ForEach(FeedbackKind.allCases) { k in
                    Button { fb.kind = k } label: {
                        HStack(spacing: 6) {
                            FeedbackGlyph(kind: k, size: S(11))
                            Text(k.label.uppercased()).font(Brand.label(8)).tracking(0.8)
                                .foregroundStyle(k == kind ? Brand.cream : Brand.mute)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(PixelBox(step: 2).fill(k == kind ? k.color.opacity(0.16) : Brand.panel2))
                        .overlay(PixelBox(step: 2).stroke(k == kind ? k.color : Brand.line2))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).pointerStyle(.link)
                }
            }
            Text(kind.hint).font(.system(size: S(12))).foregroundStyle(Brand.mute).fixedSize(horizontal: false, vertical: true)
            TextField(kind.titlePrompt, text: $title)
                .textFieldStyle(.plain).font(.system(size: S(13.5), weight: .medium)).foregroundStyle(Brand.cream)
                .padding(9).background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel2))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(focused ? kind.color.opacity(0.6) : Brand.line2))
                .focused($focused)
                .onSubmit { if canSend { send() } }
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(kind == .bug ? "What you did, what you expected, what happened instead" : "A few more words (optional)")
                        .font(.system(size: S(12.5))).foregroundStyle(Brand.mute.opacity(0.7)).padding(.horizontal, 13).padding(.vertical, 9)
                }
                TextEditor(text: $text).font(.system(size: S(12.5))).foregroundStyle(Brand.cream)
                    .scrollContentBackground(.hidden).padding(6)
            }
            .frame(height: 78)
            .background(RoundedRectangle(cornerRadius: 7).fill(Brand.panel2))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.line2))
            attached
            if let failure {
                Text("Not sent: \(failure)").font(.system(size: S(11.5))).foregroundStyle(Brand.red)
            }
            HStack {
                Button("or open it on GitHub ↗") { NSWorkspace.shared.open(AppFeedback.github) }
                    .buttonStyle(.plain).font(.system(size: S(11.5))).foregroundStyle(Brand.mute).pointerStyle(.link)
                Spacer()
                PixelCTA(title: "Send", color: canSend ? kind.color : Brand.line2, small: true, icon: "play") { if canSend { send() } }
                    .disabled(!canSend)
            }
        }
    }

    /// Exactly what goes with it, each part in one click.
    private var attached: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("SENT WITH IT · YOU SEE ALL OF IT").font(Brand.label(8)).tracking(0.8).foregroundStyle(Brand.mute)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $withInfo) {
                        Text("Steerify \(AppFeedback.version)\(fb.tab.isEmpty ? "" : " · tab \(fb.tab)")").font(.system(size: S(11.5))).foregroundStyle(Brand.ink)
                    }.toggleStyle(.checkbox)
                    if fb.shot != nil {
                        Toggle(isOn: Binding(get: { shotOn }, set: { withShot = $0 })) {
                            Text("A screenshot of this window").font(.system(size: S(11.5))).foregroundStyle(Brand.ink)
                        }.toggleStyle(.checkbox)
                    }
                    HStack(spacing: 6) {
                        small("Name (optional)", $name).frame(width: 130)
                        small("Email, to hear back (optional)", $email)
                    }
                }
                if let img = fb.shot {
                    Image(nsImage: img).resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
                        .frame(width: 128).clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Brand.line2))
                        .opacity(shotOn ? 1 : 0.25)
                        .onTapGesture { withShot = !shotOn }
                }
            }
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.line2, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
    private func small(_ p: String, _ b: Binding<String>) -> some View {
        TextField(p, text: b).textFieldStyle(.plain).font(.system(size: S(11.5))).foregroundStyle(Brand.cream)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(Brand.panel2))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.line2))
    }

    // MARK: sending

    /// The throw takes 3 s; the bottle waits at sea for the relay, then reaches the lighthouse.
    private func progress(_ now: Date) -> Double {
        let base = min(now.timeIntervalSince(startedAt) / 3.0, 0.88)
        guard let d = doneAt else { return base }
        let after = now.timeIntervalSince(max(d, startedAt.addingTimeInterval(3.0)))
        return after < 0 ? base : 0.88 + min(after / 0.9, 1) * 0.12
    }
    private var sending: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MESSAGE IN A BOTTLE…").font(Brand.label(16)).foregroundStyle(Brand.cream)
            BottleScene(progress: progress)
            Text("“\(title)” is on its way to the Steerify crew.").font(.system(size: S(12.5))).foregroundStyle(Brand.mute).lineLimit(2)
        }
    }

    private func send() {
        failure = nil
        let k = kind, ti = title.trimmingCharacters(in: .whitespacesAndNewlines), tx = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let nm = name.trimmingCharacters(in: .whitespaces), em = email.trimmingCharacters(in: .whitespaces)
        Prefs.store.set(nm, forKey: "feedbackName"); Prefs.store.set(em, forKey: "feedbackEmail")
        let shot = shotOn ? fb.shot.flatMap(AppFeedback.dataURL) : nil
        let pg = page
        startedAt = Date(); doneAt = nil
        withAnimation(.easeOut(duration: 0.2)) { phase = .sending }
        Task {
            do {
                let s = try await AppFeedback.send(kind: k, title: ti, text: tx, page: pg, name: nm, email: em, shot: shot)
                sent = s; AppFeedback.countOne(); doneAt = Date()
                let land = max(Date(), startedAt.addingTimeInterval(3.0)).addingTimeInterval(1.7)
                try? await Task.sleep(nanoseconds: UInt64(max(0, land.timeIntervalSinceNow) * 1e9))
                withAnimation(.easeOut(duration: 0.25)) { phase = .sent }
            } catch {
                failure = error.localizedDescription
                withAnimation { phase = .writing }
            }
        }
    }

    // MARK: sent

    private var thanks: some View {
        let n = max(AppFeedback.sentCount, freeze == "sent" ? 3 : 1), r = AppFeedback.rank(n)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                RankBadge(n: n).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("GOT IT. THANK YOU!").font(Brand.label(16)).foregroundStyle(Brand.cream)
                    Text("Report #\(n) · you're a \(r.name) now" + (r.next.map { " · \($0 - n) more to the next rank" } ?? ""))
                        .font(.system(size: S(12))).foregroundStyle(Brand.amber)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Array(["Received", "Planned", "In progress", "Ready to test", "Live"].enumerated()), id: \.offset) { i, s in
                        VStack(alignment: .leading, spacing: 4) {
                            Rectangle().fill(i == 0 ? Brand.green : Brand.line2).frame(height: 6)
                            Text(s.uppercased()).font(Brand.label(8)).foregroundStyle(i == 0 ? Brand.green : Brand.mute).lineLimit(1).fixedSize()
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(email.isEmpty ? "It's on our board now. Follow it with the link below." : "We'll email \(email) at every step.")
                    .font(.system(size: S(12))).foregroundStyle(Brand.mute)
            }
            HStack {
                if let u = sent?.follow {
                    Button("Follow it ↗") { NSWorkspace.shared.open(u) }.buttonStyle(.plain)
                        .font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.amber).pointerStyle(.link)
                }
                Spacer()
                Button("Send another") { title = ""; text = ""; phase = .writing }.buttonStyle(.plain)
                    .font(.system(size: S(12))).foregroundStyle(Brand.mute).pointerStyle(.link)
                PixelCTA(title: "Done", small: true, icon: "play") { fb.close() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// A pixel medal for the crew rank: a ribbon, a gold coin with the ship's wheel, one star per rank.
private struct RankBadge: View {
    let n: Int
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 10)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let p = Pix(ctx: ctx, px: size.width / 16)
                for y in 0..<5 { p.dot(5, y, Color(hex: 0xe0533d)); p.dot(6, y, Color(hex: 0xe0533d)); p.dot(9, y, Brand.blue); p.dot(10, y, Brand.blue) }
                for y in 4..<16 { for x in 2..<14 {
                    let dx = Double(x) - 7.5, dy = Double(y) - 9.5, r = (dx * dx + dy * dy).squareRoot()
                    if r <= 5.6 { p.dot(x, y, r > 4.6 ? Color(hex: 0xb07a10) : Brand.amber) }
                } }
                for (x, y) in [(7, 7), (8, 7), (7, 12), (8, 12), (5, 9), (5, 10), (10, 9), (10, 10), (7, 9), (8, 10), (8, 9), (7, 10)] { p.dot(x, y, Color(hex: 0x6b4a10)) }
                let shine = Int(t * 6) % 24
                if shine < 6 { p.dot(4 + shine, 6 + shine / 2, Brand.cream) }
            }
        }
        .accessibilityLabel("Report \(n)")
    }
}
