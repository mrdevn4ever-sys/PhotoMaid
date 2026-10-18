import Foundation
import Observation
import Photos
import PhotoMaidCore
import SwiftUI

enum AppTab: String, Hashable, CaseIterable, Sendable {
    case today, library, cleanup, studio, history
}

enum CleanupRunResult: Sendable {
    case finished(OperationIntent)
    case rejected(CleanupError)
    /// Systemoperation lief, das Ergebnis ist unklar: beim nächsten Start ohne erneutes Löschen abgleichen.
    case needsReconciliation
}

/// Abgeleitete Lesemodelle (nach jeder Mutation aus dem Ledger neu berechnet, abseits des Main-Threads).
struct LedgerReadModel: Sendable {
    var records: [ItemReference: ItemRecord] = [:]
    var basket: [ItemRecord] = []
    var laterRecords: [ItemRecord] = []
    var events: [DecisionEvent] = []
    var allowance: AllowanceSnapshot?
    var canUndo = false
    var reconciliationNeeded: [OperationIntent] = []
}

/// Stand der Mediathek (einmal geladen, nach jeder Änderung neu). Nur Beschreibungen, keine Bilder.
struct LibrarySnapshot: Sendable {
    var all: [MediaAsset] = []
    var byID: [String: MediaAsset] = [:]
    var hiddenAlbumMembers: Set<String> = []
    var excludedAlbumMembers: Set<String> = []
    var loaded = false
}

/// Zentrale App-Instanz: Abhängigkeiten und abgeleitete Lesemodelle (Port von Android `AppModel`).
/// Zustandsändernde Entscheidungen laufen ausschließlich über den `DecisionLedger`.
@MainActor
@Observable
final class AppModel {
    @ObservationIgnored let kv: KeyValueStore?
    @ObservationIgnored let ledger: DecisionLedger
    let library: PhotoLibraryService
    let purchases: StoreKitGateway
    let reminders: ReminderScheduler
    let player: FeedPlayer
    let gameScores: PhotoGameScores
    let memory: PhotoMemoryModel
    let snake: PhotoSnakeModel
    let blocks: PhotoBlocksModel
    @ObservationIgnored let sizer: MediaSizer
    @ObservationIgnored let previews: PreviewPipeline
    @ObservationIgnored let bytes = PhotoResourceByteProvider()
    let organize: OrganizeStore
    let sources: ConnectedSourceStore
    let files = FileIndex()
    let isQAFixtureMode: Bool

    private(set) var settings: AppSettingsData
    private(set) var quickAccess: [QuickAccessItem]
    private(set) var rewards: RewardLedger
    private(set) var customCollections: [SmartCollection]
    private(set) var read = LedgerReadModel()
    /// Never show an all-open library before persistent decisions have been loaded.
    private(set) var readReady = false
    private(set) var snapshot = LibrarySnapshot()
    /// Tab „Fotos“: alles außer „In PhotoMaid ausgeblendet“.
    private(set) var visibleMedia: [MediaAsset] = []
    /// Aufräumen, Zahlen, Sammlungen, Monate: zusätzlich ohne ausgenommene Alben.
    private(set) var cleanupMedia: [MediaAsset] = []
    /// Noch zu prüfen – dieselbe Regel wie der Feed (`ReviewQueues.normalQueue`). Einzige Quelle für „Heute“.
    private(set) var pending: [ItemReference] = []
    private(set) var skippedPreviews: Set<ItemReference> = []
    private(set) var now = Date()
    private(set) var isLoadingLibrary = false
    /// Erhöht sich, wenn sich der Bestand der Medien ändert (neu/entfernt/ausgeblendet/ausgenommen) – nicht bei bloßen
    /// Inhaltsänderungen einzelner Medien. Langlaufende Arbeit (Analyse) passt nur ihren Umfang an und läuft weiter.
    private(set) var mediaRevision = 0
    /// Last non-sensitive file-provider failure code, reset before each cleanup request.
    /// Exposed only to explain failures; never contains file names or paths.
    private(set) var lastFileCleanupFailureCode: String?

    var toast: ToastMessage?
    var selectedTab: AppTab = .today
    /// Geöffneter Entscheidungs-Feed (Vollbild über den Tabs).
    var feed: FeedRequest?
    /// Einmaliger Wunsch aus Schnellaktion/„Öffnen in“ (wird von RootView ausgewertet).
    var pendingRoute: AppRoute?
    /// Vollbild über den Tabs (Betrachter, Editor, Diashow, Scanner).
    var fullScreen: FullScreenRequest?
    /// Navigationsverlauf je Tab (eigener Zurück-Stapel, bleibt beim Tabwechsel erhalten).
    var paths: [AppTab: [Route]] = [:]

