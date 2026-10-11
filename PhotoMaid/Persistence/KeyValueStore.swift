import Foundation
import PhotoMaidCore

struct StoreKey<Value: Codable & Sendable>: Sendable {
    let name: String
    let fallback: @Sendable () -> Value
    init(_ name: String, _ fallback: @escaping @Sendable () -> Value) {
        self.name = name; self.fallback = fallback
    }
}

enum StoreKeys {
    static let settings = StoreKey<AppSettingsData>("app.settings") { AppSettingsData() }
    static let quickAccess = StoreKey<[QuickAccessItem]>("app.quickAccess") { QuickAccess.defaults }
    static let rewards = StoreKey<RewardLedger>("entitlements.rewards") { RewardLedger() }
    static let purchaseCache = StoreKey<PurchaseState>("entitlements.purchaseCache") { .unknown }
    static let collections = StoreKey<[SmartCollection]>("collections.custom") { [] }
    static let tags = StoreKey<[String: [String]]>("organize.tags") { [:] }
    static let notes = StoreKey<[String: String]>("organize.notes") { [:] }
    static let refs = StoreKey<[String: MediaRef]>("organize.refs") { [:] }
    static let selectionBasket = StoreKey<[String]>("organize.basket") { [] }
    static let workflows = StoreKey<[Workflow]>("workflows.list") { [] }
    static let presets = StoreKey<[EditPreset]>("editor.presets") { [] }
    static let edits = StoreKey<[EditRecord]>("editor.records") { [] }
    static let collageDrafts = StoreKey<[CollageProject]>("studio.collageDrafts") { [] }
    static let videoDrafts = StoreKey<[VideoProject]>("studio.videoDrafts") { [] }
    static let feedAds = StoreKey<FeedAdState>("ads.feed") { FeedAdState() }
    static let sizeCache = StoreKey<[String: SizeCacheEntry]>("cache.sizes") { [:] }
    static let analysisCache = StoreKey<[String: AnalysisCacheEntry]>("cache.analysis") { [:] }
    static let archiveJournal = StoreKey<ArchiveJournal?>("archive.lastJournal") { nil }
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
        self.modified = modified; self.sharpness = sharpness; self.category = category
        self.aesthetics = aesthetics; self.isUtility = isUtility; self.text = text
    }
}

@MainActor
final class KeyValueStore {
    let core: CoreDataStore
    init(core: CoreDataStore) { self.core = core }

    /// Public reads cannot resurrect a private item through a stored ID or project.
    /// Hide an entire mixed project rather than rendering it with a missing input.
    func get<V>(_ key: StoreKey<V>) -> V {
        let raw = core.value(V.self, forKey: key.name) ?? key.fallback()
        let policy = VaultIsolation.shared.snapshot
        func allowed(_ id: String) -> Bool { policy.allows(id) }
        var filtered: Any = raw
        switch key.name {
        case StoreKeys.edits.name:
            if let values = raw as? [EditRecord] {
                filtered = values.filter { allowed($0.newId) && ($0.sourceId.isEmpty || allowed($0.sourceId)) }
            }
        case StoreKeys.collageDrafts.name:
            if let values = raw as? [CollageProject] {
                filtered = values.filter { policy.ready && $0.items.allSatisfy { allowed($0.mediaId) } }
            }
        case StoreKeys.videoDrafts.name:
            if let values = raw as? [VideoProject] {
                filtered = values.filter { policy.ready && $0.clips.allSatisfy { allowed($0.mediaId) } }
            }
        case StoreKeys.tags.name:
            if let values = raw as? [String: [String]] { filtered = values.filter { allowed($0.key) } }
        case StoreKeys.notes.name:
            if let values = raw as? [String: String] { filtered = values.filter { allowed($0.key) } }
        case StoreKeys.refs.name:
            if let values = raw as? [String: MediaRef] { filtered = values.filter { allowed($0.key) } }
        case StoreKeys.selectionBasket.name:
            if let values = raw as? [String] { filtered = values.filter(allowed) }
        case StoreKeys.sizeCache.name:
            if let values = raw as? [String: SizeCacheEntry] { filtered = values.filter { allowed($0.key) } }
        case StoreKeys.analysisCache.name:
            if let values = raw as? [String: AnalysisCacheEntry] { filtered = values.filter { allowed($0.key) } }
        case StoreKeys.settings.name:
            if var settings = raw as? AppSettingsData {
                settings.hiddenMedia = settings.hiddenMedia.filter(allowed)
                filtered = settings
            }
        case StoreKeys.archiveJournal.name:
            // Old archive journals have no complete provenance. Never present
            // their filenames as an alternate index into private media.
            if !policy.ready || policy.hasPrivateMedia { return key.fallback() }
        default: break
        }
        return filtered as? V ?? key.fallback()
    }

    /// Reserved for authenticated vault migration; never use in public views.
    func vaultMigrationValue<V>(_ key: StoreKey<V>) -> V {
        core.value(V.self, forKey: key.name) ?? key.fallback()
    }

    func set<V>(_ key: StoreKey<V>, _ value: V) throws { try core.setValue(value, forKey: key.name) }
}
