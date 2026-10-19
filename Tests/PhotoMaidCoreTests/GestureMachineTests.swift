import Testing
@testable import PhotoMaidCore

/// Port von `GestureMachineTest.kt` (Android): keine Diagonale, Schwellen 72/380/20, lockRatio 1,3.
@Suite struct GestureMachineTests {
    @Test("A pinch or accessibility suspension cancels a locked swipe without a decision",
          arguments: [Vector2(0, -100), Vector2(-100, 0), Vector2(100, 0), Vector2(0, 100)])
    func suspensionCancelsInFlightSwipe(_ translation: Vector2) {
        var machine = FeedGestureMachine()
        machine.update(translation: translation)
        machine.isSuspended = true
        machine.cancel() // FeedViewModel.setSuspended uses this same sequence.
        #expect(machine.end(translation: translation, velocity: .zero) == .ignored)
        #expect(machine.phase == .idle)
        machine.isSuspended = false
        machine.update(translation: translation)
        #expect(machine.end(translation: translation, velocity: .zero) != .ignored)
    }

    @Test("Further drags cannot replace a pending decision before persistence completes")
    func pendingCommitKeepsOriginalDirection() {
        var machine = FeedGestureMachine()
        machine.update(translation: Vector2(-100, 0))
        #expect(machine.end(translation: Vector2(-100, 0), velocity: .zero) == .commit(.left))
        machine.update(translation: Vector2(100, 0))
        #expect(machine.phase == .commitRequested(.left))
        #expect(machine.end(translation: Vector2(100, 0), velocity: .zero) == .ignored)
        machine.finishCommit()
        #expect(machine.phase == .idle)
    }

    @discardableResult
    func swipe(_ m: inout FeedGestureMachine, _ t: Vector2, velocity: Vector2 = .zero, steps: Int = 8)
        -> FeedGestureMachine.Resolution {
        for i in 1...steps {
            let f = Double(i) / Double(steps)
            m.update(translation: Vector2(t.dx * f, t.dy * f))
        }
        return m.end(translation: t, velocity: velocity)
    }

    func swipe(_ t: Vector2, velocity: Vector2 = .zero, steps: Int = 8) -> FeedGestureMachine.Resolution {
        var m = FeedGestureMachine()
        return swipe(&m, t, velocity: velocity, steps: steps)
    }

    /// Anzeige „Loslassen entscheidet jetzt“ entspricht exakt der Commit-Bedingung ohne Schwung.
    @Test func readyToCommitMatchesCommitCondition() {
        for t in [Vector2(0, -200), Vector2(-200, 0), Vector2(200, -120), Vector2(0, -60), Vector2(120, -160), Vector2(0, 200)] {
            var m = FeedGestureMachine()
            for i in 1...8 { m.update(translation: Vector2(t.dx * Double(i) / 8, t.dy * Double(i) / 8)) }
            let ready = m.readyToCommit
            let committed = { if case .commit = m.end(translation: t, velocity: .zero) { return true } else { return false } }()
            let isDown = t.dy > 0 && t.dx == 0
            #expect(ready == (committed && !isDown), "\(t)")
        }
        #expect(!FeedGestureMachine().readyToCommit)
    }

    @Test func directionsMatchFingerMovement() {
        for (t, expected) in [(Vector2(0, -200), SwipeDirection.up), (Vector2(0, 200), .down),
                              (Vector2(-200, 0), .left), (Vector2(200, 0), .right)] {
            var m = FeedGestureMachine()
            #expect(swipe(&m, t) == .commit(expected))
            #expect(m.phase == .commitRequested(expected))
        }
    }

    @Test func fixedMeaning() {
        #expect(FeedIntent(.up) == .keep)
        #expect(FeedIntent(.left) == .markForCleanup)
        #expect(FeedIntent(.right) == .later)
        #expect(FeedIntent(.down) == .previous)
        #expect(!FeedIntent.previous.isDecision)
        #expect(FeedIntent.laterCustom.isDecision)
    }

    @Test func diagonalLeftDoesNothing() {
        var m = FeedGestureMachine()
        #expect(swipe(&m, Vector2(-150, -150)) == .cancelled)
        #expect(swipe(&m, Vector2(-150, 150)) == .cancelled)
        #expect(m.phase == .idle)
    }

