import SwiftUI

// MARK: - Answers to the people who file (request r261124-074236: "a way to answer people's questions, email + relay")
//
// A request from the project's own users (feedback form, widget, an agent through report_issue) can get a reply:
//   Claude drafts it (update_request → answer), or you write it (Answer on the request's row);
//   you edit and Send it here (or Send when live: it waits in "answerWhenLive" until every To test item the request
//   became is live, i.e. the release checked it and re-delivered it live; then Steerify sends it by itself), → requests.json "answer" {text, at, by} → the next snapshot carries it to the relay
//   (FeedbackInbox.swift), which emails it once to the person (if they left an email) and shows it on their follow
//   page; agents read it as JSON (issue_status / status_url). Nothing leaves the Mac before you press Send.

extension BoardRequest {
    /// Filed by the project's users through the feedback inbox: someone to answer.
    var answerable: Bool { fromFeedback && reporter != nil }
    var fromAgent: Bool { contextTitle?.hasPrefix("Feedback form · agent") == true }
    /// Where the answer goes, in a few words.
    var answerRoute: String {
        if let e = email { return "emailed to \(e) · on their follow page" }
        return fromAgent ? "on the agent's status link (issue_status)" : "on their follow page (no email given)"
    }
}

@MainActor
extension AppModel {
    func answersWaiting(_ p: Project) -> [BoardRequest] {
        RequestLog.cached(p.boardDir).filter { $0.answerable && ($0.answerDraft != nil || $0.answerWhenLive != nil) }
    }

    /// What a reply set to Send when live waits for: the To test items the request became (test:, road:, choice:),
    /// and the ones not live yet (a key result with no delivery yet counts as not live).
    func liveWait(_ r: BoardRequest, in p: Project) -> (linkable: Bool, linked: [ShipItem], pending: [String]) {
        let b = board(for: p)
        func ids(_ k: String) -> Set<String> { Set(r.became.filter { $0.hasPrefix(k + ":") }.map { String($0.dropFirst(k.count + 1)) }) }
        let tests = ids("test"), roads = ids("road"), choices = ids("choice")
        let roadTexts = Set(b.roadmap.filter { roads.contains($0.id) }.map(\.text))
        func onRoad(_ s: ShipItem, _ slug: String) -> Bool {
            s.roads.contains { BoardFiles.slug($0) == slug || roadTexts.contains($0) && BoardFiles.slug($0) == slug }
        }
        let linked = b.ships.filter { s in
            tests.contains(s.id) || roads.contains { onRoad(s, $0) } || !choices.isDisjoint(with: s.choices)
        }
        var pending = linked.filter { $0.status != "live" }.map(\.title)
        for slug in roads where !linked.contains(where: { onRoad($0, slug) }) {
            pending.append((b.roadmap.first { $0.id == slug }?.text ?? slug) + " (not delivered yet)")
        }
        return (!(tests.isEmpty && roads.isEmpty && choices.isEmpty), linked, pending)
    }

