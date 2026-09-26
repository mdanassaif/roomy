import SwiftUI
import AppKit

// MARK: - Overview

struct OverviewRoom: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEmpty = false

    var body: some View {
        let _ = model.treeVersion
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoomHeader(room: .overview, subtitle: "Macintosh HD at a glance") { EmptyView() }

                VStack(spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(fmt(model.volume.free)).font(.system(size: 34, weight: .bold, design: .rounded))
                                Text("free of \(fmt(model.volume.total))").foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(Double(model.volume.used) / Double(max(model.volume.total, 1)) * 100))% used")
                                    .foregroundStyle(.secondary)
                            }
                            DiskBar(total: model.volume.total, used: model.volume.used, staged: model.queuedBytes, height: 18)
                            HStack(spacing: 16) {
                                legend(.purple, "Used \(fmt(model.volume.used))")
                                if model.queuedBytes > 0 { legend(.green, "Staged \(fmt(model.queuedBytes))") }
                                legend(.secondary.opacity(0.3), "Free \(fmt(model.volume.free))")
                            }
                            .font(.caption)
                        }
                    }

                    HStack(spacing: 16) {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Trash", systemImage: "trash").font(.headline)
                                if let s = model.trashSize {
                                    Text(fmt(s)).font(.title.bold())
                                    Text("\(model.trashCount) items").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("Size hidden").font(.title3.bold())
                                    Button("Grant Full Disk Access to see it") { openFullDiskAccess() }
                                        .buttonStyle(.link).font(.caption)
                                }
                                Button(role: .destructive) { confirmEmpty = true } label: {
                                    Label("Empty Trash", systemImage: "trash.slash")
                                }
                                .disabled(model.trashSize == 0)
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Scan", systemImage: "magnifyingglass").font(.headline)
                                if model.scanning {
                                    ProgressView().controlSize(.small)
                                    Text("\(model.scanFiles.formatted()) items · \(fmt(model.scanBytes))").font(.callout.monospacedDigit())
                                    Text(model.scanCurrent).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    Button("Cancel") { model.cancelScan() }
                                } else {
                                    if let d = model.scanDate, let r = model.root {
                                        Text("\(fmt(r.size)) in \(r.name)").font(.title3.bold())
                                        Text("Scanned \(d.formatted(.relative(presentation: .named))) in \(Int(model.scanDuration))s")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("Find what's taking space").foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        Button("Home") { model.startScan(NSHomeDirectory()) }.buttonStyle(.borderedProminent)
                                        Button("Entire Disk") { model.startScan("/") }
                                        Button("Folder…") { pickFolder() }
                                    }
                                }
                            }
                        }
                    }

                    if let root = model.root {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Biggest in \(root.name)").font(.headline)
                                    Spacer()
                                    Button("Open Storage") { model.open(root) }.buttonStyle(.link)
                                }
                                ForEach(root.children.prefix(8)) { c in
                                    HStack {
                                        FileIcon(path: c.path, aggregate: c.isAggregate)
                                        Button(c.name) { if c.isDir { model.open(c) } }
                                            .buttonStyle(.plain)
                                            .lineLimit(1)
                                        Spacer()
                                        SizeBar(fraction: Double(c.size) / Double(max(root.size, 1)))
                                        Text(fmt(c.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                                        if !c.isAggregate {
                                            StageButton(path: c.path, name: c.name, size: c.size, source: "Overview")
                                        } else {
                                            Color.clear.frame(width: 16)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Private by design").font(.headline)
                                Text("Scanning happens on this Mac. No account, no sync, no analytics. The only network calls are update checks, and only when you press Check.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Full Disk Access…") { openFullDiskAccess() }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 110)
            }
        }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmpty) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("Everything in the Trash will be permanently deleted. This can't be undone.")
        }
        .onAppear { model.refreshTrash(); model.volume = .current() }
    }

    func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 8, height: 8); Text(t) }
    }

    func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.prompt = "Scan"
        if p.runModal() == .OK, let u = p.url { model.startScan(u.path) }
    }
}

