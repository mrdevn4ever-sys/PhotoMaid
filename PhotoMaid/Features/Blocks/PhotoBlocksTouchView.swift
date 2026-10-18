import PhotoMaidCore
import SwiftUI
import UIKit

/// A single zero-delay recognizer avoids competing SwiftUI tap/drag recognizers.
struct PhotoBlocksTouchView: UIViewRepresentable {
    let cellSize: CGFloat
    let enabled: Bool
    let stateDescription: String
    let onActions: ([PhotoBlocksInput.Action]) -> Void

    func makeUIView(context: Context) -> TouchSurface {
        let view = TouchSurface()
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "blocks.board"
        view.accessibilityLabel = L("blocks_gestures")
        view.accessibilityTraits = .allowsDirectInteraction
        return view
    }
    func updateUIView(_ view: TouchSurface, context: Context) {
        view.cellSize = cellSize; view.onActions = onActions
        view.stateDescription = stateDescription
        if view.inputEnabled != enabled { view.resetInput(); view.inputEnabled = enabled }
    }

    @MainActor final class TouchSurface: UIView {
        var cellSize: CGFloat = 30
        var inputEnabled = true
        var onActions: (([PhotoBlocksInput.Action]) -> Void)?
        private var input = PhotoBlocksInput()
        private var origin = CGPoint.zero
        private var began: TimeInterval = 0
        private weak var finger: UITouch?
        var stateDescription = "" { didSet { updateAccessibilityValue() } }
        #if QA_FIXTURES && targetEnvironment(simulator)
        private let diagnostics = ProcessInfo.processInfo.arguments.contains("-game-visual-tests")
        private var lastInput = ""
        #endif

        private func updateAccessibilityValue() {
            accessibilityValue = stateDescription
            #if QA_FIXTURES && targetEnvironment(simulator)
            if diagnostics { accessibilityValue = stateDescription + " | " + lastInput }
            #endif
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear; isMultipleTouchEnabled = true
        }
        required init?(coder: NSCoder) { return nil }
        func resetInput() { input.cancel(); finger = nil }
        func cancelInput() { resetInput(); onActions?([.softDrop(false)]) }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard inputEnabled, finger == nil, let touch = touches.first else { return }
            finger = touch; origin = touch.location(in: self); began = touch.timestamp
            input.cancel()
            _ = input.changed(x: 0, y: 0, time: 0, cellSize: cellSize)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard inputEnabled, let finger, touches.contains(finger) else { return }
            let point = finger.location(in: self)
            #if QA_FIXTURES && targetEnvironment(simulator)
            if diagnostics {
                print("BLOCKS_TOUCH_MOVE t=\(finger.timestamp - began) x=\(point.x - origin.x) y=\(point.y - origin.y)")
            }
            #endif
            onActions?(input.changed(x: point.x - origin.x, y: point.y - origin.y,
                                     time: finger.timestamp - began, cellSize: cellSize))
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard inputEnabled, let finger, touches.contains(finger) else { return }
            let point = finger.location(in: self)
            let actions = input.ended(x: point.x - origin.x, y: point.y - origin.y,
                                      duration: finger.timestamp - began, time: finger.timestamp - began, cellSize: cellSize)
            #if QA_FIXTURES && targetEnvironment(simulator)
            if diagnostics {
                lastInput = String(describing: actions)
                updateAccessibilityValue()
                print("BLOCKS_TOUCH_END t=\(finger.timestamp - began) x=\(point.x - origin.x) y=\(point.y - origin.y) actions=\(actions)")
            }
            #endif
            onActions?(actions)
            self.finger = nil
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelInput() }
    }
}
