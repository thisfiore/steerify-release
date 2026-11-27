import AppKit
import SwiftUI
import Foundation

// MARK: - Steerify relay (realtime between the iPhone and this Mac; server in relay/server.mjs)
//
// steerify.json → "relay": {"url": "https://relay.steerify.dev", "channel": "<random id>"}. The channel lives in the repo,
// so the phone (which reads the repo) finds it by itself. The relay never holds the board, only signals:
// - the phone sent its inbox → "pull" → this Mac takes it at once (PhoneInbox.swift)
// - this Mac applied it      → "pull" → the phone reads the board again
// - sessions changed         → "status" → the phone shows what runs and what needs you
// One open event stream per project, no polling (requirement mac-perf-idle); reconnects with a growing pause.

enum RelayConfig {
    struct Config { let url: URL; let channel: String }
    static func of(_ p: Project) -> Config? {
        guard let d = FileManager.default.contents(atPath: p.manifest),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let r = o["relay"] as? [String: Any], let ch = r["channel"] as? String, !ch.isEmpty else { return nil }
        let base = ProcessInfo.processInfo.environment["STEERIFY_RELAY_URL"] ?? r["url"] as? String ?? ""
        guard let u = URL(string: base), u.scheme?.hasPrefix("http") == true else { return nil }
        return Config(url: u, channel: ch)
    }
}

@MainActor
final class RelayHub {
    static let shared = RelayHub()
    var streams: [String: Task<Void, Never>] = [:]     // project id → its event stream
    var statusPending = false
    var lastStatus: [String: String] = [:]             // project id → last status sent (no repeats)
    var observing = false
    var observingRemote = false
}

extension Notification.Name {
    /// A session's Remote Control link was found (Sessions.swift): the phone gets it with the next status.
    static let steerifySessionRemote = Notification.Name("SteerifySessionRemote")
}

