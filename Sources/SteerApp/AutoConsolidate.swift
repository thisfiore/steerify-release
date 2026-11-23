import SwiftUI

// MARK: - Roadmap auto-consolidate (chapter "Roadmap auto-consolidate: count down, then celebrate",
// choice autoconsolidate-done, option A, from request r261123-083203)
//
// Opening the Roadmap tab with outdated key results shows what the board detected (item · old → new) and counts down
// 10 s, then applies them by itself. Cancel stops it, and the same set never counts down again (a new detection
// does). When applied, a pixel boat sails past one buoy per key result (each turns green), with the list, Undo and
// Nice. Only sure proposals (linked deliveries); likely / commit / session ones stay in each chapter's panel.

struct AutoConsolidateBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var board: BoardStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Prefs.autoConsolidate, store: Prefs.store) private var autoOn = true

    private enum Phase: Equatable { case idle, counting, done }
    @State private var phase: Phase = .idle
    @State private var left = AutoConsolidateBar.seconds
    @State private var counted = ""                       // the signature being counted down
    @State private var applied: [RoadProposal] = []
    @State private var before: [(String, String)] = []
    @State private var doneLeft = 30
    static let seconds = 10

    /// Sure proposals over every chapter (not the filtered view: the countdown is about the whole roadmap).
    private var props: [RoadProposal] {
        let tracks = NSOrderedSet(array: board.roadmap.map(\.track)).array as? [String] ?? []
        return tracks.flatMap { board.consolidation(track: $0) }.filter(\.sure)
    }
    private static func signature(_ ps: [RoadProposal]) -> String { ps.map(\.id).sorted().joined(separator: "|") }
    private var cancelKey: String { "autocons.cancelled." + board.project.id }
    private var cancelled: String { Prefs.store.string(forKey: cancelKey) ?? "" }

    var body: some View {
        let ps = props, sig = Self.signature(ps)
        Group {
            switch phase {
            case .done: doneCard
            case .counting where !ps.isEmpty: countCard(ps)
            default:
                // Cancelled earlier: a quiet line with the old one-click button, no countdown.
                if !ps.isEmpty { quietLine(ps) }
            }
        }
        .padding(.horizontal, 12).padding(.top, 8)
        .onAppear { start(sig) }
        .onChange(of: phase) { _, ph in
            guard let b = Self.press else { return }
            if (b == "cancel" && ph == .counting) || (b == "undo" && ph == .done) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if b == "cancel" { cancel() } else { undo() } }
            }
        }
        .onChange(of: sig) { _, s in if phase != .done { start(s) } }
        .onChange(of: autoOn) { _, _ in if phase != .done { start(sig) } }
        .task(id: phase == .counting ? counted : "") {
            guard phase == .counting else { return }
            while left > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, phase == .counting else { return }
                left -= 1
            }
            apply(props)
        }
        .task(id: phase == .done) {
            guard phase == .done else { return }
            doneLeft = 30
            while doneLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, phase == .done else { return }
                doneLeft -= 1
            }
            phase = .idle
        }
    }

    private func start(_ sig: String) {
        guard !sig.isEmpty else { if phase == .counting { phase = .idle }; return }
        guard sig != cancelled, autoOn else { phase = .idle; return }   // Settings off: only the quiet line
        counted = sig; left = Self.seconds; phase = .counting
    }

    private func cancel() { Prefs.store.set(counted, forKey: cancelKey); phase = .idle }
    private func undo() {
        let back = before
        board.setRoad(back); phase = .idle
        // The same set is back: don't count it down again right away.
        Prefs.store.set(Self.signature(applied), forKey: cancelKey)
        model.showToast("\(back.count) key result\(back.count == 1 ? "" : "s") put back")
    }
    /// Test hook: `--autocons-press cancel|undo` presses that button 2 s after it shows.
    private static let press: String? = {
        let a = CommandLine.arguments
        return a.firstIndex(of: "--autocons-press").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil }
    }()

    private func apply(_ ps: [RoadProposal]) {
        guard !ps.isEmpty else { phase = .idle; return }
        before = board.setRoad(ps.map { ($0.item, $0.to) })
        applied = ps
        phase = .done
    }

    // MARK: countdown

    private func countCard(_ ps: [RoadProposal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PierCountdown(left: left, total: Self.seconds, buoys: ps.count, still: reduceMotion)
                .frame(maxWidth: .infinity).frame(height: S(78))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 12) {
                CountRing(left: left, total: Self.seconds, still: reduceMotion)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bringing \(ps.count) key result\(ps.count == 1 ? "" : "s") up to date")
                        .font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(Brand.cream)
                    Text("From approved / sent-back deliveries on To test")
                        .font(.system(size: S(11))).foregroundStyle(Brand.mute)
                }
                Spacer()
                Button("Cancel") { cancel() }
                .buttonStyle(SteerButton()).font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.cream)
                .keyboardShortcut(.cancelAction)
                ActionButton(title: "Now", icon: "test", primary: true) { apply(ps) }
            }
            ForEach(ps.prefix(5)) { p in ProposalRow(p: p, showFrom: true) }
            if ps.count > 5 { Text("+ \(ps.count - 5) more").font(.system(size: S(11))).foregroundStyle(Brand.mute) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.amber.opacity(0.45)))
    }

    private func quietLine(_ ps: [RoadProposal]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist").foregroundStyle(Brand.amber)
            Text("\(ps.count) key result\(ps.count == 1 ? "" : "s") look outdated: their deliveries were already approved or sent back.")
                .font(.system(size: S(12))).foregroundStyle(Brand.ink)
            Spacer()
            ActionButton(title: "Consolidate all", icon: "test", primary: true) { apply(ps) }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Brand.amberDim.opacity(0.7)))
    }

    // MARK: done

    private var doneCard: some View {
        VStack(spacing: 10) {
            BuoyVoyage(buoys: applied.count, still: reduceMotion)
                .frame(maxWidth: S(760)).aspectRatio(96.0 / 30.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("\(applied.count) key result\(applied.count == 1 ? "" : "s") moved forward")
                .font(.system(size: S(19), weight: .heavy)).foregroundStyle(Brand.cream)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(applied.prefix(8)) { p in ProposalRow(p: p, showFrom: false) }
                if applied.count > 8 { Text("+ \(applied.count - 8) more").font(.system(size: S(11))).foregroundStyle(Brand.mute) }
            }
            .frame(maxWidth: S(620), alignment: .leading)
            HStack(spacing: 12) {
                Button("Undo") { undo() }
                .buttonStyle(SteerButton()).font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.cream)
                ActionButton(title: "Nice", icon: "test", primary: true) { phase = .idle }
            }
            Text("Closes by itself in \(doneLeft) s").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.green.opacity(0.4)))
    }
}

