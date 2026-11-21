// Renders the Steerify pixel-wheel icon into an .iconset (all macOS sizes). Usage: swift make-icon.swift <out.iconset>
// iPhone: swift make-icon.swift --ios <out.png>  → 1024×1024, full square, no transparency (iOS rounds the corners).
import AppKit

let ios = CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--ios"
let out = ios ? CommandLine.arguments[2] : CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
if !ios { try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true) }

func cg(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}

// Same raster as the board mockup (17×17 grid).
func wheelCells() -> [(Int, Int, UInt32)] {
    let n = 17, c = 8.0
    var cells: [(Int, Int, UInt32)] = []
    for y in 0..<n { for x in 0..<n {
        let dx = Double(x) - c, dy = Double(y) - c, r = hypot(dx, dy), a = atan2(dy, dx)
        let k = (a / (.pi / 4)).rounded(), da = abs(a - k * .pi / 4) * r
        var col: UInt32? = nil
        if r <= 2.2 { col = 0xffb020 }
        else if r >= 4.6 && r <= 5.9 { col = 0xf2e8cf }
        else if da < 0.55 && r <= 7.4 { col = 0xf2e8cf }
        else if r > 7.4 && r <= 8.3 && da < 0.9 { col = 0xf2e8cf }
        if let col { cells.append((x, y, col)) }
    } }
    for (x, y) in [(7, 7), (8, 8), (7, 9)] {
        if let i = cells.firstIndex(where: { $0.0 == x && $0.1 == y }) { cells[i].2 = 0x1b1305 }
    }
    return cells
}

func render(_ px: Int, fullBleed: Bool = false) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: (fullBleed ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1)         // top-left origin
    let inset = fullBleed ? 0 : s * 100 / 1024, body = s - 2 * inset   // macOS icon grid: 824 of 1024; iOS: the whole square
    let rect = CGRect(x: inset, y: inset, width: body, height: body)
    let path = fullBleed ? CGPath(rect: rect, transform: nil) : CGPath(roundedRect: rect, cornerWidth: body * 0.225, cornerHeight: body * 0.225, transform: nil)
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let grad = CGGradient(colorsSpace: nil, colors: [cg(0x1a1d24), cg(0x07080a)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    let pad = body * 0.15, cell = (body - 2 * pad) / 17, gap = max(cell * 0.06, px >= 64 ? 1 : 0)
    for (x, y, col) in wheelCells() {
        ctx.setFillColor(cg(col))
        ctx.fill(CGRect(x: rect.minX + pad + CGFloat(x) * cell + gap / 2, y: rect.minY + pad + CGFloat(y) * cell + gap / 2,
                        width: cell - gap, height: cell - gap))
    }
    if px >= 128 {                                                // faint CRT scanlines
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.16))
        var y = rect.minY; let step = max(body / 92 * 4, 3)
        while y < rect.maxY { ctx.fill(CGRect(x: rect.minX, y: y, width: body, height: step / 2)); y += step }
    }
    ctx.restoreGState()
    if fullBleed { return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])! }
    ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14)); ctx.setLineWidth(max(1, s / 512)); ctx.strokePath()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

if ios {
    try! render(1024, fullBleed: true).write(to: URL(fileURLWithPath: out))
    print("ok"); exit(0)
}
for (base, name) in [(16, "16x16"), (32, "32x32"), (128, "128x128"), (256, "256x256"), (512, "512x512")] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(name)@2x.png"))
}
print("ok")
