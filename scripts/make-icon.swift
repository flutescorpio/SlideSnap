// Draws the app icon (1024×1024 PNG): a skewed photo of a slide behind
// the same slide straightened. Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r / 255, g / 255, b / 255, a])!
}

// Background: macOS-style rounded square with a violet gradient.
let inset: CGFloat = 100
let bg = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let bgPath = CGPath(roundedRect: bg, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0, 0, 0, 0.35))
ctx.addPath(bgPath)
ctx.setFillColor(color(60, 40, 140))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let grad = CGGradient(colorsSpace: cs, colors: [color(118, 92, 240), color(52, 34, 128)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: bg.minX, y: bg.maxY), end: CGPoint(x: bg.maxX, y: bg.minY), options: [])
ctx.restoreGState()

// The photo: a skewed, dim quad.
let quad = [CGPoint(x: 230, y: 560), CGPoint(x: 760, y: 640), CGPoint(x: 800, y: 330), CGPoint(x: 260, y: 300)]
ctx.beginPath()
ctx.addLines(between: quad)
ctx.closePath()
ctx.setFillColor(color(255, 255, 255, 0.22))
ctx.fillPath()

// The straightened slide.
let slide = CGRect(x: 300, y: 380, width: 480, height: 270)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0, 0, 0, 0.35))
ctx.addPath(CGPath(roundedRect: slide, cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.setFillColor(color(255, 255, 255))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: slide, cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.clip()
ctx.setFillColor(color(80, 58, 180))
ctx.fill(CGRect(x: slide.minX, y: slide.maxY - 58, width: slide.width, height: 58))
ctx.restoreGState()
// Text lines.
ctx.setFillColor(color(200, 196, 220))
for (i, w) in [CGFloat(360), 300, 330].enumerated() {
    let y = slide.maxY - 100 - CGFloat(i) * 46
    ctx.addPath(CGPath(roundedRect: CGRect(x: slide.minX + 40, y: y, width: w, height: 20),
                       cornerWidth: 10, cornerHeight: 10, transform: nil))
    ctx.fillPath()
}

// Corner brackets of a "scan" frame.
ctx.setStrokeColor(color(255, 255, 255, 0.95))
ctx.setLineWidth(18)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let f = slide.insetBy(dx: -38, dy: -38), arm: CGFloat = 70
for (p, dx, dy) in [(CGPoint(x: f.minX, y: f.maxY), arm, -arm), (CGPoint(x: f.maxX, y: f.maxY), -arm, -arm),
                    (CGPoint(x: f.minX, y: f.minY), arm, arm), (CGPoint(x: f.maxX, y: f.minY), -arm, arm)] {
    ctx.move(to: CGPoint(x: p.x, y: p.y + dy))
    ctx.addLine(to: p)
    ctx.addLine(to: CGPoint(x: p.x + dx, y: p.y))
}
ctx.strokePath()

// "Text" badge: T in a circle, bottom right.
let badge = CGRect(x: 650, y: 190, width: 170, height: 170)
ctx.setFillColor(color(255, 196, 64))
ctx.fillEllipse(in: badge)
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 110, weight: .heavy),
                                            .foregroundColor: NSColor(red: 0.25, green: 0.16, blue: 0.55, alpha: 1)]
let t = NSAttributedString(string: "Aa", attributes: attrs)
let line = CTLineCreateWithAttributedString(t)
let tb = CTLineGetImageBounds(line, ctx)
ctx.textPosition = CGPoint(x: badge.midX - tb.width / 2 - tb.minX, y: badge.midY - tb.height / 2 - tb.minY)
let scale: CGFloat = 0.62
ctx.saveGState()
ctx.translateBy(x: badge.midX, y: badge.midY)
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: -badge.midX, y: -badge.midY)
CTLineDraw(line, ctx)
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
