import SwiftUI

// Liquid Glass – nur öffentliche iOS-26-APIs (`glassEffect`, `GlassEffectContainer`, `.glass`/`.glassProminent`).
// Glas nur für Navigation und schwebende Bedienelemente über Medien; Listen und Fotos bleiben ohne Glas.
// Reduce Transparency/Increase Contrast setzt das System selbst um; zusätzlich deckender Ersatz bei Reduce Transparency.

struct GlassCapsuleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var interactive = false
    var tint: Color?
    var overMedia = false

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(overMedia ? AppColors.stage : AppColors.surface, in: .capsule)
                .overlay(Capsule().strokeBorder(AppColors.surfaceStroke))
        } else {
            content.glassEffect(glass, in: .capsule)
        }
    }

    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        return interactive ? g.interactive() : g
    }
}

struct GlassRectModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var radius: CGFloat = AppRadii.card
    var interactive = false

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(AppColors.surface, in: .rect(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(AppColors.surfaceStroke))
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: radius))
        }
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

/// Runder Glas-Button für Kopfzeilen über Medien (Schließen, Rückgängig, Mehr). Trefferfläche 48 pt.
struct GlassIconButton: View {
    let symbol: String
    let label: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: AppSpacing.touch, height: AppSpacing.touch)
                .contentShape(.circle)
        }
        .modifier(GlassButtonStyleModifier(prominent: prominent))
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(verbatim: label))
    }
}

struct GlassButtonStyleModifier: ViewModifier {
    let prominent: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        } else {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        }
    }
}

/// Hauptaktion auf ruhigem Grund (Listen, Karten): deckend, klar lesbar. Über Medien: `.glassProminent`.
struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var role: ButtonRole?
    var overMedia = false
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: AppSpacing.xs) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(verbatim: title).multilineTextAlignment(.center)
            }
            .font(AppTypography.headline)
            .frame(maxWidth: .infinity, minHeight: AppSpacing.touch)
        }
        .modifier(PrimaryStyle(overMedia: overMedia, destructive: role == .destructive))
    }

    private struct PrimaryStyle: ViewModifier {
        let overMedia: Bool
        let destructive: Bool
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast

        func body(content: Content) -> some View {
            if overMedia && !reduceTransparency && contrast != .increased {
                content.buttonStyle(.glassProminent).tint(destructive ? AppColors.cleanup : AppColors.accentFill)
            } else {
                content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .tint(destructive ? AppColors.cleanup : AppColors.accentFill)
            }
        }
    }
}

struct SecondaryButton: View {
    let title: String
    var symbol: String?
    var overMedia = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(verbatim: title).multilineTextAlignment(.center)
            }
            .font(AppTypography.headline)
            .frame(maxWidth: .infinity, minHeight: AppSpacing.touch)
        }
        .modifier(SecondaryStyle(overMedia: overMedia))
    }

    private struct SecondaryStyle: ViewModifier {
        let overMedia: Bool
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
        @Environment(\.colorSchemeContrast) private var contrast

        func body(content: Content) -> some View {
            if overMedia && !reduceTransparency && contrast != .increased {
                content.buttonStyle(.glass)
            } else {
                content.buttonStyle(.bordered).buttonBorderShape(.capsule)
            }
        }
    }
}
