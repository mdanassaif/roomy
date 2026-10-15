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
            VStack(alignment: .leading, spacing: 18) {
                RoomHeader(room: .awake, subtitle: "Keep your Mac running for downloads, builds and remote sessions, even with the lid closed") { EmptyView() }

                VStack(spacing: 16) {
                    hero
                    if let error = awake.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warn)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        lidTile
                        rulesTile
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 110)
            }
        }
    }

    var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: awake.isOn ? "cup.and.heat.waves.fill" : "moon.stars.fill")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(awake.isOn ? Theme.warm : .white.opacity(0.75))
                    .symbolEffect(.pulse, isActive: awake.isOn)
                    .frame(width: 44, height: 44, alignment: .leading)
                Spacer()
                Mono(awake.isOn ? (awake.lidClosedActive ? "lid closed ok" : "lid open") : "off")
            }
            Spacer(minLength: 28)
            Text(awake.isOn ? "Staying awake" : "Sleeping normally")
                .font(.system(size: 34, weight: .bold)).tracking(-0.5)
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(awake.statusLine).font(.title3).foregroundStyle(.white.opacity(0.65))
            }
            .padding(.top, 2)
            HStack(spacing: 10) {
                Button(awake.isOn ? "Turn Off" : "Keep Awake") {
                    withAnimation(.snappy) { awake.toggle() }
                }
                .buttonStyle(PillButtonStyle(color: awake.isOn ? .white : Theme.warm, filled: !awake.isOn))
                .controlSize(.large)
                Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 22).padding(.horizontal, 4)
                ForEach(awakeDurations.dropLast(), id: \.title) { d in
                    Button(d.title) { withAnimation(.snappy) { awake.turnOn(for: d.seconds) } }
                        .buttonStyle(PillButtonStyle(color: .white))
                }
            }
            .padding(.top, 22)
        }
        .frame(minHeight: 260)
        .inkTile(padding: 28, glow: awake.isOn ? Theme.warm : Theme.accent.opacity(0.5))
        .animation(.snappy, value: awake.isOn)
    }

    var lidTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(symbol: "laptopcomputer", color: awake.lidSetupDone ? Theme.good : Theme.accent)
                Spacer()
                if awake.lidSetupDone { Mono("ready") }
            }
            Text("Lid-closed mode").font(.headline).padding(.top, 4)
            Text(awake.lidSetupDone
                 ? "Close the lid and your Mac keeps going, Wi-Fi included. Sleep goes back to normal when Keep Awake turns off."
                 : "Needs your password once. Roomy then allows only the two sleep commands it uses, nothing else.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !awake.lidSetupDone {
                Button("Set Up…") { awake.setUpLidClosed() }.buttonStyle(PillButtonStyle(filled: true)).padding(.top, 4)
            }
        }
        .tile()
    }

    var rulesTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(symbol: "shield.lefthalf.filled", color: .teal)
            Text("It turns itself off").font(.headline).padding(.top, 4)
            rule("timer", "When your timer runs out")
            rule("battery.25percent", "On battery at \(KeepAwake.batteryMinOpen)%, or \(KeepAwake.batteryMinClosed)% with the lid closed")
            rule("thermometer.medium", "If it runs hot with the lid closed")
            rule("xmark.app", "When you quit Roomy")
            if let last = awake.lastStop {
                Mono("last time: \(last)").padding(.top, 2)
            }
        }
        .tile()
    }

    func rule(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
        }
        .font(.callout)
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
                    .foregroundStyle(awake.isOn ? Color.orange : Color.secondary)
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
                    .tint(.orange)
                    .labelsHidden()
            }
            if let error = awake.lastError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
