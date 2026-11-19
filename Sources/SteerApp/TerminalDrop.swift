import AppKit
import SwiftTerm
import UniformTypeIdentifiers

/// The terminal view of every session, plus drag & drop and image paste:
/// - drop files / screenshots → their paths are pasted (Claude Code turns image paths into [Image #1]);
/// - drop or ⌘V an image that has no file (screenshot thumbnail, browser image) → saved to Caches, path pasted.
final class SteerTerminalView: LocalProcessTerminalView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .png, .tiff, NSPasteboard.PasteboardType("public.jpeg")])
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    private var dropHighlight = false { didSet { needsDisplay = true; layer?.borderWidth = dropHighlight ? 2 : 0 } }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Self.paths(from: sender.draggingPasteboard, materialize: false) != nil else { return [] }
        layer?.borderColor = Theme.accent.cgColor
        dropHighlight = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropHighlight = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { dropHighlight = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHighlight = false
        guard let paths = Self.paths(from: sender.draggingPasteboard, materialize: true), !paths.isEmpty else { return false }
        pasteText(paths.map(Self.escape).joined(separator: " ") + " ")   // SwiftTerm paste: bracketed when asked, clipboard untouched
        window?.makeFirstResponder(self)
        return true
    }

    /// ⌘V with an image (and no text) on the clipboard → save it and paste its path, like a dropped screenshot.
    override func paste(_ sender: Any) {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) == nil, pb.types?.contains(.fileURL) != true,
           let paths = Self.paths(from: pb, materialize: true), !paths.isEmpty {
            pasteText(paths.map(Self.escape).joined(separator: " ") + " ")   // SwiftTerm paste: bracketed when asked, clipboard untouched
            return
        }
        if pb.string(forType: .string) == nil, let paths = Self.paths(from: pb, materialize: false), !paths.isEmpty {
            pasteText(paths.map(Self.escape).joined(separator: " ") + " ")   // SwiftTerm paste: bracketed when asked, clipboard untouched      // copied files in Finder
            return
        }
        super.paste(sender)
    }

    /// File paths in a pasteboard; images without a file are written to Caches/Steerify/drops when `materialize`.
    static func paths(from pb: NSPasteboard, materialize: Bool) -> [String]? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.map(\.path)
        }
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]
        guard let type = imageTypes.first(where: { pb.data(forType: $0) != nil }) else { return nil }
        guard materialize else { return [] }
        guard let data = pb.data(forType: type), let png = Self.png(data, type: type) else { return nil }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Steerify/drops", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = dir.appendingPathComponent("Image \(f.string(from: Date())).png")
        guard (try? png.write(to: url)) != nil else { return nil }
        return [url.path]
    }

    private static func png(_ data: Data, type: NSPasteboard.PasteboardType) -> Data? {
        if type == .png { return data }
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Same escaping as Terminal / iTerm drops: backslash before spaces and shell specials.
    static func escape(_ path: String) -> String {
        var out = ""
        for ch in path { if " \\'\"()[]{}&;|<>*?$`!#~".contains(ch) { out.append("\\") }; out.append(ch) }
        return out
    }
}
