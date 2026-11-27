import SwiftUI

// MARK: - After setup: the pixel mate (request r261125-000506, choice onboarding-after-setup A)
//
// A small pixel captain walks a new user through the real screens right after setup:
//   1. resume  — the roadmap has a chapter with open work: explain chapters, ring its Resume button.
//   2. request — point at + Request (⌘N); in the sheet, explain the kinds and offer an example.
//   then, the first time a choice / an item to test shows up: an in-place card says what happens when you answer.
// Per Mac. It starts when you press Set up with Claude (never for boards set up before this build), and again from
// Help → Show the Steerify Guide. Every step can be skipped; the whole guide is under a minute.

@MainActor final class Onboarding: ObservableObject {
    static let shared = Onboarding()

    enum Step: String { case off = "", pending, resume, request, requestSheet, farewell, done }
    private static let stepKey = "onbStep", seenKey = "onbSeen"

    @Published private(set) var step: Step
    @Published private(set) var seen: Set<String>
    /// The chapter whose Resume button the mate points at (step resume).
    @Published var target: String?

    private init() {
        step = Step(rawValue: Prefs.store.string(forKey: Self.stepKey) ?? "") ?? .off
        seen = Set(Prefs.store.stringArray(forKey: Self.seenKey) ?? [])
        // Test hook: `--onboarding [step]` starts the guide (at that step: resume, request, requestSheet, done).
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--onboarding") {
            step = (i + 1 < a.count ? Step(rawValue: a[i + 1]) : nil) ?? .pending; seen = []
        }
    }

    /// Guide shown at all on this Mac (started by a setup or by Help).
    var active: Bool { step != .off }

    func go(_ s: Step) {
        step = s
        if s != .resume { target = nil }
        Prefs.store.set(s.rawValue, forKey: Self.stepKey)
    }
    /// Set up with Claude pressed: the guide waits for the board to be drafted.
    func setupStarted() { if step == .off || step == .done { go(.pending) } }
    /// Help → Show the Steerify Guide: from the start, first-time cards included.
    func replay() { seen = []; Prefs.store.set([String](), forKey: Self.seenKey); go(.pending) }
    func skipAll() { go(.done); markSeen("choice"); markSeen("test") }

    func shouldExplain(_ kind: String) -> Bool { active && !seen.contains(kind) }
    func markSeen(_ kind: String) {
        seen.insert(kind)
        Prefs.store.set(Array(seen).sorted(), forKey: Self.seenKey)
    }

    /// The chapter to resume: where you left off, else the first approved chapter with open work.
    func chapterToResume(_ b: BoardStore, _ model: AppModel) -> String? {
        let drafts = Set(b.chapters.filter(\.draft).map(\.name))
        let ok: (String) -> Bool = { !drafts.contains($0) && $0 != RequestLog.fixesChapter }
        if let c = model.whereYouLeftOff(b.project, limit: 3).first(where: { ok($0.track) }) { return c.track }
        return b.roadmap.first { $0.status != "done" && ok($0.track) }?.track
    }
}

// MARK: - Anchors (the real controls the mate points at)

struct OnbAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Marks the Resume button of the chapter the mate points at.
struct OnbResumeAnchor: ViewModifier {
    @ObservedObject private var onb = Onboarding.shared
    let track: String
    func body(content: Content) -> some View {
        content.anchorPreference(key: OnbAnchorKey.self, value: .bounds) {
            onb.step == .resume && onb.target == track ? ["resume": $0] : [:]
        }
    }
}

// MARK: - Frenk's pixel face (the one on the site + HQ; choice onboarding-guide-character A)
//
// art/guide/frenk.png = 4 faces (neutral, brow up, squint, smirk), frenk-laugh.png = neutral + laugh.
// Bundled in Contents/Resources/guide by scripts/bundle.sh; `swift run` reads them from the repo.

enum FrenkMood { case neutral, brow, squint, smirk, laugh }

