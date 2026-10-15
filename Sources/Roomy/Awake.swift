import Foundation
import AppKit
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

/// Keep Awake (formerly Simmer): keeps the Mac running, lid closed included.
///
/// Two locks do the work:
/// - a power assertion stops idle sleep. macOS drops it on its own if Roomy quits or crashes.
/// - `pmset -a disablesleep 1` stops lid sleep. That needs root, so a one-time setup installs a
///   sudoers rule for exactly those two pmset commands. Without it, Keep Awake still works with the lid open.
///
/// While it's on, a check every minute turns it off on low battery, or when the Mac runs hot with the lid closed.
@Observable
final class KeepAwake {
    private(set) var isOn = false
    private(set) var until: Date?
    /// True while lid sleep is disabled by us.
    private(set) var lidClosedActive = false
    private(set) var lidSetupDone = KeepAwake.sudoersInstalled()
    private(set) var lastStop: String?
    var lastError: String?

    private var assertions: [IOPMAssertionID] = []
    private var timer: Timer?
    private var hotStrikes = 0

    private static let prevKey = "awake.prevSleepDisabled"
    static let batteryMinOpen = 10, batteryMinClosed = 20, tempMax = 40.0

    init() {
        // A crash or force quit can leave lid sleep disabled. Put it back.
        if UserDefaults.standard.object(forKey: Self.prevKey) != nil { restoreLidSleep() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.turnOff()
        }
    }

    // MARK: On / off

    /// Turns on until turned off, or for `duration` seconds.
    func turnOn(for duration: TimeInterval? = nil) {
        lastError = nil
        let power = PowerState.read()
        if let why = power.tooLow { lastError = "Not turning on: \(why)"; return }

        if assertions.isEmpty {
            for type in [kIOPMAssertPreventUserIdleSystemSleep, kIOPMAssertionTypePreventSystemSleep] {
                var id: IOPMAssertionID = 0
                if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Roomy Keep Awake" as CFString, &id) == kIOReturnSuccess {
                    assertions.append(id)
                }
            }
        }
        guard !assertions.isEmpty else { lastError = "macOS refused the sleep lock."; return }

