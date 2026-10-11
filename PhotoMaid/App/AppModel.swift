import Foundation
import Observation
import Photos
import PhotoMaidCore
import SwiftUI

enum AppTab: String, Hashable, CaseIterable, Sendable { case today, library, cleanup, studio, history }
enum CleanupRunResult: Sendable { case finished(OperationIntent), rejected(CleanupError), needsReconciliation }
struct LedgerReadModel: Sendable {
    var records: [ItemReference: ItemRecord] = [:]
    var basket: [ItemRecord] = []
    var laterRecords: [ItemRecord] = []
    var events: [DecisionEvent] = []
    var allowance: AllowanceSnapshot?
    var canUndo = false
    var reconciliationNeeded: [OperationIntent] = []
}
struct LibrarySnapshot: Sendable {
    var all: [MediaAsset] = []
    var byID: [String: MediaAsset] = [:]
    var hiddenAlbumMembers: Set<String> = []
    var excludedAlbumMembers: Set<String> = []
    var loaded = false
}

@MainActor @Observable
final class AppModel {
    @ObservationIgnored let kv: KeyValueStore?
    @ObservationIgnored let ledger: DecisionLedger
    let library: PhotoLibraryService
    let purchases: StoreKitGateway
    let reminders: ReminderScheduler
    let player: FeedPlayer
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
    private(set) var readReady = false
    private(set) var snapshot = LibrarySnapshot()
    private(set) var visibleMedia: [MediaAsset] = []
    private(set) var cleanupMedia: [MediaAsset] = []
    private(set) var pending: [ItemReference] = []
    private(set) var now = Date()
    private(set) var isLoadingLibrary = false
    private(set) var lastFileCleanupFailureCode: String?
    /// Recreates PUBLIC view state only; vault presentation lives outside this identity.
    private(set) var privacyRevision = UUID()
    var publicMediaReady: Bool { VaultIsolation.shared.snapshot.ready }
    var toast: ToastMessage?
    var selectedTab: AppTab = .today
    var feed: FeedRequest?
    var pendingRoute: AppRoute?
    var fullScreen: FullScreenRequest?
    var paths: [AppTab: [Route]] = [:]
    @ObservationIgnored private var recoveredThisProcess = false
    @ObservationIgnored private var cleanupInFlight = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadedToken = -1
    @ObservationIgnored private var readGeneration = 0
    @ObservationIgnored private var queueInputsRevision = 0
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    var today: LocalDay { LocalDay(now, timeZone: .autoupdatingCurrent) }

    init(kv: KeyValueStore?, persistence: any LedgerPersistence, qa: Bool) throws {
        self.kv = kv; isQAFixtureMode = qa
        ledger = try DecisionLedger(persistence: persistence)
        library = PhotoLibraryService()
        purchases = StoreKitGateway(productID: AppConfig.proProductID, kv: kv)
        reminders = ReminderScheduler(); player = FeedPlayer()
        previews = PreviewPipeline(manager: PHCachingImageManager())
        organize = OrganizeStore(kv: kv); sources = ConnectedSourceStore(kv: kv)
        settings = kv?.get(StoreKeys.settings) ?? AppSettingsData()
        quickAccess = QuickAccess.sanitize(kv?.get(StoreKeys.quickAccess) ?? QuickAccess.defaults)
        rewards = kv?.get(StoreKeys.rewards) ?? RewardLedger()
        customCollections = kv?.get(StoreKeys.collections) ?? []
        let store = kv
        sizer = MediaSizer(initial: kv?.get(StoreKeys.sizeCache) ?? [:]) { cache in
            await MainActor.run { try? store?.set(StoreKeys.sizeCache, cache) }
        }
        if settings.firstSeenDay == nil { settings.firstSeenDay = today; try? kv?.set(StoreKeys.settings, settings) }
        Haptics.enabled = settings.haptics
        VaultStore.shared.attach(app: self)
    }

    static func bootstrap() -> Result<AppModel, BootstrapError> {
        #if QA_FIXTURES
        if ProcessInfo.processInfo.arguments.contains("-qa-fixtures") {
            do { return .success(try AppModel(kv: nil, persistence: InMemoryLedgerPersistence(), qa: true)) }
            catch { return .failure(.ledger) }
        }
        #endif
        do {
            let core = try CoreDataStore()
            return .success(try AppModel(kv: KeyValueStore(core: core), persistence: CoreDataLedgerPersistence(store: core), qa: false))
        } catch is CoreDataStore.StoreError {
            Diagnostics.log(.persistence, "store-load-failed"); return .failure(.store)
        } catch {
            Diagnostics.error(.persistence, "ledger-load-failed", error); return .failure(.ledger)
        }
    }
    enum BootstrapError: Error { case store, ledger }
    var capabilities: Capabilities {
        let c = Capabilities.resolve(purchase: purchases.state, rewards: rewards, now: now)
        return Capabilities(tier: c.tier, adsAllowed: c.adsAllowed && AppConfig.adsEnabled,
                            rewardRemaining: c.rewardRemaining, cleanupBonus: c.cleanupBonus)
    }

