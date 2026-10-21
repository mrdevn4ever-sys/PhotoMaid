import PhotoMaidCore
import SwiftUI

/// Später: fällige und kommende Wiedervorlagen in echten Datumsgruppen. Ansehen, Datum ändern, jetzt prüfen,
/// Zurückstellung entfernen (löscht keine Datei).
/// Experiment-Design: violetter Titel, „Jetzt ansehen (n)“, Erinnerungskarte und Karten je Medium wie im Artefakt.
struct LaterView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: ItemRecord?

    var body: some View {
        let groups = ReviewQueues.laterGroups(records: app.read.laterRecords, today: app.today)
        let due = groups.first { $0.key == .due }?.items ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                PageHeading(title: L("later"), color: AppColors.later, subtitle: L("art_later_sub"))
                if groups.isEmpty {
                    VStack(spacing: 6) {
                        Text(key: "later_empty_title").font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                        Text(verbatim: L("later_empty_hint")).font(AppTypography.subheadline).foregroundStyle(AppColors.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 40).padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(AppColors.dashed, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    .accessibilityElement(children: .combine)
                }
                if !due.isEmpty {
                    Button {
                        app.open(FeedRequest(.items(due.map(\.item), titleKey: "feed_title_due")))
                    } label: {
                        Text(verbatim: L("later_review_now_count", due.count))
                            .font(AppTypography.button).foregroundStyle(AppColors.onLater)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(AppColors.later, in: .rect(cornerRadius: AppRadii.button))
                            .contentShape(.rect(cornerRadius: AppRadii.button))
                    }
                    .buttonStyle(PMPressStyle())
                    .accessibilityIdentifier("later.review")
                }
                if !groups.isEmpty && app.reminders.access == .notDetermined { notifyCard }
                ForEach(groups.indices, id: \.self) { gi in
                    let group = groups[gi]
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(verbatim: header(group.key, group.items.count))
                            .font(PMFont.heading(18, relativeTo: .headline)).foregroundStyle(AppColors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4).padding(.horizontal, 4)
                        ForEach(group.items, id: \.item) { r in row(r) }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.pageMargin)
            .padding(.bottom, AppSpacing.xxl)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .appPage()
        .navigationTitle(L("later"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        .sheet(item: $editing) { r in
            LaterDateSheet(today: app.today) { day in
                Task {
                    await app.decide(r.item, .schedule(day))
                    await app.reminders.scheduleDueReminder(for: day, optedIn: app.settings.notificationsOptIn)
                }
            }
        }
    }

    /// „Erinnern, wenn es wieder dran ist?“ – violette Pausen-Karte mit Glocke.
    private var notifyCard: some View {
        HStack(alignment: .top, spacing: 14) {
            PMIcon(.bell, size: 19, lineWidth: 2)
                .foregroundStyle(AppColors.later)
                .frame(width: 38, height: 38)
                .background(AppColors.pauseStroke, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(key: "later_notify_title").font(PMFont.text(.semibold, 15, relativeTo: .subheadline))
                    .foregroundStyle(AppColors.textPrimary)
                Text(key: "privacy_notifications_text").font(AppTypography.footnote).foregroundStyle(AppColors.pauseText)
                    .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        await app.reminders.requestAccess()
                        app.updateSettings { $0.notificationsOptIn = app.reminders.access == .allowed }
                    }
                } label: {
                    Text(key: "privacy_notifications_allow")
                        .font(PMFont.text(.bold, 13, relativeTo: .footnote)).foregroundStyle(AppColors.onLater)
                        .padding(.horizontal, 14).frame(minHeight: 36)
                        .background(AppColors.later, in: .capsule)
                        .frame(minHeight: AppSpacing.minTouch)
                        .contentShape(.rect)
                }
                .buttonStyle(PMPressStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AppColors.pauseSurface, in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(AppColors.pauseStroke, lineWidth: 1))
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

    /// Karte je Medium: Vorschau 48 × 60, Art, Termin (fällig violett), „Datum ändern“. Ansehen und Entfernen über
    /// Tippen bzw. das Kontextmenü (und als Bedienungshilfen-Aktionen).
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
        let review: () -> Void = { app.open(FeedRequest(.items([r.item], titleKey: "later"))) }
        let remove: () -> Void = { Task { await app.decide(r.item, .removeDeferral) } }
        return HStack(spacing: AppSpacing.s) {
            Button { if isPhoto { review() } else { editing = r } } label: {
                HStack(spacing: AppSpacing.s) {
                    Group {
                        if isPhoto {
                            AssetCell(assetID: r.item.localIdentifier)
                        } else {
                            PMIcon(.file, size: 20).foregroundStyle(AppColors.textSecondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(AppColors.control)
                        }
                    }
                    .frame(width: 48, height: 60)
                    .clipShape(.rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: title).font(PMFont.text(.semibold, 15, relativeTo: .subheadline))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(verbatim: whenText).font(AppTypography.footnote)
                            .foregroundStyle(due ? AppColors.later : AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(PMPressStyle())
            .accessibilityElement(children: .combine)
            Button { editing = r } label: {
                Text(key: "change_date")
                    .font(PMFont.text(.semibold, 13, relativeTo: .footnote)).foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 12).frame(minHeight: 36)
                    .background(AppColors.background, in: .capsule)
                    .overlay(Capsule().strokeBorder(AppColors.control, lineWidth: 1))
                    .frame(minHeight: AppSpacing.minTouch)
                    .contentShape(.rect)
            }
            .buttonStyle(PMPressStyle())
            .fixedSize()
        }
        .padding(10)
        .background(AppColors.surface, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppColors.surfaceStroke, lineWidth: 1))
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 16))
        .contextMenu {
            Button { editing = r } label: { Label(L("change_date"), systemImage: "calendar") }
            if isPhoto {
                Button { review() } label: { Label(L("later_review_now"), systemImage: "eye") }
            }
            Button(role: .destructive) { remove() } label: {
                Label(L(r.bookmarked ? "later_back_to_stack" : "later_remove"), systemImage: "calendar.badge.minus")
            }
        }
        .accessibilityAction(named: Text(verbatim: L(r.bookmarked ? "later_back_to_stack" : "later_remove"))) { remove() }
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
