import SwiftUI
import UIKit

/// Experiment-Design (Artefakt „PhotoMaid – komplette App“, 21.10.2026): warmes Dunkel, Bernstein-Akzent. Werte im
/// Dunkelmodus 1:1 aus dem Artefakt; dazu ein heller Modus im selben warmen Stil (Nutzerwunsch 21.10.2026,
/// Einstellungen › Erscheinungsbild, Standard dunkel). Text auf Akzentflächen ist dunkel (`onAccent`), nie weiß.
enum AppColors {
    static let background = dyn(0x0F0E0D, 0xF6F2EC)
    static let backgroundTint = dyn(0x1B1917, 0xFFFFFF)
    /// Deckende Inhalte (Karten, Zeilengruppen).
    static let surface = dyn(0x1B1917, 0xFFFFFF)
    static let surfaceStroke = dyn(0x2A2623, 0xE9E2D8)
    /// Rand runder Knöpfe, Chips und der Tableiste.
    static let control = dyn(0x2F2B28, 0xDDD4C8)
    /// Gestrichelte Leerflächen.
    static let dashed = dyn(0x3A3531, 0xCFC5B8)
    static let textPrimary = dyn(0xF4EFE8, 0x1C1916)
    static let textSecondary = dyn(0xA89F94, 0x6F665C)
    static let textTertiary = dyn(0x8E857B, 0x776E64)
    /// Abgeschwächter Text (z. B. Aufzählungen in der Pro-Karte).
    static let textMuted = dyn(0xD8D0C6, 0x4A433C)
    /// Nicht verfügbare Symbole (z. B. Rückgängig ohne Schritt).
    static let disabled = dyn(0x5A534C, 0xB9B0A5)
    /// Akzent für Text/Symbole.
    static let accent = dyn(0xF2B24C, 0x9A600E)
    /// Akzent als Fläche – Schrift darauf `onAccent`.
    static let accentFill = hex(0xF2B24C)
    static let onAccent = hex(0x1A1208)
    static let keep = dyn(0x7CC8FF, 0x1B6FA8)
    static let onKeep = dyn(0x06202F, 0xFFFFFF)
    static let cleanup = dyn(0xFF7A50, 0xC4441A)
    static let cleanupFill = hex(0xFF6A3D)
    static let onCleanup = hex(0x1A0B05)
    /// „Endgültig löschen“ als ruhige Kapsel (Tresor-Papierkorb).
    static let cleanupSoft = dyn(0x26150F, 0xFCE3D9)
    static let cleanupSoftStroke = dyn(0x5A2E20, 0xF2B6A0)
    static let later = dyn(0xC4B5FD, 0x6347D0)
    static let onLater = dyn(0x1A1430, 0xFFFFFF)
    static let warning = dyn(0xF2B24C, 0x9A600E)
    static let success = dyn(0x8FD9A8, 0x277548)
    static let indigo = later
    /// Warmer Markenton für Kacheln und Illustrationen – nie für Text.
    static let warm = dyn(0x2A2418, 0xFBEED6)
    static let warmStrong = dyn(0x3A3022, 0xF3DFBA)
    static let amber = hex(0xF2B24C)
    /// Editor und Medien-Bühnen sind immer dunkel (wie die Fotos-App).
    static let stage = Color.black
    /// Schatten schwebender Flächen (Tableiste): im Hellen deutlich leiser.
    static let shadow = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.black.withAlphaComponent(0.5) : UIColor.black.withAlphaComponent(0.14) })

    // Symbolkacheln (40 × 40) der Zeilen und Karten.
    static let tileAmber = dyn(0x2A2418, 0xFBEED6)
    static let tileCleanup = dyn(0x33201A, 0xFCE3D9)
    static let tileLater = dyn(0x262236, 0xECE7FD)
    static let tileKeep = dyn(0x1C2A33, 0xE0EFF9)
    static let tileGreen = dyn(0x1C2A22, 0xDFF2E6)

    // „Kurze Pause“ (Spiele): violetter Grund.
    static let pauseGround = dyn(0x13111C, 0xF1EEFB)
    static let pauseSurface = dyn(0x1E1A2B, 0xEFEBFC)
    static let pauseStroke = dyn(0x2E2842, 0xDCD4F6)
    static let pauseText = dyn(0xB4A9CC, 0x574E7C)
    static let pauseMuted = dyn(0x8F86A6, 0x7D759C)
    static let pauseLine = dyn(0x3D3460, 0xD6CEF3)

    /// Farbe je Erscheinungsbild: dunkel (Artefakt) und hell.
    static func dyn(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(uiColor: UIColor.dynamic(dark: dark, light: light))
    }

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> Color { Color(uiColor: UIColor(hex: value, alpha: alpha)) }
}

