import PhotoMaidCore
import SwiftUI

/// Screen 11 – Später. Fällige und kommende Wiedervorlagen in echten Datumsgruppen.
/// Ansehen, Datum ändern, jetzt prüfen, Zurückstellung entfernen (löscht keine Datei).
struct LaterView: View {
    @Environment(AppModel.self) private var app
    let openFeed: (FeedRequest) -> Void
    @State private var editing: ItemRecord?

    var body: some View {
        let groups = ReviewQueues.laterGroups(records: app.laterRecords, today: app.today)
        List {
            if groups.isEmpty {
                Section {
                    Text("Nichts zurückgestellt. Wische im Feed nach rechts, um etwas auf später zu legen.")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            ForEach(groups, id: \.key) { group in
                Section {
                    ForEach(group.items, id: \.item) { r in row(r) }
                    if group.key == .due {
                        Button("Jetzt prüfen (\(group.items.count))") {
                            openFeed(FeedRequest(source: .items(group.items.map(\.item), title: "Wieder fällig")))
                        }
                    }
                } header: {
                    header(group.key, count: group.items.count)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle(Text("Später"))
        .sheet(item: Binding(get: { editing.map(EditingBox.init) }, set: { editing = $0?.record })) { box in
            LaterDateSheet(title: "Datum ändern") { day in
                Task { await app.decide(box.record.item, .schedule(day)); await app.reminders.scheduleDueReminder(for: day) }
            }
        }
    }

    private struct EditingBox: Identifiable {
        let record: ItemRecord
        var id: ItemReference { record.item }
    }

    private func header(_ key: LaterGroup, count: Int) -> Text {
        switch key {
        case .due: Text("Wieder fällig · \(count)")
        case .tomorrow: Text("Morgen · \(count)")
        case .withinSevenDays: Text("In den nächsten 7 Tagen · \(count)")
        case .later(let d): Text("Ab \(DayText.string(d)) · \(count)")
        case .noDate: Text("Ohne Datum · \(count)")
        }
    }

    private func row(_ r: ItemRecord) -> some View {
        HStack(spacing: AppSpacing.s) {
            if r.item.provider == .photoLibrary {
                ThumbnailView(assetID: r.item.localIdentifier).frame(width: 52, height: 52)
            } else {
                Image(systemName: "doc.fill").font(.title2).frame(width: 52, height: 52).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.item.provider == .photoLibrary ? String(localized: "Medium") : (r.item.localIdentifier as NSString).lastPathComponent)
                    .font(AppTypography.subheadline.weight(.semibold)).lineLimit(1)
                if let d = r.dueDay { DayText.text(d).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary) }
            }
            Spacer()
            Menu {
                Button("Datum ändern", systemImage: "calendar") { editing = r }
                Button("Jetzt prüfen", systemImage: "eye") {
                    openFeed(FeedRequest(source: .items([r.item], title: "Später")))
                }
                Button("Zurückstellung entfernen", systemImage: "bookmark.slash") {
                    Task { await app.decide(r.item, .removeDeferral) }
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text("Aktionen"))
        }
    }
}
