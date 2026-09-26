import SwiftUI
import AppKit

enum Room: String, CaseIterable, Identifiable {
    case overview, storage, clean, large, apps, snapshots
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .storage: "Storage"
        case .clean: "Quick Clean"
        case .large: "Large Files"
        case .apps: "Applications"
        case .snapshots: "Snapshots"
        }
    }
    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .storage: "square.grid.3x3.square"
        case .clean: "sparkles"
        case .large: "doc.badge.ellipsis"
        case .apps: "app.badge"
        case .snapshots: "camera.aperture"
        }
    }
    var color: Color {
        switch self {
        case .overview: .blue
        case .storage: .purple
        case .clean: .green
        case .large: .orange
        case .apps: .pink
        case .snapshots: .teal
        }
    }
}

struct QueueItem: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let size: Int64
    let source: String
}

@Observable
final class AppModel {
    var room: Room = .overview
    var volume = VolumeInfo.current()

    // Scan
    var root: FileNode?
    var current: FileNode?
    var scanTarget = NSHomeDirectory()
    var scanning = false
    var scanFiles = 0
    var scanBytes: Int64 = 0
    var scanCurrent = ""
    var scanDate: Date?
    var scanDuration: TimeInterval = 0
    var treeVersion = 0
    private var progress: ScanProgress?

    // Queue
    var queue: [QueueItem] = []
    var showReview = false
    var trashing = false
    var toast: String?

    // Trash
    var trashSize: Int64?
    var trashCount = 0

    // Clean
    var cleanResults: [String: [SizedItem]] = [:]
    var cleanLoading = false

    // Apps
    var apps: [AppInfo] = []
    var appsLoading = false
    var sizingApps = false
    var sparkleUpdates: [AppInfo] = []
    var brewOutdated: [BrewItem] = []
    var checkingUpdates = false
    var lastUpdateCheck: Date?
    var startup: [StartupItem] = []
    var busy: Set<String> = []

    let snapshots = SnapshotStore()

