import AppKit
import CoreText
import SwiftUI

/// "Ink", the dashboard's look, after the Silenzio mark: solid black organic shapes on white
/// paper and no accent colour. In dark mode it turns into its negative, a light blob on a dark page.
/// Ink is the colour of the shapes and the text; paper is the page, and whatever sits on ink.
/// Reference: prototype/alternatives/studio-ink.html
enum Ink {
    static let paper = adaptive(srgb(0xFFFFFF), srgb(0x0F0F0E))
    static let ink = adaptive(srgb(0x0D0D0D), srgb(0xF3F1EC))
    static let text = ink
    static let text2 = adaptive(srgb(0x545350), srgb(0xB3B0AA))   // 7.6:1 on paper, 8.6:1 dark
    static let text3 = adaptive(srgb(0x6C6B68), srgb(0x95928C))   // 5.3:1, 6.0:1 dark; meta only
    static let inkSoft = adaptive(srgb(0x2E2E2D), srgb(0xD9D6CF))  // primary button hover

    static let hairline = tint(0.09, 0.1)
    static let hover = tint(0.04, 0.045)
    static let fill = tint(0.06, 0.08)
    static let fillHover = tint(0.1, 0.13)
    static let off = tint(0.2, 0.26)

    // On the ink blob: the sidebar, the toast, keys, the recording widget and its style picker.
    static let onInk = paper
    static let onInk2 = onInkTint(0.7, 0.7)
    static let onInk3 = onInkTint(0.45, 0.45)
    static let inkHover = onInkTint(0.11, 0.08)
    static let inkHair = onInkTint(0.14, 0.12)

    static let shadow = adaptive(NSColor.black.withAlphaComponent(0.22), NSColor.black.withAlphaComponent(0.55))
    static let windowBackground = NSColor(name: nil) { appearance in
        isDark(appearance) ? srgb(0x0F0F0E) : srgb(0xFFFFFF)
    }

    /// Ink at an opacity, for fills and hairlines on paper.
    private static func tint(_ light: CGFloat, _ dark: CGFloat) -> Color {
        adaptive(srgb(0x0D0D0D, light), srgb(0xF3F1EC, dark))
    }

    /// Paper at an opacity, for things drawn on ink.
    private static func onInkTint(_ light: CGFloat, _ dark: CGFloat) -> Color {
        adaptive(srgb(0xFFFFFF, light), srgb(0x0F0F0E, dark))
    }

    private static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { isDark($0) ? dark : light })
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Registers the bundled faces for this process. Call once at launch.
    /// Bricolage Grotesque is a static cut of the variable font at the 14pt optical size.
    static func registerFonts() {
        let faces = [
            "BricolageGrotesque-Regular", "BricolageGrotesque-Medium",
            "BricolageGrotesque-SemiBold", "BricolageGrotesque-Bold",
            "Rock3D-Regular",
        ]
        for name in faces {
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
    /// Bricolage Grotesque, the text face, at a fixed size. Falls back to the system font if it isn't registered.
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face: String
        switch weight {
        case .medium: face = "BricolageGrotesque-Medium"
        case .semibold: face = "BricolageGrotesque-SemiBold"
        case .bold, .heavy, .black: face = "BricolageGrotesque-Bold"
        default: face = "BricolageGrotesque-Regular"
        }
        return .custom(face, fixedSize: size)
    }

    static func inkMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