@MainActor
extension AppModel {
    func startRelay() {
        let hub = RelayHub.shared
        if CommandLine.arguments.contains("--pairing"), pairingProjectId == nil { pairingProjectId = project?.id }   // screenshots: the pairing window open
        // screenshots: a phone "connects" after N seconds (the pairing window's celebration, request r261123-211230)
        if let i = CommandLine.arguments.firstIndex(of: "--fake-phone"), i + 1 < CommandLine.arguments.count,
           let secs = Double(CommandLine.arguments[i + 1]), let pid = project?.id {
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) { [weak self] in self?.phones[pid] = 1 }
        }
        if !hub.observing {
            hub.observing = true
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartRelay() }
            }
        }
        if !hub.observingRemote {
            hub.observingRemote = true
            NotificationCenter.default.addObserver(forName: .steerifySessionRemote, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.publishStatus() }
            }
        }
        guard TaskClock.enabled else { return }
        for p in projects where hub.streams[p.id] == nil {
            guard let cfg = RelayConfig.of(p) else { continue }
            let pid = p.id
            hub.streams[pid] = Task { [weak self] in await self?.relayLoop(projectId: pid, cfg) }
        }
    }

    func restartRelay() {
        for t in RelayHub.shared.streams.values { t.cancel() }
        RelayHub.shared.streams = [:]
        startRelay()
    }

    private func relayLoop(projectId: String, _ cfg: RelayConfig.Config) async {
        var pause: UInt64 = 2
        while !Task.isCancelled {
            var req = URLRequest(url: cfg.url.appendingPathComponent("v1/c/\(cfg.channel)/events"))
            req.url = URL(string: req.url!.absoluteString + "?role=mac")
            req.timeoutInterval = 120                       // heartbeats every 25 s keep it open
            do {
                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                pause = 2
                publishStatus(force: true)
                var name = ""
                for try await line in bytes.lines {
                    if line.hasPrefix("event: ") { name = String(line.dropFirst(7)) }
                    else if line.hasPrefix("data: ") {
                        let o = (try? JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8))) as? [String: Any] ?? [:]
                        switch name {
                        case "pull": syncPhoneInbox()
                        case "hello": phones[projectId] = o["phones"] as? Int ?? 0
                        case "phones": phones[projectId] = o["count"] as? Int ?? 0
                        default: break
                        }
                        name = ""
                    }
                }
                phones[projectId] = nil
            } catch { phones[projectId] = nil }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: pause * 1_000_000_000)
            pause = min(pause * 2, 60)
        }
    }

    /// Tell the phone to read the board again (after this Mac applied its inbox).
    func relayPull(_ p: Project, why: String) {
        guard let cfg = RelayConfig.of(p) else { return }
        relayPost(cfg, "pull", ["from": "mac", "why": why])
    }

    /// Sessions changed: send each project's sessions (title, item, state), coalesced, only when something changed.
    func publishStatus(force: Bool = false) {
        let hub = RelayHub.shared
        guard TaskClock.enabled, !hub.statusPending else { return }
        hub.statusPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            hub.statusPending = false
            for p in self.projects {
                guard let cfg = RelayConfig.of(p) else { continue }
                let list: [[String: String]] = self.orderedSessions(of: p.id).filter { $0.kind == .claude && $0.status != .ended }.map {
                    self.phoneRow($0, project: p)
                }
                let sig = list.map { row in row.keys.sorted().map { k in k + "=" + row[k]! }.joined(separator: ",") }.joined(separator: "|")
                if !force && hub.lastStatus[p.id] == sig { continue }
                hub.lastStatus[p.id] = sig
                self.relayPost(cfg, "status", ["sessions": list])
            }
        }
    }

    /// One session as the phone draws it: the same signals as the Mac's session row (choice iphone-session-list).
    /// The Mac works them out (icon, outlook, your turn, done); the phone only draws (requirement ios-sessions-one-source).
    func phoneRow(_ s: TerminalSession, project p: Project) -> [String: String] {
        let turn = isWrapped(s) ? nil : yourTurn(s)
        let outlook = outlook(s)
        let wrapped = isWrapped(s)
        let parts = s.title.components(separatedBy: " · ")
        let hasVerb = parts.count > 1 && SessionName.verbs.values.contains(parts[0])
        let iconTitle = s.item?.title ?? s.title
        let iconName = PixelArt.cached(iconTitle) ?? PixelArt.pick(iconTitle)
        let icon = PixelArt.icons[iconName] ?? PixelArt.icons["sparkle"]!
        let group: String
        if wrapped { group = "done" }
        else if turn != nil || s.status == .waiting { group = "turn" }
        else if case .ask? = outlook { group = "turn" }
        else if s.status == .working || s.status == .starting { group = "working" }
        else if case .shells? = outlook { group = "working" }
        else { group = "idle" }
        let line: String
        if wrapped { line = outlook?.line ?? "done" }
        else if let turn { line = "your turn · " + turn.tab.title.capitalized.replacingOccurrences(of: "To Test", with: "To test") }
        else if let outlook { line = outlook.line }
        else { line = s.moodWord + (s.status == .idle ? " · " + s.repo.name : "") }
        return ["title": s.title, "item": s.item?.ref ?? "", "state": s.status.rawValue, "project": p.name, "remote": s.remoteURL ?? "",
                "verb": hasVerb ? parts[0] : "", "name": hasVerb ? parts.dropFirst().joined(separator: " · ") : s.title,
                "stage": wrapped ? "" : (stage(of: s)?.rawValue ?? ""), "line": line, "group": group,
                "turn": turn?.verb ?? "", "turnRef": turn?.ref ?? "",
                "icon": icon.rows.joined(separator: "/"), "iconColor": Self.hex(icon.color),
                "id": s.claudeId ?? "", "pinned": s.pinned ? "1" : "", "named": s.customName == nil ? "" : "1"]
    }

    private static func hex(_ c: Color) -> String {
        guard let n = NSColor(c).usingColorSpace(.sRGB) else { return "ffd27a" }
        return String(format: "%02x%02x%02x", Int(n.redComponent * 255), Int(n.greenComponent * 255), Int(n.blueComponent * 255))
    }

    private func relayPost(_ cfg: RelayConfig.Config, _ what: String, _ body: [String: Any]) {
        var r = URLRequest(url: cfg.url.appendingPathComponent("v1/c/\(cfg.channel)/\(what)"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        r.timeoutInterval = 15
        URLSession.shared.dataTask(with: r).resume()
    }
}
