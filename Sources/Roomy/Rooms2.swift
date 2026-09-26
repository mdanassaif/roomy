import SwiftUI
import AppKit

// MARK: - Applications

struct AppsRoom: View {
    enum Tab: String, CaseIterable { case updates = "Updates", startup = "Startup", all = "All Apps" }
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .updates
    @State private var sortBySize = true

    var body: some View {
        VStack(spacing: 0) {
            RoomHeader(room: .apps, subtitle: "Updates and startup, in the same place") {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            switch tab {
            case .updates: updates
            case .startup: startup
            case .all: allApps
            }
        }
        .onAppear {
            if model.apps.isEmpty { model.loadApps() }
            if model.startup.isEmpty { model.loadStartup() }
        }
    }

    // Updates
    var updates: some View {
        List {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let d = model.lastUpdateCheck {
                        Text("Checked \(d.formatted(.relative(presentation: .named)))").font(.headline)
                    } else {
                        Text("Look for newer versions").font(.headline)
                    }
                    Text("Asks each app's own update feed (Sparkle) and Homebrew. This is the only time Roomy uses the network.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.checkingUpdates { ProgressView().controlSize(.small) }
                Button(model.checkingUpdates ? "Checking…" : "Check for Updates") { model.checkUpdates() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.checkingUpdates)
            }
            .padding(.vertical, 8)

            if model.lastUpdateCheck != nil {
                Section("From the app's own feed") {
                    if model.sparkleUpdates.isEmpty {
                        Text("Everything is up to date").foregroundStyle(.secondary)
                    }
                    ForEach(model.sparkleUpdates) { a in
                        HStack {
                            FileIcon(path: a.path, size: 28)
                            VStack(alignment: .leading) {
                                Text(a.name).font(.headline)
                                Text("\(a.version) → \(a.latest ?? "?")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Open to Update") {
                                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: a.path), configuration: .init())
                            }
                            .help("Opens the app. Most Sparkle apps offer the update on launch, or under the app menu › Check for Updates")
                        }
                    }
                }
                Section {
                    if Shell.brew == nil {
                        Text("Homebrew isn't installed").foregroundStyle(.secondary)
                    } else if model.brewOutdated.isEmpty {
                        Text("Everything is up to date").foregroundStyle(.secondary)
                    }
                    ForEach(model.brewOutdated) { b in
                        HStack {
                            Image(systemName: b.isCask ? "macwindow" : "terminal").frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(b.name).font(.headline)
                                Text("\(b.installed) → \(b.current)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.busy.contains(b.id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("In Terminal") { model.upgradeInTerminal(b) }.buttonStyle(.link)
                                Button("Update") { model.upgrade(b) }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Homebrew")
                        Spacer()
                        if model.brewOutdated.count > 1 {
                            Button("Update All") { model.brewOutdated.forEach { model.upgrade($0) } }.buttonStyle(.link)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
    }

    // Startup
    var startup: some View {
        List {
            HStack {
                Text("Things that start with your Mac use memory and battery. Switching one off doesn't uninstall it.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.loadStartup() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            ForEach([StartupItem.Kind.loginItem, .userAgent, .globalAgent, .daemon], id: \.self) { kind in
                let items = model.startup.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section(kind.rawValue) {
                        ForEach(items) { item in
                            HStack {
                                Image(systemName: kind == .loginItem ? "power" : kind == .daemon ? "gearshape.2" : "gearshape")
                                    .foregroundStyle(.pink).frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).lineLimit(1)
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                if model.busy.contains(item.id) {
                                    ProgressView().controlSize(.small)
                                } else if kind == .loginItem {
                                    Button("Remove") { model.setStartup(item, false) }
                                } else {
                                    Toggle("", isOn: Binding(get: { item.enabled }, set: { model.setStartup(item, $0) }))
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .help(kind == .daemon ? "Needs your admin password" : "")
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
    }

    // All apps
    var allApps: some View {
        let apps = sortBySize ? model.apps.sorted { ($0.size ?? 0) > ($1.size ?? 0) } : model.apps
        return VStack(spacing: 0) {
            HStack {
                Text("\(model.apps.count) apps · \(fmt(model.apps.reduce(0) { $0 + ($1.size ?? 0) }))").foregroundStyle(.secondary)
                if model.sizingApps { ProgressView().controlSize(.small); Text("measuring…").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Toggle("Sort by size", isOn: $sortBySize).toggleStyle(.checkbox)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 6)
            List(apps) { a in
                HStack(spacing: 10) {
                    FileIcon(path: a.path, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(a.name).font(.headline)
                            if a.isAppStore { Text("App Store").font(.caption2).padding(.horizontal, 5).background(.blue.opacity(0.15), in: Capsule()) }
                        }
                        Text(a.version.isEmpty ? a.bundleID : "Version \(a.version)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(a.size.map(fmt) ?? "—").monospacedDigit().frame(width: 80, alignment: .trailing)
                    let staged = model.isQueued(a.path)
                    Button(staged ? "Added" : "Uninstall") {
                        if staged {
                            model.queue.removeAll { $0.source == "Uninstall" && ($0.path == a.path || $0.name.hasPrefix(a.name + ":")) }
                        } else {
                            model.stageUninstall(a)
                        }
                    }
                    .tint(staged ? .green : nil)
                    .disabled(a.bundleID.hasPrefix("com.apple."))
                    .help("Adds the app plus its support files, caches and preferences to your clean list")
                }
                .padding(.vertical, 2)
                .contextMenu { Button("Reveal in Finder") { reveal(a.path) } }
            }
            .listStyle(.inset)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
        }
    }
}

// MARK: - Snapshots

struct SnapshotsRoom: View {
    @Environment(AppModel.self) private var model
    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var filter: DiffRow.Kind = .all
    @State private var depth = 2

    var body: some View {
        let snaps = model.snapshots.items
        VStack(spacing: 0) {
            RoomHeader(room: .snapshots, subtitle: "Scan again next month and see exactly what grew") {
                if let r = model.root {
                    Button { model.snapshots.save(from: r) } label: { Label("Save Snapshot", systemImage: "camera") }
                }
            }
            if snaps.count < 2 {
                ContentUnavailableView {
                    Label(snaps.isEmpty ? "No snapshots yet" : "One snapshot so far", systemImage: "camera.aperture")
                } description: {
                    Text("Every scan saves a snapshot of folder sizes (turn this off in Settings). Scan again later to compare.")
                }
                snapshotList(snaps).frame(maxHeight: 200)
            } else {
                let from = snaps.first { $0.id == fromID } ?? snaps[1]
                let to = snaps.first { $0.id == toID } ?? snaps[0]
                HStack {
                    Picker("From", selection: Binding(get: { from.id }, set: { fromID = $0 })) {
                        ForEach(snaps) { Text(label($0)).tag($0.id) }
                    }
                    Picker("To", selection: Binding(get: { to.id }, set: { toID = $0 })) {
                        ForEach(snaps) { Text(label($0)).tag($0.id) }
                    }
                    Stepper("Depth \(depth)", value: $depth, in: 1...5).fixedSize()
                }
                .padding(.horizontal, 24)
                HStack {
                    Picker("", selection: $filter) {
                        ForEach(DiffRow.Kind.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                    Spacer()
                    let d = to.total - from.total
                    Text("Total \(d >= 0 ? "+" : "−")\(fmt(abs(d)))")
                        .font(.headline).foregroundStyle(d > 0 ? .orange : .green)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                let rows = SnapshotStore.diff(from, to, maxDepth: depth).filter { filter == .all || $0.kind == filter }
                List {
                    if rows.isEmpty { Text("No changes over 1 MB").foregroundStyle(.secondary) }
                    ForEach(rows.prefix(400)) { r in
                        HStack {
                            Image(systemName: icon(r.kind)).foregroundStyle(color(r.kind)).frame(width: 20)
                            Text(r.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.head)
                            Spacer()
                            Text(r.before.map(fmt) ?? "—").foregroundStyle(.secondary).monospacedDigit().frame(width: 80, alignment: .trailing)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                            Text(r.after.map(fmt) ?? "—").monospacedDigit().frame(width: 80, alignment: .trailing)
                            Text("\(r.delta >= 0 ? "+" : "−")\(fmt(abs(r.delta)))")
                                .monospacedDigit().foregroundStyle(color(r.kind)).frame(width: 90, alignment: .trailing)
                        }
                        .contextMenu { Button("Reveal in Finder") { reveal(r.path) } }
                    }
                    Section("All snapshots") { snapshotRows(snaps) }
                }
                .listStyle(.inset)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
            }
        }
    }

    func snapshotList(_ snaps: [Snapshot]) -> some View {
        List { snapshotRows(snaps) }.listStyle(.inset)
    }

    @ViewBuilder
    func snapshotRows(_ snaps: [Snapshot]) -> some View {
        ForEach(snaps) { s in
            HStack {
                Image(systemName: "camera.aperture").foregroundStyle(.teal)
                Text(label(s))
                Spacer()
                Text(fmt(s.total)).monospacedDigit().foregroundStyle(.secondary)
                Button { model.snapshots.delete(s) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless)
            }
        }
    }

    func label(_ s: Snapshot) -> String {
        let root = s.root == NSHomeDirectory() ? "Home" : s.root == "/" ? "Disk" : URL(fileURLWithPath: s.root).lastPathComponent
        return "\(root) · \(s.date.formatted(date: .abbreviated, time: .shortened))"
    }

    func icon(_ k: DiffRow.Kind) -> String {
        switch k { case .grew: "arrow.up.circle.fill"; case .shrank: "arrow.down.circle.fill"; case .new: "plus.circle.fill"; case .gone: "minus.circle.fill"; case .all: "circle" }
    }

    func color(_ k: DiffRow.Kind) -> Color {
        switch k { case .grew, .new: .orange; case .shrank, .gone: .green; case .all: .primary }
    }
}

// MARK: - Queue

struct QueueBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bytes = model.queuedBytes
        HStack(spacing: 14) {
            Image(systemName: "tray.full.fill")
                .font(.title2).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.green.gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text("Clean list: \(model.queue.count) item\(model.queue.count == 1 ? "" : "s") · \(fmt(bytes))").font(.headline)
                HStack(spacing: 6) {
                    Text("Free \(fmt(model.volume.free))")
                    Image(systemName: "arrow.right").font(.caption2)
                    Text(fmt(model.volume.free + bytes)).bold().foregroundStyle(.green)
                    Text("afterwards")
                }
                .font(.caption).foregroundStyle(.secondary)
                DiskBar(total: model.volume.total, used: model.volume.used, staged: bytes, height: 5).frame(width: 240)
            }
            Spacer()
            Button("Clear") { model.queue.removeAll() }
            Button("Review & Clean") { model.showReview = true }
                .buttonStyle(.borderedProminent).tint(.green)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.2)))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

struct ReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var emptyAfter = false

    var groups: [(source: String, items: [QueueItem])] {
        Dictionary(grouping: model.queue, by: \.source)
            .map { ($0.key, $0.value.sorted { $0.size > $1.size }) }
            .sorted { $0.1.reduce(0) { $0 + $1.size } > $1.1.reduce(0) { $0 + $1.size } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to clean \(fmt(model.queuedBytes))").font(.title2.bold())
                Text("These \(model.queue.count) items go to the Trash. Changed your mind? Press Undo afterwards, or put them back from the Trash.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            List {
                ForEach(groups, id: \.source) { g in
                  Section {
                    ForEach(g.items) { item in
                    HStack {
                        FileIcon(path: item.path, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).lineLimit(1)
                            Text(item.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        Spacer()
                        Text(fmt(item.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        Button { model.unstage(item.path) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.borderless).help("Keep this one")
                    }
                    }
                  } header: {
                    HStack {
                        Text(g.source)
                        Spacer()
                        Text(fmt(g.items.reduce(0) { $0 + $1.size }))
                        Button("Keep all") { g.items.forEach { model.unstage($0.path) } }.buttonStyle(.link)
                    }
                  }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 280)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Frees \(fmt(model.queuedBytes))").font(.headline)
                    Spacer()
                    Text("Free space: \(fmt(model.volume.free)) → \(fmt(model.volume.free + model.queuedBytes))").foregroundStyle(.secondary)
                }
                Toggle(isOn: $emptyAfter) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Empty the Trash too, so the space comes back right away")
                        Text("Permanent. There's no Undo when this is on.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button {
                        model.trashQueue(emptyAfter: emptyAfter) { dismiss() }
                    } label: {
                        if model.trashing { ProgressView().controlSize(.small) }
                        else { Text(emptyAfter ? "Delete \(model.queue.count) Items" : "Move \(model.queue.count) Items to Trash") }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(emptyAfter ? .red : .green)
                    .disabled(model.queue.isEmpty || model.trashing)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 720, height: 560)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Appearance", selection: $model.appearance) {
                Text("Match System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.radioGroup)
            Toggle("Save a snapshot after every scan", isOn: $model.autoSnapshot)
            LabeledContent("Full Disk Access") {
                Button("Open Privacy Settings…") { openFullDiskAccess() }
            }
            Text("Full Disk Access lets Roomy measure the Trash, Mail, Messages and other protected folders.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Private by design: scanning, sizing and matching happen on this Mac. No account, no sync, no analytics, and no filename leaves it. Update checks only run when you press Check for Updates.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 460)
    }
}
