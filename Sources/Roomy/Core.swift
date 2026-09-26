import Foundation
import AppKit

func fmt(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
}

// MARK: - Shell

enum Shell {
    static let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    @discardableResult
    static func run(_ launch: String, _ args: [String]) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = path
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    static func osascript(_ source: String) -> (status: Int32, out: String) {
        run("/usr/bin/osascript", ["-e", source])
    }

    static var brew: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Volume

struct VolumeInfo: Equatable {
    var total: Int64 = 0
    var free: Int64 = 0
    var used: Int64 { max(0, total - free) }

    static func current(_ path: String = "/") -> VolumeInfo {
        let url = URL(fileURLWithPath: path)
        let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        let free = v?.volumeAvailableCapacityForImportantUsage ?? Int64(v?.volumeAvailableCapacity ?? 0)
        return VolumeInfo(total: total, free: free)
    }
}

// MARK: - Safety

enum Safety {
    static let home = NSHomeDirectory()
    static let exact: Set<String> = [
        "/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin", "/private",
        "/var", "/etc", "/opt", "/cores", "/tmp", "/Volumes",
        home, home + "/Library", home + "/Desktop", home + "/Documents", home + "/Downloads",
        home + "/Applications", home + "/Pictures", home + "/Movies", home + "/Music", home + "/.Trash",
        home + "/Library/Caches", home + "/Library/Application Support", home + "/Library/Preferences",
        home + "/Library/Containers", home + "/Library/Mobile Documents",
    ]

    static func isProtected(_ p: String) -> Bool {
        if exact.contains(p) { return true }
        if p.hasPrefix("/System/") || p.hasPrefix("/bin/") || p.hasPrefix("/sbin/") { return true }
        if p.hasPrefix("/usr/") && !p.hasPrefix("/usr/local/") { return true }
        if p.hasPrefix("/private/var/db/") || p.hasPrefix("/private/var/vm") { return true }
        if p.hasPrefix(Bundle.main.bundlePath) { return true }
        return false
    }
}

// MARK: - Sizing

enum Sizer {
    static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    static func size(of url: URL) -> Int64 {
        guard let rv = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        if rv.isSymbolicLink == true { return 0 }
        if rv.isDirectory != true { return Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        while let f = e?.nextObject() as? URL {
            if let v = try? f.resourceValues(forKeys: Set(keys)), v.isDirectory != true, v.isSymbolicLink != true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

// MARK: - File tree

final class FileNode: Identifiable, Hashable {
    let name: String
    let path: String
    let isDir: Bool
    let isAggregate: Bool
    var size: Int64
    var items: Int
    var modified: Date?
    var children: [FileNode] = []
    weak var parent: FileNode?

    init(name: String, path: String, isDir: Bool, isAggregate: Bool = false, size: Int64 = 0, items: Int = 0) {
        self.name = name
        self.path = path
        self.isDir = isDir
        self.isAggregate = isAggregate
        self.size = size
        self.items = items
    }

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    static func == (a: FileNode, b: FileNode) -> Bool { a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    var chain: [FileNode] {
        var out: [FileNode] = [self]
        var p = parent
        while let n = p { out.insert(n, at: 0); p = n.parent }
        return out
    }

    func find(_ p: String) -> FileNode? {
        if p == path { return self }
        guard isDir, p.hasPrefix(path == "/" ? "/" : path + "/") else { return nil }
        for c in children { if let f = c.find(p) { return f } }
        return nil
    }

    func remove(_ child: FileNode) {
        children.removeAll { $0 === child }
        var p: FileNode? = self
        while let n = p {
            n.size -= child.size
            n.items -= child.items
            p = n.parent
        }
    }

    func files(atLeast min: Int64, into out: inout [FileNode]) {
        for c in children {
            if c.isDir { if c.size >= min { c.files(atLeast: min, into: &out) } }
            else if !c.isAggregate && c.size >= min { out.append(c) }
        }
    }
}

// MARK: - Scanner

final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var files = 0
    private var bytes: Int64 = 0
    private var current = ""
    private var _cancelled = false

    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); _cancelled = newValue; lock.unlock() }
    }

    func add(files f: Int, bytes b: Int64, current c: String) {
        lock.lock(); files += f; bytes += b; current = c; lock.unlock()
    }

    var snapshot: (files: Int, bytes: Int64, current: String) {
        lock.lock(); defer { lock.unlock() }
        return (files, bytes, current)
    }
}

struct Scanner {
    static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
    static let keySet = Set(keys)
    // Firmlinks and other mounts that would double count when scanning "/"
    static let skip: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/Network"]
    static let keepThreshold: Int64 = 1_000_000

