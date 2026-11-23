import SwiftUI

// MARK: - One release model: ship by product, everywhere (choice ship-by-product, pick A, from request r261123-171620)
//
// The unit of a release is a product with all its approved, not-live items. Every ship button in the app (a To test
// card after OK, the preview, a session's "Ship" pill, Ready, the Release tab) opens the same sheet for the item's
// product: its ready items ticked (this one highlighted), untick = waits for the next release, a release note. The
// sheet's Ship starts the one engine below: the same run, modal, shipping state and hand-off of feature sessions.

/// The sheet to show: which product, and the item it was opened from (highlighted).
struct ShipAsk: Equatable {
    let projectId: String
    let productId: String
    var highlight: String? = nil
}

extension AppModel {
    /// The project's products (steerify.json → products, else one per area). Memoised for the current turn.
    func products(_ p: Project) -> [ReleaseProduct] {
        TurnMemo.get("products:" + p.id) { ReleaseProduct.load(p, board: board(for: p)) }
    }

    /// The one product an item belongs to (match words first, then areas); nil = no product owns it.
    func product(of s: ShipItem, in p: Project) -> ReleaseProduct? {
        let all = products(p)
        return all.first { $0.owns(s, among: all) }
    }

    /// Approved, not live, owned by this product: what its next release takes (oldest OK first, like Ready).
    func readyItems(_ pr: ReleaseProduct, in p: Project) -> [ShipItem] {
        let all = products(p)
        return releasable(p.id).filter { pr.owns($0, among: all) }
    }

    /// Ship button label for one item: "Ship Mac app · 3" (nil = no product owns it: the old single-item release).
    func shipLabel(_ s: ShipItem, in p: Project) -> (product: ReleaseProduct, title: String, count: Int)? {
        guard let pr = product(of: s, in: p) else { return nil }
        let n = max(readyItems(pr, in: p).count, 1)
        return (pr, "Ship \(pr.name) · \(n)", n)
    }

    /// Open the ship sheet for a product (from anywhere in the app).
    func askShip(projectId: String, product: String, highlight: String? = nil) {
        if let r = ShipRuns.shared.active[projectId + "/" + product], r.phase == .shipping { ShipRuns.shared.shown = r.key; return }
        ShipRuns.shared.ask = ShipAsk(projectId: projectId, productId: product, highlight: highlight)
    }

    /// Open the ship sheet for the product of an item; false = no product owns it (the caller falls back).
    @discardableResult
    func askShip(item s: ShipItem, in p: Project) -> Bool {
        guard let pr = product(of: s, in: p) else { return false }
        askShip(projectId: p.id, product: pr.id, highlight: s.id)
        return true
    }

    /// THE ship engine. Every ship button ends here. Runs the product's release script when it has one and nothing
    /// needs Claude (no notes to apply, no release note); otherwise one Claude session ships just this product.
    func shipProduct(_ pr: ReleaseProduct, in p: Project, from: ProductState, items: [ShipItem], skipped: [ShipItem], note: String) {
        let runs = ShipRuns.shared
        let key = p.id + "/" + pr.id
        if runs.active[key]?.phase == .shipping { runs.shown = key; return }
        var run = ShipRun(key: key, projectId: p.id, product: pr, from: from, items: items.map(\.title))
        run.itemIds = items.map(\.id)        // their feature sessions hand off while it ships (ship-feature-session-end)
        runs.start(run)
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = items.compactMap { notesHint("test:" + $0.id, in: p) }
        if let cmd = pr.deploy, notes.isEmpty, note.isEmpty, let repo = pr.repo.flatMap({ p.resolveRepo($0) }) ?? p.repos.first {
            runs.runDeploy(cmd, repo: repo, in: p, model: self, key: key)
        } else {
            var x = ItemRef(ref: "release:" + p.id)!; x.title = "Release: " + pr.name
            var brief = "Ship only the product \(pr.name) (steerify.json → products → \(pr.id)) with these approved items, as one release:\n"
                + (items.isEmpty ? "- none approved, just its unreleased commits\n" : items.map { "- test:\($0.id) — \($0.title)" }.joined(separator: "\n") + "\n")
            if !skipped.isEmpty {
                brief += "\nLeave these out (they stay approved and wait for its next release):\n"
                    + skipped.map { "- test:\($0.id) — \($0.title)" }.joined(separator: "\n") + "\n"
            }
            if !notes.isEmpty { brief += "\nNotes to apply before shipping:\n" + notes.map { "- " + $0 }.joined(separator: "\n") + "\n" }
            if let how = pr.how { brief += "\nHow it ships: " + how }
            if let cmd = pr.deploy { brief += "\nIts release command: `\(cmd)` (run it once the items are ready)." }
            if !note.isEmpty { brief += "\n\nThe user's release note (follow it: version, what to include or hide, who gets it):\n" + note }
            brief += "\n\nLeave the other products alone. Re-deliver each shipped item with status live, keepVerdict true."
            start(projectId: p.id, item: x, intent: .ship, extraBrief: brief, also: items.map { "test:" + $0.id })
        }
        let refs = Set(items.map { "test:" + $0.id })
        nudges.filter { $0.projectId == p.id && refs.contains($0.ref) }.forEach(markHandled)
    }

