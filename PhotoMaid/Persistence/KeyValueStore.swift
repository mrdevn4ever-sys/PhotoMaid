import Foundation
import PhotoMaidCore

/// Typisierte Schlüssel für App-Zustand in `CDKeyValue` (JSON). Eine Wahrheit je Zustand; Entscheidungen liegen nie hier.
struct StoreKey<Value: Codable & Sendable>: Sendable {
    let name: String
    let fallback: @Sendable () -> Value
    init(_ name: String, _ fallback: @escaping @Sendable () -> Value) {
        self.name = name
        self.fallback = fallback
    }
}

enum StoreKeys {
    static let settings = StoreKey<AppSettingsData>("app.settings") { AppSettingsData() }
    static let quickAccess = StoreKey<[QuickAccessItem]>("app.quickAccess") { QuickAccess.defaults }
    static let rewards = StoreKey<RewardLedger>("entitlements.rewards") { RewardLedger() }
    static let purchaseCache = StoreKey<PurchaseState>("entitlements.purchaseCache") { .unknown }
    static let collections = StoreKey<[SmartCollection]>("collections.custom") { [] }
    /// Schlagwörter je Medium (`localIdentifier` → Liste), nur PhotoMaid.
    static let tags = StoreKey<[String: [String]]>("organize.tags") { [:] }
    static let notes = StoreKey<[String: String]>("organize.notes") { [:] }
    /// Fingerabdrücke der Medien mit Schlagwort/Notiz/Korb (Wiederfinden nach Neuindizierung, `Rematch`).
    static let refs = StoreKey<[String: MediaRef]>("organize.refs") { [:] }
    /// Auswahlkorb (dauerhafter Arbeitsvorrat, ≠ Papierkorb).
    static let selectionBasket = StoreKey<[String]>("organize.basket") { [] }
    static let workflows = StoreKey<[Workflow]>("workflows.list") { [] }
    static let presets = StoreKey<[EditPreset]>("editor.presets") { [] }
    static let edits = StoreKey<[EditRecord]>("editor.records") { [] }
    static let collageDrafts = StoreKey<[CollageProject]>("studio.collageDrafts") { [] }
    static let videoDrafts = StoreKey<[VideoProject]>("studio.videoDrafts") { [] }
    static let feedAds = StoreKey<FeedAdState>("ads.feed") { FeedAdState() }
    static let gameRecords = StoreKey<PhotoGameRecords>("games.personalRecords.v1") { PhotoGameRecords() }
    /// Gemessene Mediengrößen (Bytes) je `localIdentifier` + Änderungsdatum. Nur lokal, nie gesichert.
    static let sizeCache = StoreKey<[String: SizeCacheEntry]>("cache.sizes") { [:] }
    /// Ergebnisse der lokalen Bildanalyse (Schärfe, Kategorie, erkannter Text) – nur lokal, nie gesichert.
    static let analysisCache = StoreKey<[String: AnalysisCacheEntry]>("cache.analysis") { [:] }
    static let archiveJournal = StoreKey<ArchiveJournal?>("archive.lastJournal") { nil }
    /// Vom Nutzer verbundene Ordner (security-scoped Bookmarks, nur lokal).
    static let sources = StoreKey<[ConnectedSource]>("sources.connected") { [] }
}

struct SizeCacheEntry: Codable, Hashable, Sendable {
    let bytes: Int64
    let modified: Date?
}

struct AnalysisCacheEntry: Codable, Hashable, Sendable {
    var modified: Date?
    var sharpness: Double?
    var category: PhotoCategory?
    var aesthetics: Float?
    var isUtility: Bool?
    var text: String?

    init(modified: Date? = nil, sharpness: Double? = nil, category: PhotoCategory? = nil,
         aesthetics: Float? = nil, isUtility: Bool? = nil, text: String? = nil) {
        self.modified = modified
        self.sharpness = sharpness
        self.category = category
        self.aesthetics = aesthetics
        self.isUtility = isUtility
        self.text = text
    }
}

/// Zugriff auf `CDKeyValue` mit Typen. Lesen nach dem Start einmal, Schreiben atomar je Schlüssel.
@MainActor
final class KeyValueStore {
    let core: CoreDataStore
    init(core: CoreDataStore) { self.core = core }

    func get<V>(_ key: StoreKey<V>) -> V { core.value(V.self, forKey: key.name) ?? key.fallback() }

    func set<V>(_ key: StoreKey<V>, _ value: V) throws { try core.setValue(value, forKey: key.name) }
}
