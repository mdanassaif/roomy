import SwiftUI
import AppKit

// MARK: - Home

/// A to-do list for the disk: how much room is left, where it went, what's worth doing about it.
struct HomeRoom: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEmpty = false

    var freeFraction: Double { Double(model.volume.free) / Double(max(model.volume.total, 1)) }
    var low: Bool { freeFraction < 0.10 }
    var ready: Int64 { model.smartBytes + (model.trashSize ?? 0) }

    var subtitle: String {
        if ready > 0 { return "\(fmt(ready)) can go right now without you missing a thing" }
        if model.cleanLoading { return "Looking for things you can safely remove" }
        return "Nothing needs cleaning right now"
    }

    var body: some View {
        let list = model.suggestions
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RoomHeader(room: .home, subtitle: subtitle) { ScanControl() }
                VStack(alignment: .leading, spacing: 18) {
                    tiles(list)
                    if !model.hasFullDiskAccess { FullDiskAccessRow() }
                    Panel(title: "Where your space goes", icon: "chart.bar.xaxis") { space.padding(.horizontal, 10).padding(.vertical, 6) }
                    todo(list)
                    if let g = model.growth, !g.rows.isEmpty { grew(g) }
                }
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .padding(.bottom, 90)
            }
        }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmpty) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("Everything in the Trash will be permanently deleted. This can't be undone.")
        }
    }

    // MARK: Summary

    func tiles(_ list: [Suggestion]) -> some View {
        let free = sizeParts(model.volume.free)
        let check = list.filter { $0.id != "smart" && $0.id != "trash" }
        let checkBytes = check.reduce(Int64(0)) { $0 + $1.bytes }
        let grew = model.growth?.rows ?? []
        let grewBytes = grew.reduce(Int64(0)) { $0 + $1.delta }
        let readyParts = sizeParts(ready), checkParts = sizeParts(checkBytes), grewParts = sizeParts(grewBytes)
        return HStack(spacing: 12) {
            StatTile(icon: "internaldrive", label: "Free space", value: free.0, unit: free.1,
                     caption: "of \(fmt(model.volume.total))" + (model.forecast.ready ? " · " + model.forecast.text : ""),
                     tint: low ? Theme.warn : .primary) { model.storageTab = .folders; model.room = .storage }
            StatTile(icon: "checkmark.seal", label: "Safe to clear", value: readyParts.0, unit: readyParts.1,
                     caption: ready > 0 ? "Caches and Trash" : "Nothing right now",
                     tint: ready > 0 ? Theme.good : .secondary) { model.room = .clean }
            StatTile(icon: "eye", label: "Worth a look", value: checkParts.0, unit: checkParts.1,
                     caption: check.isEmpty ? "Nothing to check" : "\(check.count) thing\(check.count == 1 ? "" : "s") to check first",
                     tint: checkBytes > 0 ? Theme.warm : .secondary) { model.room = .clean }
            StatTile(icon: "arrow.up.right", label: "Grew lately", value: grewParts.0, unit: grewParts.1,
                     caption: grew.isEmpty ? "Shows after a few days of scans" : "\(grew.count) folder\(grew.count == 1 ? "" : "s") got bigger",
                     tint: .primary) { model.storageTab = .changes; model.room = .storage }
        }
    }

    // MARK: Space

    var space: some View {
        let segments = folders
        let total = Double(max(model.volume.total, 1))
        return VStack(alignment: .leading, spacing: 12) {
            StackBar(parts: segments.map { (Double($0.bytes) / total, $0.color) }, height: 8, gap: 2)
            HStack(spacing: 16) {
                ForEach(segments) { s in
                    Button {
                        if let n = s.node { model.open(n) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(s.color).frame(width: 7, height: 7)
                            Text(s.name).foregroundStyle(.primary)
                            Text(fmt(s.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(s.node == nil)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
        }
    }

    struct Segment: Identifiable {
        var id: String { name }
        let name: String
        let bytes: Int64
        let color: Color
        var node: FileNode?
    }

    /// The three biggest folders in shades of the accent, then everything else on the disk.
    var folders: [Segment] {
        let used = model.volume.used
        guard let root = model.root else { return [Segment(name: "Used", bytes: used, color: Theme.accent)] }
        let top = root.children.filter { $0.isDir }.prefix(3)
        let shades: [Double] = [1, 0.62, 0.36]
        var out = top.enumerated().map { i, n in
            Segment(name: n.name, bytes: n.size, color: Theme.accent.opacity(shades[i]), node: n)
        }
        let rest = used - top.reduce(0) { $0 + $1.size }
        if rest > 0 { out.append(Segment(name: "Everything else", bytes: rest, color: Color.primary.opacity(0.2))) }
        return out
    }

    // MARK: To do

    @ViewBuilder
    func todo(_ list: [Suggestion]) -> some View {
        Panel(title: "Worth doing", icon: "checklist", count: list.count) {
            if model.smartBytes > 0 {
                Button("Free up \(fmt(model.smartBytes))") { model.stageSmart() }
                    .buttonStyle(ActionButtonStyle(color: Theme.accent, filled: true))
            }
        } content: {

            if list.isEmpty {
                Text(model.cleanLoading ? "Checking your Mac…" : "All clear. Nothing to do.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 10)
            }
            ForEach(list.prefix(7)) { s in
                HoverRow(height: 46) {
                    Image(systemName: s.icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.title).font(.system(size: 13, weight: .medium))
                        Text(s.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 12)
                    Text(fmt(s.bytes)).font(.system(size: 13).monospacedDigit())
                    Button(s.button) {
                        if case .emptyTrash = s.action { confirmEmpty = true } else { model.run(s.action) }
                    }
                    .buttonStyle(ActionButtonStyle())
                    .frame(width: 66, alignment: .trailing)
                }
            }
        }
    }

    // MARK: What grew

    func grew(_ g: (since: Date, rows: [Growth])) -> some View {
        Panel(title: "Grew since \(g.since.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))",
              icon: "arrow.up.right", count: g.rows.count) {
            Button("See changes") { model.storageTab = .changes; model.room = .storage }
                .buttonStyle(ActionButtonStyle(color: .secondary))
        } content: {
            ForEach(g.rows) { r in
                Button {
                    if let n = model.root?.find(r.path) { model.open(n) } else { reveal(r.path) }
                } label: {
                    HoverRow(height: 34) {
                        Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 20)
                        Text(r.name).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Text("+\(fmt(r.delta))").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.warm)
                    }
                }
                .buttonStyle(.plain)
                .help(r.path)
            }
        }
    }
}

// MARK: - Storage

struct StorageRoom: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            RoomHeader(room: .storage, subtitle: subtitle) { ScanControl() }
            if !model.hasFullDiskAccess { FullDiskAccessRow().padding(.horizontal, 28).padding(.bottom, 12) }
            TabStrip(selection: $model.storageTab, tabs: StorageTab.allCases.map { ($0, $0.rawValue) })
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
            switch model.storageTab {
            case .folders: FoldersView()
            case .large: LargeFilesView()
            case .types: TypesView()
            case .duplicates: DuplicatesView()
            case .changes: ChangesView()
            }
        }
    }

    var subtitle: String {
        switch model.storageTab {
        case .folders: "Add what you don't need. Nothing is deleted until you review it"
        case .large: "The biggest single files from your last scan"
        case .types: "What kinds of files are taking up the room"
        case .duplicates: "Identical copies, compared by their contents"
        case .changes: "Compare two scans and see what grew"
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
                RowList {
                    ForEach(node.children.prefix(300)) { row($0, parent: node) }
                }
                .id(node.path)
            }
        } else {
            EmptyScanPrompt()
        }
    }

    func breadcrumb(_ node: FileNode) -> some View {
        HStack(spacing: 5) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(node.chain) { n in
                        Button(n.name) { model.current = n }
                            .buttonStyle(.plain)
                            .foregroundStyle(n === node ? Color.primary : Color.secondary)
                            .fontWeight(n === node ? .medium : .regular)
                        if n !== node { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary) }
                    }
                }
            }
            Spacer(minLength: 12)
            Text("\(fmt(node.size)) · \(node.items.formatted()) files").foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            if node.parent != nil {
                Button { model.current = node.parent } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Up one level")
            }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    func row(_ c: FileNode, parent: FileNode) -> some View {
        let advice = Advisor.explain(c.path, name: c.name)
        return HoverRow(height: 40) {
            Button {
                if c.isDir { model.current = c }
            } label: {
                HStack(spacing: 10) {
                    FileIcon(path: c.path, aggregate: c.isAggregate, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            Text(c.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                            if let advice { AdviceBadge(advice: advice) }
                        }
                        if let advice {
                            Text(advice.text).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 12)
                    SizeBar(fraction: Double(c.size) / Double(max(parent.size, 1)))
                    Text(fmt(c.size)).font(.system(size: 13).monospacedDigit()).frame(width: 74, alignment: .trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if c.isAggregate { Color.clear.frame(width: 62, height: 1) } else {
                StageButton(path: c.path, name: c.name, size: c.size, source: "Storage")
            }
        }
        .contextMenu {
            if !c.isAggregate {
                Button("Add to Clean List") { model.stage(c) }
                Button("Reveal in Finder") { reveal(c.path) }
            }
        }
    }
}

// MARK: - Clean Up

struct CleanRoom: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEmpty = false

    var body: some View {
        VStack(spacing: 0) {
            RoomHeader(room: .clean, subtitle: model.smartBytes > 0
                       ? "\(fmt(model.smartBytes)) of leftovers can go. Nothing is deleted until you review it"
                       : "Leftovers that are safe to remove. Nothing is deleted until you review it") {
                if model.cleanLoading { ProgressView().controlSize(.mini) }
                Button("Look Again") { model.refreshClean() }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(model.cleanLoading)
                Button("Add All Safe") { model.stageSmart(review: false) }
                    .buttonStyle(ActionButtonStyle(color: Theme.accent, filled: true))
                    .disabled(model.smartBytes == 0)
                    .opacity(model.smartBytes == 0 ? 0.5 : 1)
                    .help("Adds caches, logs, build files and installers. Leaves out project dependencies, archives and old downloads, which you should look at yourself.")
            }
            RowList {
                HoverRow(height: 46) {
                    Color.clear.frame(width: 12, height: 1)
                    Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Trash").font(.system(size: 13, weight: .medium))
                        Text("Moving things to the Trash frees no space until you empty it").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer()
                    Text(model.trashSize.map(fmt) ?? "Size needs access").font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
                        .help("Roomy can still empty it by asking Finder")
                    Button("Empty") { confirmEmpty = true }.buttonStyle(ActionButtonStyle(color: Theme.warn))
                        .frame(width: 62, alignment: .trailing)
                }
                let found = Cleaners.all.filter { !(model.cleanResults[$0.id] ?? []).isEmpty || (model.cleanLoading && model.cleanResults[$0.id] == nil) }
                let locked = model.hasFullDiskAccess ? [] : Cleaners.all.filter { Cleaners.needAccess.contains($0.id) }
                let empty = Cleaners.all.filter { c in !found.contains { $0.id == c.id } && !locked.contains { $0.id == c.id } }
                ForEach(found) { category($0) }
                if !empty.isEmpty { note("checkmark", "Nothing to clear in " + list(empty)) }
                if !locked.isEmpty {
                    note("lock", list(locked) + " need Full Disk Access", action: ("Turn on…", { model.room = .home; model.showAccess = true }))
                }
            }
        }
        .onAppear { if model.cleanResults.isEmpty { model.refreshClean() } }
        .confirmationDialog("Empty the Trash?", isPresented: $confirmEmpty) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("Everything in the Trash will be permanently deleted.")
        }
    }

    func list(_ cats: [CleanCategory]) -> String {
        let names = cats.map(\.title)
        return names.count <= 1 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    func note(_ icon: String, _ text: String, action: (String, () -> Void)? = nil) -> some View {
        HoverRow(height: 40) {
            Color.clear.frame(width: 12, height: 1)
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 20)
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 8)
            if let action { Button(action.0, action: action.1).buttonStyle(ActionButtonStyle()) }
        }
    }

    @ViewBuilder
    func category(_ cat: CleanCategory) -> some View {
        let items = model.cleanResults[cat.id] ?? []
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        let stagedAll = !items.isEmpty && items.allSatisfy { model.isQueued($0.url.path) || model.isCovered($0.url.path) }
        let open = model.cleanExpanded.contains(cat.id) && !items.isEmpty

        Button {
            if open { model.cleanExpanded.remove(cat.id) } else { model.cleanExpanded.insert(cat.id) }
        } label: {
            HoverRow(height: 46) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(items.isEmpty ? Color.clear : Color.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 12)
                Image(systemName: cat.icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(cat.title).font(.system(size: 13, weight: .medium))
                    Text(cat.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                if model.cleanLoading && model.cleanResults[cat.id] == nil {
                    ProgressView().controlSize(.mini)
                } else {
                    Text(items.isEmpty ? "Nothing" : fmt(total)).font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(items.isEmpty ? .secondary : .primary)
                }
                Button(stagedAll ? "Added" : "Add All") {
                    if stagedAll { items.forEach { model.unstage($0.url.path) } }
                    else { items.forEach { model.stage(path: $0.url.path, name: $0.name, size: $0.size, source: cat.title) } }
                }
                .buttonStyle(ActionButtonStyle(color: stagedAll ? Theme.good : .primary))
                .disabled(items.isEmpty)
                .opacity(items.isEmpty ? 0 : 1)
                .frame(width: 62, alignment: .trailing)
            }
        }
        .buttonStyle(.plain)

        if open {
            ForEach(items.prefix(200)) { i in
                HoverRow(height: 34) {
                    Color.clear.frame(width: 32, height: 1)
                    FileIcon(path: i.url.path, size: 16)
                    Text(i.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(fmt(i.size)).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(.secondary)
                    StageButton(path: i.url.path, name: i.name, size: i.size, source: cat.title)
                }
                .contextMenu { Button("Reveal in Finder") { reveal(i.url.path) } }
            }
        }
    }
}

// MARK: - Large files

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var threshold: Int64 = 100_000_000
    @State private var stale = false
    @State private var files: [FileNode] = []

    var key: String { "\(model.treeVersion)-\(threshold)-\(stale)" }

    var body: some View {
        VStack(spacing: 0) {
            if model.root == nil {
                EmptyScanPrompt()
            } else {
                HStack(spacing: 12) {
                    TabStrip(selection: $threshold, tabs: [(50_000_000, "50 MB"), (100_000_000, "100 MB"), (500_000_000, "500 MB"), (1_000_000_000, "1 GB")])
                    Toggle("Untouched for a year", isOn: $stale).toggleStyle(.checkbox)
                        .help("Only files whose contents haven't changed in over a year")
                    Spacer()
                    Text("\(files.count) files · \(fmt(files.reduce(0) { $0 + $1.size }))").foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.system(size: 12.5))
                .padding(.leading, 22)
                .padding(.trailing, 28)
                .padding(.bottom, 8)

                if files.isEmpty {
                    Text("No files that big").font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    RowList {
                        ForEach(files.prefix(500)) { row($0) }
                    }
                }
            }
        }
        .task(id: key) {
            guard let root = model.root else { return }
            let min = threshold
            let cutoff = stale ? Date().addingTimeInterval(-365 * 86400) : nil
            files = await Task.detached(priority: .userInitiated) {
                var out: [FileNode] = []
                root.files(atLeast: min, into: &out)
                if let cutoff { out = out.filter { ($0.modified ?? .distantFuture) < cutoff } }
                return out.sorted { $0.size > $1.size }
            }.value
        }
    }

    func row(_ f: FileNode) -> some View {
        FileRow(file: f, source: "Large files", showDate: true)
    }
}

/// One file with what it is, whether it's safe to remove, and where it lives.
struct FileRow: View {
    let file: FileNode
    let source: String
    var showDate = false

    var body: some View {
        let f = file
        let advice = Advisor.explain(f.path, name: f.name)
        let place = f.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return HoverRow(height: 44) {
            FileIcon(path: f.path, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(f.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    if let advice { AdviceBadge(advice: advice) }
                }
                Text(advice.map { $0.text + "  ·  " + place } ?? place)
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .help(place)
            Spacer(minLength: 12)
            if showDate, let m = f.modified {
                Text(m.formatted(.dateTime.month(.abbreviated).year())).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text(fmt(f.size)).font(.system(size: 13).monospacedDigit()).frame(width: 74, alignment: .trailing)
            StageButton(path: f.path, name: f.name, size: f.size, source: source)
        }
        .contextMenu { Button("Reveal in Finder") { reveal(f.path) } }
    }
}

// MARK: - Full Disk Access

/// Apple's one switch for apps that measure the whole disk. With it, macOS never asks about single folders.
/// Shown as a full card until it's on or the user chooses to go without, then as one quiet line.
struct FullDiskAccessRow: View {
    @Environment(AppModel.self) private var model
    @State private var waiting = false

    var body: some View {
        if model.scanLimited && !model.showAccess {
            HoverRow(height: 40) {
                Image(systemName: "lock").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 20)
                Text("Desktop, Documents, Downloads and other protected folders are left out.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Button("Include them…") { model.showAccess = true }.buttonStyle(ActionButtonStyle())
            }
        } else {
            card
        }
    }

    var card: some View {
        Panel(title: "Give Roomy Full Disk Access", icon: "lock.shield") {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text("macOS guards Desktop, Documents, Downloads, Photos and other apps' data, and asks about each one separately. Full Disk Access is Apple's single switch for apps that measure your disk. Turn it on once and macOS stops asking.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Open Privacy & Security › Full Disk Access")
                    step(2, "Switch Roomy on. If it isn't listed, click + and choose Roomy in Applications")
                    step(3, "Come back here. Roomy notices and starts scanning")
                }
                HStack(spacing: 8) {
                    Button("Open System Settings") { waiting = true; openFullDiskAccess() }
                        .buttonStyle(ActionButtonStyle(color: Theme.accent, filled: true))
                    if waiting {
                        ProgressView().controlSize(.mini)
                        Text("Waiting for the switch…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Scan without it") { model.accessSettled(limited: true) }
                        .buttonStyle(ActionButtonStyle(color: .secondary))
                        .help("Leaves out every protected folder, so macOS never asks")
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            if FullDiskAccess.granted { model.accessSettled(limited: false) }
        }
    }

    func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 18, height: 18)
                .background(Color.primary.opacity(0.07), in: Circle())
            Text(text).font(.system(size: 12.5))
        }
    }
}

// MARK: - Summary pieces

/// One number that matters, what it means, and where clicking it takes you.
struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let caption: String
    var tint: Color = .primary
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 11, weight: .medium))
                    Text(label).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).opacity(hovered ? 1 : 0)
                }
                .foregroundStyle(.secondary)
                BigValue(value: value, unit: unit, size: 26).foregroundStyle(tint)
                Text(caption).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? Color.primary.opacity(0.035) : Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// A titled group of rows with a count, so each part of the page says what it is.
struct Panel<Trailing: View, Content: View>: View {
    let title: String
    let icon: String
    var count: Int? = nil
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 13, weight: .semibold))
                if let count { Text("\(count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary) }
                Spacer()
                trailing
            }
            .frame(minHeight: 30)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            content
        }
        .padding(8)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
    }
}

extension Panel where Trailing == EmptyView {
    init(title: String, icon: String, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, icon: icon, count: count, trailing: { EmptyView() }, content: content)
    }
}
