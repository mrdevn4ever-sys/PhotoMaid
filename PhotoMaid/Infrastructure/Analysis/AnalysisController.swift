import BackgroundTasks
import Foundation
import Observation
import PhotoMaidCore
import UIKit

private struct AnalysisDisplay: Sendable {
    var counts: AnalysisCounts
    var results: AnalysisResultPage
    var groups: AnalysisGroupPage
}

/// One owner for foreground and continued background work. Views never create a second library-wide scan.
/// Eine Analyse läuft, weitere warten (`AnalysisPlan`): Das Öffnen einer anderen Analyse hält die laufende nie an.
/// Änderungen der Mediathek (iCloud-Abgleich, Favoriten, neue Fotos) passen nur den Umfang an – nichts wird
/// zurückgesetzt. Angehalten wird endgültig nur auf Wunsch des Nutzers; nach Wärme, Verlassen der App oder
/// Speicherwarnung geht es von selbst weiter (`AnalysisAutoResume`). Ergebnisse zeigen standardmäßig nur offene Fotos.
@MainActor @Observable
final class AnalysisController {
    static let shared = AnalysisController()
    nonisolated static let pageSize = 120
    nonisolated static let groupsPerPage = 10

    // MARK: Angezeigte Analyse

    private(set) var kind = AnalysisKind.blurry
    /// Treffer der aktuellen Seite (bzw. Gruppen bei „Ähnliche Aufnahmen“) und alle Treffer für „Durchwischen“.
    private(set) var results = AnalysisResultPage(ordered: [], include: { _ in true }, page: 0, pageSize: AnalysisController.pageSize)
    private(set) var similar = AnalysisGroupPage(groups: [], include: { _ in true }, page: 0, pageSize: AnalysisController.groupsPerPage)
    private(set) var page = 0
    private(set) var reading = false
    private(set) var scopeRevision: UInt64 = 0
    var hasScope: Bool { validScope }
    /// iCloud-Fotos einbeziehen (nur WLAN). Bleibt gespeichert (`optionsChanged`); gilt auch für einen laufenden Lauf.
    var includeCloud = UserDefaults.standard.bool(forKey: AnalysisController.cloudKey)
    /// Weiterlaufen, wenn die App verlassen wird (iOS zeigt den Fortschritt). Bleibt gespeichert, Standard aus.
    var continueInBackground = UserDefaults.standard.bool(forKey: "analysis.background")
    /// Auch bereits entschiedene Fotos zeigen (Standard: nur offene).
    var showDecided = false
    var query = ""
    var category: String?

    // MARK: Lauf

    /// Was gerade läuft (`nil` = nichts).
    @ObservationIgnored private let screenRequest = UUID()
    private(set) var runKind: AnalysisKind? {
        didSet { ScreenAwake.shared.set(screenRequest, active: runKind != nil) }
    }
    private(set) var runStage = AnalysisRunStage.idle
    private(set) var downloadFraction: Double?
    /// Reihenfolge: laufende und wartende Analysen (gespeichert).
    private(set) var plan: AnalysisPlan
    /// Zähler je Analyse (laufende live, andere aus der Datenbank) und letzter Zustand je Analyse.
    private(set) var countsByKind: [AnalysisKind: AnalysisCounts] = [:]
    private(set) var stageByKind: [AnalysisKind: AnalysisRunStage] = [:]

    var running: Bool { runKind != nil }
    /// Die angezeigte Analyse läuft gerade.
    var isRunningShown: Bool { runKind == kind }
    var counts: AnalysisCounts { countsByKind[kind] ?? AnalysisCounts() }
    /// Zustand der angezeigten Analyse (nach einem Neustart der App aus dem gespeicherten Grund des letzten Halts).
    var stage: AnalysisRunStage {
        if isRunningShown { return runStage }
        if let known = stageByKind[kind] { return known }
        switch storedStop(kind) {
        case .user?, .background?, .memory?: return .paused
        case .thermal?: return .thermal
        case .network?: return .waitingWiFi
        case .finished?: return .finished
        case .error?, nil: return .idle
        }
    }
    /// Wartet die angezeigte Analyse? 1 = als Nächstes.
    var queuePosition: Int? { plan.position(of: kind) }

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var runID: UUID?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshID = UUID()
    @ObservationIgnored private var sources: [AnalysisSource] = []
    @ObservationIgnored private var sourcesRevision = -1
    @ObservationIgnored private var validScope = false
    @ObservationIgnored private var lastRefresh: TimeInterval = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pauseReason: AnalysisStopReason?
    /// Nach dem Anhalten der laufenden Analyse diese starten („Jetzt zuerst“).
    @ObservationIgnored private var handover: AnalysisKind?
    @ObservationIgnored private var continued: UncheckedBox<BGContinuedProcessingTask>?
    /// Läuft gerade als fortgesetzte Aufgabe außerhalb der App weiter.
    var backgroundRun: Bool { continued != nil }

