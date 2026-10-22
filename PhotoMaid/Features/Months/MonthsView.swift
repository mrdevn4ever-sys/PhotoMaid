import PhotoMaidCore
import SwiftUI

/// Nach Monat: Noch nicht begonnen · In Arbeit · Durchgesehen. Monate sind nur Filter (nichts je Monat gespeichert).
struct MonthsView: View {
    @Environment(AppModel.self) private var app
    @State private var months: [MonthProgress]?

    var body: some View {
        Group {
            if let months {
                if months.isEmpty {
                    EmptyState(symbol: "calendar", title: L("months_empty_title"), message: L("months_empty_text"))
                } else {
                    list(months)
                }
            } else {
                LoadingState()
            }
        }
        .appPage()
        .navigationTitle(L("months_title"))
        .task(id: app.tabRecountKey("\(app.cleanupMedia.count)-\(app.read.events.count)")) {
            guard !app.tabsCoveredByFeed else { return }
            await load()
        }
    }

    private func list(_ months: [MonthProgress]) -> some View {
        let years = Dictionary(grouping: months, by: \.month.year)
        return List {
            Section {
                Text(key: "months_intro").font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                    .listRowBackground(Color.clear)
            }
            if !app.settings.monthsTourSeen {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(key: "tour_months_row_title").font(AppTypography.headline)
                        Text(key: "tour_months_row_text").font(AppTypography.footnote)
                        Text(key: "tour_months_later_text").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                        Text(key: "tour_months_more_text").font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
                        Button(L("tour_done")) { app.updateSettings { $0.monthsTourSeen = true } }
                    }
                }
            }
            ForEach(years.keys.sorted(by: >), id: \.self) { year in
                Section(String(year)) {
                    ForEach(years[year] ?? []) { m in row(m) }
                }
            }
        }
    }

    private func row(_ m: MonthProgress) -> some View {
        let title = MonthText.title(m.month)
        let progress = switch m.state {
        case .done: L("month_done")
        case .notStarted: LP("month_not_started", m.total)
        case .inProgress: LP("month_progress", m.total, m.reviewed, m.total)
        }
        let later = m.later > 0 ? LP("month_later", m.later) : nil
        return HStack(spacing: AppSpacing.s) {
            Button { app.open(FeedRequest(.month(m.month, again: false))) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(verbatim: title).font(AppTypography.body.weight(.semibold))
                        if m.state == .done {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.success).accessibilityHidden(true)
                        }
                    }
                    Text(verbatim: progress).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    if let later { Text(verbatim: later).font(AppTypography.caption).foregroundStyle(AppColors.later) }
                    if m.state == .inProgress { ProgressView(value: m.fraction).tint(AppColors.accent) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(m.state == .done)
            Menu {
                Button { app.navigate(.grid(.month(m.month))) } label: { Label(L("grid_open"), systemImage: "square.grid.3x3") }
                Button { app.open(FeedRequest(.month(m.month, again: true))) } label: {
                    Label(L("month_again"), systemImage: "arrow.counterclockwise")
                }
                .disabled(m.reviewed == 0)
            } label: {
                Image(systemName: "ellipsis").frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text(verbatim: L("month_actions", title)))
        }
        .frame(minHeight: 64)
    }

    private func load() async {
        let media = app.cleanupMedia
        let records = app.read.records
        months = await Task.detached(priority: .userInitiated) {
            ProgressRules.months(media, date: \.creationDate, record: { records[$0.reference] }, timeZone: .autoupdatingCurrent)
        }.value
    }
}