/// One proposal: [old →] new · the key result · its evidence.
private struct ProposalRow: View {
    let p: RoadProposal; let showFrom: Bool
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if showFrom {
                StatusChip(status: p.from)
                Image(systemName: "arrow.right").font(.system(size: S(8.5), weight: .bold)).foregroundStyle(Brand.mute)
            }
            StatusChip(status: p.to)
            Text(p.item).font(.system(size: S(12.5))).foregroundStyle(Brand.ink).lineLimit(1).truncationMode(.tail)
            Text(p.evidence).font(.system(size: S(10.5))).foregroundStyle(Brand.mute).lineLimit(1).truncationMode(.tail)
                .layoutPriority(-1)
        }
    }
}

private struct StatusChip: View {
    let status: String
    private var color: Color { ["done": Brand.green, "review": Brand.blue, "wip": Brand.amber, "you": Brand.amber][status] ?? Brand.mute }
    private var label: String { ["done": "done", "review": "review", "wip": "wip", "you": "you", "todo": "todo"][status] ?? status }
    var body: some View {
        Text(label).font(.system(size: S(10.5), weight: .bold, design: .monospaced)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.16)))
            .fixedSize()
    }
}

/// The 10-second ring: drains smoothly once a second (Reduce Motion: just the number).
private struct CountRing: View {
    let left: Int, total: Int, still: Bool
    var body: some View {
        ZStack {
            Circle().stroke(Brand.line2, lineWidth: 4)
            if !still {
                Circle().trim(from: 0, to: CGFloat(left) / CGFloat(max(total, 1)))
                    .stroke(Brand.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
            }
            Text("\(left)").font(.system(size: S(17), weight: .heavy, design: .monospaced)).foregroundStyle(Brand.cream)
        }
        .frame(width: S(46), height: S(46))
        .accessibilityLabel("Applies in \(left) seconds")
    }
}

/// Night harbour, 96 × 30 pixels: a boat sails left to right past one buoy per key result, each turns green as it
/// passes; then the boat waits at the right with a green flag. The animation stops after ~10 s (a still frame), and
/// pauses while the window is in the background or with Reduce Motion.
struct BuoyVoyage: View {
    let buoys: Int
    var still = false
    @Environment(\.controlActiveState) private var active
    @State private var started = Date()
    @State private var settled = false
    static let sail: Double = 4.5          // seconds from left to right

