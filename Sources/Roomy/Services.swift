import Foundation
import AppKit
import IOKit.ps

// MARK: - Quick clean categories

struct SizedItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let name: String
}

struct CleanCategory: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let resolve: () -> [URL]
    var name: (URL) -> String = { $0.lastPathComponent }
}

enum Cleaners {
    static let home = NSHomeDirectory()
    static let fm = FileManager.default

    static func contents(_ p: String) -> () -> [URL] {
        { (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: p), includingPropertiesForKeys: nil)) ?? [] }
    }

    static func single(_ p: String) -> () -> [URL] {
        { fm.fileExists(atPath: p) ? [URL(fileURLWithPath: p)] : [] }
    }

    static var all: [CleanCategory] {
        [
            CleanCategory(id: "caches", title: "App caches", detail: "Apps rebuild these when they need them", icon: "shippingbox",
                          resolve: contents(home + "/Library/Caches")),
            CleanCategory(id: "logs", title: "Logs", detail: "Old diagnostic logs from apps", icon: "doc.text",
                          resolve: contents(home + "/Library/Logs")),
            CleanCategory(id: "derived", title: "Xcode DerivedData", detail: "Build products, rebuilt on the next build", icon: "hammer",
                          resolve: contents(home + "/Library/Developer/Xcode/DerivedData")),
            CleanCategory(id: "archives", title: "Xcode Archives", detail: "Old app builds; keep the ones you may need to symbolicate", icon: "archivebox",
                          resolve: contents(home + "/Library/Developer/Xcode/Archives")),
            CleanCategory(id: "devicesupport", title: "iOS Device Support", detail: "Symbols for old iOS versions, fetched again when a device connects", icon: "iphone",
                          resolve: contents(home + "/Library/Developer/Xcode/iOS DeviceSupport")),
            CleanCategory(id: "simcaches", title: "Simulator caches", detail: "CoreSimulator caches", icon: "ipad.and.iphone",
                          resolve: contents(home + "/Library/Developer/CoreSimulator/Caches")),
            CleanCategory(id: "pkgcaches", title: "Package manager caches", detail: "npm, pnpm, bun, gradle and pip caches, downloaded again when needed", icon: "cube.box",
                          resolve: {
                              [home + "/.npm/_cacache", home + "/Library/pnpm/store", home + "/.bun/install/cache",
                               home + "/.gradle/caches", home + "/.cache/pip", home + "/.cargo/registry/cache"]
                                  .filter { fm.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
                          },
                          name: { $0.path.replacingOccurrences(of: home, with: "~") }),
            CleanCategory(id: "deps", title: "Project dependencies", detail: "node_modules, .next and .turbo folders; run npm install to get them back", icon: "folder.badge.gearshape",
                          resolve: findDeps,
                          name: { $0.deletingLastPathComponent().lastPathComponent + "/" + $0.lastPathComponent }),
            CleanCategory(id: "installers", title: "Installers in Downloads", detail: ".dmg, .pkg, .iso and .xip files you've probably already installed", icon: "opticaldiscdrive",
                          resolve: {
                              contents(home + "/Downloads")().filter { ["dmg", "pkg", "mpkg", "iso", "xip"].contains($0.pathExtension.lowercased()) }
                          }),
            CleanCategory(id: "olddownloads", title: "Old downloads", detail: "Things in Downloads added more than 90 days ago", icon: "clock.arrow.circlepath",
                          resolve: {
                              let cutoff = Date().addingTimeInterval(-90 * 86400)
                              return contents(home + "/Downloads")().filter {
                                  let v = try? $0.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
                                  let d = v?.addedToDirectoryDate ?? v?.contentModificationDate ?? Date()
                                  return d < cutoff && !$0.lastPathComponent.hasPrefix(".")
                              }
                          }),
        ]
    }

    static func findDeps() -> [URL] {
        let roots = ["Desktop", "Documents", "Developer", "Projects", "code", "dev", "src", "repos", "work", "Sites"]
            .map { home + "/" + $0 }.filter { fm.fileExists(atPath: $0) }
        let targets: Set<String> = ["node_modules", ".next", ".turbo"]
        var out: [URL] = []
        func walk(_ u: URL, _ depth: Int) {
            guard depth < 7 else { return }
            let items = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
            for i in items {
                let v = try? i.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard v?.isDirectory == true, v?.isSymbolicLink != true else { continue }
                let n = i.lastPathComponent
                if targets.contains(n) { out.append(i); continue }
                if n.hasPrefix(".") || n.hasSuffix(".app") || n == "Library" { continue }
                walk(i, depth + 1)
            }
        }
        roots.forEach { walk(URL(fileURLWithPath: $0), 0) }
        return out
    }
}

