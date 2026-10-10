import Photos
import PhotoMaidCore
import SwiftUI

/// Status einer Quelle: Mitglieder und davon offene (immer aus dem globalen Ledger, nie je Quelle gespeichert).
struct QuickStatus: Equatable {
    let members: Int
    let pending: Int
}

/// „Schnellzugriffe“ auf Heute: eine Zeile je Quelle, „Hinzufügen“ als letzte Zeile. Nur Abfragen, keine Medien-IDs.
struct QuickAccessSection: View {
    @Environment(AppModel.self) private var app
    @State private var adding = false
    @State private var editing = false
    @State private var status: [String: QuickStatus] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: L("qa_title"), actionTitle: app.quickAccess.isEmpty ? nil : L("qa_edit")) { editing = true }
            RowGroup {
                ForEach(Array(app.quickAccess.enumerated()), id: \.element.key) { i, q in
                    if i > 0 { SwiftUI.Divider().padding(.leading, 52) }
                    let st = status[q.key]
                    Button {
                        if st?.members == 0 { editing = true } else { app.open(FeedRequest(.quick(q))) }
                    } label: {
                        NavRow(symbol: QuickAccessText.symbol(q), tint: QuickAccessUI.tint(q.kind), title: QuickAccessText.title(q),
                               value: QuickAccessUI.statusText(st), showsChevron: st?.members != 0)
                    }
                    .buttonStyle(.plain)
                }
                if app.quickAccess.count < QuickAccess.maxItems {
                    if !app.quickAccess.isEmpty { SwiftUI.Divider().padding(.leading, 52) }
                    Button { adding = true } label: {
                        NavRow(symbol: "plus", title: L("qa_add"), showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: "\(app.quickAccess.map(\.key))-\(app.pending.count)-\(app.cleanupMedia.count)") { await recount() }
        .sheet(isPresented: $adding) { QuickAccessAddSheet() }
        .sheet(isPresented: $editing) { QuickAccessEditSheet() }
    }

    private func recount() async {
        status = await QuickAccessUI.status(for: app.quickAccess, media: app.cleanupMedia,
                                             pending: Set(app.pending.map(\.localIdentifier)), now: app.now)
    }
}

enum QuickAccessUI {
    static func tint(_ k: QuickSourceKind) -> Color {
        switch k {
        case .photos, .latestPhotos, .portraits: AppColors.accent
        case .videos, .latestVideos, .longVideos: AppColors.amber
        case .screenshots, .livePhotos, .selfies: AppColors.later
        case .thisWeek, .onThisDay: AppColors.success
        case .album, .random: AppColors.indigo
        case .favorites: AppColors.warning
        }
    }

    static func statusText(_ st: QuickStatus?) -> String? {
        guard let st else { return nil }
        if st.members == 0 { return L("qa_empty") }
        if st.pending == 0 { return "✓" }
        return CountText.number(st.pending)
    }

    static func subtitle(_ q: QuickAccessItem) -> String? {
        switch q.kind {
        case .latestPhotos: LP("qa_latest_photos_sub", QuickAccess.latestPhotosLimit)
        case .latestVideos: LP("qa_latest_videos_sub", QuickAccess.latestVideosLimit)
        case .thisWeek: L("qa_this_week_sub")
        case .random: L("qa_random_sub", QuickAccess.randomLimit)
        case .onThisDay: L("qa_on_this_day_sub")
        case .longVideos: L("qa_long_videos_sub")
        case .selfies: L("qa_selfies_sub")
        case .portraits: L("qa_portraits_sub")
        case .livePhotos: L("qa_live_photos_sub")
        case .favorites: L("qa_favorites_sub")
        case .photos, .videos, .screenshots, .album: nil
        }
    }

    /// Reine Filter im Speicher (Sammlungen einmal je Quelle gelesen), abseits des Main-Threads.
    static func status(for items: [QuickAccessItem], media: [MediaAsset], pending: Set<String>, now: Date) async -> [String: QuickStatus] {
        await Task.detached(priority: .utility) {
            var out: [String: QuickStatus] = [:]
            for q in items {
                let c = QuickAccessQuery.count(q, in: media, now: now, open: pending)
                out[q.key] = QuickStatus(members: c.members, pending: c.open)
            }
            return out
        }.value
    }
}

/// Quellen der Schnellzugriffe (nur Abfragen; ohne Medien-IDs gespeichert). Die Regeln stehen im Kern
/// (`QuickSourceFilter`); hier kommen nur Uhr, Region, Zufall und die Sammlungen der Fotos-App dazu.
enum QuickAccessQuery {
    /// `open`: noch offene Medien – „Zufällig“ wählt nur daraus. `seed`: bei jedem Aufruf neu gemischt.
    static func assets(_ q: QuickAccessItem, in media: [MediaAsset], now: Date, open: Set<String>? = nil,
                       seed: UInt64 = UInt64.random(in: 1...UInt64.max)) -> [MediaAsset] {
        QuickSourceFilter.select(q, in: media, facts: { $0.quickFacts }, context: context(q, now: now, open: open, seed: seed))
    }

    static func count(_ q: QuickAccessItem, in media: [MediaAsset], now: Date, open: Set<String>) -> QuickSourceCount {
        QuickSourceFilter.count(q, in: media, facts: { $0.quickFacts }, context: context(q, now: now, open: open, seed: 0))
    }

    private static func context(_ q: QuickAccessItem, now: Date, open: Set<String>?, seed: UInt64) -> QuickQueryContext {
        QuickQueryContext(now: now, timeZone: .autoupdatingCurrent, firstWeekday: Calendar.current.firstWeekday,
                          members: q.kind.readsCollection ? members(q) : nil, open: open, seed: seed)
    }

    /// Mitglieder eines Albums bzw. des Smart-Albums „Selfies“ (PhotoKit, keine Bildanalyse).
    private static func members(_ q: QuickAccessItem) -> Set<String>? {
        switch q.kind {
        case .album:
            guard let id = q.album else { return nil }
            return PhotoLibraryService.assetIDs(inCollection: id)
        case .selfies:
            let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumSelfPortraits, options: nil)
            guard let selfies = albums.firstObject else { return nil }
            return PhotoLibraryService.assetIDs(inCollection: selfies.localIdentifier)
        default:
            return nil
        }
    }
}

