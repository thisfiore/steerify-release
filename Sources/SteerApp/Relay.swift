import AppKit
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
                let list: [[String: String]] = self.sessions.filter { $0.projectId == p.id && $0.kind == .claude && $0.status != .ended }.map {
                    ["title": $0.title, "item": $0.item?.ref ?? "", "state": $0.status.rawValue, "project": p.name, "remote": $0.remoteURL ?? ""]
                }
                let sig = list.map { $0["item"]! + $0["state"]! + $0["title"]! + $0["remote"]! }.joined(separator: "|")
                if !force && hub.lastStatus[p.id] == sig { continue }
                hub.lastStatus[p.id] = sig
                self.relayPost(cfg, "status", ["sessions": list])
            }
        }
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
