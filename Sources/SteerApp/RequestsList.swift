import SwiftUI
import AppKit

// MARK: - Requests: where every request is (request r261124: "we don't have a list of requests")
//
// READY tab: requests waiting for you on top (filed, no session yet: the project's users via the feedback form,
// the widget or Claude's report_issue, GitHub issues, what you filed without starting), the latest 5 at the bottom.
// Board › All Requests… (⇧⌘R): every request of the project, searchable, filtered by state.

extension AppModel {
    /// Filed and not started yet: you look first, then Start or Discard.
    func waitingRequests(_ p: Project) -> [BoardRequest] {
        let b = board(for: p)
        return RequestLog.cached(p.boardDir).filter { $0.status == "filed" && b.lastLink("request:" + $0.id) == nil }
    }

    func discardRequest(_ r: BoardRequest, in p: Project) {
        RequestLog.edit(p.boardDir, id: r.id) { $0["status"] = "discarded"; $0["note"] = "Discarded without a session" }
        objectWillChange.send()
        showToast("Discarded “\(r.title ?? r.short)”", projectId: p.id)
    }
}

/// A request line with Discard next to Start (only while it is waiting).
struct RequestLine: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    let r: BoardRequest
    var onOpen: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            RequestRow(project: project, r: r, onOpen: onOpen)
            if r.status == "filed" && model.board(for: project).lastLink("request:" + r.id) == nil {
                Button { model.discardRequest(r, in: project) } label: { Image(systemName: "xmark").font(.system(size: S(9), weight: .bold)) }
                    .buttonStyle(SteerButton()).foregroundStyle(Brand.mute.opacity(0.8)).help("Discard: no session, it stays in All Requests")
            }
        }
    }
}

/// READY tab, top: what came in and waits for you.
struct RequestsWaiting: View {
    @EnvironmentObject var model: AppModel
    let project: Project

    var body: some View {
        let waiting = model.waitingRequests(project)
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("NEW REQUESTS").font(Brand.label(10)).tracking(0.9).foregroundStyle(Color(hex: 0xc4a7ff))
                    Text("filed, no session yet · Start or discard").font(.system(size: S(11))).foregroundStyle(Brand.mute)
                    Spacer()
                    Button("All requests ⇧⌘R") { model.requestsListOpen = true }.buttonStyle(.link).font(.system(size: S(11))).pointerStyle(.link)
                }
                ForEach(waiting) { RequestLine(project: project, r: $0) }
                BugSquashButton(project: project).padding(.top, 4)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.panel.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xc4a7ff).opacity(0.35)))
            .padding(.bottom, 8)
        }
    }
}

/// READY tab, bottom: the latest requests and where they went.
struct RequestsRecent: View {
    @EnvironmentObject var model: AppModel
    let project: Project

    var body: some View {
        let waiting = Set(model.waitingRequests(project).map(\.id))
        let recent = Array(RequestLog.cached(project.boardDir).filter { !waiting.contains($0.id) }.prefix(5))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("RECENT REQUESTS · WHERE THEY WENT").font(Brand.label(9)).tracking(0.9).foregroundStyle(Brand.mute)
                    Spacer()
                    Button("All requests ⇧⌘R") { model.requestsListOpen = true }.buttonStyle(.link).font(.system(size: S(11))).pointerStyle(.link)
                }
                ForEach(recent) { RequestLine(project: project, r: $0) }
            }
        }
    }
}

enum RequestFilter: String, CaseIterable {
    case waiting, open, users, all
    var title: String { ["waiting": "Waiting", "open": "Open", "users": "From users", "all": "All"][rawValue]! }
}