@MainActor enum FrenkFace {
    private static func sheet(_ name: String) -> NSImage? {
        if let u = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "guide"), let i = NSImage(contentsOf: u) { return i }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../art/guide/\(name).png")
        return NSImage(contentsOf: repo)
    }
    private static var cache: [String: CGImage] = [:]
    private static func cut(_ name: String, _ i: Int, of n: Int) -> CGImage? {
        let key = "\(name)#\(i)"
        if let c = cache[key] { return c }
        guard let img = sheet(name), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = cg.width / n
        let out = cg.cropping(to: CGRect(x: i * w, y: 0, width: w, height: cg.height))
        cache[key] = out
        return out
    }
    static func image(_ m: FrenkMood) -> CGImage? {
        switch m {
        case .neutral: cut("frenk", 0, of: 4)
        case .brow: cut("frenk", 1, of: 4)
        case .squint: cut("frenk", 2, of: 4)
        case .smirk: cut("frenk", 3, of: 4)
        case .laugh: cut("frenk-laugh", 1, of: 2)
        }
    }
    static var available: Bool { image(.neutral) != nil }
}

/// The face in its amber frame with the name plate. Talking: the mouth opens and closes; at rest a smirk now and then.
struct FrenkPortrait: View {
    var mood: FrenkMood = .neutral
    var talking = false
    var size: CGFloat = 120
    @Environment(\.controlActiveState) private var windowState

    var body: some View {
        VStack(spacing: 0) {
            Group {
                // Pauses when the window is not in front (idle CPU budget, requirement onb-perf).
                if windowState == .inactive { face(mood) } else {
                    TimelineView(.periodic(from: .now, by: 0.15)) { t in face(frame(Int(t.date.timeIntervalSinceReferenceDate / 0.15))) }
                }
            }
            .frame(width: size, height: size)
            .background(Color(hex: 0x0b0c10))
            .overlay(Rectangle().stroke(Brand.amber, lineWidth: 3))
            Text("FRENK").font(Brand.label(10)).tracking(1).foregroundStyle(Color(hex: 0x1a1200))
                .frame(width: size + 3).padding(.vertical, 3).background(Brand.amber)
        }
    }
    private func frame(_ t: Int) -> FrenkMood {
        if talking { return t % 2 == 1 ? (mood == .laugh ? .smirk : .laugh) : mood }
        return t % 40 == 0 && mood != .laugh ? .smirk : mood
    }
    @ViewBuilder private func face(_ m: FrenkMood) -> some View {
        if let cg = FrenkFace.image(m) {
            Image(decorative: cg, scale: 1).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
        } else {
            Text("F").font(Brand.label(40)).foregroundStyle(Brand.amber)
        }
    }
}

/// An RPG dialogue box: Frenk on the left, the text typing itself out (click it to show it all), buttons below.
/// Markdown in `say`: **bold** comes out amber.
struct FrenkSays<Buttons: View>: View {
    var mood: FrenkMood = .neutral
    let title: String
    let say: String
    var dots: String? = nil
    var width: CGFloat = 600
    var face: CGFloat = 120
    @ViewBuilder var buttons: Buttons
    @State private var shown = 0

    private var full: AttributedString {
        var a = (try? AttributedString(markdown: say)) ?? AttributedString(say)
        for r in a.runs where r.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            a[r.range].foregroundColor = Brand.amber
        }
        return a
    }
    private var total: Int { full.characters.count }
    /// What is typed so far, plus the rest invisible: the box keeps its size while the text appears.
    private var typed: AttributedString {
        let a = full, n = min(shown, a.characters.count)
        let cut = a.characters.index(a.startIndex, offsetBy: n)
        var rest = AttributedString(a[cut...]); rest.foregroundColor = .clear
        return AttributedString(a[..<cut]) + rest
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FrenkPortrait(mood: mood, talking: shown < total, size: S(face))
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased()).font(Brand.label(10.5)).tracking(1).foregroundStyle(Brand.amber)
                Text(typed).font(.system(size: S(13.5))).foregroundStyle(Brand.cream).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle()).onTapGesture { shown = total }
                HStack(spacing: 12) {
                    if let dots { Text(dots).font(.system(size: S(10), design: .monospaced)).foregroundStyle(Brand.mute) }
                    Spacer(minLength: 0)
                    buttons
                }
            }
        }
        .padding(12)
        .frame(width: S(width), alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)   // as tall as its text, never the whole window
        .background(Color(hex: 0x16171c))
        .overlay(Rectangle().inset(by: 5).stroke(Brand.amber, lineWidth: 2))
        .overlay(Rectangle().stroke(Brand.cream, lineWidth: 3))
        .background(Rectangle().fill(Color.black).offset(x: 6, y: 6))
        .task(id: say) {
            shown = 0
            while shown < total {
                try? await Task.sleep(for: .milliseconds(22))
                if Task.isCancelled { return }
                shown += 1
            }
        }
    }
}

