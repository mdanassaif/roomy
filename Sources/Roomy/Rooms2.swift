import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Applications

struct AppsRoom: View {
    enum Tab: String, CaseIterable { case all = "Installed", startup = "Startup", updates = "Updates" }
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = ProcessInfo.processInfo.environment["ROOMY_TAB"].flatMap(Tab.init(rawValue:)) ?? .all
    @State private var sortBySize = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoomHeader(room: .apps, subtitle: subtitle) { EmptyView() }
            TabStrip(selection: $tab, tabs: tabs)
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
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

    var waiting: Int { model.sparkleUpdates.count + model.brewOutdated.count }

    var tabs: [(value: Tab, title: String)] {
        [(.all, "Installed"), (.startup, "Startup"), (.updates, waiting > 0 ? "Updates \(waiting)" : "Updates")]
    }

    var subtitle: String {
        switch tab {
        case .all:
            let total = model.apps.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
            return model.sizingApps ? "\(model.apps.count) apps, measuring" : "\(model.apps.count) apps, \(fmt(total)) on disk"
        case .startup:
            return "\(model.startup.filter { $0.enabled }.count) things start with your Mac. Switching one off doesn't uninstall it"
        case .updates:
            return model.lastUpdateCheck.map { "Checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet"
        }
    }

    // Updates
    @ViewBuilder
    var updates: some View {
        if model.lastUpdateCheck == nil && !model.checkingUpdates {
            let feeds = model.apps.filter { $0.feedURL != nil && !$0.isAppStore }.count
            VStack(spacing: 12) {
                Text("Find newer versions").font(.system(size: 13, weight: .medium))
                Text("Roomy asks \(feeds > 0 ? "\(feeds) apps" : "each app") through their own update feeds\(Shell.brew == nil ? "" : ", plus Homebrew"). It's the only time Roomy goes online.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button("Check for Updates") { model.checkUpdates() }
                    .buttonStyle(ActionButtonStyle(color: Theme.accent, filled: true))
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 80)
        } else {
            List {
                HStack {
                    if model.checkingUpdates {
                        ProgressView().controlSize(.small)
                        Text("Asking update feeds…").foregroundStyle(.secondary)
                    } else if let d = model.lastUpdateCheck {
                        Text("Checked \(d.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Again") { model.checkUpdates() }
                        .buttonStyle(ActionButtonStyle(color: .secondary))
                        .disabled(model.checkingUpdates)
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)

                if model.lastUpdateCheck != nil {
                    Section("From each app's own feed") {
                        if model.sparkleUpdates.isEmpty {
                            Label("Everything is up to date", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                        }
                        ForEach(model.sparkleUpdates) { a in
                            HStack(spacing: 12) {
                                FileIcon(path: a.path, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.name).font(.body.weight(.semibold))
                                    Text("\(a.version) → \(a.latest ?? "?")").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Open to Update") {
                                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: a.path), configuration: .init())
                                }
                                .buttonStyle(ActionButtonStyle(color: Theme.accent))
                                .help("Opens the app. Most apps offer the update on launch, or under the app menu › Check for Updates")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    Section {
                        if Shell.brew == nil {
                            Text("Homebrew isn't installed").foregroundStyle(.secondary)
                        } else if model.brewOutdated.isEmpty {
                            Label("Everything is up to date", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                        }
                        ForEach(model.brewOutdated) { b in
                            HStack(spacing: 12) {
                                Image(systemName: b.isCask ? "macwindow" : "terminal").foregroundStyle(.secondary).frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.name).font(.body.weight(.semibold))
                                    Text("\(b.installed) → \(b.current)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.busy.contains(b.id) {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Button("In Terminal") { model.upgradeInTerminal(b) }.buttonStyle(.borderless).foregroundStyle(.secondary)
                                    Button("Update") { model.upgrade(b) }.buttonStyle(ActionButtonStyle(color: Theme.accent))
                                }
                            }
                            .padding(.vertical, 3)
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
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
        }
    }

    // Startup
    var startup: some View {
        List {
            HStack {
                Spacer()
                Button { model.loadStartup() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh")
            }
            ForEach([StartupItem.Kind.loginItem, .userAgent, .globalAgent, .daemon], id: \.self) { kind in
                let items = model.startup.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section(kind.rawValue) {
                        ForEach(items) { item in
                            HStack {
                                Image(systemName: kind == .loginItem ? "power" : kind == .daemon ? "gearshape.2" : "gearshape")
                                    .foregroundStyle(.secondary).frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name).lineLimit(1)
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                if model.busy.contains(item.id) {
                                    ProgressView().controlSize(.small)
                                } else if kind == .loginItem {
                                    Button("Remove") { model.setStartup(item, false) }.buttonStyle(ActionButtonStyle(color: .secondary))
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
                .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
    }

    // All apps
    var allApps: some View {
        let apps = sortBySize ? model.apps.sorted { ($0.size ?? 0) > ($1.size ?? 0) } : model.apps
        return VStack(spacing: 0) {
            HStack {
                Spacer()
                Toggle("Sort by size", isOn: $sortBySize).toggleStyle(.checkbox)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 28)
            .padding(.bottom, 4)
            RowList {
                ForEach(apps) { a in
                    HoverRow(height: 42) {
                        FileIcon(path: a.path, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(a.version.isEmpty ? a.bundleID : "Version \(a.version)\(a.isAppStore ? " · App Store" : "")")
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 12)
                        Text(a.size.map(fmt) ?? "–").font(.system(size: 13).monospacedDigit()).frame(width: 74, alignment: .trailing)
                        let staged = model.isQueued(a.path)
                        let apple = a.bundleID.hasPrefix("com.apple.")
                        Button(staged ? "Added" : "Uninstall") {
                            if staged {
                                model.queue.removeAll { $0.source == "Uninstall" && ($0.path == a.path || $0.name.hasPrefix(a.name + ":")) }
                            } else {
                                model.stageUninstall(a)
                            }
                        }
                        .buttonStyle(ActionButtonStyle(color: staged ? Theme.good : .primary))
                        .disabled(apple)
                        .opacity(apple ? 0.35 : 1)
                        .frame(width: 76, alignment: .trailing)
                        .help("Adds the app plus its support files, caches and preferences to your clean list")
                    }
                    .contextMenu { Button("Reveal in Finder") { reveal(a.path) } }
                }
            }
        }
    }
}

// MARK: - Snapshots

struct ChangesView: View {
    @Environment(AppModel.self) private var model
    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var filter: DiffRow.Kind = .all
    @State private var depth = 2

    var body: some View {
        let snaps = model.snapshots.items
        VStack(spacing: 0) {
            if let r = model.root {
                HStack {
                    Spacer()
                    Button { model.snapshots.save(from: r) } label: { Label("Save Snapshot", systemImage: "camera") }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 6)
            }
            if snaps.count < 2 {
                ContentUnavailableView {
                    Label(snaps.isEmpty ? "No snapshots yet" : "One snapshot so far", systemImage: "clock.arrow.circlepath")
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
                .padding(.horizontal, 32)
                HStack {
                    Picker("", selection: $filter) {
                        ForEach(DiffRow.Kind.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                    Spacer()
                    let d = to.total - from.total
                    Text("Total \(d >= 0 ? "+" : "−")\(fmt(abs(d)))")
                        .font(.headline).foregroundStyle(d > 0 ? Theme.warm : Theme.good)
                }
                .padding(.horizontal, 32)
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
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 80) }
            }
        }
    }

    func snapshotList(_ snaps: [Snapshot]) -> some View {
        List { snapshotRows(snaps) }.listStyle(.inset)
                .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    func snapshotRows(_ snaps: [Snapshot]) -> some View {
        ForEach(snaps) { s in
            HStack {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
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
        switch k { case .grew, .new: Theme.warm; case .shrank, .gone: Theme.good; case .all: .primary }
    }
}

// MARK: - Queue

struct QueueBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let bytes = model.queuedBytes
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.queue.count) item\(model.queue.count == 1 ? "" : "s") · \(fmt(bytes))").font(.system(size: 13, weight: .medium))
                Text("\(fmt(model.volume.free)) free now, \(fmt(model.volume.free + bytes)) afterwards")
                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear") { model.queue.removeAll() }.buttonStyle(ActionButtonStyle(color: .secondary))
            Button("Review and Clean") { model.showReview = true }
                .buttonStyle(ActionButtonStyle(color: Theme.accent, filled: true))
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
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
                .scrollContentBackground(.hidden)
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
                    .tint(emptyAfter ? .red : nil)
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
    @Environment(KeepAwake.self) private var awake
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Appearance", selection: $model.appearance) {
                    Text("Match System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Toggle("Save a snapshot after every scan", isOn: $model.autoSnapshot)
            }
            Section {
                LabeledContent("Lid-closed mode") {
                    if awake.lidSetupDone {
                        Text("Set up").foregroundStyle(.secondary)
                    } else {
                        Button("Set Up…") { awake.setUpLidClosed() }
                    }
                }
                LabeledContent("Full Disk Access") {
                    Button("Open Privacy Settings…") { openFullDiskAccess() }
                }
            } footer: {
                Text("Private by design: scanning happens on this Mac. No account, no sync, no analytics. Roomy only uses the network when you press Check for Updates.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