    /// Ohne Diagonale (E2): schräg rechts oben oder unten bis 45° ist „rechts“ = Später.
    @Test func rightVariants() {
        for t in [Vector2(180, -130), Vector2(200, -100), Vector2(200, -190), Vector2(200, -60), Vector2(180, 120), Vector2(200, 0)] {
            #expect(swipe(t) == .commit(.right), "\(t)")
        }
    }

    @Test func rightDeadZones() {
        var m = FeedGestureMachine()
        #expect(swipe(&m, Vector2(140, -160)) == .cancelled) // ≈ 49° nach oben: Totzone
        #expect(swipe(&m, Vector2(140, 165)) == .cancelled)  // ≈ 50° nach unten: Totzone
        #expect(swipe(Vector2(120, -160)) == .commit(.up))   // ≈ 53°: „hoch“
        #expect(swipe(Vector2(60, -200)) == .commit(.up))
    }

    @Test func rightFollowsHorizontally() {
        var m = FeedGestureMachine()
        m.update(translation: Vector2(90, -60))
        #expect(m.lockedDirection == .right)
        #expect(m.displayOffset == Vector2(90, 0))
        m.cancel()
        m.update(translation: Vector2(90, 30))
        #expect(m.lockedDirection == .right)
        #expect(m.displayOffset == Vector2(90, 0))
    }

    @Test func tooShortIsCancelled() {
        var m = FeedGestureMachine()
        #expect(swipe(&m, Vector2(0, -60)) == .cancelled)
        #expect(m.phase == .idle)
    }

    @Test func flickSufficesWithMinimumDistance() {
        #expect(swipe(Vector2(-50, 0), velocity: Vector2(-900, 0)) == .commit(.left))
    }

    @Test func flickAgainstDirectionDoesNotCommit() {
        #expect(swipe(Vector2(-50, 0), velocity: Vector2(900, 0)) == .cancelled)
    }

    @Test func reversalSwitchesDirectionNotTwoActions() {
        var m = FeedGestureMachine()
        m.update(translation: Vector2(0, -80))
        #expect(m.lockedDirection == .up)
        m.update(translation: Vector2(0, -10))
        #expect(m.lockedDirection == .up)
        m.update(translation: Vector2(0, 40))
        #expect(m.lockedDirection == .down)
        #expect(m.end(translation: Vector2(0, 160), velocity: .zero) == .commit(.down))
    }

    @Test func axisOffsetAfterLock() {
        var m = FeedGestureMachine()
        m.update(translation: Vector2(8, -90))
        #expect(m.displayOffset == Vector2(0, -90))
    }

    @Test func suspendedIgnoresGestures() {
        var m = FeedGestureMachine()
        m.isSuspended = true
        #expect(swipe(&m, Vector2(0, -300)) == .ignored)
        #expect(m.phase == .idle)
    }

    @Test func noDoubleCommit() {
        var m = FeedGestureMachine()
        #expect(swipe(&m, Vector2(0, -200)) == .commit(.up))
        #expect(swipe(&m, Vector2(0, -200)) == .ignored)
        m.finishCommit()
        #expect(m.phase == .idle)
    }

    @Test func systemCancelReturnsToIdle() {
        var m = FeedGestureMachine()
        m.update(translation: Vector2(0, -200))
        m.cancel()
        #expect(m.phase == .idle)
        #expect(m.end(translation: Vector2(0, -200), velocity: .zero) == .ignored)
    }

    @Test func slowLongDragCommitsShortDoesNot() {
        #expect(swipe(Vector2(3, -120), steps: 60) == .commit(.up))
        #expect(swipe(Vector2(0, -30), velocity: Vector2(0, -300)) == .cancelled)
    }

    /// Masterprompt: mehrfach schnelles Wischen – jede Geste höchstens ein Schritt, auch ohne `finishCommit`.
    @Test func rapidRepeatedSwipesNeverDoubleCommit() {
        var m = FeedGestureMachine()
        var commits = 0
        for _ in 0..<10 { if case .commit = swipe(&m, Vector2(0, -200), velocity: Vector2(0, -2000)) { commits += 1 } }
        #expect(commits == 1)
    }
}
