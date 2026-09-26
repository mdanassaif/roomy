import SwiftUI
import AppKit

@main
struct RoomyApp: App {
    @State private var model = AppModel()
    @State private var monitor = SystemMonitor()

    var body: some Scene {
        Window("Roomy", id: "main") {
            ContentView()
                .environment(model)
                .environment(monitor)
        }
        .defaultSize(width: 1120, height: 760)

        MenuBarExtra {
            MonitorView()
                .environment(model)
                .environment(monitor)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "internaldrive")
                Text(model.menuBarText)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model)
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: Binding(get: { model.room }, set: { if let r = $0 { model.room = r } })) {
                ForEach(Room.allCases) { r in
                    Label {
                        Text(r.title)
                    } icon: {
                        Image(systemName: r.icon).foregroundStyle(r.color)
                    }
                    .tag(r)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Macintosh HD").font(.caption.bold())
                    DiskBar(total: model.volume.total, used: model.volume.used, staged: model.queuedBytes, height: 6)
                    Text("\(fmt(model.volume.free)) free of \(fmt(model.volume.total))").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(14)
            }
        } detail: {
            ZStack(alignment: .bottom) {
                Group {
                    switch model.room {
                    case .overview: OverviewRoom()
                    case .storage: StorageRoom()
                    case .clean: CleanRoom()
                    case .large: LargeFilesRoom()
                    case .apps: AppsRoom()
                    case .snapshots: SnapshotsRoom()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if !model.queue.isEmpty {
                    QueueBar()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let t = model.toast {
                    Text(t)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 8)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.queue.isEmpty)
            .animation(.snappy, value: model.toast)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Appearance", selection: $model.appearance) {
                        Text("Match System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                } label: {
                    Image(systemName: "circle.lefthalf.filled")
                }
                .help("Appearance")
            }
        }
        .sheet(isPresented: $model.showReview) { ReviewSheet().environment(model) }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
            model.applyAppearance()
            model.refreshTrash()
        }
    }
}

// MARK: - Menu bar monitor

struct MonitorView: View {
    @Environment(AppModel.self) private var model
    @Environment(SystemMonitor.self) private var mon
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "internaldrive.fill").foregroundStyle(.purple)
                Text("Macintosh HD").font(.headline)
                Spacer()
                Text("\(fmt(model.volume.free)) free").font(.callout.monospacedDigit())
            }
            DiskBar(total: model.volume.total, used: model.volume.used, height: 8)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    stat("cpu", "CPU", String(format: "%.0f%%", mon.cpu * 100), mon.cpu, .blue)
                    stat("memorychip", "Memory",
                         "\(fmt(Int64(mon.memUsed))) / \(fmt(Int64(mon.memTotal)))",
                         Double(mon.memUsed) / Double(max(mon.memTotal, 1)), .green)
                }
                GridRow {
                    if let b = mon.battery {
                        stat(b.charging ? "battery.100.bolt" : "battery.75", "Battery",
                             "\(b.level)%\(b.charging ? " charging" : b.onAC ? " on power" : "")", Double(b.level) / 100, .orange)
                    } else {
                        stat("powerplug", "Power", "AC", 1, .orange)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Network", systemImage: "network").font(.caption).foregroundStyle(.secondary)
                        Text("↓ \(rate(mon.rxRate))  ↑ \(rate(mon.txRate))").font(.callout.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()
            Text("Busiest processes").font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(mon.processes.prefix(5)) { p in
                HStack {
                    Text(p.name).lineLimit(1)
                    Spacer()
                    Text(fmt(p.memKB * 1024)).foregroundStyle(.secondary).font(.caption.monospacedDigit())
                    Text(String(format: "%.1f%%", p.cpu)).font(.callout.monospacedDigit()).frame(width: 55, alignment: .trailing)
                }
            }

            if !mon.ports.isEmpty {
                Divider()
                Text("Listening ports").font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(mon.ports) { p in
                            HStack {
                                Text(":" + (p.address.split(separator: ":").last.map(String.init) ?? "")).font(.callout.monospacedDigit().bold())
                                Text(p.command).lineLimit(1)
                                Spacer()
                                Text("pid \(p.pid)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 110)
            }

            Divider()
            HStack {
                Button {
                    show()
                    model.room = .overview
                    model.startScan()
                } label: { Label("Scan", systemImage: "magnifyingglass") }
                    .buttonStyle(.borderedProminent)
                Button("Open Roomy") { show() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { mon.start(); model.volume = .current() }
        .onDisappear { mon.stop() }
    }

    func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    func stat(_ icon: String, _ title: String, _ value: String, _ frac: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
            ProgressView(value: min(1, max(0, frac))).tint(c)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func rate(_ bps: Double) -> String { fmt(Int64(bps)) + "/s" }
}