    func onForeground() async {
        now = Date(); library.refreshAccess()
        if !publicMediaReady { VaultIsolation.shared.reload(); applyVaultIsolation() }
        await publishRead(); reloadLibraryIfNeeded()
        await reminders.refresh()
        let previousPurchase = purchases.state
        await purchases.refresh()
        var didRecover = false
        if !recoveredThisProcess && !cleanupInFlight {
            recoveredThisProcess = true; await recoverOperations(); didRecover = true
        }
        if didRecover || purchases.state != previousPurchase { await publishRead() }
    }
    func tick() { now = Date() }

    /// Synchronous privacy boundary: no old photo, player, sheet, selection, draft
    /// or toast survives an import/migration in a public presentation tree.
    func applyVaultIsolation() {
        loadTask?.cancel(); loadTask = nil; loadedToken = -1
        readGeneration += 1; queueInputsRevision += 1
        player.stop(); previews.clear(); ThumbnailLoader.shared.clear()
        feed = nil; fullScreen = nil; pendingRoute = nil; paths = [:]
        toastTask?.cancel(); toast = nil
        StudioHandoff.shared.ids = []
        organize.refreshPrivacy()
        let policy = VaultIsolation.shared.snapshot
        snapshot = LibrarySnapshot()
        visibleMedia = []; cleanupMedia = []; pending = []
        read = LedgerReadModel(); readReady = false
        settings.hiddenMedia = settings.hiddenMedia.filter(policy.allows)
        privacyRevision = UUID()
        if policy.ready {
            reloadLibraryIfNeeded(force: true)
            Task { await publishRead() }
        }
    }