    var autoSnapshot: Bool = UserDefaults.standard.object(forKey: "autoSnapshot") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSnapshot, forKey: "autoSnapshot") }
    }
    var appearance: String = UserDefaults.standard.string(forKey: "appearance") ?? "system" {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance"); applyAppearance() }
    }

    private var volumeTimer: Timer?

    init() {
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.volume = .current()
        }
    }

    var menuBarText: String { fmt(volume.free) }

    func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func flash(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            if self?.toast == message { self?.toast = nil }
        }
    }

    // MARK: Scan

    func startScan(_ path: String? = nil) {
        if let path { scanTarget = path }
        guard !scanning else { return }
        scanning = true
        scanFiles = 0
        scanBytes = 0
        scanCurrent = ""
        let prog = ScanProgress()
        progress = prog
        let target = scanTarget
        let start = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            let s = prog.snapshot
            self?.scanFiles = s.files
            self?.scanBytes = s.bytes
            self?.scanCurrent = s.current
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let node = Scanner(progress: prog).scan(path: target)
            DispatchQueue.main.async {
                timer.invalidate()
                self.scanning = false
                guard !prog.cancelled else { return }
                self.root = node
                self.current = node
                self.scanDate = Date()
                self.scanDuration = Date().timeIntervalSince(start)
                self.treeVersion += 1
                self.volume = .current()
                if self.autoSnapshot { self.snapshots.save(from: node) }
            }
        }
    }

    func cancelScan() { progress?.cancelled = true }

    func open(_ node: FileNode) {
        current = node
        room = .storage
    }

    // MARK: Queue

    func isQueued(_ path: String) -> Bool { queue.contains { $0.path == path } }

    func isCovered(_ path: String) -> Bool {
        queue.contains { path.hasPrefix($0.path + "/") }
    }

    var queuedBytes: Int64 { queue.reduce(0) { $0 + $1.size } }

    func stage(path: String, name: String, size: Int64, source: String) {
        guard !Safety.isProtected(path) else { flash("\(name) is protected and can't be removed"); return }
        guard !isQueued(path), !isCovered(path) else { return }
        queue.removeAll { $0.path.hasPrefix(path + "/") }
        queue.append(QueueItem(path: path, name: name, size: size, source: source))
    }

    func stage(_ node: FileNode, source: String = "Storage") {
        guard !node.isAggregate else { return }
        stage(path: node.path, name: node.name, size: node.size, source: source)
    }

    func toggle(path: String, name: String, size: Int64, source: String) {
        if isQueued(path) { unstage(path) } else { stage(path: path, name: name, size: size, source: source) }
    }

    func unstage(_ path: String) { queue.removeAll { $0.path == path } }

    func trashQueue(emptyAfter: Bool, done: @escaping () -> Void) {
        let items = queue
        trashing = true
        DispatchQueue.global(qos: .userInitiated).async {
            var ok: [QueueItem] = []
            var failed: [String] = []
            for it in items {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: it.path), resultingItemURL: nil)
                    ok.append(it)
                } catch {
                    failed.append(it.name)
                }
            }
            if emptyAfter { Self.emptyTrashSync() }
            DispatchQueue.main.async {
                self.trashing = false
                let okPaths = Set(ok.map(\.path))
                self.queue.removeAll { okPaths.contains($0.path) }
                for it in ok { self.removeFromTree(it.path) }
                self.treeVersion += 1
                self.pruneClean(okPaths)
                self.volume = .current()
                self.refreshTrash()
                let freed = ok.reduce(0) { $0 + $1.size }
                var msg = emptyAfter ? "Deleted \(ok.count) items, \(fmt(freed)) freed" : "Moved \(ok.count) items (\(fmt(freed))) to the Trash"
                if !failed.isEmpty { msg += ". \(failed.count) couldn't be moved: " + failed.prefix(3).joined(separator: ", ") }
                self.flash(msg)
                done()
            }
        }
    }

    private func removeFromTree(_ path: String) {
        guard let root, let n = root.find(path), let p = n.parent else { return }
        p.remove(n)
        if let c = current, c.path == path || c.path.hasPrefix(path + "/") { current = p }
    }

    private func pruneClean(_ paths: Set<String>) {
        for k in cleanResults.keys { cleanResults[k]?.removeAll { paths.contains($0.url.path) } }
        apps.removeAll { paths.contains($0.path) }
    }

    // MARK: Trash

    static let trashURL = URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")

    func refreshTrash() {
        DispatchQueue.global(qos: .utility).async {
            let items = try? FileManager.default.contentsOfDirectory(at: Self.trashURL, includingPropertiesForKeys: nil)
            let size = items?.reduce(Int64(0)) { $0 + Sizer.size(of: $1) }
            DispatchQueue.main.async {
                self.trashSize = size
                self.trashCount = items?.count ?? 0
            }
        }
    }

    @discardableResult
    static func emptyTrashSync() -> Bool {
        var allOK = true
        if let items = try? FileManager.default.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil) {
            for i in items {
                do { try FileManager.default.removeItem(at: i) } catch { allOK = false }
            }
        } else {
            allOK = false
        }
        if !allOK {
            // Without Full Disk Access, ask Finder to do it.
            return Shell.osascript("tell application \"Finder\" to empty trash").status == 0
        }
        return true
    }

    func emptyTrash() {
        let before = volume.free
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Self.emptyTrashSync()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.volume = .current()
                self.refreshTrash()
                let gained = self.volume.free - before
                self.flash(ok ? "Trash emptied" + (gained > 0 ? ", \(fmt(gained)) freed" : "") : "Couldn't empty the Trash")
            }
        }
    }

    // MARK: Clean

    func refreshClean() {
        guard !cleanLoading else { return }
        cleanLoading = true
        refreshTrash()
        let cats = Cleaners.all
        DispatchQueue.global(qos: .userInitiated).async {
            var res: [String: [SizedItem]] = [:]
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: cats.count) { i in
                let c = cats[i]
                let items = c.resolve()
                    .map { SizedItem(url: $0, size: Sizer.size(of: $0), name: c.name($0)) }
                    .filter { $0.size > 0 && !Safety.isProtected($0.url.path) }
                    .sorted { $0.size > $1.size }
                lock.lock(); res[c.id] = items; lock.unlock()
            }
            DispatchQueue.main.async {
                self.cleanResults = res
                self.cleanLoading = false
            }
        }
    }

    // MARK: Apps

    func loadApps() {
        guard !appsLoading else { return }
        appsLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let list = AppScanner.list()
            DispatchQueue.main.async {
                self.apps = list
                self.appsLoading = false
                self.sizingApps = true
            }
            var sizes: [String: Int64] = [:]
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: list.count) { i in
                let s = Sizer.size(of: URL(fileURLWithPath: list[i].path))
                lock.lock(); sizes[list[i].path] = s; lock.unlock()
            }
            DispatchQueue.main.async {
                for i in self.apps.indices { self.apps[i].size = sizes[self.apps[i].path] }
                self.sizingApps = false
            }
        }
    }

    func checkUpdates() {
        guard !checkingUpdates else { return }
        checkingUpdates = true
        let known = apps
        Task.detached(priority: .userInitiated) {
            let list = known.isEmpty ? AppScanner.list() : known
            async let brew = Task.detached { AppScanner.brewOutdated() }.value
            var found: [AppInfo] = []
            await withTaskGroup(of: AppInfo?.self) { g in
                for a in list where a.feedURL != nil && !a.isAppStore {
                    g.addTask { await AppScanner.checkSparkle(a) }
                }
                for await r in g { if let r { found.append(r) } }
            }
            let b = await brew
            let result = found
            await MainActor.run {
                self.sparkleUpdates = result.sorted { $0.name < $1.name }
                self.brewOutdated = b
                self.checkingUpdates = false
                self.lastUpdateCheck = Date()
            }
        }
    }

    func upgrade(_ item: BrewItem) {
        busy.insert(item.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = AppScanner.brewUpgrade(item)
            DispatchQueue.main.async {
                self.busy.remove(item.id)
                if ok {
                    self.brewOutdated.removeAll { $0.id == item.id }
                    self.flash("Updated \(item.name) to \(item.current)")
                } else {
                    self.flash("Couldn't update \(item.name). It may need your password; try Terminal.")
                }
            }
        }
    }

    func upgradeInTerminal(_ item: BrewItem) {
        let cmd = "brew upgrade \(item.isCask ? "--cask" : "--formula") \(item.name)"
        Shell.osascript("tell application \"Terminal\" to activate\ntell application \"Terminal\" to do script \"\(cmd)\"")
    }

    func stageUninstall(_ app: AppInfo) {
        guard !app.bundleID.hasPrefix("com.apple.") else { flash("Apple apps can't be removed here"); return }
        stage(path: app.path, name: app.name, size: app.size ?? 0, source: "Uninstall")
        for u in AppScanner.leftovers(for: app) {
            stage(path: u.path, name: "\(app.name): \(u.lastPathComponent)", size: Sizer.size(of: u), source: "Uninstall")
        }
    }

    func loadStartup() {
        DispatchQueue.global(qos: .userInitiated).async {
            let items = Startup.load()
            DispatchQueue.main.async { self.startup = items }
        }
    }

    func setStartup(_ item: StartupItem, _ on: Bool) {
        busy.insert(item.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = Startup.setEnabled(item, on)
            DispatchQueue.main.async {
                self.busy.remove(item.id)
                if ok {
                    if item.kind == .loginItem { self.startup.removeAll { $0.id == item.id } }
                    else if let i = self.startup.firstIndex(where: { $0.id == item.id }) { self.startup[i].enabled = on }
                } else {
                    self.flash("Couldn't change \(item.name)")
                }
            }
        }
    }
}
