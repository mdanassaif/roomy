import SwiftUI
import AppKit

struct DiskBar: View {
    let total: Int64
    let used: Int64
    var staged: Int64 = 0
    var height: CGFloat = 6

    var body: some View {
        let t = Double(max(total, 1))
        let s = Double(min(staged, used)) / t
        StackBar(parts: [(Double(used) / t - s, Theme.accent), (s, Theme.good)], height: height)
    }
}

struct StageButton: View {
    @Environment(AppModel.self) private var model
    let path: String
    let name: String
    let size: Int64
    let source: String

    var body: some View {
        let queued = model.isQueued(path)
        let covered = !queued && model.isCovered(path)
        if Safety.isProtected(path) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 70)
                .help("Protected. Roomy won't remove this folder itself, but you can go inside it and clean what's there.")
        } else {
            Button {
                model.toggle(path: path, name: name, size: size, source: source)
            } label: {
                Text(queued || covered ? "Added" : "Add").frame(minWidth: 40)
            }
            .buttonStyle(ActionButtonStyle(color: queued || covered ? Theme.good : .primary))
            .disabled(covered)
            .frame(width: 70)
            .help(queued ? "Remove from your clean list" : covered ? "Its folder is already on your clean list" : "Add to your clean list. Nothing is deleted until you review it.")
        }
    }
}

struct FileIcon: View {
    let path: String
    var aggregate = false
    var size: CGFloat = 18

    private static let cache = NSCache<NSString, NSImage>()
    private static func icon(_ path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    var body: some View {
        if aggregate {
            Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary).frame(width: size, height: size)
        } else {
            Image(nsImage: Self.icon(path)).resizable().frame(width: size, height: size)
        }
    }
}

struct SizeBar: View {
    let fraction: Double
    var color: Color = Theme.accent

    var body: some View {
        StackBar(parts: [(max(0.02, fraction), color)], height: 4).frame(width: 80)
    }
}

struct RoomHeader<Trailing: View>: View {
    let room: Room
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(room.title).font(.system(size: 20, weight: .semibold)).tracking(-0.2)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }
}

/// A plain row that lights up under the pointer. Hover lives here so only this row redraws.
struct HoverRow<Content: View>: View {
    var height: CGFloat = 44
    @ViewBuilder var content: Content
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 10)
            .frame(minHeight: height)
            .background(hovered ? Color.primary.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

/// A scrolling column of rows. Only what's on screen gets built.
struct RowList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 18)
                .padding(.bottom, 90)
        }
    }
}

/// Text tabs, styled like the sidebar.
struct TabStrip<T: Hashable>: View {
    @Binding var selection: T
    let tabs: [(value: T, title: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.value) { tab in
                let on = tab.value == selection
                Button { selection = tab.value } label: {
                    Text(tab.title)
                        .font(.system(size: 12.5, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(on ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// When the results are from, or how a scan is going, and the way to scan again.
/// Progress numbers are read here alone, so a running scan never redraws the page around it.
struct ScanControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if model.scanning {
                ProgressView().controlSize(.mini)
                Text("Scanning \(model.scanFiles.formatted()) files").monospacedDigit().foregroundStyle(.secondary)
                Button("Cancel") { model.cancelScan() }.buttonStyle(ActionButtonStyle(color: .secondary))
            } else {
                if let d = model.scanDate {
                    Text("Updated \(d.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
                }
                Menu {
                    Button("My Files") { model.startScan(NSHomeDirectory()) }
                    Button("Whole Mac") { model.startScan("/") }
                    Button("A Folder…") { pick() }
                } label: {
                    Text("Scan")
                } primaryAction: {
                    model.startScan()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
    }

    func pick() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.prompt = "Scan"
        if p.runModal() == .OK, let u = p.url { model.startScan(u.path) }
    }
}

struct EmptyScanPrompt: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 10) {
            if model.scanning {
                ProgressView().controlSize(.small)
                Text("Scanning \(model.scanFiles.formatted()) files · \(fmt(model.scanBytes))")
                    .font(.system(size: 12.5).monospacedDigit()).foregroundStyle(.secondary)
                Text("This only takes a while the first time.").font(.system(size: 12)).foregroundStyle(.tertiary)
            } else {
                Text("Nothing scanned yet").font(.system(size: 13, weight: .medium))
                Button("Scan My Files") { model.startScan(NSHomeDirectory()) }
                    .buttonStyle(ActionButtonStyle(color: Theme.accent, filled: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func reveal(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}

func openFullDiskAccess() {
    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
        NSWorkspace.shared.open(u)
    }
}

/// A scrolling room page.
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ScrollView { content } }
}
