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
        default: app.settings.appearance.colorScheme
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
                    VStack(spacing: AppSpacing.m) {
                        PhotoGameAnalysisStatus(onResults: onResults)
                        PhotoGameRecordSaveStatus()
                        Button { selected = .memory } label: {
                            PhotoGameTile(symbol: "rectangle.on.rectangle", title: L("memory_title"),
                                          subtitle: L(app.memory.game?.isFinished == false ? "memory_resume" : "games_memory_description"), snake: false)
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("games.memory")
                        Button { selected = .snake } label: {
                            PhotoGameTile(symbol: "", title: L("snake_title"),
                                          subtitle: L(app.snake.game?.status == .playing ? "memory_resume" : "game_setup_snake_intro"), snake: true)
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("games.snake")
                        Button { selected = .blocks } label: {
                            SurfaceCard(padding: AppSpacing.l) {
                                VStack(alignment: .leading, spacing: AppSpacing.m) {
                                    Label(L("blocks_title"), systemImage: "square.stack.3d.up.fill")
                                        .font(AppTypography.title).foregroundStyle(AppColors.accent)
                                    Text(key: "blocks_subtitle").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("games.blocks")
                    }
                    .padding(AppSpacing.pageMargin)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
                .appPage()
                .navigationTitle(L("memory_break"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("close")) { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showRecords = true } label: { Label(L("game_records_title"), systemImage: "trophy") }
                            .accessibilityIdentifier("games.records")
                    }
                }
                .sheet(isPresented: $showRecords) { PhotoGameRecordsView().environment(app) }
            }
        }
    }
}

private struct PhotoGameTile: View {
    @Environment(AppModel.self) private var app
    let symbol: String
    let title: String
    let subtitle: String
    let snake: Bool

    var body: some View {
        SurfaceCard(padding: AppSpacing.l) {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(0..<4) { index in
                        Group {
                            if snake {
                                if index == 0 {
                                    Image(uiImage: SnakeArt.headImage(app.snake.preferences.character)).resizable().scaledToFit()
                                } else {
                                    Image(systemName: "photo").resizable().scaledToFit().padding(8)
                                }
                            } else { Image(systemName: index == 0 ? symbol : PhotoMemoryModel.motifs[index]) }
                        }
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(index == 0 ? .white : AppColors.accent)
                            .frame(width: 44, height: 48)
                            .background(index == 0 ? AppColors.accentFill : AppColors.warm, in: .rect(cornerRadius: 10))
                            .offset(y: snake && index.isMultiple(of: 2) ? -5 : 0)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.forward").foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityHidden(true)
                Text(verbatim: title).font(AppTypography.title).foregroundStyle(AppColors.textPrimary)
                Text(verbatim: subtitle).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
