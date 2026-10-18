import XCTest

/// Real app/PhotoKit test, using the existing disposable store-capture simulator setup.
/// Not run by a workflow here; must be selected explicitly on a Mac with the fixture library.
@MainActor final class PhotoBlocksVisualTests: XCTestCase {
    func testStartTouchPausePhotosAndReturnToGames() {
        continueAfterFailure = false
        installPermissionMonitor()
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-store-capture", "-game-visual-tests", "-store-page", "feed",
                               "-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
        app.launch()
        let feed = app.descendants(matching: .any)["feed.stage"].firstMatch
        let deadline = Date().addingTimeInterval(60)
        while !feed.exists && Date() < deadline {
            resolvePrivacyPrompts(in: app, prefix: "blocks", photos: true)
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(feed.exists)
        app.buttons["feed.memory"].tap()
        let blocks = app.buttons["games.blocks"]
        XCTAssertTrue(blocks.waitForExistence(timeout: 5))
        if !blocks.isHittable { app.swipeUp() }
        blocks.tap()
        let start = app.buttons["blocks.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        checkpoint("blocks_start", app: app)
        start.tap()
        let board = app.descendants(matching: .any)["blocks.board"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(board.frame.width, 180)
        XCTAssertLessThanOrEqual(board.frame.maxX, app.windows.firstMatch.frame.maxX)
        XCTAssertTrue(app.buttons["blocks.pause"].isHittable)
        checkpoint("blocks_playing", app: app)
        func position() -> [Int] {
            (board.value as? String ?? "").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let before = position()
        XCTAssertEqual(before.count, 3)
        board.tap()
        XCTAssertEqual(position().last, before.last.map { ($0 + 1) % 4 }, "One tap rotates exactly once")
        let beforeLeft = position()
        board.swipeLeft()
        XCTAssertLessThan(position().first ?? 99, beforeLeft.first ?? 0)
        let beforeRight = position()
        board.swipeRight()
        XCTAssertGreaterThan(position().first ?? 0, beforeRight.first ?? 99)
        board.swipeDown(velocity: .fast)
        let placed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != 'Score: 0'"), object: app.staticTexts["blocks.score"])
        XCTAssertEqual(XCTWaiter.wait(for: [placed], timeout: 3), .completed, "Fast downward flick must place the piece")
        let dropScore = app.staticTexts["blocks.score"].label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first ?? 0
        XCTAssertGreaterThan(dropScore, 5, "Hard Drop also awards the actually dropped distance")
        app.buttons["blocks.pause"].tap()
        let resume = app.buttons["blocks.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        let score = app.staticTexts["blocks.score"].label
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.staticTexts["blocks.score"].label, score)
        checkpoint("blocks_paused", app: app)
        resume.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "Backgrounding must require explicit resume")
        app.buttons["Fotos ändern"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["blocks.source"].firstMatch.waitForExistence(timeout: 3))
        checkpoint("blocks_photos", app: app)
        app.buttons["Fertig"].firstMatch.tap()
        app.buttons["blocks.back"].tap()
        XCTAssertTrue(app.buttons["games.snake"].waitForExistence(timeout: 5))
    }
}
