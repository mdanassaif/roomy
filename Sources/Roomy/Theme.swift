import SwiftUI
import AppKit

/// Roomy's look: neutral surfaces, hairlines, plain rows, one accent. Colour is for status only.
/// Every colour has a light and a dark value, so both modes are first-class.
enum Theme {
    static let chrome = dynamic(light: (0.962, 0.962, 0.958), dark: (0.086, 0.086, 0.094))
    static let canvas = dynamic(light: (1.000, 1.000, 1.000), dark: (0.110, 0.110, 0.118))
    static let card = dynamic(light: (0.970, 0.970, 0.966), dark: (0.145, 0.145, 0.155))
    static let line = dynamic(light: (0.898, 0.898, 0.890), dark: (0.200, 0.200, 0.212))
    static let empty = dynamic(light: (0.925, 0.925, 0.918), dark: (0.190, 0.190, 0.202))

    static let accent = dynamic(light: (0.310, 0.340, 0.830), dark: (0.545, 0.580, 0.980))
    static let warm = dynamic(light: (0.760, 0.490, 0.060), dark: (0.930, 0.690, 0.280))
    static let warn = dynamic(light: (0.780, 0.180, 0.200), dark: (1.000, 0.430, 0.420))
    static let good = dynamic(light: (0.160, 0.520, 0.360), dark: (0.400, 0.790, 0.590))
    static let calm = dynamic(light: (0.240, 0.380, 0.600), dark: (0.560, 0.690, 0.930))

    static let radius: CGFloat = 7

    static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// A small label above a group of rows.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// A small flat button: solid for the one thing to do now, a quiet fill otherwise.
struct ActionButtonStyle: ButtonStyle {
    var color: Color = .primary
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .foregroundStyle(filled ? Color.white : color)
            .background(filled ? AnyShapeStyle(color) : AnyShapeStyle(Color.primary.opacity(0.06)),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A number with its unit set small beside it: "69.5" "GB".
struct BigValue: View {
    let value: String
    var unit: String = ""
    var size: CGFloat = 30
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: size, weight: .semibold)).monospacedDigit().tracking(-size * 0.02)
            if !unit.isEmpty {
                Text(unit).font(.system(size: max(12, size * 0.4))).foregroundStyle(.secondary)
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

/// One thin bar. `parts` fill from the left in order; whatever's left stays empty.
struct StackBar: View {
    var parts: [(fraction: Double, color: Color)]
    var height: CGFloat = 6
    var gap: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            ctx.fill(shape, with: .color(Theme.empty))
            ctx.clip(to: shape)
            var x: CGFloat = 0
            for p in parts {
                let w = size.width * CGFloat(min(1, max(0, p.fraction)))
                guard w > 0 else { continue }
                ctx.fill(Path(CGRect(x: x, y: 0, width: max(1, w - gap), height: size.height)), with: .color(p.color))
                x += w
            }
        }
        .frame(height: height)
    }
}
