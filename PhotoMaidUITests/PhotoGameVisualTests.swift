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

    private func launch(_ page: String = "feed", light: Bool = false, language: String = "en", snakeSteps: Bool = false, pdfFiles: Bool = false) {
        app.launchArguments = ["-store-capture", "-game-visual-tests", "-store-page", page, "-AppleLanguages", "(\(language))", "-AppleLocale", "en_US"]
        if light { app.launchArguments.append("-capture-light") }
        if snakeSteps { app.launchArguments.append("-snake-swipe-steps") }
        if pdfFiles { app.launchArguments.append("-pdf-editor-fixtures") }
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

    func test05SimpleSetupCloudAndManualPhotoChoice() {
        launch(light: true, language: "de")
        openGame("memory")
        XCTAssertTrue(app.navigationBars["Paare"].waitForExistence(timeout: 5))
        let memoryCloud = app.switches["memory.cloud"]
        XCTAssertEqual(memoryCloud.value as? String, "1")
        checkpoint("pairs_setup_default_cloud_on", app: app)
        memoryCloud.tap()
        XCTAssertEqual(memoryCloud.value as? String, "0")
        app.buttons["memory.startPhotos"].tap()
        XCTAssertTrue(app.buttons["memory.card.0"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'")).count, 24)
        app.buttons["memory.change"].tap()
        XCTAssertEqual(memoryCloud.value as? String, "0", "The user's explicit choice survives round preparation")
        checkpoint("pairs_setup_keeps_cloud_opt_out", app: app)
        app.buttons["memory.close"].tap()

        openGame("snake")
        XCTAssertTrue(app.buttons["snake.source"].label.contains("Gesamte Mediathek"))
        checkpoint("snake_setup_default_library_cloud_on", app: app)
        let options = app.descendants(matching: .any)["snake.options"].firstMatch
        options.tap()
        XCTAssertEqual(app.switches["snake.cloud"].value as? String, "1")
        XCTAssertTrue(app.buttons["snake.mode"].exists)
        XCTAssertTrue(app.buttons["snake.speed"].exists)
        checkpoint("snake_setup_labelled_options", app: app)
        options.tap()

        app.buttons["snake.source"].tap()
        app.buttons["Eigene Fotos wählen"].firstMatch.tap()
        XCTAssertTrue(app.buttons["snake.prepare"].label.contains("Spiel starten"))
        XCTAssertFalse(app.buttons["snake.prepare"].isEnabled)
        XCTAssertTrue(app.buttons["snake.editPhotos"].label.contains("Fotos auswählen"))
        app.buttons["snake.editPhotos"].tap()
        XCTAssertTrue(app.buttons["snake.gallery.add"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["snake.board"].exists, "Empty manual selection must open photo selection instead of a placeholder game")
        checkpoint("snake_empty_manual_choice_opens_gallery", app: app)
        app.buttons["Fertig"].firstMatch.tap()
        app.buttons["snake.source"].tap()
        app.buttons["Gesamte Mediathek"].firstMatch.tap()
        app.buttons["snake.prepare"].tap()
        let board = app.descendants(matching: .any)["snake.board"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 30))
        assertFullscreenSnake(board)
        board.swipeUp()
        let before = board.value as? String ?? ""
        let moving = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: board)
        XCTAssertEqual(XCTWaiter.wait(for: [moving], timeout: 3), .completed)
        checkpoint("snake_simple_setup_real_photo_game", app: app)
        app.buttons["snake.pause"].tap()
        app.buttons["snake.otherGames"].tap()
        XCTAssertTrue(app.buttons["games.memory"].waitForExistence(timeout: 5), "Games returns to the actual chooser")
        checkpoint("games_chooser_after_snake_pause", app: app)
        app.buttons["games.memory"].tap()
        app.buttons["memory.change"].tap()
        checkpoint("pairs_after_snake_uses_app_appearance", app: app)
    }

    func test70UnavailableVideosCanBePassed() {
        launch("feed-failures", language: "de")
        let stage = app.descendants(matching: .any)["feed.stage"].firstMatch
        let position = app.descendants(matching: .any)["feed.position"].firstMatch
        let failed = app.descendants(matching: .any)["feed.preview.failed"].firstMatch
        XCTAssertTrue(failed.waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts.matching(identifier: "feed.preview.failed").count, 1,
                       "Hidden neighbor errors must not appear in accessibility")
        XCTAssertTrue(position.label.contains("1 von 3"))
        let trash = app.buttons["feed.dock"].label
        checkpoint("feed_unavailable_video_01", app: app)
        // An unseen video must not silently become a Trash or Keep decision.
        stage.swipeLeft()
        XCTAssertEqual(app.buttons["feed.dock"].label, trash)
        XCTAssertTrue(position.label.contains("1 von 3"))
        app.buttons["feed.retryPreview"].tap()
        XCTAssertTrue(failed.waitForExistence(timeout: 10))
        app.buttons["feed.skipUnavailable"].tap()
        waitForPosition("2 von 3")
        XCTAssertTrue(failed.waitForExistence(timeout: 10))
        checkpoint("feed_unavailable_video_02", app: app)
        app.buttons["feed.skipUnavailable"].tap()
        waitForPosition("3 von 3")
        XCTAssertEqual(app.buttons["feed.dock"].label, trash)
        XCTAssertFalse(failed.exists)
        checkpoint("feed_after_two_unavailable_videos", app: app)
        // Real process restart, Core Data and the same original identifiers: no test-store reset.
        app.terminate()
        launch("feed-failures", language: "de")
        waitForPosition("1 von 1")
        XCTAssertFalse(failed.exists)
        XCTAssertEqual(app.buttons["feed.dock"].label, trash)
        checkpoint("feed_skips_survive_relaunch", app: app)
        app.buttons["feed.close"].tap()
        let retry = app.buttons["hub.retrySkipped"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        checkpoint("feed_skipped_retry_in_cleanup", app: app)
        retry.tap()
        waitForPosition("1 von 2")
        XCTAssertTrue(failed.waitForExistence(timeout: 15))
        checkpoint("feed_explicit_retry_skipped_videos", app: app)
    }

    func test80VideoPlaysWithoutPoster() {
        launch("feed-posterless", light: true)
        let ready = app.descendants(matching: .any)["feed.video.ready"].firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 30), "The actual AVPlayerLayer must display a frame even without a poster")
        XCTAssertFalse(app.descendants(matching: .any)["feed.preview.failed"].exists)
        checkpoint("feed_video_without_poster_plays", app: app)
        app.descendants(matching: .any)["feed.stage"].firstMatch.swipeUp()
        waitForPosition("2 of 2")
        XCTAssertFalse(ready.exists)
        checkpoint("feed_after_video_without_poster", app: app)
    }

    func test85VideoPosterAllowsDecisionsBeforePlayback() {
        launch("feed-video-posters")
        let stage = app.descendants(matching: .any)["feed.stage"].firstMatch
        let poster = app.descendants(matching: .any)["feed.video.poster"].firstMatch
        let frame = app.descendants(matching: .any)["feed.video.ready"].firstMatch
        waitForPosition("1 of 4")
        let trash = app.buttons["feed.dock"].label
        stage.swipeUp()
        waitForPosition("2 of 4")
        XCTAssertTrue(poster.waitForExistence(timeout: 10))
        XCTAssertFalse(frame.exists, "Playback is still preparing; the real poster must suffice")
        checkpoint("feed_video_poster_before_playback", app: app)
        stage.swipeLeft()
        waitForPosition("3 of 4")
        XCTAssertNotEqual(app.buttons["feed.dock"].label, trash)
        XCTAssertTrue(poster.waitForExistence(timeout: 10))
        XCTAssertFalse(frame.exists)
        stage.swipeUp()
        waitForPosition("4 of 4")
        let afterTrash = app.buttons["feed.dock"].label
        // Return to the same video without a player frame. Its retained image must be usable again.
        stage.swipeDown()
        waitForPosition("3 of 4")
        XCTAssertTrue(poster.waitForExistence(timeout: 5))
        XCTAssertFalse(frame.exists)
        stage.swipeRight()
        waitForPosition("4 of 4")
        XCTAssertEqual(app.buttons["feed.dock"].label, afterTrash)
        checkpoint("feed_video_posters_three_decisions_without_playback", app: app)
    }

    func test90LoadingPhotoCanBePassed() {
        launch("feed-slow")
        XCTAssertTrue(app.descendants(matching: .any)["feed.preview.loading"].firstMatch.waitForExistence(timeout: 15))
        let trash = app.buttons["feed.dock"].label
        checkpoint("feed_slow_download_skip_available", app: app)
        app.buttons["feed.skipUnavailable"].tap()
        waitForPosition("2 of 2")
        XCTAssertEqual(app.buttons["feed.dock"].label, trash)
        XCTAssertFalse(app.descendants(matching: .any)["feed.preview.failed"].exists)
        checkpoint("feed_after_slow_download", app: app)
    }

    private func waitForPosition(_ value: String) {
        let position = app.descendants(matching: .any)["feed.position"].firstMatch
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", value), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 8), .completed)
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
        launch(snakeSteps: true)
        openGame("snake")
        checkpoint("snake_01_setup_dark", app: app)
        // Use real PhotoKit thumbnails from the explicitly selected disposable QA library.
        // The production default uses the actual library; manual PhotosPicker selection remains available.
        app.buttons["snake.source"].tap()
        app.buttons["Entire photo library"].firstMatch.tap()
        app.buttons["snake.prepare"].tap()
        let board = app.descendants(matching: .any)["snake.board"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 30))
        checkpoint("snake_02_fullscreen_ready_dark", app: app)
        assertFullscreenSnake(board)
        func move(_ direction: String) {
            switch direction {
            case "up": board.swipeUp()
            case "down": board.swipeDown()
            case "left": board.swipeLeft()
            default: board.swipeRight()
            }
        }
        // Explicit QA step driver isolates gesture routing from XCTest's input latency.
        // test60 separately exercises the real clock, with the same visible swipe-only surface.
        move("up")
        var previous = "up"
        let opposite = ["up": "down", "down": "up", "left": "right", "right": "left"]
        for _ in 0..<90 {
            if app.staticTexts["snake.score"].label.contains("1") { break }
            let n = (board.value as? String ?? "").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            XCTAssertGreaterThanOrEqual(n.count, 4)
            guard n.count >= 4 else { return }
            var direction = n[0] != n[2] ? (n[0] < n[2] ? "right" : "left") : (n[1] < n[3] ? "down" : "up")
            if direction == opposite[previous] { direction = ["up", "down"].contains(previous) ? "right" : "down" }
            move(direction); previous = direction
        }
        XCTAssertTrue(app.staticTexts["snake.score"].label.contains("1"))
        XCTAssertTrue(app.staticTexts["snake.best"].label.contains("1"))
        checkpoint("snake_03_fullscreen_collected_record_dark", app: app)
        let beforeClose = board.value as? String
        closeSnake()
        let position = app.descendants(matching: .any)["feed.position"].firstMatch.label
        openGame("snake")
        XCTAssertTrue(app.buttons["snake.resume"].waitForExistence(timeout: 5))
        app.buttons["snake.resume"].tap()
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        XCTAssertEqual(board.value as? String, beforeClose)
        assertFullscreenSnake(board)
        closeSnake()
        XCTAssertEqual(app.descendants(matching: .any)["feed.position"].firstMatch.label, position)
    }

    private func closeSnake() {
        app.descendants(matching: .any)["snake.play"].firstMatch.buttons["snake.close"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                               object: app.descendants(matching: .any)["snake.play"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["feed.memory"].isHittable)
    }

    private func assertFullscreenSnake(_ board: XCUIElement) {
        XCTAssertGreaterThanOrEqual(board.frame.width, app.frame.width - 12)
        XCTAssertGreaterThanOrEqual(board.frame.height, app.frame.height * 0.72, "The board fills the window below the safe HUD")
        let surface = app.descendants(matching: .any)["snake.play"].firstMatch
        XCTAssertTrue(surface.exists)
        for identifier in ["snake.close", "snake.pause", "snake.settings"] {
            let control = surface.buttons[identifier]
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
        XCTAssertFalse(app.buttons["snake.toggleRunning"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'snake.direction.'")).count, 0)
    }

    func test30PortraitAndExpandedWorkspaceScreens() {
        launch(light: true)
        let position = app.descendants(matching: .any)["feed.position"].firstMatch
        XCTAssertGreaterThanOrEqual(position.frame.width, 60, "The feed title and counter must retain readable width")
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
            if page == "library" {
                XCTAssertGreaterThanOrEqual(app.descendants(matching: .any)["library.mode"].firstMatch.frame.width, 280,
                                            "Library modes need their own readable row")
            }
            if page == "editor" {
                XCTAssertTrue(app.descendants(matching: .any)["editor.stage"].firstMatch.waitForExistence(timeout: 25))
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                    object: app.descendants(matching: .any)["editor.preview.rendering"].firstMatch)
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
            }
            checkpoint("workspace_" + page, app: app)
            app.terminate()
        }
        for page in ["today", "cleanup", "studio"] {
            launch(page, light: false, language: "de")
            if page == "cleanup" {
                XCTAssertTrue(app.buttons["cleanup.trash"].exists)
                XCTAssertTrue(app.buttons["cleanup.later"].exists)
                XCTAssertTrue(app.descendants(matching: .any)["cleanup.sections"].firstMatch.exists)
            }
            if page == "studio" {
                for key in ["studio_collage", "movie_title", "movie_title_slideshow", "pdf_title"] {
                    XCTAssertTrue(app.buttons["studio.create." + key].exists, "Every existing creation action remains reachable")
                }
                checkpoint("design_studio_dark_create", app: app)
                let resize = app.buttons["studio.tools.resize"]
                for _ in 0..<6 where !resize.isHittable { app.swipeUp() }
                XCTAssertTrue(resize.isHittable)
                resize.tap()
                XCTAssertTrue(app.navigationBars["Verkleinern"].waitForExistence(timeout: 10))
                checkpoint("design_studio_resize_destination", app: app)
                let back = app.navigationBars.buttons.element(boundBy: 0)
                XCTAssertTrue(back.exists, "Styled root header must retain destination navigation and Back")
                back.tap()
                for id in ["studio.tools.convert", "studio.tools.location", "studio.tools.stitch", "studio.tools.gif",
                           "studio.tools.batch", "studio.workflows", "studio.archive", "studio.pdfEditor", "studio.saved"] {
                    let control = app.buttons[id]
                    for _ in 0..<6 where !control.isHittable { app.swipeUp() }
                    XCTAssertTrue(control.isHittable, "Existing tool/document/saved action remains reachable: \(id)")
                    XCTAssertGreaterThanOrEqual(control.frame.height, 44)
                    if id == "studio.archive" { checkpoint("design_studio_dark_tools", app: app) }
                }
                checkpoint("design_studio_dark_documents_saved", app: app)
            }
            checkpoint("design_dark_" + page, app: app)
            app.terminate()
        }
    }

    func test35PdfCreationAndLiveEditing() {
        launch("studio", language: "de")
        let creation = app.buttons["studio.create.pdf_title"]
        XCTAssertTrue(creation.label.contains("PDF erstellen"))
        creation.tap()
        XCTAssertTrue(app.buttons["pdf.photosChoose"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["pdf.fromFiles"].exists, "Create PDF supports a separate file source")
        checkpoint("pdf_create_photos_or_files", app: app)
        app.buttons["pdf.fromFiles"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN {'Abbrechen', 'Cancel'}")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "File creation opens the system multi-file picker")
        checkpoint("pdf_system_file_picker", app: app)
        cancel.tap()
        XCTAssertTrue(app.buttons["pdf.import"].waitForExistence(timeout: 10))
        app.terminate()

        launch("pdf-studio", language: "de", pdfFiles: true)
        let preview = app.descendants(matching: .any)["pdf.preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        XCTAssertGreaterThan(preview.frame.height, app.frame.height * 0.5, "The PDF gets most of the editing workspace")
        XCTAssertTrue(app.staticTexts["pdf.pageCount"].label.contains("von 3"))
        checkpoint("pdf_live_preview_three_pages", app: app)
        app.buttons["pdf.rotate"].tap()
        XCTAssertTrue((app.buttons["pdf.page.0"].value as? String ?? "").contains("rotation=90"))
        app.buttons["pdf.later"].tap()
        XCTAssertTrue((app.buttons["pdf.page.1"].value as? String ?? "").contains("0:0;rotation=90"))
        XCTAssertEqual(app.staticTexts["pdf.pageCount"].label, "Seite 2 von 3", "The visible page follows the moved page identity")
        XCTAssertTrue(preview.exists)
        checkpoint("pdf_rotated_and_reordered_live", app: app)
        app.buttons["pdf.remove"].tap()
        XCTAssertTrue(app.staticTexts["pdf.pageCount"].label.contains("von 2"))
        XCTAssertTrue((app.buttons["pdf.page.0"].value as? String ?? "").contains("0:1;"))
        XCTAssertTrue((app.buttons["pdf.page.1"].value as? String ?? "").contains("1:0;"))
        app.buttons["pdf.save"].tap()
        XCTAssertTrue(app.buttons["pdf.share"].waitForExistence(timeout: 10))
        checkpoint("pdf_saved_copy_with_preview", app: app)
        app.buttons["pdf.rotate"].tap()
        XCTAssertFalse(app.buttons["pdf.share"].exists, "An edited preview must not share an older saved copy")
        app.buttons["pdf.remove"].tap()
        XCTAssertTrue(app.staticTexts["pdf.pageCount"].label.contains("von 1"))
        XCTAssertFalse(app.buttons["pdf.remove"].isEnabled)
        for id in ["pdf.rotate", "pdf.remove", "pdf.earlier", "pdf.later"] {
            XCTAssertGreaterThanOrEqual(app.buttons[id].frame.height, 44)
        }
    }

    func test40LargeTextAndArabic() {
        app.launchArguments = ["-store-capture", "-game-visual-tests", "-store-page", "feed", "-AppleLanguages", "(ar)",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        waitForPage("feed")
        openGame("memory")
        checkpoint("pairs_setup_arabic_large_text", app: app)
        let motifs = app.buttons["memory.startMotifs"]
        for _ in 0..<6 where !motifs.isHittable { app.swipeUp() }
        motifs.tap()
        XCTAssertTrue(app.buttons["memory.card.0"].waitForExistence(timeout: 10))
        checkpoint("memory_accessibility_arabic", app: app)
        app.buttons["memory.close"].tap()
        openGame("snake")
        checkpoint("snake_setup_arabic_large_text", app: app)
        let symbols = app.buttons["snake.symbols"]
        for _ in 0..<6 where !symbols.isHittable { app.swipeUp() }
        symbols.tap()
        XCTAssertTrue(app.descendants(matching: .any)["snake.board"].firstMatch.waitForExistence(timeout: 10))
        checkpoint("snake_accessibility_arabic", app: app)
        assertFullscreenSnake(app.descendants(matching: .any)["snake.board"].firstMatch)
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
        checkpoint("snake_realtime_fullscreen_started_by_button", app: app)
        assertFullscreenSnake(board)
        let initial = board.value as? String ?? ""
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initial), object: board)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 3), .completed)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        let paused = board.value as? String
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(board.value as? String, paused)
        XCTAssertTrue(app.buttons["snake.start"].isHittable)
        XCTAssertTrue(app.buttons["snake.changePhotos"].isHittable)
        XCTAssertTrue(app.buttons["snake.otherGames"].isHittable)
        checkpoint("snake_realtime_fullscreen_paused", app: app)
        app.buttons["snake.start"].tap()
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", paused ?? ""), object: board)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 3), .completed)
    }
}