// MARK: - Storage

struct StorageRoom: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.treeVersion
        VStack(spacing: 0) {
            RoomHeader(room: .storage, subtitle: model.root == nil ? "Where your space went" : "Click a block to go inside it. Press + to stage it for cleanup") {
                if model.root != nil {
                    Button { model.startScan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                        .disabled(model.scanning)
                }
            }
            if let node = model.current ?? model.root {
                breadcrumb(node)
                TreemapView(node: node)
                    .frame(height: 240)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                List {
                    ForEach(node.children.prefix(300)) { c in
                        row(c, parent: node)
                    }
                    Color.clear.frame(height: 80).listRowSeparator(.hidden)
                }
                .listStyle(.inset)
            } else {
                EmptyScanPrompt()
            }
        }
    }

    func breadcrumb(_ node: FileNode) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if node.parent != nil {
                    Button { model.current = node.parent } label: { Image(systemName: "chevron.backward") }
                        .buttonStyle(.borderless)
                        .keyboardShortcut("[", modifiers: .command)
                }
                ForEach(node.chain) { n in
                    Button(n.name) { model.current = n }
                        .buttonStyle(.plain)
                        .foregroundStyle(n === node ? Color.primary : Color.secondary)
                        .fontWeight(n === node ? .semibold : .regular)
                    if n !== node { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                }
                Spacer()
                Text("\(fmt(node.size)) · \(node.items.formatted()) files").foregroundStyle(.secondary).font(.callout)
            }
            .padding(.horizontal, 24)
        }
    }

    func row(_ c: FileNode, parent: FileNode) -> some View {
        HStack(spacing: 10) {
            Button {
                if c.isDir { model.current = c }
            } label: {
                HStack(spacing: 10) {
                    FileIcon(path: c.path, aggregate: c.isAggregate, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).lineLimit(1).truncationMode(.middle)
                        if c.isDir { Text("\(c.items.formatted()) files").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(String(format: "%.1f%%", Double(c.size) / Double(max(parent.size, 1)) * 100))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    SizeBar(fraction: Double(c.size) / Double(max(parent.size, 1)))
                    Text(fmt(c.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(c.isDir ? Color.secondary : Color.clear)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if c.isAggregate { Color.clear.frame(width: 16) } else {
                StageButton(path: c.path, name: c.name, size: c.size, source: "Storage")
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if !c.isAggregate {
                Button("Add to Cleanup Queue") { model.stage(c) }
                Button("Reveal in Finder") { reveal(c.path) }
            }
        }
    }
}

// MARK: - Quick clean

struct CleanRoom: View {
    @Environment(AppModel.self) private var model
    @State private var expanded: Set<String> = []
    @State private var confirmEmpty = false

    var body: some View {
        VStack(spacing: 0) {
            RoomHeader(room: .clean, subtitle: "Safe-to-remove leftovers. Nothing is deleted until you review the queue") {
                if model.cleanLoading { ProgressView().controlSize(.small) }
                Button { model.refreshClean() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.cleanLoading)
                Button("Stage Everything") {
                    for c in Cleaners.all where c.id != "olddownloads" && c.id != "archives" {
                        for i in model.cleanResults[c.id] ?? [] { model.stage(path: i.url.path, name: i.name, size: i.size, source: c.title) }
                    }
                }
                .disabled(model.cleanResults.isEmpty)
                .help("Stages everything except Archives and Old downloads, which you should look through yourself")
            }
            List {
                HStack(spacing: 12) {
                    icon("trash", .red)
                    VStack(alignment: .leading) {
                        Text("Trash").font(.headline)
                        Text("Moving things to the Trash frees no space until you empty it").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(model.trashSize.map(fmt) ?? "Hidden").monospacedDigit().foregroundStyle(.secondary)
                    Button("Empty Trash", role: .destructive) { confirmEmpty = true }
                }
                .padding(.vertical, 6)

                ForEach(Cleaners.all) { cat in
                    let items = model.cleanResults[cat.id] ?? []
                    let total = items.reduce(Int64(0)) { $0 + $1.size }
                    let stagedAll = !items.isEmpty && items.allSatisfy { model.isQueued($0.url.path) || model.isCovered($0.url.path) }
                    DisclosureGroup(isExpanded: Binding(get: { expanded.contains(cat.id) },
                                                        set: { if $0 { expanded.insert(cat.id) } else { expanded.remove(cat.id) } })) {
                        ForEach(items.prefix(200)) { i in
                            HStack {
                                FileIcon(path: i.url.path)
                                Text(i.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(fmt(i.size)).monospacedDigit().foregroundStyle(.secondary)
                                StageButton(path: i.url.path, name: i.name, size: i.size, source: cat.title)
                            }
                            .contextMenu { Button("Reveal in Finder") { reveal(i.url.path) } }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            icon(cat.icon, .green)
                            VStack(alignment: .leading) {
                                Text(cat.title).font(.headline)
                                Text(cat.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.cleanLoading && model.cleanResults[cat.id] == nil {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(items.isEmpty ? "Nothing" : fmt(total)).monospacedDigit()
                                    .foregroundStyle(items.isEmpty ? .secondary : .primary)
                            }
                            Button(stagedAll ? "Staged" : "Stage") {
                                if stagedAll { items.forEach { model.unstage($0.url.path) } }
                                else { items.forEach { model.stage(path: $0.url.path, name: $0.name, size: $0.size, source: cat.title) } }
                            }
                            .disabled(items.isEmpty)
                            .tint(stagedAll ? .green : nil)
                        }
                        .padding(.vertical, 6)
                    }
                }
                Color.clear.frame(height: 80).listRowSeparator(.hidden)
            }
            .listStyle(.inset)
        }
        .onAppear { if model.cleanResults.isEmpty { model.refreshClean() } }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmpty) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("Everything in the Trash will be permanently deleted.")
        }
    }

    func icon(_ name: String, _ c: Color) -> some View {
        Image(systemName: name).foregroundStyle(c).font(.title3).frame(width: 30)
    }
}

// MARK: - Large files

struct LargeFilesRoom: View {
    @Environment(AppModel.self) private var model
    @State private var threshold: Int64 = 100_000_000

    var body: some View {
        let _ = model.treeVersion
        VStack(spacing: 0) {
            RoomHeader(room: .large, subtitle: "The biggest single files from your last scan") {
                Picker("At least", selection: $threshold) {
                    Text("50 MB").tag(Int64(50_000_000))
                    Text("100 MB").tag(Int64(100_000_000))
                    Text("500 MB").tag(Int64(500_000_000))
                    Text("1 GB").tag(Int64(1_000_000_000))
                }
                .frame(width: 170)
            }
            if let root = model.root {
                let files: [FileNode] = {
                    var out: [FileNode] = []
                    root.files(atLeast: threshold, into: &out)
                    return out.sorted { $0.size > $1.size }
                }()
                if files.isEmpty {
                    ContentUnavailableView("No files that big", systemImage: "checkmark.seal", description: Text("Try a smaller size."))
                } else {
                    HStack {
                        Text("\(files.count) files · \(fmt(files.reduce(0) { $0 + $1.size }))").foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    List(files.prefix(500)) { f in
                        HStack(spacing: 10) {
                            FileIcon(path: f.path, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.name).lineLimit(1).truncationMode(.middle)
                                Text(f.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                            if let m = f.modified {
                                Text(m.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(fmt(f.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                            Button { reveal(f.path) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.borderless).help("Reveal in Finder")
                            StageButton(path: f.path, name: f.name, size: f.size, source: "Large files")
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                    .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
                }
            } else {
                EmptyScanPrompt()
            }
        }
    }
}