// MARK: - Applications

struct AppInfo: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let version: String
    let build: String
    let bundleID: String
    let feedURL: String?
    let isAppStore: Bool
    var size: Int64?
    var latest: String?
}

struct BrewItem: Identifiable, Hashable {
    var id: String { (isCask ? "cask:" : "formula:") + name }
    let name: String
    let installed: String
    let current: String
    let isCask: Bool
}

enum AppScanner {
    static let home = NSHomeDirectory()

    static func list() -> [AppInfo] {
        let fm = FileManager.default
        var urls: [URL] = []
        for dir in ["/Applications", home + "/Applications"] {
            for u in (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? [] {
                if u.pathExtension == "app" { urls.append(u) }
                else if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    urls += ((try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" }
                }
            }
        }
        return urls.compactMap { u in
            guard let b = Bundle(url: u), let info = b.infoDictionary else { return nil }
            let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? u.deletingPathExtension().lastPathComponent
            return AppInfo(path: u.path, name: u.deletingPathExtension().lastPathComponent.isEmpty ? name : u.deletingPathExtension().lastPathComponent,
                           version: info["CFBundleShortVersionString"] as? String ?? "",
                           build: info["CFBundleVersion"] as? String ?? "",
                           bundleID: b.bundleIdentifier ?? "",
                           feedURL: info["SUFeedURL"] as? String,
                           isAppStore: fm.fileExists(atPath: u.path + "/Contents/_MASReceipt/receipt"))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func leftovers(for app: AppInfo) -> [URL] {
        guard !app.bundleID.isEmpty else { return [] }
        let l = home + "/Library/"
        let id = app.bundleID
        let candidates = [
            l + "Application Support/" + id, l + "Application Support/" + app.name,
            l + "Caches/" + id, l + "Preferences/" + id + ".plist", l + "Containers/" + id,
            l + "Saved Application State/" + id + ".savedState", l + "Logs/" + app.name,
            l + "HTTPStorages/" + id, l + "WebKit/" + id, l + "Cookies/" + id + ".binarycookies",
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static func checkSparkle(_ app: AppInfo) async -> AppInfo? {
        guard let feed = app.feedURL, let url = URL(string: feed) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Roomy update check", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        let parser = AppcastParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        func newer(_ a: String, _ b: String) -> Bool { a.compare(b, options: .numeric) == .orderedDescending }
        // Prefer comparing short versions; fall back to build numbers
        if let best = parser.items.compactMap(\.short).max(by: { newer($1, $0) }), !app.version.isEmpty {
            if newer(best, app.version) { var a = app; a.latest = best; return a }
            return nil
        }
        if let best = parser.items.compactMap(\.build).max(by: { newer($1, $0) }), !app.build.isEmpty, newer(best, app.build) {
            var a = app; a.latest = best; return a
        }
        return nil
    }

    static func brewOutdated() -> [BrewItem] {
        guard let brew = Shell.brew else { return [] }
        Shell.run(brew, ["update", "--quiet"])
        let out = Shell.run(brew, ["outdated", "--greedy", "--json=v2"]).out
        guard let json = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any] else { return [] }
        func parse(_ key: String, cask: Bool) -> [BrewItem] {
            ((json[key] as? [[String: Any]]) ?? []).compactMap { d in
                guard let name = d["name"] as? String else { return nil }
                let inst = (d["installed_versions"] as? [String])?.joined(separator: ", ") ?? (d["installed_versions"] as? String) ?? "?"
                return BrewItem(name: name, installed: inst, current: d["current_version"] as? String ?? "?", isCask: cask)
            }
        }
        return parse("casks", cask: true) + parse("formulae", cask: false)
    }

    static func brewUpgrade(_ item: BrewItem) -> Bool {
        guard let brew = Shell.brew else { return false }
        return Shell.run(brew, ["upgrade", item.isCask ? "--cask" : "--formula", item.name]).status == 0
    }
}

final class AppcastParser: NSObject, XMLParserDelegate {
    struct Item { var short: String?; var build: String? }
    var items: [Item] = []
    private var cur: Item?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "item" { cur = Item() }
        if name == "enclosure" {
            if let s = attributes["sparkle:shortVersionString"] { cur?.short = s }
            if let v = attributes["sparkle:version"] { cur?.build = v }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "sparkle:shortVersionString", !t.isEmpty { cur?.short = t }
        if name == "sparkle:version", !t.isEmpty { cur?.build = t }
        if name == "item", let c = cur { items.append(c); cur = nil }
    }
}

// MARK: - Startup items

struct StartupItem: Identifiable, Hashable {
    enum Kind: String { case loginItem = "Opens at login", userAgent = "Your background agents", globalAgent = "Background agents (all users)", daemon = "System daemons" }
    var id: String { kind.rawValue + label }
    let kind: Kind
    let label: String
    let name: String
    let detail: String
    let plist: String?
    var enabled: Bool
}

enum Startup {
    static var uid: uid_t { getuid() }

    static func disabledSet(_ domain: String) -> [String: Bool] {
        let out = Shell.run("/bin/launchctl", ["print-disabled", domain]).out
        var d: [String: Bool] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let v = parts[1].trimmingCharacters(in: .whitespaces)
            d[label] = (v == "disabled" || v == "true")
        }
        return d
    }

    static func load() -> [StartupItem] {
        var items: [StartupItem] = []
        let names = Shell.osascript("tell application \"System Events\" to get the name of every login item").out
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !names.isEmpty {
            for n in names.components(separatedBy: ", ") {
                items.append(StartupItem(kind: .loginItem, label: n, name: n, detail: "Login item", plist: nil, enabled: true))
            }
        }
        let gui = disabledSet("gui/\(uid)")
        let sys = disabledSet("system")
        let dirs: [(String, StartupItem.Kind)] = [
            (NSHomeDirectory() + "/Library/LaunchAgents", .userAgent),
            ("/Library/LaunchAgents", .globalAgent),
            ("/Library/LaunchDaemons", .daemon),
        ]
        for (dir, kind) in dirs {
            for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where f.hasSuffix(".plist") {
                let path = dir + "/" + f
                guard let d = NSDictionary(contentsOfFile: path) as? [String: Any] else { continue }
                let label = d["Label"] as? String ?? String(f.dropLast(6))
                let program = (d["Program"] as? String) ?? ((d["ProgramArguments"] as? [String])?.first) ?? ""
                var name = label
                if let r = program.range(of: ".app/") {
                    name = URL(fileURLWithPath: String(program[..<r.lowerBound]) + ".app").deletingPathExtension().lastPathComponent
                }
                let plistDisabled = d["Disabled"] as? Bool ?? false
                let override = (kind == .daemon ? sys : gui)[label]
                items.append(StartupItem(kind: kind, label: label, name: name, detail: program.isEmpty ? label : program,
                                         plist: path, enabled: !(override ?? plistDisabled)))
            }
        }
        return items
    }

    static func setEnabled(_ item: StartupItem, _ on: Bool) -> Bool {
        switch item.kind {
        case .loginItem:
            guard !on else { return false }
            let safe = item.name.replacingOccurrences(of: "\"", with: "\\\"")
            return Shell.osascript("tell application \"System Events\" to delete login item \"\(safe)\"").status == 0
        case .userAgent, .globalAgent:
            let domain = "gui/\(uid)"
            if on {
                Shell.run("/bin/launchctl", ["enable", "\(domain)/\(item.label)"])
                if let p = item.plist { Shell.run("/bin/launchctl", ["bootstrap", domain, p]) }
            } else {
                Shell.run("/bin/launchctl", ["disable", "\(domain)/\(item.label)"])
                Shell.run("/bin/launchctl", ["bootout", "\(domain)/\(item.label)"])
            }
            return true
        case .daemon:
            let label = item.label.replacingOccurrences(of: "'", with: "")
            let plist = (item.plist ?? "").replacingOccurrences(of: "'", with: "")
            let cmd = on
                ? "launchctl enable system/\(label); launchctl bootstrap system '\(plist)'"
                : "launchctl disable system/\(label); launchctl bootout system/\(label)"
            return Shell.osascript("do shell script \"\(cmd); true\" with administrator privileges").status == 0
        }
    }
}

// MARK: - System monitor

struct ProcRow: Identifiable, Hashable { let pid: Int; let name: String; let cpu: Double; let memKB: Int64; var id: Int { pid } }
struct PortRow: Identifiable, Hashable { let command: String; let pid: Int; let address: String; var id: String { "\(pid)-\(address)" } }
struct BatteryInfo: Equatable { var level: Int; var charging: Bool; var onAC: Bool }

@Observable
final class SystemMonitor {
    var cpu: Double = 0
    var memUsed: UInt64 = 0
    let memTotal = ProcessInfo.processInfo.physicalMemory
    var battery: BatteryInfo?
    var rxRate: Double = 0
    var txRate: Double = 0
    var processes: [ProcRow] = []
    var ports: [PortRow] = []

    private var prevTicks: [UInt32]?
    private var prevNet: (rx: UInt64, tx: UInt64, at: Date)?
    private var timer: Timer?
    private var tick = 0

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func sample() {
        cpu = readCPU()
        memUsed = readMemory()
        battery = readBattery()
        readNetwork()
        let withPorts = tick % 3 == 0
        tick += 1
        DispatchQueue.global(qos: .utility).async {
            let procs = Self.readProcesses()
            let ports = withPorts ? Self.readPorts() : nil
            DispatchQueue.main.async {
                self.processes = procs
                if let ports { self.ports = ports }
            }
        }
    }

    private func readCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return cpu }
        let t = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3] // user, system, idle, nice
        defer { prevTicks = t }
        guard let p = prevTicks else { return 0 }
        let d = zip(t, p).map { Double($0 &- $1) }
        let total = d.reduce(0, +)
        return total > 0 ? (d[0] + d[1] + d[3]) / total : 0
    }

    private func readMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return memUsed }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private func readBattery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return BatteryInfo(level: cur * 100 / max,
                               charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                               onAC: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue)
        }
        return nil
    }

    private func readNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var p = ifaddr
        while let a = p {
            let name = String(cString: a.pointee.ifa_name)
            if let addr = a.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"), let data = a.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(d.ifi_ibytes)
                tx += UInt64(d.ifi_obytes)
            }
            p = a.pointee.ifa_next
        }
        freeifaddrs(ifaddr)
        let now = Date()
        if let prev = prevNet {
            let dt = now.timeIntervalSince(prev.at)
            if dt > 0 {
                rxRate = rx >= prev.rx ? Double(rx - prev.rx) / dt : 0
                txRate = tx >= prev.tx ? Double(tx - prev.tx) / dt : 0
            }
        }
        prevNet = (rx, tx, now)
    }

    static func readProcesses() -> [ProcRow] {
        let out = Shell.run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm=", "-r"]).out
        return out.split(separator: "\n").prefix(6).compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int(parts[0]), let cpu = Double(parts[1]), let rss = Int64(parts[2]) else { return nil }
            return ProcRow(pid: pid, name: String(parts[3]), cpu: cpu, memKB: rss)
        }
    }

    static func readPorts() -> [PortRow] {
        let out = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"]).out
        var seen = Set<String>()
        return out.split(separator: "\n").dropFirst().compactMap { line in
            let c = line.split(separator: " ", omittingEmptySubsequences: true)
            guard c.count >= 9, let pid = Int(c[1]) else { return nil }
            let addr = String(c[8])
            let port = addr.split(separator: ":").last.map(String.init) ?? addr
            let key = "\(c[0])-\(port)"
            guard seen.insert(key).inserted else { return nil }
            return PortRow(command: String(c[0]).replacingOccurrences(of: "\\x20", with: " "), pid: pid, address: addr)
        }
        .sorted { (Int($0.address.split(separator: ":").last ?? "") ?? 0) < (Int($1.address.split(separator: ":").last ?? "") ?? 0) }
    }
}