/// Board › All Requests… (⇧⌘R): every request of the project, searchable.
struct RequestsListView: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    @State private var query = ""
    @State private var filter: RequestFilter = .all
    @FocusState private var focused: Bool

    private func matches(_ r: BoardRequest, _ f: RequestFilter, waiting: Set<String>) -> Bool {
        switch f {
        case .waiting: return waiting.contains(r.id)
        case .open: return !["done", "approved", "discarded"].contains(r.status)
        case .users: return r.fromFeedback || r.fromGitHub
        case .all: return true
        }
    }

    var body: some View {
        let all = RequestLog.cached(project.boardDir)
        let waiting = Set(model.waitingRequests(project).map(\.id))
        let words = query.lowercased().split(separator: " ").map(String.init)
        let found = all.filter { r in
            let hay = [r.text, r.title ?? "", r.reporter ?? "", r.chapter ?? "", r.note ?? "", r.kind.label, r.status, r.id].joined(separator: " ").lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
        let shown = found.filter { matches($0, filter, waiting: waiting) }
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { close() }
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.system(size: S(16), weight: .semibold)).foregroundStyle(Color(hex: 0xc4a7ff))
                        TextField("Search \(project.name)'s requests: words, a name, a chapter…", text: $query)
                            .textFieldStyle(.plain).font(.system(size: S(17), weight: .medium)).foregroundStyle(.white).focused($focused)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.mute) }.buttonStyle(.plain).pointerStyle(.link)
                        }
                        Button("ESC") { close() }.buttonStyle(.plain).font(Brand.label(8.5)).foregroundStyle(Brand.mute)
                            .padding(.horizontal, 5).padding(.vertical, 2).overlay(RoundedRectangle(cornerRadius: 4).stroke(Brand.line2))
                    }
                    .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 12)
                    HStack(spacing: 6) {
                        ForEach(RequestFilter.allCases, id: \.self) { f in
                            let n = found.filter { matches($0, f, waiting: waiting) }.count, on = f == filter
                            Button { filter = f; focused = true } label: {
                                HStack(spacing: 6) {
                                    Text(f.title.uppercased()).font(Brand.label(9.5)).tracking(0.7)
                                    Text("\(n)").font(.system(size: S(10), weight: .semibold).monospacedDigit()).opacity(0.75)
                                }
                                .foregroundStyle(on ? Color.black : n == 0 ? Brand.mute.opacity(0.5) : Brand.ink)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(PixelBox().fill(on ? Color(hex: 0xc4a7ff) : Brand.panel2))
                            }
                            .buttonStyle(.plain).pointerStyle(.link)
                        }
                        Spacer()
                        BugSquashButton(project: project)
                        Button { close(); model.requestOpen = true } label: { Text("+ Request ⌘N").font(.system(size: S(11.5), weight: .semibold)) }
                            .buttonStyle(SteerButton()).foregroundStyle(Brand.amber)
                    }
                    .padding(.horizontal, 18).padding(.bottom, 12)
                    Divider().overlay(Brand.line)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if shown.isEmpty {
                                Text(all.isEmpty ? "No requests yet. ⌘N files one; your users' reports land here too." : "Nothing matches.")
                                    .font(.system(size: S(12))).foregroundStyle(Brand.mute).padding(.vertical, 20)
                            }
                            ForEach(shown) { RequestLine(project: project, r: $0, onOpen: close) }
                        }
                        .padding(.horizontal, 18).padding(.vertical, 10)
                    }
                    .frame(height: min(S(520), geo.size.height - S(200)))
                    Divider().overlay(Brand.line)
                    Text("Click a request to open where it went · Start opens a briefed Claude session · ✕ discards a waiting one")
                        .font(.system(size: S(10.5))).foregroundStyle(Brand.mute)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.vertical, 9)
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0x101216)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Brand.line2))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.7), radius: 40, y: 16)
                .frame(width: min(S(860), geo.size.width - 60))
                .padding(.top, max(40, geo.size.height * 0.09))
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if !model.waitingRequests(project).isEmpty { filter = .waiting }
            NSApp.keyWindow?.makeFirstResponder(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onKeyPress(.escape) { if query.isEmpty { close() } else { query = "" }; return .handled }
    }

    private func close() { model.requestsListOpen = false }
}
