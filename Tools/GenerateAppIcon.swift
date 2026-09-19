import AppKit
import CoreGraphics

// MARK: - Shape helpers

/// Apple's icon outline is a squircle, not a rounded rectangle. A circular
/// corner reads as visibly "pinched" beside real macOS icons in the Dock, so
/// this samples the superellipse |x|^n + |y|^n = 1 instead.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720

    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * pow(abs(ct), 2 / n) * (ct < 0 ? -1 : 1)
        let y = cy + b * pow(abs(st), 2 / n) * (st < 0 ? -1 : 1)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

// MARK: - The icon

/// Small sizes get their own drawing rather than a downsample.
///
/// At 16 and 32 pixels the content lines, the pull and the stand all collapse
/// into noise — the detail that makes the large icon legible is exactly what
/// muddies the small one. Below 64px the mark is reduced to the two shapes
/// that survive: a screen, and a curtain across it.
func drawIcon(size: CGFloat) -> CGImage {
    let simplified = size <= 64
    let scale = size / 1024
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)

    // Apple's grid: the shape sits inside the canvas rather than filling it.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let outline = squircle(in: body)

    // Background: deep indigo, calm rather than alarming. The icon stands for
    // the app, not for the state it is in — amber is reserved for "on".
    ctx.saveGState()
    ctx.addPath(outline)
    ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 0.290, green: 0.318, blue: 0.639, alpha: 1),
        CGColor(red: 0.113, green: 0.125, blue: 0.290, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Three tones only — background, dark glass, white curtain. Anything
    // subtler than that dissolves into a smudge at 16pt, which is the size
    // most people will actually see this at.
    let screen = simplified
        ? CGRect(x: 236, y: 300, width: 552, height: 424)
        : CGRect(x: 272, y: 348, width: 480, height: 344)
    let screenPath = CGPath(roundedRect: screen,
                            cornerWidth: simplified ? 56 : 30,
                            cornerHeight: simplified ? 56 : 30, transform: nil)

    // The glass: dark, so the covered half genuinely contrasts with it.
    ctx.addPath(screenPath)
    ctx.setFillColor(CGColor(red: 0.063, green: 0.070, blue: 0.180, alpha: 1))
    ctx.fillPath()

    // What is being hidden, suggested rather than drawn: two lines of
    // something private, just visible below the curtain's edge.
    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.clip()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    for (y, width) in simplified ? [] : [(CGFloat(438), CGFloat(250)), (394, 170)] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: screen.minX + 42, y: y, width: width, height: 26),
                           cornerWidth: 13, cornerHeight: 13, transform: nil))
    }
    ctx.fillPath()

    // The curtain, drawn down over the top.
    let hem = screen.minY + screen.height * 0.46
    ctx.addPath(CGPath(rect: CGRect(x: screen.minX, y: hem, width: screen.width, height: screen.height), transform: nil))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()

    // A hem bar, so it reads as fabric pulled down rather than a crop.
    ctx.addPath(CGPath(rect: CGRect(x: screen.minX, y: hem, width: screen.width, height: simplified ? 34 : 22), transform: nil))
    ctx.setFillColor(CGColor(red: 0.290, green: 0.318, blue: 0.639, alpha: 0.85))
    ctx.fillPath()
    ctx.restoreGState()

    // The pull, hanging below the hem.
    if !simplified {
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.setLineWidth(11)
    ctx.move(to: CGPoint(x: 512, y: hem))
    ctx.addLine(to: CGPoint(x: 512, y: hem - 38))
    ctx.strokePath()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.fillEllipse(in: CGRect(x: 490, y: hem - 78, width: 44, height: 44))

    }

    // The stand, solid enough to actually read as one.
    if !simplified {
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 474, y: 286, width: 76, height: 70),
                       cornerWidth: 12, cornerHeight: 12, transform: nil))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 392, y: 262, width: 240, height: 34),
                       cornerWidth: 17, cornerHeight: 17, transform: nil))
    ctx.fillPath()
    }
    ctx.restoreGState()

    // A hairline lip, the way macOS icons catch the light along the top edge.
    ctx.addPath(outline)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.13))
    ctx.setLineWidth(3)
    ctx.strokePath()

    return ctx.makeImage()!
}

// MARK: - Export

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

struct Slot { let size: Int; let scale: Int }
let slots = [16, 32, 128, 256, 512].flatMap { [Slot(size: $0, scale: 1), Slot(size: $0, scale: 2)] }

var entries: [String] = []
for slot in slots {
    let pixels = slot.size * slot.scale
    let name = slot.scale == 1 ? "icon_\(slot.size).png" : "icon_\(slot.size)@2x.png"
    let image = drawIcon(size: CGFloat(pixels))
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: pixels, height: pixels)
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    entries.append("""
        {
          "filename" : "\(name)",
          "idiom" : "mac",
          "scale" : "\(slot.scale)x",
          "size" : "\(slot.size)x\(slot.size)"
        }
    """)
}

let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! contents.write(toFile: "\(out)/Contents.json", atomically: true, encoding: .utf8)
print("wrote \(slots.count) sizes to \(out)")
