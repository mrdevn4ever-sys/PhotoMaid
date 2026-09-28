import Testing
@testable import PhotoMaidCore

@Suite("Gesten-State-Machine")
struct GestureMachineTests {
    func swipe(_ m: inout FeedGestureMachine, _ t: Vector2, velocity: Vector2 = .zero, steps: Int = 8) -> FeedGestureMachine.Resolution {
        for i in 1...steps {
            let f = Double(i) / Double(steps)
            m.update(translation: Vector2(t.dx * f, t.dy * f))
        }
        return m.end(translation: t, velocity: velocity)
    }

    @Test("Jede Richtung entspricht der tatsächlichen Fingerbewegung",
          arguments: [(Vector2(0, -200), SwipeDirection.up), (Vector2(0, 200), .down),
                      (Vector2(-200, 0), .left), (Vector2(200, 0), .right)])
    func directions(_ t: Vector2, _ expected: SwipeDirection) {
        var m = FeedGestureMachine()
        #expect(swipe(&m, t) == .commit(expected))
        #expect(m.phase == .commitRequested(expected))
    }

    @Test("Feste Bedeutung: hoch=Behalten, links=Vormerken, rechts=Später, runter=Vorheriges")
    func mapping() {
        #expect(FeedIntent(.up) == .keep)
        #expect(FeedIntent(.left) == .markForCleanup)
        #expect(FeedIntent(.right) == .later)
        #expect(FeedIntent(.down) == .previous)
        #expect(!FeedIntent.previous.isDecision)
    }

    @Test("Diagonale Bewegung löst keine Aktion aus")
    func diagonal() {
        var m = FeedGestureMachine()
        #expect(swipe(&m, Vector2(150, -150)) == .cancelled)
        #expect(m.phase == .idle)
    }

    @Test("Zu kurze Bewegung wird abgebrochen, keine Entscheidung")
    func tooShort() {
        var m = FeedGestureMachine()
        #expect(swipe(&m, Vector2(0, -60)) == .cancelled)
        #expect(m.phase == .idle)
    }

    @Test("Schwung genügt bei Mindeststrecke")
    func flick() {
        var m = FeedGestureMachine()
        #expect(swipe(&m, Vector2(-50, 0), velocity: Vector2(-900, 0)) == .commit(.left))
    }

    @Test("Schwung gegen die gebundene Richtung committet nicht")
    func flickOpposite() {
        var m = FeedGestureMachine()
        #expect(swipe(&m, Vector2(-50, 0), velocity: Vector2(900, 0)) == .cancelled)
    }

    @Test("Hysterese: Umkehr über den Nullpunkt wechselt die Richtung, nicht zwei Aktionen")
    func reversal() {
        var m = FeedGestureMachine()
        m.update(translation: Vector2(0, -80))
        #expect(m.lockedDirection == .up)
        m.update(translation: Vector2(0, -10))
        #expect(m.lockedDirection == .up) // noch über unlockDistance
        m.update(translation: Vector2(0, 40))
        #expect(m.lockedDirection == .down)
        #expect(m.end(translation: Vector2(0, 160), velocity: .zero) == .commit(.down))
    }

    @Test("Medium folgt nach Bindung nur der Achse")
    func axisOffset() {
        var m = FeedGestureMachine()
        m.update(translation: Vector2(8, -90))
        #expect(m.displayOffset == Vector2(0, -90))
    }

    @Test("Während Zoom/Control/VoiceOver: keine Entscheidungsgesten")
    func suspended() {
        var m = FeedGestureMachine()
        m.isSuspended = true
        #expect(swipe(&m, Vector2(0, -300)) == .ignored)
        #expect(m.phase == .idle)
    }

    @Test("Während commitRequested werden weitere Gesten ignoriert (max. ein Schritt)")
    func noDoubleCommit() {
        var m = FeedGestureMachine()
        #expect(swipe(&m, Vector2(0, -200)) == .commit(.up))
        #expect(swipe(&m, Vector2(0, -200)) == .ignored)
        m.finishCommit()
        #expect(m.phase == .idle)
    }

    @Test("Systemabbruch führt zurück nach idle")
    func systemCancel() {
        var m = FeedGestureMachine()
        m.update(translation: Vector2(0, -200))
        m.cancel()
        #expect(m.phase == .idle)
        #expect(m.end(translation: Vector2(0, -200), velocity: .zero) == .ignored)
    }
}
