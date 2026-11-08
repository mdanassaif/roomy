import SwiftUI

/// Timer choices, shared by the Keep Awake room and the menu bar.
let awakeDurations: [(title: String, seconds: TimeInterval?)] = [
    ("30 min", 1800), ("1 hour", 3600), ("2 hours", 7200), ("4 hours", 14400), ("8 hours", 28800), ("Until I stop it", nil),
]

extension KeepAwake {
    var statusLine: String {
        guard isOn else { return "Off. Your Mac sleeps as usual." }
        if let until {
            return "On until \(until.formatted(date: .omitted, time: .shortened))"
        }
        return "On until you turn it off"
    }

    var lidLine: String {
        if lidClosedActive { return "Works with the lid closed" }
        return lidSetupDone ? "Lid closed: ready" : "Lid open only. Set up lid-closed mode once to close the lid too."
    }
}

// MARK: - Room

struct AwakeRoom: View {
    @Environment(KeepAwake.self) private var awake
    @State private var power = PowerState.read()
    @State private var choice: TimeInterval? = 3600

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 0) {
                RoomHeader(room: .awake, subtitle: "Keep your Mac running for downloads, builds and remote sessions") { EmptyView() }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    VStack(alignment: .leading, spacing: 18) {
                        tiles(now: ctx.date)
                        if let error = awake.lastError {
                            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn).font(.system(size: 12.5))
                                .padding(.horizontal, 10)
                        }
                        control(now: ctx.date)
                        lid
                        rules
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .padding(.bottom, 90)
            }
        }
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in power = PowerState.read() }
        .onAppear { power = PowerState.read() }
    }

    // MARK: Tiles

    func tiles(now: Date) -> some View {
        let left = awake.until.map { max(0, $0.timeIntervalSince(now)) }
        return HStack(spacing: 12) {
            InfoTile(icon: awake.isOn ? "cup.and.heat.waves" : "moon.zzz", label: "Status",
                     value: awake.isOn ? "Awake" : "Off",
                     caption: awake.isOn ? (awake.until == nil ? "Until you turn it off" : "Until \(awake.until!.formatted(date: .omitted, time: .shortened))") : "Sleeps as usual",
                     tint: awake.isOn ? Theme.good : .secondary)
            InfoTile(icon: "timer", label: "Time left",
                     value: left.map(clock) ?? (awake.isOn ? "No limit" : "—"),
                     caption: awake.isOn ? (left == nil ? "Runs until stopped" : "Then sleep goes back to normal") : "Pick a time below",
                     tint: .primary)
            InfoTile(icon: power.onBattery ? "battery.75percent" : "powerplug", label: "Power",
                     value: power.percent.map { "\($0)%" } ?? "Plugged in",
                     caption: power.onBattery ? "On battery" : "Charging or plugged in",
                     tint: power.tooLow != nil ? Theme.warn : .primary)
            InfoTile(icon: "laptopcomputer", label: "Lid closed",
                     value: awake.lidSetupDone ? "Ready" : "Not set up",
                     caption: awake.lidSetupDone ? "You can close the lid" : "Keep the lid open for now",
                     tint: awake.lidSetupDone ? Theme.good : Theme.warm)
        }
    }

    func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up)), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: Control

    func control(now: Date) -> some View {
        Panel(title: awake.isOn ? "Staying awake" : "Keep awake for", icon: "power") {
            if awake.isOn {
                Button("Turn Off") { awake.turnOff() }.buttonStyle(ActionButtonStyle())
            } else {
                Button("Start") { awake.turnOn(for: choice) }.buttonStyle(ActionButtonStyle(color: Theme.accent, filled: true))
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if awake.isOn, let until = awake.until, let start = awake.startedAt {
                    let total = max(until.timeIntervalSince(start), 1)
                    let done = min(max(now.timeIntervalSince(start) / total, 0), 1)
                    VStack(alignment: .leading, spacing: 6) {
                        StackBar(parts: [(1 - done, Theme.good)], height: 6, gap: 0)
                        HStack {
                            Text("Started \(start.formatted(date: .omitted, time: .shortened))")
                            Spacer()
                            Text("Ends \(until.formatted(date: .omitted, time: .shortened))")
                        }
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(awakeDurations, id: \.title) { d in
                        let picked = awake.isOn ? false : choice == d.seconds
                        Button(d.title) {
                            if awake.isOn { awake.turnOn(for: d.seconds) } else { choice = d.seconds }
                        }
                        .buttonStyle(ActionButtonStyle(color: picked ? Theme.accent : .secondary))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(picked ? Theme.accent.opacity(0.6) : .clear))
                    }
                    Spacer(minLength: 0)
                }
                Text(awake.isOn ? "Pick a time to restart the timer from now." : "Your Mac stays on for this long, then sleeps as usual.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    // MARK: Lid

    var lid: some View {
        Panel(title: "Lid-closed mode", icon: "laptopcomputer") {
            if awake.lidSetupDone {
                Label("Ready", systemImage: "checkmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.good)
            } else {
                Button("Set Up…") { awake.setUpLidClosed() }.buttonStyle(ActionButtonStyle())
            }
        } content: {
            Text(awake.lidSetupDone
                 ? "Close the lid and your Mac keeps going, Wi-Fi included. Sleep goes back to normal when Keep Awake turns off."
                 : "Asks for your password once. Roomy then allows only the two sleep commands it uses, nothing else.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.bottom, 6)
        }
    }

    // MARK: Safety

    var rules: some View {
        let battLimit = power.lidClosed ? KeepAwake.batteryMinClosed : KeepAwake.batteryMinOpen
        return Panel(title: "It turns itself off", icon: "shield") {
            if let last = awake.lastStop { Text("Last time: \(last)").font(.system(size: 12)).foregroundStyle(.secondary) }
        } content: {
            VStack(spacing: 0) {
                rule("timer", "When your timer runs out",
                     awake.until.map { "at \($0.formatted(date: .omitted, time: .shortened))" } ?? (awake.isOn ? "no timer" : "—"))
                rule("battery.25percent", "On battery at \(KeepAwake.batteryMinOpen)%, or \(KeepAwake.batteryMinClosed)% with the lid closed",
                     power.onBattery ? (power.percent.map { "now \($0)%, stops at \(battLimit)%" } ?? "") : "plugged in",
                     warn: power.tooLow != nil)
                rule("thermometer.medium", "If it runs hot with the lid closed",
                     power.batteryTemp.map { "now \(Int($0))°C, stops at \(Int(KeepAwake.tempMax))°C" } ?? "",
                     warn: power.tooHot != nil)
                rule("xmark.app", "When you quit Roomy", "")
            }
        }
    }

    func rule(_ icon: String, _ text: String, _ now: String, warn: Bool = false) -> some View {
        HoverRow(height: 34) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 20)
            Text(text).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 12)
            Text(now).font(.system(size: 12).monospacedDigit()).foregroundStyle(warn ? Theme.warn : .secondary).lineLimit(1)
        }
    }
}

/// A tile that shows a word or short value rather than a size.
struct InfoTile: View {
    let icon: String
    let label: String
    let value: String
    let caption: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold).monospacedDigit()).tracking(-0.3)
                .foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
    }
}

// MARK: - Menu bar row

struct AwakeMenuRow: View {
    @Environment(KeepAwake.self) private var awake

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: awake.isOn ? "cup.and.heat.waves.fill" : "cup.and.saucer")
                    .font(.title3)
                    .foregroundStyle(awake.isOn ? Theme.warm : Color.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep Awake").font(.headline)
                    Text(awake.isOn ? awake.statusLine : awake.lidSetupDone ? "Off" : "Off · lid open only")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Menu {
                    ForEach(awakeDurations, id: \.title) { d in
                        Button(d.title) { awake.turnOn(for: d.seconds) }
                    }
                } label: {
                    Image(systemName: "timer")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Keep awake for a while")
                Toggle("", isOn: Binding(get: { awake.isOn }, set: { $0 ? awake.turnOn() : awake.turnOff() }))
                    .toggleStyle(.switch)
                    .tint(Theme.warm)
                    .labelsHidden()
            }
            if let error = awake.lastError {
                Text(error).font(.caption).foregroundStyle(Theme.warn)
            }
        }
    }
}
