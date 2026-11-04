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
                .task {
                    DebugSnapshot.scheduleIfAsked(model: model)
                }
        }
        .windowStyle(.hiddenTitleBar)
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
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.line).frame(width: 1)
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

                if !model.queue.isEmpty {
                    QueueBar()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Theme.canvas)
            .overlay(alignment: .top) {
                if let t = model.toast {
                    HStack(spacing: 12) {
                        Text(t.text).font(.system(size: 12.5))
                        if t.canUndo {
                            Button("Undo") { model.undoTrash() }
                                .buttonStyle(ActionButtonStyle(color: Theme.accent))
                                .keyboardShortcut("z", modifiers: .command)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    .padding(.top, 12)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: model.queue.isEmpty)
            .animation(.easeOut(duration: 0.15), value: model.toast)
        }
        .background(Theme.chrome)
        .ignoresSafeArea()
        .background(WindowTweaks())
        .background(shortcuts)
        .tint(Theme.accent)
        .sheet(isPresented: $model.showReview) { ReviewSheet().environment(model).tint(Theme.accent) }
        .overlay {
            if model.showSearch {
                ZStack(alignment: .top) {
                    // Clicking anywhere outside closes search.
                    Color.black.opacity(0.25)
                        .contentShape(Rectangle())
                        .onTapGesture { model.showSearch = false }
                    SearchPalette().padding(.top, 72)
                }
                .ignoresSafeArea()
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .onAppear {
            model.applyAppearance()
            model.refreshTrash()
            model.autoStart()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshTrash(force: false)
            model.refreshVolume()
        }
    }

    /// ⌘K to search, ⌘1 to ⌘5 for pages, ⌘R to scan again.
    var shortcuts: some View {
        ZStack {
            Button("") { model.showSearch = true }.keyboardShortcut("k", modifiers: .command)
            Button("") { model.startScan() }.keyboardShortcut("r", modifiers: .command)
            ForEach(Array(Room.allCases.enumerated()), id: \.element) { i, r in
                Button("") { model.room = r }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    /// One flat list of rooms, free space as one quiet line at the bottom.
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button { model.showSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).frame(width: 18)
                    Text("Search")
                    Spacer()
                    Text("⌘K").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            ForEach(Room.allCases) { item($0) }
            Spacer()
            Text("\(fmt(model.volume.free)) free")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
        }
        .padding(.top, 44)
        .padding(.horizontal, 8)
        .frame(width: 196)
    }

    func item(_ r: Room) -> some View {
        let selected = model.room == r
        return Button { model.room = r } label: {
            HStack(spacing: 8) {
                Image(systemName: r == .awake && awake.isOn ? "cup.and.heat.waves.fill" : r.icon)
                    .font(.system(size: 12.5))
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                    .frame(width: 18)
                Text(r.title)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if let b = badge(for: r) {
                    Text(b).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(selected ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func badge(for r: Room) -> String? {
        switch r {
        case .clean where model.smartBytes > 0: fmt(model.smartBytes)
        case .apps where !model.sparkleUpdates.isEmpty || !model.brewOutdated.isEmpty:
            "\(model.sparkleUpdates.count + model.brewOutdated.count)"
        case .awake where awake.isOn: "On"
        default: nil
        }
    }
}

/// Lets the window be dragged from its frame, since the title bar is hidden.
struct WindowTweaks: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isMovableByWindowBackground = true
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.backgroundColor = NSColor(Theme.chrome)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
                    Text(fmt(model.volume.free)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
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
        .onAppear { mon.start(); model.refreshVolume() }
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
