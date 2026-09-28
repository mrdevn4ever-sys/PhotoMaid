import Foundation
import Observation
import PhotoMaidCore
import SwiftUI

enum AppearanceChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppSettingsData: Codable, Equatable, Sendable {
    var haptics = true
    var gestureHintSeen = false
    var appearance: AppearanceChoice = .system
    var largeFileThresholdMB = 100
    var privacyIntroSeen = false
}

/// Zentrale App-Instanz: Abhängigkeiten (DI) und abgeleitete Lesemodelle.
/// Schreiboperationen laufen ausschließlich über den `DecisionLedger`-Actor.
@MainActor
@Observable
final class AppModel {
    let store: CoreDataStore
    let ledger: DecisionLedger
    let photos: PhotoLibraryService
    let preview: PreviewPipeline
    let sources: ConnectedSourceStore
    let player = FeedPlayer()
    let entitlements: EntitlementCenter
    let reminders = ReminderScheduler()
    let rules: RulesStore
    let isQAFixtureMode: Bool

    private(set) var settings: AppSettingsData
    // Lesemodelle (werden nach jeder Mutation aus dem Ledger neu abgeleitet)
    private(set) var basket: [ItemRecord] = []
    private(set) var laterRecords: [ItemRecord] = []
    private(set) var events: [DecisionEvent] = []
    private(set) var allowance: AllowanceSnapshot?
    private(set) var canUndo = false
    private(set) var reconciliationNeeded: [OperationIntent] = []
    private(set) var lastError: String?

    private static let settingsKey = "app.settings"

    init(store: CoreDataStore, qaFixtures: Bool = false) throws {
        self.store = store
        self.isQAFixtureMode = qaFixtures
        ledger = try DecisionLedger(persistence: CoreDataLedgerPersistence(store: store))
        photos = PhotoLibraryService()
        preview = PreviewPipeline(manager: photos.imageManager)
        sources = ConnectedSourceStore(store: store)
        let purchases = PurchaseGatewayFactory.make(store: store)
        entitlements = EntitlementCenter(store: store, purchases: purchases, ads: UnconfiguredRewardedAdGateway())
        rules = RulesStore(store: store)
        settings = store.value(AppSettingsData.self, forKey: Self.settingsKey) ?? AppSettingsData()
    }

    var capabilities: Capabilities { entitlements.capabilities }

    func updateSettings(_ change: (inout AppSettingsData) -> Void) {
        var s = settings
        change(&s)
        do { try store.setValue(s, forKey: Self.settingsKey); settings = s }
        catch { lastError = String(localized: "Einstellung konnte nicht gespeichert werden.") }
    }

    /// Start/Resume: Berechtigungen neu prüfen, offene Operationen klären, Lesemodelle laden.
    func onForeground() async {
        photos.refreshAccess()
        await reminders.refresh()
        await entitlements.purchases.refresh()
        entitlements.tick()
        await recoverOperations()
        await reload()
        await rules.evaluateOnResume(app: self)
    }

    func reload() async {
        let snapshot = await ledger.snapshotState()
        basket = snapshot.records.values.filter { $0.disposition == .markedForCleanup }
            .sorted { $0.item.description < $1.item.description }
        laterRecords = snapshot.records.values.filter { $0.disposition == .later }
        events = snapshot.events
        allowance = await ledger.allowance(limit: capabilities.dailyCleanupLimit)
        canUndo = await ledger.canUndo()
        reconciliationNeeded = snapshot.intents.values.filter { $0.state == .reconciliationRequired }
    }

    var today: LocalDay { SystemClock().today }

    var dueCount: Int {
        laterRecords.filter {
            if case .due = ReviewQueues.laterStatus($0, today: today) { return true }
            return false
        }.count
    }

    // MARK: Entscheidungen

    func apply(_ command: DecisionCommand, session: ReviewSessionID? = nil) async throws -> CommitOutcome {
        let out = try await ledger.apply(command, sessionID: session)
        await reload()
        return out
    }

    func decide(_ item: ItemReference, _ action: DecisionAction) async {
        do {
            let r = await ledger.record(for: item)
            _ = try await apply(DecisionCommand(item: item, expectedRevision: r.revision, action: action))
        } catch {
            lastError = String(localized: "Die Änderung wurde nicht gespeichert.")
        }
    }

    func undo() async -> ItemRecord? {
        do {
            let r = try await ledger.undo()
            await reload()
            return r
        } catch DecisionError.undoConflict {
            lastError = String(localized: "Rückgängig nicht möglich: Das Element wurde inzwischen verändert.")
        } catch DecisionError.itemBusy {
            lastError = String(localized: "Rückgängig nicht möglich, solange eine Bereinigung läuft.")
        } catch {
            lastError = String(localized: "Rückgängig nicht möglich.")
        }
        await reload()
        return nil
    }

    func clearError() { lastError = nil }

    // MARK: Bereinigung

    /// Führt eine bestätigte Bereinigung für EINEN Provider durch.
    /// Entdecken → Entscheiden → Auswahl prüfen → Bestätigen → Provider-Operation → Abgleichen → Verlauf.
    func runCleanup(_ items: [ItemReference], kind: CleanupOperationKind) async -> CleanupRunResult {
        let limit = capabilities.dailyCleanupLimit
        let intent: OperationIntent
        do {
            intent = try await ledger.prepareCleanup(items, kind: kind, dailyLimit: limit)
            try await ledger.markSubmitted(intent.id)
        } catch let e as CleanupError {
            await reload()
            return .rejected(e)
        } catch {
            await reload()
            return .rejected(.persistenceFailed(String(describing: error)))
        }
        player.stop()
        let outcome: OperationOutcome
        switch kind {
        case .photoLibraryDelete:
            outcome = await photos.delete(ids: items.map(\.localIdentifier))
        case .fileDeletePermanently:
            outcome = FileOperations.deletePermanently(items, sources: sources)
        case .fileMoveToTrash:
            outcome = .failed(reason: "trash-not-supported") // nicht angeboten, siehe IOS_CAPABILITY_MATRIX
        }
        do {
            let done = try await ledger.reconcile(intent.id, outcome: outcome)
            await reload()
            return .finished(done)
        } catch {
            // Systemoperation lief, DB-Abgleich scheiterte: beim nächsten Start reconciliationRequired.
            await reload()
            return .needsReconciliation
        }
    }

    private func recoverOperations() async {
        guard let open = try? await ledger.recoverAfterLaunch() else { return }
        for intent in open where intent.state == .reconciliationRequired {
            let refs = Array(intent.items.keys)
            var probes: [ItemReference: ExistenceProbe] = [:]
            let photoIDs = refs.filter { $0.provider == .photoLibrary }.map(\.localIdentifier)
            probes.merge(photos.probe(photoIDs)) { $1 }
            probes.merge(FileOperations.probe(refs.filter { $0.provider != .photoLibrary }, sources: sources)) { $1 }
            _ = try? await ledger.resolveReconciliation(intent.id, probes: probes)
        }
    }
}

enum CleanupRunResult: Equatable {
    case finished(OperationIntent)
    case rejected(CleanupError)
    case needsReconciliation
}
