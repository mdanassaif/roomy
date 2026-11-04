import AppKit

// Roomy's icon: a room with space left in it.
let ink = NSColor(srgbRed: 0.075, green: 0.078, blue: 0.095, alpha: 1)
let accent = NSColor(srgbRed: 0.33, green: 0.36, blue: 0.86, alpha: 1)

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (px, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: s*0.1, y: s*0.1, width: s*0.8, height: s*0.8), xRadius: s*0.18, yRadius: s*0.18).fill()
    let frame = NSBezierPath(roundedRect: NSRect(x: s*0.27, y: s*0.27, width: s*0.46, height: s*0.46), xRadius: s*0.07, yRadius: s*0.07)
    frame.lineWidth = s*0.04
    NSColor.white.setStroke()
    frame.stroke()
    accent.setFill()
    NSBezierPath(roundedRect: NSRect(x: s*0.325, y: s*0.325, width: s*0.35, height: s*0.15), xRadius: s*0.03, yRadius: s*0.03).fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