    var body: some View {
        let frozen = still || settled || active == .inactive
        TimelineView(.animation(minimumInterval: 0.12, paused: frozen)) { tl in
            let t = (still || settled) ? 99 : tl.date.timeIntervalSince(started)
            Canvas { ctx, size in Self.draw(ctx, size, t, buoys) }
        }
        .accessibilityHidden(true)
        .task {
            started = Date()
            try? await Task.sleep(for: .seconds(10))
            settled = true
        }
    }

    static func draw(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, _ n: Int) {
        let cols = 96, rows = 30
        let px = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
        let ox = (size.width - px * CGFloat(cols)) / 2, oy = (size.height - px * CGFloat(rows)) / 2
        func dot(_ x: Int, _ y: Int, _ c: Color, _ a: Double = 1) {
            guard x >= 0, x < cols, y >= 0, y < rows else { return }
            ctx.fill(Path(CGRect(x: ox + CGFloat(x) * px, y: oy + CGFloat(y) * px, width: px + 0.3, height: px + 0.3)), with: .color(c.opacity(a)))
        }
        ctx.fill(Path(CGRect(x: ox, y: oy, width: px * CGFloat(cols), height: px * CGFloat(rows))), with: .color(Color(hex: 0x141a26)))
        let tick = Int(t / 0.45)
        // stars + moon
        for (i, (x, y)) in [(5, 3), (14, 7), (27, 2), (41, 5), (55, 3), (63, 8), (9, 11), (35, 9), (74, 4), (88, 10)].enumerated() {
            dot(x, y, Brand.cream, (i + tick) % 3 == 0 ? 1 : 0.4)
        }
        for y in 0..<5 { for x in 0..<5 where (x - 2) * (x - 2) + (y - 2) * (y - 2) <= 5 { dot(84 + x, 2 + y, Brand.cream, 0.85) } }
        // sea
        let sea = 22
        for r in 0..<3 {
            for x in 0..<cols where (x + tick * (r + 1) + r * 3) % 7 < 4 {
                dot(x, sea + r * 3, r == 0 ? Color(hex: 0x3d6ea5) : Color(hex: 0x26364d))
            }
        }
        // the boat: from off-screen left to the right edge in `sail` seconds, then it stays
        let p = min(1, t / sail)
        let ease = 1 - pow(1 - p, 2)
        let bx = Int((-14 + ease * Double(cols - 16 + 14)).rounded())
        // buoys: spread between x 14 and cols - 22, one per key result (at most 10 drawn)
        let shown = min(max(n, 1), 10)
        for i in 0..<shown {
            let x = shown == 1 ? cols / 2 : 14 + i * (cols - 36) / (shown - 1)
            let lit = bx + 6 >= x
            let bob = (tick + i) % 2
            let c = lit ? Brand.green : Brand.amber
            dot(x, sea - 3 + bob, c); dot(x, sea - 2 + bob, Brand.cream); dot(x - 1, sea - 1 + bob, c); dot(x, sea - 1 + bob, c); dot(x + 1, sea - 1 + bob, c)
            if lit && (tick + i) % 2 == 0 { dot(x, sea - 5 + bob, Brand.green, 0.6) }          // a blink above a lit buoy
        }
        // hull, mast, sail (Claude orange), flag (green once the voyage is done)
        let by = sea - 2 + (p >= 1 ? tick % 2 : 0)
        for x in 0..<12 { dot(bx + x, by + 1, Color(hex: 0x8a5a2b)) }
        for x in 1..<11 { dot(bx + x, by + 2, Color(hex: 0x5c3b1c)) }
        for y in 0..<9 { dot(bx + 5, by - 8 + y, Color(hex: 0x6b4a2a)) }
        for y in 0..<7 { for x in 0...Int(Double(y) / 1.6) { dot(bx + 6 + x, by - 7 + y, Color(hex: 0xd97757)) } }
        let flag = p >= 1 ? Brand.green : Brand.amber
        dot(bx + 4, by - 9, flag); dot(bx + 3, by - 9, flag); dot(bx + 4, by - 8, flag)
        // a wake behind the boat while it sails
        if p < 1 { for k in 1...4 where (k + tick) % 2 == 0 { dot(bx - k * 2, by + 2, Brand.cream, 0.35) } }
    }
}
