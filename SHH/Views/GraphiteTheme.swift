import AppKit
import CoreText
import SwiftUI

/// "Graphite", the dashboard's look: warm dark greys with a hint of the brand's
/// Desert Sand, never pure black, and a single Spice accent.
/// Reference: prototype/alternatives/studio-graphite.html
enum Graphite {
    static let background = Color(hex: "1B1A19")
    static let sidebar = Color(hex: "151413")
    static let raised = Color(hex: "2B2927")
    static let text = Color(hex: "F1EEE8")      // 15.0:1 on background
    static let text2 = Color(hex: "B4AEA5")     // 7.9:1
    static let text3 = Color(hex: "9C958C")     // 5.9:1, meta only

    static let hairline = ink(0.08)
    static let hover = ink(0.035)
    static let fill = ink(0.065)
    static let fillHover = ink(0.1)
    static let fieldHover = ink(0.08)
    static let fieldFocus = ink(0.085)
    static let selected = ink(0.075)
    static let switchOff = ink(0.22)
    static let ring = ink(0.34)

    static let accent = Color(hex: "F26A4B")    // brand Spice #E94F37 lifted for dark: 5.7:1 on background
    static let accentHover = Color(hex: "F47C60")
    static let onAccent = Color(hex: "1C0E0A")
    static let searchMark = Color(hex: "F26A4B").opacity(0.28)

    static let windowBackground = NSColor(srgbRed: 0x1B / 255, green: 0x1A / 255, blue: 0x19 / 255, alpha: 1)

    static func ink(_ opacity: Double) -> Color {
        Color(hex: "F1EEE8").opacity(opacity)
    }

    /// Registers the bundled Inter faces for this process. Call once at launch.
    static func registerFonts() {
        for name in ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Model sizes the way the dashboard shows them: "466 MB", "1.53 GB".
    static func formatBytes(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= 1e9 { return String(format: "%.2f GB", value / 1e9) }
        return "\(Int((value / 1e6).rounded())) MB"
    }
}

extension Font {
    /// Inter at a fixed size. Falls back to the system font if Inter isn't registered.
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face: String
        switch weight {
        case .medium: face = "Inter-Medium"
        case .semibold: face = "Inter-SemiBold"
        case .bold, .heavy, .black: face = "Inter-Bold"
        default: face = "Inter-Regular"
        }
        return .custom(face, fixedSize: size)
    }

    static func graphiteMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
