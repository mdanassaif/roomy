import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The notch, put to work for storage. Point at it for a read-only overview (free space, where it's
/// heading, CPU, memory, battery, Keep Awake). Drag a file or folder onto it to measure it and add it
/// to the clean list. It only exists on screens that have a notch.
///
/// While closed, the panel covers exactly the notch (a dead area of the screen anyway), so it can catch
/// drags from Finder. It grows to full size only while open.
@MainActor
final class NotchController {
    static let shared = NotchController()

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private let state = NotchState()
    private var model: AppModel?
    private var monitor: SystemMonitor?
    private var awake: KeepAwake?
    private var collapseWork: DispatchWorkItem?
    private var notchFrame = NSRect.zero
    private var openFrame = NSRect.zero

    static let expandedSize = CGSize(width: 440, height: 184)

    func install(model: AppModel, monitor: SystemMonitor, awake: KeepAwake) {
        guard self.model == nil else { return }
        self.model = model
        self.monitor = monitor
        self.awake = awake
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Builds or removes the panel to match the setting and the current screens.
    func refresh() {
        teardown()
        guard model?.notchOverview == true, let screen = Self.notchScreen(), let model, let monitor, let awake else { return }

        notchFrame = Self.notchRect(on: screen)
        state.notchSize = notchFrame.size
        let size = Self.expandedSize
        openFrame = NSRect(x: notchFrame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)

        let p = NSPanel(contentRect: notchFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .mainMenu + 3
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView:
            NotchView(open: { [weak self] in self?.openMain() },
                      review: { [weak self] in self?.openMain(review: true) },
                      dragging: { [weak self] on in self?.dragChanged(on) },
                      dropped: { [weak self] urls in self?.measure(urls) })
                .environment(state)
                .environment(model)
                .environment(monitor)
                .environment(awake)
        )
        host.sizingOptions = []
        p.contentView = host
        p.orderFrontRegardless()
        panel = p

        let handler: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.track() } }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { handler($0); return $0 }) { monitors.append(l) }
    }

    private func teardown() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if state.expanded { monitor?.stop() }
        state.expanded = false
        state.mode = .overview
        panel?.orderOut(nil)
        panel = nil
    }

    private func track() {
        let p = NSEvent.mouseLocation
        if state.expanded {
            if openFrame.insetBy(dx: -8, dy: -8).contains(p) {
                collapseWork?.cancel(); collapseWork = nil
            } else {
                scheduleCollapse()
            }
        } else if notchFrame.insetBy(dx: -6, dy: 0).contains(p) {
            setExpanded(true)
        }
    }

    private func scheduleCollapse(after delay: Double = 0.25) {
        guard collapseWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            if self.openFrame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) { return }
            self.setExpanded(false)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func setExpanded(_ on: Bool) {
        collapseWork?.cancel(); collapseWork = nil
        guard state.expanded != on else { return }
        if on {
            monitor?.start()
            model?.volume = .current()
            panel?.setFrame(openFrame, display: true)
        } else {
            monitor?.stop()
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { state.expanded = on }
        if !on {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, !self.state.expanded else { return }
                self.state.mode = .overview
                self.panel?.setFrame(self.notchFrame, display: true)
            }
        }
    }

    // MARK: Drop to measure

    private func dragChanged(_ inside: Bool) {
        if inside {
            if case .measured = state.mode {} else { state.mode = .dropHere }
            setExpanded(true)
        } else {
            if state.mode == .dropHere { state.mode = .overview }
            scheduleCollapse(after: 0.4)
        }
    }

    private func measure(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let name = urls.count == 1 ? first.lastPathComponent : "\(first.lastPathComponent) and \(urls.count - 1) more"
        state.mode = .measuring(name)
        DispatchQueue.global(qos: .userInitiated).async {
            let items = urls.map { NotchState.Item(path: $0.path, name: $0.lastPathComponent, size: Sizer.size(of: $0)) }
            DispatchQueue.main.async {
                self.state.mode = .measured(NotchState.Measured(name: name, items: items))
            }
        }
    }

    private func openMain(review: Bool = false) {
        setExpanded(false)
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.title == "Roomy" || $0.identifier?.rawValue.hasPrefix("main") == true }) {
            w.makeKeyAndOrderFront(nil)
        }
        if review, let model, !model.queue.isEmpty { model.showReview = true }
    }

    // MARK: Debug

    func debugImage(mode: NotchState.Mode = .overview) -> NSImage? {
        guard let model, let monitor, let awake else { return nil }
        let saved = (state.expanded, state.mode)
        state.expanded = true
        state.mode = mode
        defer { state.expanded = saved.0; state.mode = saved.1 }
        let r = ImageRenderer(content: NotchView(open: {}, review: {}, dragging: { _ in }, dropped: { _ in })
            .environment(state).environment(model).environment(monitor).environment(awake)
            .frame(width: Self.expandedSize.width + 80, height: Self.expandedSize.height + 30)
            .background(Color(white: 0.85)))
        r.scale = 2
        return r.nsImage
    }

    // MARK: Geometry

    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
    }

    /// The notch in screen coordinates: the gap between the two menu-bar areas beside it.
    static func notchRect(on screen: NSScreen) -> NSRect {
        let f = screen.frame
        let h = screen.safeAreaInsets.top
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return NSRect(x: f.minX + l.width, y: f.maxY - h, width: f.width - l.width - r.width, height: h)
        }
        return NSRect(x: f.midX - 100, y: f.maxY - h, width: 200, height: h)
    }
}

