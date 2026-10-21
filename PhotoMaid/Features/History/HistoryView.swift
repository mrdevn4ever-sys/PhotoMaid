import PhotoMaidCore
import SwiftUI

/// Verlauf: Alle / Behalten / Bereinigt / Später. Echte Ereignisse, keine erfundenen Statistiken.
/// Experiment-Design: Kennzahl-Kacheln, Filter-Chips und Karten je Eintrag wie im Artefakt.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var filter = 0

    private func matches(_ e: DecisionEvent, _ filter: Int) -> Bool {
        switch filter {
        case 1: e.to.disposition == .kept && e.kind != .undo
        case 2: e.kind == .cleanupConfirmed || e.kind == .reconciledMissing
        case 3: e.to.disposition == .later && e.kind != .undo
        default: true
        }
    }

    var body: some View {
        let all = app.read.events
        let events = all.filter { matches($0, filter) }
        let entries = Array(HistoryGrouping.group(events).reversed())
        let cal = Calendar.current
        let days = Dictionary(grouping: entries) { cal.startOfDay(for: $0.primary.at) }
        let keys = Array(days.keys.sorted(by: >).prefix(60))
        let newest = entries.first?.id
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                Text(key: "tab_history").pageTitle().accessibilityAddTraits(.isHeader).padding(.top, AppSpacing.xs)
                HStack(spacing: 10) {
                    stat(HistoryGrouping.group(all.filter { matches($0, 1) }).count, "history_kept", AppColors.keep) { filter = 1 }
                    stat(HistoryGrouping.group(all.filter { matches($0, 2) }).count, "history_cleaned", AppColors.cleanup) { filter = 2 }
                    stat(app.read.laterRecords.count, "history_later", AppColors.later) { app.navigate(.later, in: .history) }
                }
                chips
                if keys.isEmpty {
                    if all.isEmpty {
                        dashed(L("history_empty_title"), L("history_empty"))
                    } else {
                        dashed(L("history_filter_empty_title"), L("history_filter_empty"))
                    }
                }
                ForEach(keys, id: \.self) { day in
                    let list = days[day] ?? []
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(verbatim: LP("history_day_header", list.count, DateText.complete(day), list.count))
                            .font(PMFont.heading(18, relativeTo: .headline)).foregroundStyle(AppColors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4).padding(.horizontal, 4)
                        ForEach(list.prefix(300)) { entry in
                            HistoryRow(entry: entry, undo: entry.id == newest && app.read.canUndo ? {
                                Task { _ = await app.undo() }
                            } : nil)
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .appPage()
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle(L("tab_history"))
        .accessibilityIdentifier("history.events")
        .accessibilityValue(Text(verbatim: String(all.count)))
    }

    private func stat(_ value: Int, _ key: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: CountText.number(value)).font(PMFont.heading(28, relativeTo: .title)).foregroundStyle(tint)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(key: key).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(PMPressStyle())
        .accessibilityElement(children: .combine)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(Array(["history_all", "history_kept", "history_cleaned", "history_later"].enumerated()), id: \.offset) { i, key in
                    PMChip(title: L(key), selected: filter == i) { filter = i }
                }
            }
        }
        .accessibilityIdentifier("history.filter")
    }

    private func dashed(_ title: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
            Text(verbatim: text).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 28).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AppColors.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        .accessibilityElement(children: .combine)
    }
}

/// Auswahl-Chip (Artefakt): Kapsel 36 pt; gewählt hell mit dunkler Schrift.
struct PMChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(PMFont.text(.semibold, 14, relativeTo: .subheadline))
                .foregroundStyle(selected ? AppColors.background : AppColors.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(selected ? AppColors.textPrimary : AppColors.surface, in: .capsule)
                .overlay(Capsule().strokeBorder(selected ? AppColors.textPrimary : AppColors.control, lineWidth: 1))
                .frame(minHeight: AppSpacing.minTouch)
                .contentShape(.rect)
        }
        .buttonStyle(PMPressStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    var undo: (() -> Void)?

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
            Group {
                if e.item.provider == .photoLibrary {
                    AssetCell(assetID: e.item.localIdentifier)
                } else {
                    Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(PMTile.background(for: tint))
                }
            }
            .frame(width: 44, height: 54)
            .clipShape(.rect(cornerRadius: 10))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text).font(PMFont.text(.semibold, 15, relativeTo: .subheadline)).foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: DateText.time(e.at)).font(AppTypography.footnote).foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 0)
            if let undo {
                Button(action: undo) {
                    HStack(spacing: 6) {
                        PMIcon(.undo, size: 14, lineWidth: 2.4)
                        Text(key: "undo").font(PMFont.text(.semibold, 13, relativeTo: .footnote))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(AppColors.background, in: .capsule)
                    .overlay(Capsule().strokeBorder(AppColors.control, lineWidth: 1))
                    .frame(minHeight: AppSpacing.minTouch)
                    .contentShape(.rect)
                }
                .buttonStyle(PMPressStyle())
                .accessibilityIdentifier("history.undo")
            }
        }
        .padding(10)
        .background(AppColors.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
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