    @ObservationIgnored private var recoveredThisProcess = false
    @ObservationIgnored private var cleanupInFlight = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var patchTask: Task<Void, Never>?
    @ObservationIgnored private var reloadAfterLoad = false
    @ObservationIgnored private var publishDebounce: Task<Void, Never>?
    @ObservationIgnored private var feedAds: FeedAdState?
    @ObservationIgnored private var publishCoalescer = ChangeCoalescer(quiet: 0.6, maxDelay: 2.5)
    @ObservationIgnored private var loadedToken = -1
    /// Gestartete Mediathek-Abfragen (fortlaufend).
    @ObservationIgnored private var loadGeneration = 0
    /// Gerade bestätigt gelöschte Fotos: keine Kandidaten, bis eine NACH der Löschung gestartete Abfrage vorliegt –
    /// ältere Stände enthalten sie noch. Danach gilt K5: Ist ein Foto wieder da, wurde es zurückgeholt und ist offen.
    @ObservationIgnored private var removedAwaitingReload: Set<ItemReference> = []
    @ObservationIgnored private var removedHeldAtGeneration = 0
    @ObservationIgnored private var readGeneration = 0
    @ObservationIgnored private var queueInputsRevision = 0
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    var today: LocalDay { LocalDay(now, timeZone: .autoupdatingCurrent) }

    init(kv: KeyValueStore?, persistence: any LedgerPersistence, qa: Bool) throws {
        self.kv = kv
        self.isQAFixtureMode = qa
        let scores = PhotoGameScores(records: kv?.get(StoreKeys.gameRecords) ?? .init()) { records in
            try kv?.set(StoreKeys.gameRecords, records)
        }
        gameScores = scores
        let memoryModel = PhotoMemoryModel(scores: scores)
        let snakeDirectory = qa ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SnakePhotos", isDirectory: true)
        let snakeModel = PhotoSnakeModel(scores: scores, gallery: SnakePhotoLibrary(directory: snakeDirectory),
                                        preferences: kv?.get(StoreKeys.snakePreferences) ?? .init()) { preferences in
            try kv?.set(StoreKeys.snakePreferences, preferences)
        }
        memoryModel.photos.updateVisibility([])
        snakeModel.photos.updateVisibility([])
        memory = memoryModel
        snake = snakeModel
        let blocksModel = PhotoBlocksModel(archive: kv?.get(StoreKeys.blocksArchive) ?? .init()) { archive in
            try kv?.set(StoreKeys.blocksArchive, archive)
        }
        blocksModel.photos.updateVisibility([])
        blocks = blocksModel
        ledger = try DecisionLedger(persistence: persistence)
        library = PhotoLibraryService()
        purchases = StoreKitGateway(productID: AppConfig.proProductID, kv: kv)
        reminders = ReminderScheduler()
        player = FeedPlayer()
        previews = PreviewPipeline(manager: PHCachingImageManager())
        organize = OrganizeStore(kv: kv)
        sources = ConnectedSourceStore(kv: kv)
        settings = kv?.get(StoreKeys.settings) ?? AppSettingsData()
        quickAccess = QuickAccess.sanitize(kv?.get(StoreKeys.quickAccess) ?? QuickAccess.defaults)
        rewards = kv?.get(StoreKeys.rewards) ?? RewardLedger()
        customCollections = kv?.get(StoreKeys.collections) ?? []
        skippedPreviews = kv?.get(StoreKeys.skippedPreviews) ?? []
        // Größen in SQLite (einzelne Einträge statt eines großen JSON-Blocks); der alte Block wird einmal übernommen.
        let sizeIndex = SizeIndexDatabase.shared()
        let legacySizes = kv?.get(StoreKeys.sizeCache) ?? [:]
        sizer = MediaSizer(db: sizeIndex, legacy: legacySizes)
        if sizeIndex != nil, !legacySizes.isEmpty { try? kv?.set(StoreKeys.sizeCache, [:]) }
        if settings.firstSeenDay == nil {
            settings.firstSeenDay = today
            try? kv?.set(StoreKeys.settings, settings)
        }
        Haptics.enabled = settings.haptics
    }

    /// Produktion: Core Data. Schlägt das Laden fehl, gibt es keine Ersatz-Wahrheit (sonst gingen Entscheidungen verloren).
    static func bootstrap() -> Result<AppModel, BootstrapError> {
        #if QA_FIXTURES
        if ProcessInfo.processInfo.arguments.contains("-qa-fixtures") {
            do {
                let model = try AppModel(kv: nil, persistence: InMemoryLedgerPersistence(), qa: true)
                return .success(model)
            } catch {
                return .failure(.ledger)
            }
        }
        #endif
        do {
            let core = try CoreDataStore()
            let model = try AppModel(kv: KeyValueStore(core: core), persistence: CoreDataLedgerPersistence(store: core), qa: false)
            return .success(model)
        } catch is CoreDataStore.StoreError {
            Diagnostics.log(.persistence, "store-load-failed")
            return .failure(.store)
        } catch {
            Diagnostics.error(.persistence, "ledger-load-failed", error)
            return .failure(.ledger)
        }
    }

    enum BootstrapError: Error { case store, ledger }

    // MARK: Fähigkeiten

    /// Einzige Stelle für Free/Pro in der App. Werbung/Rewarded sind auf iOS aus (E1).
    var capabilities: Capabilities {
        let c = Capabilities.resolve(purchase: purchases.state, rewards: rewards, now: now)
        return Capabilities(tier: c.tier, adsAllowed: c.adsAllowed && AppConfig.adsEnabled,
                            rewardRemaining: c.rewardRemaining, cleanupBonus: c.cleanupBonus)
    }

