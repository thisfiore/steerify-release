import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Connect the iPhone from the Mac (feedback 21 Nov: "set it up from the desktop, no complicated stuff")
//
// One QR per project. The iPhone camera opens it as steerify://pair?… and Steerify for iPhone keeps:
// the GitHub repo + branch + board folder, the relay (url + channel) and a GitHub token (from `gh auth token` on this
// Mac when you are logged in with the GitHub CLI; otherwise the phone asks for one). The QR only shows on screen,
// it never leaves this Mac. Later: "Sign in with GitHub" on the phone instead of the Mac's token.

enum PhonePairing {
    struct Info {
        let url: URL; let repo: String; let hasToken: Bool; let relay: Bool
        let branch: String
        /// Why the phone would not find the board on GitHub yet (nil = pushed), and the command that fixes it.
        var unpushed: String? = nil
        var pushCommand: String = ""
    }

    static func info(for p: Project) -> Info? {
        guard let root = Git.run(p.boardDir, ["rev-parse", "--show-toplevel"]), !root.isEmpty,
              let remote = Git.run(root, ["remote", "get-url", "origin"]),
              let repo = githubRepo(remote) else { return nil }
        let branch = Git.run(root, ["rev-parse", "--abbrev-ref", "HEAD"]) ?? "main"
        let realRoot = (root as NSString).resolvingSymlinksInPath, realBoard = (p.boardDir as NSString).resolvingSymlinksInPath
        let dir = realBoard.hasPrefix(realRoot) ? String(realBoard.dropFirst(realRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : ".steerify"
        let relay = ensureRelay(p)
        let token = ghToken()
        var c = URLComponents()
        c.scheme = "steerify"; c.host = "pair"
        var q = [URLQueryItem(name: "v", value: "1"), URLQueryItem(name: "name", value: p.name), URLQueryItem(name: "repo", value: repo),
                 URLQueryItem(name: "branch", value: branch), URLQueryItem(name: "dir", value: dir.isEmpty ? "." : dir)]
        if let relay { q += [URLQueryItem(name: "relay", value: relay.url.absoluteString), URLQueryItem(name: "channel", value: relay.channel)] }
        if let token { q.append(URLQueryItem(name: "token", value: token)) }
        c.queryItems = q
        guard let url = c.url else { return nil }
        let boardDir = dir.isEmpty ? "." : dir
        return Info(url: url, repo: repo, hasToken: token != nil, relay: relay != nil, branch: branch,
                    unpushed: pushProblem(root: root, branch: branch, dir: dir),
                    pushCommand: "git add \(boardDir) && git commit -m \"Steerify board\" && git push -u origin \(branch)")
    }

    /// The iPhone reads the board from GitHub, not from this Mac: a board that was never committed or pushed
    /// is a 404 on the phone (request 23 Nov: "Not found on GitHub"). Checked against the last known origin
    /// refs, no network call.
    static func pushProblem(root: String, branch: String, dir: String) -> String? {
        let board = dir.isEmpty ? "board.json" : dir + "/board.json"
        if Git.run(root, ["ls-files", "--error-unmatch", board]) == nil { return "The board is not committed yet." }
        if Git.run(root, ["rev-parse", "--verify", "--quiet", "refs/remotes/origin/\(branch)"]) == nil {
            return "Branch “\(branch)” is not on GitHub yet."
        }
        if Git.run(root, ["cat-file", "-e", "origin/\(branch):\(board)"]) == nil { return "The board is committed but not pushed." }
        return nil
    }

    /// "https://github.com/owner/name(.git)" or "git@github.com:owner/name.git" → "owner/name".
    static func githubRepo(_ remote: String) -> String? {
        let r = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = r.range(of: #"github\.com[:/]([^/]+)/([^/]+?)(\.git)?$"#, options: .regularExpression) else { return nil }
        let tail = r[m].replacingOccurrences(of: "github.com", with: "").trimmingCharacters(in: CharacterSet(charactersIn: ":/"))
        return tail.hasSuffix(".git") ? String(tail.dropLast(4)) : tail
    }

    /// The project's relay channel; created (and written to steerify.json) the first time.
    static func ensureRelay(_ p: Project) -> RelayConfig.Config? {
        if let c = RelayConfig.of(p) { return c }
        guard let d = FileManager.default.contents(atPath: p.manifest),
              var o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let ch = "ch-" + bytes.map { String(format: "%02x", $0) }.joined()
        o["relay"] = ["url": "https://relay.steerify.dev", "channel": ch]
        if let out = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? out.write(to: URL(fileURLWithPath: p.manifest), options: .atomic)
        }
        return RelayConfig.of(p)
    }

    /// The GitHub CLI's token on this Mac, if you are logged in with `gh auth login`.
    static func ghToken() -> String? {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = ["auth", "token"]
            let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { continue }
            p.waitUntilExit()
            let t = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if p.terminationStatus == 0, !t.isEmpty { return t }
        }
        return nil
    }

    /// The QR, drawn in crisp pixels (nearest neighbour), like the rest of Steerify.
    static func qr(_ text: String, size: CGFloat) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8); f.correctionLevel = "M"
        guard let img = f.outputImage else { return nil }
        let scale = (size / img.extent.width).rounded(.down)
        let scaled = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let out = NSImage(size: rep.size); out.addRepresentation(rep)
        return out
    }
}