@Observable
final class NotchState {
    struct Item: Equatable {
        let path: String
        let name: String
        let size: Int64
    }

    struct Measured: Equatable {
        let name: String
        let items: [Item]
        var total: Int64 { items.reduce(0) { $0 + $1.size } }
        var path: String { items.first?.path ?? "" }
    }

    enum Mode: Equatable {
        case overview, dropHere, measuring(String), measured(Measured), added(Int64)
    }

    var expanded = false
    var mode: Mode = .overview
    var notchSize = CGSize(width: 200, height: 32)
}

/// Black like the notch itself in both light and dark mode, so it reads as the notch growing.
struct NotchView: View {
    @Environment(NotchState.self) private var state
    @Environment(AppModel.self) private var model
    @Environment(SystemMonitor.self) private var mon
    @Environment(KeepAwake.self) private var awake
    let open: () -> Void
    let review: () -> Void
    let dragging: (Bool) -> Void
    let dropped: ([URL]) -> Void

    var body: some View {
        let size = state.expanded ? NotchController.expandedSize : state.notchSize
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: state.expanded ? 24 : 10,
                                       bottomTrailingRadius: state.expanded ? 24 : 10, style: .continuous)
                    .fill(.black)
                if state.expanded {
                    content
                        .padding(.top, state.notchSize.height + 8)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .transition(.opacity.animation(.easeOut(duration: 0.15).delay(0.08)))
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(state.expanded ? 1 : 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { state.mode == .dropHere }, set: { dragging($0) })) { providers in
            load(providers)
            return true
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    var content: some View {
        Group {
            switch state.mode {
            case .overview: overview
            case .dropHere:
                center(symbol: "arrow.down.to.line", title: "Drop to measure", note: "Roomy weighs it and tells you if it's safe to clear")
            case .measuring(let name):
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Measuring \(name)…").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .measured(let m): measured(m)
            case .added(let bytes):
                VStack(alignment: .leading, spacing: 10) {
                    Label("Added to your clean list", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 17, design: .serif)).foregroundStyle(Theme.good)
                    Text("\(fmt(model.queuedBytes)) waiting in total, including \(fmt(bytes)) just now. Nothing is removed until you review it.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    HStack {
                        Spacer()
                        Button("Review in Roomy", action: review).buttonStyle(PillButtonStyle(color: Theme.accent, filled: true))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .foregroundStyle(.white)
    }

    var overview: some View {
        let f = model.forecast
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                BigValue(value: sizeParts(model.volume.free).0, unit: "\(sizeParts(model.volume.free).1) free", size: 24)
                Spacer()
                Text(f.text).font(.caption.weight(.medium)).foregroundStyle(f.urgent ? Theme.warn : .secondary).lineLimit(1)
            }
            DiskBar(total: model.volume.total, used: model.volume.used, staged: model.queuedBytes, height: 6, count: 34)
            HStack(spacing: 0) {
                stat("CPU", String(format: "%.0f%%", mon.cpu * 100))
                stat("Memory", "\(Int(Double(mon.memUsed) / Double(max(mon.memTotal, 1)) * 100))%")
                if let b = mon.battery { stat("Battery", "\(b.level)%" + (b.charging ? " charging" : "")) }
                stat("Keep Awake", awake.isOn ? "On" : "Off", color: awake.isOn ? Theme.warm : nil)
            }
            HStack {
                Label("Drop a file here to measure it", systemImage: "arrow.down.to.line")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button(action: open) {
                    HStack(spacing: 3) {
                        Text("Open Roomy")
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    func measured(_ m: NotchState.Measured) -> some View {
        let advice = m.items.count == 1 ? Advisor.explain(m.path, name: m.items[0].name) : nil
        let protected = m.items.contains { Safety.isProtected($0.path) }
        let s = sizeParts(m.total)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                FileIcon(path: m.path, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    Text(((m.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                BigValue(value: s.0, unit: s.1, size: 28)
            }
            Text(protected ? "Protected by macOS. Roomy won't remove it."
                 : advice.map { "\($0.verdict.label). \($0.text)" } ?? "Roomy doesn't know this one. Check before removing it.")
                .font(.caption)
                .foregroundStyle(protected ? Theme.warn : advice?.verdict.color ?? .secondary)
                .lineLimit(2)
                .padding(.top, 12)
            Spacer(minLength: 0)
            HStack {
                Button("Reveal") { reveal(m.path) }.buttonStyle(PillButtonStyle(color: .secondary))
                Spacer()
                Button("Add to clean list") {
                    for i in m.items { model.stage(path: i.path, name: i.name, size: i.size, source: "Notch") }
                    state.mode = .added(m.total)
                }
                .buttonStyle(PillButtonStyle(color: Theme.accent, filled: true))
                .disabled(protected || m.total == 0)
                .opacity(protected || m.total == 0 ? 0.45 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func center(symbol: String, title: String, note: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 20, design: .serif))
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func stat(_ title: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.callout.monospacedDigit()).foregroundStyle(color ?? .white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func load(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { dropped(urls) }
    }
}
