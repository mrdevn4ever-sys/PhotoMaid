import SwiftUI

// Einheitlicher Rahmen der drei Spiele (Nutzer, 22.10.2026: „Können wir das Design vereinheitlichen“): wie Paare und die
// übrige App – App-Grund, Bernstein-Akzent, App-Schrift, Karten und Knöpfe aus dem Design-System, gleiche Kopfzeile und
// gleiche Beschriftungen. Nur das eigentliche Spielfeld (Paare-Karten, Snake-Wiese, Blocks-Raster mit Foto) behält
// sein eigenes Aussehen.

/// Breiter Spielknopf (Starten, Fortsetzen, Fotos ändern …). `prominent` = Bernstein, sonst Fläche mit Rand.
/// Farben fest aus dem Design-System, unabhängig vom Tint des Spiels.
struct GameButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PMFont.text(.bold, 16, relativeTo: .headline))
            .multilineTextAlignment(.center)
            .foregroundStyle(prominent ? AppColors.onAccent : AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: AppSpacing.minTouch)
            .padding(.horizontal, 18)
            .padding(.vertical, prominent ? 13 : 10)
            .background(prominent ? AppColors.accent : AppColors.surface, in: .rect(cornerRadius: 16))
            .overlay {
                if !prominent { RoundedRectangle(cornerRadius: 16).strokeBorder(AppColors.control, lineWidth: 1) }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .contentShape(.rect(cornerRadius: 16))
    }
}

/// Oben auf der Startseite: laufende Spielszene (zeigt, wie gespielt wird), ein Satz und – falls vorhanden – der Rekord.
struct GameIntro: View {
    let showcase: GameShowcase.Kind
    let text: String
    var best: String?
    var bestIdentifier = "game.best"
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 14) {
            GameShowcase(kind: showcase)
                .frame(height: typeSize.isAccessibilitySize ? 136 : 184)
                .frame(maxWidth: .infinity)
            Text(verbatim: text)
                .font(PMFont.heading(20, relativeTo: .title3)).foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let best {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill").accessibilityHidden(true)
                    Text(verbatim: best).monospacedDigit().accessibilityIdentifier(bestIdentifier)
                }
                .font(AppTypography.subheadline.weight(.semibold)).foregroundStyle(AppColors.accent)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(AppColors.accent.opacity(0.14), in: .capsule)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Fenster über dem Spielfeld (Pause, Rundenende): App-Fläche mit Rand; passt es nicht, wird es scrollbar.
struct GamePanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 12) { content }.padding(22).fixedSize(horizontal: false, vertical: true)
            ScrollView { VStack(spacing: 12) { content }.padding(22) }
        }
        .gamePanelStyle()
    }
}

extension View {
    /// Fläche eines Spielfensters (für Fenster, die selbst entscheiden, wann sie scrollen).
    func gamePanelStyle() -> some View {
        foregroundStyle(AppColors.textPrimary)
            .background(AppColors.surface, in: .rect(cornerRadius: AppRadii.sheet))
            .overlay(RoundedRectangle(cornerRadius: AppRadii.sheet).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }

    /// Gleiche Kopfzeile in allen Spielen: „Schließen“ links, Spielname in der Mitte, „Andere Spiele“ rechts.
    func gameToolbar(title: String, closeID: String, otherGamesID: String,
                     close: @escaping () -> Void, otherGames: (() -> Void)?) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("close"), action: close).accessibilityIdentifier(closeID)
                }
                if let otherGames {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("snake_other_games"), action: otherGames).accessibilityIdentifier(otherGamesID)
                    }
                }
            }
    }
}