    // MARK: Lebenszyklus

    /// Start/Resume: Berechtigungen neu prüfen, Kaufstatus, offene Operationen klären, Lesemodelle laden.
    func onForeground() async {
        now = Date()
        library.refreshAccess()
        // The persisted review decisions must be published before requesting
        // StoreKit products or refreshing reminders. Either may suspend while
        // PhotoKit finishes loading: without this order, a briefly empty read
        // model can make every photo appear as "not reviewed" on Today.
        await publishRead()
        reloadLibraryIfNeeded()

        await reminders.refresh()
        let previousPurchase = purchases.state
        await purchases.refresh()
        var didRecover = false
        if !recoveredThisProcess && !cleanupInFlight {
            recoveredThisProcess = true
            await recoverOperations()
            didRecover = true
        }
        // Skip a second full 37k-asset queue rebuild if neither the purchase
        // capabilities nor the operation journal could have changed.
        if didRecover || purchases.state != previousPurchase {
            await publishRead()
        }
    }

    func tick() { now = Date() }

    /// Mediathek neu lesen, wenn sie sich geändert hat (Änderungsbeobachter) oder noch nicht geladen ist.
    func reloadLibraryIfNeeded(force: Bool = false) {
        guard library.access.canRead else {
            snapshot = LibrarySnapshot(loaded: true)
            rebuildFiltered()
            return
        }
        let token = library.changeToken
        guard force || token != loadedToken || !snapshot.loaded else { return }
        loadedToken = token
        let changes = LibraryChangeTracker.shared.take()
        if !force, snapshot.loaded {
            // Läuft schon ein Neuladen: nicht abbrechen (bei Dauermeldungen würde es nie fertig), danach noch einmal.
            if isLoadingLibrary {
                if !changes.isEmpty { reloadAfterLoad = true }
                return
            }
            // Nur geänderte Medien (Favorit, bearbeitet, iCloud-Abgleich …): diese aktualisieren, nichts neu laden.
            let albumsMatter = !settings.hiddenAlbums.isEmpty || !settings.excludedAlbums.isEmpty
            switch changes.reaction(albumsMatter: albumsMatter) {
            case .none: return
            case .patch(let ids): patchAssets(ids); return
            case .reload: break
            }
        }
        reloadAfterLoad = false
        loadTask?.cancel()
        patchTask?.cancel()
        isLoadingLibrary = true
        loadGeneration += 1
        let generation = loadGeneration
        let hiddenAlbums = settings.hiddenAlbums
        let excluded = settings.excludedAlbums
        loadTask = Task { [weak self] in
            let all = await PhotoLibraryService.loadAll()
            let (hidden, excl) = await Task.detached(priority: .userInitiated) { () -> (Set<String>, Set<String>) in
                var h = Set<String>(), e = Set<String>()
                for id in hiddenAlbums { h.formUnion(PhotoLibraryService.assetIDs(inCollection: id)) }
                for id in excluded { e.formUnion(PhotoLibraryService.assetIDs(inCollection: id)) }
                return (h, e)
            }.value
            guard let self, !Task.isCancelled else { return }
            var s = LibrarySnapshot(all: all, hiddenAlbumMembers: hidden, excludedAlbumMembers: excl, loaded: true)
            s.byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            self.snapshot = s
            self.isLoadingLibrary = false
            if generation > self.removedHeldAtGeneration { self.removedAwaitingReload = [] }
            self.rebuildFiltered()
            if self.reloadAfterLoad { self.reloadLibraryIfNeeded(force: true) }
        }
    }

    /// Geänderte Medien neu beschreiben, ohne die Mediathek neu zu laden (Bestand und Warteschlange bleiben gleich).
    private func patchAssets(_ ids: Set<String>) {
        let generation = loadGeneration
        let previous = patchTask
        patchTask = Task { [weak self] in
            await previous?.value // der Reihe nach: ein älterer Stand überschreibt nie einen neueren
            let fresh = await Task.detached(priority: .utility) { PhotoLibraryService.describeAssets(Array(ids)) }.value
            guard let self, !Task.isCancelled, generation == self.loadGeneration, !fresh.isEmpty else { return }
            var updates: [String: MediaAsset] = [:]
            for a in fresh where self.snapshot.byID[a.id] != nil && self.snapshot.byID[a.id] != a { updates[a.id] = a }
            guard !updates.isEmpty else { return }
            var s = self.snapshot
            for i in s.all.indices { if let a = updates[s.all[i].id] { s.all[i] = a } }
            for (id, a) in updates { s.byID[id] = a }
            self.snapshot = s
            self.visibleMedia = self.visibleMedia.map { updates[$0.id] ?? $0 }
            self.cleanupMedia = self.cleanupMedia.map { updates[$0.id] ?? $0 }
        }
    }

