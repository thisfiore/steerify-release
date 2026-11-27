import SwiftUI
import AppKit

// MARK: - Read the whole command of a permission prompt (request r261127-171427-fb8d6364)
//
// Claude Code's "Do you want to proceed?" prompt shows only the last lines of a long command ("↑ 242 more lines") and
// has no key to scroll it. The PermissionRequest hook saves the tool call it asks about (status/<session>.perm, see
// SessionHooks); while the session waits on it, a bar over the terminal opens the whole command: scrollable,
// selectable, with Copy. Answer the prompt in the terminal as usual (1 / 2 / Esc / Tab).

struct PendingPermission: Equatable {
    let tool: String
    let description: String?
    let body: String
    var lines: Int { body.split(separator: "\n", omittingEmptySubsequences: false).count }

    static func file(_ id: UUID) -> URL { SessionHooks.dir.appendingPathComponent(id.uuidString + ".perm") }

    static func read(_ id: UUID) -> PendingPermission? {
        guard let d = try? Data(contentsOf: file(id)) else { return nil }
        return parse(d)
    }

    /// The PermissionRequest hook input → what it asks to run.
    static func parse(_ d: Data) -> PendingPermission? {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let tool = o["tool_name"] as? String ?? "Tool"
        let input = o["tool_input"] as? [String: Any] ?? [:]
        let desc = (input["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var body: String
        if let c = input["command"] as? String { body = c }
        else if let c = input["content"] as? String, let f = input["file_path"] as? String { body = f + "\n\n" + c }
        else if let n = input["new_string"] as? String, let f = input["file_path"] as? String {
            body = f + "\n\n− " + ((input["old_string"] as? String) ?? "") + "\n\n+ " + n
        } else if let j = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
                  let s = String(data: j, encoding: .utf8) { body = s }
        else { return nil }
        body = body.trimmingCharacters(in: .newlines)
        guard !body.isEmpty else { return nil }
        return PendingPermission(tool: tool, description: desc, body: body)
    }
}

/// Over a Claude session's terminal: while it waits on a permission for a long tool call, "Read the whole command".
struct PermissionPeekLayer: View {
    @ObservedObject var session: TerminalSession
    @State private var pending: PendingPermission?
    @State private var open = false
    /// Below this the prompt shows the whole call itself.
    static let minLines = 12

    var body: some View {
        ZStack(alignment: .top) {
            if let p = pending, open || p.lines >= Self.minLines { PermissionPeekView(p: p, open: $open) }
        }
        .animation(.easeOut(duration: 0.15), value: open)
        .animation(.easeOut(duration: 0.15), value: pending)
        .onAppear { load() }
        .onChange(of: session.status) { _, _ in load() }
        .onChange(of: session.statusAt) { _, _ in load() }
    }

    private func load() {
        let p = session.kind == .claude && session.status == .waiting ? PendingPermission.read(session.id) : nil
        if p != pending { pending = p }
        if p == nil { open = false }
    }
}

/// The bar (closed) or the whole command (open).
struct PermissionPeekView: View {
    let p: PendingPermission
    @Binding var open: Bool

    var body: some View {
        if open { sheet(p).transition(.opacity) }
        else { bar(p).transition(.opacity.combined(with: .move(edge: .top))) }
    }

    private func bar(_ p: PendingPermission) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass").foregroundStyle(Brand.amber)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude asks to run a \(p.lines)-line \(p.tool == "Bash" ? "command" : p.tool)")
                    .font(.system(size: S(12), weight: .semibold)).foregroundStyle(Brand.cream).lineLimit(1)
                Text(p.description ?? "The prompt below shows only its last lines")
                    .font(.system(size: S(11))).foregroundStyle(Brand.mute).lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { open = true } label: {
                Text("Read it all").font(.system(size: S(12), weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Brand.amber)).foregroundStyle(Color(hex: 0x1a1200))
            }
            .buttonStyle(.plain).help("Open the whole command, scrollable and selectable")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x171a20).opacity(0.97)))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9).fill(Brand.amber).frame(width: 3) }
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Brand.line2))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
        .padding(.horizontal, 14).padding(.top, 10)
    }

    private func sheet(_ p: PendingPermission) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("THE WHOLE \(p.tool == "Bash" ? "COMMAND" : p.tool.uppercased()) · \(p.lines) LINES")
                    .font(Brand.label(8.5)).tracking(1.1).foregroundStyle(Brand.amber).lineLimit(1)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(p.body, forType: .string) } label: {
                    Label("Copy", systemImage: "doc.on.doc").font(.system(size: S(11.5), weight: .semibold))
                }
                .buttonStyle(SteerButton()).foregroundStyle(Brand.cream)
                Button { open = false } label: { Image(systemName: "xmark").font(.system(size: S(10), weight: .bold)) }
                    .buttonStyle(SteerButton()).foregroundStyle(Brand.mute).help("Back to the prompt")
                    .keyboardShortcut(.cancelAction)
            }
            if let d = p.description {
                Text(d).font(.system(size: S(13), weight: .semibold)).foregroundStyle(Brand.cream)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(p.body)
                    .font(.system(size: S(11.5), design: .monospaced)).foregroundStyle(Brand.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x0d0f12)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Brand.line))
            Text("Answer in the terminal below: 1 Yes · 2 No · Esc cancel · Tab amend")
                .font(.system(size: S(11))).foregroundStyle(Brand.mute)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x171a20).opacity(0.98)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.line2))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, S(150))   // the prompt stays visible below
    }
}

extension PermissionPeekView {
    /// `--perm-peek-shot <dir>`: the bar and the open view over a fake prompt, as pictures (2×), then quit.
    @MainActor static func renderShots(to dir: String) {
        let cmd = (0..<260).map { "rep(\"\"\"  /* step \($0) of the header patch */ const t = hd.querySelector(':scope > b'); \"\"\")" }
            .joined(separator: "\n")
        let p = PendingPermission(tool: "Bash", description: "Patch the work-area header script", body: "python3 - <<'EOF'\n" + cmd + "\nEOF")
        for (name, open) in [("bar", false), ("open", true)] {
            let v = ZStack(alignment: .topLeading) {
                Color(hex: 0x0d0f12)
                VStack(alignment: .leading, spacing: 2) {
                    Spacer()
                    ForEach(0..<6, id: \.self) { _ in Text("t.getBoundingClientRect().width > 1 ? t.getBoundingClientRect().right").foregroundStyle(Brand.ink) }
                    Text("Do you want to proceed?").foregroundStyle(Brand.cream)
                    Text("❯ 1. Yes").foregroundStyle(Brand.amber); Text("  2. No").foregroundStyle(Brand.ink)
                    Text("↑ 242 more lines").foregroundStyle(Brand.amber)
                    Text("Esc to cancel · Tab to amend").foregroundStyle(Brand.mute)
                }
                .font(.system(size: 12, design: .monospaced)).padding(12)
                PermissionPeekView(p: p, open: .constant(open))
            }
            .frame(width: 720, height: 820).environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: v)
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 820)
            let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = host; host.layoutSubtreeIfNeeded(); host.display()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("perm-peek-\(name).png")) }
        }
        NSApp.terminate(nil)
    }
}