    /// Send when live: you approve the text now; it goes out by itself once every linked item is live.
    func sendWhenLive(_ r: BoardRequest, text: String, in p: Project) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        _ = RequestLog.edit(p.boardDir, id: r.id) { x in
            x["answerWhenLive"] = ["text": t, "at": RequestLog.now(), "by": "you"]
            x.removeValue(forKey: "answerDraft")
            x["updated"] = RequestLog.now()
        }
        objectWillChange.send()
        let w = liveWait(r, in: p)
        if !w.linked.isEmpty && w.pending.isEmpty { sendAnswersNowLive() }
        else { showToast("Goes out by itself when " + Self.waitWords(w.pending) + " is live", projectId: p.id) }
    }

    /// Back to a draft: nothing is sent.
    func cancelWhenLive(_ r: BoardRequest, in p: Project) {
        _ = RequestLog.edit(p.boardDir, id: r.id) { x in
            if let w = x["answerWhenLive"] as? [String: Any] { x["answerDraft"] = ["text": w["text"] ?? "", "at": RequestLog.now(), "by": "you"] }
            x.removeValue(forKey: "answerWhenLive")
        }
        objectWillChange.send()
    }

    nonisolated static func waitWords(_ pending: [String]) -> String {
        guard let f = pending.first else { return "the fix" }
        let one = "“" + (f.count > 48 ? String(f.prefix(46)) + "…" : f) + "”"
        return pending.count > 1 ? one + " +\(pending.count - 1)" : one
    }

    /// The live check: runs on every board reload (a release re-delivering items live writes delivered.json) and at
    /// launch. A waiting reply goes out only when it has linked items and all of them are live.
    func sendAnswersNowLive() {
        guard AppModel.mayWriteBoards else { return }
        for p in projects {
            for r in RequestLog.load(p.boardDir) where r.answerWhenLive != nil && r.answerable {
                let w = liveWait(r, in: p)
                guard !w.linked.isEmpty, w.pending.isEmpty, let t = r.answerWhenLive else { continue }
                sendAnswer(r, text: t, in: p, because: "“" + (w.linked.first?.title ?? "the fix") + "” is live")
            }
        }
    }

    func startAnswersLiveCheck() {
        NotificationCenter.default.addObserver(forName: .steerifyBoardReloaded, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendAnswersNowLive() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.sendAnswersNowLive() }
    }

    /// Send: the answer is kept on the request, the draft goes, and the relay gets it now (it mails it once).
    func sendAnswer(_ r: BoardRequest, text: String, in p: Project, because: String? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        _ = RequestLog.edit(p.boardDir, id: r.id) { x in
            x["answer"] = ["text": t, "at": RequestLog.now(), "by": "you"]
            x.removeValue(forKey: "answerDraft")
            x.removeValue(forKey: "answerWhenLive")
            x["updated"] = RequestLog.now()
        }
        objectWillChange.send()
        syncFeedbackInbox(force: true)
        showToast(FeedbackInbox.config(p) == nil ? "Answer saved: this project has no feedback inbox to send it through"
                                                 : (because.map { $0 + ": " } ?? "") + "Answer sent to \(r.reporter ?? "them") · \(r.answerRoute)",
                  projectId: p.id, ref: "request:" + r.id)
    }

    /// Keep or start a draft (your own words, before sending).
    func saveAnswerDraft(_ r: BoardRequest, text: String?, in p: Project) {
        _ = RequestLog.edit(p.boardDir, id: r.id) { x in
            if let text { x["answerDraft"] = ["text": text, "at": RequestLog.now(), "by": "you"] } else { x.removeValue(forKey: "answerDraft") }
        }
        objectWillChange.send()
    }
}