    /// A run's product shows a new version: mark its items live and their key results done (from any tab).
    func landShips(_ p: Project, states: [String: ProductState]) {
        let landed = ShipRuns.shared.check(project: p.id, states: states).flatMap(\.itemIds)
        guard !landed.isEmpty, AppModel.mayWriteBoards else { return }
        let items = board(for: p).ships.filter { landed.contains($0.id) && $0.status != "live" }
        if !items.isEmpty { setLive(items, in: p, live: true); _ = markRoadsDone(of: items, in: p) }
    }
}

/// Over the board, whatever the tab: the ship sheet and the shipping modal. While a product ships, its version is
/// read here too, so it lands even when the Release tab is not open.
struct ShipHost: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var runs = ShipRuns.shared
    let projectId: String

    var body: some View {
        ZStack {
            if let a = runs.ask, a.projectId == projectId, let p = model.projects.first(where: { $0.id == projectId }),
               let pr = model.products(p).first(where: { $0.id == a.productId }) {
                ShipSheet(project: p, product: pr, highlight: a.highlight).id(a.productId)
            }
            ShipModal(projectId: projectId)
        }
        // Test hook (test copies only): `--ask-ship <product id> [test id]` opens the ship sheet 2 s in.
        .onAppear {
            let a = CommandLine.arguments
            guard a.contains("--background"), let i = a.firstIndex(of: "--ask-ship"), i + 1 < a.count else { return }
            let hl = i + 2 < a.count && !a[i + 2].hasPrefix("--") ? a[i + 2] : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.askShip(projectId: projectId, product: a[i + 1], highlight: hl) }
        }
        .task(id: "\(projectId)·\(runs.tick)") {
            guard let p = model.projects.first(where: { $0.id == projectId }) else { return }
            let all = model.products(p).filter { runs.active[p.id + "/" + $0.id]?.phase == .shipping }
            guard !all.isEmpty else { return }
            let out = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: all.map { ($0.id, ProductState.read($0, in: p)) })
            }.value
            model.landShips(p, states: out)
        }
    }
}

