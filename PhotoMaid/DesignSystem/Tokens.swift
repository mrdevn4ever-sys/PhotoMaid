import SwiftUI
import UIKit

/// Farbrollen der PhotoMaid-Identität: warmer Grund (Creme/Sand), Blau als Akzent – wie Android (2026-10-04).
/// Hell ist die Referenz; Dunkel ist dieselbe Marke (warmes Anthrazit). Erhöhter Kontrast hat eigene Werte.
/// Glas kommt ausschließlich von Liquid Glass (`glassEffect`, `.glass`-Buttonstile) – nie aus diesen Farben.
enum AppColors {
    static let background = dynamic(0xFAF6F1, 0x161311, hcLight: 0xFFFBF7, hcDark: 0x0B0907)
    static let backgroundTint = dynamic(0xF2EBE3, 0x201B18, hcLight: 0xF4EEE7, hcDark: 0x15110F)
    /// Ruhige, deckende Fläche für Listen und Karten (kein Glas).
    static let surface = dynamic(0xFFFFFF, 0x262120, hcLight: 0xFFFFFF, hcDark: 0x1C1816)
    static let surfaceStroke = dynamic(0xEADFD3, 0x3A322D, hcLight: 0xA89584, hcDark: 0x857565)
    static let textPrimary = dynamic(0x231F1C, 0xF5EFE9, hcLight: 0x120F0D, hcDark: 0xFFFFFF)
    static let textSecondary = dynamic(0x6B625A, 0xC2B6AA, hcLight: 0x453E37, hcDark: 0xE6DDD3)
    /// Akzent für Text/Symbole (AA ≥ 4,5 : 1).
    static let accent = dynamic(0x0064D2, 0x4DA3FF, hcLight: 0x0050A8, hcDark: 0x7ABCFF)
    /// Akzent als Fläche mit weißer Schrift.
    static let accentFill = dynamic(0x0071E3, 0x0A84FF, hcLight: 0x0058B0, hcDark: 0x0A84FF)
    static let keep = Color(uiColor: .systemBlue)
    static let cleanup = dynamic(0xD70015, 0xFF453A, hcLight: 0xB00012, hcDark: 0xFF6961)
    static let later = dynamic(0x0E8FA8, 0x40C8E0, hcLight: 0x0A7287, hcDark: 0x70D7EA)
    static let warning = Color(uiColor: .systemOrange)
    static let success = dynamic(0x248A3D, 0x30D158, hcLight: 0x1B6E30, hcDark: 0x5BE07A)
    static let indigo = Color(uiColor: .systemIndigo)
    /// Warmer Markenton (Sand/Latte) für Einführung, Hero und Illustrationen – nie für Text.
    static let warm = dynamic(0xEFE7DA, 0x2B2622, hcLight: 0xE9DFCF, hcDark: 0x332C27)
    static let warmStrong = dynamic(0xDCC9AB, 0x54473A, hcLight: 0xCDB894, hcDark: 0x66574A)
    static let amber = dynamic(0xB86A00, 0xF0B53C, hcLight: 0x8F5200, hcDark: 0xFFC857)
    /// Editor und Medien-Bühnen sind immer dunkel (wie die Fotos-App).
    static let stage = Color.black

    private static func dynamic(_ light: UInt32, _ dark: UInt32, hcLight: UInt32, hcDark: UInt32) -> Color {
        Color(uiColor: UIColor { t in
            let isDark = t.userInterfaceStyle == .dark
            let hc = t.accessibilityContrast == .high
            return UIColor(hex: isDark ? (hc ? hcDark : dark) : (hc ? hcLight : light))
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Systemschrift, Dynamic Type. Keine festen Punktgrößen für Fließtext.
enum AppTypography {
    static let display = Font.largeTitle.weight(.heavy)
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.semibold)
    static let title3 = Font.title3.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let callout = Font.callout
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let metric = Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
    static let metricSmall = Font.system(.headline, design: .rounded).weight(.semibold).monospacedDigit()
}

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let pageMargin: CGFloat = 16
    /// Mindest-Touchfläche (Masterprompt: ≥ 44 pt, bevorzugt 48 pt).
    static let minTouch: CGFloat = 44
    static let touch: CGFloat = 48
}

enum AppRadii {
    static let small: CGFloat = 12
    static let card: CGFloat = 22
    static let sheet: CGFloat = 28
    static let thumb: CGFloat = 6
}

enum AppMotion {
    static func standard(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    static func commit(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.2)
    }

    /// Öffnen: kurzer, leichter Übergang (Android: 150-ms-Fade).
    static func open(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.15) }
}
