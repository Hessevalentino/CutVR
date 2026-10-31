// Generates Icon/AppIcon.icns: black squircle, VR goggles pictogram, two crossed bones below.
// Usage: swift Icon/make_icon.swift
import AppKit

let S: CGFloat = 1024

func drawIcon(_ ctx: CGContext) {
    // Coordinates are top-down for readability.
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: 824 px body, ~185 px corner radius
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [CGColor(gray: 0.13, alpha: 1), CGColor(gray: 0.0, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    ctx.restoreGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); ctx.setLineWidth(3); ctx.strokePath()

    let fg = CGColor(gray: 0.94, alpha: 1)
    let black = CGColor(gray: 0.04, alpha: 1)

    // --- VR goggles ---
    let cx: CGFloat = 512, gy: CGFloat = 400
    let gw: CGFloat = 500, gh: CGFloat = 250
    // strap
    ctx.setFillColor(fg)
    ctx.fill(CGRect(x: cx - gw / 2 - 52, y: gy - 30, width: gw + 104, height: 60))
    // body
    let goggles = CGPath(roundedRect: CGRect(x: cx - gw / 2, y: gy - gh / 2, width: gw, height: gh),
                         cornerWidth: 95, cornerHeight: 95, transform: nil)
    ctx.addPath(goggles)
    ctx.fillPath()
    // lenses
    ctx.setFillColor(black)
    for dx in [-1.0, 1.0] as [CGFloat] {
        let lens = CGRect(x: cx + dx * 118 - 92, y: gy - 66, width: 184, height: 122)
        ctx.addPath(CGPath(roundedRect: lens, cornerWidth: 58, cornerHeight: 58, transform: nil))
    }
    ctx.fillPath()
    // nose notch, cut out of the goggles body only
    ctx.saveGState()
    ctx.addPath(goggles); ctx.clip()
    ctx.addEllipse(in: CGRect(x: cx - 66, y: gy + gh / 2 - 62, width: 132, height: 132)); ctx.clip()
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    ctx.restoreGState()

    // --- crossed bones ---
    func bone(angle: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: cx, y: 720)
        ctx.rotate(by: angle)
        let len: CGFloat = 400, shaft: CGFloat = 46, knob: CGFloat = 36
        ctx.setFillColor(fg)
        ctx.addPath(CGPath(roundedRect: CGRect(x: -len / 2, y: -shaft / 2, width: len, height: shaft),
                           cornerWidth: shaft / 2, cornerHeight: shaft / 2, transform: nil))
        for ex in [-len / 2, len / 2] {
            for ey in [-knob * 0.82, knob * 0.82] {
                ctx.addEllipse(in: CGRect(x: ex - knob, y: ey - knob, width: knob * 2, height: knob * 2))
            }
        }
        ctx.fillPath()
        ctx.restoreGState()
    }
    // Thin black outline between the bones so the crossing reads clearly.
    bone(angle: .pi / 6.5)
    ctx.saveGState()
    ctx.translateBy(x: cx, y: 720); ctx.rotate(by: -.pi / 6.5)
    ctx.setFillColor(black)
    ctx.addPath(CGPath(roundedRect: CGRect(x: -150, y: -35, width: 300, height: 70), cornerWidth: 35, cornerHeight: 35, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    bone(angle: -.pi / 6.5)
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = gc.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / S, y: CGFloat(size) / S)
    drawIcon(ctx)
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = dir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("Hotovo: \(dir.appendingPathComponent("AppIcon.icns").path)")
