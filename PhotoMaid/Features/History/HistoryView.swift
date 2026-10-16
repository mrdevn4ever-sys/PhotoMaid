import PhotoMaidCore
import SwiftUI

/// Verlauf: Alle / Behalten / Bereinigt / Später. Echte Ereignisse, keine erfundenen Statistiken. Später-Liste oben.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var filter = 0

    var body: some View {
        let events = app.read.events.filter { e in
            switch filter {
            case 1: e.to.disposition == .kept && e.kind != .undo
            case 2: e.kind == .cleanupConfirmed || e.kind == .reconciledMissing
            case 3: e.to.disposition == .later && e.kind != .undo
            default: true
            }
        }
        let entries = Array(HistoryGrouping.group(events).reversed())
        let cal = Calendar.current
        let days = Dictionary(grouping: entries) { cal.startOfDay(for: $0.primary.at) }
        let keys = days.keys.sorted(by: >).prefix(60)
        List {
            Section {
                Button { app.navigate(.later, in: .history) } label: {
                    NavRow(symbol: "clock", tint: AppColors.later, title: L("later"), value: CountText.number(app.read.laterRecords.count))
                }
                .buttonStyle(.plain)
                Picker("", selection: $filter) {
                    Text(key: "history_all").tag(0)
                    Text(key: "history_kept").tag(1)
                    Text(key: "history_cleaned").tag(2)
                    Text(key: "history_later").tag(3)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            if keys.isEmpty {
                if app.read.events.isEmpty {
                    EmptyState(symbol: "clock.arrow.circlepath", title: L("history_empty_title"), message: L("history_empty"))
                        .listRowBackground(Color.clear)
                } else {
                    EmptyState(symbol: "line.3.horizontal.decrease.circle", title: L("history_filter_empty_title"),
                               message: L("history_filter_empty"))
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(Array(keys), id: \.self) { day in
                let list = days[day] ?? []
                Section(LP("history_day_header", list.count, DateText.complete(day), list.count)) {
                    ForEach(list.prefix(300)) { HistoryRow(entry: $0) }
                }
            }
        }
        .appPage().readableContent()
        .navigationTitle(L("tab_history"))
        .accessibilityIdentifier("history.events")
        .accessibilityValue(Text(verbatim: String(app.read.events.count)))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { _ = await app.undo() } } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!app.read.canUndo)
                    .accessibilityLabel(Text(key: "undo"))
            }
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        let e = entry.primary
        let (symbol, tint, key) = Self.describe(e)
        let day = (entry.schedule ?? (e.kind == .scheduleChanged ? e : nil))?.to.dueDay
        let text: String = if let day {
            L("history_with_day", L(key), DayText.string(day))
        } else if entry.itemCount > 1 {
            L("history_with_day", L(key), LP("items_count", entry.itemCount))
        } else {
            L(key)
        }
        HStack(spacing: AppSpacing.s) {
            if e.item.provider == .photoLibrary { AssetThumbnail(assetID: e.item.localIdentifier, side: 44) }
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(verbatim: text).font(AppTypography.subheadline.weight(.semibold))
                Text(verbatim: DateText.time(e.at)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    static func describe(_ e: DecisionEvent) -> (String, Color, String) {
        switch e.kind {
        case .cleanupConfirmed: return ("trash.slash", AppColors.cleanup, "h_cleaned")
        case .reconciledMissing: return ("questionmark.circle", AppColors.warning, "h_reconciled")
        case .cleanupNotPerformed: return ("xmark.circle", AppColors.textSecondary, "h_not_performed")
        case .undo: return ("arrow.uturn.backward", AppColors.textSecondary, "h_undo")
        case .scheduleChanged: return ("calendar", AppColors.later, "h_schedule")
        case .deferralRemoved: return ("calendar.badge.minus", AppColors.textSecondary, "h_deferral_removed")
        case .unmarked: return ("minus.circle", AppColors.textSecondary, "h_unmarked")
        case .decision, .correction:
            let corr = e.kind == .correction
            switch e.to.disposition {
            case .kept: return ("checkmark.circle", AppColors.keep, corr ? "h_kept_corr" : "h_kept")
            case .markedForCleanup: return ("trash", AppColors.cleanup, corr ? "h_trash_corr" : "h_trash")
            case .later: return ("clock", AppColors.later, corr ? "h_later_corr" : "h_later")
            default: return ("circle", AppColors.textSecondary, "h_changed")
            }
        }
    }
}
