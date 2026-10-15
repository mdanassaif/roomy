import SwiftUI
import AppKit

/// Roomy's look: a soft tinted canvas, white cards, a few dark tiles, one violet accent.
enum Theme {
    static let canvas = dynamic(light: (0.949, 0.947, 0.965), dark: (0.075, 0.073, 0.09))
    static let card = dynamic(light: (1, 1, 1), dark: (0.155, 0.152, 0.18))
    static let accent = dynamic(light: (0.42, 0.33, 0.88), dark: (0.62, 0.54, 1.0))
    static let accentSoft = dynamic(light: (0.93, 0.91, 0.99), dark: (0.22, 0.19, 0.33))
    static let warm = Color(red: 0.96, green: 0.58, blue: 0.20)
    static let warn = dynamic(light: (0.76, 0.48, 0.08), dark: (0.95, 0.68, 0.25))
    static let good = Color(red: 0.20, green: 0.68, blue: 0.48)

    /// Dark tiles stay dark in both modes, like a lit display.
    static let ink = LinearGradient(colors: [Color(red: 0.11, green: 0.10, blue: 0.15), Color(red: 0.06, green: 0.055, blue: 0.08)],
                                    startPoint: .top, endPoint: .bottom)

    static let radius: CGFloat = 22

    static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

extension View {
    /// A white (or dark-mode grey) rounded card.
    func tile(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.04), radius: 14, y: 6)
    }

    /// A dark tile, with an optional coloured glow in the corner.
    func inkTile(padding: CGFloat = 20, glow: Color? = nil) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .background {
                ZStack {
                    Theme.ink
                    if let glow {
                        RadialGradient(colors: [glow.opacity(0.55), .clear], center: .bottomLeading, startRadius: 4, endRadius: 260)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

/// Small monospaced caps, for labels like "ON POWER" or dates.
struct Mono: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// A coloured circle holding a white symbol.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
    }
}

/// The round ↗ button in a tile's corner.
struct ArrowButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.07), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

/// A soft pill button, filled when it's the thing to do now.
struct PillButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(filled ? Color.white : color)
            .background(filled ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.13)),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// A big number with its unit set small beside it: "69.5" "GB".
struct BigValue: View {
    let value: String
    var unit: String = ""
    var size: CGFloat = 30
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
            if !unit.isEmpty {
                Text(unit).font(.system(size: size * 0.45, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// "69.47 GB" → ("69.5", "GB")
func sizeParts(_ bytes: Int64) -> (String, String) {
    let s = fmt(bytes)
    let parts = s.split(separator: " ", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return (s, "") }
    let unit = parts[1] == "bytes" || parts[1] == "byte" ? "B" : parts[1]
    if parts[0] == "Zero" { return ("0", unit) }
    if let d = Double(parts[0].replacingOccurrences(of: ",", with: "")), d >= 10 {
        return (String(format: d >= 100 ? "%.0f" : "%.1f", d), unit)
    }
    return (parts[0], unit)
}

/// A thin progress line.
struct Meter: View {
    let fraction: Double
    var color: Color = Theme.accent
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color.gradient).frame(width: max(height, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}