/// "Ship Mac app": the product's ready items (ticked = goes in, the one you came from highlighted), its unreleased
/// commits, a release note, Ship. The same sheet from every ship button.
struct ShipSheet: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var runs = ShipRuns.shared
    let project: Project
    let product: ReleaseProduct
    let highlight: String?
    @State private var state: ProductState?
    @State private var note = ""

    private var noteKey: String { "releaseNote." + project.id + "." + product.id }
    private func close() { runs.ask = nil }

    var body: some View {
        let items = model.readyItems(product, in: project)
        let skip = model.releaseSkipped(project.id)
        let shipping = model.shippingIds(project.id)
        let picked = items.filter { !skip.contains($0.id) && !shipping.contains($0.id) }
        let left = items.filter { skip.contains($0.id) && !shipping.contains($0.id) }
        let commits = state?.unreleased ?? 0
        let canShip = state != nil && (!picked.isEmpty || commits > 0)
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ProductArt(icon: product.icon).frame(width: S(44), height: S(44))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ship \(product.name)").font(.system(size: S(17), weight: .heavy)).foregroundStyle(.white)
                        Text(state.map { "from \($0.version)" + ($0.date.map { " · " + ReleaseProducts.day($0) } ?? "") } ?? "reading its version…")
                            .font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.mute)
                    }
                    Spacer(minLength: 0)
                }
                Text(tip(picked: picked.count, of: items.count)).font(.system(size: S(11.5))).foregroundStyle(Brand.cream)
                    .fixedSize(horizontal: false, vertical: true)
                if items.isEmpty {
                    Text("No approved items waiting").italic().font(.system(size: S(12))).foregroundStyle(Brand.mute)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { s in row(s, on: !skip.contains(s.id), shipping: shipping.contains(s.id)) }
                }
                if commits > 0 || (state?.dirty ?? 0) > 0 {
                    Text([commits > 0 ? "+ \(commits) commit\(commits == 1 ? "" : "s") since \(state?.version ?? "")" : nil,
                          (state?.dirty ?? 0) > 0 ? "\(state!.dirty) uncommitted" : nil].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.mute)
                }
                Text("RELEASE NOTE · OPTIONAL").font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.mute).padding(.top, 2)
                TextField("For Claude: major or minor? Leave something out? Hide a half-done feature behind a flag? Only for some users?",
                          text: $note, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: S(12))).foregroundStyle(Brand.ink).lineLimit(2...5)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Brand.bg.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Brand.line))
                    .onChange(of: note) { _, v in Prefs.store.set(v, forKey: noteKey) }
                HStack(spacing: 10) {
                    Button("Cancel", action: close).buttonStyle(.plain).keyboardShortcut(.cancelAction)
                        .font(.system(size: S(12))).foregroundStyle(Brand.mute)
                    Spacer()
                    PixelCTA(title: picked.isEmpty ? "Ship \(product.name)" : "Ship \(picked.count)",
                             subtitle: picked.isEmpty ? "its commits" : picked.count == items.count ? "all ready · one release" : "\(left.count) wait",
                             color: Brand.green, icon: "rocket") {
                        guard let st = state else { return }
                        model.shipProduct(product, in: project, from: st, items: picked, skipped: left, note: note)
                        note = ""; Prefs.store.removeObject(forKey: noteKey)
                        close()
                    }
                    .disabled(!canShip).opacity(canShip ? 1 : 0.4)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: S(470))
            .background(RoundedRectangle(cornerRadius: 14).fill(Brand.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.green.opacity(0.6)))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        }
        .task(id: product.id) {
            if note.isEmpty { note = Prefs.store.string(forKey: noteKey) ?? "" }
            let pr = product, p = project
            state = await Task.detached(priority: .userInitiated) { ProductState.read(pr, in: p) }.value
        }
    }

    private func tip(picked: Int, of n: Int) -> String {
        let flow = WorkFlow.of(project)
        let how = product.deploy != nil ? "Runs its release script" : "A Claude session ships it"
        switch flow {
        case .main: return "\(how). On main the ticked items are already together; an unticked one stays approved for the next release."
        case .worktree: return "\(how), merging the ticked branches oldest first. Unticked ones wait."
        case .pr: return "\(how), merging the ticked pull requests oldest first. Unticked ones wait."
        }
    }

    private func row(_ s: ShipItem, on: Bool, shipping: Bool) -> some View {
        let me = s.id == highlight
        let at = model.board(for: project).verdict("ship:" + s.id).at.flatMap { AppModel.iso.date(from: $0) }
        return HStack(spacing: 9) {
            if shipping {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: S(13), height: S(13))
            } else {
                Button {
                    var skip = model.releaseSkipped(project.id)
                    if on { skip.insert(s.id) } else { skip.remove(s.id) }
                    model.setReleaseSkipped(project.id, skip)
                } label: {
                    Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: S(13)))
                        .foregroundStyle(on ? Brand.green : Brand.mute)
                }
                .buttonStyle(SteerButton()).help(on ? "Leave it for a later release" : "Put it in this release")
            }
            Text(s.title).font(.system(size: S(12.5), weight: me ? .semibold : .medium)).foregroundStyle(on ? Brand.ink : Brand.mute).lineLimit(1)
            if me { Text("· this one").font(.system(size: S(10.5))).foregroundStyle(Brand.green) }
            if shipping { Text("shipping…").font(.system(size: S(10.5))).foregroundStyle(Brand.blue) }
            else if !on { Text("waits").font(.system(size: S(10.5))).foregroundStyle(Brand.amber) }
            Spacer(minLength: 6)
            if let at { Text("OK " + at.formatted(.dateTime.day().month(.abbreviated))).font(.system(size: S(10.5))).foregroundStyle(Brand.mute) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(me ? Brand.green.opacity(0.14) : .clear))
    }
}