extension MediaAsset {
    /// Was die Schnellzugriffe über ein Medium wissen dürfen (nur Metadaten aus PhotoKit).
    var quickFacts: QuickMediaFacts {
        QuickMediaFacts(id: id, kind: kind, creationDate: creationDate, duration: duration, isFavorite: isFavorite,
                        isLivePhoto: isLivePhoto, isPortrait: isPortrait)
    }
}

/// Stabiler Katalog: alle Quellen immer an derselben Stelle, vorhandene mit „Auf der Startseite“, jede mit echter
/// offener Zahl. Alben der Fotos-App darunter (die größten zuerst).
struct QuickAccessAddSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [PhotoAlbum]?
    @State private var status: [String: QuickStatus] = [:]

    private let catalogue: [QuickAccessItem] = QuickAccess.catalogue.map { QuickAccessItem(kind: $0) }

    private var albumItems: [(PhotoAlbum, QuickAccessItem)] {
        func walk(_ l: [PhotoAlbum]) -> [PhotoAlbum] { l.flatMap { $0.isFolder ? walk($0.children) : [$0] } }
        return walk(albums ?? []).filter { $0.count > 0 }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.title.localizedCompare($1.title) == .orderedAscending }
            .map { ($0, QuickAccessItem(kind: .album, album: $0.id)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if app.quickAccess.count >= QuickAccess.maxItems {
                    Text(verbatim: L("qa_limit", QuickAccess.maxItems)).font(AppTypography.footnote)
                } else {
                    Section {
                        ForEach(catalogue) { option($0, title: QuickAccessText.title($0), subtitle: QuickAccessUI.subtitle($0)) }
                    }
                    Section(L("qa_folders_header")) {
                        if albums == nil {
                            ProgressView()
                        } else if albumItems.isEmpty {
                            Text(key: "qa_no_folders").foregroundStyle(AppColors.textSecondary)
                        } else {
                            ForEach(albumItems, id: \.1.key) { album, q in
                                option(q, title: album.title, subtitle: LP("items_count", album.count))
                            }
                        }
                    }
                }
            }
            .appPage()
            .navigationTitle(L("qa_add_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task {
            albums = await PhotoLibraryService.loadAlbums()
            status = await QuickAccessUI.status(for: catalogue + albumItems.map(\.1), media: app.cleanupMedia,
                                                 pending: Set(app.pending.map(\.localIdentifier)), now: app.now)
        }
    }

    private func option(_ q: QuickAccessItem, title: String, subtitle: String?) -> some View {
        let present = app.quickAccess.contains { $0.key == q.key }
        return Button {
            Haptics.success()
            app.setQuickAccess(QuickAccess.add(app.quickAccess, q))
        } label: {
            NavRow(symbol: QuickAccessText.symbol(q), tint: QuickAccessUI.tint(q.kind), title: title, subtitle: subtitle,
                   value: present ? L("qa_on_today") : QuickAccessUI.statusText(status[q.key]), showsChevron: false)
        }
        .buttonStyle(.plain)
        .disabled(present)
    }
}

/// Bearbeiten: Reihenfolge ziehen, entfernen. Entfernt wird nur der Schnellzugriff – Medien und Entscheidungen bleiben.
struct QuickAccessEditSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.quickAccess) { q in
                        Label { Text(verbatim: QuickAccessText.title(q)) } icon: {
                            Image(systemName: QuickAccessText.symbol(q)).foregroundStyle(QuickAccessUI.tint(q.kind))
                        }
                        .frame(minHeight: AppSpacing.minTouch)
                        .accessibilityAction(named: Text(verbatim: L("qa_move_up", QuickAccessText.title(q)))) {
                            app.setQuickAccess(QuickAccess.move(app.quickAccess, q, by: -1))
                        }
                        .accessibilityAction(named: Text(verbatim: L("qa_move_down", QuickAccessText.title(q)))) {
                            app.setQuickAccess(QuickAccess.move(app.quickAccess, q, by: 1))
                        }
                    }
                    .onMove { from, to in
                        var list = app.quickAccess
                        list.move(fromOffsets: from, toOffset: to)
                        Haptics.tick()
                        app.setQuickAccess(list)
                    }
                    .onDelete { idx in
                        let remove = idx.map { app.quickAccess[$0] }
                        var list = app.quickAccess
                        for q in remove { list = QuickAccess.remove(list, q) }
                        app.setQuickAccess(list)
                    }
                } footer: {
                    Text(key: "qa_remove_note")
                }
            }
            .environment(\.editMode, .constant(.active))
            .appPage()
            .navigationTitle(L("qa_edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("done")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
