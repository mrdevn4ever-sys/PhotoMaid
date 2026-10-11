import Foundation
import Observation
import PhotoMaidCore
import UIKit

private struct AnalysisDisplay: Sendable {
    var counts: AnalysisCounts?
    var ids: [String]
    var total: Int
    var groups: [[String]]
    var groupTotal: Int
}

/// One owner for foreground and system-scheduled work. Views never create a second library-wide scan.
@MainActor @Observable
final class AnalysisController {
    static let shared = AnalysisController()
    nonisolated static let pageSize = 120
    nonisolated static let groupsPerPage = 10
    private(set) var kind = AnalysisKind.blurry
    private(set) var stage = AnalysisRunStage.idle
    private(set) var counts = AnalysisCounts()
    private(set) var resultIDs: [String] = []
    private(set) var groups: [[String]] = []
    private(set) var matchCount = 0
    private(set) var groupCount = 0
    private(set) var page = 0
    private(set) var running = false
    private(set) var reading = false
    private(set) var downloadFraction: Double?
    private(set) var scopeRevision: UInt64 = 0
    var hasScope: Bool { validScope }
    var includeCloud = false
    var query = ""
    var category: String?
    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var runID: UUID?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var selectionID = UUID()
    @ObservationIgnored private var sources: [AnalysisSource] = []
    @ObservationIgnored private var validScope = false
    @ObservationIgnored private var lastRefresh: TimeInterval = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var backgroundRun = false

