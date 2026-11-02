import SwiftUI

/// A folder drawn as an architect's floor plan: every child is a room sized by the space it takes,
/// separated by ink walls, with a door swing in the bigger rooms. Click a room to walk into it.
struct FloorPlan: View {
    @Environment(AppModel.self) private var model
    let node: FileNode
    var maxRooms = 12
    let enter: (FileNode) -> Void
    @State private var hover: String?

    struct Room: Identifiable {
        let id: String
        let name: String
        let size: Int64
        let node: FileNode?
        var rect: CGRect = .zero
    }

    func rooms(in size: CGSize) -> [Room] {
        let kids = node.children.filter { $0.size > 0 }
        var list = kids.prefix(maxRooms).map { Room(id: $0.path, name: $0.name, size: $0.size, node: $0) }
        let rest = kids.dropFirst(maxRooms).reduce(Int64(0)) { $0 + $1.size }
        if rest > 0 { list.append(Room(id: "rest", name: "Everything else", size: rest, node: nil)) }
        let rects = Treemap.layout(list.map { Double($0.size) }, in: CGRect(origin: .zero, size: size))
        for i in list.indices where i < rects.count { list[i].rect = rects[i] }
        return list
    }

    var body: some View {
        let _ = model.treeVersion
        let _ = model.queue.count
        GeometryReader { g in
            let plan = rooms(in: g.size)
            ZStack(alignment: .topLeading) {
                ForEach(plan) { room in
                    roomView(room)
                        .frame(width: room.rect.width, height: room.rect.height)
                        .offset(x: room.rect.minX, y: room.rect.minY)
                }
                Canvas { ctx, size in drawWalls(ctx, size: size, plan: plan) }
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    func roomView(_ room: Room) -> some View {
        let queued = room.node.map { model.isQueued($0.path) || model.isCovered($0.path) } ?? false
        let advice = room.node.flatMap { Advisor.explain($0.path, name: $0.name) }
        let big = room.rect.width > 150 && room.rect.height > 90
        let fill: Color = queued ? Theme.good.opacity(0.16)
            : hover == room.id ? Theme.accentSoft
            : room.node == nil ? Theme.card : Theme.canvas
        ZStack(alignment: .topLeading) {
            Rectangle().fill(fill)
            if queued { Hatch().stroke(Theme.good.opacity(0.35), lineWidth: 1) }
            if room.rect.width > 64 && room.rect.height > 38 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .font(.system(size: big ? 12.5 : 11, weight: .semibold))
                        .lineLimit(1)
                    let s = sizeParts(room.size)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(s.0).font(.system(size: big ? 22 : 14, design: .serif)).monospacedDigit()
                        Text(s.1).font(.system(size: big ? 11 : 9.5, weight: .medium)).foregroundStyle(.secondary)
                    }
                    if big, let advice, advice.verdict == .safe || advice.verdict == .rebuilds {
                        Text(advice.verdict.label)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(advice.verdict.color)
                            .padding(.top, 2)
                    }
                    if queued && room.rect.height > 70 {
                        Text("On your clean list").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.good)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onHover { hover = $0 ? room.id : (hover == room.id ? nil : hover) }
        .onTapGesture { if let n = room.node, n.isDir { enter(n) } }
        .help("\(room.name) · \(fmt(room.size))" + (advice.map { " · " + $0.text } ?? ""))
        .contextMenu {
            if let n = room.node, !n.isAggregate {
                Button(queued ? "Remove from Clean List" : "Add to Clean List") {
                    model.toggle(path: n.path, name: n.name, size: n.size, source: "Floor plan")
                }
                Button("Reveal in Finder") { reveal(n.path) }
            }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    /// Walls are drawn once over the rooms so shared edges read as one line, then doors are cut into them.
    func drawWalls(_ ctx: GraphicsContext, size: CGSize, plan: [Room]) {
        let ink = GraphicsContext.Shading.color(Color.primary.opacity(0.72))
        // Inner walls: what's inside each big room, drawn faintly below its label.
        let faint = GraphicsContext.Shading.color(Color.primary.opacity(0.13))
        for room in plan where room.rect.width > 120 && room.rect.height > 110 {
            guard let kids = room.node?.children.filter({ $0.size > 0 }).prefix(10), kids.count > 1 else { continue }
            let area = CGRect(x: room.rect.minX + 10, y: room.rect.minY + 62,
                              width: room.rect.width - 20, height: room.rect.height - 72)
            guard area.width > 40, area.height > 30 else { continue }
            for r in Treemap.layout(kids.map { Double($0.size) }, in: area) {
                ctx.stroke(Path(r), with: faint, lineWidth: 0.75)
            }
        }
        for room in plan {
            ctx.stroke(Path(room.rect), with: ink, lineWidth: 1.5)
        }
        ctx.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: 1.25, dy: 1.25)), with: ink, lineWidth: 2.5)

        // A door in each room that has space for one: a gap in the bottom wall and its swing.
        let paper = GraphicsContext.Shading.color(Theme.canvas)
        let thin = GraphicsContext.Shading.color(Color.primary.opacity(0.35))
        for room in plan where room.rect.width > 110 && room.rect.height > 80 && room.rect.maxY < size.height - 2 {
            let w = min(22, room.rect.width * 0.18)
            let x = room.rect.maxX - w - 14
            let y = room.rect.maxY
            ctx.fill(Path(CGRect(x: x, y: y - 1.5, width: w, height: 3)), with: paper)
            var swing = Path()
            swing.move(to: CGPoint(x: x, y: y))
            swing.addLine(to: CGPoint(x: x, y: y - w))
            swing.addArc(center: CGPoint(x: x, y: y), radius: w, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            ctx.stroke(swing, with: thin, lineWidth: 1)
        }
    }
}

/// Diagonal lines, the plan's way of saying "marked for removal".
struct Hatch: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = -r.height
        while x < r.width {
            p.move(to: CGPoint(x: r.minX + x, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + x + r.height, y: r.minY))
            x += 9
        }
        return p
    }
}
