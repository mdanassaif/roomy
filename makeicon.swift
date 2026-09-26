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
    NSGradient(colors: [NSColor(calibratedRed: 0.35, green: 0.3, blue: 0.95, alpha: 1), NSColor(calibratedRed: 0.1, green: 0.75, blue: 0.6, alpha: 1)])!.draw(in: path, angle: -60)
    let cfg = NSImage.SymbolConfiguration(pointSize: s*0.4, weight: .semibold).applying(.init(paletteColors: [.white]))
    if let img = NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let sz = img.size
        img.draw(in: NSRect(x: (s - sz.width)/2, y: (s - sz.height)/2, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
