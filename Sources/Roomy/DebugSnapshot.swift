import AppKit

/// For checking the UI without Screen Recording permission:
/// `ROOMY_SNAPSHOT=/tmp/out ROOMY_ROOM=storage ROOMY_NOTCH=1 ROOMY_QUIT=1 .build/release/Roomy`
/// writes the main window (and, with ROOMY_NOTCH, the notch states) as PNGs into that folder.
enum DebugSnapshot {
    @MainActor
    static func scheduleIfAsked(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["ROOMY_SNAPSHOT"] else { return }
        if let r = env["ROOMY_ROOM"].flatMap(Room.init(rawValue:)) { model.room = r }
        let delay = Double(env["ROOMY_DELAY"] ?? "") ?? 6
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let out = URL(fileURLWithPath: dir)
            for (i, w) in NSApp.windows.enumerated() where w.isVisible && w.level == .normal {
                guard let v = w.contentView, v.bounds.width > 300,
                      let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("window\(i).png"))
            }
            if env["ROOMY_NOTCH"] == "1" {
                let caches = NSHomeDirectory() + "/Library/Caches"
                let sample = NotchState.Measured(name: "Caches", items: [.init(path: caches, name: "Caches", size: 1_840_000_000)])
                let modes: [(String, NotchState.Mode)] = [("overview", .overview), ("drop", .dropHere), ("measured", .measured(sample)), ("added", .added(1_840_000_000))]
                for (name, mode) in modes {
                    if let img = NotchController.shared.debugImage(mode: mode), let tiff = img.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: out.appendingPathComponent("notch-\(name).png"))
                    }
                }
            }
            if env["ROOMY_QUIT"] == "1" { NSApp.terminate(nil) }
        }
    }
}
