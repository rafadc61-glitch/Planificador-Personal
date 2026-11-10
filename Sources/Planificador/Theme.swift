import SwiftUI
import AppKit

enum Palette {
    private static func adaptive(_ dark: String, _ light: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
    static let background = adaptive("#0D1423", "#F1F5FA")
    static let sidebar = adaptive("#101A2C", "#E7EDF6")
    static let surface = adaptive("#172337", "#FFFFFF")
    static let raised = adaptive("#1E2D43", "#DDE7F2")
    static let line = adaptive("#314056", "#D8E1EC")
    static let text = adaptive("#F5F3EF", "#14243B")
    static let muted = adaptive("#A3B1C2", "#617185")
    static let lavender = Color(hex: "#BDA6FF")
    static let mint = Color(hex: "#91DFC2")
    static let peach = Color(hex: "#FFBD98")
    static func tagColor(_ tag: String) -> Color {
        let colors = [lavender, mint, peach, Color(hex: "#7FCBD7"), Color(hex: "#F59EB7"), Color(hex: "#E2CE83")]
        let value = tag.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return colors[value % colors.count]
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&number)
        self.init(red: Double((number >> 16) & 0xff) / 255,
                  green: Double((number >> 8) & 0xff) / 255,
                  blue: Double(number & 0xff) / 255)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var number: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&number)
        self.init(red: CGFloat((number >> 16) & 0xff) / 255,
                  green: CGFloat((number >> 8) & 0xff) / 255,
                  blue: CGFloat(number & 0xff) / 255, alpha: 1)
    }
}

struct Surface<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line))
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.muted)
        }
    }
}

struct IconBadge: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct CategoryBadge: View {
    let category: MoneyCategory
    var body: some View {
        Group {
            if let emoji = category.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: 20))
            } else {
                Image(systemName: category.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: category.tint))
            }
        }
        .frame(width: 40, height: 40)
        .background(Color(hex: category.tint).opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TagChip: View {
    let name: String
    var body: some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.tagColor(name))
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Palette.tagColor(name).opacity(0.13), in: Capsule())
            .overlay(Capsule().stroke(Palette.tagColor(name).opacity(0.22)))
    }
}

/// Campo numérico que guarda el valor en cada pulsación (no espera a Enter ni a perder el foco)
/// y conserva lo que escribes aunque la vista se vuelva a dibujar.
struct MoneyField: View {
    var placeholder: String = "0.00"
    @Binding var value: Double
    var allowsNegative: Bool = true
    var allowsDecimals: Bool = true
    @State private var text: String = ""
    @State private var didLoad = false
    @FocusState private var focused: Bool

    private static let posix = Locale(identifier: "en_US_POSIX")

    static func display(_ number: Double, decimals: Bool) -> String {
        guard number.isFinite, number != 0 else { return "" }
        return number.formatted(.number.precision(.fractionLength(0...(decimals ? 2 : 0))).grouping(.never).locale(posix))
    }

    static func parse(_ raw: String, allowsNegative: Bool, allowsDecimals: Bool) -> Double {
        var cleaned = raw.filter { $0.isNumber || $0 == "." || $0 == "-" }
        let negative = allowsNegative && cleaned.hasPrefix("-")
        cleaned.removeAll { $0 == "-" }
        if !allowsDecimals, let dot = cleaned.firstIndex(of: ".") { cleaned = String(cleaned[..<dot]) }
        if let first = cleaned.firstIndex(of: ".") {
            let tail = cleaned[cleaned.index(after: first)...].filter { $0 != "." }
            cleaned = String(cleaned[...first]) + tail
        }
        let number = Double(cleaned) ?? 0
        return negative ? -number : number
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                text = Self.display(value, decimals: allowsDecimals)
            }
            .onChange(of: text) { _, newText in
                let parsed = Self.parse(newText, allowsNegative: allowsNegative, allowsDecimals: allowsDecimals)
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                // Solo reescribe el texto si el valor cambió desde fuera (p. ej. un botón "Usar libre").
                let current = Self.parse(text, allowsNegative: allowsNegative, allowsDecimals: allowsDecimals)
                if abs(current - newValue) > 0.000_001 { text = Self.display(newValue, decimals: allowsDecimals) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = Self.display(value, decimals: allowsDecimals) }
            }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Palette.lavender)
            Text(title).font(.headline).foregroundStyle(Palette.text)
            Text(detail).font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

extension Date {
    var shortDay: String { formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) }
    var hourText: String { formatted(.dateTime.hour().minute()) }
}
