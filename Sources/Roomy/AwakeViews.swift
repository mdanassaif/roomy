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
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(awake.isOn ? Theme.warm : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                    Eyebrow(awake.isOn ? (awake.lidClosedActive ? "On · lid closed is fine" : "On · keep the lid open") : "Off")
                }
                Text(awake.isOn ? "Staying awake" : "Sleeping normally")
                    .font(.system(size: 44, weight: .regular, design: .serif)).tracking(-0.6)
                    .padding(.top, 10)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(awake.statusLine).font(.title3).foregroundStyle(.secondary)
                }
                .padding(.top, 2)
                HStack(spacing: 8) {
                    Button(awake.isOn ? "Turn Off" : "Keep Awake") {
                        withAnimation(.snappy) { awake.toggle() }
                    }
                    .buttonStyle(PillButtonStyle(color: awake.isOn ? .secondary : Theme.warm, filled: !awake.isOn))
                    Rectangle().fill(Theme.line).frame(width: 1, height: 22).padding(.horizontal, 4)
                    ForEach(awakeDurations.dropLast(), id: \.title) { d in
                        Button(d.title) { withAnimation(.snappy) { awake.turnOn(for: d.seconds) } }
                            .buttonStyle(PillButtonStyle(color: .secondary))
                    }
                }
                .padding(.top, 24)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().strokeBorder(awake.isOn ? Theme.warm.opacity(0.35) : Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                Circle().fill(awake.isOn ? Theme.warm.opacity(0.14) : Theme.empty).padding(18)
                Image(systemName: awake.isOn ? "cup.and.heat.waves.fill" : "moon.stars.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(awake.isOn ? Theme.warm : .secondary)
                    .symbolEffect(.pulse, isActive: awake.isOn)
            }
            .frame(width: 150, height: 150)
        }
        .frame(minHeight: 240)
        .washTile(padding: 30, color: awake.isOn ? Theme.warm : nil)
        .animation(.snappy, value: awake.isOn)
    }

    var lidTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Glyph(symbol: "laptopcomputer", color: awake.lidSetupDone ? Theme.good : Theme.accent)
                Spacer()
                if awake.lidSetupDone { Label("Ready", systemImage: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(Theme.good) }
            }
            Text("Lid-closed mode").font(.system(size: 19, design: .serif)).padding(.top, 4)
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
            Glyph(symbol: "shield.lefthalf.filled", color: Theme.calm)
            Text("It turns itself off").font(.system(size: 19, design: .serif)).padding(.top, 4)
            rule("timer", "When your timer runs out")
            rule("battery.25percent", "On battery at \(KeepAwake.batteryMinOpen)%, or \(KeepAwake.batteryMinClosed)% with the lid closed")
            rule("thermometer.medium", "If it runs hot with the lid closed")
            rule("xmark.app", "When you quit Roomy")
            if let last = awake.lastStop {
                Eyebrow("Last time: \(last)").padding(.top, 2)
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
