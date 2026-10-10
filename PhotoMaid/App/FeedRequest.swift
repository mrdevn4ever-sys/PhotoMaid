import Foundation
import PhotoMaidCore

/// Anfrage an den Feed: Quelle der Warteschlange (Port von Android `FeedRequest`).
/// Eine Quelle liefert nur Kandidaten; was noch offen ist, entscheidet immer der globale Ledger.
struct FeedRequest: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case category(MediaCategory)
        /// Gemeinsamer Feed aller offenen Medien – „Jetzt aufräumen“ auf Heute.
        case allMedia
        case due
        /// Dauerhafte Sammlung: beim Öffnen frisch ausgewertet.
        case collection(SmartCollection)
        /// Feste Liste (Papierkorb ansehen, Analyse-Ergebnis, Auswahl). Keine Neuordnung.
        case items([ItemReference], titleKey: String)
        /// Schnellzugriff von „Heute“: nur eine Abfrage.
        case quick(QuickAccessItem)
        /// Ein Kalendermonat. `again` = „Erneut durchsehen“: auch bereits entschiedene Medien.
        case month(MonthKey, again: Bool)
        /// Auf diesem iPhone hinzugekommen seit dem Ende der letzten Sitzung.
        case newSince
        /// Album der Fotos-App (E5).
        case album(id: String, title: String)
    }

    let id: UUID
    let source: Source

    init(_ source: Source, id: UUID = UUID()) {
        self.source = source
        self.id = id
    }

    /// Reihenfolge darf gewechselt werden (nicht für feste Listen wie Papierkorb oder „Wieder dran“).
    var isOrderable: Bool {
        switch source {
        case .items, .due: false
        // „Zufällig“ behält die gemischte Reihenfolge.
        case .quick(let q): q.kind.isOrderable
        default: true
        }
    }

    var title: String {
        switch source {
        case .category(.photos): L("feed_title_photos")
        case .category(.videos): L("feed_title_videos")
        case .category(.screenshots): L("feed_title_screenshots")
        case .allMedia: L("feed_title_all")
        case .due: L("feed_title_due")
        case .collection(let c): CollectionText.title(c)
        case .items(_, let key): L(key)
        case .quick(let q): QuickAccessText.title(q)
        case .month(let m, _): MonthText.title(m)
        case .newSince: L("feed_title_new")
        case .album(_, let title): title
        }
    }
}