    nonisolated static let cloudKey = "analysis.includeCloud"
    private static let planKey = "analysis.plan"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.planKey),
           let stored = try? JSONDecoder().decode(AnalysisPlan.self, from: data) {
            plan = stored
        } else {
            // Älterer Stand: nur die zuletzt gestartete Analyse war bekannt.
            let last = UserDefaults.standard.string(forKey: "analysis.lastKind").flatMap(AnalysisKind.init(rawValue:))
            plan = AnalysisPlan(current: last)
        }
        _ = AnalysisNetwork.shared
        observers.append(NotificationCenter.default.addObserver(forName: .analysisVisibilityChanged, object: nil,
            queue: nil, using: Self.invalidationHandler(self)))
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
        { [weak owner] _ in Task { @MainActor in owner?.stopRun(reason: .memory) } }
    }
    private nonisolated static func backgroundHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in
            // Ohne fortgesetzte Aufgabe: beim Verlassen anhalten, bei der Rückkehr von selbst fortsetzen.
            guard let owner, !owner.backgroundRun else { return }
            owner.stopRun(reason: .background)
        } }
    }
    private nonisolated static func foregroundHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in owner?.resumeIfAllowed() } }
    }
    private nonisolated static func thermalHandler(_ owner: AnalysisController) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in owner?.resumeIfAllowed() } }
    }
    private nonisolated static func libraryChanged(_ owner: AnalysisController) -> @Sendable () -> Void {
        { [weak owner] in Task { @MainActor in owner?.libraryChanged(); owner?.watchLibrary() } }
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

    /// Nur der Bestand zählt (neu/entfernt/ausgeblendet), nicht jede Inhaltsänderung: Fotos meldet bei großen
    /// Mediatheken laufend Änderungen – früher hat jede die Analyse zurückgesetzt und neu vorbereitet.
    private func watchLibrary() {
        guard let app else { return }
        withObservationTracking({
            _ = app.mediaRevision; _ = app.library.access; _ = app.settings.analysisEnabled
        }, onChange: Self.libraryChanged(self))
    }
    private func libraryChanged() {
        guard let app else { return }
        guard app.library.access.canRead, app.settings.analysisEnabled else {
            invalidate(); scopeRevision &+= 1; return
        }
        // Umfang anpassen; ein laufender Lauf arbeitet mit seiner Liste weiter (fehlende Fotos überspringt er).
        // Noch kein Umfang (z. B. Mediathek war beim Öffnen noch nicht geladen): die Ansicht wählt neu.
        guard validScope else { scopeRevision &+= 1; return }
        updateSources(app)
        refreshResults(force: true, debounce: true)
    }
    private func updateSources(_ app: AppModel) {
        guard sourcesRevision != app.mediaRevision || sources.isEmpty else { return }
        sources = VaultConcealment.shared.visible(app.cleanupMedia.filter { !$0.isVideo }, id: \.id).map(AnalysisSource.init)
        sourcesRevision = app.mediaRevision
    }

    /// Nur für Datenschutz (Tresor), ausgeschaltete Analyse oder fehlenden Zugriff: anhalten und Anzeige leeren.
    func invalidate() {
        stopRun(reason: .background); refreshTask?.cancel(); refreshID = UUID()
        validScope = false; reading = false; sources = []; sourcesRevision = -1
        clearResults()
        countsByKind = [:]
        stageByKind[kind] = VaultConcealment.shared.analysisReady ? .paused : .privacy
    }

    /// „Anhalten“ in der Ansicht: endgültig bis zum nächsten Tipp (kein automatisches Fortsetzen).
    func pause() { stopRun(reason: .user) }

    private func stopRun(reason: AnalysisStopReason) {
        guard running else { return }
        pauseReason = reason
        work?.cancel(); downloadFraction = nil
        runStage = .paused
    }
    func waitUntilStopped() async { if let work { await work.value } }

    /// Schalter in der Ansicht geändert: speichern; „Weiterlaufen“ sofort an- bzw. abmelden.
    func optionsChanged() {
        UserDefaults.standard.set(includeCloud, forKey: Self.cloudKey)
        UserDefaults.standard.set(continueInBackground, forKey: "analysis.background")
        if continueInBackground { beginContinued() } else { endContinued(success: false) }
        if includeCloud, !running { resumeIfAllowed() }
    }

    // MARK: Gespeicherter Zustand je Analyse

    private static func stopKey(_ kind: AnalysisKind) -> String { "analysis.stop." + kind.rawValue }
    private func storedStop(_ kind: AnalysisKind) -> AnalysisStopReason? {
        UserDefaults.standard.string(forKey: Self.stopKey(kind)).flatMap(AnalysisStopReason.init(rawValue:))
    }
    private func storeStop(_ reason: AnalysisStopReason?, for kind: AnalysisKind) {
        UserDefaults.standard.set(reason?.rawValue, forKey: Self.stopKey(kind))
    }
    private func savePlan() {
        if let data = try? JSONEncoder().encode(plan) { UserDefaults.standard.set(data, forKey: Self.planKey) }
    }
    /// Noch Arbeit für `kind`? Unbekannt (nie angezeigt) gilt als ja – ein Lauf ohne Arbeit endet sofort.
    private func hasWork(_ kind: AnalysisKind) -> Bool {
        guard let c = countsByKind[kind], c.total > 0 else { return true }
        return c.pending > 0 || (includeCloud && c.cloud > 0)
    }

    // MARK: Anzeigen

    /// Ansicht geöffnet: Umfang bestimmen und Ergebnisse dieser Analyse lesen. Eine laufende (andere) Analyse läuft
    /// dabei weiter.
    func select(_ requested: AnalysisKind, app: AppModel) async {
        attach(app)
        if kind != requested { kind = requested; query = ""; category = nil; page = 0; clearResults() }
        guard app.snapshot.loaded, app.library.access.canRead else { return }
        guard VaultConcealment.shared.analysisReady else { invalidate(); stageByKind[kind] = .privacy; return }
        updateSources(app)
        validScope = true
        if stageByKind[kind] == .privacy { stageByKind[kind] = nil }
        // Old full-library JSON results used a different blur scale and had no per-feature completion state.
        // They are a rebuildable cache, not user data; do not keep stale OCR in the legacy public search cache.
        if let kv = app.kv, !kv.get(StoreKeys.analysisCache).isEmpty { try? kv.set(StoreKeys.analysisCache, [:]) }
        reading = true
        await refreshNow()
        reading = false
        resumeIfAllowed()
    }

    /// Mediathek geladen (App-Start): eine unterbrochene, nicht vom Nutzer angehaltene Analyse läuft weiter, ohne dass
    /// ihre Ansicht geöffnet werden muss.
    func resumeAfterLaunch(app: AppModel) {
        attach(app)
        guard !running, plan.current != nil else { return }
        resumeIfAllowed()
    }

    /// Umfang (alle sichtbaren Fotos) bereitstellen, wenn möglich – auch ohne geöffnete Ansicht.
    private func ensureScope(_ app: AppModel) -> Bool {
        if validScope { return true }
        guard app.snapshot.loaded, app.library.access.canRead, VaultConcealment.shared.analysisReady else { return false }
        updateSources(app)
        validScope = true
        return true
    }

    // MARK: Starten, einreihen, vorziehen

    /// „Analyse starten/fortsetzen“ der angezeigten Analyse. Läuft schon eine andere, wird diese nur eingereiht.
    func start(app: AppModel, retryFailures: Bool = false) {
        guard validScope, app.snapshot.loaded, app.library.access.canRead, app.settings.analysisEnabled,
              app.capabilities.smartReview else { return }
        guard VaultConcealment.shared.analysisReady else { stageByKind[kind] = .privacy; return }
        attach(app)
        let previous = plan.current
        let keep = previous.map { p in
            p != kind && hasWork(p) && [.background, .thermal, .memory, .network].contains(storedStop(p))
        } ?? false
        switch plan.request(kind, running: running, keepCurrent: keep) {
        case .start: savePlan(); launch(kind, retryFailures: retryFailures)
        case .queued: savePlan()
        case .alreadyRunning: break
        }
    }

    /// „Jetzt zuerst“: die angezeigte Analyse sofort, die laufende wartet danach als Nächste (ihr Fortschritt bleibt).
    func prioritize(app: AppModel) {
        guard running, runKind != kind else { start(app: app); return }
        plan.prioritize(kind); savePlan()
        handover = kind
        stopRun(reason: .background)
    }

    /// Nicht mehr warten lassen.
    func unqueue() { plan.remove(kind); savePlan() }

    /// Nach Rückkehr in die App, nach dem Abkühlen und beim Öffnen einer Ansicht: weiter, wenn nicht ausdrücklich
    /// angehalten (bzw. die nächste wartende Analyse, wenn die bisherige fertig ist).
    func resumeIfAllowed() {
        guard let app, !running, app.settings.analysisEnabled, app.capabilities.smartReview,
              UIApplication.shared.applicationState == .active else { return }
        guard let current = plan.current, ensureScope(app) else { return }
        let thermal = AnalysisRunner.thermalLevel()
        let stop = storedStop(current)
        if AnalysisAutoResume.shouldResume(after: stop, pendingWork: hasWork(current), thermal: thermal,
                                           cloudReady: AnalysisNetwork.shared.permitsCloud) {
            launch(current, retryFailures: false)
        } else if stop == .finished || stop == .network, thermal < .serious, !plan.waiting.isEmpty {
            advance(after: current, reason: stop ?? .finished)
        }
    }

    /// Nächste wartende Analyse starten. Wartet die bisherige nur auf WLAN (iCloud-Teil), kommt sie hinten wieder dran.
    /// Ohne WLAN werden Analysen, die ebenfalls nur noch auf WLAN warten, übersprungen (kein Hin und Her).
    private func advance(after ended: AnalysisKind, reason: AnalysisStopReason) {
        var parked: [AnalysisKind] = reason == .network ? [ended] : []
        var next: AnalysisKind?
        while let candidate = plan.advance() {
            if storedStop(candidate) == .network && !AnalysisNetwork.shared.permitsCloud {
                parked.append(candidate); continue
            }
            next = candidate; break
        }
        guard let next else {
            // Nichts ohne WLAN möglich: die erste wartende bleibt vorgemerkt und geht mit WLAN von selbst weiter.
            plan = AnalysisPlan(current: parked.first, waiting: Array(parked.dropFirst()))
            savePlan(); return
        }
        for kind in parked { _ = plan.request(kind, running: true, keepCurrent: false) }
        savePlan()
        launch(next, retryFailures: false)
    }

    private func launch(_ kind: AnalysisKind, retryFailures: Bool) {
        guard let app, !running, validScope else { return }
        updateSources(app)
        let sources = sources
        let token = UUID(); runID = token; runKind = kind; pauseReason = nil
        runStage = .preparing; downloadFraction = nil; stageByKind[kind] = nil
        // Bis zum Ende gilt der Lauf als „unterbrochen“: wird die App beendet, geht es beim nächsten Öffnen weiter.
        storeStop(.background, for: kind)
        if continueInBackground { beginContinued() }
        let background = continueInBackground
        work = Task.detached(priority: .utility) { [weak self] in
            let result = await AnalysisRunner.run(sources: sources, kind: kind,
                includeCloud: { UserDefaults.standard.bool(forKey: AnalysisController.cloudKey) },
                retryFailures: retryFailures, background: background) { [weak self] event in await self?.receive(event, token: token) }
            await self?.finished(result, token: token)
        }
    }

    private func receive(_ event: AnalysisRunEvent, token: UUID) {
        guard runID == token, work?.isCancelled != true, let runKind else { return }
        switch event {
        case .counts(let counts, let stage):
            countsByKind[runKind] = counts; runStage = stage
            if stage != .cloud { downloadFraction = nil }
            reportContinued()
            if runKind == kind { refreshResults() }
        case .download(let fraction):
            if fraction.isFinite { downloadFraction = min(1, max(0, fraction)) }
        }
    }

    private func finished(_ result: AnalysisRunStage, token: UUID) {
        guard runID == token, let ended = runKind else { return }
        let reason: AnalysisStopReason = switch result {
        case .finished: .finished
        case .paused: pauseReason ?? .user
        case .waitingWiFi: .network
        case .thermal: .thermal
        default: .error
        }
        storeStop(reason, for: ended)
        stageByKind[ended] = result
        work = nil; runID = nil; runKind = nil; downloadFraction = nil; pauseReason = nil
        runStage = .idle
        if ended == kind { refreshResults(force: true) }
        if let next = handover {
            handover = nil
            launch(next, retryFailures: false)
        } else if reason == .finished || reason == .network,
                  UIApplication.shared.applicationState == .active || backgroundRun, !plan.waiting.isEmpty {
            // Fertig (oder iCloud wartet auf WLAN): gleich die nächste wartende Analyse.
            advance(after: ended, reason: reason)
        } else if reason == .thermal {
            // Kühl genug und Nutzer hat nicht angehalten (z. B. war nur kurz kritisch heiß): gleich weiter.
            resumeIfAllowed()
        } else if reason == .memory {
            // Speicherwarnung: kurz Luft lassen, dann von selbst weiter.
            Task { [weak self] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.resumeIfAllowed()
            }
        }
        if !running { endContinued(success: result == .finished) }
    }

    // MARK: Ergebnisse

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

    private func refreshNow() async {
        refreshTask?.cancel()
        let token = UUID(); refreshID = token
        let sources = sources, kind = kind, query = query, category = category, page = page, open = openFilter()
        do {
            let display = try await Task.detached(priority: .utility) {
                try Self.readDisplay(sources: sources, kind: kind, query: query, category: category, page: page, open: open)
            }.value
            guard refreshID == token, self.kind == kind else { return }
            apply(display, for: kind)
        } catch {
            if refreshID == token { stageByKind[kind] = .storageError }
        }
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
                    try Self.readDisplay(sources: sources, kind: kind, query: query, category: category, page: page, open: open)
                }.value
                guard let self, !Task.isCancelled, self.refreshID == token, self.kind == kind else { return }
                self.apply(display, for: kind)
            } catch {
                guard let self, !Task.isCancelled, self.refreshID == token else { return }
                self.stageByKind[kind] = .storageError
            }
        }
    }
    private func clearResults() {
        results = AnalysisResultPage(ordered: [], include: { _ in true }, page: 0, pageSize: Self.pageSize)
        similar = AnalysisGroupPage(groups: [], include: { _ in true }, page: 0, pageSize: Self.groupsPerPage)
    }
    private func apply(_ display: AnalysisDisplay, for shown: AnalysisKind) {
        guard validScope, VaultConcealment.shared.analysisReady else { invalidate(); return }
        let ids = VaultConcealment.shared.visible(display.results.all, id: { $0 })
        let groups = display.groups.all.map { VaultConcealment.shared.visible($0, id: { $0 }) }
        guard ids.count == display.results.all.count, groups.map(\.count) == display.groups.all.map(\.count) else {
            invalidate(); return
        }
        results = display.results; similar = display.groups
        page = shown == .similar ? display.groups.page : display.results.page
        // Die laufende Analyse zählt live mit; sonst gilt der gespeicherte Stand.
        if runKind != shown { countsByKind[shown] = display.counts }
    }
    /// Schnell auch bei 30 000 Fotos: Zustände ohne JSON, Treffer per SQL (nur aktuelle Verfahren).
    nonisolated private static func readDisplay(sources: [AnalysisSource], kind: AnalysisKind, query: String,
        category: String?, page: Int, open: Set<String>?) throws -> AnalysisDisplay {
        guard VaultConcealment.shared.analysisReady else { throw AnalysisDatabaseError.privacy }
        let db = try AnalysisDatabase.shared()
        let algorithm = LocalPhotoAnalyzer.algorithm(kind)
        let states = try db.states(kind, algorithm: algorithm)
        var counts = AnalysisCounts()
        var allowed = Set<String>()
        allowed.reserveCapacity(sources.count)
        for source in sources {
            allowed.insert(source.id)
            counts.add(states[source.id] ?? .pending)
        }
        let include: (String) -> Bool = { id in allowed.contains(id) && (open?.contains(id) ?? true) }
        if kind == .similar {
            var graph = AnalysisSimilarityGraph()
            for (a, b) in try db.links() where allowed.contains(a) && allowed.contains(b) { graph.join(a, b) }
            return AnalysisDisplay(counts: counts,
                                   results: AnalysisResultPage(ordered: [], include: include, page: 0, pageSize: pageSize),
                                   groups: AnalysisGroupPage(groups: graph.groups(), include: include, page: page,
                                                             pageSize: groupsPerPage))
        }
        let hits = try db.hits(kind: kind, algorithm: algorithm, query: query, category: category, limit: nil)
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
                    owner.stopRun(reason: .background)
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
        guard let task = continued?.value, let runKind, let counts = countsByKind[runKind] else { return }
        task.progress.totalUnitCount = Int64(max(1, counts.total))
        task.progress.completedUnitCount = Int64(min(counts.total, counts.complete))
    }

    private func endContinued(success: Bool) {
        guard let task = continued?.value else { return }
        continued = nil
        task.setTaskCompleted(success: success)
        // Ohne fortgesetzte Aufgabe darf die Analyse im Hintergrund nicht weiterlaufen.
        if running, UIApplication.shared.applicationState == .background { stopRun(reason: .background) }
    }
}
