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

    enum Step: String { case off = "", pending, resume, request, requestSheet, done }
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

// MARK: - The pixel mate (24 × 24, drawn like PixelScene / LevelArt)

struct PixelMate: View {
    enum Pose { case idle, point, wave, think }
    var pose: Pose = .idle
    var size: CGFloat = 96
    @Environment(\.controlActiveState) private var windowState

    var body: some View {
        // Pauses when the window is not in front (idle CPU budget, requirement onb-perf).
        if windowState == .inactive {
            canvas(0)
        } else {
            TimelineView(.periodic(from: .now, by: 0.14)) { t in canvas(Int(t.date.timeIntervalSinceReferenceDate / 0.14)) }
        }
    }

    private func canvas(_ t: Int) -> some View {
        Canvas { ctx, sz in
            let px = sz.width / 24
            func r(_ c: Color, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
                ctx.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: CGFloat(w) * px, height: CGFloat(h) * px)), with: .color(c))
            }
            let skin = Color(hex: 0xf2c79a), ink = Color(hex: 0x16171c), coat = Brand.blue
            let bob = (t >> 2) % 2
            r(Brand.amber, 7, 2 + bob, 10, 2); r(Brand.amber, 5, 4 + bob, 14, 1)            // captain's hat
            r(ink, 7, 3 + bob, 10, 1)
            r(skin, 8, 5 + bob, 8, 6)                                                       // face
            if t % 22 == 0 { r(skin, 10, 7 + bob, 4, 1) } else { r(ink, 10, 7 + bob, 1, 1); r(ink, 13, 7 + bob, 1, 1) }
            r(ink, 10, 9 + bob, 4, 1)
            r(coat, 7, 11, 10, 8); r(Brand.cream, 11, 11, 2, 8); r(Brand.amber, 11, 13, 2, 1) // coat, shirt, buckle
            r(ink, 8, 19, 3, 3); r(ink, 13, 19, 3, 3)                                       // boots
            switch pose {
            case .point: r(coat, 5, 12, 2, 5); r(coat, 17, 12, 5, 2); r(skin, 22, 12, 2, 2)
            case .wave:
                let up = (t >> 1) % 2 == 0
                r(coat, 5, 12, 2, 5); r(coat, 17, up ? 8 : 10, 2, 4); r(skin, 17, up ? 6 : 8, 2, 2)
            case .think:
                r(coat, 5, 12, 2, 5); r(skin, 14, 10 + bob, 2, 2)
                if (t >> 2) % 3 == 0 { r(Brand.cream, 19, 2, 2, 2); r(Brand.cream, 21, 0, 1, 1) }
            case .idle: r(coat, 5, 12, 2, 5); r(coat, 17, 12, 2, 5)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Cream speech bubble with a hard pixel shadow (the site / onboarding art look).
struct MateBubble<Buttons: View>: View {
    let title: String
    let text: Text
    var dots: String? = nil
    var width: CGFloat = 300
    @ViewBuilder var buttons: Buttons
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Brand.label(10.5)).tracking(0.8).foregroundStyle(Color(hex: 0x7a4a00))
            text.font(.system(size: S(13))).foregroundStyle(Color(hex: 0x16171c)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let dots { Text(dots).font(.system(size: S(10), design: .monospaced)).foregroundStyle(Color(hex: 0x7b7f8a)) }
                Spacer(minLength: 0)
                buttons
            }.padding(.top, 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(width: S(width), alignment: .leading)
        .background(ZStack {   // hard pixel shadow under the cream
            Rectangle().fill(Color(hex: 0x16171c)).offset(x: 4, y: 4)
            Rectangle().fill(Brand.cream)
        })
    }
}