/// Settings → iPhone: pick a project, show its QR, scan it with the iPhone camera.
struct PhonePairingView: View {
    @EnvironmentObject var model: AppModel
    @State private var projectId: String = ""
    @State private var shown: PhonePairing.Info?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("Project", selection: $projectId) {
                    ForEach(model.projects, id: \.id) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 260)
                Button(shown == nil ? "Show QR" : "Hide") {
                    if shown != nil { shown = nil; return }
                    guard let p = model.projects.first(where: { $0.id == projectId }) else { return }
                    shown = PhonePairing.info(for: p)
                    problem = shown == nil ? "This project's board is not in a GitHub repo yet (git remote origin on github.com)." : nil
                }
            }
            if let s = shown, let img = PhonePairing.qr(s.url.absoluteString, size: 260) {
                HStack(alignment: .top, spacing: 18) {
                    Image(nsImage: img).interpolation(.none).resizable().frame(width: 220, height: 220)
                        .padding(10).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Point the iPhone camera at it, tap “Open in Steerify”.").font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.ink)
                        row("Board", s.repo)
                        row("On GitHub", s.unpushed == nil ? "pushed on \(s.branch)" : "not yet: push first")
                        if let why = s.unpushed {
                            PushFirstNote(why: why, command: s.pushCommand)
                        }
                        row("Realtime", s.relay ? "relay.steerify.dev" : "off")
                        row("GitHub access", s.hasToken ? "your GitHub CLI login on this Mac" : "the phone will ask for a token")
                        Text("The code holds a GitHub token: show it only to your own phone.").font(.system(size: 11)).foregroundStyle(Brand.amber)
                    }
                }
            }
            if let problem { Text(problem).font(.system(size: 12)).foregroundStyle(Brand.red) }
        }
        .onAppear { if projectId.isEmpty { projectId = model.project?.id ?? model.projects.first?.id ?? "" } }
        .onChange(of: projectId) { _, _ in shown = nil }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(k.uppercased()).font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute).frame(width: 96, alignment: .leading)
            Text(v).font(.system(size: 12)).foregroundStyle(Brand.ink)
        }
    }
}

