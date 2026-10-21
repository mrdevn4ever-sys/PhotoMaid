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
            PhotoBlocksView(onChooseGame: { selected = nil })
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
                            PhotoGameTile(art: .memory, title: L("memory_title"),
                                          subtitle: L(app.memory.game?.isFinished == false ? "memory_resume" : "games_memory_description"))
                        }
                        .buttonStyle(PMPressStyle()).accessibilityIdentifier("games.memory")
                        Button { selected = .snake } label: {
                            PhotoGameTile(art: .snake, title: L("snake_title"),
                                          subtitle: L(app.snake.game?.status == .playing ? "memory_resume" : "game_setup_snake_intro"))
                        }
                        .buttonStyle(PMPressStyle()).accessibilityIdentifier("games.snake")
                        Button { selected = .blocks } label: {
                            PhotoGameTile(art: .blocks, title: L("blocks_title"), subtitle: L("blocks_subtitle"))
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

/// Spielkarte wie im Artefakt: violette Fläche, 84-pt-Bild, Titel 22 (Bricolage 700), Untertitel 14.
private struct PhotoGameTile: View {
    enum Art { case memory, snake, blocks }
    let art: Art
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            artwork.frame(width: 84, height: 84).accessibilityHidden(true)
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

    @ViewBuilder private var artwork: some View {
        switch art {
        case .memory:
            let open = AppColors.keep
            let closed = AppColors.pauseStroke
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    RoundedRectangle(cornerRadius: 10).fill(open)
                    RoundedRectangle(cornerRadius: 10).fill(closed)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppColors.pauseLine, lineWidth: 1))
                }
                GridRow {
                    RoundedRectangle(cornerRadius: 10).fill(closed)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppColors.pauseLine, lineWidth: 1))
                    RoundedRectangle(cornerRadius: 10).fill(open)
                }
            }
        case .snake:
            Canvas { ctx, size in
                let s = size.width / 84
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16 * s), with: .color(AppColors.pauseStroke))
                let dots: [(CGFloat, CGFloat, CGFloat, Color)] = [(22, 58, 9, AppColors.success), (34, 50, 9, AppColors.keep),
                                                                  (46, 42, 9, AppColors.accent), (58, 34, 10, AppColors.cleanup)]
                for (x, y, r, c) in dots {
                    let rect = CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)
                    ctx.fill(Path(ellipseIn: rect), with: .color(c))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(AppColors.textPrimary), lineWidth: 1.5 * s)
                }
                ctx.fill(Path(roundedRect: CGRect(x: 58 * s, y: 58 * s, width: 12 * s, height: 12 * s), cornerRadius: 6 * s),
                         with: .color(AppColors.later))
            }
        case .blocks:
            Canvas { ctx, size in
                let s = size.width / 84
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16 * s), with: .color(AppColors.pauseStroke))
                let blocks: [(CGFloat, CGFloat, Color)] = [(14, 52, AppColors.cleanup), (33, 52, AppColors.accent),
                                                          (52, 52, AppColors.keep), (33, 33, AppColors.later), (52, 14, AppColors.success)]
                for (x, y, c) in blocks {
                    ctx.fill(Path(roundedRect: CGRect(x: x * s, y: y * s, width: 18 * s, height: 18 * s), cornerRadius: 4 * s),
                             with: .color(c))
                }
            }
        }
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