struct MateButton: View {
    let title: String
    var primary = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: S(11.5), weight: primary ? .bold : .regular, design: primary ? .monospaced : .default))
                .foregroundStyle(primary ? Brand.amber : Color(hex: 0x5a5a5a))
                .padding(.horizontal, primary ? 10 : 2).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 3).fill(primary ? Color(hex: 0x16171c) : .clear))
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
                default: EmptyView()
                }
            }
        }
        .onAppear(perform: advance)
        .onChange(of: onb.step) { _, _ in advance() }
        .onChange(of: board.roadmap.count) { _, _ in advance() }
        .onChange(of: model.requestProjectId) { _, id in
            if id == nil, onb.step == .requestSheet { onb.go(.done); model.showToast("Guide done. Replay it any time: Help → Show the Steerify Guide.") }
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
            if onb.target == nil, let t = onb.chapterToResume(board, model) { onb.target = t; show(t) }
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
            mate(.point,
                 title: "Your roadmap",
                 text: Text("A chapter is one goal, split in key results. ")
                    + Text("\(t)").bold() + Text(": \(done) of \(items.count) done")
                    + (next.map { Text(", next ") + Text($0.text.prefix(60) + ($0.text.count > 60 ? "…" : "")).bold() } ?? Text(""))
                    + Text(". ") + Text("Resume").bold() + Text(" opens Claude on it: it checks what really exists, then starts the next step."),
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
                mate(.wave, title: "Ask for anything",
                     text: Text("A fix, a feature, a job to do: write it in your words with ") + Text("+ Request").bold()
                        + Text(" (⌘N). Claude files it in the right place and asks you only what it can't guess."),
                     dots: "● ● ○") {
                    MateButton(title: "Skip", primary: false) { onb.skipAll() }
                    MateButton(title: "Try it ⌘N") { onb.go(.requestSheet); model.requestOpen = true }
                }
            }
            .padding(.top, 6).padding(.trailing, 30)
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .topTrailing)
    }

    private func mate<B: View>(_ pose: PixelMate.Pose, title: String, text: Text, dots: String, @ViewBuilder buttons: () -> B) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            PixelMate(pose: pose, size: S(84))
            MateBubble(title: title, text: text, dots: dots, width: 320) { buttons() }
        }
        .fixedSize()
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Below-left of the button it points at (the mate's hand towards it), kept inside the board.
    private func bubbleCenter(_ g: GeometryProxy, near rect: CGRect?) -> CGPoint {
        let w = S(84) + 8 + S(320), h = S(170)
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
            HStack(alignment: .top, spacing: 10) {
                PixelMate(pose: .think, size: S(56))
                VStack(alignment: .leading, spacing: 6) {
                    (Text("One line is enough. ").bold()
                     + Text("Steerify sorts it before Claude starts: a ") + Text("fix").bold() + Text(" or ") + Text("refinement").bold()
                     + Text(" lands in Fixes, a ") + Text("feature").bold() + Text(" becomes a draft chapter you approve, a ")
                     + Text("task").bold() + Text(" goes to Tasks, a ") + Text("question").bold() + Text(" comes back as a choice."))
                        .font(.system(size: S(12))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button { fill("Customers should get an email when their order ships") } label: {
                            Text("Use an example").font(.system(size: S(11), weight: .semibold)).foregroundStyle(Brand.amber)
                        }.buttonStyle(SteerButton())
                        Text("· Esc to close, nothing is sent").font(.system(size: S(11))).foregroundStyle(Brand.mute)
                    }
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
            HStack(alignment: .center, spacing: 12) {
                PixelMate(pose: kind == .choice ? .think : .point, size: S(64))
                MateBubble(title: kind == .choice ? "Your first choice" : "Your first test", text: text, dots: "first time only", width: 520) {
                    MateButton(title: "Got it") { withAnimation { onb.markSeen(kind.rawValue) } }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .transition(.opacity)
        }
    }
    private var text: Text {
        switch kind {
        case .choice:
            return Text("Claude stopped here because only you can decide. Look at the options (open them live), ")
                + Text("pick one").bold() + Text(", add a note to mix or change it. Claude then ")
                + Text("builds your pick").bold() + Text(" and puts it in ") + Text("To test").bold() + Text(".")
        case .test:
            return Text("Claude built this and tried it. Open each link and look at the picture, then: ")
                + Text("OK").bold() + Text(" ships it with the next release, ") + Text("Refine").bold()
                + Text(" sends your note back for a new version, ") + Text("Broken").bold() + Text(" says it doesn't work. Notes on pictures count too.")
        }
    }
}
