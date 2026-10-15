import SwiftUI
import AppKit

// MARK: - Home

struct HomeRoom: View {
    @Environment(AppModel.self) private var model
    @Environment(SystemMonitor.self) private var mon
    @Environment(KeepAwake.self) private var awake
    @State private var confirmEmpty = false
    @State private var insightColumns = 4

    var freeFraction: Double { Double(model.volume.free) / Double(max(model.volume.total, 1)) }
    var low: Bool { freeFraction < 0.10 }

    var body: some View {
        let _ = model.treeVersion
        Page {
            VStack(alignment: .leading, spacing: 0) {
                greeting.padding(.bottom, 22)
                headline.padding(.bottom, 22)
                insights
                if !model.hasFullDiskAccess { FullDiskAccessCard().padding(.top, 16) }

                sectionTitle("Your Mac today").padding(.top, 34).padding(.bottom, 14)
                today

                sectionTitle(model.root.map { "Biggest in \($0.name)" } ?? "What's taking space").padding(.top, 34).padding(.bottom, 14)
                biggest
            }
            .padding(.horizontal, 32)
            .padding(.top, 26)
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

    var greeting: some View {
        HStack(spacing: 12) {
            Image(systemName: low ? "exclamationmark" : "face.smiling")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background((low ? Theme.warn : Theme.accent).gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(Self.greeting()).font(.title3).foregroundStyle(.secondary)
            Spacer()
            Mono(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
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

    var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headlineText)
                .font(.system(size: 34, weight: .bold, design: .default))
                .tracking(-0.6)
            Text(subheadText).font(.title3).foregroundStyle(.secondary)
        }
    }

    var headlineText: String {
        if freeFraction < 0.05 { return "This Mac has almost run out of space" }
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

    // MARK: Insights

    var insights: some View {
        // Four across when there's room, two when the window is narrow. Never a gap on the right.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: insightColumns), spacing: 16) {
            let free = sizeParts(model.volume.free)
            InsightCard(value: free.0, unit: free.1, meter: 1 - freeFraction, meterColor: low ? Theme.warn : Theme.accent,
                        corner: "of \(sizeParts(model.volume.total).0) \(sizeParts(model.volume.total).1)",
                        title: "free space",
                        detail: low ? "Updates and saving files will start to fail" : "Room for updates and new things",
                        action: "See what's using it", urgent: low) {
                if let root = model.root { model.open(root) } else { model.storageTab = .folders; model.room = .storage }
            }

            let clean = sizeParts(model.smartBytes)
            InsightCard(value: model.cleanLoading && model.smartBytes == 0 ? "…" : clean.0, unit: model.smartBytes > 0 ? clean.1 : "",
                        corner: "\(model.smartItems.reduce(0) { $0 + $1.items.count }) items",
                        title: "Temporary files",
                        detail: "Caches, logs and build files nothing needs",
                        action: model.smartBytes > 0 ? "Clean up…" : "Nothing to clean",
                        disabled: model.smartBytes == 0) { model.stageSmart() }

            let trash = sizeParts(model.trashSize ?? 0)
            InsightCard(value: model.trashSize == nil ? "–" : trash.0, unit: model.trashSize == nil ? "" : trash.1,
                        corner: model.trashSize == nil ? "" : "\(model.trashCount) items",
                        title: model.trashSize == nil ? "Trash size hidden" : "in the Trash",
                        detail: "Still takes space until you empty it",
                        action: "Empty Trash", disabled: model.trashSize == 0) { confirmEmpty = true }

            let updates = model.sparkleUpdates.count + model.brewOutdated.count
            InsightCard(value: model.lastUpdateCheck == nil ? "–" : "\(updates)",
                        corner: model.lastUpdateCheck.map { $0.formatted(.relative(presentation: .named)) } ?? "",
                        title: model.lastUpdateCheck == nil ? "Updates unchecked" : updates == 1 ? "update is waiting" : "updates are waiting",
                        detail: "From app feeds and Homebrew",
                        action: model.lastUpdateCheck == nil ? "Check for updates" : "See updates") {
                model.room = .apps
                if model.lastUpdateCheck == nil { model.checkUpdates() }
            }
        }
        .onGeometryChange(for: Int.self) { $0.size.width >= 760 ? 4 : 2 } action: { insightColumns = $0 }
    }

    // MARK: Today

    var today: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                spaceTile.frame(maxWidth: .infinity)
                HStack(spacing: 16) {
                    batteryTile
                    awakeTile
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 220)
            HStack(spacing: 16) {
                HStack(spacing: 16) {
                    memoryTile
                    cpuTile
                }
                .frame(maxWidth: .infinity)
                networkTile.frame(maxWidth: .infinity)
            }
            .frame(height: 190)
        }
    }

    var spaceTile: some View {
        let used = Double(model.volume.used) / Double(max(model.volume.total, 1))
        let staged = Double(model.queuedBytes) / Double(max(model.volume.total, 1))
        let free = sizeParts(model.volume.free)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                FileIcon(path: "/", size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Space").font(.headline)
                    Text("Macintosh HD").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                ArrowButton { model.room = .storage }
            }
            Spacer(minLength: 10)
            HStack(alignment: .firstTextBaseline) {
                BigValue(value: free.0, unit: "\(free.1) available", size: 40)
                Spacer()
                Mono("\(fmt(model.volume.total)) disk")
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill((low ? Theme.warn : Theme.accent).gradient)
                        .frame(width: max(18, (g.size.width - 8) * used))
                        .padding(4)
                    if staged > 0 {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.good.gradient)
                            .frame(width: max(6, (g.size.width - 8) * min(staged, used)))
                            .padding(4)
                            .offset(x: (g.size.width - 8) * (used - min(staged, used)))
                    }
                }
            }
            .frame(height: 40)
            .padding(.top, 8)
            .animation(.snappy, value: staged)
            HStack {
                if low {
                    Label("Running out of room", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                } else if staged > 0 {
                    Label("\(fmt(model.queuedBytes)) on your clean list", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.good)
                } else {
                    Label("Plenty of room", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                }
                Spacer()
                Mono("\(Int(used * 100))% used")
            }
            .font(.callout)
            .padding(.top, 10)
        }
        .tile()
    }

