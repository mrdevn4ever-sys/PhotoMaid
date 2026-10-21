import PhotoMaidCore
import SwiftUI

/// Später: fällige und kommende Wiedervorlagen in echten Datumsgruppen. Ansehen, Datum ändern, jetzt prüfen,
/// Zurückstellung entfernen (löscht keine Datei).
struct LaterView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: ItemRecord?

    var body: some View {
        let groups = ReviewQueues.laterGroups(records: app.read.laterRecords, today: app.today)
        List {
            if !groups.isEmpty && app.reminders.access == .notDetermined {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(key: "later_notify_title").font(AppTypography.headline)
                        Text(key: "privacy_notifications_text").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        Button(L("privacy_notifications_allow")) {
                            Task {
                                await app.reminders.requestAccess()
                                app.updateSettings { $0.notificationsOptIn = app.reminders.access == .allowed }
                            }
                        }
                        .buttonStyle(.pmBordered)
                    }
                }
            }
            if groups.isEmpty {
                EmptyState(symbol: "clock", title: L("later_empty_title"), message: L("later_empty") + "\n\n" + L("later_empty_hint"))
                    .listRowBackground(Color.clear)
            }
            ForEach(groups.indices, id: \.self) { gi in
                let group = groups[gi]
                Section {
                    ForEach(group.items, id: \.item) { r in row(r) }
                    if group.key == .due {
                        Button(L("later_review_now_count", group.items.count)) {
                            app.open(FeedRequest(.items(group.items.map(\.item), titleKey: "feed_title_due")))
                        }
                        .frame(minHeight: AppSpacing.minTouch)
                    }
                } header: {
                    Text(verbatim: header(group.key, group.items.count))
                }
            }
        }
        .appPage()
        .navigationTitle(L("later"))
        .sheet(item: $editing) { r in
            LaterDateSheet(today: app.today) { day in
                Task {
                    await app.decide(r.item, .schedule(day))
                    await app.reminders.scheduleDueReminder(for: day, optedIn: app.settings.notificationsOptIn)
                }
            }
        }
    }

    private func header(_ g: LaterGroup, _ n: Int) -> String {
        switch g {
        case .due: L("later_group_due", n)
        case .tomorrow: L("later_group_tomorrow", n)
        case .withinSevenDays: L("later_group_7", n)
        case .later(let d): L("later_group_from", DayText.string(d), n)
        case .noDate: L("later_group_nodate", n)
        case .bookmarked: L("later_group_bookmarked", n)
        }
    }

    private func row(_ r: ItemRecord) -> some View {
        let isPhoto = r.item.provider == .photoLibrary
        let asset = isPhoto ? app.asset(r.item.localIdentifier) : nil
        let title: String
        if !isPhoto { title = L("file") }
        else if let kind = asset?.kind { title = kind == .video ? L("video") : (kind == .screenshot ? L("screenshot") : L("photo")) }
        else { title = L("medium") } // Medium nicht (mehr) lesbar: Typ unbekannt, nichts erfinden.
        let today = app.today
        let whenText: String
        if r.bookmarked { whenText = L("later_bookmarked_row") }
        else if let d = r.dueDay {
            whenText = d == today ? L("later_due_today") : (d < today ? L("later_due_since", DayText.string(d)) : L("later_review_on", DayText.string(d)))
        } else { whenText = L("later_next_review") }
        let due = r.dueDay.map { $0 <= today } ?? false
        return HStack(spacing: AppSpacing.s) {
            if isPhoto { AssetThumbnail(assetID: r.item.localIdentifier, side: 56) }
            else { Image(systemName: "doc").font(.title2).frame(width: 56, height: 56) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(AppTypography.subheadline.weight(.semibold))
                Text(verbatim: whenText).font(AppTypography.footnote).foregroundStyle(due ? AppColors.later : AppColors.textSecondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button { editing = r } label: { Label(L("change_date"), systemImage: "calendar") }
                if isPhoto {
                    Button { app.open(FeedRequest(.items([r.item], titleKey: "later"))) } label: {
                        Label(L("later_review_now"), systemImage: "eye")
                    }
                }
                Button(role: .destructive) { Task { await app.decide(r.item, .removeDeferral) } } label: {
                    Label(L(r.bookmarked ? "later_back_to_stack" : "later_remove"), systemImage: "calendar.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: AppSpacing.minTouch, height: AppSpacing.minTouch)
            }
            .accessibilityLabel(Text(key: "actions"))
        }
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }
}

/// Datum ändern (Später-Verwaltung).
struct LaterDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let today: LocalDay
    let confirm: (LocalDay) -> Void
    @State private var date: Date

    init(today: LocalDay, confirm: @escaping (LocalDay) -> Void) {
        self.today = today
        self.confirm = confirm
        _date = State(initialValue: today.adding(days: 14).startOfDay(in: .autoupdatingCurrent))
    }

    var body: some View {
        NavigationStack {
            DatePicker(L("change_date"), selection: $date, in: today.startOfDay(in: .autoupdatingCurrent)...,
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(AppSpacing.pageMargin)
                .navigationTitle(L("change_date"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("save")) { confirm(LocalDay(date, timeZone: .autoupdatingCurrent)); dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

extension ItemRecord: @retroactive Identifiable {
    public var id: ItemReference { item }
}