    private func rebuildFiltered() {
        queueInputsRevision += 1
        mediaRevision += 1
        let hiddenIDs = Set(settings.hiddenMedia)
        let hiddenAlbum = snapshot.hiddenAlbumMembers
        let excluded = snapshot.excludedAlbumMembers
        visibleMedia = snapshot.all.filter { !hiddenIDs.contains($0.id) && !hiddenAlbum.contains($0.id) }
        let gamePhotos = Set(visibleMedia.filter { !$0.isVideo }.map(\.id))
        memory.photos.updateVisibility(gamePhotos)
        snake.photos.updateVisibility(gamePhotos)
        memory.validatePhotos()
        snake.validatePhotos()
        let held = removedAwaitingReload
        cleanupMedia = excluded.isEmpty && held.isEmpty ? visibleMedia
            : visibleMedia.filter { !excluded.contains($0.id) && !held.contains($0.reference) }
        blocks.refreshPhotos(app: self)
        rebuildPending()
    }

    private func rebuildPending() {
        guard readReady else { pending = []; return }
        pending = ReviewQueues.normalQueue(candidates: cleanupMedia.map(\.reference).filter { !skippedPreviews.contains($0) }, records: read.records,
                                           session: ReviewSessionID(), today: today)
    }

    func asset(_ id: String) -> MediaAsset? { snapshot.byID[id] ?? library.asset(id) }

    func assets(_ refs: [ItemReference]) -> [MediaAsset] {
        var missing: [String] = []
        var out: [String: MediaAsset] = [:]
        for r in refs where r.provider == .photoLibrary {
            if let a = snapshot.byID[r.localIdentifier] { out[a.id] = a } else { missing.append(r.localIdentifier) }
        }
        for a in library.assets(ids: missing) { out[a.id] = a }
        return refs.compactMap { out[$0.localIdentifier] }
    }

    func record(_ item: ItemReference) -> ItemRecord { read.records[item] ?? ItemRecord(item: item) }

    func makeBackup() async -> PhotoMaidBackup {
        let state = await ledger.snapshotState()
        var backup = PhotoMaidBackup(createdAt: Int64(Date().timeIntervalSince1970 * 1000), appVersion: AppConfig.appVersion)
        var table = BackupRefTable()
        // Medien im Tresor gehören in keine öffentliche Sicherung (auch nicht als Kennung).
        let concealment = VaultConcealment.shared
        let visible: (String) -> Bool = { !concealment.isConcealed($0) }
        for record in state.records.values where record.item.provider == .photoLibrary && visible(record.item.localIdentifier) {
            guard let backupState = BackupRules.state(record.disposition) else { continue }
            let media = organize.refs[record.item.localIdentifier]
                ?? MediaRef(id: record.item.localIdentifier, name: nil, size: nil, takenMillis: nil)
            let index = table.add(media)
            backup.decisions.append(BackupDecision(ref: index, state: backupState, due: record.dueDay,
                                                   bookmarked: record.bookmarked))
        }
        for (id, tags) in organize.tags where visible(id) {
            let index = table.add(organize.refs[id] ?? MediaRef(id: id, name: nil, size: nil, takenMillis: nil))
            backup.tags[index] = tags
        }
        for (id, note) in organize.notes where visible(id) {
            let index = table.add(organize.refs[id] ?? MediaRef(id: id, name: nil, size: nil, takenMillis: nil))
            backup.notes[index] = note
        }
        backup.basket = organize.basket.filter(visible).map {
            table.add(organize.refs[$0] ?? MediaRef(id: $0, name: nil, size: nil, takenMillis: nil))
        }
        backup.hiddenMedia = settings.hiddenMedia.filter(visible).map {
            table.add(organize.refs[$0] ?? MediaRef(id: $0, name: nil, size: nil, takenMillis: nil))
        }
        backup.refs = table.refs
        return backup
    }

    /// Medien liegen jetzt im Tresor (E16): in PhotoMaid nirgends mehr zeigen. Papierkorb- und Später-Einträge
    /// aufheben, aus Auswahlkorb und Entwürfen nehmen, Vorschaubilder vergessen, Mediathek und Lesemodell neu laden.
    /// Gilt auch, wenn iOS das Löschen in der Fotos-App nicht bestätigt hat.
    func applyVaultConcealment(_ ids: Set<String>) async {
        guard !ids.isEmpty else { return }
        blocks.invalidatePhotos()
        memory.validatePhotos()
        snake.validatePhotos()
        for id in ids {
            let ref = ItemReference.photo(id)
            switch record(ref).disposition {
            case .markedForCleanup: await decide(ref, .unmark)
            case .later: await decide(ref, .removeDeferral)
            default: break
            }
        }
        organize.removeFromBasket(Array(ids))
        if let kv {
            let collages = kv.get(StoreKeys.collageDrafts)
            let cleanedCollages = collages.compactMap { draft -> CollageProject? in
                guard draft.items.contains(where: { ids.contains($0.mediaId) }) else { return draft }
                var p = draft
                for i in p.items.indices.reversed() where ids.contains(p.items[i].mediaId) { p = p.removeItem(i) }
                return p.items.contains(where: { ids.contains($0.mediaId) }) ? nil : p
            }
            if cleanedCollages != collages { try? kv.set(StoreKeys.collageDrafts, cleanedCollages) }
            let movies = kv.get(StoreKeys.videoDrafts)
            let cleanedMovies = movies.map { project in
                project.clips.contains(where: { ids.contains($0.mediaId) })
                    ? project.withClips(project.clips.filter { !ids.contains($0.mediaId) }) : project
            }
            if cleanedMovies != movies { try? kv.set(StoreKeys.videoDrafts, cleanedMovies) }
            // Ergebnisse der Bildanalyse (u. a. erkannter Text) der verborgenen Medien verwerfen.
            var analysis = kv.get(StoreKeys.analysisCache)
            if analysis.keys.contains(where: ids.contains) {
                for id in ids { analysis[id] = nil }
                try? kv.set(StoreKeys.analysisCache, analysis)
            }
        }
        ThumbnailLoader.shared.clear()
        previews.forgetCache()
        reloadLibraryIfNeeded(force: true)
        await refreshVaultConcealment()
    }

