import SwiftUI

/// Gemeinsame Hierarchie für Start- und Werkzeugbereiche, ohne eigene Navigation zu besitzen.
struct FeatureHeader: View {
    let title: String
    var subtitle: String?
    let settings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: title)
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            GlassIconButton(symbol: "gearshape", label: L("settings"), action: settings)
                .accessibilityIdentifier("feature.settings")
        }
        .padding(.top, AppSpacing.m)
    }
}

/// Echte Aktion mit klarer Hierarchie; Inhalt bleibt deckend, Glas ist keine Inhaltsdekoration.
struct FeatureActionTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    var value: String?
    var tint: Color = AppColors.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Image(systemName: symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    if let value {
                        Text(verbatim: value)
                            .font(AppTypography.metric)
                            .foregroundStyle(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(verbatim: title)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: subtitle)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            }
            .contentShape(.rect(cornerRadius: AppRadii.card))
        }
        .buttonStyle(FeaturePressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Kurze Klickrückmeldung, ohne Inhalte bei Reduce Motion zu bewegen.
struct FeaturePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(AppMotion.open(reduceMotion), value: configuration.isPressed)
    }
}
