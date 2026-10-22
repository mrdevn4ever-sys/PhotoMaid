import SwiftUI

/// One modal pause for both games, keeping the underlying feed suspended until the pause is closed.
struct PhotoGamesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onResults: (SmartReviewKind) -> Void
    @State private var session = PhotoGameSession()
    @State private var selected: Game?
    @State private var showRecords = false
    private enum Game { case memory, snake, blocks }

    var body: some View {
        content.environment(session)
            .preferredColorScheme(gameAppearance)
            // Bernstein-Akzent für alle Spiele, auch wenn das Fenster aus dem Feed kommt (dort erbte Paare sonst Blau).
            .tint(AppColors.accent)
    }

    /// One owner for the modal's system appearance, including returning from the dark Snake scene.
    private var gameAppearance: ColorScheme? {
        switch selected {
        case .snake, .blocks: .dark
        default: .dark
        }
    }

    @ViewBuilder private var content: some View {
        switch selected {
        case .memory:
            PhotoMemoryView(onResults: onResults, onChooseGame: { selected = nil })
        case .snake:
            PhotoSnakeView(onResults: onResults, onChooseGame: { selected = nil }, onClose: { dismiss() })
        case .blocks:
            PhotoBlocksView(onChooseGame: { selected = nil }, onClose: { dismiss() })
        case nil:
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.m) {
                        HStack {
                            Button { dismiss() } label: {
                                HStack(spacing: 4) {
                                    PMIcon(.chevronLeft, size: 20, lineWidth: 2.2).flipsForRightToLeftLayoutDirection(true)
                                    Text(key: "back").font(PMFont.text(.semibold, 16, relativeTo: .headline))
                                }
                                .foregroundStyle(AppColors.later)
                                .frame(minHeight: AppSpacing.minTouch)
                                .contentShape(.rect)
                            }
                            .buttonStyle(PMPressStyle())
                            .accessibilityIdentifier("games.close")
                            Spacer()
                            Button { showRecords = true } label: {
                                Image(systemName: "trophy").font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.later)
                                    .frame(width: 44, height: 44)
                                    .background(AppColors.pauseSurface, in: .circle)
                                    .overlay(Circle().strokeBorder(AppColors.pauseStroke, lineWidth: 1))
                            }
                            .buttonStyle(PMPressStyle())
                            .accessibilityLabel(Text(key: "game_records_title"))
                            .accessibilityIdentifier("games.records")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key: "memory_break").pageTitle().accessibilityAddTraits(.isHeader)
                            Text(key: "art_pause_intro").font(AppTypography.subheadline).foregroundStyle(AppColors.pauseText)
                        }
                        PhotoGameAnalysisStatus(onResults: onResults)
                        PhotoGameRecordSaveStatus()
                        Button { selected = .memory } label: {
                            PhotoGameTile(showcase: .pairs, title: L("memory_title"),
                                          subtitle: L(app.memory.game?.isFinished == false ? "memory_resume" : "games_memory_description"))
                        }
                        .buttonStyle(PMPressStyle()).accessibilityIdentifier("games.memory")
                        Button { selected = .snake } label: {
                            PhotoGameTile(showcase: .snake(app.snake.preferences.character, night: app.snake.preferences.night),
                                          title: L("snake_title"),
                                          subtitle: L(app.snake.game?.status == .playing ? "memory_resume" : "game_setup_snake_intro"))
                        }
                        .buttonStyle(PMPressStyle()).accessibilityIdentifier("games.snake")
                        Button { selected = .blocks } label: {
                            PhotoGameTile(showcase: .blocks, title: L("blocks_title"), subtitle: L("blocks_subtitle"))
                        }
                        .buttonStyle(PMPressStyle()).accessibilityIdentifier("games.blocks")
                    }
                    .padding(.horizontal, AppSpacing.pageMargin)
                    .padding(.vertical, AppSpacing.s)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
                .scrollContentBackground(.hidden)
                .background(AppColors.pauseGround.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showRecords) { PhotoGameRecordsView().environment(app) }
            }
        }
    }
}

/// Spielkarte wie im Artefakt: violette Fläche, 84-pt-Bild aus der Spielszene, Titel 22 (Bricolage 700), Untertitel 14.
/// Ein festes Bild genügt hier, damit klar ist, worum es geht; die Szene läuft auf der Startseite des Spiels.
private struct PhotoGameTile: View {
    let showcase: GameShowcase.Kind
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            GameShowcase(kind: showcase, compact: true, animated: false).frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title).font(AppTypography.title).foregroundStyle(AppColors.textPrimary)
                Text(verbatim: subtitle).font(PMFont.text(.regular, 14, relativeTo: .subheadline))
                    .foregroundStyle(AppColors.pauseText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.pauseSurface, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(AppColors.pauseStroke, lineWidth: 1))
        .contentShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// „Kurze Pause“ als Vollbild (Start, Studio): wie aus dem Feed; Analyse-Ergebnisse öffnen „Aufräumen“.
    func gamesCover(isPresented: Binding<Bool>) -> some View {
        modifier(GamesCoverModifier(isPresented: isPresented))
    }
}

private struct GamesCoverModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var isPresented: Bool
    @State private var results: SmartReviewKind?

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented, onDismiss: {
            if let kind = results {
                results = nil
                app.navigate(.smartReview(kind), in: .cleanup)
            }
        }) {
            PhotoGamesView { results = $0 }.environment(app)
        }
    }
}
