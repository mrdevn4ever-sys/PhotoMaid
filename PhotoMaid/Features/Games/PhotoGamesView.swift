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
                            NavRow(symbol: "rectangle.on.rectangle", title: L("memory_title"),
                                   subtitle: L(app.memory.game == nil ? "games_memory_description" : "memory_resume"))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("games.memory")
                        Button { selected = .snake } label: {
                            NavRow(symbol: "camera.fill", title: L("snake_title"),
                                   subtitle: L(app.snake.game?.status == .playing ? "memory_resume" : "snake_intro"))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("games.snake")
                    }
                    .padding(AppSpacing.pageMargin)
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
