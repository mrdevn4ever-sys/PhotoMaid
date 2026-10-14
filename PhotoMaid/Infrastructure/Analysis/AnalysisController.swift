import BackgroundTasks
import Foundation
import Observation
import PhotoMaidCore
import UIKit

private struct AnalysisDisplay: Sendable {
    var counts: AnalysisCounts?
    var results: AnalysisResultPage
    var groups: AnalysisGroupPage
}

/// One owner for foreground and continued background work. Views never create a second library-wide scan.
/// Angehalten wird nur auf Wunsch des Nutzers endgültig; nach Wärme, Verlassen der App oder Speicherwarnung geht es von
/// selbst weiter (`AnalysisAutoResume`). Ergebnisse zeigen standardmäßig nur noch offene Fotos.
@MainActor @Observable
final class AnalysisController {
    static let shared = AnalysisController()
    nonisolated static let pageSize = 120
    nonisolated static let groupsPerPage = 10
    private(set) var kind = AnalysisKind.blurry
    private(set) var stage = AnalysisRunStage.idle
    private(set) var counts = AnalysisCounts()
    /// Treffer der aktuellen Seite (bzw. Gruppen bei „Ähnliche Aufnahmen“) und alle Treffer für „Durchwischen“.
    private(set) var results = AnalysisResultPage(ordered: [], include: { _ in true }, page: 0, pageSize: AnalysisController.pageSize)
    private(set) var similar = AnalysisGroupPage(groups: [], include: { _ in true }, page: 0, pageSize: AnalysisController.groupsPerPage)
    private(set) var page = 0
    private(set) var running = false
    private(set) var reading = false
    private(set) var downloadFraction: Double?
    private(set) var scopeRevision: UInt64 = 0
    var hasScope: Bool { validScope }
    /// iCloud-Fotos einbeziehen (nur WLAN). Bleibt gespeichert (`optionsChanged`).
    var includeCloud = UserDefaults.standard.bool(forKey: "analysis.includeCloud")
    /// Weiterlaufen, wenn die App verlassen wird (iOS zeigt den Fortschritt). Bleibt gespeichert, Standard aus.
    var continueInBackground = UserDefaults.standard.bool(forKey: "analysis.background")
    /// Auch bereits entschiedene Fotos zeigen (Standard: nur offene).
    var showDecided = false
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
    @ObservationIgnored private var pauseReason: AnalysisStopReason?
    @ObservationIgnored private var continued: UncheckedBox<BGContinuedProcessingTask>?
    /// Läuft gerade als fortgesetzte Aufgabe außerhalb der App weiter.
    var backgroundRun: Bool { continued != nil }

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
        observers.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: nil, using: Self.thermalHandler(self)))
    }
    private nonisolated static func invalidationHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in guard let owner else { return }; owner.invalidate(); owner.scopeRevision &+= 1 } }
    }
    private nonisolated static func memoryHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in owner?.pause(reason: .memory) } }
    }
    private nonisolated static func backgroundHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in
            // Ohne fortgesetzte Aufgabe: beim Verlassen anhalten, bei der Rückkehr von selbst fortsetzen.
            guard let owner, !owner.backgroundRun else { return }
            owner.pause(reason: .background)
        } }
    }
    private nonisolated static func foregroundHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in owner?.resumeIfAllowed() } }
    }
    private nonisolated static func thermalHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in owner?.resumeIfAllowed() } }
    }
    private nonisolated static func libraryChanged(_ owner: AnalysisController) -> @Sendable () -> Void {
        { [weak owner] in Task { @MainActor in owner?.libraryInvalidated(); owner?.watchLibrary() } }
    }
    var attachedApp: AppModel? { app }
    var canNext: Bool { kind == .similar ? similar.canNext : results.canNext }
    var matchCount: Int { kind == .similar ? similar.total : results.total }
    /// Alle Treffer in Anzeigereihenfolge (für „Durchwischen“).
    var feedIDs: [String] { kind == .similar ? similar.all.flatMap { $0 } : results.all }
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
        pause(reason: .background); refreshTask?.cancel(); refreshID = UUID(); selectionID = UUID()
        validScope = false; reading = false
        results = AnalysisResultPage(ordered: [], include: { _ in true }, page: 0, pageSize: Self.pageSize)
        similar = AnalysisGroupPage(groups: [], include: { _ in true }, page: 0, pageSize: Self.groupsPerPage)
        sources = []; counts = AnalysisCounts()
        stage = VaultConcealment.shared.analysisReady ? .paused : .privacy
    }

    /// Anhalten. `user` = ausdrücklich angehalten (kein automatisches Fortsetzen); sonst geht es später von selbst weiter.
    func pause(reason: AnalysisStopReason = .user) {
        if running { pauseReason = reason }
        work?.cancel(); downloadFraction = nil
        if running { stage = .paused }
    }
    func waitUntilStopped() async { if let work { await work.value } }

    /// Schalter in der Ansicht geändert: speichern; „Weiterlaufen“ sofort an- bzw. abmelden.
    func optionsChanged() {
        UserDefaults.standard.set(includeCloud, forKey: "analysis.includeCloud")
        UserDefaults.standard.set(continueInBackground, forKey: "analysis.background")
        if continueInBackground { beginContinued() } else { endContinued(success: false) }
    }

    // MARK: Automatisch fortsetzen

    private static func stopKey(_ kind: AnalysisKind) -> String { "analysis.stop." + kind.rawValue }
    private func storedStop(_ kind: AnalysisKind) -> AnalysisStopReason? {
        UserDefaults.standard.string(forKey: Self.stopKey(kind)).flatMap(AnalysisStopReason.init(rawValue:))
    }
    private func storeStop(_ reason: AnalysisStopReason?, for kind: AnalysisKind) {
        UserDefaults.standard.set(reason?.rawValue, forKey: Self.stopKey(kind))
    }

    /// Nach Rückkehr in die App, nach dem Abkühlen und beim Öffnen der Ansicht: weiter, wenn nicht ausdrücklich angehalten.
    func resumeIfAllowed() {
        guard let app, !running, validScope, UIApplication.shared.applicationState == .active else { return }
        let pendingWork = counts.pending > 0 || (includeCloud && counts.cloud > 0)
        guard AnalysisAutoResume.shouldResume(after: storedStop(kind), pendingWork: pendingWork,
                                              thermal: AnalysisRunner.thermalLevel(),
                                              cloudReady: AnalysisNetwork.shared.permitsCloud) else { return }
        start(app: app, retryFailures: false)
    }

    func select(_ requested: AnalysisKind, app: AppModel) async {
        attach(app)
        let selection = UUID(); selectionID = selection
        if running, kind == requested, validScope { refreshResults(force: true); return }
        if running { pause(reason: .background); await waitUntilStopped() }
        guard selectionID == selection, !Task.isCancelled else { return }
        if kind != requested { kind = requested; query = ""; category = nil; page = 0 }
        guard app.snapshot.loaded, !app.isLoadingLibrary, app.library.access.canRead else { invalidate(); return }
        guard VaultConcealment.shared.analysisReady else { invalidate(); stage = .privacy; return }
        sources = VaultConcealment.shared.visible(app.cleanupMedia.filter { !$0.isVideo }, id: \.id).map(AnalysisSource.init)
        validScope = true
        let sources = sources, kind = kind, query = query, category = category, page = page, open = openFilter()
        let token = UUID(); refreshID = token; reading = true
        defer { if refreshID == token { reading = false } }
        do {
            // Old full-library JSON results used a different blur scale and had no per-feature completion state.
            // They are a rebuildable cache, not user data; do not keep stale OCR in the legacy public search cache.
            if let kv = app.kv, !kv.get(StoreKeys.analysisCache).isEmpty { try kv.set(StoreKeys.analysisCache, [:]) }
            let display = try await Task.detached(priority: .utility) {
                try Self.readDisplay(sources: sources, kind: kind, query: query, category: category, page: page,
                                     open: open, reconcile: true)
            }.value
            guard refreshID == token, selectionID == selection, !Task.isCancelled else { return }
            apply(display); if validScope { stage = .idle }
        } catch {
            if refreshID == token { stage = .storageError; clearResults() }
        }
        if refreshID == token { reading = false }
        resumeIfAllowed()
    }

    func start(app: AppModel, retryFailures: Bool = false) {
        guard !running, validScope, app.snapshot.loaded, !app.isLoadingLibrary, app.library.access.canRead,
              app.settings.analysisEnabled, app.capabilities.smartReview else { return }
        guard VaultConcealment.shared.analysisReady else { stage = .privacy; return }
        attach(app)
        sources = VaultConcealment.shared.visible(app.cleanupMedia.filter { !$0.isVideo }, id: \.id).map(AnalysisSource.init)
        let sources = sources, kind = kind, cloud = includeCloud
        refreshTask?.cancel(); refreshID = UUID()
        let token = UUID(); runID = token; running = true; pauseReason = nil
        reading = false; stage = .preparing; downloadFraction = nil
        // Bis zum Ende gilt der Lauf als „unterbrochen“: wird die App beendet, geht es beim nächsten Öffnen weiter.
        storeStop(.background, for: kind)
        UserDefaults.standard.set(kind.rawValue, forKey: "analysis.lastKind")
        UserDefaults.standard.set(true, forKey: "analysis.hasPendingWork")
        if continueInBackground { beginContinued() }
        let background = continueInBackground
        work = Task.detached(priority: .utility) { [weak self] in
            let result = await AnalysisRunner.run(sources: sources, kind: kind, includeCloud: cloud,
                retryFailures: retryFailures, background: background) { [weak self] event in await self?.receive(event, token: token) }
            await self?.finished(result, token: token)
        }
    }
    private func receive(_ event: AnalysisRunEvent, token: UUID) {
        guard runID == token, work?.isCancelled != true, validScope else { return }
        switch event {
        case .counts(let counts, let stage):
            self.counts = counts; self.stage = stage
            if stage != .cloud { downloadFraction = nil }
            reportContinued()
            refreshResults()
        case .download(let fraction):
            if fraction.isFinite { downloadFraction = min(1, max(0, fraction)) }
        }
    }
    private func finished(_ result: AnalysisRunStage, token: UUID) {
        guard runID == token else { return }
        let reason: AnalysisStopReason = switch result {
        case .finished: .finished
        case .paused: pauseReason ?? .user
        case .waitingWiFi: .network
        case .thermal: .thermal
        default: .error
        }
        storeStop(reason, for: kind)
        work = nil; runID = nil; running = false; downloadFraction = nil; pauseReason = nil
        endContinued(success: result == .finished)
        guard validScope else { return }
        UserDefaults.standard.set(counts.pending > 0 && result != .privacy && result != .storageError,
                                  forKey: "analysis.hasPendingWork")
        stage = result; refreshResults(force: true)
        // Kühl genug und Nutzer hat nicht angehalten (z. B. war nur kurz kritisch heiß): gleich weiter.
        if reason == .thermal { resumeIfAllowed() }
    }
    func next() { guard canNext else { return }; page += 1; refreshResults(force: true) }
    func previous() { guard page > 0 else { return }; page -= 1; refreshResults(force: true) }
    func filterChanged() { page = 0; refreshResults(force: true, debounce: true) }
    /// Nach Entscheidungen im Feed: entschiedene Fotos aus der Liste nehmen.
    func reload() { refreshResults(force: true) }

    /// Nur offene Fotos (wie im Feed), außer „Auch entschiedene zeigen“ ist an.
    private func openFilter() -> Set<String>? {
        guard !showDecided, let app else { return nil }
        return Set(app.pending.map(\.localIdentifier))
    }

    private func refreshResults(force: Bool = false, debounce: Bool = false) {
        guard validScope else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastRefresh >= 1 else { return }
        lastRefresh = now
        refreshTask?.cancel()
        let token = UUID(); refreshID = token
        let sources = sources, kind = kind, query = query, category = category, page = page, open = openFilter()
        refreshTask = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(250)) }
                let display = try await Task.detached(priority: .utility) {
                    try Self.readDisplay(sources: sources, kind: kind, query: query, category: category, page: page,
                                         open: open, reconcile: false)
                }.value
                guard let self, !Task.isCancelled, self.refreshID == token else { return }
                self.apply(display)
            } catch {
                guard let self, !Task.isCancelled, self.refreshID == token else { return }
                self.pause(reason: .user); self.stage = .storageError
            }
        }
    }
    private func clearResults() {
        results = AnalysisResultPage(ordered: [], include: { _ in true }, page: 0, pageSize: Self.pageSize)
        similar = AnalysisGroupPage(groups: [], include: { _ in true }, page: 0, pageSize: Self.groupsPerPage)
    }
    private func apply(_ display: AnalysisDisplay) {
        guard validScope, VaultConcealment.shared.analysisReady else { invalidate(); return }
        let ids = VaultConcealment.shared.visible(display.results.all, id: { $0 })
        let groups = display.groups.all.map { VaultConcealment.shared.visible($0, id: { $0 }) }
        guard ids.count == display.results.all.count, groups.map(\.count) == display.groups.all.map(\.count) else {
            invalidate(); return
        }
        results = display.results; similar = display.groups
        page = kind == .similar ? display.groups.page : display.results.page
        if let counts = display.counts { self.counts = counts }
    }
    nonisolated private static func readDisplay(sources: [AnalysisSource], kind: AnalysisKind, query: String,
        category: String?, page: Int, open: Set<String>?, reconcile: Bool) throws -> AnalysisDisplay {
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
        let include: (String) -> Bool = { id in allowed[id] != nil && (open?.contains(id) ?? true) }
        if kind == .similar {
            var graph = AnalysisSimilarityGraph()
            for (a, b) in try db.links() where allowed[a] != nil && allowed[b] != nil { graph.join(a, b) }
            return AnalysisDisplay(counts: counts,
                                   results: AnalysisResultPage(ordered: [], include: include, page: 0, pageSize: pageSize),
                                   groups: AnalysisGroupPage(groups: graph.groups(), include: include, page: page,
                                                             pageSize: groupsPerPage))
        }
        let hits = try db.hits(kind: kind, query: query, category: category, limit: nil)
        return AnalysisDisplay(counts: counts,
                               results: AnalysisResultPage(ordered: hits.ids, include: include, page: page, pageSize: pageSize),
                               groups: AnalysisGroupPage(groups: [], include: include, page: 0, pageSize: groupsPerPage))
    }

    // MARK: Weiterlaufen außerhalb der App (fortgesetzte Aufgabe, iOS zeigt den Fortschritt)

    private func beginContinued() {
        guard continued == nil, running, UIApplication.shared.applicationState == .active else { return }
        let id = (Bundle.main.bundleIdentifier ?? "app.photomaid") + ".analysis." + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil,
                                                        launchHandler: Self.continuedHandler(for: self))
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: L("ana2_bg_title"),
                                                       subtitle: L("ana2_bg_subtitle"))
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) } catch { Diagnostics.log(.analysis, "continued-refused") }
    }

    nonisolated private static func continuedHandler(for owner: AnalysisController) -> @Sendable (BGTask) -> Void {
        { @Sendable task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let box = UncheckedBox(task)
            task.expirationHandler = { @Sendable in
                Task { @MainActor in
                    // iOS beendet die Aufgabe: sauber anhalten, bei der Rückkehr geht es von selbst weiter.
                    owner.continued = nil
                    owner.pause(reason: .background)
                    box.value.setTaskCompleted(success: false)
                }
            }
            Task { @MainActor in
                guard owner.running, owner.continueInBackground else { box.value.setTaskCompleted(success: false); return }
                owner.continued = box
                owner.reportContinued()
            }
        }
    }

    private func reportContinued() {
        guard let task = continued?.value else { return }
        task.progress.totalUnitCount = Int64(max(1, counts.total))
        task.progress.completedUnitCount = Int64(min(counts.total, counts.complete))
    }

    private func endContinued(success: Bool) {
        guard let task = continued?.value else { return }
        continued = nil
        task.setTaskCompleted(success: success)
        // Ohne fortgesetzte Aufgabe darf die Analyse im Hintergrund nicht weiterlaufen.
        if running, UIApplication.shared.applicationState == .background { pause(reason: .background) }
    }
}
