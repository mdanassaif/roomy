import Foundation

private var roomyFolder: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Roomy", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

/// The last scan, kept on disk so opening Roomy shows results straight away instead of walking the disk again.
/// A flat binary file: millions of files reduce to a tree small enough to read in a moment.
enum ScanCache {
    private static let magic: UInt32 = 0x524D_5932
    static var url: URL { roomyFolder.appendingPathComponent("LastScan.bin") }

    static func save(_ root: FileNode, date: Date = Date()) {
        var d = Data()
        d.reserveCapacity(1 << 20)
        put(magic, &d)
        put(date.timeIntervalSince1970, &d)
        put(root.path, &d)
        write(root, &d)
        try? d.write(to: url, options: .atomic)
    }

    static func load() -> (root: FileNode, date: Date)? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return data.withUnsafeBytes { raw -> (FileNode, Date)? in
            var r = Reader(bytes: raw)
            guard r.read(UInt32.self) == magic, let time = r.read(Double.self), let path = r.string(),
                  let root = r.node(path: path) else { return nil }
            return (root, Date(timeIntervalSince1970: time))
        }
    }

    private static func put<T>(_ v: T, _ d: inout Data) {
        withUnsafeBytes(of: v) { d.append(contentsOf: $0) }
    }

    private static func put(_ s: String, _ d: inout Data) {
        let bytes = Data(s.utf8)
        put(UInt32(bytes.count), &d)
        d.append(bytes)
    }

    private static func write(_ n: FileNode, _ d: inout Data) {
        put(UInt8((n.isDir ? 1 : 0) | (n.isAggregate ? 2 : 0)), &d)
        put(n.size, &d)
        put(Int64(n.items), &d)
        put(n.modified?.timeIntervalSince1970 ?? 0, &d)
        put(n.name, &d)
        put(UInt32(n.children.count), &d)
        for c in n.children { write(c, &d) }
    }

    private struct Reader {
        let bytes: UnsafeRawBufferPointer
        var at = 0

        mutating func read<T>(_: T.Type) -> T? {
            guard at + MemoryLayout<T>.size <= bytes.count else { return nil }
            defer { at += MemoryLayout<T>.size }
            return bytes.loadUnaligned(fromByteOffset: at, as: T.self)
        }

        mutating func string() -> String? {
            guard let n = read(UInt32.self), at + Int(n) <= bytes.count else { return nil }
            defer { at += Int(n) }
            return String(decoding: bytes[at..<at + Int(n)], as: UTF8.self)
        }

        mutating func node(path: String) -> FileNode? {
            guard let flags = read(UInt8.self), let size = read(Int64.self), let items = read(Int64.self),
                  let modified = read(Double.self), let name = string(), let count = read(UInt32.self) else { return nil }
            let n = FileNode(name: name, path: path, isDir: flags & 1 != 0, isAggregate: flags & 2 != 0, size: size, items: Int(items))
            if modified > 0 { n.modified = Date(timeIntervalSince1970: modified) }
            n.children.reserveCapacity(Int(min(count, 4096)))
            for _ in 0..<count {
                // Peek past the fixed fields for this child's own name to build its path.
                let start = at
                guard read(UInt8.self) != nil, read(Int64.self) != nil, read(Int64.self) != nil, read(Double.self) != nil,
                      let childName = string() else { return nil }
                let aggregate = bytes[start] & 2 != 0
                at = start
                let base = path == "/" ? "" : path
                guard let c = node(path: base + "/" + (aggregate ? "·smaller" : childName)) else { return nil }
                c.parent = n
                n.children.append(c)
            }
            return n
        }
    }
}

/// What Clean Up found last time, so Home can say what's worth clearing the moment it opens.
enum CleanCache {
    private struct Entry: Codable { let path: String; let size: Int64; let name: String }
    private struct File: Codable { let date: Date; let results: [String: [Entry]] }
    private static var url: URL { roomyFolder.appendingPathComponent("LastClean.json") }

    static func save(_ results: [String: [SizedItem]]) {
        let file = File(date: Date(), results: results.mapValues { $0.map { Entry(path: $0.url.path, size: $0.size, name: $0.name) } })
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: url, options: .atomic) }
    }

    static func load() -> (results: [String: [SizedItem]], date: Date)? {
        guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let results = file.results.mapValues { $0.map { SizedItem(url: URL(fileURLWithPath: $0.path), size: $0.size, name: $0.name) } }
        return (results, file.date)
    }
}
