import PhotoMaidCore
import SwiftUI

/// Screen 13 – Verlauf. Alle / Behalten / Bereinigt / Später. Echte Events, keine erfundenen Statistiken.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var filter: Filter = .all

    enum Filter: Hashable { case all, kept, cleaned, later }

    private var filtered: [DecisionEvent] {
        app.events.reversed().filter { e in
            switch filter {
            case .all: true
            case .kept: e.to.disposition == .kept && e.kind != .undo
            case .cleaned: e.kind == .cleanupConfirmed || e.kind == .reconciledMissing
            case .later: e.to.disposition == .later && e.kind != .undo
            }
        }
    }

    var body: some View {
        let days = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.at) }
        let keys = days.keys.sorted(by: >)
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    Text("Alle").tag(Filter.all)
                    Text("Behalten").tag(Filter.kept)
                    Text("Bereinigt").tag(Filter.cleaned)
                    Text("Später").tag(Filter.later)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            if keys.isEmpty {
                Section { Text("Noch keine Einträge.").foregroundStyle(AppColors.textSecondary) }
            }
            ForEach(keys.prefix(60), id: \.self) { day in
                let items = days[day] ?? []
                Section {
                    ForEach(items.prefix(300)) { e in row(e) }
                } header: {
                    Text("\(day.formatted(date: .complete, time: .omitted)) · \(items.count) Einträge")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text("Verlauf"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Rückgängig", systemImage: "arrow.uturn.backward") { Task { _ = await app.undo() } }
                    .disabled(!app.canUndo)
            }
        }
    }

    private func row(_ e: DecisionEvent) -> some View {
        let (symbol, tint, title) = describe(e)
        return HStack(spacing: AppSpacing.s) {
            if e.item.provider == .photoLibrary {
                ThumbnailView(assetID: e.item.localIdentifier).frame(width: 44, height: 44)
            }
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppTypography.subheadline.weight(.semibold))
                Text(e.at.formatted(date: .omitted, time: .shortened)).font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func describe(_ e: DecisionEvent) -> (String, Color, LocalizedStringKey) {
        switch e.kind {
        case .cleanupConfirmed: return ("trash.fill", AppColors.cleanup, "Bereinigt (bestätigt)")
        case .reconciledMissing: return ("questionmark.circle", AppColors.warning, "Nicht mehr vorhanden (abgeglichen)")
        case .cleanupNotPerformed: return ("xmark.circle", AppColors.textSecondary, "Bereinigung nicht ausgeführt")
        case .undo: return ("arrow.uturn.backward", AppColors.textSecondary, "Rückgängig gemacht")
        case .scheduleChanged: return ("calendar", AppColors.later, "Termin gesetzt")
        case .deferralRemoved: return ("bookmark.slash", AppColors.textSecondary, "Zurückstellung entfernt")
        case .unmarked: return ("minus.circle", AppColors.textSecondary, "Aus dem Papierkorb zurückgelegt")
        case .decision, .correction:
            let corr = e.kind == .correction
            switch e.to.disposition {
            case .kept: return ("checkmark.circle.fill", AppColors.keep, corr ? "Korrigiert: behalten" : "Behalten")
            case .markedForCleanup: return ("trash", AppColors.cleanup, corr ? "Korrigiert: Papierkorb" : "In den Papierkorb")
            case .later: return ("clock", AppColors.later, corr ? "Korrigiert: später" : "Auf später gelegt")
            default: return ("circle", AppColors.textSecondary, "Geändert")
            }
        }
    }
}
