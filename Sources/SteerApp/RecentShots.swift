import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The screenshots you just took (⇧⌘3 / ⇧⌘4 / ⇧⌘5), newest first, from the folder macOS saves them to.
/// Read when the New request sheet opens and again whenever that folder changes (no polling).
enum RecentShots {
    /// `defaults write com.apple.screencapture location …`, else the Desktop.
    static var folder: URL {
        // Test copies (demo shots) point it elsewhere so your real Desktop never shows up in a picture.
        if let t = ProcessInfo.processInfo.environment["STEERIFY_SHOTS_DIR"], !t.isEmpty { return URL(fileURLWithPath: t, isDirectory: true) }
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !loc.isEmpty {
            let u = URL(fileURLWithPath: (loc as NSString).expandingTildeInPath, isDirectory: true)
            var dir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &dir), dir.boolValue { return u }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Screenshots of the last `within` seconds, newest first. Only files macOS marked as a screen capture
    /// (works whatever the language of the file name), plus anything Steerify's own Capture… made.
    static func list(limit: Int = 5, within: TimeInterval = 24 * 3600, in dir: URL = folder) -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentTypeKey, .isRegularFileKey]
        guard let all = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let since = Date().addingTimeInterval(-within)
        return all.compactMap { u -> (URL, Date)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  v.contentType?.conforms(to: .image) == true,
                  let d = v.creationDate, d > since, isScreenCapture(u) else { return nil }
            return (u, d)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit).map(\.0)
    }

    static func isScreenCapture(_ u: URL) -> Bool {
        getxattr(u.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }

    /// A small thumbnail without decoding the whole (often 5K) picture.
    static func thumb(_ u: URL, px: Int = 240) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                    kCGImageSourceThumbnailMaxPixelSize: px,
                                                                    kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Calls `onChange` (on main) whenever a file lands in or leaves the folder. Keep the returned source; cancel it to stop.
    static func watch(_ dir: URL = folder, onChange: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        s.setEventHandler(handler: onChange)
        s.setCancelHandler { close(fd) }
        s.resume()
        return s
    }
}

/// One row under the text: your latest screenshots; click one to attach it, click again to take it back.
struct RecentShotsStrip: View {
    let shots: [URL]
    let thumbs: [URL: NSImage]
    @Binding var images: [URL]
    var onMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT SCREENSHOTS · \(RecentShots.folder.lastPathComponent.uppercased())")
                .font(Brand.label(8.5)).tracking(0.8).foregroundStyle(Brand.mute)
            HStack(spacing: 8) {
                ForEach(shots, id: \.self) { u in
                    let on = images.contains(u)
                    Button { if on { images.removeAll { $0 == u } } else { images.append(u) } } label: {
                        ZStack(alignment: .topTrailing) {
                            Group {
                                if let t = thumbs[u] { Image(nsImage: t).resizable().aspectRatio(contentMode: .fill) }
                                else { Rectangle().fill(Brand.panel2) }
                            }
                            .frame(width: 104, height: 64).clipped()
                            .overlay(alignment: .bottomLeading) {
                                Text(Self.time(u)).font(.system(size: S(9.5), design: .monospaced)).foregroundStyle(.white)
                                    .padding(.horizontal, 4).padding(.vertical, 1).background(.black.opacity(0.6)).padding(3)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? Brand.amber : Brand.line2, lineWidth: on ? 2 : 1))
                            .opacity(on ? 1 : 0.8)
                            if on {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(Color(hex: 0x1a1200), Brand.amber)
                                    .padding(3)
                            }
                        }
                        // A filled thumbnail overflows its 104×64 box; .clipped() hides that but still takes clicks,
                        // so the next (older) shot, drawn on top, used to steal clicks on the newest one.
                        .frame(width: 104, height: 64)
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain).pointerStyle(.link)
                    .help(on ? "Attached · click to remove" : "Attach \(u.lastPathComponent)")
                }
                Button(action: onMore) {
                    Text("More…").font(.system(size: S(11))).foregroundStyle(Brand.cream)
                        .padding(.horizontal, 8).padding(.vertical, 4).overlay(RoundedRectangle(cornerRadius: 5).stroke(Brand.line2))
                }.buttonStyle(SteerButton()).help("Pick older screenshots from \(RecentShots.folder.path)")
                Spacer()
            }
        }
    }

    static func time(_ u: URL) -> String {
        guard let d = (try? u.resourceValues(forKeys: [.creationDateKey]))?.creationDate else { return "" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: d)
    }
}