struct MateButton: View {
    let title: String
    var primary = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: S(11.5), weight: primary ? .bold : .regular, design: primary ? .monospaced : .default))
                .foregroundStyle(primary ? Color(hex: 0x1a1200) : Brand.mute)
                .padding(.horizontal, primary ? 10 : 2).padding(.vertical, 6)
                .background(Rectangle().fill(primary ? Brand.amber : .clear))
                .background(Rectangle().fill(primary ? Color.black : .clear).offset(x: 3, y: 3))
        }.buttonStyle(SteerButton())
    }
}

// MARK: - The guide over the board (steps resume and request)

struct OnboardingHost: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var onb = Onboarding.shared
    @ObservedObject private var since = SinceYouLeft.shared   // the guide waits for "Since you left" to close
    @ObservedObject var board: BoardStore
    let anchors: [String: Anchor<CGRect>]
    @State private var pulse = false

    private var p: Project { board.project }
    private var ready: Bool {
        ProjectSetup.phase(board, model) == .board && !ProjectSetup.isBlank(board) && model.requestProjectId == nil
            && !model.paletteOpen && model.preview == nil && since.brief == nil
    }

    var body: some View {
        GeometryReader { g in
            if ready {
                switch onb.step {
                case .resume: resumeStep(g)
                case .request: requestStep(g)
                case .farewell: farewell(g)
                default: EmptyView()
                }
            }
        }
        .onAppear(perform: advance)
        .onChange(of: onb.step) { _, _ in advance() }
        .onChange(of: board.roadmap.count) { _, _ in advance() }
        .onChange(of: model.requestProjectId) { _, id in
            if id == nil, onb.step == .requestSheet { onb.go(.farewell) }
        }
        // Resume pressed on the chapter itself (not in the bubble): same as the bubble's button.
        .onChange(of: model.sessions.count) { _, _ in
            guard onb.step == .resume, let t = onb.target else { return }
            if model.liveSession(for: "track:" + BoardFiles.slug(t), in: p) != nil { onb.go(.request) }
        }
    }

    /// pending → the first step that applies, once the board is drafted and setup has stopped.
    private func advance() {
        guard ProjectSetup.phase(board, model) == .board, !ProjectSetup.isBlank(board) else { return }
        switch onb.step {
        case .pending:
            if let t = onb.chapterToResume(board, model) { onb.target = t; onb.go(.resume); show(t) } else { onb.go(.request) }
        case .resume:
            // Back after a relaunch: point at the chapter again, but never pull you to the Roadmap by yourself.
            if onb.target == nil, let t = onb.chapterToResume(board, model) { onb.target = t }
            if onb.target == nil { onb.go(.request) }
        default: break
        }
    }
    private func show(_ track: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { model.focusItem(projectId: p.id, ref: "track:" + BoardFiles.slug(track)) }
    }

    private func resume() {
        guard let t = onb.target else { return }
        var x = ItemRef(ref: "track:" + BoardFiles.slug(t))!; x.title = "Chapter: " + t
        x.area = board.roadmap.first { $0.track == t }?.area
        onb.go(.request)
        model.start(projectId: p.id, item: x, intent: .resume)
    }

    @ViewBuilder private func resumeStep(_ g: GeometryProxy) -> some View {
        let t = onb.target ?? ""
        let items = board.roadmap.filter { $0.track == t }
        let done = items.filter { $0.status == "done" }.count
        let next = items.first { $0.status == "wip" } ?? items.first { $0.status != "done" }
        let rect = anchors["resume"].map { g[$0] }
        ZStack(alignment: .topLeading) {
            if let rect {
                // Dim everything but the real Resume button; clicks still go through to it.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: g.size))
                    path.addRoundedRect(in: rect.insetBy(dx: -6, dy: -6), cornerSize: CGSize(width: 8, height: 8))
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 8).stroke(pulse ? Brand.cream : Brand.amber, lineWidth: 2)
                    .frame(width: rect.width + 12, height: rect.height + 12)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                    .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { pulse = true } }
            }
            FrenkSays(mood: .neutral, title: "Your roadmap · 1/3",
                      say: "Hi, I'm Frenk, I made Steerify. This is your roadmap: one chapter, one goal. **\(t)** is \(done) of \(items.count) done"
                        + (next.map { ", next up **\($0.text.prefix(60))\($0.text.count > 60 ? "…" : "")**" } ?? "")
                        + ". Hit **Resume** and Claude checks what really exists, then rows on.",
                      dots: "● ○ ○") {
                MateButton(title: "Skip guide", primary: false) { onb.skipAll() }
                MateButton(title: "Later", primary: false) { onb.go(.request) }
                MateButton(title: "Resume it ▶") { resume() }
            }
            .position(bubbleCenter(g, near: rect))
        }
    }

    @ViewBuilder private func requestStep(_ g: GeometryProxy) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 2) {
                Text("▲ + Request").font(Brand.label(11)).foregroundStyle(Brand.amber).padding(.trailing, 8)
                FrenkSays(mood: .smirk, title: "Ask for anything · 2/3",
                          say: "Want something new? A fix, a feature, a chore you hate: hit **+ Request** (⌘N) and say it like you'd tell a friend. Claude files it and only asks what it can't guess.",
                          dots: "● ● ○", width: 520, face: 96) {
                    MateButton(title: "Skip", primary: false) { onb.skipAll() }
                    MateButton(title: "Try it ⌘N") { onb.go(.requestSheet); model.requestOpen = true }
                }
            }
            .padding(.top, 8).padding(.trailing, 30)
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .topTrailing)
    }

    @ViewBuilder private func farewell(_ g: GeometryProxy) -> some View {
        FrenkSays(mood: .laugh, title: "That's it · 3/3",
                  say: "You steer, Claude rows. Lost? **⌘J** jumps to whatever waits on you. I'm in **Help** if you miss me.",
                  width: 520, face: 96) {
            MateButton(title: "Let's go") { withAnimation { onb.go(.done) } }
        }
        .position(x: g.size.width / 2, y: g.size.height * 0.4)
    }

    /// Below-left of the button it points at (the mate's hand towards it), kept inside the board.
    private func bubbleCenter(_ g: GeometryProxy, near rect: CGRect?) -> CGPoint {
        let w = S(600), h = S(175)
        guard let rect else { return CGPoint(x: g.size.width / 2, y: S(150)) }
        var x = rect.maxX - w / 2 - 24, y = rect.maxY + 14 + h / 2
        if y + h / 2 > g.size.height - 10 { y = rect.minY - 14 - h / 2 }
        x = min(max(x, w / 2 + 10), g.size.width - w / 2 - 10)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - In the request sheet (step requestSheet)

struct OnbRequestTip: View {
    @ObservedObject private var onb = Onboarding.shared
    let fill: (String) -> Void
    var body: some View {
        if onb.step == .requestSheet {
            HStack(alignment: .top, spacing: 12) {
                FrenkPortrait(mood: .brow, size: S(64))
                VStack(alignment: .leading, spacing: 6) {
                    (Text("One line is enough. ").bold().foregroundColor(Brand.amber)
                     + Text("Steerify sorts it first: a ") + Text("fix").bold() + Text(" lands in Fixes, a ") + Text("feature").bold()
                     + Text(" becomes a draft chapter you approve, a ") + Text("task").bold() + Text(" goes to Tasks, a ")
                     + Text("question").bold() + Text(" comes back as a choice. No pressure: Esc and nothing is sent."))
                        .font(.system(size: S(12))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                    Button { fill("Customers should get an email when their order ships") } label: {
                        Text("Use an example").font(.system(size: S(11), weight: .semibold)).foregroundStyle(Brand.amber)
                    }.buttonStyle(SteerButton())
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.amberDim))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.amber.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }
}

// MARK: - First choice / first item to test: what happens when you answer (once each)

struct OnbFirstCard: View {
    enum Kind: String { case choice, test }
    let kind: Kind
    @ObservedObject private var onb = Onboarding.shared
    var body: some View {
        if onb.shouldExplain(kind.rawValue) {
            HStack(spacing: 0) {
                FrenkSays(mood: kind == .choice ? .brow : .squint, title: kind == .choice ? "Your first choice" : "Your first test",
                          say: say, dots: "first time only", width: 640, face: 96) {
                    MateButton(title: "Got it") { withAnimation { onb.markSeen(kind.rawValue) } }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4).padding(.bottom, 10)
            .transition(.opacity)
        }
    }
    private var say: String {
        switch kind {
        case .choice:
            return "Claude stopped: only you can decide this one (yes, the power). Look at the options, **pick one**, mix them with a note. Claude builds your pick and brings it to **To test**."
        case .test:
            return "Claude says it works. Trust, but click. Open each link, look at the picture, then **OK** ships it with the next release, **Refine** sends your note back, **Broken**… you know."
        }
    }
}
