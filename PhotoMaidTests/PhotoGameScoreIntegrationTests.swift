import PhotoMaidCore
import Testing
@testable import PhotoMaid

@MainActor struct PhotoGameScoreIntegrationTests {
    @Test func memoryCountsOnlyActiveTimeAndFreezesOnVictory() throws {
        var time = 100.0
        let scores = PhotoGameScores()
        let model = PhotoMemoryModel(scores: scores, now: { time })
        model.startMotifs()
        model.setTimingActive(true)
        time = 200
        #expect(model.elapsedSeconds == 0)
        let game = try #require(model.game)
        let pairs = Dictionary(grouping: game.cards, by: \.pairID).values.map { $0.map(\.id) }
        model.reveal(pairs[0][0])
        time += 3
        model.setTimingActive(false)
        time += 100
        #expect(model.elapsedSeconds == 3)
        model.setTimingActive(true)
        time += 2
        model.reveal(pairs[0][1])
        for pair in pairs.dropFirst() {
            time += 1
            model.reveal(pair[0]); model.reveal(pair[1])
        }
        #expect(model.game?.isFinished == true)
        #expect(model.elapsedSeconds == 10 && model.bestSeconds == 10 && model.newBest)
        time += 500
        #expect(model.elapsedSeconds == 10)
        model.replay()
        #expect(model.elapsedSeconds == 0 && model.bestSeconds == 10 && !model.newBest)
    }

    @Test func recordsSurviveLocalStoreReloadAndSaveFailureCanRetry() throws {
        let store = try CoreDataStore(inMemory: true)
        let kv = KeyValueStore(core: store)
        var shouldFail = true
        let scores = PhotoGameScores { records in
            if shouldFail { throw Failure.unavailable }
            try kv.set(StoreKeys.gameRecords, records)
        }
        var game = PhotoMemoryGame(pairIDs: ["a", "b"])
        for pair in Dictionary(grouping: game.cards, by: \.pairID).values {
            for card in pair { _ = game.reveal(card.id) }
        }
        #expect(scores.recordMemory(game, seconds: 12.5, usesPhotos: true, manualMismatch: false) == true)
        #expect(scores.saveFailed && scores.records.memory.count == 1)
        shouldFail = false
        scores.retrySave()
        #expect(!scores.saveFailed)
        let reloaded = PhotoGameScores(records: kv.get(StoreKeys.gameRecords))
        #expect(reloaded.records == scores.records)
    }

    @Test func hiddenPhotoInvalidatesCachedRoundBeforeAnotherMove() async throws {
        let model = PhotoMemoryModel(canUsePhotos: { _ in true })
        model.photos.updateVisibility(["a", "b"])
        model.startPhotos(["a", "b"]) { _ in .init() }
        for _ in 0..<100 where model.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(model.game != nil)
        model.photos.updateVisibility(["b"])
        model.reveal(0)
        #expect(model.game == nil && model.images.isEmpty)
    }

    @Test func analysisContextSurvivesCompletionAndSwitchingGames() {
        let session = PhotoGameSession()
        let kind = AnalysisKind.allCases[0]
        session.observe(kind)
        session.observe(nil)
        #expect(session.watchedAnalysis == kind)
    }

    private enum Failure: Error { case unavailable }
}
