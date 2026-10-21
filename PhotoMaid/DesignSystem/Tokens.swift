import SwiftUI
import UIKit

/// Experiment-Design (Artefakt „PhotoMaid – komplette App“, 21.10.2026): warmes Dunkel, Bernstein-Akzent, immer
/// dunkel. Werte 1:1 aus dem Artefakt; Text auf Akzentflächen ist dunkel (`onAccent`), nie weiß.
enum AppColors {
    static let background = hex(0x0F0E0D)
    static let backgroundTint = hex(0x1B1917)
    /// Deckende Inhalte (Karten, Zeilengruppen).
    static let surface = hex(0x1B1917)
    static let surfaceStroke = hex(0x2A2623)
    /// Rand runder Knöpfe, Chips und der Tableiste.
    static let control = hex(0x2F2B28)
    /// Gestrichelte Leerflächen.
    static let dashed = hex(0x3A3531)
    static let textPrimary = hex(0xF4EFE8)
    static let textSecondary = hex(0xA89F94)
    static let textTertiary = hex(0x8E857B)
    /// Akzent für Text/Symbole.
    static let accent = hex(0xF2B24C)
    /// Akzent als Fläche – Schrift darauf `onAccent`.
    static let accentFill = hex(0xF2B24C)
    static let onAccent = hex(0x1A1208)
    static let keep = hex(0x7CC8FF)
    static let onKeep = hex(0x06202F)
    static let cleanup = hex(0xFF7A50)
    static let cleanupFill = hex(0xFF6A3D)
    static let onCleanup = hex(0x1A0B05)
    static let later = hex(0xC4B5FD)
    static let onLater = hex(0x1A1430)
    static let warning = hex(0xF2B24C)
    static let success = hex(0x8FD9A8)
    static let indigo = later
    /// Warmer Markenton für Kacheln und Illustrationen – nie für Text.
    static let warm = hex(0x2A2418)
    static let warmStrong = hex(0x3A3022)
    static let amber = hex(0xF2B24C)
    /// Editor und Medien-Bühnen sind immer dunkel (wie die Fotos-App).
    static let stage = Color.black

    // Symbolkacheln (40 × 40) der Zeilen und Karten.
    static let tileAmber = hex(0x2A2418)
    static let tileCleanup = hex(0x33201A)
    static let tileLater = hex(0x262236)
    static let tileKeep = hex(0x1C2A33)
    static let tileGreen = hex(0x1C2A22)

    // „Kurze Pause“ (Spiele): violetter Grund.
    static let pauseGround = hex(0x13111C)
    static let pauseSurface = hex(0x1E1A2B)
    static let pauseStroke = hex(0x2E2842)
    static let pauseText = hex(0xB4A9CC)
    static let pauseMuted = hex(0x8F86A6)

    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> Color { Color(uiColor: UIColor(hex: value, alpha: alpha)) }
}

extension UIColor {
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