/// The product an item ships with, as a small chip next to its ship button.
struct ProductChip: View {
    let product: ReleaseProduct
    var body: some View {
        HStack(spacing: 5) {
            ProductArt(icon: product.icon).frame(width: S(13), height: S(13))
            Text(product.name).font(.system(size: S(10.5), weight: .semibold, design: .monospaced)).lineLimit(1)
        }
        .foregroundStyle(Brand.cream).padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(Brand.panel2)).overlay(Capsule().stroke(Brand.line2))
        .help("Ships with \(product.name)")
    }
}

/// READY TO RELEASE, one section per product, from the same data as the Release tab's cards (readyItems, the
/// shared skip list): same items, same counts. Ship opens the product's ship sheet. Items no product owns keep
/// the old card, as "Other".
struct ReadyByProduct: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    let items: [ShipItem]

    var body: some View {
        let all = model.products(project)
        let groups = all.map { pr in (pr, items.filter { pr.owns($0, among: all) }) }.filter { !$0.1.isEmpty }
        let other = items.filter { s in !all.contains { $0.owns(s, among: all) } }
        let skip = model.releaseSkipped(project.id)
        let shipping = model.shippingIds(project.id)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups, id: \.0.id) { pr, rd in
                let picked = rd.filter { !skip.contains($0.id) && !shipping.contains($0.id) }
                let busy = rd.allSatisfy { shipping.contains($0.id) }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 12) {
                        ProductArt(icon: pr.icon).frame(width: S(34), height: S(34))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.name).font(.system(size: S(15), weight: .bold)).foregroundStyle(.white)
                            Text("\(rd.count) approved · " + (pr.deploy != nil ? "release script" : "Claude ships it"))
                                .font(.system(size: S(10.5), design: .monospaced)).foregroundStyle(Brand.mute)
                        }
                        Spacer(minLength: 8)
                        PixelCTA(title: busy ? "Shipping…" : picked.count == rd.count ? "Ship \(pr.name)" : "Ship \(picked.count) of \(rd.count)",
                                 subtitle: busy ? "a release is on it" : "\(picked.count) ready · one release",
                                 color: Brand.green, icon: "rocket") { model.askShip(projectId: project.id, product: pr.id) }
                            .help("Opens the ship sheet for \(pr.name): tick what goes in, add a release note")
                    }
                    ForEach(rd) { s in
                        let on = !skip.contains(s.id), sh = shipping.contains(s.id)
                        HStack(spacing: 8) {
                            Text(sh ? "◌" : on ? "▸" : "·").foregroundStyle(sh ? Brand.blue : on ? Brand.green : Brand.mute)
                            Text(s.title).font(.system(size: S(12.5), weight: .medium)).foregroundStyle(on ? Brand.ink : Brand.mute).lineLimit(1)
                                .contentShape(Rectangle())
                                .onTapGesture { model.openCombo(projectId: project.id, ref: "test:" + s.id, startNew: false) }
                            if sh { Text("shipping…").font(.system(size: S(10.5))).foregroundStyle(Brand.blue) }
                            else if !on { Text("waits").font(.system(size: S(10.5))).foregroundStyle(Brand.amber) }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Brand.green.opacity(0.12), Brand.panel], startPoint: .leading, endPoint: .trailing)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.green.opacity(0.45)))
            }
            if !other.isEmpty {
                Text("OTHER · NO PRODUCT").font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute)
                ReleaseReadyCard(project: project, items: other)
            }
        }
    }
}
