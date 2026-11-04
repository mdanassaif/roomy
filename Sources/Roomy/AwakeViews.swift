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

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 0) {
                RoomHeader(room: .awake, subtitle: "Keep your Mac running for downloads, builds and remote sessions") { EmptyView() }
                VStack(alignment: .leading, spacing: 28) {
                    status
                    if let error = awake.lastError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn).font(.system(size: 12.5))
                    }
                    lid
                    rules
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 90)
            }
        }
    }

    var status: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle().fill(awake.isOn ? Theme.good : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                    Text(awake.isOn ? "Staying awake" : "Sleeping normally").font(.system(size: 26, weight: .semibold)).tracking(-0.4)
                }
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(awake.statusLine).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Button(awake.isOn ? "Turn Off" : "Keep Awake") { awake.toggle() }
                    .buttonStyle(ActionButtonStyle(color: awake.isOn ? .primary : Theme.accent, filled: !awake.isOn))
                ForEach(awakeDurations.dropLast(), id: \.title) { d in
                    Button(d.title) { awake.turnOn(for: d.seconds) }.buttonStyle(ActionButtonStyle(color: .secondary))
                }
            }
        }
    }

    var lid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Eyebrow("Lid-closed mode")
                if awake.lidSetupDone { Text("Ready").font(.system(size: 12)).foregroundStyle(Theme.good) }
            }
            Text(awake.lidSetupDone
                 ? "Close the lid and your Mac keeps going, Wi-Fi included. Sleep goes back to normal when Keep Awake turns off."
                 : "Needs your password once. Roomy then allows only the two sleep commands it uses, nothing else.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            if !awake.lidSetupDone {
                Button("Set Up…") { awake.setUpLidClosed() }.buttonStyle(ActionButtonStyle()).padding(.top, 4)
            }
        }
    }

    var rules: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("It turns itself off")
            rule("timer", "When your timer runs out")
            rule("battery.25percent", "On battery at \(KeepAwake.batteryMinOpen)%, or \(KeepAwake.batteryMinClosed)% with the lid closed")
            rule("thermometer.medium", "If it runs hot with the lid closed")
            rule("xmark.app", "When you quit Roomy")
            if let last = awake.lastStop { Eyebrow("Last time: \(last)").padding(.top, 2) }
        }
    }

    func rule(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
        }
        .font(.system(size: 13))
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
