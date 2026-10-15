import SwiftUI
import AppKit

@main
struct RoomyApp: App {
    @State private var model = AppModel()
    @State private var monitor = SystemMonitor()
    @State private var awake = KeepAwake()

    var body: some Scene {
        Window("Roomy", id: "main") {
            ContentView()
                .environment(model)
                .environment(monitor)
                .environment(awake)
        }
        .defaultSize(width: 1080, height: 740)

        MenuBarExtra {
            MonitorView()
                .environment(model)
                .environment(monitor)
                .environment(awake)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: awake.isOn ? "cup.and.heat.waves.fill" : "internaldrive")
                Text(model.menuBarText)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model).environment(awake)
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(KeepAwake.self) private var awake

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: Binding(get: { model.room }, set: { if let r = $0 { model.room = r } })) {
                item(.home)
                Section("Your files") {
                    item(.clean)
                    item(.storage)
                }
                Section("Apps") {
                    item(.apps)
                }
                Section("This Mac") {
                    item(.awake)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    DiskBar(total: model.volume.total, used: model.volume.used, staged: model.queuedBytes, height: 5)
                    Text("\(fmt(model.volume.free)) free").font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
        } detail: {
            ZStack(alignment: .bottom) {
                Group {
                    switch model.room {
                    case .home: HomeRoom()
                    case .clean: CleanRoom()
                    case .storage: StorageRoom()
                    case .apps: AppsRoom()
                    case .awake: AwakeRoom()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Theme.canvas)

                if !model.queue.isEmpty {
                    QueueBar()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay(alignment: .top) {
                if let t = model.toast {
                    HStack(spacing: 12) {
                        Text(t.text)
                        if t.canUndo {
                            Button("Undo") { model.undoTrash() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .keyboardShortcut("z", modifiers: .command)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.queue.isEmpty)
            .animation(.snappy, value: model.toast)
        }
        .tint(Theme.accent)
        .sheet(isPresented: $model.showReview) { ReviewSheet().environment(model).tint(Theme.accent) }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            model.applyAppearance()
            model.refreshTrash()
            model.autoStart()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshTrash()
            model.volume = .current()
        }
    }

    func item(_ r: Room) -> some View {
        Label(r.title, systemImage: r == .awake && awake.isOn ? "cup.and.heat.waves.fill" : r.icon)
            .badge(badge(for: r))
            .tag(r)
    }

    func badge(for r: Room) -> Text? {
        switch r {
        case .clean where model.smartBytes > 0: Text(fmt(model.smartBytes))
        case .apps where !model.sparkleUpdates.isEmpty || !model.brewOutdated.isEmpty:
            Text("\(model.sparkleUpdates.count + model.brewOutdated.count)")
        case .awake where awake.isOn: Text("On")
        default: nil
        }
    }
}

// MARK: - Menu bar

struct MonitorView: View {
    @Environment(AppModel.self) private var model
    @Environment(SystemMonitor.self) private var mon
    @Environment(\.openWindow) private var openWindow
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AwakeMenuRow()

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fmt(model.volume.free)).font(.title3.weight(.semibold)).monospacedDigit()
                    Text("free").foregroundStyle(.secondary)
                    Spacer()
                    Text("of \(fmt(model.volume.total))").font(.caption).foregroundStyle(.secondary)
                }
                DiskBar(total: model.volume.total, used: model.volume.used, height: 6)
            }

            HStack(spacing: 0) {
                stat("CPU", String(format: "%.0f%%", mon.cpu * 100))
                stat("Memory", "\(Int(Double(mon.memUsed) / Double(max(mon.memTotal, 1)) * 100))%")
                if let b = mon.battery {
                    stat("Battery", "\(b.level)%\(b.charging ? " ⚡︎" : "")")
                }
                stat("Network", "↓ \(rate(mon.rxRate))")
            }

            DisclosureGroup("Processes and ports", isExpanded: $showDetails) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(mon.processes.prefix(5)) { p in
                        HStack {
                            Text(p.name).lineLimit(1)
                            Spacer()
                            Text(fmt(p.memKB * 1024)).foregroundStyle(.secondary).font(.caption.monospacedDigit())
                            Text(String(format: "%.0f%%", p.cpu)).font(.callout.monospacedDigit()).frame(width: 44, alignment: .trailing)
                        }
                    }
                    if !mon.ports.isEmpty {
                        Divider().padding(.vertical, 2)
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(mon.ports) { p in
                                    HStack {
                                        Text(":" + (p.address.split(separator: ":").last.map(String.init) ?? ""))
                                            .font(.callout.monospacedDigit().weight(.semibold))
                                        Text(p.command).lineLimit(1)
                                        Spacer()
                                        Text("pid \(p.pid)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 100)
                    }
                }
                .padding(.top, 6)
            }
            .font(.callout)

            Divider()
            HStack {
                Button("Open Roomy") { show() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
        .tint(Theme.accent)
        .onAppear { mon.start(); model.volume = .current() }
        .onDisappear { mon.stop() }
    }

    func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func rate(_ bps: Double) -> String { fmt(Int64(bps)) + "/s" }
}