    var batteryTile: some View {
        let level = mon.battery?.level ?? 100
        let state = mon.battery.map { $0.charging ? "Charging" : $0.onAC ? "On power" : "On battery" } ?? "On power"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    BigValue(value: mon.battery == nil ? "AC" : "\(level)", unit: mon.battery == nil ? "" : "%", size: 38)
                    Mono(state)
                }
                Spacer()
                Image(systemName: mon.battery?.onAC == false ? "battery.75percent" : "bolt.fill")
                    .font(.title3).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            VStack(spacing: 6) {
                Meter(fraction: Double(level) / 100, color: level <= 20 ? Theme.warn : Theme.good, height: 6)
                HStack {
                    Mono("0"); Spacer(); Mono("50"); Spacer(); Mono("100")
                }
            }
        }
        .inkTile(glow: mon.battery?.charging == true ? Theme.good : nil)
    }

    var awakeTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Awake", systemImage: awake.isOn ? "cup.and.heat.waves.fill" : "moon.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(awake.isOn ? Theme.warm : .white.opacity(0.7))
                Spacer()
                ArrowButton { model.room = .awake }
            }
            Spacer()
            Text(awake.isOn ? (awake.until.map { "Awake until \($0.formatted(date: .omitted, time: .shortened))" } ?? "Awake all night")
                            : "Sleeping normally")
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(awake.isOn ? (awake.lidClosedActive ? "Lid closed is fine" : "Keep the lid open") : "Your Mac sleeps as usual")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
                .padding(.top, 2)
            Toggle("Keep awake", isOn: Binding(get: { awake.isOn }, set: { $0 ? awake.turnOn() : awake.turnOff() }))
                .toggleStyle(.switch)
                .tint(Theme.warm)
                .labelsHidden()
                .padding(.top, 12)
        }
        .inkTile(glow: awake.isOn ? Theme.warm : nil)
        .animation(.snappy, value: awake.isOn)
    }

    var memoryTile: some View {
        let frac = Double(mon.memUsed) / Double(max(mon.memTotal, 1))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                IconBadge(symbol: "memorychip", color: Theme.accent)
                Spacer()
                Mono("of \(fmt(Int64(mon.memTotal)))")
            }
            Spacer()
            BigValue(value: "\(Int(frac * 100))", unit: "%", size: 32)
            Text(frac > 0.85 ? "Memory is tight" : "Memory in use").font(.callout).foregroundStyle(.secondary)
            Meter(fraction: frac, color: frac > 0.85 ? Theme.warn : Theme.accent).padding(.top, 10)
        }
        .tile()
    }

    var cpuTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                IconBadge(symbol: "cpu", color: .teal)
                Spacer()
                ArrowButton { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
                    .help("Open Activity Monitor")
            }
            Spacer()
            BigValue(value: "\(Int(mon.cpu * 100))", unit: "%", size: 32)
            Text(mon.processes.first.map { "Busiest: \($0.name)" } ?? "Processor busy")
                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Meter(fraction: mon.cpu, color: .teal).padding(.top, 10)
        }
        .tile()
    }

    var networkTile: some View {
        let down = sizeParts(Int64(mon.rxRate))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Network", systemImage: "dot.radiowaves.left.and.right")
                    .font(.callout.weight(.medium)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Mono("\(mon.ports.count) listening ports")
            }
            Spacer()
            BigValue(value: down.0, unit: "\(down.1)/s down", size: 34)
            HStack {
                let up = sizeParts(Int64(mon.txRate))
                Text("↑ \(up.0) \(up.1)/s up").font(.callout.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                Spacer()
                if let top = mon.processes.first {
                    Mono("top: \(top.name)")
                }
            }
            .padding(.top, 4)
        }
        .inkTile(glow: Theme.accent.opacity(0.8))
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
                    if i > 0 { Divider().opacity(0.5) }
                    HStack(spacing: 12) {
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
                        Meter(fraction: Double(c.size) / Double(max(root.size, 1))).frame(width: 110)
                        Text(fmt(c.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        if c.isAggregate { Color.clear.frame(width: 70) } else {
                            StageButton(path: c.path, name: c.name, size: c.size, source: "Home")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .tile()
    }

    func sectionTitle(_ text: String) -> some View {
        Text(text).font(.title3.weight(.semibold))
    }

    func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.prompt = "Scan"
        if p.runModal() == .OK, let u = p.url { model.startScan(u.path) }
    }
}

/// One of the cards along the top of Home: a number, what it means, and what to do about it.
struct InsightCard: View {
    let value: String
    var unit: String = ""
    var meter: Double? = nil
    var meterColor: Color = Theme.accent
    var corner: String = ""
    let title: String
    let detail: String
    let action: String
    var urgent = false
    var disabled = false
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                BigValue(value: value, unit: unit, size: 28)
                Spacer()
                Mono(corner)
            }
            if let meter {
                Meter(fraction: meter, color: meterColor, height: 4).padding(.top, 8)
            } else {
                Rectangle().fill(.clear).frame(height: 12)
            }
            Text(title).font(.body.weight(.semibold)).padding(.top, 12).lineLimit(1)
            Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true).padding(.top, 2)
            Spacer(minLength: 14)
            Button(action, action: perform)
                .buttonStyle(PillButtonStyle(color: urgent ? Theme.warn : Theme.accent, filled: urgent))
                .disabled(disabled)
                .opacity(disabled ? 0.5 : 1)
        }
        .frame(height: 172)
        .tile(padding: 18)
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
                            .tint(stagedAll ? .green : nil)
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
            Image(systemName: "hand.raised.circle").font(.title3).foregroundStyle(Theme.warn)
            Text("Roomy can't see protected folders like the Trash and Mail, so some sizes look smaller.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Allow…") { openFullDiskAccess() }.buttonStyle(PillButtonStyle())
            Button("Relaunch") { model.relaunch() }.buttonStyle(PillButtonStyle(color: .secondary))
                .help("After switching Roomy on in Full Disk Access, relaunch so it takes effect")
        }
    }
}
