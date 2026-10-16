import SwiftUI
import AppKit

// MARK: - Home

struct HomeRoom: View {
    @Environment(AppModel.self) private var model
    @Environment(SystemMonitor.self) private var mon
    @Environment(KeepAwake.self) private var awake
    @State private var confirmEmpty = false
    @State private var wide = true

    var freeFraction: Double { Double(model.volume.free) / Double(max(model.volume.total, 1)) }
    var low: Bool { freeFraction < 0.10 }

    var body: some View {
        let _ = model.treeVersion
        Page {
            VStack(alignment: .leading, spacing: 0) {
                masthead.padding(.bottom, 26)
                Group {
                    if wide {
                        HStack(alignment: .top, spacing: 16) {
                            spaceCard
                            todo.frame(width: 360)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 16) { spaceCard; todo }
                    }
                }
                .onGeometryChange(for: Bool.self) { $0.size.width >= 820 } action: { wide = $0 }
                if !model.hasFullDiskAccess { FullDiskAccessCard().padding(.top, 14) }

                sectionTitle("Your Mac right now").padding(.top, 36).padding(.bottom, 12)
                vitals

                sectionTitle(model.root.map { "Biggest in \($0.name)" } ?? "What's taking space").padding(.top, 36).padding(.bottom, 12)
                biggest
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
        .onAppear { model.refreshTrash(); model.volume = .current(); mon.start() }
        .onDisappear { mon.stop() }
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

    // MARK: Space

    var spaceCard: some View {
        let t = Double(max(model.volume.total, 1))
        let used = Double(model.volume.used) / t
        let staged = Double(min(model.queuedBytes, model.volume.used)) / t
        let free = sizeParts(model.volume.free)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                FileIcon(path: "/", size: 22)
                Eyebrow("Macintosh HD · \(fmt(model.volume.total))")
                Spacer()
                OpenLink(title: "Storage") { model.room = .storage }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BigValue(value: free.0, unit: "\(free.1) free", size: 64)
                Spacer()
                Text("\(Int(used * 100))% used").font(.callout.monospacedDigit()).foregroundStyle(low ? Theme.warn : .secondary)
            }
            .padding(.top, 14)
            // The disk as a floor plan: two rows of rooms.
            VStack(spacing: 3) {
                let rows = 2, per = 32
                ForEach(0..<rows, id: \.self) { r in
                    let lo = Double(r) / Double(rows)
                    let span = 1 / Double(rows)
                    let u = min(max(used - staged - lo, 0), span) / span
                    let s = min(max(used - lo, 0), span) / span - u
                    BlockBar(parts: [(u, low ? Theme.warn : Theme.accent), (s, Theme.good)], count: per, height: 18, gap: 3)
                }
            }
            .padding(.top, 14)
            .animation(.snappy, value: staged)
            HStack(spacing: 16) {
                legend(low ? Theme.warn : Theme.accent, "Used \(fmt(model.volume.used))")
                if model.queuedBytes > 0 { legend(Theme.good, "On your clean list \(fmt(model.queuedBytes))") }
                legend(Theme.empty, "Free \(fmt(model.volume.free))")
                Spacer()
            }
            .padding(.top, 12)
            HStack {
                Text(low ? "Updates and saving files will start to fail soon." : "Room for updates and new things.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("See what's using it") {
                    if let root = model.root { model.open(root) } else { model.storageTab = .folders; model.room = .storage }
                }
                .buttonStyle(PillButtonStyle(color: low ? Theme.warn : Theme.accent, filled: low))
            }
            .padding(.top, 18)
        }
        .tile(padding: 24)
    }

    func legend(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 9, height: 9)
            Text(text).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    // MARK: Worth doing

    var todo: some View {
        let clean = sizeParts(model.smartBytes)
        let trash = sizeParts(model.trashSize ?? 0)
        let updates = model.sparkleUpdates.count + model.brewOutdated.count
        return VStack(alignment: .leading, spacing: 0) {
            Text("Worth doing").font(.system(size: 20, weight: .regular, design: .serif)).padding(.bottom, 8)
            TodoRow(symbol: "sparkles", color: Theme.accent,
                    title: "Temporary files",
                    value: model.cleanLoading && model.smartBytes == 0 ? "…" : model.smartBytes > 0 ? "\(clean.0) \(clean.1)" : "None",
                    detail: "Caches, logs and build files nothing needs",
                    action: "Clean up", primary: model.smartBytes > 0, disabled: model.smartBytes == 0) { model.stageSmart() }
            Divider().overlay(Theme.line)
            TodoRow(symbol: "trash", color: Theme.warm,
                    title: "Trash",
                    value: model.trashSize == nil ? "Hidden" : "\(trash.0) \(trash.1)",
                    detail: model.trashSize == nil ? "Allow Full Disk Access to see its size" : "\(model.trashCount) items still taking space",
                    action: "Empty", disabled: model.trashSize == 0) { confirmEmpty = true }
            Divider().overlay(Theme.line)
            TodoRow(symbol: "arrow.down.circle", color: Theme.calm,
                    title: "Updates",
                    value: model.lastUpdateCheck == nil ? "Unchecked" : "\(updates)",
                    detail: model.lastUpdateCheck.map { "Checked \($0.formatted(.relative(presentation: .named)))" } ?? "From app feeds and Homebrew",
                    action: model.lastUpdateCheck == nil ? "Check" : "See") {
                model.room = .apps
                if model.lastUpdateCheck == nil { model.checkUpdates() }
            }
        }
        .tile(padding: 20)
    }

    // MARK: Right now

    var vitals: some View {
        let memFrac = Double(mon.memUsed) / Double(max(mon.memTotal, 1))
        let level = mon.battery?.level ?? 100
        let down = sizeParts(Int64(mon.rxRate))
        let cells: [AnyView] = [
            AnyView(VitalCell(symbol: "memorychip", label: "Memory", value: "\(Int(memFrac * 100))", unit: "%",
                              note: memFrac > 0.85 ? "Tight · of \(fmt(Int64(mon.memTotal)))" : "of \(fmt(Int64(mon.memTotal)))",
                              fraction: memFrac, color: memFrac > 0.85 ? Theme.warn : Theme.accent)),
            AnyView(VitalCell(symbol: "cpu", label: "Processor", value: "\(Int(mon.cpu * 100))", unit: "%",
                              note: mon.processes.first.map { "Busiest: \($0.name)" } ?? "Idle",
                              fraction: mon.cpu, color: Theme.calm)),
            AnyView(VitalCell(symbol: mon.battery?.charging == true ? "bolt.fill" : "battery.75percent", label: "Battery",
                              value: mon.battery == nil ? "AC" : "\(level)", unit: mon.battery == nil ? "" : "%",
                              note: mon.battery.map { $0.charging ? "Charging" : $0.onAC ? "On power" : "On battery" } ?? "On power",
                              fraction: Double(level) / 100, color: level <= 20 ? Theme.warn : Theme.good)),
            AnyView(VitalCell(symbol: "dot.radiowaves.left.and.right", label: "Network", value: down.0, unit: "\(down.1)/s",
                              note: "↑ \(fmt(Int64(mon.txRate)))/s · \(mon.ports.count) ports", fraction: nil, color: Theme.calm)),
            AnyView(awakeCell),
        ]
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(cells.indices, id: \.self) { i in
                    if i > 0 { Rectangle().fill(Theme.line).frame(width: 1) }
                    cells[i].frame(minWidth: 150)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        if i > 0 { Rectangle().fill(Theme.line).frame(width: 1) }
                        cells[i]
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Theme.line).frame(height: 1)
                HStack(spacing: 0) {
                    cells[3]
                    Rectangle().fill(Theme.line).frame(width: 1)
                    cells[4]
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    var awakeCell: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Keep Awake", systemImage: awake.isOn ? "cup.and.heat.waves.fill" : "moon.zzz")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(awake.isOn ? Theme.warm : .secondary)
                Spacer()
            }
            Text(awake.isOn ? "On" : "Off")
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(awake.isOn ? Theme.warm : .primary)
                .padding(.top, 10)
            Text(awake.isOn ? (awake.until.map { "Until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Until you stop it") : "Sleeps as usual")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 10)
            HStack {
                Toggle("Keep awake", isOn: Binding(get: { awake.isOn }, set: { $0 ? awake.turnOn() : awake.turnOff() }))
                    .toggleStyle(.switch).tint(Theme.warm).labelsHidden().controlSize(.small)
                Spacer()
                OpenLink(title: "More") { model.room = .awake }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(awake.isOn ? Theme.warm.opacity(0.10) : .clear)
        .animation(.snappy, value: awake.isOn)
    }

    // MARK: Biggest

    var biggest: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if model.scanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning… \(model.scanFiles.formatted()) files · \(fmt(model.scanBytes))")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { model.cancelScan() }.buttonStyle(PillButtonStyle(color: .secondary))
                } else {
                    Text(model.root == nil ? "Scan to see which folders are biggest." : "Click a folder to look inside.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Menu("Scan") {
                        Button("My Files") { model.startScan(NSHomeDirectory()) }
                        Button("Whole Mac") { model.startScan("/") }
                        Button("A Folder…") { pickFolder() }
                    }
                    .fixedSize()
                    if let root = model.root {
                        Button("See all") { model.open(root) }.buttonStyle(PillButtonStyle())
                    }
                }
            }
            .padding(.bottom, 8)
            if let root = model.root {
                ForEach(Array(root.children.prefix(7).enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Divider().overlay(Theme.line) }
                    HStack(spacing: 12) {
                        Text("\(i + 1)")
                            .font(.system(size: 15, design: .serif)).foregroundStyle(.tertiary)
                            .frame(width: 16, alignment: .trailing)
                        FileIcon(path: c.path, aggregate: c.isAggregate, size: 26)
                        Button { if c.isDir { model.open(c) } } label: {
                            HStack(spacing: 6) {
                                Text(c.name).lineLimit(1)
                                if let a = Advisor.explain(c.path, name: c.name) { AdviceBadge(advice: a, compact: true) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(Advisor.explain(c.path, name: c.name)?.text ?? "")
                        Spacer()
                        Meter(fraction: max(0.03, Double(c.size) / Double(max(root.size, 1))), height: 8, count: 14).frame(width: 120)
                        Text(fmt(c.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        if c.isAggregate { Color.clear.frame(width: 70) } else {
                            StageButton(path: c.path, name: c.name, size: c.size, source: "Home")
                        }
                    }
                    .padding(.vertical, 7)
                }
            }
        }
        .tile()
    }

    func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 22, weight: .regular, design: .serif))
    }

    func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.prompt = "Scan"
        if p.runModal() == .OK, let u = p.url { model.startScan(u.path) }
    }
}

/// One line of "Worth doing": what it is, how big, and the button that deals with it.
struct TodoRow: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String
    let detail: String
    let action: String
    var primary = false
    var disabled = false
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Glyph(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(.body.weight(.semibold))
                    Text(value).font(.system(size: 15, design: .serif)).monospacedDigit().foregroundStyle(color)
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action, action: perform)
                .buttonStyle(PillButtonStyle(color: primary ? Theme.accent : .secondary, filled: primary))
                .disabled(disabled)
                .opacity(disabled ? 0.45 : 1)
        }
        .padding(.vertical, 12)
    }
}

/// One cell of the "right now" strip.
struct VitalCell: View {
    let symbol: String
    let label: String
    let value: String
    var unit = ""
    let note: String
    let fraction: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(label, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            BigValue(value: value, unit: unit, size: 30).padding(.top, 10)
            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 10)
            if let fraction {
                Meter(fraction: fraction, color: color, height: 6, count: 14)
            } else {
                Color.clear.frame(height: 6)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                TreemapView(node: node)
                    .frame(height: 220)
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
