import SwiftUI

// Experiment-Design (Artefakt): schwebende Bedienelemente sind deckende, dunkle Flächen mit feinem Rand statt
// Liquid Glass. Die bisherigen Namen bleiben, damit alle Ansichten das neue Aussehen ohne Umbau übernehmen.

struct GlassCapsuleModifier: ViewModifier {
    var interactive = false
    var tint: Color?
    var overMedia = false

    func body(content: Content) -> some View {
        content
            .background((tint ?? AppColors.surface).opacity(tint == nil ? 0.96 : 1), in: .capsule)
            .overlay(Capsule().strokeBorder(tint == nil ? AppColors.control : Color.clear, lineWidth: 1))
            .shadow(color: .black.opacity(overMedia ? 0.4 : 0.25), radius: 14, y: 6)
    }
}

struct GlassRectModifier: ViewModifier {
    var radius: CGFloat = AppRadii.card
    var interactive = false

    func body(content: Content) -> some View {
        content
            .background(AppColors.surface.opacity(0.97), in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(AppColors.control, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

extension View {
    /// Schwebende Kapsel (Feed-Kopf, Richtungs-Pille, Später-Pille, Editor-Kapseln).
    func glassCapsule(interactive: Bool = false, tint: Color? = nil, overMedia: Bool = false) -> some View {
        modifier(GlassCapsuleModifier(interactive: interactive, tint: tint, overMedia: overMedia))
    }

    /// Schwebende Fläche mit runden Ecken (Werkzeugzone im Editor, Später-Auswahl über dem Medium).
    func glassPanel(radius: CGFloat = AppRadii.card, interactive: Bool = false) -> some View {
        modifier(GlassRectModifier(radius: radius, interactive: interactive))
    }
}

/// Runder Knopf (44 pt) wie im Artefakt: dunkle Fläche, feiner Rand. Trefferfläche 48 pt.
struct GlassIconButton: View {
    let symbol: String
    let label: String
    var prominent = false
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(prominent ? AppColors.onAccent : (tint ?? AppColors.textPrimary))
                .frame(width: 44, height: 44)
                .background(prominent ? AppColors.accentFill : AppColors.surface, in: .circle)
                .overlay(Circle().strokeBorder(prominent ? Color.clear : AppColors.control, lineWidth: 1))
                .frame(width: AppSpacing.touch, height: AppSpacing.touch)
                .contentShape(.circle)
        }
        .buttonStyle(PMPressStyle())
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// Frühere Glas-Knopfstile: jetzt die Artefakt-Stile.
struct GlassButtonStyleModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if prominent { content.buttonStyle(.pmProminent) } else { content.buttonStyle(.pmBordered) }
    }
}

/// Gefüllter Knopf in der aktuellen Tönung (Standard: Bernstein) mit dunkler Schrift.
struct PMProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PMFont.text(.bold, 16, relativeTo: .headline))
            .foregroundStyle(AppColors.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(minHeight: AppSpacing.minTouch)
            .background(.tint, in: .rect(cornerRadius: 16))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .contentShape(.rect(cornerRadius: 16))
    }
}

/// Umrandeter Knopf: dunkle Fläche, Rand #2F2B28, helle Schrift.
struct PMBorderedButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PMFont.text(.semibold, 15, relativeTo: .subheadline))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: AppSpacing.minTouch)
            .background(AppColors.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(AppColors.control, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(.capsule)
    }
}

/// Nur Druck-Rückmeldung (Inhalt gestaltet sich selbst).
struct PMPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(AppMotion.open(reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PMProminentButtonStyle {
    static var pmProminent: PMProminentButtonStyle { PMProminentButtonStyle() }
}

extension ButtonStyle where Self == PMBorderedButtonStyle {
    static var pmBordered: PMBorderedButtonStyle { PMBorderedButtonStyle() }
}

/// Hauptaktion wie im Artefakt: 56 pt hoch, Radius 18, Bernstein (Löschen: Orange), dunkle Schrift 17/700.
struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var role: ButtonRole?
    var overMedia = false
    var trailingArrow = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 10) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(verbatim: title).multilineTextAlignment(.center)
                if trailingArrow {
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .bold)).accessibilityHidden(true)
                }
            }
            .font(AppTypography.button)
            .foregroundStyle(role == .destructive ? AppColors.onCleanup : AppColors.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(role == .destructive ? AppColors.cleanupFill : AppColors.accentFill,
                        in: .rect(cornerRadius: AppRadii.button))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.rect(cornerRadius: AppRadii.button))
        }
        .buttonStyle(PMPressStyle())
    }
}

/// Zweite Aktion: umrandet, 52 pt, Radius 16.
struct SecondaryButton: View {
    let title: String
    var symbol: String?
    var overMedia = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(verbatim: title).multilineTextAlignment(.center)
            }
            .font(PMFont.text(.semibold, 16, relativeTo: .headline))
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(overMedia ? AppColors.surface : Color.clear, in: .rect(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppColors.control, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(PMPressStyle())
    }
}