    /// Nach Änderungen am Tresor (z. B. beim Schließen): Dateien im Tresor im Bereich „Dateien“ ausblenden bzw. wieder
    /// zeigen; ihre Papierkorb-/Später-Einträge aufheben. Danach Lesemodell neu.
    func refreshVaultConcealment() async {
        files.applyConcealment()
        for ref in files.concealedReferences {
            switch record(ref).disposition {
            case .markedForCleanup: await decide(ref, .unmark)
            case .later: await decide(ref, .removeDeferral)
            default: break
            }
        }
        await publishRead()
    }

    var dueCount: Int {
        read.laterRecords.filter { if case .due = ReviewQueues.laterStatus($0, today: today) { true } else { false } }.count
    }

    // MARK: Lesemodell

    /// Serialisiert über eine Generation: ein langsamerer, älterer Lauf überschreibt nie einen neueren.
    func publishRead() async {
        readGeneration += 1
        let generation = readGeneration
        let state = await ledger.snapshotState()
        let limit = capabilities.dailyCleanupLimit
        let day = today
        // Rebuilding the full review queue for a large library is O(n). Perform
        // it alongside the ledger projection off the main actor rather than
        // blocking SwiftUI while the swipe-out animation is running.
        let candidates = cleanupMedia.map(\.reference).filter { !skippedPreviews.contains($0) }
        let queueRevision = queueInputsRevision
        let hiddenFiles = files.concealedReferences
        let derived = await Task.detached(priority: .userInitiated) { () -> (LedgerReadModel, [ItemReference]) in
            // Medien und Dateien im Tresor erscheinen weder im Papierkorb noch unter „Später“ noch im Verlauf (E16).
            let concealment = VaultConcealment.shared
            let hidden: (ItemReference) -> Bool = { ref in
                ref.provider == .photoLibrary ? concealment.isConcealed(ref.localIdentifier) : hiddenFiles.contains(ref)
            }
            let anyHidden = !concealment.isEmpty
            let view = LedgerReadModel(
                records: state.records,
                basket: state.records.values.filter { $0.disposition == .markedForCleanup && !(anyHidden && hidden($0.item)) }
                    .sorted { $0.item.description < $1.item.description },
                laterRecords: state.records.values.filter { $0.disposition == .later && !(anyHidden && hidden($0.item)) },
                events: anyHidden ? state.events.filter { !hidden($0.item) } : state.events,
                allowance: DecisionLedger.allowance(in: state, day: day, limit: limit),
                canUndo: !state.undoStack.isEmpty,
                reconciliationNeeded: state.intents.values.filter { $0.state == .reconciliationRequired })
            let queue = ReviewQueues.normalQueue(candidates: candidates, records: state.records,
                                                 session: ReviewSessionID(), today: day)
            return (view, queue)
        }.value
        guard generation == readGeneration else { return }
        read = derived.0
        readReady = true
        // PhotoKit may have reloaded the library while the detached queue was
        // building. In that rare case use the latest visible media and ledger.
        if queueInputsRevision == queueRevision {
            pending = derived.1
        } else {
            rebuildPending()
        }
    }

    // MARK: Einstellungen und kleine Stores

    func updateSettings(_ change: (inout AppSettingsData) -> Void) {
        var s = settings
        change(&s)
        guard s != settings else { return }
        do {
            try kv?.set(StoreKeys.settings, s)
            let filterChanged = s.hiddenMedia != settings.hiddenMedia
            let albumsChanged = s.hiddenAlbums != settings.hiddenAlbums || s.excludedAlbums != settings.excludedAlbums
            settings = s
            Haptics.enabled = s.haptics
            if albumsChanged { reloadLibraryIfNeeded(force: true) } else if filterChanged { rebuildFiltered() }
        } catch {
            showError(L("error_settings_not_saved"))
        }
    }

    func setQuickAccess(_ list: [QuickAccessItem]) {
        let clean = QuickAccess.sanitize(list)
        do { try kv?.set(StoreKeys.quickAccess, clean); quickAccess = clean } catch { showError(L("error_settings_not_saved")) }
    }

