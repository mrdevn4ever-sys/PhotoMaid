import Testing
@testable import PhotoMaidCore

@Suite struct PhotoMemoryGameTests {
    @Test func rejectsUnplayableDecksAndDeduplicatesPictures() throws {
        #expect(PhotoMemoryGame(pairIDs: []) == nil)
        #expect(PhotoMemoryGame(pairIDs: ["a", "a", ""]) == nil)
        #expect(PhotoMemoryGame(pairIDs: (0..<19).map(String.init)) == nil)
        let game = try #require(PhotoMemoryGame(pairIDs: ["a", "b", "a", ""], shuffled: false))
        #expect(game.pairCount == 2)
        #expect(Set(game.cards.map(\.id)).count == 4)
        #expect(game.cards.filter { $0.pairID == "a" }.count == 2)
    }

    @Test func rapidTapsCannotRevealAThirdCardOrInflateScore() throws {
        var game = try #require(PhotoMemoryGame(pairIDs: ["a", "b"], shuffled: false))
        #expect(game.reveal(-1) == .ignored)
        #expect(game.reveal(0) == .revealed)
        #expect(game.reveal(0) == .ignored)
        #expect(game.moves == 0)
        #expect(game.reveal(2) == .mismatched)
        #expect(game.reveal(1) == .ignored)
        #expect(game.faceUp == [0, 2] && game.moves == 1)
        game.concealMismatch()
        #expect(game.faceUp.isEmpty)
        #expect(game.reveal(0) == .revealed)
        #expect(game.reveal(1) == .matched)
        #expect(game.matchedPairs == ["a"] && game.moves == 2)
        #expect(game.reveal(0) == .ignored)
    }

    @Test func selectingANewHiddenCardDismissesTheOldMismatchAndNeverGetsStuck() throws {
        var game = try #require(PhotoMemoryGame(pairIDs: ["a", "b", "c"], shuffled: false))
        #expect(game.select(0) == .revealed)
        #expect(game.select(2) == .mismatched)
        #expect(game.select(2) == .ignored)
        #expect(game.select(-1) == .ignored)
        #expect(game.faceUp == [0, 2])
        #expect(game.select(4) == .revealed)
        #expect(game.faceUp == [4] && game.moves == 1)
        #expect(game.select(5) == .matched)
        #expect(game.matchedPairs == ["c"] && game.moves == 2)
        #expect(game.select(4) == .ignored)
        #expect(game.select(0) == .revealed)
        #expect(game.select(1) == .matched)
        #expect(game.select(2) == .revealed)
        #expect(game.select(3) == .matched)
        #expect(game.isFinished)
    }

    @Test func interruptionPreservesTheRoundAndUnmatchedFirstCard() throws {
        var game = try #require(PhotoMemoryGame(pairIDs: ["a", "b"], shuffled: false))
        _ = game.reveal(0)
        let paused = game
        // Closing a view must not conceal a single revealed card or rebuild the deck.
        game.concealMismatch()
        #expect(game == paused)
        #expect(game.reveal(1) == .matched)
        _ = game.reveal(2)
        #expect(game.reveal(3) == .matched)
        #expect(game.isFinished && game.moves == 2)
        #expect(game.cards.allSatisfy(game.isRevealed))
        #expect(game.reveal(3) == .ignored)
    }

    @Test func shuffledDecksAlwaysHaveExactlyTwoOfEveryPicture() throws {
        for count in 2...18 {
            let pairs = (0..<count).map(String.init)
            let game = try #require(PhotoMemoryGame(pairIDs: pairs))
            #expect(game.cards.count == count * 2)
            for pair in pairs { #expect(game.cards.filter { $0.pairID == pair }.count == 2) }
        }
    }

    @Test func largeRoundCanBeCompletedWithoutLosingPairs() throws {
        var game = try #require(PhotoMemoryGame(pairIDs: (0..<18).map(String.init), shuffled: false))
        for pair in 0..<18 {
            #expect(game.reveal(pair * 2) == .revealed)
            #expect(game.reveal(pair * 2 + 1) == .matched)
        }
        #expect(game.isFinished && game.moves == 18 && game.cards.count == 36)
    }

    @Test func randomSourcesRespectFavoritesCollectionsAndExclusions() {
        let items = [
            PhotoMemorySelection.Candidate(id: "favorite", isFavorite: true),
            .init(id: "normal"), .init(id: "video", isPhoto: false, isFavorite: true),
            .init(id: "vault", isFavorite: true), .init(id: "normal"),
        ]
        #expect(PhotoMemorySelection.pool(items, scope: .library, excluding: ["vault"]) == ["favorite", "normal"])
        #expect(PhotoMemorySelection.pool(items, scope: .favorites, excluding: ["vault"]) == ["favorite"])
        #expect(PhotoMemorySelection.pool(items, scope: .collection(["normal", "video", "vault"]), excluding: ["vault"]) == ["normal"])
        #expect(PhotoMemorySelection.pool(items, scope: .collection([])).isEmpty)
    }

    @Test func randomSampleIsUniqueBoundedAndNeverAddsOtherPhotos() {
        let ids = (0..<1000).map(String.init)
        for count in [6, 12, 18] {
            let chosen = PhotoMemorySelection.sample(ids + ids, pairCount: count)
            #expect(chosen.count == count * 3)
            #expect(Set(chosen).count == chosen.count)
            #expect(Set(chosen).isSubset(of: Set(ids)))
        }
        #expect(PhotoMemorySelection.sample(["a", "b"], pairCount: 6).isEmpty)
        #expect(PhotoMemorySelection.sample(ids, pairCount: 19).isEmpty)
        #expect(PhotoMemorySelection.sample(["only"], pairCount: 1, minimumCount: 1) == ["only"])
        #expect(PhotoMemorySelection.sample(["only"], pairCount: 1).isEmpty)
    }
}
