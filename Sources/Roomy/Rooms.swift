import SwiftUI
import AppKit

// MARK: - Home

struct HomeRoom: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEmpty = false

    var freeFraction: Double { Double(model.volume.free) / Double(max(model.volume.total, 1)) }
    var low: Bool { freeFraction < 0.10 }

    var body: some View {
        let _ = model.treeVersion
        Page {
            VStack(alignment: .leading, spacing: 0) {
                masthead.padding(.bottom, 24)
                plan
                grewLately.padding(.top, 18)
                if !model.hasFullDiskAccess { FullDiskAccessCard().padding(.top, 20) }
            }
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .padding(.bottom, 120)
        }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmpty) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("Everything in the Trash will be permanently deleted. This can't be undone.")
        }
        .onAppear { model.refreshTrash(); model.volume = .current() }
    }

    // MARK: Top

    var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(low ? Theme.warn : Theme.accent).frame(width: 7, height: 7)
                Text("\(Self.greeting()) · \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                    .font(.callout.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(headlineText)
                .font(.system(size: 40, weight: .regular, design: .serif))
                .tracking(-0.6)
            Text(subheadText).font(.title3).foregroundStyle(.secondary)
        }
    }

    static func greeting() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Hello, night owl"
        }
    }

    var headlineText: String {
        if freeFraction < 0.05 { return "This Mac has almost run out of room" }
        if low { return "Space is getting tight" }
        if freeFraction < 0.25 { return "This Mac is in good shape" }
        return "This Mac has plenty of room"
    }

    var subheadText: String {
        let bytes = model.smartBytes
        if model.cleanLoading && bytes == 0 { return "Looking for things you can safely remove…" }
        if bytes > 0 { return "\(fmt(bytes)) of leftovers can go without you missing a thing." }
        return "Nothing obvious to clean right now."
    }

    // MARK: The plan

    /// Free space, where it's heading, and the home folder as a floor plan. One card, one main action.
    var plan: some View {
        let free = sizeParts(model.volume.free)
        let f = model.forecast
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BigValue(value: free.0, unit: "\(free.1) free", size: 56)
                Text("of \(fmt(model.volume.total))").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Label(f.text, systemImage: f.urgent ? "exclamationmark.triangle" : f.ready ? "chart.line.downtrend.xyaxis" : "clock")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(f.urgent ? Theme.warn : .secondary)
                    .lineLimit(1)
                    .help("Roomy notes free space a few times a day and draws a line through the last three weeks.")
            }
            DiskBar(total: model.volume.total, used: model.volume.used, staged: model.queuedBytes, height: 8, count: 48)
                .padding(.top, 12)

            HStack {
                Eyebrow(model.root.map { "Inside \($0.name)" } ?? "Your files")
                Spacer()
                if model.scanning {
                    Button("Cancel") { model.cancelScan() }.buttonStyle(.borderless).foregroundStyle(.secondary)
                } else {
                    Menu("Scan") {
                        Button("My Files") { model.startScan(NSHomeDirectory()) }
                        Button("Whole Mac") { model.startScan("/") }
                        Button("A Folder…") { pickFolder() }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 8)

            Group {
                if let root = model.root, !model.scanning {
                    FloorPlan(node: root) { model.open($0) }
                } else {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.scanning ? "Measuring \(model.scanFiles.formatted()) files · \(fmt(model.scanBytes))" : "Scan to draw your floor plan")
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
            }
            .frame(height: 330)

            HStack(spacing: 10) {
                Button(model.smartBytes > 0 ? "Free up \(fmt(model.smartBytes))" : model.cleanLoading ? "Looking…" : "Nothing to clean") {
                    model.stageSmart()
                }
                .buttonStyle(PillButtonStyle(color: Theme.accent, filled: true))
                .disabled(model.smartBytes == 0)
                .opacity(model.smartBytes == 0 ? 0.5 : 1)
                if let t = model.trashSize, t > 0 {
                    Button("Empty Trash · \(fmt(t))") { confirmEmpty = true }
                        .buttonStyle(PillButtonStyle(color: .secondary))
                }
                Spacer()
                Text("Click a room to walk in. Right-click to add it to your clean list.")
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            .padding(.top, 18)
        }
        .tile(padding: 24)
    }

    // MARK: What grew

    @ViewBuilder
    var grewLately: some View {
        let g = model.root.flatMap { model.snapshots.grewLately(root: $0.path) }
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
            if let g, !g.rows.isEmpty {
                Text("Grew since \(g.since.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    .font(.callout.weight(.semibold))
                ForEach(g.rows) { r in
                    Button {
                        if let n = model.root?.find(r.path) { model.open(n) } else { reveal(r.path) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(r.name).foregroundStyle(.primary)
                            Text("+\(fmt(r.delta))").monospacedDigit().foregroundStyle(Theme.accent)
                        }
                        .font(.callout)
                        .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help(r.path)
                }
            } else if g != nil {
                Text("Nothing grew much since your last scan a while ago.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Scan again in a day or two and Roomy will show what grew.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
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
        @Bindable var model = model
        VStack(spacing: 0) {
            RoomHeader(room: .storage, subtitle: subtitle) {
                Picker("", selection: $model.storageTab) {
                    ForEach(StorageTab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                if model.root != nil {
                    Button { model.startScan() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Scan again")
                        .disabled(model.scanning)
                }
            }
            switch model.storageTab {
            case .folders: FoldersView()
            case .large: LargeFilesView()
            case .changes: ChangesView()
            }
        }
    }

    var subtitle: String {
        switch model.storageTab {
        case .folders: "Click a folder to look inside. Add what you don't need; nothing is deleted until you review"
        case .large: "The biggest single files from your last scan"
        case .changes: "Every scan is saved. Compare two and see what grew"
        }
    }
}

struct FoldersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.treeVersion
        if let node = model.current ?? model.root {
            VStack(spacing: 0) {
                breadcrumb(node)
                FloorPlan(node: node, maxRooms: 16) { model.current = $0 }
                    .frame(height: 240)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                List {
                    ForEach(node.children.prefix(300)) { c in
                        row(c, parent: node)
                    }
                    Color.clear.frame(height: 80).listRowSeparator(.hidden)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        } else {
            EmptyScanPrompt()
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
            .padding(.horizontal, 32)
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
                        HStack(spacing: 6) {
                            Text(c.name).lineLimit(1).truncationMode(.middle)
                            if let a = Advisor.explain(c.path, name: c.name) { AdviceBadge(advice: a) }
                        }
                        if let a = Advisor.explain(c.path, name: c.name) {
                            Text(a.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else if c.isDir {
                            Text("\(c.items.formatted()) files").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    SizeBar(fraction: Double(c.size) / Double(max(parent.size, 1)))
                    Text(fmt(c.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(c.isDir ? Color.secondary : Color.clear)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if c.isAggregate { Color.clear.frame(width: 70) } else {
                StageButton(path: c.path, name: c.name, size: c.size, source: "Storage")
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if !c.isAggregate {
                Button("Add to Clean List") { model.stage(c) }
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
            RoomHeader(room: .clean, subtitle: "Leftovers that are safe to remove. Nothing is deleted until you review") {
                if model.cleanLoading { ProgressView().controlSize(.small) }
                Button { model.refreshClean() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Look again")
                    .disabled(model.cleanLoading)
                Button("Add All Safe") { model.stageSmart(review: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.smartBytes == 0)
                    .help("Adds caches, logs, build files and installers. Leaves out project dependencies, archives and old downloads, which you should look at yourself.")
            }
            List {
                HStack(spacing: 12) {
                    icon("trash", .secondary)
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
                            icon(cat.icon, .secondary)
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
                            Button(stagedAll ? "Added" : "Add All") {
                                if stagedAll { items.forEach { model.unstage($0.url.path) } }
                                else { items.forEach { model.stage(path: $0.url.path, name: $0.name, size: $0.size, source: cat.title) } }
                            }
                            .disabled(items.isEmpty)
                            .tint(stagedAll ? Theme.good : nil)
                        }
                        .padding(.vertical, 6)
                    }
                }
                Color.clear.frame(height: 80).listRowSeparator(.hidden)
            }
            .listStyle(.inset)
                .scrollContentBackground(.hidden)
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

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var threshold: Int64 = 100_000_000

    var body: some View {
        let _ = model.treeVersion
        VStack(spacing: 0) {
            HStack {
                Picker("At least", selection: $threshold) {
                    Text("50 MB").tag(Int64(50_000_000))
                    Text("100 MB").tag(Int64(100_000_000))
                    Text("500 MB").tag(Int64(500_000_000))
                    Text("1 GB").tag(Int64(1_000_000_000))
                }
                .frame(width: 170)
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
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
                    .padding(.horizontal, 32)
                    List(files.prefix(500)) { f in
                        HStack(spacing: 10) {
                            FileIcon(path: f.path, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(f.name).lineLimit(1).truncationMode(.middle)
                                    if let a = Advisor.explain(f.path, name: f.name) { AdviceBadge(advice: a) }
                                }
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
                .scrollContentBackground(.hidden)
                    .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
                }
            } else {
                EmptyScanPrompt()
            }
        }
    }
}

// MARK: - Full Disk Access

struct FullDiskAccessCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Glyph(symbol: "hand.raised", color: Theme.warm, size: 28)
            Text("Roomy can't see protected folders like the Trash and Mail, so some sizes look smaller.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Allow…") { openFullDiskAccess() }.buttonStyle(PillButtonStyle(filled: true))
            Button("Relaunch") { model.relaunch() }.buttonStyle(PillButtonStyle(color: .secondary))
                .help("After switching Roomy on in Full Disk Access, relaunch so it takes effect")
        }
        .padding(12)
        .background(Theme.warm.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.warm.opacity(0.3), lineWidth: 1))
    }
}
