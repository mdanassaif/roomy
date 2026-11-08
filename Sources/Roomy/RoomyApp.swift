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
    @Environment(KeepAwake.self) private var awake
    @Environment(\.openWindow) private var openWindow
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            awakeSection.padding(14)
            Divider()
            storage.padding(14)
            Divider()
            stats.padding(14)
            Divider()
            details
            Divider()
            footer.padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 340)
        .background(Theme.canvas)
        .tint(Theme.accent)
        .onAppear { mon.start(); model.refreshVolume() }
        .onDisappear { mon.stop() }
    }

    // MARK: Keep Awake

    var awakeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: awake.isOn ? "cup.and.heat.waves.fill" : "cup.and.saucer")
                    .font(.system(size: 15))
                    .foregroundStyle(awake.isOn ? Theme.good : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep Awake").font(.system(size: 13, weight: .semibold))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(awakeLine(ctx.date)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(get: { awake.isOn }, set: { $0 ? awake.turnOn() : awake.turnOff() }))
                    .toggleStyle(.switch).controlSize(.small).tint(Theme.good).labelsHidden()
            }
            HStack(spacing: 5) {
                ForEach([("30m", 1800.0), ("1h", 3600), ("2h", 7200), ("4h", 14400), ("8h", 28800)], id: \.0) { d in
                    Button { awake.turnOn(for: d.1) } label: { Text(d.0).frame(maxWidth: .infinity) }
                        .buttonStyle(ActionButtonStyle(color: .secondary))
                }
            }
            .help("Stay awake for this long from now")
            if let error = awake.lastError {
                Text(error).font(.system(size: 11.5)).foregroundStyle(Theme.warn)
            }
        }
    }

    func awakeLine(_ now: Date) -> String {
        guard awake.isOn else { return awake.lidSetupDone ? "Off · works with the lid closed" : "Off · keep the lid open" }
        guard let until = awake.until else { return "On until you turn it off" }
        let s = max(0, Int(until.timeIntervalSince(now))), h = s / 3600, m = (s % 3600) / 60
        let left = h > 0 ? "\(h)h \(m)m" : m > 0 ? "\(m)m \(s % 60)s" : "\(s)s"
        return "On · \(left) left, until \(until.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: Storage

    var storage: some View {
        let free = sizeParts(model.volume.free)
        let ready = model.smartBytes + (model.trashSize ?? 0)
        let low = Double(model.volume.free) / Double(max(model.volume.total, 1)) < 0.1
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                BigValue(value: free.0, unit: free.1, size: 24).foregroundStyle(low ? Theme.warn : .primary)
                Text("free").font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
                Text("of \(fmt(model.volume.total))").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            DiskBar(total: model.volume.total, used: model.volume.used, height: 6)
            if ready > 0 {
                Button {
                    model.room = .clean; show()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal").foregroundStyle(Theme.good)
                        Text("\(fmt(ready)) safe to clear")
                        Spacer()
                        Text("Clean Up").foregroundStyle(Theme.accent)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Stats

    var stats: some View {
        let mem = Double(mon.memUsed) / Double(max(mon.memTotal, 1))
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Meter(label: "CPU", value: String(format: "%.0f%%", mon.cpu * 100), fraction: mon.cpu)
                Meter(label: "Memory", value: "\(Int(mem * 100))%", fraction: mem,
                      detail: "\(fmt(Int64(mon.memUsed))) of \(fmt(Int64(mon.memTotal)))")
            }
            GridRow {
                if let b = mon.battery {
                    Meter(label: "Battery", value: "\(b.level)%", fraction: Double(b.level) / 100,
                          detail: b.charging ? "Charging" : b.onAC ? "Plugged in" : "On battery",
                          color: b.level <= 20 && !b.onAC ? Theme.warn : Theme.good)
                } else {
                    Meter(label: "Power", value: "Plugged in", fraction: nil)
                }
                Meter(label: "Network", value: "↓ " + rate(mon.rxRate), fraction: nil, detail: "↑ " + rate(mon.txRate) + " up")
            }
        }
    }

    // MARK: Processes

    var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showDetails.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showDetails ? 90 : 0)).foregroundStyle(.secondary).frame(width: 12)
                    Text("Busiest apps and open ports").font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    if let top = mon.processes.first {
                        Text(top.name).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 14).frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDetails {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(mon.processes.prefix(5)) { p in
                        HStack(spacing: 8) {
                            Text(p.name).lineLimit(1)
                            Spacer()
                            Text(fmt(p.memKB * 1024)).foregroundStyle(.secondary)
                            Text(String(format: "%.0f%%", p.cpu)).frame(width: 40, alignment: .trailing)
                        }
                    }
                    if !mon.ports.isEmpty {
                        Text("Listening ports").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.top, 6)
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(mon.ports) { p in
                                    HStack(spacing: 8) {
                                        Text(":" + (p.address.split(separator: ":").last.map(String.init) ?? "")).fontWeight(.semibold)
                                        Text(p.command).lineLimit(1)
                                        Spacer()
                                        Text("pid \(p.pid)").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 96)
                    }
                }
                .font(.system(size: 12).monospacedDigit())
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }

    // MARK: Footer

    var footer: some View {
        HStack {
            Button { show() } label: {
                HStack(spacing: 5) { Text("Open Roomy"); Image(systemName: "arrow.up.forward").font(.system(size: 9, weight: .semibold)) }
            }
            .buttonStyle(ActionButtonStyle(color: Theme.accent))
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
    }

    func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    func rate(_ bps: Double) -> String { fmt(Int64(bps)) + "/s" }
}

/// A small labelled reading with an optional bar underneath.
struct Meter: View {
    let label: String
    let value: String
    let fraction: Double?
    var detail: String? = nil
    var color: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            if let fraction {
                StackBar(parts: [(min(max(fraction, 0), 1), fraction > 0.85 ? Theme.warn : color)], height: 4, gap: 0)
            }
            if let detail {
                Text(detail).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
    }
}
