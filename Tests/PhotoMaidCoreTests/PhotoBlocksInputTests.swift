import Testing
@testable import PhotoMaidCore

struct PhotoBlocksInputTests {
    @Test func swipesMoveOnceThenRepeatByDistanceAndNeverRotate() {
        for sign in [-1.0, 1.0] {
            var input = PhotoBlocksInput()
            let first = input.changed(x: sign * 16, y: 2, time: 0.08, cellSize: 32)
            #expect(first == [sign < 0 ? .left : .right])
            let repeated = input.changed(x: sign * 80, y: 4, time: 0.25, cellSize: 32)
            #expect(repeated.count == 3)
            let end = input.ended(x: sign * 80, y: 4, duration: 0.27, time: 0.27, cellSize: 32)
            #expect(!end.contains(.rotate) && !end.contains(.hardDrop))
        }
    }
    @Test func tapRotatesExactlyOnceAndLongPressDoesNot() {
        var input = PhotoBlocksInput()
        #expect(input.ended(x: 2, y: 3, duration: 0.14, time: 0.14, cellSize: 30) == [.rotate])
        #expect(input.ended(x: 0, y: 0, duration: 0.8, time: 0.8, cellSize: 30).isEmpty)
        #expect(input.ended(x: 11, y: 11, duration: 0.1, time: 0.1, cellSize: 30).isEmpty)
    }
    @Test func slowDragSoftDropsButFastDownwardFlickHardDropsOnce() {
        var input = PhotoBlocksInput()
        #expect(input.changed(x: 2, y: 24, time: 0.12, cellSize: 30) == [.softDrop(true)])
        let slow = input.ended(x: 3, y: 100, duration: 0.9, time: 0.9, cellSize: 30)
        #expect(slow == [.softDrop(false)])
        let fast = input.ended(x: 4, y: 120, duration: 0.13, time: 0.13, cellSize: 30)
        #expect(fast.filter { $0 == .hardDrop }.count == 1)
        #expect(!fast.contains(.rotate))
        let short = input.ended(x: 0, y: 25, duration: 0.02, time: 0.02, cellSize: 30)
        #expect(!short.contains(.hardDrop))
        let up = input.ended(x: 0, y: -150, duration: 0.1, time: 0.1, cellSize: 30)
        #expect(up.isEmpty)
    }
    @Test func axisLockCancellationAndRapidSuccessiveGesturesRemainSeparate() {
        var input = PhotoBlocksInput()
        _ = input.changed(x: 20, y: 0, time: 0.03, cellSize: 30)
        #expect(!input.ended(x: 22, y: 200, duration: 0.1, time: 0.1, cellSize: 30).contains(.hardDrop))
        _ = input.changed(x: 0, y: 30, time: 0.2, cellSize: 30)
        input.cancel()
        for _ in 0..<100 {
            #expect(input.ended(x: 0, y: 0, duration: 0.05, time: 0.05, cellSize: 24) == [.rotate])
        }
        #expect(input.changed(x: .nan, y: 4, time: 1, cellSize: 30).isEmpty)
    }
    @Test func sparseTouchSamplesRepeatByDistanceWithoutDependingOnFrameRate() {
        var input = PhotoBlocksInput()
        #expect(input.changed(x: 100, y: 0, time: 0.2, cellSize: 30) == Array(repeating: .right, count: 5))
        #expect(input.changed(x: 100, y: 0, time: 0.3, cellSize: 30).isEmpty)
        #expect(input.ended(x: 100, y: 0, duration: 0.3, time: 0.3, cellSize: 30).isEmpty)
    }
    @Test func stationaryTouchUpDoesNotEraseTheFinalFastMovementSample() {
        var input = PhotoBlocksInput()
        _ = input.changed(x: 0, y: 0, time: 0, cellSize: 30)
        _ = input.changed(x: 0, y: 75, time: 0.1, cellSize: 30)
        let released = input.ended(x: 0, y: 75, duration: 0.14, time: 0.14, cellSize: 30)
        #expect(released.filter { $0 == .hardDrop }.count == 1)
        #expect(!released.contains(.rotate))
        _ = input.changed(x: 0, y: 0, time: 0, cellSize: 30)
        _ = input.changed(x: 0, y: 75, time: 0.1, cellSize: 30)
        let held = input.ended(x: 0, y: 75, duration: 0.4, time: 0.4, cellSize: 30)
        #expect(!held.contains(.hardDrop), "A stationary hold must discard stale velocity")
    }
}
