import PhotoMaidCore
import Testing
@testable import PhotoMaid

@MainActor struct FeedSkipPersistenceTests {
    @Test func skipsSurviveReloadAndOnlyExplicitRestoreRemovesThem() async throws {
        let core = try CoreDataStore(inMemory: true)
        let kv = KeyValueStore(core: core)
        let persistence = CoreDataLedgerPersistence(store: core)
        let first = ItemReference.photo("QA-UNAVAILABLE-1")
        let second = ItemReference.photo("QA-UNAVAILABLE-2")
        let app = try AppModel(kv: kv, persistence: persistence, qa: false)
        #expect(app.rememberSkippedPreview(first))
        #expect(app.rememberSkippedPreview(second))
        let reloaded = try AppModel(kv: KeyValueStore(core: core), persistence: persistence, qa: false)
        #expect(reloaded.skippedPreviews == [first, second])
        // Publishing decisions must not reintroduce skipped previews or create a review decision.
        await reloaded.publishRead()
        #expect(reloaded.skippedPreviews == [first, second])
        #expect(reloaded.read.records.isEmpty && reloaded.read.events.isEmpty && !reloaded.read.canUndo)
        #expect(reloaded.restoreSkippedPreviews([first]))
        #expect(kv.get(StoreKeys.skippedPreviews) == [second])
        #expect(reloaded.restoreSkippedPreviews([second]))
        #expect(kv.get(StoreKeys.skippedPreviews).isEmpty)
        let ledger = try DecisionLedger(persistence: persistence)
        let state = await ledger.snapshotState()
        #expect(state.records.isEmpty && state.events.isEmpty && state.undoStack.isEmpty)
    }
}