/// One reply being written: who it goes to, what they asked, the text, Send.
struct AnswerComposer: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    let r: BoardRequest
    var onDone: () -> Void = {}
    @State private var text: String
    @State private var showQuestion = false

    init(project: Project, r: BoardRequest, onDone: @escaping () -> Void = {}) {
        self.project = project; self.r = r; self.onDone = onDone
        _text = State(initialValue: r.answerWhenLive ?? r.answerDraft ?? r.answer ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: r.fromAgent ? "cpu" : "person.crop.circle").font(.system(size: S(11))).foregroundStyle(Color(hex: 0xc4a7ff))
                Text((r.fromAgent ? "Agent " : "") + (r.reporter ?? "Someone")).font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.cream)
                Text(r.kind.label.uppercased()).font(Brand.label(8)).foregroundStyle(r.kind.color)
                Spacer()
                Text(r.answerRoute).font(.system(size: S(10.5))).foregroundStyle(Brand.mute).lineLimit(1)
            }
            Button { showQuestion.toggle() } label: {
                Text("“" + (showQuestion ? r.text : r.short) + "”").font(.system(size: S(11.5))).italic().foregroundStyle(Brand.ink.opacity(0.85))
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(showQuestion ? nil : 2)
            }.buttonStyle(.plain).help(showQuestion ? "Fold" : "Their whole message")
            TextEditor(text: $text)
                .font(.system(size: S(12.5))).scrollContentBackground(.hidden)
                .padding(6).frame(minHeight: S(70), maxHeight: S(160))
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.bg))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.line2))
            let wait = model.liveWait(r, in: project)
            HStack(spacing: 8) {
                if r.answerWhenLive != nil {
                    Label("Goes out by itself when " + AppModel.waitWords(wait.pending) + " is live", systemImage: "clock.badge.checkmark")
                        .font(.system(size: S(10.5), weight: .semibold)).foregroundStyle(Color(hex: 0xc4a7ff)).lineLimit(1)
                        .help(wait.pending.isEmpty ? "Everything is live: it goes out now" : "Waiting for:\n" + wait.pending.joined(separator: "\n"))
                } else if r.answerDraft != nil && r.answer == nil {
                    Text("Drafted by Claude: check it, then send").font(.system(size: S(10.5))).foregroundStyle(Brand.claude)
                } else if let at = r.answerAt {
                    Text("Sent \(SessionChip.ago(at)): sending again replaces it and mails it again").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                }
                Spacer()
                let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if r.answerWhenLive != nil {
                    Button("Cancel") { model.cancelWhenLive(r, in: project) }
                        .buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                        .help("Stop waiting: back to a draft, nothing is sent")
                    ActionButton(title: "Send now", icon: "paperplane") { model.sendAnswer(r, text: text, in: project); onDone() }
                        .disabled(empty)
                } else {
                    Button("Not now") {
                        model.saveAnswerDraft(r, text: nil, in: project); onDone()
                    }.buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                        .help("Drop the draft: nothing is sent (Answer on the request's row writes one again)")
                    if wait.linkable && r.answer == nil {
                        ActionButton(title: "Send now", icon: "paperplane") { model.sendAnswer(r, text: text, in: project); onDone() }
                            .disabled(empty)
                        ActionButton(title: "Send when live", icon: "clock.badge.checkmark", primary: true) {
                            model.sendWhenLive(r, text: text, in: project); onDone()
                        }
                        .disabled(empty)
                        .help("You approve it now; Steerify sends it by itself once " + AppModel.waitWords(wait.pending.isEmpty ? wait.linked.map(\.title) : wait.pending) + " is live")
                    } else {
                        ActionButton(title: "Send", icon: "paperplane", primary: true) {
                            model.sendAnswer(r, text: text, in: project); onDone()
                        }
                        .disabled(empty)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.panel2))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.line))
    }
}

/// READY tab: replies waiting for your OK before they go out.
struct AnswersWaiting: View {
    @EnvironmentObject var model: AppModel
    let project: Project

    var body: some View {
        let waiting = model.answersWaiting(project)
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("ANSWERS TO SEND").font(Brand.label(10)).tracking(0.9).foregroundStyle(Color(hex: 0xc4a7ff))
                    Text("to the people who asked · nothing goes out before Send, or before the fix is live").font(.system(size: S(11))).foregroundStyle(Brand.mute)
                }
                ForEach(waiting) { AnswerComposer(project: project, r: $0).id($0.id + ($0.answerDraft ?? "")) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xc4a7ff).opacity(0.35)))
            .padding(.bottom, 8)
        }
    }
}

/// On a request's row: answered ✓, or Answer (opens the composer).
struct AnswerBadge: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    let r: BoardRequest
    @State private var open = false

    var body: some View {
        if r.answerable {
            Button { open = true } label: {
                if r.answerWhenLive != nil {
                    Label("Waits for live", systemImage: "clock.badge.checkmark").font(.system(size: S(10.5), weight: .semibold)).foregroundStyle(Color(hex: 0xc4a7ff))
                } else if r.answer != nil {
                    Label("Answered", systemImage: "checkmark.bubble").font(.system(size: S(10.5), weight: .semibold)).foregroundStyle(Brand.green)
                } else if r.answerDraft != nil {
                    Label("Answer ready", systemImage: "bubble.left").font(.system(size: S(10.5), weight: .semibold)).foregroundStyle(Brand.claude)
                } else {
                    Label("Answer", systemImage: "bubble.left").font(.system(size: S(10.5))).foregroundStyle(Color(hex: 0xc4a7ff))
                }
            }
            .buttonStyle(SteerButton())
            .help(r.answer.map { "Your answer: " + $0 } ?? "Write to \(r.reporter ?? "them"): \(r.answerRoute)")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                AnswerComposer(project: project, r: r) { open = false }.environmentObject(model).frame(width: S(460)).padding(8)
            }
        }
    }
}

