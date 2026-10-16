import SwiftUI

/// One modal pause for both games, keeping the underlying feed suspended until the pause is closed.
struct PhotoGamesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onResults: (SmartReviewKind) -> Void
    @State private var session = PhotoGameSession()
    @State private var selected: Game?
    @State private var showRecords = false
    private enum Game { case memory, snake }

    var body: some View {
        content.environment(session)
    }

    @ViewBuilder private var content: some View {
        switch selected {
        case .memory:
            PhotoMemoryView(onResults: onResults, onChooseGame: { selected = nil })
        case .snake:
            PhotoSnakeView(onResults: onResults, onChooseGame: { selected = nil })
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
                            PhotoGameTile(symbol: "camera.fill", title: L("snake_title"),
                                          subtitle: L(app.snake.game?.status == .playing ? "memory_resume" : "snake_intro"), snake: true)
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("games.snake")
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
    let symbol: String
    let title: String
    let subtitle: String
    let snake: Bool

    var body: some View {
        SurfaceCard(padding: AppSpacing.l) {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(0..<4) { index in
                        Image(systemName: index == 0 ? symbol : PhotoMemoryModel.motifs[index])
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
