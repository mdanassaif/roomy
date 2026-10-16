import SwiftUI
import AppKit

/// Roomy's look: warm paper, hairline-edged cards, serif numbers, one coral accent,
/// and space drawn as rows of little blocks, like rooms in a floor plan.
/// Every colour has a light and a dark value, so both modes are first-class.
enum Theme {
    static let canvas = dynamic(light: (0.962, 0.949, 0.925), dark: (0.082, 0.078, 0.071))
    static let card = dynamic(light: (0.995, 0.991, 0.980), dark: (0.129, 0.123, 0.112))
    static let line = dynamic(light: (0.875, 0.855, 0.815), dark: (0.235, 0.224, 0.204))
    static let empty = dynamic(light: (0.915, 0.900, 0.870), dark: (0.200, 0.191, 0.175))

    static let accent = dynamic(light: (0.855, 0.330, 0.200), dark: (0.980, 0.510, 0.365))
    static let accentSoft = dynamic(light: (0.985, 0.915, 0.885), dark: (0.255, 0.140, 0.105))
    static let warm = dynamic(light: (0.835, 0.560, 0.090), dark: (0.960, 0.720, 0.300))
    static let warn = dynamic(light: (0.780, 0.180, 0.200), dark: (1.000, 0.430, 0.420))
    static let good = dynamic(light: (0.200, 0.530, 0.380), dark: (0.430, 0.800, 0.600))
    static let calm = dynamic(light: (0.240, 0.380, 0.600), dark: (0.560, 0.690, 0.930))

    static let radius: CGFloat = 14

    static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

extension View {
    /// A paper card with a hairline edge. No drop shadow: the edge does the work.
    func tile(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    /// A card washed with a colour, for things that are "on" right now (Keep Awake, charging).
    func washTile(padding: CGFloat = 20, color: Color?) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.card)
                    .overlay {
                        if let color {
                            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(color.opacity(0.12))
                        }
                    }
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(color.map { $0.opacity(0.45) } ?? Theme.line, lineWidth: 1))
    }
}

/// A small sans label set above or beside a value: "Macintosh HD", "of 8 GB".
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// A symbol on a softly tinted square.
struct Glyph: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// "Open ›": a quiet text link in a card's corner.
struct OpenLink: View {
    var title = "Open"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A capsule button: solid when it's the thing to do now, outlined otherwise.
struct PillButtonStyle: ButtonStyle {
    var color: Color = Theme.accent
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(filled ? Color.white : color)
            .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(Color.clear), in: Capsule())
            .overlay(Capsule().strokeBorder(filled ? Color.clear : color.opacity(0.45), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A big serif number with its unit set small beside it: "69.5" "GB".
struct BigValue: View {
    let value: String
    var unit: String = ""
    var size: CGFloat = 30
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: size, weight: .regular, design: .serif)).monospacedDigit()
            if !unit.isEmpty {
                Text(unit).font(.system(size: max(12, size * 0.36), weight: .medium)).foregroundStyle(.secondary)
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

/// Roomy's signature bar: a row of blocks, each one a slice of the whole.
/// `parts` fill from the left in order; whatever's left stays empty.
struct BlockBar: View {
    var parts: [(fraction: Double, color: Color)]
    var count = 24
    var height: CGFloat = 8
    var gap: CGFloat = 2

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: min(3, height / 3), style: .continuous)
                    .fill(color(at: i))
            }
        }
        .frame(height: height)
    }

    func color(at i: Int) -> Color {
        let mid = (Double(i) + 0.5) / Double(count)
        var edge = 0.0
        for p in parts {
            edge += max(0, p.fraction)
            if mid < edge { return p.color }
        }
        return Theme.empty
    }
}

/// A single-value block bar.
struct Meter: View {
    let fraction: Double
    var color: Color = Theme.accent
    var height: CGFloat = 6
    var count = 20
    var body: some View {
        BlockBar(parts: [(min(1, max(0, fraction)), color)], count: count, height: height)
            .animation(.snappy, value: fraction)
    }
}
