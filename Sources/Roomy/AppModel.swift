import SwiftUI
import AppKit

enum Room: String, CaseIterable, Identifiable {
    case home, clean, storage, apps, awake
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "Home"
        case .clean: "Clean Up"
        case .storage: "Storage"
        case .apps: "Apps"
        case .awake: "Keep Awake"
        }
    }
    var icon: String {
        switch self {
        case .home: "house"
        case .clean: "sparkles"
        case .storage: "square.grid.2x2"
        case .apps: "app.badge"
        case .awake: "cup.and.saucer"
        }
    }
}

enum StorageTab: String, CaseIterable {
    case folders = "Folders", large = "Large Files", types = "File Types", duplicates = "Duplicates", changes = "Changes"
}

struct Toast: Equatable {
    let id = UUID()
    let text: String
    var canUndo = false
}

struct Suggestion: Identifiable {
    enum Action { case cleanSafe, emptyTrash, openClean(String), openLarge }
    let id: String
    let title: String
    let detail: String
    let icon: String
    let bytes: Int64
    let button: String
    let action: Action
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
    var room: Room = .home
    var storageTab: StorageTab = .folders
    var volume = VolumeInfo.current() {
        didSet {
            guard volume != oldValue else { return }
            SpaceLog.record(free: volume.free)
            let f = Forecast.make(log: SpaceLog.load(), free: volume.free)
            if f != forecast { forecast = f }
        }
    }
    var forecast = Forecast.make(log: SpaceLog.load(), free: VolumeInfo.current().free)

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
    /// What grew, and how many very large files exist. Worked out off the main thread after each scan.
    var growth: (since: Date, rows: [Growth])?
    var bigFiles: (count: Int, bytes: Int64) = (0, 0)
    var fileTypes: [TypeGroup] = []
    var searchIndex: [(key: String, node: FileNode)] = []
    var showSearch = false

    // Duplicates
    var duplicates: [DuplicateGroup]?
    var findingDuplicates = false
    var duplicateProgress = 0.0
    private var duplicateRun = UUID()
    private var progress: ScanProgress?

    // Queue
    var queue: [QueueItem] = []
    var showReview = false
    var trashing = false
    var toast: Toast?
    private var lastTrashed: [(from: String, to: URL)] = []
    private var didAutoStart = false

    /// True when Roomy can read protected folders like the Trash.
    var hasFullDiskAccess = true

    // Trash
    var trashSize: Int64?
    var trashCount = 0

    // Clean
    var cleanResults: [String: [SizedItem]] = [:]
    var cleanLoading = false
    var cleanExpanded: Set<String> = []

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
    private var lastTrashCheck = Date.distantPast