        if lidSetupDone && !lidClosedActive { disableLidSleep() }
        isOn = true
        until = duration.map { Date().addingTimeInterval($0) }
        hotStrikes = 0
        startChecks()
    }

    func turnOff(reason: String? = nil) {
        guard isOn else { return }
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions = []
        if lidClosedActive { restoreLidSleep() }
        isOn = false
        until = nil
        timer?.invalidate()
        timer = nil
        if let reason {
            lastStop = reason
            notify("Keep Awake turned off: \(reason).")
        }
    }

    func toggle() { isOn ? turnOff() : turnOn() }

    // MARK: Safety checks

    private func startChecks() {
        timer?.invalidate()
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private var lastSafetyCheck = Date.distantPast

    private func check() {
        guard isOn else { return }
        if let until, Date() >= until { turnOff(reason: "the timer finished"); return }
        guard Date().timeIntervalSince(lastSafetyCheck) >= 60 else { return }
        lastSafetyCheck = Date()
        let power = PowerState.read()
        if let why = power.tooLow { turnOff(reason: why); return }
        if let why = power.tooHot {
            hotStrikes += 1
            if hotStrikes >= 2 { turnOff(reason: why) }
        } else {
            hotStrikes = 0
        }
    }

    // MARK: Lid sleep (pmset)

    private func disableLidSleep() {
        let prev = Self.sleepDisabled()
        UserDefaults.standard.set(prev, forKey: Self.prevKey)
        if prev || Self.setSleepDisabled(true) {
            lidClosedActive = true
        } else {
            UserDefaults.standard.removeObject(forKey: Self.prevKey)
            lidSetupDone = Self.sudoersInstalled()
            lastError = "Couldn't keep it awake with the lid closed. Run the one-time setup again."
        }
    }

    private func restoreLidSleep() {
        let prev = UserDefaults.standard.bool(forKey: Self.prevKey)
        if Self.sleepDisabled() == prev || Self.setSleepDisabled(prev) {
            UserDefaults.standard.removeObject(forKey: Self.prevKey)
        } else {
            lastError = "Couldn't turn lid sleep back on. In Terminal: sudo pmset -a disablesleep 0"
        }
        lidClosedActive = false
    }

    static func sleepDisabled() -> Bool {
        let out = Shell.run("/usr/bin/pmset", ["-g"]).out
        return out.split(separator: "\n").contains { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            return parts.count >= 2 && parts[0] == "SleepDisabled" && parts[1] == "1"
        }
    }

    private static func setSleepDisabled(_ on: Bool) -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]).status == 0
    }

    // MARK: One-time setup

    static func sudoersInstalled() -> Bool {
        let out = Shell.run("/usr/bin/sudo", ["-n", "-l"]).out
        return out.contains("/usr/bin/pmset -a disablesleep 0") && out.contains("/usr/bin/pmset -a disablesleep 1")
    }

    /// Asks for the admin password once and installs a rule that allows only
    /// `pmset -a disablesleep 0|1` without a password.
    func setUpLidClosed() {
        lastError = nil
        let user = NSUserName()
        guard user.allSatisfy({ $0.isLetter || $0.isNumber || "._-".contains($0) }) else {
            lastError = "Your username has characters Roomy can't put in the rule safely."
            return
        }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("roomy-awake-\(UUID().uuidString)")
        do { try (rule + "\n").write(to: tmp, atomically: true, encoding: .utf8) } catch {
            lastError = "Couldn't write the rule file."
            return
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        let cmd = "/usr/sbin/visudo -cf '\(tmp.path)' && /usr/bin/install -m 0440 -o root -g wheel '\(tmp.path)' /etc/sudoers.d/roomy-awake"
        let script = "do shell script \"\(cmd)\" with administrator privileges with prompt \"Roomy wants to keep your Mac awake with the lid closed.\""
        let r = Shell.osascript(script)
        lidSetupDone = Self.sudoersInstalled()
        if lidSetupDone {
            if isOn && !lidClosedActive { disableLidSleep() }
        } else if r.status != 0 {
            lastError = nil // Cancelled at the password prompt.
        } else {
            lastError = "Setup didn't finish. Try again."
        }
    }

    private func notify(_ text: String) {
        let safe = text.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "'")
        DispatchQueue.global(qos: .utility).async {
            Shell.osascript("display notification \"\(safe)\" with title \"Roomy\"")
        }
    }
}

/// Battery, lid and heat, read the same way Simmer's watcher did.
struct PowerState {
    var onBattery = false
    var percent: Int?
    var lidClosed = false
    var batteryTemp: Double?
    var thermal = ProcessInfo.processInfo.thermalState

    static func read() -> PowerState {
        var s = PowerState()
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                      let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
                s.percent = cur * 100 / max
                s.onBattery = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            }
        }
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        if root != 0 {
            s.lidClosed = (IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Bool) ?? false
            IOObjectRelease(root)
        }
        let battery = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if battery != 0 {
            if let t = IORegistryEntryCreateCFProperty(battery, "Temperature" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int {
                s.batteryTemp = Double(t) / 100
            }
            IOObjectRelease(battery)
        }
        return s
    }

    var tooLow: String? {
        guard onBattery, let percent else { return nil }
        let limit = lidClosed ? KeepAwake.batteryMinClosed : KeepAwake.batteryMinOpen
        guard percent <= limit else { return nil }
        return "battery at \(percent)%" + (lidClosed ? " with the lid closed" : "")
    }

    var tooHot: String? {
        guard lidClosed else { return nil }
        if let t = batteryTemp, t >= KeepAwake.tempMax { return "the Mac got hot with the lid closed (\(Int(t))°C)" }
        if thermal == .serious || thermal == .critical { return "the Mac got hot with the lid closed" }
        return nil
    }
}
