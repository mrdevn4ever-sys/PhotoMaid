import XCTest

/// Real SwiftUI/PhotoKit on disposable simulators; imported synthetic images are labelled QA.
/// Wide-device runs verify window adaptation. They are not a claim of fold/unfold hardware validation.
@MainActor final class PhotoGameVisualTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
        installPermissionMonitor()
        app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ page: String = "feed", light: Bool = false, language: String = "en") {
        app.launchArguments = ["-store-capture", "-game-visual-tests", "-store-page", page, "-AppleLanguages", "(\(language))", "-AppleLocale", "en_US"]
        if light { app.launchArguments.append("-capture-light") }
        app.launch()
        waitForPage(page)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func waitForPage(_ page: String) {
        let ready = page == "feed" ? app.descendants(matching: .any)["feed.stage"].firstMatch : app.windows["store.capture." + page]
        let deadline = Date().addingTimeInterval(60)
        repeat {
            resolvePrivacyPrompts(in: app, prefix: "games_" + page, photos: true)
            if ready.exists { return }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        XCTAssertTrue(ready.exists, "The actual page and its photo library must be ready: \(page)")
    }

    private func openGame(_ name: String) {
        app.buttons["feed.memory"].tap()
        let game = app.buttons["games." + name]
        XCTAssertTrue(game.waitForExistence(timeout: 5)); game.tap()
    }

    func test10MemoryPhotosWinAndPersistentRecord() throws {
        launch(light: true)
        openGame("memory")
        checkpoint("memory_01_setup_light", app: app)
        app.buttons["memory.startPhotos"].tap()
        let first = app.buttons["memory.card.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'"))
        XCTAssertEqual(cards.count, 24, "The default photo round has twelve pairs")
        for card in cards.allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(card.frame.width, 44)
            XCTAssertGreaterThanOrEqual(card.frame.height, 44)
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(card.frame), "Card must fit: \(card.identifier)")
        }
        checkpoint("memory_02_photos_board_light", app: app)
        var known: [String: [String]] = [:]
        var unseen = cards.allElementsBoundByIndex.map(\.identifier)
        var solved: Set<String> = []
        for _ in 0..<40 {
            if app.descendants(matching: .any)["memory.finished"].exists { break }
            let firstID: String
            let plannedSecond: String?
            if let pair = known.values.first(where: { $0.count == 2 && !$0.contains(where: solved.contains) }) {
                firstID = pair[0]; plannedSecond = pair[1]
            } else {
                guard let next = unseen.first else { XCTFail("No remaining known pair"); return }
                firstID = next; unseen.removeFirst(); plannedSecond = nil
            }
            let a = app.buttons[firstID]; a.tap()
            let value = (a.value as? String ?? "").split(whereSeparator: { !$0.isNumber }).last.map(String.init) ?? ""
            XCTAssertFalse(value.isEmpty)
            let secondID: String
            if let plannedSecond { secondID = plannedSecond }
            else if let match = known[value]?.first(where: { $0 != firstID && !solved.contains($0) }) { secondID = match }
            else {
                guard let next = unseen.first else { XCTFail("Unpaired card"); return }
                secondID = next; unseen.removeFirst()
            }
            if known[value]?.contains(firstID) != true { known[value, default: []].append(firstID) }
            let b = app.buttons[secondID]; b.tap()
            let secondValue = (b.value as? String ?? "").split(whereSeparator: { !$0.isNumber }).last.map(String.init) ?? ""
            if secondValue == value {
                solved.formUnion([firstID, secondID]); known.removeValue(forKey: value)
            } else {
                if known[secondValue]?.contains(secondID) != true { known[secondValue, default: []].append(secondID) }
                // Wait through the real automatic flip. Tap only if the viewport requires manual flipping.
                let concealed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: a)
                if XCTWaiter.wait(for: [concealed], timeout: 2) != .completed {
                    let flip = app.buttons["memory.flip"]
                    XCTAssertTrue(flip.isEnabled); flip.tap()
                }
            }
        }
        XCTAssertTrue(app.descendants(matching: .any)["memory.finished"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["memory.best"].label.contains("No record"))
        checkpoint("memory_03_victory_record_light", app: app)
        app.buttons["memory.close"].tap()
        app.buttons["feed.memory"].tap()
        app.buttons["games.records"].tap()
        checkpoint("games_04_saved_records", app: app)
        app.terminate()
        launch()
        app.buttons["feed.memory"].tap(); app.buttons["games.records"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '12 pairs'")).firstMatch.waitForExistence(timeout: 5))
        checkpoint("games_05_record_after_relaunch", app: app)
    }

    func test20SnakeControlsFoodHighscoreAndPause() throws {
        launch()
        openGame("snake")
        checkpoint("snake_01_setup_dark", app: app)
        let stepSwitch = app.switches["snake.stepMode"]
        XCTAssertTrue(stepSwitch.waitForExistence(timeout: 5)); stepSwitch.tap()
        // Use the real photo loader and all source defaults.
        app.buttons["snake.prepare"].tap()
        let board = app.descendants(matching: .any)["snake.board"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 30))
        XCTAssertGreaterThanOrEqual(board.frame.height, 256)
        checkpoint("snake_02_photos_paused_dark", app: app)
        let initial = board.value as? String ?? ""
        let numbers = initial.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertGreaterThanOrEqual(numbers.count, 4)
        guard numbers.count >= 4 else { return }
        var x = numbers[0], y = numbers[1]
        let foodX = numbers[2], foodY = numbers[3]
        app.buttons["snake.toggleRunning"].tap()
        func move(_ direction: String) { app.buttons["snake.direction." + direction].tap() }
        if foodY == y && foodX < x { move("up"); y -= 1 }
        if foodY != numbers[1] {
            while y < foodY { move("down"); y += 1 }
            while y > foodY { move("up"); y -= 1 }
        }
        while x < foodX { move("right"); x += 1 }
        while x > foodX { move("left"); x -= 1 }
        while y < foodY { move("down"); y += 1 }
        XCTAssertTrue(app.staticTexts["snake.score"].label.contains("1"))
        XCTAssertTrue(app.staticTexts["snake.best"].label.contains("1"))
        app.buttons["snake.toggleRunning"].tap()
        let paused = board.value as? String
        XCTAssertFalse(app.buttons["snake.direction.up"].isEnabled)
        XCTAssertEqual(board.value as? String, paused, "Paused controls must not move the camera")
        checkpoint("snake_03_collected_record_dark", app: app)
        app.buttons["snake.close"].tap()
        let position = app.descendants(matching: .any)["feed.position"].firstMatch.label
        app.buttons["feed.memory"].tap(); app.buttons["games.snake"].tap()
        XCTAssertEqual(board.value as? String, paused)
        app.buttons["snake.close"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["feed.position"].firstMatch.label, position)
    }

    func test30PortraitAndExpandedWorkspaceScreens() {
        launch(light: true)
        let position = app.descendants(matching: .any)["feed.position"].firstMatch
        XCTAssertGreaterThanOrEqual(position.frame.width, 70, "The feed title and counter must retain readable width")
        XCTAssertLessThan(position.frame.height, 70, "The counter must not wrap into a vertical column")
        XCTAssertGreaterThanOrEqual(app.buttons["feed.memory"].frame.width, 44)
        checkpoint("workspace_01_feed", app: app)
        let wide = app.frame.width >= 540
        let panel = app.descendants(matching: .any)["feed.basketPanel"].firstMatch
        XCTAssertEqual(panel.exists, wide)
        if wide {
            let stage = app.descendants(matching: .any)["feed.stage"].firstMatch
            XCTAssertLessThan(panel.frame.maxX, stage.frame.minX)
            for _ in 0..<8 {
                stage.swipeLeft()
                if app.alerts.firstMatch.waitForExistence(timeout: 1) {
                    app.alerts.buttons["Cancel"].tap()
                    stage.swipeUp()
                } else { break }
            }
            XCTAssertTrue(app.buttons["feed.basket.restore"].firstMatch.waitForExistence(timeout: 10))
            checkpoint("workspace_02_live_basket", app: app)
        } else {
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertLessThan(app.frame.width, app.frame.height, "Normal iPhone stays in portrait")
            XCUIDevice.shared.orientation = .portrait
        }
        app.terminate()
        for page in ["today", "library", "cleanup", "studio", "history", "editor", "collage", "settings", "vault"] {
            launch(page, light: page != "editor")
            if page == "editor" {
                XCTAssertTrue(app.descendants(matching: .any)["editor.stage"].firstMatch.waitForExistence(timeout: 25))
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                    object: app.descendants(matching: .any)["editor.preview.rendering"].firstMatch)
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
            }
            checkpoint("workspace_" + page, app: app)
            app.terminate()
        }
    }

    func test40LargeTextAndArabic() {
        app.launchArguments = ["-store-capture", "-game-visual-tests", "-store-page", "feed", "-AppleLanguages", "(ar)",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        waitForPage("feed")
        openGame("memory")
        let motifs = app.buttons["memory.startMotifs"]
        for _ in 0..<6 where !motifs.isHittable { app.swipeUp() }
        motifs.tap()
        XCTAssertTrue(app.buttons["memory.card.0"].waitForExistence(timeout: 10))
        checkpoint("memory_accessibility_arabic", app: app)
        app.buttons["memory.close"].tap()
        openGame("snake")
        let symbols = app.buttons["snake.symbols"]
        for _ in 0..<6 where !symbols.isHittable { app.swipeUp() }
        symbols.tap()
        XCTAssertTrue(app.descendants(matching: .any)["snake.board"].firstMatch.waitForExistence(timeout: 10))
        checkpoint("snake_accessibility_arabic", app: app)
    }

    func test50FavoritesAndFolderSources() {
        launch(light: true)
        openGame("memory")
        app.buttons["memory.source"].tap()
        app.buttons["Favorites"].firstMatch.tap()
        app.buttons["memory.size"].tap()
        app.buttons["6 pairs (12 cards)"].firstMatch.tap()
        app.buttons["memory.startPhotos"].tap()
        XCTAssertTrue(app.buttons["memory.card.0"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'")).count, 12)
        checkpoint("memory_favorites_six_pairs", app: app)
        app.buttons["memory.close"].tap()
        app.terminate(); launch(light: true); openGame("memory")
        app.buttons["memory.source"].tap()
        app.buttons["Album or photo folder"].firstMatch.tap()
        app.buttons["memory.chooseCollection"].tap()
        let folder = app.buttons.matching(NSPredicate(format: "label CONTAINS 'QA Game Folder'")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15)); folder.tap()
        app.buttons["memory.startPhotos"].tap()
        XCTAssertTrue(app.buttons["memory.card.0"].waitForExistence(timeout: 30))
        checkpoint("memory_folder_with_subalbum", app: app)
    }

    func test60SnakeRealtimeDriverAndPause() {
        launch(light: true)
        openGame("snake")
        app.buttons["snake.symbols"].tap()
        let board = app.descendants(matching: .any)["snake.board"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        let initial = board.value as? String ?? ""
        app.buttons["snake.toggleRunning"].tap()
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initial), object: board)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 3), .completed)
        app.buttons["snake.toggleRunning"].tap()
        let paused = board.value as? String
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(board.value as? String, paused)
        checkpoint("snake_realtime_paused_after_movement", app: app)
    }
}