    init() {
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshVolume()
        }
    }

    func refreshVolume() {
        let v = VolumeInfo.current()
        if v != volume { volume = v }
    }

    var menuBarText: String { fmt(volume.free) }

    func applyAppearance() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func flash(_ message: String, canUndo: Bool = false) {
        let t = Toast(text: message, canUndo: canUndo)
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + (canUndo ? 8 : 3.5)) { [weak self] in
            if self?.toast == t { self?.toast = nil }
        }
    }

    /// Opening the window: show the last results at once. Only look at the disk again when they're
    /// over a day old, and then quietly, with the old results staying on screen.
    func autoStart() {
        guard !didAutoStart else { return }
        didAutoStart = true
        snapshots.load { [weak self] in self?.updateInsights() }
        DispatchQueue.global(qos: .userInitiated).async {
            let saved = ScanCache.load()
            let clean = CleanCache.load()
            DispatchQueue.main.async {
                if let clean { self.cleanResults = clean.results }
                // Saved results are shown as they are; Roomy only looks again when you press Scan.
                if clean == nil { self.refreshClean() }
                guard let saved else {
                    self.startScan(NSHomeDirectory())
                    return
                }
                self.root = saved.root
                self.current = saved.root
                self.scanTarget = saved.root.path
                self.scanDate = saved.date
                self.treeVersion += 1
                self.updateInsights()
            }
        }
    }

    func updateInsights() {
        guard let root else { return }
        let items = snapshots.items
        DispatchQueue.global(qos: .utility).async {
            let grew = SnapshotStore.grewLately(in: items, root: root.path)
            var big: [FileNode] = []
            root.files(atLeast: 500_000_000, into: &big)
            let bytes = big.reduce(Int64(0)) { $0 + $1.size }
            let types = FileTypes.group(root)
            var index: [(key: String, node: FileNode)] = []
            func walk(_ n: FileNode) {
                for c in n.children where !c.isAggregate {
                    index.append((c.name.lowercased(), c))
                    if c.isDir { walk(c) }
                }
            }
            walk(root)
            index.sort { $0.node.size > $1.node.size }
            DispatchQueue.main.async {
                self.growth = grew
                self.bigFiles = (big.count, bytes)
                self.fileTypes = types
                self.searchIndex = index
            }
        }
    }

    // MARK: Duplicates

    func findDuplicates() {
        guard let root, !findingDuplicates else { return }
        let run = UUID()
        duplicateRun = run
        findingDuplicates = true
        duplicateProgress = 0
        DispatchQueue.global(qos: .utility).async {
            let cancelled = { DispatchQueue.main.sync { self.duplicateRun != run } }
            let found = Duplicates.find(root: root, isCancelled: cancelled) { p in
                DispatchQueue.main.async { self.duplicateProgress = p }
            }
            DispatchQueue.main.async {
                guard self.duplicateRun == run else { return }
                self.duplicates = found
                self.findingDuplicates = false
            }
        }
    }

    func cancelDuplicates() {
        duplicateRun = UUID()
        findingDuplicates = false
    }

    /// Keeps the newest copy, adds the rest to the clean list.
    func stageExtras(_ group: DuplicateGroup) {
        for f in group.files.dropFirst() { stage(path: f.path, name: f.name, size: f.size, source: "Duplicates") }
    }

    func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: Smart clean

    /// Categories that are safe to clear without looking: they only hold things that get rebuilt or downloaded again.
    static let smartCategories = ["caches", "logs", "derived", "simcaches", "pkgcaches", "toolcache", "installers"]

    var smartItems: [(category: CleanCategory, items: [SizedItem])] {
        Cleaners.all.filter { Self.smartCategories.contains($0.id) }.compactMap { c in
            let items = cleanResults[c.id] ?? []
            return items.isEmpty ? nil : (c, items)
        }
    }

    var smartBytes: Int64 {
        smartItems.reduce(0) { $0 + $1.items.reduce(0) { $0 + $1.size } }
    }

    /// Home's to-do list: everything worth doing about space right now, biggest first.
    var suggestions: [Suggestion] {
        var list: [Suggestion] = []
        let smart = smartItems
        if !smart.isEmpty {
            let count = smart.reduce(0) { $0 + $1.items.count }
            list.append(Suggestion(id: "smart", title: "Caches, logs and build files",
                                   detail: "\(count) items that rebuild themselves or are no longer needed",
                                   icon: "shippingbox", bytes: smartBytes, button: "Review", action: .cleanSafe))
        }
        if let t = trashSize, t > 0 {
            list.append(Suggestion(id: "trash", title: "Empty the Trash", detail: "In the Trash, but still taking up space",
                                   icon: "trash", bytes: t, button: "Empty", action: .emptyTrash))
        }
        for c in Cleaners.all where !Self.smartCategories.contains(c.id) {
            let bytes = (cleanResults[c.id] ?? []).reduce(Int64(0)) { $0 + $1.size }
            if bytes > 0 {
                list.append(Suggestion(id: c.id, title: c.title, detail: c.detail, icon: c.icon, bytes: bytes,
                                       button: "Look", action: .openClean(c.id)))
            }
        }
        if bigFiles.count > 0 {
            list.append(Suggestion(id: "big", title: "\(bigFiles.count) file\(bigFiles.count == 1 ? "" : "s") over 500 MB",
                                   detail: "Check whether you still need them", icon: "doc", bytes: bigFiles.bytes,
                                   button: "Look", action: .openLarge))
        }
        return list.sorted { $0.bytes > $1.bytes }
    }

    func run(_ action: Suggestion.Action) {
        switch action {
        case .cleanSafe: stageSmart()
        case .emptyTrash: break
        case .openClean(let id):
            cleanExpanded.insert(id)
            room = .clean
        case .openLarge:
            storageTab = .large
            room = .storage
        }
    }

    func stageSmart(review: Bool = true) {
        for (c, items) in smartItems {
            for i in items { stage(path: i.url.path, name: i.name, size: i.size, source: c.title) }
        }
        if review && !queue.isEmpty { showReview = true }
    }

    // MARK: Scan

    /// Results already on screen stay there until the new ones are ready. `quietly` runs at low priority.
    /// Set when someone chose to scan without Full Disk Access, so Roomy stops asking them about it.
    var scanLimited = UserDefaults.standard.bool(forKey: "scan.limited") {
        didSet { UserDefaults.standard.set(scanLimited, forKey: "scan.limited") }
    }
    /// True while Roomy is waiting for Full Disk Access to be switched on.
    var showAccess = false

    /// Without Full Disk Access a scan of your files would set off one macOS prompt per folder,
    /// so it waits for that access unless you've chosen to scan without it.
    func startScan(_ path: String? = nil, quietly: Bool = false) {
        if !FullDiskAccess.granted && !scanLimited && !isPicked(path ?? scanTarget) {
            if let path { scanTarget = path }
            showAccess = true
            return
        }
        runScan(path, quietly: quietly)
    }

    /// A folder chosen in the open panel is one macOS already let the user pick, so it never prompts.
    private var pickedFolders: Set<String> = []
    func scanPicked(_ path: String) { pickedFolders.insert(path); runScan(path) }
    private func isPicked(_ path: String?) -> Bool { path.map(pickedFolders.contains) ?? false }

    /// Called once access is on, or when someone chooses to go without it.
    func accessSettled(limited: Bool) {
        if limited { scanLimited = true }
        hasFullDiskAccess = FullDiskAccess.granted
        showAccess = false
        cleanResults = [:]
        refreshTrash()
        runScan(nil)
    }

    private func runScan(_ path: String? = nil, quietly: Bool = false) {
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
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            let s = prog.snapshot
            self?.scanFiles = s.files
            self?.scanBytes = s.bytes
            self?.scanCurrent = s.current
        }
        DispatchQueue.global(qos: quietly ? .utility : .userInitiated).async {
            let node = Scanner(progress: prog).scan(path: target)
            if !prog.cancelled { ScanCache.save(node) }
            DispatchQueue.main.async {
                timer.invalidate()
                self.scanning = false
                guard !prog.cancelled else { return }
                let here = self.current?.path
                self.root = node
                self.current = here.flatMap(node.find) ?? node
                self.scanDate = Date()
                self.scanDuration = Date().timeIntervalSince(start)
                self.treeVersion += 1
                self.duplicates = nil
                self.refreshVolume()
                self.refreshClean()
                self.updateInsights()
                if self.autoSnapshot { self.snapshots.saveIfDue(from: node) { [weak self] in self?.updateInsights() } }
            }
        }
    }

    func cancelScan() { progress?.cancelled = true }

    func open(_ node: FileNode) {
        current = node
        storageTab = .folders
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
            var moved: [(from: String, to: URL)] = []
            for it in items {
                do {
                    var out: NSURL?
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: it.path), resultingItemURL: &out)
                    if let out { moved.append((it.path, out as URL)) }
                    ok.append(it)
                } catch {
                    failed.append(it.name)
                }
            }
            if emptyAfter { Self.emptyTrashSync() }
            DispatchQueue.main.async {
                self.trashing = false
                self.lastTrashed = emptyAfter ? [] : moved
                let okPaths = Set(ok.map(\.path))
                self.queue.removeAll { okPaths.contains($0.path) }
                for it in ok { self.removeFromTree(it.path) }
                self.treeVersion += 1
                self.pruneClean(okPaths)
                self.saveTree()
                self.updateInsights()
                self.duplicates = self.duplicates?.compactMap { g in
                    let left = g.files.filter { !okPaths.contains($0.path) }
                    return left.count > 1 ? DuplicateGroup(id: g.id, size: g.size, files: left) : nil
                }
                self.refreshVolume()
                self.refreshTrash()
                let freed = ok.reduce(0) { $0 + $1.size }
                var msg = emptyAfter ? "Deleted \(ok.count) items, \(fmt(freed)) freed" : "Moved \(ok.count) items (\(fmt(freed))) to the Trash"
                if !failed.isEmpty { msg += ". \(failed.count) couldn't be moved: " + failed.prefix(3).joined(separator: ", ") }
                self.flash(msg, canUndo: !emptyAfter && !moved.isEmpty)
                done()
            }
        }
    }

    func undoTrash() {
        let moves = lastTrashed
        lastTrashed = []
        toast = nil
        var restored = 0
        for m in moves {
            do {
                try FileManager.default.createDirectory(at: URL(fileURLWithPath: m.from).deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: m.to, to: URL(fileURLWithPath: m.from))
                restored += 1
            } catch {}
        }
        refreshVolume()
        refreshTrash()
        cleanResults = [:]
        refreshClean()
        flash(restored == moves.count ? "Put back \(restored) items. Rescan to see them in Storage." : "Put back \(restored) of \(moves.count) items. The rest are still in the Trash.")
    }

    /// After a clean, so the saved results match what's left.
    private func saveTree() {
        guard let root else { return }
        let results = cleanResults
        DispatchQueue.global(qos: .utility).async {
            ScanCache.save(root, date: self.scanDate ?? Date())
            CleanCache.save(results)
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

    /// `force` is for after something changed the Trash. Otherwise at most once a minute, since it walks every file in there.
    func refreshTrash(force: Bool = true) {
        guard force || Date().timeIntervalSince(lastTrashCheck) > 60 else { return }
        lastTrashCheck = Date()
        DispatchQueue.global(qos: .utility).async {
            let items = try? FileManager.default.contentsOfDirectory(at: Self.trashURL, includingPropertiesForKeys: nil)
            let size = items?.reduce(Int64(0)) { $0 + Sizer.size(of: $1) }
            let full = FullDiskAccess.granted
            DispatchQueue.main.async {
                if self.trashSize != size { self.trashSize = size }
                if self.trashCount != items?.count ?? 0 { self.trashCount = items?.count ?? 0 }
                if self.hasFullDiskAccess != full { self.hasFullDiskAccess = full }
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
                self.refreshVolume()
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
        let full = FullDiskAccess.granted
        DispatchQueue.global(qos: .utility).async {
            var res: [String: [SizedItem]] = [:]
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: cats.count) { i in
                let c = cats[i]
                let items = (!full && Cleaners.needAccess.contains(c.id) ? [] : c.resolve())
                    .map { SizedItem(url: $0, size: Sizer.size(of: $0), name: c.name($0)) }
                    .filter { $0.size > 0 && !Safety.isProtected($0.url.path) }
                    .sorted { $0.size > $1.size }
                lock.lock(); res[c.id] = items; lock.unlock()
            }
            CleanCache.save(res)
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
