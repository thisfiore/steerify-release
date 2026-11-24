import SwiftUI

// MARK: - Answers to the people who file (request r261124-074236: "a way to answer people's questions, email + relay")
//
// A request from the project's own users (feedback form, widget, an agent through report_issue) can get a reply:
//   Claude drafts it (update_request → answer), or you write it (Answer on the request's row);
//   you edit and Send it here → requests.json "answer" {text, at, by} → the next snapshot carries it to the relay
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
        RequestLog.cached(p.boardDir).filter { $0.answerable && $0.answerDraft != nil }
    }

    /// Send: the answer is kept on the request, the draft goes, and the relay gets it now (it mails it once).
    func sendAnswer(_ r: BoardRequest, text: String, in p: Project) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        _ = RequestLog.edit(p.boardDir, id: r.id) { x in
            x["answer"] = ["text": t, "at": RequestLog.now(), "by": "you"]
            x.removeValue(forKey: "answerDraft")
            x["updated"] = RequestLog.now()
        }
        objectWillChange.send()
        syncFeedbackInbox(force: true)
        showToast(FeedbackInbox.config(p) == nil ? "Answer saved: this project has no feedback inbox to send it through"
                                                 : "Answer sent to \(r.reporter ?? "them") · \(r.answerRoute)", projectId: p.id)
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
        _text = State(initialValue: r.answerDraft ?? r.answer ?? "")
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
            HStack(spacing: 8) {
                if r.answerDraft != nil && r.answer == nil {
                    Text("Drafted by Claude: check it, then send").font(.system(size: S(10.5))).foregroundStyle(Brand.claude)
                } else if let at = r.answerAt {
                    Text("Sent \(SessionChip.ago(at)): sending again replaces it and mails it again").font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                }
                Spacer()
                Button("Not now") {
                    model.saveAnswerDraft(r, text: nil, in: project); onDone()
                }.buttonStyle(SteerButton()).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
                    .help("Drop the draft: nothing is sent (Answer on the request's row writes one again)")
                ActionButton(title: "Send", icon: "paperplane", primary: true) {
                    model.sendAnswer(r, text: text, in: project); onDone()
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Text("to the people who asked · nothing goes out before Send").font(.system(size: S(11))).foregroundStyle(Brand.mute)
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
                if r.answer != nil {
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