/// "Connect your iPhone": the pairing window, opened from the phone icon at the end of the tab bar.
struct PairingModal: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    @State private var info: PhonePairing.Info?
    @State private var loading = true
    @AppStorage(Prefs.remoteControl, store: Prefs.store) private var remoteControl = true
    /// When the phone connected while this window was open: the celebration bursts (request r261123-211230).
    @State private var cheeredAt: Date?
    /// Connected, but the user wants the code again (pairing another phone).
    @State private var showCode = false

    var body: some View {
        let n = model.phones[project.id] ?? 0
        let done = n > 0
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                PixelIcon(name: "phone", size: S(26)).foregroundStyle(n > 0 ? Brand.green : Brand.cream)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONNECT YOUR IPHONE").font(Brand.label(13)).tracking(1.4).foregroundStyle(Brand.amber)
                    Text(project.name).font(.system(size: S(17), weight: .bold)).foregroundStyle(Brand.ink)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(n > 0 ? Brand.green : Brand.mute).frame(width: 8, height: 8)
                    Text(n > 0 ? (n == 1 ? "Connected now" : "\(n) phones connected") : "Not connected").font(.system(size: S(12.5), weight: .semibold))
                        .foregroundStyle(n > 0 ? Brand.green : Brand.mute)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill((n > 0 ? Brand.green : Brand.mute).opacity(0.12)))
            }
            HStack(alignment: .top, spacing: 26) {
                if done && !showCode {
                    VStack(spacing: 6) {
                        PairedCheer(since: cheeredAt).frame(width: 260, height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Brand.green.opacity(0.6), lineWidth: 1.5))
                        Button("Show the code (pair another phone)") { showCode = true }
                            .buttonStyle(.plain).font(.system(size: S(11))).foregroundStyle(Brand.mute)
                    }
                } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.white)
                    if let i = info, let img = PhonePairing.qr(i.url.absoluteString, size: 300) {
                        Image(nsImage: img).interpolation(.none).resizable().padding(14)
                    } else if loading { ProgressView() }
                    else { Text("No GitHub repo for this board").font(.system(size: 12)).foregroundStyle(.black).padding() }
                }
                .frame(width: 260, height: 260)
                }
                VStack(alignment: .leading, spacing: 14) {
                    step(1, "Push this repo to GitHub", info.map { $0.unpushed == nil ? "Done: the board is on \($0.branch)" : "The phone reads the board from there" }
                         ?? "The phone reads the board from there", ok: done || (info != nil && info?.unpushed == nil))
                    step(2, "Install Steerify on the iPhone", done ? "Done" : "TestFlight → Steerify", ok: done)
                    step(3, "Open the Camera, point it here", done ? "Done: code scanned" : "No app to open first", ok: done)
                    step(4, "Tap “Open in Steerify”", done ? "Done: the board is on your phone" : "The board shows in a few seconds", ok: done)
                    Divider().overlay(Brand.line)
                    if let i = info {
                        row("BOARD", i.repo)
                        row("REALTIME", i.relay ? "relay.steerify.dev" : "off")
                        row("GITHUB", i.hasToken ? "your GitHub CLI login on this Mac" : "the phone asks for a token")
                    }
                }
            }
            if let i = info, let why = i.unpushed {
                PushFirstNote(why: why, command: i.pushCommand)
            }
            Toggle(isOn: $remoteControl) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open sessions on your phone").font(.system(size: S(12.5), weight: .medium)).foregroundStyle(Brand.ink)
                    Text("New Claude sessions start with Remote Control: tap one on the iPhone to continue it in the Claude app.")
                        .font(.system(size: S(11))).foregroundStyle(Brand.mute)
                }
            }.toggleStyle(.switch).tint(Brand.amber)
            HStack {
                Text("The code holds GitHub access: show it only to your own phone.").font(.system(size: S(11))).foregroundStyle(Brand.amber)
                Spacer()
                Button("Done") { model.pairingProjectId = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 640)
        .background(RoundedRectangle(cornerRadius: 14).stroke(Brand.green.opacity(done ? 0.55 : 0), lineWidth: 2).padding(1))
        .animation(.easeOut(duration: 0.35), value: done)
        .onChange(of: n) { old, new in
            if old == 0 && new > 0 { cheeredAt = Date(); showCode = false }
        }
        .task {
            let p = project
            info = await Task.detached { PhonePairing.info(for: p) }.value   // git + gh calls off the main thread
            loading = false
        }
    }

    private func step(_ n: Int, _ title: String, _ sub: String, ok: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(ok ? "✓" : "\(n)").font(.system(size: S(13), weight: .heavy, design: .monospaced)).foregroundStyle(Color(hex: 0x1a1200))
                .frame(width: 24, height: 24).background(Rectangle().fill(ok ? Brand.green : Brand.amber))
                .animation(.spring(response: 0.3, dampingFraction: 0.5).delay(Double(n) * 0.12), value: ok)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: S(13.5), weight: .semibold)).foregroundStyle(Brand.ink)
                Text(sub).font(.system(size: S(11.5))).foregroundStyle(Brand.mute)
            }
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(k).font(Brand.label(9)).tracking(0.8).foregroundStyle(Brand.mute).frame(width: 70, alignment: .leading)
            Text(v).font(.system(size: S(12))).foregroundStyle(Brand.ink).lineLimit(1)
        }
    }
}

/// "Push first": the board is not on GitHub yet, so the phone would say "Not found on GitHub".
struct PushFirstNote: View {
    let why: String
    let command: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PUSH FIRST · THE PHONE WON’T FIND THE BOARD").font(Brand.label(10)).tracking(1).foregroundStyle(Brand.red)
            Text(why + " The iPhone reads the board from GitHub, so push the repo with its board folder, then scan.")
                .font(.system(size: S(12))).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(command).font(.system(size: S(11), design: .monospaced)).foregroundStyle(Brand.cream)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 4)
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string); copied = true
                }
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Brand.red.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.red.opacity(0.45)))
    }
}

/// The phone icon at the end of the tab bar: green while an iPhone is connected; opens the pairing window.
struct PhoneStatusButton: View {
    @EnvironmentObject var model: AppModel
    let project: Project
    var body: some View {
        let n = model.phones[project.id] ?? 0
        Button { model.pairingProjectId = project.id } label: {
            HStack(spacing: 5) {
                PixelIcon(name: "phone", size: S(15))
                if n > 0 { Circle().fill(Brand.green).frame(width: 6, height: 6) }
            }
            .foregroundStyle(n > 0 ? Brand.green : Brand.mute)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(n > 0 ? Brand.green.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(SteerButton())
        .help(n > 0 ? "iPhone connected · click to pair another or change settings" : "Connect your iPhone (scan a code)")
    }
}