    private init() {
        _ = AnalysisNetwork.shared
        for name in [Notification.Name.analysisVisibilityChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil,
                using: Self.invalidationHandler(self)))
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil, using: Self.memoryHandler(self)))
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: nil, using: Self.backgroundHandler(self)))
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: nil, using: Self.foregroundHandler(self)))
    }
    private nonisolated static func invalidationHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in guard let owner else { return }; owner.invalidate(); owner.scopeRevision &+= 1 } }
    }
    private nonisolated static func memoryHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in owner?.pause() } }
    }
    private nonisolated static func backgroundHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in
            // Keine Hintergrundanalyse (noch nicht freigegeben): beim Verlassen anhalten, beim nächsten Start fortsetzen.
            guard let owner, !owner.backgroundRun else { return }
            owner.pause()
        } }
    }
    private nonisolated static func foregroundHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in owner?.stopBackgroundRun() } }
    }
    private nonisolated static func libraryChanged(_ owner: AnalysisController) -> @Sendable () -> Void {
        { [weak owner] in Task { @MainActor in owner?.libraryInvalidated(); owner?.watchLibrary() } }
    }
    var attachedApp: AppModel? { app }
    var canNext: Bool {
        kind == .similar ? (page + 1) * Self.groupsPerPage < groupCount : (page + 1) * Self.pageSize < matchCount
    }
    var visibleIDs: [String] { kind == .similar ? groups.flatMap { $0 } : resultIDs }
    func stopBackgroundRun() { if backgroundRun { pause() } }
    func attach(_ app: AppModel) {
        guard self.app !== app else { return }
        self.app = app; watchLibrary()
    }
    private func watchLibrary() {
        guard let app else { return }
        withObservationTracking({
            _ = app.library.changeToken; _ = app.isLoadingLibrary
            _ = app.settings.hiddenMedia; _ = app.settings.hiddenAlbums
            _ = app.settings.excludedAlbums; _ = app.settings.analysisEnabled
        }, onChange: Self.libraryChanged(self))
    }
    private func libraryInvalidated() {
        if UserDefaults.standard.string(forKey: "analysis.lastKind") != nil {
            UserDefaults.standard.set(true, forKey: "analysis.hasPendingWork")
        }
        invalidate(); scopeRevision &+= 1
    }
    func invalidate() {
        pause(); refreshTask?.cancel(); refreshID = UUID(); selectionID = UUID()
        validScope = false; reading = false
        resultIDs = []; groups = []; matchCount = 0; groupCount = 0; sources = []; counts = AnalysisCounts()
        stage = VaultConcealment.shared.analysisReady ? .paused : .privacy
    }
    func pause() {
        work?.cancel(); downloadFraction = nil
        if running { stage = .paused }
    }
    func waitUntilStopped() async { if let work { await work.value } }

    func select(_ requested: AnalysisKind, app: AppModel) async {
        attach(app)
        let selection = UUID(); selectionID = selection
        if running, kind == requested, validScope { refreshResults(force: true); return }
        if running { pause(); await waitUntilStopped() }
        guard selectionID == selection, !Task.isCancelled else { return }
        if kind != requested { kind = requested; query = ""; category = nil; page = 0 }
        guard app.snapshot.loaded, !app.isLoadingLibrary, app.library.access.canRead else { invalidate(); return }
        guard VaultConcealment.shared.analysisReady else { invalidate(); stage = .privacy; return }
        sources = VaultConcealment.shared.visible(app.cleanupMedia.filter { !$0.isVideo }, id: \.id).map(AnalysisSource.init)
        validScope = true
        let sources = sources, kind = kind, query = query, category = category, page = page
        let token = UUID(); refreshID = token; reading = true
        defer { if refreshID == token { reading = false } }
        do {
            // Old full-library JSON results used a different blur scale and had no per-feature completion state.
            // They are a rebuildable cache, not user data; do not keep stale OCR in the legacy public search cache.
            if let kv = app.kv, !kv.get(StoreKeys.analysisCache).isEmpty { try kv.set(StoreKeys.analysisCache, [:]) }
            let display = try await Task.detached(priority: .utility) {
                try Self.readDisplay(sources: sources, kind: kind, query: query, category: category, page: page, reconcile: true)
            }.value
            guard refreshID == token, selectionID == selection, !Task.isCancelled else { return }
            apply(display); if validScope { stage = .idle }
        } catch {
            if refreshID == token { stage = .storageError; resultIDs = []; groups = [] }
        }
        if refreshID == token { reading = false }
    }

    func start(app: AppModel, retryFailures: Bool = false, inBackground: Bool = false) {
        guard !running, validScope, app.snapshot.loaded, !app.isLoadingLibrary, app.library.access.canRead,
              app.settings.analysisEnabled, app.capabilities.smartReview else { return }
        guard VaultConcealment.shared.analysisReady else { stage = .privacy; return }
        attach(app)
        sources = VaultConcealment.shared.visible(app.cleanupMedia.filter { !$0.isVideo }, id: \.id).map(AnalysisSource.init)
        let sources = sources, kind = kind, cloud = includeCloud && !inBackground
        refreshTask?.cancel(); refreshID = UUID()
        let token = UUID(); runID = token; running = true; backgroundRun = inBackground
        reading = false; stage = .preparing; downloadFraction = nil
        UserDefaults.standard.set(kind.rawValue, forKey: "analysis.lastKind")
        UserDefaults.standard.set(true, forKey: "analysis.hasPendingWork")
        work = Task.detached(priority: .utility) { [weak self] in
            let result = await AnalysisRunner.run(sources: sources, kind: kind, includeCloud: cloud,
                retryFailures: retryFailures) { [weak self] event in await self?.receive(event, token: token) }
            await self?.finished(result, token: token)
        }
    }
    private func receive(_ event: AnalysisRunEvent, token: UUID) {
        guard runID == token, work?.isCancelled != true, validScope else { return }
        switch event {
        case .counts(let counts, let stage):
            self.counts = counts; self.stage = stage
            if stage != .cloud { downloadFraction = nil }
            refreshResults()
        case .download(let fraction):
            if fraction.isFinite { downloadFraction = min(1, max(0, fraction)) }
        }
    }
    private func finished(_ result: AnalysisRunStage, token: UUID) {
        guard runID == token else { return }
        work = nil; runID = nil; running = false; backgroundRun = false; downloadFraction = nil
        guard validScope else { return }
        UserDefaults.standard.set(counts.pending > 0 && result != .privacy && result != .storageError,
                                  forKey: "analysis.hasPendingWork")
        stage = result; refreshResults(force: true)
    }
    func next() { guard canNext else { return }; page += 1; refreshResults(force: true) }
    func previous() { guard page > 0 else { return }; page -= 1; refreshResults(force: true) }
    func filterChanged() { page = 0; refreshResults(force: true, debounce: true) }

    private func refreshResults(force: Bool = false, debounce: Bool = false) {
        guard validScope else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastRefresh >= 1 else { return }
        lastRefresh = now
        refreshTask?.cancel()
        let token = UUID(); refreshID = token
        let sources = sources, kind = kind, query = query, category = category, page = page
        refreshTask = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(250)) }
                let display = try await Task.detached(priority: .utility) {
                    try Self.readDisplay(sources: sources, kind: kind, query: query, category: category, page: page, reconcile: false)
                }.value
                guard let self, !Task.isCancelled, self.refreshID == token else { return }
                self.apply(display)
            } catch {
                guard let self, !Task.isCancelled, self.refreshID == token else { return }
                self.pause(); self.stage = .storageError
            }
        }
    }
    private func apply(_ display: AnalysisDisplay) {
        guard validScope, VaultConcealment.shared.analysisReady else { invalidate(); return }
        let ids = VaultConcealment.shared.visible(display.ids, id: { $0 })
        let groups = display.groups.map { VaultConcealment.shared.visible($0, id: { $0 }) }
        guard ids.count == display.ids.count, groups.map(\.count) == display.groups.map(\.count) else { invalidate(); return }
        resultIDs = ids; self.groups = groups.filter { $0.count >= 2 }
        matchCount = display.total; groupCount = display.groupTotal
        if let counts = display.counts { self.counts = counts }
    }
    nonisolated private static func readDisplay(sources: [AnalysisSource], kind: AnalysisKind, query: String,
        category: String?, page: Int, reconcile: Bool) throws -> AnalysisDisplay {
        guard VaultConcealment.shared.analysisReady else { throw AnalysisDatabaseError.privacy }
        let db = try AnalysisDatabase.shared()
        let allowed = Dictionary(sources.map { ($0.id, $0.fingerprint) }, uniquingKeysWith: { a, _ in a })
        if reconcile {
            for type in AnalysisKind.allCases {
                let stale = try db.rows(type).filter { allowed[$0.id] != $0.fingerprint || VaultConcealment.shared.isConcealed($0.id) }
                try db.remove(Set(stale.map(\.id)))
            }
            let invalid = try db.rows(kind).filter { $0.algorithm != LocalPhotoAnalyzer.algorithm(kind) }
            try db.remove(Set(invalid.map(\.id)), kind: kind)
        }
        var counts: AnalysisCounts?
        if reconcile {
            var value = AnalysisCounts()
            let rows = try db.rows(kind)
            let states = Dictionary(rows.map { ($0.id, $0.state) }, uniquingKeysWith: { a, _ in a })
            for source in sources { value.add(states[source.id] ?? .pending) }
            counts = value
        }
        if kind == .similar {
            var graph = AnalysisSimilarityGraph()
            for (a, b) in try db.links() where allowed[a] != nil && allowed[b] != nil { graph.join(a, b) }
            let groups = graph.groups()
            return AnalysisDisplay(counts: counts, ids: [], total: groups.reduce(0) { $0 + $1.count },
                groups: Array(groups.dropFirst(max(0, page) * groupsPerPage).prefix(groupsPerPage)), groupTotal: groups.count)
        }
        let result = try db.hits(kind: kind, query: query, category: category,
                                limit: pageSize, offset: max(0, page) * pageSize)
        return AnalysisDisplay(counts: counts, ids: result.ids.filter { allowed[$0] != nil }, total: result.total, groups: [], groupTotal: 0)
    }
}