    func reloadLibraryIfNeeded(force: Bool = false) {
        guard publicMediaReady else { isLoadingLibrary = false; return }
        guard library.access.canRead else { snapshot = LibrarySnapshot(loaded: true); rebuildFiltered(); return }
        let token = library.changeToken
        guard force || token != loadedToken || !snapshot.loaded else { return }
        loadedToken = token; loadTask?.cancel(); isLoadingLibrary = true
        let hiddenAlbums = settings.hiddenAlbums, excluded = settings.excludedAlbums
        let policy = VaultIsolation.shared.snapshot
        loadTask = Task { [weak self] in
            let all = await PhotoLibraryService.loadAll()
            let (hidden, excl) = await Task.detached(priority: .userInitiated) { () -> (Set<String>, Set<String>) in
                var h = Set<String>(), e = Set<String>()
                for id in hiddenAlbums { h.formUnion(PhotoLibraryService.assetIDs(inCollection: id)) }
                for id in excluded { e.formUnion(PhotoLibraryService.assetIDs(inCollection: id)) }
                return (h, e)
            }.value
            guard let self, !Task.isCancelled, VaultIsolation.shared.snapshot.epoch == policy.epoch else { return }
            let safe = all.filter { policy.allows($0.id) }
            var s = LibrarySnapshot(all: safe, hiddenAlbumMembers: hidden, excludedAlbumMembers: excl, loaded: true)
            s.byID = Dictionary(safe.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            self.snapshot = s; self.isLoadingLibrary = false; self.rebuildFiltered()
            await self.publishRead()
        }
    }
    private func rebuildFiltered() {
        queueInputsRevision += 1
        let policy = VaultIsolation.shared.snapshot
        let hiddenIDs = Set(settings.hiddenMedia), hiddenAlbum = snapshot.hiddenAlbumMembers, excluded = snapshot.excludedAlbumMembers
        visibleMedia = snapshot.all.filter { policy.allows($0.id) && !hiddenIDs.contains($0.id) && !hiddenAlbum.contains($0.id) }
        cleanupMedia = excluded.isEmpty ? visibleMedia : visibleMedia.filter { !excluded.contains($0.id) }
        rebuildPending()
    }
    private func rebuildPending() {
        guard readReady, publicMediaReady else { pending = []; return }
        pending = ReviewQueues.normalQueue(candidates: cleanupMedia.map(\.reference), records: read.records, session: ReviewSessionID(), today: today)
    }
    func asset(_ id: String) -> MediaAsset? {
        guard VaultIsolation.shared.allows(id) else { return nil }
        return snapshot.byID[id] ?? library.asset(id)
    }
    func assets(_ refs: [ItemReference]) -> [MediaAsset] {
        var missing: [String] = []; var out: [String: MediaAsset] = [:]
        let safe = refs.filter { $0.provider == .photoLibrary && VaultIsolation.shared.allows($0) }
        for r in safe {
            if let a = snapshot.byID[r.localIdentifier] { out[a.id] = a } else { missing.append(r.localIdentifier) }
        }
        for a in library.assets(ids: missing) { out[a.id] = a }
        return safe.compactMap { out[$0.localIdentifier] }
    }
    func record(_ item: ItemReference) -> ItemRecord { read.records[item] ?? ItemRecord(item: item) }

    func makeBackup() async -> PhotoMaidBackup {
        let state = await ledger.snapshotState()
        let policy = VaultIsolation.shared.snapshot
        let publicIDs = Set(snapshot.byID.keys)
        func allowed(_ id: String) -> Bool { policy.allows(id) && (!policy.hasPrivateMedia || publicIDs.contains(id)) }
        var backup = PhotoMaidBackup(createdAt: Int64(Date().timeIntervalSince1970 * 1000), appVersion: AppConfig.appVersion)
        var table = BackupRefTable()
        for record in state.records.values where record.item.provider == .photoLibrary && allowed(record.item.localIdentifier) {
            guard let backupState = BackupRules.state(record.disposition) else { continue }
            let media = organize.refs[record.item.localIdentifier] ?? MediaRef(id: record.item.localIdentifier, name: nil, size: nil, takenMillis: nil)
            let index = table.add(media)
            backup.decisions.append(BackupDecision(ref: index, state: backupState, due: record.dueDay, bookmarked: record.bookmarked))
        }
        for (id, tags) in organize.tags where allowed(id) {
            backup.tags[table.add(organize.refs[id] ?? MediaRef(id: id, name: nil, size: nil, takenMillis: nil))] = tags
        }
        for (id, note) in organize.notes where allowed(id) {
            backup.notes[table.add(organize.refs[id] ?? MediaRef(id: id, name: nil, size: nil, takenMillis: nil))] = note
        }
        backup.basket = organize.basket.filter(allowed).map { table.add(organize.refs[$0] ?? MediaRef(id: $0, name: nil, size: nil, takenMillis: nil)) }
        backup.hiddenMedia = settings.hiddenMedia.filter(allowed).map { table.add(organize.refs[$0] ?? MediaRef(id: $0, name: nil, size: nil, takenMillis: nil)) }
        backup.refs = table.refs
        return backup
    }
    var dueCount: Int { read.laterRecords.filter { if case .due = ReviewQueues.laterStatus($0, today: today) { true } else { false } }.count }

    func publishRead() async {
        readGeneration += 1; let generation = readGeneration
        let state = await ledger.snapshotState()
        let policy = VaultIsolation.shared.snapshot
        let publicIDs = Set(snapshot.byID.keys)
        let limit = capabilities.dailyCleanupLimit, day = today
        let candidates = cleanupMedia.map(\.reference), queueRevision = queueInputsRevision
        let derived = await Task.detached(priority: .userInitiated) { () -> (LedgerReadModel, [ItemReference]) in
            func allowed(_ ref: ItemReference) -> Bool {
                policy.allows(ref) && (ref.provider != .photoLibrary || !policy.hasPrivateMedia || publicIDs.contains(ref.localIdentifier))
            }
            let records = state.records.filter { allowed($0.key) }
            let view = LedgerReadModel(records: records,
                basket: records.values.filter { $0.disposition == .markedForCleanup }.sorted { $0.item.description < $1.item.description },
                laterRecords: records.values.filter { $0.disposition == .later },
                events: state.events.filter { allowed($0.item) },
                allowance: DecisionLedger.allowance(in: state, day: day, limit: limit),
                canUndo: state.undoStack.last.map { allowed($0.item) } ?? false,
                reconciliationNeeded: state.intents.values.filter { $0.state == .reconciliationRequired && $0.items.keys.allSatisfy(allowed) })
            let queue = ReviewQueues.normalQueue(candidates: candidates.filter(allowed), records: records, session: ReviewSessionID(), today: day)
            return (view, queue)
        }.value
        guard generation == readGeneration, VaultIsolation.shared.snapshot.epoch == policy.epoch else { return }
        read = derived.0; readReady = policy.ready
        if queueInputsRevision == queueRevision { pending = derived.1 } else { rebuildPending() }
    }

    func updateSettings(_ change: (inout AppSettingsData) -> Void) {
        var s = settings; change(&s); guard s != settings else { return }
        do {
            try kv?.set(StoreKeys.settings, s)
            let filterChanged = s.hiddenMedia != settings.hiddenMedia
            let albumsChanged = s.hiddenAlbums != settings.hiddenAlbums || s.excludedAlbums != settings.excludedAlbums
            settings = s; Haptics.enabled = s.haptics
            if albumsChanged { reloadLibraryIfNeeded(force: true) } else if filterChanged { rebuildFiltered() }
        } catch { showError(L("error_settings_not_saved")) }
    }
    func setQuickAccess(_ list: [QuickAccessItem]) {
        let clean = QuickAccess.sanitize(list)
        do { try kv?.set(StoreKeys.quickAccess, clean); quickAccess = clean } catch { showError(L("error_settings_not_saved")) }
    }
    func setCustomCollections(_ list: [SmartCollection]) {
        do { try kv?.set(StoreKeys.collections, list); customCollections = list } catch { showError(L("error_settings_not_saved")) }
    }
    func showToast(_ text: String, actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        present(ToastMessage(text: text, actionTitle: actionTitle, action: action))
    }
    func showError(_ text: String) { Haptics.error(); present(ToastMessage(text: text, isError: true)) }
    private func present(_ t: ToastMessage) {
        toast = t; toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(t.actionTitle == nil ? 3 : 5))
            guard !Task.isCancelled, self?.toast?.id == t.id else { return }
            self?.toast = nil
        }
    }
    @discardableResult func apply(_ command: DecisionCommand, session: ReviewSessionID? = nil) async throws -> CommitOutcome {
        guard VaultIsolation.shared.allows(command.item) else { throw VaultIsolationError.privateMedia }
        let out = try await ledger.apply(command, sessionID: session)
        await publishRead(); return out
    }
    func decide(_ item: ItemReference, _ action: DecisionAction) async {
        guard VaultIsolation.shared.allows(item) else { return }
        do {
            let r = await ledger.record(for: item)
            try await apply(DecisionCommand(item: item, expectedRevision: r.revision, action: action))
        } catch { showError(L("error_change_not_saved")); await publishRead() }
    }
    func decideMany(_ items: [ItemReference], _ action: DecisionAction) async -> Int {
        var succeeded = 0
        for item in items where VaultIsolation.shared.allows(item) {
            do {
                let r = await ledger.record(for: item)
                guard VaultIsolation.shared.allows(item) else { continue }
                _ = try await ledger.apply(DecisionCommand(item: item, expectedRevision: r.revision, action: action))
                succeeded += 1
            } catch { showError(L("error_change_not_saved")) }
        }
        await publishRead(); return succeeded
    }
    func undo() async -> ItemRecord? {
        let state = await ledger.snapshotState()
        guard let top = state.undoStack.last, VaultIsolation.shared.allows(top.item) else { return nil }
        do {
            let r = try await ledger.undo(); await publishRead()
            return r.flatMap { VaultIsolation.shared.allows($0.item) ? $0 : nil }
        } catch DecisionError.undoConflict { showError(L("error_undo_conflict")) }
        catch DecisionError.itemBusy { showError(L("error_undo_busy")) }
        catch { showError(L("error_undo_generic")) }
        await publishRead(); return nil
    }

    func runCleanup(_ items: [ItemReference], kind: CleanupOperationKind) async -> CleanupRunResult {
        guard items.allSatisfy({ VaultIsolation.shared.allows($0) }) else { return .rejected(.emptySelection) }
        lastFileCleanupFailureCode = nil; cleanupInFlight = true
        defer { cleanupInFlight = false }
        let selected = items.filter { kind == .photoLibraryDelete ? $0.provider == .photoLibrary : $0.provider != .photoLibrary }
        let intent: OperationIntent
        do {
            intent = try await ledger.prepareCleanup(selected, kind: kind, dailyLimit: capabilities.dailyCleanupLimit, aliasKeys: aliasKeys(selected))
            try await ledger.markSubmitted(intent.id)
        } catch let e as CleanupError { await publishRead(); return .rejected(e) }
        catch { await publishRead(); return .rejected(.persistenceFailed(String(describing: error))) }
        player.stop()
        Diagnostics.log(.cleanup, "submitted kind=\(kind.rawValue) n=\(selected.count)")
        let outcome: OperationOutcome
        switch kind {
        case .photoLibraryDelete: outcome = await library.delete(ids: selected.map(\.localIdentifier))
        case .fileDeletePermanently, .fileMoveToTrash:
            outcome = FileOperations.deletePermanently(selected, sources: sources)
            if case .failed(let reason) = outcome { lastFileCleanupFailureCode = reason }
        }
        do {
            let done = try await ledger.reconcile(intent.id, outcome: outcome)
            Diagnostics.log(.cleanup, "reconciled \(done.state.rawValue)"); await publishRead()
            if kind == .photoLibraryDelete { library.bumpChangeToken(); reloadLibraryIfNeeded() }
            else { await files.scan(sources) }
            return .finished(done)
        } catch { Diagnostics.error(.cleanup, "reconcile-failed", error); await publishRead(); return .needsReconciliation }
    }
    private func aliasKeys(_ items: [ItemReference]) -> [ItemReference: String] {
        var out: [ItemReference: String] = [:]
        for e in files.entries where items.contains(e.reference) { if let key = e.aliasKey { out[e.reference] = key } }
        return out
    }
    private func recoverOperations() async {
        guard let open = try? await ledger.recoverAfterLaunch() else { return }
        for intent in open where intent.state == .reconciliationRequired {
            let refs = Array(intent.items.keys)
            var probes = library.probe(refs.filter { $0.provider == .photoLibrary }.map(\.localIdentifier))
            for (k, v) in FileOperations.probe(refs.filter { $0.provider != .photoLibrary }, sources: sources) { probes[k] = v }
            for ref in refs where !VaultIsolation.shared.allows(ref) { probes[ref] = .unknown }
            _ = try? await ledger.resolveReconciliation(intent.id, probes: probes)
        }
    }
    func recordSavings(_ removed: Set<ItemReference>, sizes: [ItemReference: KnownSize]) -> CleanupSavings {
        let s = CleanupSavings.of(removed: removed, sizes: sizes)
        let total = SavingsTotal(bytes: settings.savedTotalBytes, lowerBound: settings.savedTotalLowerBound).adding(s)
        updateSettings { $0.savedTotalBytes = total.bytes; $0.savedTotalLowerBound = total.lowerBound }
        return s
    }
    func size(_ asset: MediaAsset) async -> KnownSize {
        guard VaultIsolation.shared.allows(asset.id) else { return .unknown }
        return await sizer.size(of: asset)
    }
    func sizes(_ assets: [MediaAsset], progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [String: KnownSize] {
        await sizer.sizes(of: assets.filter { VaultIsolation.shared.allows($0.id) }, progress: progress)
    }
    func hide(_ ids: [String]) {
        let safe = ids.filter { VaultIsolation.shared.allows($0) }
        updateSettings { $0.hiddenMedia = Array(Set($0.hiddenMedia).union(safe)).sorted() }
    }
    func unhide(_ ids: [String]) {
        let remove = Set(ids)
        updateSettings { $0.hiddenMedia = $0.hiddenMedia.filter { !remove.contains($0) } }
    }
    func setExcluded(album id: String, _ excluded: Bool) {
        updateSettings { s in var set = Set(s.excludedAlbums); if excluded { set.insert(id) } else { set.remove(id) }; s.excludedAlbums = set.sorted() }
    }
    func rememberRecentAlbum(_ id: String) { updateSettings { $0.recentAlbums = Array(([id] + $0.recentAlbums.filter { $0 != id }).prefix(5)) } }
    func togglePinnedAlbum(_ id: String) {
        updateSettings { s in if s.pinnedAlbums.contains(id) { s.pinnedAlbums.removeAll { $0 == id } } else { s.pinnedAlbums = Array((s.pinnedAlbums + [id]).prefix(8)) } }
    }
    func navigate(_ route: Route, in tab: AppTab? = nil) {
        guard publicMediaReady else { VaultStore.shared.present(); return }
        let t = tab ?? selectedTab; selectedTab = t; paths[t, default: []].append(route)
    }
    func popToRoot(_ tab: AppTab) { paths[tab] = [] }
    func open(_ request: FeedRequest) { guard publicMediaReady else { return }; player.stop(); feed = request }
    func closeFeed(reviewed: Int) {
        player.stop(); feed = nil
        if reviewed > 0 {
            let token = PhotoLibraryService.currentChangeTokenData()
            updateSettings { $0.lastSessionEnd = Date(); $0.lastSessionChangeToken = token }
        }
    }
}

enum AppRoute: Equatable, Sendable { case startReview, trash, later, studio, openFiles([URL]) }