    func setCustomCollections(_ list: [SmartCollection]) {
        do { try kv?.set(StoreKeys.collections, list); customCollections = list } catch { showError(L("error_settings_not_saved")) }
    }

    // MARK: Meldungen

    func showToast(_ text: String, actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        present(ToastMessage(text: text, actionTitle: actionTitle, action: action))
    }

    func showError(_ text: String) {
        Haptics.error()
        present(ToastMessage(text: text, isError: true))
    }

    private func present(_ t: ToastMessage) {
        toast = t
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(t.actionTitle == nil ? 3 : 5))
            guard !Task.isCancelled, self?.toast?.id == t.id else { return }
            self?.toast = nil
        }
    }

    // MARK: Entscheidungen

    @discardableResult
    /// - Parameter deferPublish: Feed: nicht auf das neue Lesemodell warten (bei 30 000 Medien spürbar), sondern es
    ///   nach kurzer Ruhe einmal für alle schnellen Entscheidungen berechnen (`schedulePublishRead`). Gespeichert ist
    ///   die Entscheidung in beiden Fällen, bevor diese Funktion zurückkehrt.
    func apply(_ command: DecisionCommand, session: ReviewSessionID? = nil,
               deferPublish: Bool = false) async throws -> CommitOutcome {
        let out = try await ledger.apply(command, sessionID: session)
        if deferPublish { schedulePublishRead() } else { await publishRead() }
        return out
    }

    /// Lesemodell bald neu berechnen: nach 0,6 s Ruhe, spätestens nach 2,5 s. Viele schnelle Wische ergeben eine
    /// Berechnung – der Hauptthread bleibt während des Wischens frei.
    func schedulePublishRead() {
        let wait = publishCoalescer.register(now: ProcessInfo.processInfo.systemUptime)
        publishDebounce?.cancel()
        publishDebounce = Task { [weak self] in
            if wait > 0 {
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
            guard let self else { return }
            self.publishCoalescer.flushed()
            self.publishDebounce = nil
            await self.publishRead()
        }
    }

    // MARK: Werbung (nur Gratis, E19)

    /// Eine Entscheidung im Feed gezählt. `true`: jetzt ist eine Werbekarte fällig (nach jeder 50. Entscheidung).
    /// Nur eine Zahl wird gespeichert – nie Medien oder Kennungen.
    func countFeedDecisionForAds() -> (due: Bool, untilDue: Int) {
        guard AdsService.shared.allowed(self) else { return (false, .max) }
        var state = feedAds ?? kv?.get(StoreKeys.feedAds) ?? FeedAdState()
        state = FeedAdPolicy.onDecision(state)
        feedAds = state
        try? kv?.set(StoreKeys.feedAds, state)
        let due = FeedAdPolicy.isDue(state, today: today, nowMs: Int64(Date().timeIntervalSince1970 * 1000))
        return (due, max(0, FeedAdPolicy.interval - state.sinceLastAd))
    }

    /// Werbekarte wurde gezeigt: Takt beginnt neu.
    func feedAdCardShown() {
        let state = FeedAdPolicy.onCardShown(feedAds ?? kv?.get(StoreKeys.feedAds) ?? FeedAdState(), today: today,
                                             nowMs: Int64(Date().timeIntervalSince1970 * 1000))
        feedAds = state
        try? kv?.set(StoreKeys.feedAds, state)
    }

    /// „+100 für heute“ nach bestätigter Belohnung (idempotent über die Kennung). `false`: nichts freigeschaltet.
    func grantLimitBonus(rewardID: String) async -> Bool {
        var ledger = rewards
        do {
            try ledger.grantBonus(rewardID: rewardID, now: Date(), timeZone: .autoupdatingCurrent, purchase: purchases.state)
            try kv?.set(StoreKeys.rewards, ledger)
        } catch {
            return false
        }
        rewards = ledger
        now = Date() // der Bonus gilt ab jetzt (Fähigkeiten rechnen mit `now`)
        await publishRead()
        return true
    }

    /// Noch ausstehende, aufgeschobene Berechnung sofort ausführen (z. B. beim Schließen des Feeds).
    func flushPendingPublish() {
        guard let pending = publishDebounce else { return }
        pending.cancel()
        publishDebounce = nil
        publishCoalescer.flushed()
        Task { await publishRead() }
    }

    /// Entscheidung außerhalb des Feeds (Papierkorb zurücklegen, Später entfernen). Immer mit aktueller Revision.
    func decide(_ item: ItemReference, _ action: DecisionAction) async {
        do {
            let r = await ledger.record(for: item)
            try await apply(DecisionCommand(item: item, expectedRevision: r.revision, action: action))
        } catch {
            showError(L("error_change_not_saved"))
            await publishRead()
        }
    }

    func decideMany(_ items: [ItemReference], _ action: DecisionAction) async -> Int {
        var failed = 0
        for item in items {
            do {
                let r = await ledger.record(for: item)
                _ = try await ledger.apply(DecisionCommand(item: item, expectedRevision: r.revision, action: action))
            } catch {
                failed += 1
            }
        }
        await publishRead()
        if failed > 0 { showError(L("error_change_not_saved")) }
        return items.count - failed
    }

    func undo() async -> ItemRecord? {
        do {
            let r = try await ledger.undo()
            await publishRead()
            return r
        } catch DecisionError.undoConflict {
            showError(L("error_undo_conflict"))
        } catch DecisionError.itemBusy {
            showError(L("error_undo_busy"))
        } catch {
            showError(L("error_undo_generic"))
        }
        await publishRead()
        return nil
    }

    // MARK: Bereinigung

    /// Entdecken → Entscheiden → Papierkorb prüfen → Bestätigen → Systemoperation → Nachprüfen → Abgleichen → Verlauf.
    /// Je Aufruf genau EIN Anbieter: Fotos (`deleteAssets`, Systembestätigung, „Zuletzt gelöscht“) oder Dateien
    /// (endgültig, nach eigener deutlicher Bestätigung).
    func runCleanup(_ items: [ItemReference], kind: CleanupOperationKind) async -> CleanupRunResult {
        lastFileCleanupFailureCode = nil
        cleanupInFlight = true
        defer { cleanupInFlight = false }
        let selected = items.filter { kind == .photoLibraryDelete ? $0.provider == .photoLibrary : $0.provider != .photoLibrary }
        let intent: OperationIntent
        do {
            intent = try await ledger.prepareCleanup(selected, kind: kind, dailyLimit: capabilities.dailyCleanupLimit,
                                                     aliasKeys: aliasKeys(selected))
            try await ledger.markSubmitted(intent.id)
        } catch let e as CleanupError {
            await publishRead()
            return .rejected(e)
        } catch {
            await publishRead()
            return .rejected(.persistenceFailed(String(describing: error)))
        }
        player.stop()
        Diagnostics.log(.cleanup, "submitted kind=\(kind.rawValue) n=\(selected.count)")
        let outcome: OperationOutcome
        switch kind {
        case .photoLibraryDelete:
            outcome = await library.delete(ids: selected.map(\.localIdentifier))
        case .fileDeletePermanently, .fileMoveToTrash:
            outcome = FileOperations.deletePermanently(selected, sources: sources)
            if case .failed(let reason) = outcome {
                lastFileCleanupFailureCode = reason
            }
        }
        do {
            let done = try await ledger.reconcile(intent.id, outcome: outcome)
            Diagnostics.log(.cleanup, "reconciled \(done.state.rawValue)")
            if kind == .photoLibraryDelete {
                removedAwaitingReload.formUnion(selected)
                removedHeldAtGeneration = loadGeneration
                rebuildFiltered()
            }
            await publishRead()
            if kind == .photoLibraryDelete {
                library.bumpChangeToken()
                reloadLibraryIfNeeded()
            } else {
                await files.scan(sources)
            }
            return .finished(done)
        } catch {
            Diagnostics.error(.cleanup, "reconcile-failed", error)
            await publishRead()
            return .needsReconciliation
        }
    }

    /// Dieselbe Datei über mehrere verbundene Ordner zählt nur einmal (Datei-Ressourcen-ID).
    private func aliasKeys(_ items: [ItemReference]) -> [ItemReference: String] {
        var out: [ItemReference: String] = [:]
        for e in files.entries where items.contains(e.reference) {
            if let key = e.aliasKey { out[e.reference] = key }
        }
        return out
    }

    /// Nach Absturz während einer Löschung: nur über Existenzprüfung klären, nie automatisch erneut löschen.
    private func recoverOperations() async {
        guard let open = try? await ledger.recoverAfterLaunch() else { return }
        for intent in open where intent.state == .reconciliationRequired {
            let refs = Array(intent.items.keys)
            var probes = library.probe(refs.filter { $0.provider == .photoLibrary }.map(\.localIdentifier))
            for (k, v) in FileOperations.probe(refs.filter { $0.provider != .photoLibrary }, sources: sources) { probes[k] = v }
            _ = try? await ledger.resolveReconciliation(intent.id, probes: probes)
        }
    }

    /// Gesparte Bytes der bestätigt entfernten Medien: gemessene Größen; ohne Messung (z. B. nur in iCloud) die
    /// Schätzung, dann ist die Zahl „ca.“ (E17). Unbekannt zählt nie als 0.
    func recordSavings(_ removed: Set<ItemReference>, sizes: [ItemReference: KnownSize],
                       estimates: [ItemReference: Int64] = [:]) -> CleanupSavings {
        let s = CleanupSavings.of(removed: removed, sizes: sizes, estimates: estimates)
        let total = SavingsTotal(bytes: settings.savedTotalBytes, lowerBound: settings.savedTotalLowerBound,
                                 approximate: settings.savedTotalApproximate).adding(s)
        updateSettings {
            $0.savedTotalBytes = total.bytes
            $0.savedTotalLowerBound = total.lowerBound
            $0.savedTotalApproximate = total.approximate
        }
        return s
    }

    /// Größenschätzung für Medien/Dateien ohne Messung (immer als „ca.“ gezeigt, E17). Kalibriert aus den eigenen
    /// Messungen, höchstens alle 10 Minuten neu; bis dahin gelten Richtwerte.
    private(set) var estimator = SizeEstimator()
    @ObservationIgnored private var estimatorAt: Date?

    func refreshSizeEstimator() async {
        if let at = estimatorAt, Date().timeIntervalSince(at) < 600 { return }
        estimatorAt = Date()
        let media = visibleMedia
        let records = await sizer.records(for: media)
        let files = self.files.entries
        estimator = await Task.detached(priority: .utility) {
            SizeEstimator.calibrated(media: media, records: records, files: files)
        }.value
    }

    /// Gemessen, sonst geschätzt („ca.“) – für Anzeigen beim Löschen.
    func sizeValue(_ asset: MediaAsset, measured: KnownSize?) -> SizeValue {
        SizeValue.of(measured ?? .unknown, estimate: estimator.estimate(asset.estimateInput))
    }

    // MARK: Größen

    func size(_ asset: MediaAsset) async -> KnownSize { await sizer.size(of: asset) }

    /// Gemessene Größen (gespeichert oder neu, parallel gemessen). Unbekannt bleibt unbekannt, nie 0.
    func sizes(_ assets: [MediaAsset], progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [String: KnownSize] {
        let records = await SizeMeasuring.measureParallel(assets, sizer: sizer, progress: progress)
        var out: [String: KnownSize] = [:]
        for a in assets { out[a.id] = records[a.id]?.size ?? .unknown }
        return out
    }

    // MARK: Ausblenden und Ausnehmen (nie eine Entscheidung, Datei unverändert)

    func hide(_ ids: [String]) {
        updateSettings { s in s.hiddenMedia = Array(Set(s.hiddenMedia).union(ids)).sorted() }
    }

    func unhide(_ ids: [String]) {
        let remove = Set(ids)
        updateSettings { s in s.hiddenMedia = s.hiddenMedia.filter { !remove.contains($0) } }
    }

    func setExcluded(album id: String, _ excluded: Bool) {
        updateSettings { s in
            var set = Set(s.excludedAlbums)
            if excluded { set.insert(id) } else { set.remove(id) }
            s.excludedAlbums = set.sorted()
        }
    }

    func rememberRecentAlbum(_ id: String) {
        updateSettings { s in s.recentAlbums = Array(([id] + s.recentAlbums.filter { $0 != id }).prefix(5)) }
    }

    func togglePinnedAlbum(_ id: String) {
        updateSettings { s in
            if s.pinnedAlbums.contains(id) { s.pinnedAlbums.removeAll { $0 == id } }
            else { s.pinnedAlbums = Array((s.pinnedAlbums + [id]).prefix(8)) }
        }
    }

    // MARK: Navigation

    func navigate(_ route: Route, in tab: AppTab? = nil) {
        let t = tab ?? selectedTab
        selectedTab = t
        paths[t, default: []].append(route)
    }

    func popToRoot(_ tab: AppTab) { paths[tab] = [] }

    // MARK: Feed

    /// Preserve library order and current visibility rules; never resolve hidden IDs directly from PhotoKit.
    var skippedPreviewItems: [ItemReference] {
        guard !skippedPreviews.isEmpty else { return [] }
        return cleanupMedia.compactMap { asset in
            let item = asset.reference
            return skippedPreviews.contains(item) ? item : nil
        }
    }

    @discardableResult
    func rememberSkippedPreview(_ item: ItemReference) -> Bool {
        guard item.provider == .photoLibrary else { return false }
        return setSkippedPreviews(skippedPreviews.union([item]))
    }

    @discardableResult
    func restoreSkippedPreviews(_ items: [ItemReference]) -> Bool {
        setSkippedPreviews(skippedPreviews.subtracting(items))
    }

    private func setSkippedPreviews(_ items: Set<ItemReference>) -> Bool {
        guard items != skippedPreviews else { return true }
        do {
            try kv?.set(StoreKeys.skippedPreviews, items)
            skippedPreviews = items
            queueInputsRevision += 1
            rebuildPending()
            return true
        } catch {
            showError(L("error_settings_not_saved"))
            return false
        }
    }

    func retrySkippedPreviews() {
        let items = skippedPreviewItems
        guard !items.isEmpty, restoreSkippedPreviews(items) else { return }
        open(FeedRequest(.items(items, titleKey: "feed_skipped_title")))
    }

    func open(_ request: FeedRequest) {
        player.stop()
        feed = request
    }

    func closeFeed(reviewed: Int) {
        player.stop()
        feed = nil
        flushPendingPublish()
        // „Neu seit dem letzten Aufräumen“: nur nach einer Sitzung mit mindestens einer Entscheidung.
        if reviewed > 0 {
            let token = PhotoLibraryService.currentChangeTokenData()
            updateSettings { $0.lastSessionEnd = Date(); $0.lastSessionChangeToken = token }
        }
    }
}

/// Einstiege von außen (Schnellaktionen, „Öffnen in“). Öffnen nur Ansichten – nie Entscheidung oder Löschen.
enum AppRoute: Equatable, Sendable {
    case startReview
    case trash
    case later
    case studio
    case openFiles([URL])
}
