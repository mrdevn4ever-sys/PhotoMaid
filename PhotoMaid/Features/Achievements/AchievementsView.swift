import PhotoMaidCore
import SwiftUI

/// Erfolge (Gamification, Nutzerentscheidung 21.10.2026): Level fürs Durchsehen, Serie mit Pausentag, Tagesziel,
/// diese Woche, Abzeichen und fertige Monate. Nur eigene, echte Zahlen; alles bleibt auf dem Gerät.
struct AchievementsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let progress = app.read.progress
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                PageHeading(title: L("ach_title"), subtitle: L("ach_sub"))
                levelCard(progress.level)
                HStack(alignment: .top, spacing: AppSpacing.s) {
                    streakCard(progress)
                    goalCard(progress)
                }
                WeekBars(progress: progress)
                HStack(alignment: .firstTextBaseline) {
                    Text(key: "ach_badges").font(AppTypography.title3).foregroundStyle(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(verbatim: L("ach_badges_count", app.achievements.earnedCount, AchievementID.allCases.count))
                        .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, 4).padding(.horizontal, 4)
                ForEach(AchievementGroup.allCases, id: \.self) { group in
                    badgeGroup(group)
                }
                monthsCard
                Text(key: "ach_local_note").font(AppTypography.footnote).foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .appPage()
        .navigationTitle(L("ach_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        .onAppear { app.achievements.refresh(app: app) }
        .accessibilityIdentifier("achievements.page")
    }

    // MARK: Karten

    private func levelCard(_ level: ReviewLevel) -> some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(AppColors.surfaceStroke, lineWidth: 10)
                Circle().trim(from: 0, to: level.fraction)
                    .stroke(AppColors.accentFill, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(key: "ach_level").textCase(.uppercase).font(PMFont.text(.bold, 11, relativeTo: .caption2))
                        .tracking(0.9).foregroundStyle(AppColors.textSecondary)
                    Text(verbatim: CountText.number(level.number)).font(PMFont.display(32, relativeTo: .title))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .frame(width: 96, height: 96)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: CountText.number(level.total)).font(PMFont.display(28, relativeTo: .title))
                    .foregroundStyle(AppColors.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                Text(key: "ach_reviewed_label").font(PMFont.text(.regular, 14, relativeTo: .subheadline))
                    .foregroundStyle(AppColors.textMuted)
                Text(verbatim: (level.remaining.map { L("ach_level_next", CountText.number($0), level.number + 1) }
                                ?? L("ach_level_max")) + " " + L("ach_equal_note"))
                    .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(AppColors.surface, in: .rect(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: L("ach_level") + " " + String(level.number) + ", "
                                 + CountText.number(level.total) + " " + L("ach_reviewed_label")))
    }

    private func streakCard(_ p: ReviewProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PMIcon(.flame, size: 17).foregroundStyle(AppColors.cleanup)
                    .frame(width: 32, height: 32).background(AppColors.tileCleanup, in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text(key: "ach_streak").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: CountText.number(p.streak)).font(PMFont.display(28, relativeTo: .title))
                Text(verbatim: LP("ach_days_unit", p.streak))
                    .font(PMFont.text(.regular, 14, relativeTo: .subheadline)).foregroundStyle(AppColors.textMuted)
            }
            .foregroundStyle(AppColors.textPrimary)
            WeekDots(progress: p)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: L("ach_streak") + ": " + CountText.number(p.streak) + " " + LP("ach_days_unit", p.streak)))
    }

    private func goalCard(_ p: ReviewProgress) -> some View {
        let goal = app.settings.dailyGoal
        return VStack(alignment: .leading, spacing: 10) {
            Text(key: "ach_goal").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            if goal > 0 {
                ZStack {
                    Circle().stroke(AppColors.surfaceStroke, lineWidth: 8)
                    Circle().trim(from: 0, to: min(1, Double(p.reviewedToday) / Double(goal)))
                        .stroke(AppColors.success, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if p.reviewedToday >= goal {
                        PMIcon(.check, size: 24, lineWidth: 2.6).foregroundStyle(AppColors.success)
                    } else {
                        Text(verbatim: CountText.number(p.reviewedToday)).font(PMFont.heading(17, relativeTo: .headline))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .frame(width: 72, height: 72)
                Text(verbatim: p.reviewedToday >= goal ? L("ach_goal_done") : L("ach_goal_of", CountText.number(goal)))
                    .font(AppTypography.footnote).foregroundStyle(AppColors.textMuted)
            } else {
                Text(key: "ach_goal_off").font(AppTypography.footnote).foregroundStyle(AppColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func badgeGroup(_ group: AchievementGroup) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(verbatim: AchievementText.group(group)).font(PMFont.text(.semibold, 14, relativeTo: .subheadline))
                .foregroundStyle(AchievementText.tint(group)).padding(.horizontal, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(AchievementID.allCases.filter { $0.group == group }, id: \.self) { id in
                    BadgeCell(id: id, earned: app.achievements.isEarned(id), at: app.achievements.earnedAt(id),
                              state: app.achievements.states[id])
                }
            }
        }
    }

    private var monthsCard: some View {
        let done = app.read.monthsDone, total = app.read.monthsTotal
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(key: "ach_months").font(PMFont.heading(18, relativeTo: .headline)).foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(verbatim: L("ach_badges_count", done, total)).font(AppTypography.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.surfaceStroke)
                    Capsule().fill(AppColors.success)
                        .frame(width: total == 0 ? 0 : geo.size.width * Double(done) / Double(total))
                }
            }
            .frame(height: 8)
        }
        .padding(16)
        .background(AppColors.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Ein Abzeichen: farbig mit Häkchen, wenn erreicht (mit Datum), sonst gedämpft mit Schloss und Rest.
struct BadgeCell: View {
    let id: AchievementID
    let earned: Bool
    let at: Date?
    let state: AchievementState?

    var body: some View {
        let tint = AchievementText.tint(id.group)
        VStack(spacing: 8) {
            PMIcon(earned ? .check : .lock, size: earned ? 22 : 19, lineWidth: earned ? 2.4 : 2)
                .foregroundStyle(earned ? tint : AppColors.disabled)
                .frame(width: 48, height: 48)
                .background(earned ? PMTile.background(for: tint) : AppColors.background, in: .circle)
                .overlay(Circle().strokeBorder(earned ? tint : AppColors.surfaceStroke, lineWidth: 2))
                .accessibilityHidden(true)
            Text(verbatim: AchievementText.title(id)).font(PMFont.text(.semibold, 12, relativeTo: .caption))
                .foregroundStyle(earned ? AppColors.textPrimary : AppColors.textTertiary)
                .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.85)
            Text(verbatim: detail).font(PMFont.text(.regular, 11, relativeTo: .caption2))
                .foregroundStyle(AppColors.textTertiary).multilineTextAlignment(.center).lineLimit(2)
        }
        .padding(.vertical, 12).padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .top)
        .background(AppColors.surface, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(earned ? [.isSelected] : [])
        .accessibilityIdentifier("achievement." + id.rawValue)
    }

    private var detail: String {
        if earned { return at.map { L("ach_earned_on", DateText.abbreviated($0)) } ?? L("ach_earned") }
        if case .open(let remaining)? = state, let remaining, remaining > 0 { return L("ach_remaining", CountText.number(remaining)) }
        return AchievementText.condition(id)
    }
}

/// Sieben Punkte (Montag bis Sonntag) der laufenden Woche: aktiv, Pausentag oder offen.
struct WeekDots: View {
    let progress: ReviewProgress

    var body: some View {
        HStack(spacing: 4) {
            ForEach(progress.currentWeek, id: \.day) { entry in
                let active = entry.reviewed > 0
                let pause = progress.pauseDays.contains(entry.day)
                VStack(spacing: 4) {
                    Circle()
                        .fill(active ? AppColors.cleanup : Color.clear)
                        .overlay(Circle().strokeBorder(active ? AppColors.cleanup : (pause ? AppColors.textTertiary : AppColors.dashed),
                                                       style: StrokeStyle(lineWidth: 1.5, dash: pause ? [2, 2] : [])))
                        .frame(width: 14, height: 14)
                    Text(verbatim: AchievementText.weekdayInitial(entry.day))
                        .font(PMFont.text(.regular, 10, relativeTo: .caption2)).foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// „Diese Woche“: durchgesehen je Tag (Montag bis Sonntag), heute hervorgehoben.
struct WeekBars: View {
    let progress: ReviewProgress

    var body: some View {
        let week = progress.currentWeek
        let peak = max(1, week.map(\.reviewed).max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(key: "ach_week").font(PMFont.heading(18, relativeTo: .headline)).foregroundStyle(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(verbatim: L("ach_reviewed_n", CountText.number(week.map(\.reviewed).reduce(0, +))))
                    .font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(week, id: \.day) { entry in
                    let isToday = entry.day == progress.today
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isToday ? AppColors.accentFill : AppColors.warmStrong)
                            .frame(height: max(6, 80 * Double(entry.reviewed) / Double(peak)))
                        Text(verbatim: AchievementText.weekdayInitial(entry.day))
                            .font(PMFont.text(isToday ? .bold : .regular, 11, relativeTo: .caption2))
                            .foregroundStyle(isToday ? AppColors.textPrimary : AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: DateText.abbreviated(entry.day.startOfDay(in: .autoupdatingCurrent))
                                             + ": " + L("ach_reviewed_n", CountText.number(entry.reviewed))))
                }
            }
            .frame(height: 104)
        }
        .padding(16)
        .background(AppColors.surface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
        .accessibilityIdentifier("achievements.week")
    }
}

/// Texte und Farben der Abzeichen.
enum AchievementText {
    static func title(_ id: AchievementID) -> String {
        switch id {
        case .firstDecision: L("ach_first_decision")
        case .activeDays3: L("ach_active_3")
        case .activeDays7: L("ach_active_7")
        case .reviewed100: L("ach_reviewed_n", CountText.number(100))
        case .reviewed1000: L("ach_reviewed_n", CountText.number(1_000))
        case .reviewed5000: L("ach_reviewed_n", CountText.number(5_000))
        case .reviewed10000: L("ach_reviewed_n", CountText.number(10_000))
        case .libraryDone: L("ach_library_done")
        case .streak3: L("ach_streak_3")
        case .streak7: L("ach_streak_7")
        case .streak30: L("ach_streak_30")
        case .streak100: L("ach_streak_100")
        case .firstMonthDone: L("ach_first_month")
        case .twelveMonthsDone: L("ach_months_12")
        case .laterCleared: L("ach_later_clear")
        case .goal10: L("ach_goal_10")
        case .firstCollage: L("ach_first_collage")
        case .firstPDF: L("ach_first_pdf")
        case .firstFilm: L("ach_first_film")
        case .pairsUnder30: L("ach_pairs_under", L("memory_title"), CountText.number(Int(Achievements.pairsUnderSeconds)))
        case .pairs12: L("ach_pairs_12")
        case .snake50: L("ach_game_photos", L("snake_title"), CountText.number(Achievements.snakeTarget))
        case .blocks5000: L("ach_game_points", L("blocks_title"), CountText.number(Achievements.blocksTarget))
        case .allGames: L("ach_all_games")
        }
    }

    /// Bedingung für offene Abzeichen ohne zählbaren Rest.
    static func condition(_ id: AchievementID) -> String {
        switch id.group {
        case .studio: L("ach_cond_studio")
        case .games: L("ach_cond_games")
        default: L("ach_cond_review")
        }
    }

    static func group(_ g: AchievementGroup) -> String {
        switch g {
        case .start: L("ach_group_start")
        case .reviewed: L("ach_group_reviewed")
        case .streak: L("ach_group_streak")
        case .order: L("ach_group_order")
        case .studio: L("tab_studio")
        case .games: L("ach_group_games")
        }
    }

    static func tint(_ g: AchievementGroup) -> Color {
        switch g {
        case .start: AppColors.accent
        case .reviewed: AppColors.keep
        case .streak: AppColors.cleanup
        case .order: AppColors.success
        case .studio, .games: AppColors.later
        }
    }

    /// Kurzer Wochentag (z. B. „M“), in der Sprache der App.
    static func weekdayInitial(_ day: LocalDay) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .autoupdatingCurrent
        cal.locale = Locale(identifier: Strings.language)
        let weekday = cal.component(.weekday, from: day.startOfDay(in: .autoupdatingCurrent))
        return cal.veryShortStandaloneWeekdaySymbols[weekday - 1]
    }
}
