import SwiftUI
import AppKit
import CryptoKit

// MARK: - Duplicates

struct DuplicateGroup: Identifiable {
    let id: String
    let size: Int64
    let files: [FileNode]
    /// What removing every copy but one would give back.
    var wasted: Int64 { size * Int64(files.count - 1) }
}

/// Finds identical files among the ones big enough to matter. Compared by contents, never by name.
enum Duplicates {
    static let minSize: Int64 = 5_000_000

    /// Copies in here belong to something else; removing one would break it, not save space.
    static func skip(_ path: String) -> Bool {
        path.contains(".app/") || path.contains("/node_modules/") || path.contains("/.git/")
            || path.contains("/Library/") || path.contains("/.Trash/") || path.hasPrefix("/System/")
            || path.contains(".dSYM/") || path.contains("/Build/Products/") || path.contains("/DerivedData/")
            || path.contains("/.build/") || path.contains("/.claude/") || path.contains("/target/debug/")
    }

    static func find(root: FileNode, isCancelled: () -> Bool, progress: (Double) -> Void) -> [DuplicateGroup] {
        var all: [FileNode] = []
        root.files(atLeast: minSize, into: &all)
        let bySize = Dictionary(grouping: all.filter { !skip($0.path) }, by: \.size).values.filter { $0.count > 1 }

        var groups: [DuplicateGroup] = []
        let total = bySize.count
        for (i, sameSize) in bySize.enumerated() {
            if isCancelled() { return [] }
            progress(Double(i) / Double(max(total, 1)))
            // A quick look at each end rules out most, so most files are never read in full.
            let quick = Dictionary(grouping: separateStorage(sameSize)) { ends($0.path) ?? UUID().uuidString }
            for candidates in quick.values where candidates.count > 1 {
                let full = Dictionary(grouping: candidates) { contents($0.path) ?? UUID().uuidString }
                for (hash, files) in full where files.count > 1 {
                    groups.append(DuplicateGroup(id: hash, size: files[0].size,
                                                 files: files.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    /// Files that share storage (APFS clones, hard links) count once: removing one of them frees nothing.
    private static func separateStorage(_ files: [FileNode]) -> [FileNode] {
        var seen = Set<String>()
        return files.filter { f in
            guard let v = try? URL(fileURLWithPath: f.path).resourceValues(forKeys: [.fileContentIdentifierKey, .fileResourceIdentifierKey]) else { return false }
            let id = v.fileContentIdentifier.map { "c\($0)" } ?? "\(String(describing: v.fileResourceIdentifier))"
            return seen.insert(id).inserted
        }
    }

    private static func hash(_ path: String, read: (FileHandle, inout SHA256) throws -> Void) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        var sha = SHA256()
        do { try read(h, &sha) } catch { return nil }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func ends(_ path: String) -> String? {
        hash(path) { h, sha in
            let chunk = 64 * 1024
            if let d = try h.read(upToCount: chunk) { sha.update(data: d) }
            let end = try h.seekToEnd()
            if end > UInt64(chunk) {
                try h.seek(toOffset: end - UInt64(chunk))
                if let d = try h.read(upToCount: chunk) { sha.update(data: d) }
            }
        }
    }

    private static func contents(_ path: String) -> String? {
        hash(path) { h, sha in
            while let d = try autoreleasepool(invoking: { try h.read(upToCount: 1 << 20) }), !d.isEmpty {
                sha.update(data: d)
            }
        }
    }
}

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.root == nil {
            EmptyScanPrompt()
        } else if model.findingDuplicates {
            VStack(spacing: 10) {
                ProgressView(value: model.duplicateProgress).frame(width: 220)
                Text("Comparing files").font(.system(size: 12.5)).foregroundStyle(.secondary)
                Button("Cancel") { model.cancelDuplicates() }.buttonStyle(ActionButtonStyle(color: .secondary))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let groups = model.duplicates {
            VStack(spacing: 0) {
                HStack {
                    Text(groups.isEmpty ? "No duplicates over 5 MB" : "\(fmt(groups.reduce(0) { $0 + $1.wasted })) in extra copies")
                        .foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    if !groups.isEmpty {
                        Button("Add All Extra Copies") { groups.forEach { model.stageExtras($0) } }
                            .buttonStyle(ActionButtonStyle())
                            .help("Keeps the newest copy of each file and adds the others to your clean list")
                    }
                    Button("Compare Again") { model.findDuplicates() }.buttonStyle(ActionButtonStyle())
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
                RowList {
                    ForEach(groups) { group($0) }
                }
            }
        } else {
            VStack(spacing: 10) {
                Text("Find files you have more than once").font(.system(size: 13, weight: .medium))
                Text("Compares the contents of your files over 5 MB. Files inside apps and Library are left out.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                Button("Find Duplicates") { model.findDuplicates() }
                    .buttonStyle(ActionButtonStyle(color: Theme.accent, filled: true))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    func group(_ g: DuplicateGroup) -> some View {
        HStack {
            Text(g.files[0].name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text("\(g.files.count) copies · \(fmt(g.size)) each").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 2)
        ForEach(Array(g.files.enumerated()), id: \.element.id) { i, f in
            HoverRow(height: 32) {
                FileIcon(path: f.path, size: 16)
                Text(f.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 12)
                if i == 0 { Text("Newest").font(.system(size: 11.5)).foregroundStyle(.tertiary) }
                StageButton(path: f.path, name: f.name, size: f.size, source: "Duplicates")
            }
            .contextMenu { Button("Reveal in Finder") { reveal(f.path) } }
        }
    }
}

// MARK: - File types

struct TypeGroup: Identifiable {
    var id: String { name }
    let name: String
    let icon: String
    var bytes: Int64 = 0
    var count = 0
    var top: [FileNode] = []
}

enum FileTypes {
    private static let kinds: [(String, String, Set<String>)] = [
        ("Videos", "film", ["mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv"]),
        ("Photos and images", "photo", ["jpg", "jpeg", "png", "heic", "gif", "tiff", "tif", "raw", "cr2", "nef", "arw", "dng", "psd", "webp"]),
        ("Audio", "waveform", ["mp3", "wav", "aiff", "aif", "flac", "m4a", "aac", "ogg"]),
        ("Disk images and installers", "opticaldisc", ["dmg", "iso", "pkg", "xip", "img", "ipsw", "qcow2", "vmdk"]),
        ("Archives", "archivebox", ["zip", "tar", "gz", "tgz", "rar", "7z", "bz2", "xz", "zst"]),
        ("Documents", "doc.text", ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "key", "pages", "numbers", "epub"]),
        ("Databases", "cylinder", ["db", "sqlite", "sqlite3", "wal", "realm"]),
        ("AI models", "cpu", ["gguf", "safetensors", "ckpt", "pt", "pth", "onnx", "mlmodel"]),
    ]

    static func group(_ root: FileNode) -> [TypeGroup] {
        var groups = kinds.map { TypeGroup(name: $0.0, icon: $0.1) } + [TypeGroup(name: "Everything else over 1 MB", icon: "doc"),
                                                                        TypeGroup(name: "Small files", icon: "square.stack.3d.up")]
        var lookup: [String: Int] = [:]
        for (i, k) in kinds.enumerated() { for e in k.2 { lookup[e] = i } }
        let other = kinds.count, small = kinds.count + 1

        func walk(_ n: FileNode) {
            for c in n.children {
                if c.isDir { walk(c); continue }
                let i = c.isAggregate ? small : lookup[(c.name as NSString).pathExtension.lowercased()] ?? other
                groups[i].bytes += c.size
                groups[i].count += c.items
                if !c.isAggregate { groups[i].top.append(c) }
            }
        }
        walk(root)
        for i in groups.indices {
            groups[i].top = Array(groups[i].top.sorted { $0.size > $1.size }.prefix(25))
        }
        return groups.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }
}

struct TypesView: View {
    @Environment(AppModel.self) private var model
    @State private var open: Set<String> = []

    var body: some View {
        if model.root == nil {
            EmptyScanPrompt()
        } else {
            let total = model.fileTypes.reduce(Int64(0)) { $0 + $1.bytes }
            RowList {
                ForEach(model.fileTypes) { t in
                    let isOpen = open.contains(t.id)
                    Button {
                        if isOpen { open.remove(t.id) } else if !t.top.isEmpty { open.insert(t.id) }
                    } label: {
                        HoverRow(height: 42) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(t.top.isEmpty ? Color.clear : Color.secondary)
                                .rotationEffect(.degrees(isOpen ? 90 : 0))
                                .frame(width: 12)
                            Image(systemName: t.icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
                            Text(t.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text("\(t.count.formatted()) files").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 12)
                            SizeBar(fraction: Double(t.bytes) / Double(max(total, 1)))
                            Text(fmt(t.bytes)).font(.system(size: 13).monospacedDigit()).frame(width: 74, alignment: .trailing)
                        }
                    }
                    .buttonStyle(.plain)
                    if isOpen {
                        ForEach(t.top) { f in
                            FileRow(file: f, source: t.name).padding(.leading, 32)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Search

/// ⌘K: jump to any page, or find any folder or big file in the last scan.
struct SearchPalette: View {
    @Environment(AppModel.self) private var model
    @State private var text = ProcessInfo.processInfo.environment["ROOMY_QUERY"] ?? ""
    @State private var picked = 0
    @State private var hits: [Hit] = []
    @FocusState private var focused: Bool

    struct Hit: Identifiable {
        let id: String
        let title: String
        var size = ""
        let detail: String
        let symbol: String
        let run: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search files and folders, or jump to a page", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    // A real Return only: onSubmit also fires when the field loses focus.
                    .onKeyPress(.return) { choose(); return .handled }
                    .onKeyPress(.downArrow) { picked = min(picked + 1, hits.count - 1); return .handled }
                    .onKeyPress(.upArrow) { picked = max(picked - 1, 0); return .handled }
                Button("Cancel") { model.showSearch = false }
                    .buttonStyle(ActionButtonStyle(color: .secondary))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.leading, 16)
            .padding(.trailing, 11)
            .frame(height: 48)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { i, h in
                            Button { picked = i; choose() } label: { row(h, on: i == picked) }
                                .buttonStyle(.plain)
                                .id(i)
                        }
                        if hits.isEmpty {
                            Text("Nothing matches").font(.system(size: 13)).foregroundStyle(.secondary).padding(20)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: picked) { _, i in proxy.scrollTo(i) }
            }
            .frame(height: 300)
        }
        .frame(width: 560)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .onAppear { DispatchQueue.main.async { focused = true } }
        .task(id: "\(text)|\(model.searchIndex.count)") {
            let q = text.trimmingCharacters(in: .whitespaces).lowercased()
            let results = await Task.detached(priority: .userInitiated) { [index = model.searchIndex] in
                q.isEmpty ? [] : Array(index.lazy.filter { $0.key.contains(q) }.prefix(40))
            }.value
            hits = pages(q) + results.map { hit($0.node) }
            picked = 0
        }
    }

    func row(_ h: Hit, on: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: h.symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            Text(h.title).font(.system(size: 13)).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 12)
            Text(h.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            Text(h.size).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(on ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
    }

    func pages(_ q: String) -> [Hit] {
        Room.allCases.filter { q.isEmpty || $0.title.lowercased().contains(q) }.map { r in
            Hit(id: "room-" + r.rawValue, title: r.title, detail: "Page", symbol: r.icon) { model.room = r }
        }
    }

    func hit(_ n: FileNode) -> Hit {
        let path = n.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return Hit(id: n.path, title: n.name, size: fmt(n.size), detail: path, symbol: n.isDir ? "folder" : "doc") {
            if n.isDir { model.open(n) } else { reveal(n.path) }
        }
    }

    func choose() {
        guard hits.indices.contains(picked) else { return }
        hits[picked].run()
        model.showSearch = false
    }
}
