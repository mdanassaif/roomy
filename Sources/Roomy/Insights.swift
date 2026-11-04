import Foundation

// MARK: - Space forecast

/// Free space, written down every few hours, so Roomy can say where the disk is heading.
struct SpaceSample: Codable {
    let date: Date
    let free: Int64
}

enum SpaceLog {
    private static let key = "spaceLog"
    private static var cached: [SpaceSample]?

    static func load() -> [SpaceSample] {
        if let cached { return cached }
        let log = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([SpaceSample].self, from: $0) } ?? []
        cached = log
        return log
    }

    /// Adds a sample if the last one is over three hours old. Keeps about two months.
    static func record(free: Int64, now: Date = Date()) {
        guard free > 0 else { return }
        var log = load()
        if let last = log.last, now.timeIntervalSince(last.date) < 3 * 3600 { return }
        log.append(SpaceSample(date: now, free: free))
        if log.count > 500 { log.removeFirst(log.count - 500) }
        cached = log
        if let data = try? JSONEncoder().encode(log) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct Forecast: Equatable {
    let text: String
    var urgent = false
    var ready = true

    /// A straight line through the last three weeks of free space.
    static func make(log: [SpaceSample], free: Int64, now: Date = Date()) -> Forecast {
        let recent = log.filter { now.timeIntervalSince($0.date) < 21 * 86400 } + [SpaceSample(date: now, free: free)]
        guard let first = recent.first, now.timeIntervalSince(first.date) >= 2 * 86400, recent.count >= 3 else {
            return Forecast(text: "Forecast after a couple of days", ready: false)
        }
        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 86400 }
        let ys = recent.map { Double($0.free) }
        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return Forecast(text: "Holding steady") }
        let perDay = num / den
        // Losing less than 150 MB a day is noise from caches coming and going.
        guard perDay < -150_000_000 else { return Forecast(text: "Holding steady") }
        let days = Double(free) / -perDay
        switch days {
        case ..<2: return Forecast(text: "Full within a day or two", urgent: true)
        case ..<14: return Forecast(text: "Full in about \(Int(days.rounded())) days", urgent: true)
        case ..<60: return Forecast(text: "Full in about \(Int((days / 7).rounded())) weeks")
        case ..<365: return Forecast(text: "Full in about \(Int((days / 30).rounded())) months")
        default: return Forecast(text: "Holding steady")
        }
    }
}

// MARK: - What grew lately

struct Growth: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let delta: Int64
}

extension SnapshotStore {
    /// Compares the newest scan of `root` with one from about a week before (at least a day older),
    /// and returns the few places that grew most, pointing at the folder that actually grew
    /// rather than its parents.
    static func grewLately(in items: [Snapshot], root: String) -> (since: Date, rows: [Growth])? {
        let same = items.filter { $0.root == root }.sorted { $0.date > $1.date }
        guard let new = same.first else { return nil }
        let target = new.date.addingTimeInterval(-7 * 86400)
        let older = same.filter { $0.date <= new.date.addingTimeInterval(-86400) }
        guard let old = older.min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }) else { return nil }

        let grew = SnapshotStore.diff(old, new, maxDepth: 8).filter { $0.delta >= 50_000_000 && $0.kind != .shrank }
        var picks: [DiffRow] = []
        for row in grew {
            var best = row
            while let deeper = grew.filter({ $0.path.hasPrefix(best.path + "/") && Double($0.delta) >= Double(best.delta) * 0.75 })
                .max(by: { $0.delta < $1.delta }) {
                best = deeper
            }
            let overlaps = picks.contains { best.path.hasPrefix($0.path + "/") || $0.path.hasPrefix(best.path + "/") || $0.path == best.path }
            if !overlaps { picks.append(best) }
            if picks.count == 3 { break }
        }
        let rows = picks.map { Growth(path: $0.path, name: ($0.path as NSString).lastPathComponent, delta: $0.delta) }
        return (old.date, rows)
    }
}
