import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (px, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = NSRect(x: s*0.1, y: s*0.1, width: s*0.8, height: s*0.8)
    let path = NSBezierPath(roundedRect: r, xRadius: s*0.18, yRadius: s*0.18)
    // Warm paper tile with a hairline edge.
    NSColor(srgbRed: 0.975, green: 0.955, blue: 0.92, alpha: 1).setFill(); path.fill()
    NSColor(srgbRed: 0.84, green: 0.81, blue: 0.76, alpha: 1).setStroke(); path.lineWidth = max(1, s*0.006); path.stroke()
    // A 3x3 floor plan of rooms: most filled coral, one green (freed), two empty.
    let coral = NSColor(srgbRed: 0.855, green: 0.33, blue: 0.20, alpha: 1)
    let green = NSColor(srgbRed: 0.20, green: 0.53, blue: 0.38, alpha: 1)
    let empty = NSColor(srgbRed: 0.90, green: 0.88, blue: 0.84, alpha: 1)
    let fills = [coral, coral, coral, coral, coral, green, coral, empty, empty]
    let inset = s*0.22, gap = s*0.035
    let cell = (s - inset*2 - gap*2) / 3
    for i in 0..<9 {
        let col = CGFloat(i % 3), row = CGFloat(2 - i / 3)
        let b = NSRect(x: inset + col*(cell+gap), y: inset + row*(cell+gap), width: cell, height: cell)
        fills[i].setFill()
        NSBezierPath(roundedRect: b, xRadius: cell*0.22, yRadius: cell*0.22).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
