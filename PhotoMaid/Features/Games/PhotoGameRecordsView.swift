import PhotoMaidCore
import SwiftUI

struct PhotoGameRecordsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(L("memory_title")) {
                    if app.gameScores.records.memory.isEmpty { Text(key: "game_no_best").foregroundStyle(AppColors.textSecondary) }
                    ForEach(app.gameScores.records.memory.reversed(), id: \.category) { record in
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(verbatim: L("memory_pair_option", record.category.pairs, record.category.pairs * 2)).font(AppTypography.headline)
                            Text(verbatim: [L(record.category.usesPhotos ? "game_record_photos" : "game_record_symbols"),
                                            L(record.category.manualMismatch ? "game_memory_manual" : "game_standard")].joined(separator: " · "))
                                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                            Text(verbatim: L("game_best_time", DateText.gameDuration(record.seconds))).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section(L("snake_title")) {
                    if app.gameScores.records.snake.isEmpty { Text(key: "game_no_best").foregroundStyle(AppColors.textSecondary) }
                    ForEach(app.gameScores.records.snake.reversed(), id: \.category) { record in
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(key: record.category.mode == .classic ? "snake_classic" : "snake_relaxed").font(AppTypography.headline)
                            Text(verbatim: speedTitle(record.category.speed) + " · " +
                                 L(record.category.stepMode ? "snake_step_mode" : "game_realtime"))
                                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                            Text(verbatim: L("game_best_eaten", record.eaten)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section { Text(key: "game_records_local").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary) }
                PhotoGameRecordSaveStatus()
            }
            .appPage()
            .navigationTitle(L("game_records_title"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("close")) { dismiss() } } }
        }
    }

    private func speedTitle(_ speed: PhotoSnakeSpeed) -> String {
        switch speed {
        case .gentle: L("snake_gentle")
        case .normal: L("snake_normal")
        case .fast: L("snake_fast")
        }
    }
}

struct PhotoGameRecordSaveStatus: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if app.gameScores.saveFailed {
            InfoBanner(symbol: "exclamationmark.triangle", tint: AppColors.warning,
                       text: L("game_records_save_failed"), actionTitle: L("retry")) { app.gameScores.retrySave() }
        }
    }
}
