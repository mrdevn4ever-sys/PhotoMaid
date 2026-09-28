import SwiftUI
import UIKit

/// Farbrollen der hellblauen PhotoMaid-Identität. Light ist die Referenz;
/// Dark ist dieselbe Marke (tiefes Nachtblau statt Schwarz), keine zweite Designsprache.
/// Erhöhter Kontrast wird über eigene Werte bedient.
enum AppColors {
    /// Sehr helle eisblaue Grundfläche.
    static let background = dynamic(light: 0xEEF5FD, dark: 0x0B1626, lightHC: 0xF6FAFF, darkHC: 0x050B14)
    /// Zweiter Verlaufston der Grundfläche.
    static let backgroundTint = dynamic(light: 0xDCEAFB, dark: 0x122540, lightHC: 0xE8F1FC, darkHC: 0x0A1628)
    /// Ruhige, gut lesbare Fläche für Inhaltslisten (kein Glas).
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x15243A, lightHC: 0xFFFFFF, darkHC: 0x101C2E, lightAlpha: 0.78, darkAlpha: 0.86)
    static let surfaceStroke = dynamic(light: 0xFFFFFF, dark: 0x2A3E5C, lightHC: 0x8FA6C4, darkHC: 0x6C84A6, lightAlpha: 0.9, darkAlpha: 0.9)
    /// Dunkelblaue Typografie.
    static let textPrimary = dynamic(light: 0x0F2747, dark: 0xEAF2FF, lightHC: 0x06152B, darkHC: 0xFFFFFF)
    static let textSecondary = dynamic(light: 0x4A6282, dark: 0xA9BCD6, lightHC: 0x2B3F5C, darkHC: 0xD5E1F2)
    /// Klares Systemblau für primäre Aktionen.
    static let accent = Color(uiColor: .systemBlue)
    static let keep = Color(uiColor: .systemBlue)
    static let cleanup = Color(uiColor: .systemRed)
    static let later = Color(uiColor: .systemTeal)
    static let warning = Color(uiColor: .systemOrange)
    static let success = Color(uiColor: .systemGreen)

    private static func dynamic(light: UInt32, dark: UInt32, lightHC: UInt32, darkHC: UInt32,
                                lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let hc = traits.accessibilityContrast == .high
            let hex = isDark ? (hc ? darkHC : dark) : (hc ? lightHC : light)
            let alpha = hc ? 1 : (isDark ? darkAlpha : lightAlpha)
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        })
    }
}

/// Systemschrift, Dynamic Type. Keine festen Punktgrößen für Fließtext.
enum AppTypography {
    static let largeTitle = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let subheadline = Font.subheadline
    static let caption = Font.caption
    static let metric = Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
}

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Seitliche Ränder (16–20 pt).
    static let pageMargin: CGFloat = 18
    /// Mindest-Touchfläche.
    static let minTouch: CGFloat = 44
}

enum AppRadii {
    static let small: CGFloat = 12
    static let card: CGFloat = 22
    static let sheet: CGFloat = 28
}

enum AppMotion {
    static func standard(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }
    static func commit(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.22)
    }
}
