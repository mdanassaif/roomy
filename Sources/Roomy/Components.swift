import SwiftUI
import AppKit

struct DiskBar: View {
    let total: Int64
    let used: Int64
    var staged: Int64 = 0
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { g in
            let t = Double(max(total, 1))
            let uw = g.size.width * Double(used) / t
            let sw = g.size.width * Double(min(staged, used)) / t
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.secondary.opacity(0.18))
                Rectangle()
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, uw))
                Rectangle()
                    .fill(Color.green)
                    .frame(width: max(0, sw))
                    .offset(x: max(0, uw - sw))
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .animation(.snappy, value: staged)
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
        let protected = Safety.isProtected(path)
        Button {
            model.toggle(path: path, name: name, size: size, source: source)
        } label: {
            Image(systemName: queued || covered ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 15))
                .foregroundStyle(queued || covered ? Color.green : protected ? Color.secondary.opacity(0.3) : Color.secondary)
        }
        .buttonStyle(.borderless)
        .disabled(covered || protected)
        .help(protected ? "Protected" : queued ? "Remove from cleanup queue" : covered ? "Its folder is already queued" : "Add to cleanup queue")
    }
}

struct FileIcon: View {
    let path: String
    var aggregate = false
    var size: CGFloat = 18

    var body: some View {
        if aggregate {
            Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary).frame(width: size, height: size)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: size, height: size)
        }
    }
}

struct SizeBar: View {
    let fraction: Double
    var color: Color = .purple

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12))
                Capsule().fill(color.gradient).frame(width: g.size.width * min(1, max(0.01, fraction)))
            }
        }
        .frame(width: 90, height: 6)
    }
}

struct RoomHeader<Trailing: View>: View {
    let room: Room
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: room.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(room.color.gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(room.title).font(.title2.bold())
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

struct EmptyScanPrompt: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ContentUnavailableView {
            Label("No scan yet", systemImage: "internaldrive")
        } description: {
            Text("Scan your home folder or the whole disk to see where the space went.")
        } actions: {
            if model.scanning {
                ProgressView("Scanning… \(model.scanFiles.formatted()) files, \(fmt(model.scanBytes))")
            } else {
                HStack {
                    Button("Scan Home Folder") { model.startScan(NSHomeDirectory()) }.buttonStyle(.borderedProminent)
                    Button("Scan Entire Disk") { model.startScan("/") }
                }
            }
        }
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

extension Color {
    static func treemap(_ i: Int) -> Color {
        let palette: [Color] = [.purple, .blue, .teal, .green, .orange, .pink, .indigo, .mint, .cyan, .red, .yellow, .brown]
        return palette[i % palette.count]
    }
}

// MARK: - Treemap

enum Treemap {
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var rects = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return rects }
        let areas = values.map { $0 / total * Double(rect.width * rect.height) }
        var remaining = rect
        var i = 0

        func worst(_ row: [Double], _ side: Double) -> Double {
            let s = row.reduce(0, +)
            guard let mx = row.max(), let mn = row.min(), s > 0, mn > 0 else { return .infinity }
            return max(side * side * mx / (s * s), (s * s) / (side * side * mn))
        }

        while i < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var row = [areas[i]]
            var j = i + 1
            while j < areas.count {
                let next = row + [areas[j]]
                if worst(next, side) <= worst(row, side) { row = next; j += 1 } else { break }
            }
            let sum = row.reduce(0, +)
            if remaining.width >= remaining.height {
                let w = CGFloat(sum) / remaining.height
                var y = remaining.minY
                for (k, a) in row.enumerated() {
                    let h = CGFloat(a) / w
                    rects[i + k] = CGRect(x: remaining.minX, y: y, width: w, height: h)
                    y += h
                }
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY, width: remaining.width - w, height: remaining.height)
            } else {
                let h = CGFloat(sum) / remaining.width
                var x = remaining.minX
                for (k, a) in row.enumerated() {
                    let w = CGFloat(a) / h
                    rects[i + k] = CGRect(x: x, y: remaining.minY, width: w, height: h)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h, width: remaining.width, height: remaining.height - h)
            }
            i = j
        }
        return rects
    }
}

struct TreemapView: View {
    @Environment(AppModel.self) private var model
    let node: FileNode

    var body: some View {
        let _ = model.treeVersion
        let kids = Array(node.children.filter { $0.size > 0 }.prefix(60))
        GeometryReader { g in
            let rects = Treemap.layout(kids.map { Double($0.size) }, in: CGRect(origin: .zero, size: g.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(kids.enumerated()), id: \.element.id) { i, child in
                    let r = rects[i].insetBy(dx: 1.5, dy: 1.5)
                    if r.width > 2 && r.height > 2 {
                        let queued = model.isQueued(child.path) || model.isCovered(child.path)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(child.isAggregate ? Color.gray.opacity(0.35) : Color.treemap(i).opacity(child.isDir ? 0.85 : 0.55))
                            .overlay {
                                if queued {
                                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.green, lineWidth: 3)
                                }
                            }
                            .overlay(alignment: .topLeading) {
                                if r.width > 60 && r.height > 30 {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(child.name).font(.caption.bold()).lineLimit(1)
                                        Text(fmt(child.size)).font(.caption2).opacity(0.85)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(6)
                                }
                            }
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX, y: r.minY)
                            .onTapGesture { if child.isDir { model.current = child } }
                            .help("\(child.name) — \(fmt(child.size))")
                            .contextMenu {
                                if !child.isAggregate {
                                    Button(queued ? "Remove from Queue" : "Add to Cleanup Queue") {
                                        model.toggle(path: child.path, name: child.name, size: child.size, source: "Storage")
                                    }
                                    Button("Reveal in Finder") { reveal(child.path) }
                                }
                            }
                    }
                }
            }
        }
    }
}