extension UIColor {
    static func dynamic(dark: UInt32, light: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Schriften des Artefakts (OFL, statische Instanzen unter `Resources/Fonts`): Figtree für Text (`PMText`),
/// Bricolage Grotesque für Titel und Zahlen (`PMDisplay`, große Zähler `PMDisplayXL`). Größen = Artefakt bei
/// Standard-Textgröße; Dynamic Type skaliert über `relativeTo`.
enum PMFont {
    enum Weight { case regular, medium, semibold, bold }

    static func text(_ weight: Weight, _ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .regular: "PMText-Regular"
        case .medium: "PMText-Medium"
        case .semibold: "PMText-SemiBold"
        case .bold: "PMText-Bold"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    /// Bricolage 800 (Seitentitel 40, Zähler 58).
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(size >= 44 ? "PMDisplayXL-ExtraBold" : "PMDisplay-ExtraBold", size: size, relativeTo: style)
    }

    /// Bricolage 700 (Abschnitte, Kartentitel, Kennzahlen).
    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        .custom("PMDisplay-Bold", size: size, relativeTo: style)
    }

    /// Bricolage 600 (Ziffernfeld).
    static func keypad(_ size: CGFloat) -> Font { .custom("PMDisplay-SemiBold", size: size, relativeTo: .title) }

    static func uiText(_ weight: Weight, _ size: CGFloat) -> UIFont {
        let name = switch weight {
        case .regular: "PMText-Regular"
        case .medium: "PMText-Medium"
        case .semibold: "PMText-SemiBold"
        case .bold: "PMText-Bold"
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }

    static func uiDisplay(_ size: CGFloat) -> UIFont {
        UIFont(name: "PMDisplay-ExtraBold", size: size) ?? .systemFont(ofSize: size, weight: .heavy)
    }
}

/// Schriftstufen (Artefakt-Größen in pt bei Standard-Textgröße).
enum AppTypography {
    /// Große Zahl im Hero (58).
    static let display = PMFont.display(58)
    /// Seitentitel (40, Bricolage 800).
    static let largeTitle = PMFont.display(40)
    static let title = PMFont.heading(22)
    static let title3 = PMFont.heading(20, relativeTo: .title3)
    static let headline = PMFont.text(.semibold, 16, relativeTo: .headline)
    static let body = PMFont.text(.regular, 16)
    static let callout = PMFont.text(.medium, 15, relativeTo: .callout)
    static let subheadline = PMFont.text(.regular, 15, relativeTo: .subheadline)
    static let footnote = PMFont.text(.regular, 13, relativeTo: .footnote)
    static let caption = PMFont.text(.regular, 13, relativeTo: .caption)
    static let metric = PMFont.heading(30, relativeTo: .title)
    static let metricSmall = PMFont.heading(18, relativeTo: .headline)
    /// Großer Knopf (17, Figtree 700).
    static let button = PMFont.text(.bold, 17, relativeTo: .headline)
    /// Großbuchstaben-Etikett über dem Hero (13, 600, Laufweite 0,08 em).
    static let eyebrow = PMFont.text(.semibold, 13, relativeTo: .footnote)
    /// Tableiste (11, 600).
    static let tab = PMFont.text(.semibold, 11, relativeTo: .caption2)
}

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Seitenrand wie im Artefakt (20).
    static let pageMargin: CGFloat = 20
    /// Mindest-Touchfläche (Masterprompt: ≥ 44 pt, bevorzugt 48 pt).
    static let minTouch: CGFloat = 44
    static let touch: CGFloat = 48
    /// Platz für die schwebende Tableiste unter dem Inhalt.
    static let tabBarClearance: CGFloat = 120
}

enum AppRadii {
    static let small: CGFloat = 12
    static let card: CGFloat = 22
    static let sheet: CGFloat = 28
    static let thumb: CGFloat = 6
    static let button: CGFloat = 18
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

extension Text {
    /// Seitentitel wie im Artefakt: Bricolage 800, 40 pt, Laufweite −0,02 em.
    func pageTitle() -> some View {
        font(AppTypography.largeTitle).tracking(-0.8).foregroundStyle(AppColors.textPrimary)
    }

    /// Großbuchstaben-Etikett (Hero): 13 pt, 600, Laufweite 0,08 em, Akzent.
    func eyebrow(_ color: Color = AppColors.accent) -> some View {
        font(AppTypography.eyebrow).tracking(1.04).textCase(.uppercase).foregroundStyle(color)
    }
}
