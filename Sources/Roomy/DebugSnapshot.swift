import AppKit
import SwiftUI

/// For checking the UI without Screen Recording permission:
/// `ROOMY_SNAPSHOT=/tmp/out ROOMY_ROOM=storage ROOMY_QUIT=1 .build/release/Roomy`
/// writes the main window as a PNG into that folder.
enum DebugSnapshot {
    @MainActor
    static func scheduleIfAsked(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["ROOMY_SNAPSHOT"] else { return }
        if let r = env["ROOMY_ROOM"].flatMap(Room.init(rawValue:)) { model.room = r }
        if let t = env["ROOMY_STORAGE"].flatMap(StorageTab.init(rawValue:)) { model.storageTab = t }
        if env["ROOMY_DARK"] == "1" { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if env["ROOMY_SEARCH"] == "1" { model.showSearch = true }
        if env["ROOMY_RESCAN"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { model.startScan() } }
        if env["ROOMY_DUPES"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { model.findDuplicates() } }
        let delay = Double(env["ROOMY_DELAY"] ?? "") ?? 6
        var menu: NSWindow?
        if env["ROOMY_MENU"] == "1" {
            let mon = SystemMonitor()
            let view = MonitorView().environment(model).environment(mon).environment(KeepAwake())
            let host = NSHostingView(rootView: view)
            host.frame.size = host.fittingSize
            let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = host
            w.orderFront(nil)
            menu = w
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let out = URL(fileURLWithPath: dir)
            if let v = menu?.contentView {
                v.frame.size = v.fittingSize
                if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("menu.png"))
                }
            }
            for (i, w) in NSApp.windows.enumerated() where w.isVisible && w.level == .normal {
                guard let v = w.contentView, v.bounds.width > 300,
                      let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("window\(i).png"))
            }
            if env["ROOMY_QUIT"] == "1" { exit(0) }
        }
    }
}
