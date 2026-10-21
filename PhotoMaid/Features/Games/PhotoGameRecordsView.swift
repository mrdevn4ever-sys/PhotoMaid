import PhotoMaidCore
import SwiftUI

/// Bestwerte (Gamification, Nutzerentscheidung 21.10.2026): ein Rekord je Spiel – nur Paare behält Bestzeiten je
/// Rundengröße und Regel. Keine Feldgrößen. Medaillen messen nur eigene Werte.
struct PhotoGameRecordsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var filter = 0

    private enum Game: Int, CaseIterable { case all, pairs, snake, blocks }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    HStack {
                        GlassIconButton(symbol: "xmark", label: L("close")) { dismiss() }
                            .accessibilityIdentifier("games.records.close")
                        Spacer()
                        if app.settings.showAchievements {
                            NavigationLink { AchievementsView() } label: {
                                HStack(spacing: 6) {
                                    PMIcon(.medal, size: 15).foregroundStyle(AppColors.accent)
                                    Text(key: "rec_all_achievements")
                                }
                                .font(PMFont.text(.semibold, 13, relativeTo: .footnote)).foregroundStyle(AppColors.textPrimary)
                                .padding(.horizontal, 14).frame(minHeight: 36)
                                .background(AppColors.surface, in: .capsule)
                                .overlay(Capsule().strokeBorder(AppColors.control, lineWidth: 1))
                                .frame(minHeight: AppSpacing.minTouch).contentShape(.rect)
                            }
                            .buttonStyle(PMPressStyle())
                            .accessibilityIdentifier("games.records.achievements")
                        }
                    }
                    PageHeading(title: L("game_records_title"), subtitle: L("rec_sub"))
                    if let latest = app.achievements.latestRecord { latestCard(latest.key, latest.stamp) }
                    chips
                    if filter == Game.all.rawValue || filter == Game.pairs.rawValue { pairsCard }
                    if filter == Game.all.rawValue || filter == Game.snake.rawValue { snakeCard }
                    if filter == Game.all.rawValue || filter == Game.blocks.rawValue { blocksCard }
                    Text(key: "rec_note").font(AppTypography.footnote).foregroundStyle(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
                    PhotoGameRecordSaveStatus()
                }
                .padding(.horizontal, AppSpacing.pageMargin)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.xxl)
            }
            .appPage()
            .navigationTitle(L("game_records_title"))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { app.achievements.refresh(app: app) }
        }
    }

    // MARK: Teile

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(Game.allCases, id: \.rawValue) { g in
                    PMChip(title: title(g), selected: filter == g.rawValue) { filter = g.rawValue }
                }
            }
        }
    }

    private func title(_ g: Game) -> String {
        switch g {
        case .all: L("history_all")
        case .pairs: L("memory_title")
        case .snake: L("snake_title")
        case .blocks: L("blocks_title")
        }
    }

    /// „Zuletzt geknackt“: jüngster Bestwert mit bekanntem Datum.
    private func latestCard(_ key: String, _ stamp: GameRecordStamp) -> some View {
        let (game, value) = describe(key, stamp.value)
        return HStack(spacing: 14) {
            PMIcon(.trophy, size: 28)
                .foregroundStyle(AppColors.onAccent)
                .frame(width: 56, height: 56)
                .background(AppColors.accentFill, in: .circle)
                .shadow(color: AppColors.accent.opacity(0.35), radius: 9, y: 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(key: "rec_latest").textCase(.uppercase).font(PMFont.text(.bold, 12, relativeTo: .caption))
                    .tracking(0.96).foregroundStyle(AppColors.accent)
                Text(verbatim: value).font(PMFont.display(26, relativeTo: .title)).foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(verbatim: game + (stamp.at.map { " · " + L("ach_earned_on", DateText.abbreviated($0)) } ?? ""))
                    .font(AppTypography.footnote).foregroundStyle(AppColors.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(AppColors.warm, in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(AppColors.warmStrong, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func describe(_ key: String, _ value: Double) -> (game: String, value: String) {
        if key == "snake" { return (L("snake_title"), LP("rec_value_photos", Int(value), CountText.number(Int(value)))) }
        if key == "blocks" { return (L("blocks_title"), LP("rec_value_points", Int(value), CountText.number(Int(value)))) }
        return (L("memory_title"), DateText.gameDuration(value))
    }

    private func card<Content: View>(_ icon: PMIconName, _ tint: Color, _ title: String, trailing: String?,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.s) {
                PMIcon(icon, size: 19).foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(PMTile.background(for: tint), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                Text(verbatim: title).font(AppTypography.title3).foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let trailing { Text(verbatim: trailing).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            content()
        }
        .background(AppColors.surface, in: .rect(cornerRadius: 22))
        .clipShape(.rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
    }

    private func row<Leading: View>(medal: GameMedal, value: String, @ViewBuilder leading: () -> Leading) -> some View {
        HStack(spacing: AppSpacing.s) {
            leading()
            Spacer(minLength: 0)
            MedalIcon(medal: medal)
            Text(verbatim: value).font(PMFont.heading(21, relativeTo: .title3)).monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(AppColors.surfaceStroke).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private func emptyRow() -> some View {
        Text(key: "game_no_best").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(AppColors.surfaceStroke).frame(height: 1) }
    }

    private func dateLine(_ key: String) -> String? {
        app.achievements.recordStamps[key]?.at.map { L("ach_earned_on", DateText.abbreviated($0)) }
    }

    private var pairsCard: some View {
        let records = app.gameScores.records.memory.sorted {
            ($0.category.pairs, $0.category.manualMismatch ? 1 : 0) < ($1.category.pairs, $1.category.manualMismatch ? 1 : 0)
        }
        return card(.cards, AppColors.later, L("memory_title"),
                    trailing: records.isEmpty ? nil : LP("rec_best_times", records.count)) {
            if records.isEmpty { emptyRow() }
            ForEach(records, id: \.category) { r in
                row(medal: GameMedal.pairs(seconds: r.seconds, pairs: r.category.pairs),
                    value: DateText.gameDuration(r.seconds)) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: L("memory_pair_option", r.category.pairs, r.category.pairs * 2))
                            .font(PMFont.text(.semibold, 15, relativeTo: .subheadline)).foregroundStyle(AppColors.textPrimary)
                        Text(verbatim: [L(r.category.usesPhotos ? "game_record_photos" : "game_record_symbols"),
                                        L(r.category.manualMismatch ? "game_memory_manual" : "game_standard")]
                                .joined(separator: " · ") + (dateLine(AchievementCenter.memoryKey(r.category)).map { " · " + $0 } ?? ""))
                            .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityIdentifier("games.records.pairs")
    }

    private var snakeCard: some View {
        let best = app.gameScores.records.snakeOverallBest
        return card(.snake, AppColors.success, L("snake_title"), trailing: nil) {
            if let best {
                row(medal: GameMedal.snake(best), value: CountText.number(best)) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(key: "rec_record").font(PMFont.text(.semibold, 15, relativeTo: .subheadline))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(verbatim: L("rec_unit_photos") + (dateLine("snake").map { " · " + $0 } ?? ""))
                            .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                    }
                }
                nextMedal(best, steps: GameMedal.snakeSteps)
            } else {
                emptyRow()
            }
        }
        .accessibilityIdentifier("games.records.snake")
    }

    private var blocksCard: some View {
        let best = app.blocks.best
        return card(.blocks, AppColors.accent, L("blocks_title"), trailing: nil) {
            if best > 0 {
                row(medal: GameMedal.blocks(best), value: CountText.number(best)) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(key: "rec_record").font(PMFont.text(.semibold, 15, relativeTo: .subheadline))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(verbatim: L("rec_unit_points") + (dateLine("blocks").map { " · " + $0 } ?? ""))
                            .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                    }
                }
                nextMedal(best, steps: GameMedal.blocksSteps)
            } else {
                emptyRow()
            }
            if app.blocks.saveFailed {
                Button(L("blocks_save_retry")) { app.blocks.checkpoint() }
                    .buttonStyle(.pmBordered).padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .accessibilityIdentifier("games.records.blocks")
    }

    /// Fortschritt zur nächsten eigenen Medaille (Balken), bei Gold nichts.
    @ViewBuilder
    private func nextMedal(_ value: Int, steps: [Int]) -> some View {
        if let next = GameMedal.next(after: value, steps: steps) {
            let previous = steps.last { $0 <= value } ?? 0
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColors.surfaceStroke)
                        Capsule().fill(AppColors.accentFill)
                            .frame(width: geo.size.width * min(1, Double(value - previous) / Double(max(1, next.at - previous))))
                    }
                }
                .frame(height: 8)
                Text(verbatim: L("rec_medal_next", MedalIcon.name(next.medal), CountText.number(next.at),
                                 CountText.number(next.at - value)))
                    .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Medaille als kleines Symbol in Gold, Silber oder Bronze (ohne Medaille gedämpft).
struct MedalIcon: View {
    let medal: GameMedal

    var body: some View {
        PMIcon(.medal, size: 18)
            .foregroundStyle(color)
            .accessibilityLabel(Text(verbatim: Self.name(medal)))
            .accessibilityHidden(medal == .none)
    }

    private var color: Color {
        switch medal {
        case .gold: AppColors.accentFill
        case .silver: AppColors.hex(0xC9C4BC)
        case .bronze: AppColors.hex(0xC98A5A)
        case .none: AppColors.disabled
        }
    }

    static func name(_ medal: GameMedal) -> String {
        switch medal {
        case .gold: L("rec_medal_gold")
        case .silver: L("rec_medal_silver")
        case .bronze: L("rec_medal_bronze")
        case .none: ""
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