    let progress: ScanProgress

    func scan(path: String) -> FileNode {
        let url = URL(fileURLWithPath: path)
        return scanDir(url, name: path == "/" ? "Macintosh HD" : url.lastPathComponent, depth: 0)
    }

    private func scanDir(_ url: URL, name: String, depth: Int) -> FileNode {
        let node = FileNode(name: name, path: url.path, isDir: true)
        guard !progress.cancelled,
              let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys, options: [])
        else { return node }

        var dirs: [URL] = []
        var files: [FileNode] = []
        var smallSize: Int64 = 0, smallCount = 0, bytes: Int64 = 0
        for item in items {
            guard let rv = try? item.resourceValues(forKeys: Self.keySet), rv.isSymbolicLink != true else { continue }
            if rv.isDirectory == true {
                if !Self.skip.contains(item.path) { dirs.append(item) }
                continue
            }
            let size = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
            bytes += size
            if size >= Self.keepThreshold {
                let f = FileNode(name: item.lastPathComponent, path: item.path, isDir: false, size: size, items: 1)
                f.modified = rv.contentModificationDate
                files.append(f)
            } else {
                smallSize += size
                smallCount += 1
            }
        }
        progress.add(files: items.count, bytes: bytes, current: url.path)

        var sub: [FileNode]
        if depth < 2 && dirs.count > 1 {
            var results = [FileNode?](repeating: nil, count: dirs.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: dirs.count) { i in
                let n = scanDir(dirs[i], name: dirs[i].lastPathComponent, depth: depth + 1)
                lock.lock(); results[i] = n; lock.unlock()
            }
            sub = results.compactMap { $0 }
        } else {
            sub = dirs.map { scanDir($0, name: $0.lastPathComponent, depth: depth + 1) }
        }

        var children = sub + files
        if smallCount > 0 {
            children.append(FileNode(name: "\(smallCount) smaller files", path: url.path + "/·smaller", isDir: false,
                                     isAggregate: true, size: smallSize, items: smallCount))
        }
        children.sort { $0.size > $1.size }
        for c in children { c.parent = node }
        node.children = children
        node.size = children.reduce(0) { $0 + $1.size }
        node.items = children.reduce(0) { $0 + $1.items }
        return node
    }
}

// MARK: - Snapshots

struct Snapshot: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var root: String
    var total: Int64
    var entries: [String: Int64]
}

struct DiffRow: Identifiable {
    enum Kind: String, CaseIterable { case all = "All", grew = "Grew", shrank = "Shrank", new = "New", gone = "Gone" }
    var id: String { path }
    let path: String
    let before: Int64?
    let after: Int64?
    var delta: Int64 { (after ?? 0) - (before ?? 0) }
    var kind: Kind {
        if before == nil { return .new }
        if after == nil { return .gone }
        return delta >= 0 ? .grew : .shrank
    }
}

@Observable
final class SnapshotStore {
    var items: [Snapshot] = []
    let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Roomy/Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder()
        items = files.filter { $0.pathExtension == "json" }
            .compactMap { try? dec.decode(Snapshot.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    func save(from node: FileNode) {
        var entries: [String: Int64] = [:]
        func walk(_ n: FileNode, depth: Int) {
            entries[n.path] = n.size
            guard depth < 5 else { return }
            for c in n.children {
                if c.isDir && c.size >= 5_000_000 { walk(c, depth: depth + 1) }
                else if !c.isDir && !c.isAggregate && c.size >= 100_000_000 { entries[c.path] = c.size }
            }
        }
        walk(node, depth: 0)
        let snap = Snapshot(id: UUID(), date: Date(), root: node.path, total: node.size, entries: entries)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: dir.appendingPathComponent(snap.id.uuidString + ".json"))
        }
        items.insert(snap, at: 0)
    }

    func delete(_ s: Snapshot) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(s.id.uuidString + ".json"))
        items.removeAll { $0.id == s.id }
    }

    static func diff(_ old: Snapshot, _ new: Snapshot, maxDepth: Int) -> [DiffRow] {
        let base = new.root == "/" ? 0 : new.root.split(separator: "/").count
        let keys = Set(old.entries.keys).union(new.entries.keys)
        return keys.compactMap { k -> DiffRow? in
            let depth = k.split(separator: "/").count - base
            guard depth >= 1, depth <= maxDepth else { return nil }
            let row = DiffRow(path: k, before: old.entries[k], after: new.entries[k])
            return abs(row.delta) >= 1_000_000 ? row : nil
        }
        .sorted { abs($0.delta) > abs($1.delta) }
    }
}