extension AppModel {
    /// Test hook: `--background --answer-send <request id>` (a test copy with STEERIFY_WORKSPACES + --scratch-writes):
    /// press Send on that request's draft in the first project, let the snapshot reach the relay, then quit.
    func answerSendTestHook() {
        let a = CommandLine.arguments
        answerWhenLiveTestHook()
        answersShotTestHook()
        guard a.contains("--background"), let i = a.firstIndex(of: "--answer-send"), i + 1 < a.count, let p = projects.first else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let r = RequestLog.load(p.boardDir).first(where: { $0.id == a[i + 1] }), let d = r.answerDraft else {
                FileHandle.standardError.write("[answer] no draft\n".data(using: .utf8)!); exit(1)
            }
            self.sendAnswer(r, text: d, in: p)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                let sent = RequestLog.load(p.boardDir).first { $0.id == r.id }
                FileHandle.standardError.write("[answer] sent=\(sent?.answer ?? "nil") draft=\(sent?.answerDraft ?? "nil")\n".data(using: .utf8)!)
                exit(0)
            }
        }
    }
}

extension AppModel {
    /// Test hook: `--background --answer-when-live <request id>` (a test copy with STEERIFY_WORKSPACES + --scratch-writes,
    /// no feedback inbox): Send when live on the draft, check it waits, mark its linked items live in delivered.json
    /// (what the release does), check it went out by itself, then quit.
    func answerWhenLiveTestHook() {
        let a = CommandLine.arguments
        guard a.contains("--background"), let i = a.firstIndex(of: "--answer-when-live"), i + 1 < a.count, let p = projects.first else { return }
        func log(_ s: String) { FileHandle.standardError.write("[when-live] \(s)\n".data(using: .utf8)!) }
        func req() -> BoardRequest? { RequestLog.load(p.boardDir).first { $0.id == a[i + 1] } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let r = req(), let d = r.answerDraft else { log("no draft"); exit(1) }
            let w = self.liveWait(r, in: p)
            log("linkable=\(w.linkable) linked=\(w.linked.map { $0.id + "/" + $0.status }) pending=\(w.pending)")
            self.sendWhenLive(r, text: d, in: p)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let q = req()
                log("waiting: whenLive=\(q?.answerWhenLive != nil) sent=\(q?.answer != nil) draft=\(q?.answerDraft != nil)")
                let f = (p.boardDir as NSString).appendingPathComponent("delivered.json")
                guard var all = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: f)))) as? [String: Any],
                      var items = all["items"] as? [[String: Any]] else { log("no delivered.json"); exit(1) }
                let ids = Set(w.linked.map(\.id))
                for k in items.indices where ids.contains(items[k]["id"] as? String ?? "") { items[k]["status"] = "live" }
                all["items"] = items
                try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: f))
                log("marked live: \(ids.sorted())")
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    let z = req()
                    log("after live: whenLive=\(z?.answerWhenLive != nil) sent=\(z?.answer != nil) text=\(z?.answer?.prefix(30) ?? "nil")")
                    exit(z?.answer != nil && z?.answerWhenLive == nil ? 0 : 2)
                }
            }
        }
    }
}

extension AppModel {
    /// Test hook: `--background --answers-shot <prefix>` (test copy, --scratch-writes): Answers to send drawn with a
    /// draft (<prefix>-draft.png), then after Send when live (<prefix>-waiting.png), then quit.
    func answersShotTestHook() {
        let a = CommandLine.arguments
        guard a.contains("--background"), let i = a.firstIndex(of: "--answers-shot"), i + 1 < a.count, let p = projects.first else { return }
        func shot(_ name: String) {
            let r = ImageRenderer(content: AnswersWaiting(project: p).environmentObject(self).frame(width: 760).padding(12)
                .background(Brand.bg).preferredColorScheme(.dark))
            r.scale = 2
            if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t) {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: a[i + 1] + "-" + name + ".png"))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            shot("draft")
            if let r = RequestLog.load(p.boardDir).first(where: { $0.answerable && $0.answerDraft != nil }), let d = r.answerDraft {
                self.sendWhenLive(r, text: d, in: p)
            }
            TurnMemo.clear()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { shot("waiting"); exit(0) }
        }
    }
}
