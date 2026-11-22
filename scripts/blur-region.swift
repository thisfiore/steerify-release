// Covers a region of a PNG with an empty terminal (dark panel + a few faint skeleton lines): the terminal in the
// sessions shot shows real paths and the launch command. Opaque on purpose: the terminal pane is transparent in the
// snapshot, so a blur would leave the text readable.
//   swift scripts/blur-region.swift <png> <x0> <y0> <x1> <y1>     fractions 0–1 from the top-left
import AppKit

let a = CommandLine.arguments
guard a.count == 6, let src = NSImage(contentsOfFile: a[1]), let cg0 = src.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { print("usage: blur-region.swift <png> x0 y0 x1 y1"); exit(1) }
let f = a[2...5].map { CGFloat(Double($0)!) }
let W = CGFloat(cg0.width), H = CGFloat(cg0.height)
let ctx = CGContext(data: nil, width: cg0.width, height: cg0.height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg0, in: CGRect(x: 0, y: 0, width: W, height: H))
let r = CGRect(x: W * f[0], y: H * (1 - f[3]), width: W * (f[2] - f[0]), height: H * (f[3] - f[1])).integral
ctx.setFillColor(CGColor(srgbRed: 0.043, green: 0.047, blue: 0.059, alpha: 1)); ctx.fill(r)
// skeleton lines: a prompt and a few rows of output, like a terminal that has just started
let line = r.height / 34, pad = r.width * 0.05
let widths: [CGFloat] = [0.42, 0.0, 0.78, 0.64, 0.71, 0.0, 0.36, 0.55, 0.0, 0.22]
for (i, w) in widths.enumerated() where w > 0 {
    let y = r.maxY - pad - CGFloat(i + 1) * line * 1.5
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: i == 0 ? 0.16 : 0.07))
    ctx.addPath(CGPath(roundedRect: CGRect(x: r.minX + pad, y: y, width: (r.width - 2 * pad) * w, height: line * 0.55),
                       cornerWidth: line * 0.27, cornerHeight: line * 0.27, transform: nil)); ctx.fillPath()
}
ctx.setFillColor(CGColor(srgbRed: 1, green: 0.69, blue: 0.13, alpha: 0.85))   // the cursor
ctx.fill(CGRect(x: r.minX + pad, y: r.maxY - pad - 12 * line * 1.5, width: line * 0.5, height: line * 0.8))
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[1]))
