import StoreKitTest
import XCTest

/// Real PhotoKit + Core Data + Google test ads + local StoreKit. NO -qa-fixtures/-qa-pro.
/// The workflow erases a disposable simulator, imports the manifest and grants Photos.
/// No test taps the app's destructive PhotoKit confirmation or any system deletion.
@MainActor
final class RealLibraryTests: XCTestCase {
    private var app: XCUIApplication!
    private var store: SKTestSession!

    override func setUp() async throws {
        continueAfterFailure = false
        store = try SKTestSession(configurationFileNamed: "PhotoMaid")
        store.disableDialogs = true
        installPermissionMonitor()
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
        app.launch()
    }

    override func tearDown() async throws {
        if let app { snap("\(name)_end") }
    }

    private func snap(_ name: String) { checkpoint("real_" + name, app: app) }
    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func contains(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    private func button(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }
    private func tap(_ element: XCUIElement, _ name: String, timeout: Double = 10) {
        XCTAssertTrue(element.exists || element.waitForExistence(timeout: timeout), name)
        if !element.isHittable { scrollTo(element) }
        XCTAssertTrue(element.isHittable, name)
        element.tap()
        snap(name)
    }
    private func scrollTo(_ element: XCUIElement) {
        for upwards in [true, false] {
            for _ in 0..<10 {
                if element.exists && element.isHittable { return }
                if upwards { app.swipeUp() } else { app.swipeDown() }
            }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func tab(_ title: String) { tap(app.tabBars.buttons[title], "tab_" + title) }
    private func back(_ name: String) { tap(app.navigationBars.buttons.element(boundBy: 0), name) }
    private func skipTour() {
        let skip = app.buttons["Tutorial überspringen"].firstMatch
        if skip.waitForExistence(timeout: 1) { tap(skip, "tour_skip") }
    }
    private func ready() {
        // From cold start four onward, the SDK can cover the tabs before any test navigation.
        // Close that start ad before requiring the root tab bar.
        consent()
        dismissTestAdIfPresent()
        finishIntroduction(in: app, prefix: "real_launch")
        consent()
        skipTour()
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 15))
    }
    private func consent() {
        resolvePrivacyPrompts(in: app, prefix: "real_privacy")
    }
    private var testAd: XCUIElement? {
        // The SDK also creates a hidden 1-point preloader containing a full-size WebView.
        // Only a hittable creative can be an on-screen ad; UMP is handled separately.
        if app.staticTexts["Our app wants to stay free for you"].exists { return nil }
        return app.webViews.allElementsBoundByIndex.first {
            $0.isHittable && $0.frame.width > app.frame.width * 0.8 && $0.frame.height > app.frame.height * 0.5
        }
    }
    private func waitForTestAd(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            consent()
            if testAd != nil { return true }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return false
    }
    private func dismissTestAdIfPresent() {
        // Wait through the allowed four-second app-open load window.
        Thread.sleep(forTimeInterval: 5)
        guard testAd != nil else { return }
        snap("startup_test_ad")
        closeTestAd()
    }
    private func closeTestAd() {
        // SDK test creatives may make the close control available after their countdown.
        let deadline = Date().addingTimeInterval(65)
        while Date() < deadline {
            let titles = ["Close", "Close ad", "Close Ad", "Close Advertisement", "Schließen", "Dismiss", "Done", "Weiter zur App", "Continue to app"]
            let candidates = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN %@", titles as NSArray)).allElementsBoundByAccessibilityElement
            if let close = candidates.first(where: { $0.exists && $0.isEnabled && $0.isHittable }) {
                close.tap()
                Thread.sleep(forTimeInterval: 0.5)
                if testAd == nil {
                    snap("test_ad_closed")
                    return
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        snap("test_ad_close_missing")
        XCTFail("Google test ad has no accessible close control")
    }
    private func hub(_ id: String) {
        let target = e("hub." + id)
        scrollTo(target)
        tap(target, "hub_" + id)
    }
    private func feed(dismissHints: Bool = true, allMedia: Bool = false) {
        if allMedia {
            tab("Heute")
            tap(app.buttons["today.review"], "all_media_feed")
        } else {
            tab("Aufräumen")
            hub("photos")
        }
        XCTAssertTrue(e("feed.stage").exists || e("feed.stage").waitForExistence(timeout: 15))
        if dismissHints, e("feed.hints").exists {
            Thread.sleep(forTimeInterval: 1.2)
            e("feed.stage").tap()
            snap("hints_dismissed_for_gesture_test")
        }
        if dismissHints { skipTour() }
    }
    private func closeFeed() { tap(app.buttons["feed.close"].firstMatch, "feed_closed") }
    private func settings() {
        tab("Heute")
        tap(app.buttons["Einstellungen"].firstMatch, "settings")
        XCTAssertTrue(app.switches["Vibration bei Aktionen"].waitForExistence(timeout: 5))
    }
    private func position() -> Int {
        let label = e("feed.position").label
        let digits = label.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        return Int(digits.first ?? "") ?? -1
    }
    private func assertNoPlaceholders() {
        let pattern = "(?s).*(%[0-9]*\\$?(lld|ld|d|@)|\\b(pro2|ana2|vault2)_[a-z_]+).*"
        let invalid = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", pattern)).firstMatch
        XCTAssertFalse(invalid.exists, "No format placeholders or localization keys may be visible")
    }
    private func setSwitch(_ control: XCUIElement, on: Bool, _ name: String) {
        XCTAssertTrue(control.exists)
        let wanted = on ? "1" : "0"
        if control.value as? String != wanted {
            // SwiftUI exposes the entire row as a Switch; its label centre does not toggle the thumb.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(control.value as? String, wanted, name)
        snap(name)
    }

    private func verifyHintDuration(_ prefix: String, trigger: () -> Void) {
        trigger()
        let started = ProcessInfo.processInfo.systemUptime
        checkpoint("real_" + prefix + "_on_open", app: app, hierarchy: false)
        XCTAssertTrue(e("feed.hints").waitForExistence(timeout: 3))
        func waitUntil(_ seconds: TimeInterval) {
            let remaining = seconds - (ProcessInfo.processInfo.systemUptime - started)
            if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
        }
        // Measure from the trigger, not from slow screenshot/AX queries (~8 seconds in CI).
        waitUntil(3)
        XCTAssertTrue(e("feed.hints").exists, "Help remains visible three seconds after opening")
        checkpoint("real_" + prefix + "_still_after_3s", app: app, hierarchy: false)
        waitUntil(7)
        XCTAssertFalse(e("feed.hints").exists)
        snap(prefix + "_gone_after_7s")
    }

    func test00IntroductionAndFourColdStarts() {
        store.clearTransactions()
        finishIntroduction(in: app, prefix: "real_start_1")
        consent()
        skipTour()
        for start in 1...4 {
            if start > 1 {
                app.terminate()
                app.launch()
                consent()
            }
            let shown = waitForTestAd(timeout: 8)
            snap("cold_start_\(start)")
            if start < 4 {
                XCTAssertFalse(shown, "Starts 1–3 must not present app-open ads")
            } else {
                XCTAssertTrue(shown, "Fourth cold start must present a Google test ad")
                closeTestAd()
            }
            XCTAssertTrue(app.tabBars.buttons["Heute"].exists)
        }
    }

    func test10AnalysisQueueProgressAndGrid() {
        ready()
        tab("Aufräumen")
        hub("blurry")
        let start = app.buttons["Analyse starten"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        tap(start, "blurry_started")
        XCTAssertTrue(app.buttons["Anhalten"].waitForExistence(timeout: 5))
        let first = e("analysis.progress").value as? String ?? ""
        back("blurry_back_while_running")
        hub("similar")
        XCTAssertTrue(contains("Gerade läuft").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Danach analysieren"].isEnabled)
        tap(app.buttons["Danach analysieren"], "similar_queued")
        XCTAssertTrue(app.buttons["Nicht mehr warten"].waitForExistence(timeout: 5))
        tap(app.buttons["Jetzt zuerst"], "similar_prioritized")
        XCTAssertTrue(app.buttons["Anhalten"].waitForExistence(timeout: 5))
        back("similar_back")
        hub("blurry")
        XCTAssertTrue(contains("Wartet").exists || contains("Gerade läuft").exists || app.buttons["Anhalten"].exists)
        if app.buttons["Jetzt zuerst"].exists { tap(app.buttons["Jetzt zuerst"], "blurry_prioritized") }
        var previous = Int(first.split(separator: "/").first ?? "") ?? 0
        let deadline = Date().addingTimeInterval(180)
        repeat {
            let text = e("analysis.progress").value as? String ?? ""
            let done = Int(text.split(separator: "/").first ?? "") ?? previous
            XCTAssertGreaterThanOrEqual(done, previous, "Analysis progress must not go backwards")
            previous = done
            snap("blurry_progress_\(done)")
            if !app.buttons["Anhalten"].exists { break }
            Thread.sleep(forTimeInterval: 2)
        } while Date() < deadline
        XCTAssertGreaterThan(previous, 0)
        XCTAssertTrue(e("analysis.swipe").waitForExistence(timeout: 15), "Blurred test photos must produce hits")
        app.swipeUp()
        snap("blurry_full_grid")
        let cells = app.buttons.matching(identifier: "media.cell").allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertGreaterThanOrEqual(cells.count, 3)
        if cells.count >= 3 {
            XCTAssertEqual(cells[0].frame.minY, cells[1].frame.minY, accuracy: 3)
            XCTAssertEqual(cells[1].frame.minY, cells[2].frame.minY, accuracy: 3)
        }
        scrollTo(e("analysis.swipe"))
        tap(e("analysis.swipe"), "blurry_swipe_feed")
        XCTAssertTrue(e("feed.stage").waitForExistence(timeout: 10))
        closeFeed()
    }

    func test20FiftyFastSwipesAdAndDirections() {
        ready()
        feed()
        // Resolve only app coordinates for the timing-sensitive gestures. Querying the ad's
        // accessibility tree first took >2 seconds in CI and missed the 1.5-second lock.
        let quickLeftStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.48))
        let quickLeftEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.48))
        let quickDownStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let quickDownEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        for index in 1...50 {
            let before = position()
            e("feed.stage").swipeLeft(velocity: .fast)
            if index == 50 {
                checkpoint("real_ad_after_50", app: app, hierarchy: false)
                quickDownStart.press(forDuration: 0.01, thenDragTo: quickDownEnd,
                                     withVelocity: .fast, thenHoldForDuration: 0)
                XCTAssertFalse(e("feed.ad").exists, "Down dismisses even while the card is locked")
                snap("ad_down_immediate")
            } else {
                snap(String(format: "rapid_%02d", index))
                XCTAssertFalse(e("feed.ad").exists)
            }
            XCTAssertEqual(position(), before + 1, "Swipe \(index) must advance once")
        }
        closeFeed()
        tab("Verlauf")
        XCTAssertEqual(e("history.events").value as? String, "50", "The ad adds no ledger event")
        snap("history_exactly_50_no_ad")
        feed()

        // A second fifty-decision interval tests the other dismiss path independently.
        for index in 1...50 {
            let before = position()
            e("feed.stage").swipeLeft(velocity: .fast)
            if index == 50 {
                // No snapshot/query before the early swipe: their overhead exceeds the lock.
                quickLeftStart.press(forDuration: 0.01, thenDragTo: quickLeftEnd,
                                     withVelocity: .fast, thenHoldForDuration: 0)
                XCTAssertTrue(e("feed.ad").exists, "An immediate sideways swipe must leave the card open")
                checkpoint("real_ad_early_swipe_blocked", app: app, hierarchy: false)
            } else {
                snap(String(format: "second_rapid_%02d", index))
                XCTAssertEqual(position(), before + 1)
            }
        }
        XCTAssertTrue(e("feed.ad").exists)
        XCTAssertTrue(app.staticTexts["Anzeige"].exists)
        Thread.sleep(forTimeInterval: 1.6)
        XCTAssertTrue(e("feed.ad.skip").exists)
        let secondAdPosition = position()
        e("feed.ad").swipeLeft(velocity: .fast)
        XCTAssertFalse(e("feed.ad").exists)
        XCTAssertEqual(position(), secondAdPosition)
        snap("ad_after_1_5s_dismissed_no_decision")
        closeFeed(); tab("Verlauf")
        XCTAssertEqual(e("history.events").value as? String, "100")
        snap("history_exactly_100_no_ad")
        feed()

        var before = position()
        e("feed.stage").swipeUp()
        snap("up_keep")
        XCTAssertEqual(position(), before + 1)
        before = position()
        e("feed.stage").swipeRight()
        snap("right_later")
        XCTAssertEqual(position(), before + 1)
        XCTAssertTrue(e("later.pill").waitForExistence(timeout: 3))
        XCTAssertTrue(e("later.pill").label.contains("2"))
        XCTAssertTrue(e("later.pill").label.contains("Ändern"))
        before = position()
        e("feed.stage").swipeDown()
        snap("down_previous")
        XCTAssertEqual(position(), before - 1)
        tap(app.buttons["Rückgängig"].firstMatch, "undo")
        XCTAssertTrue(e("feed.stage").exists)
        closeFeed()
        tab("Verlauf")
        XCTAssertEqual(e("history.events").value as? String, "103", "100 decisions + keep + later + undo audit event; ads and down add no event")
        snap("history_no_ad_decision")
        XCTAssertFalse(app.staticTexts["Anzeige"].exists)
        XCTAssertTrue(contains("Papierkorb").exists)
    }

    func test30GestureHelpAndCustomControls() {
        ready()
        settings()
        let hint = app.switches["Wischhilfe beim Öffnen zeigen"]
        XCTAssertTrue(hint.exists)
        setSwitch(hint, on: true, "hint_setting_on")
        let controls = button("Wischen & Tasten")
        tap(controls, "controls")
        tap(e("controls.right"), "right_menu")
        tap(app.buttons["In Album legen …"].firstMatch, "choose_album")
        tap(button("Neues Album"), "new_album")
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Simulator-Test")
        snap("album_name")
        tap(app.alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Erstellen'")).firstMatch, "album_created")
        XCTAssertTrue(e("controls.right").label.contains("Simulator-Test"))
        tap(button("Tasten anzeigen"), "buttons_visibility")
        tap(app.buttons["Immer"].firstMatch, "buttons_always")
        XCTAssertTrue(button("Tasten anzeigen").label.contains("Immer"))
        back("controls_back"); back("settings_back")
        tab("Aufräumen")
        let photos = app.buttons["hub.photos"].firstMatch
        scrollTo(photos)
        XCTAssertTrue(photos.exists && photos.isHittable)
        verifyHintDuration("hints") { photos.tap() }
        skipTour()
        tap(app.buttons["Weitere Aktionen"].firstMatch, "feed_more")
        let showHints = app.buttons["Wischhilfe zeigen"]
        XCTAssertTrue(showHints.exists && showHints.isHittable)
        verifyHintDuration("menu_hints") { showHints.tap() }
        let before = position()
        e("feed.stage").swipeRight()
        snap("right_adds_to_album")
        XCTAssertEqual(position(), before + 1)
        XCTAssertTrue(contains("Simulator-Test").exists)
        XCTAssertTrue(button("Behalten").exists, "Always-visible decision buttons")
        tap(app.buttons["Rückgängig"].firstMatch, "album_undo")
        closeFeed()
    }

    func test98TrashLimitRewardAndSizes() {
        // This final check explicitly returns from the local StoreKit Pro purchase to Free.
        store.clearTransactions()
        app.terminate(); app.launch()
        ready()
        tab("Fotos")
        tap(e("library.filter"), "trash_setup_sort_menu")
        tap(app.buttons["Aufnahmedatum"].firstMatch, "trash_setup_capture_order")
        tap(app.buttons["Auswählen"].firstMatch, "library_select")
        let all = app.buttons["Alle"].firstMatch
        tap(all, "library_select_all")
        tap(app.buttons["In den Papierkorb"].firstMatch, "library_mark_trash")
        // This is PhotoMaid's reversible mark, never PHAsset deletion.
        let mark = app.alerts.buttons["In den Papierkorb"].firstMatch
        if mark.waitForExistence(timeout: 3) { tap(mark, "mark_confirmed_reversible") }
        XCTAssertTrue(app.buttons["Auswählen"].firstMatch.waitForExistence(timeout: 15), "Bulk marking finished")
        tab("Heute")
        let basket = button("Papierkorb")
        scrollTo(basket)
        tap(basket, "trash")
        XCTAssertTrue(contains("Heute noch 100 von 100").waitForExistence(timeout: 10))
        XCTAssertTrue(contains("Auswahl:").exists)
        XCTAssertTrue(contains("MB").exists || contains("GB").exists || contains("KB").exists)
        snap("trash_count_sizes")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Fotos und Videos entfernen'")).firstMatch, "trash_limit_open")
        XCTAssertTrue(contains("Werbung ansehen: heute 100 mehr entfernen").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'mit Pro'")).firstMatch.exists)
        snap("limit_100")
        tap(button("Werbung ansehen: heute 100 mehr entfernen"), "bonus_video_requested")
        XCTAssertTrue(waitForTestAd(timeout: 30), "Google rewarded TEST video")
        snap("bonus_test_video")
        Thread.sleep(forTimeInterval: 32)
        closeTestAd()
        // The app may open its own confirmation after reward. Always cancel it.
        let cancel = app.buttons["Abbrechen"].firstMatch
        if cancel.waitForExistence(timeout: 5) { tap(cancel, "delete_confirmation_cancelled") }
        XCTAssertTrue(contains("Heute noch 200 von 200").waitForExistence(timeout: 10))
        snap("limit_200_no_deletion")
    }

    func test50LargeDuplicatesAndStorage() {
        ready()
        tab("Aufräumen")
        hub("large")
        snap("large_loading")
        XCTAssertTrue(app.navigationBars["Große Dateien"].exists)
        XCTAssertFalse(contains("%1$lld").exists)
        // All imported test files are below the default 100 MB threshold.
        // A responsive navigation bar alone would miss a permanently loading scanner.
        XCTAssertTrue(app.staticTexts["Keine passenden Dateien"].waitForExistence(timeout: 45))
        XCTAssertFalse(contains("Größen werden gemessen").exists)
        snap("large_finished_below_threshold")
        back("large_back")
        hub("storage")
        snap("storage_progress")
        XCTAssertTrue(contains("GB").waitForExistence(timeout: 20))
        XCTAssertNotNil(contains("GB").label.rangeOfCharacter(from: .decimalDigits))
        XCTAssertTrue(app.progressIndicators.firstMatch.exists, "Device capacity has a visible progress bar")
        snap("storage_loaded_numbers_and_progress")
        back("storage_back")
        hub("duplicates")
        tap(app.buttons["Kopien suchen"], "duplicates_started")
        snap("duplicates_progress")
        XCTAssertTrue(app.buttons["Erneut suchen"].waitForExistence(timeout: 180))
        snap("duplicates_five_copies")
        let move = button("5 ")
        XCTAssertTrue(move.exists, "Manifest has exactly five extra byte-identical copies")
        XCTAssertFalse(contains("Keine identischen").exists)
    }

    func test60LibraryFiltersSortAndAspect() {
        ready()
        tab("Fotos")
        for filter in ["Alle", "Favoriten", "Fotos", "Videos", "Screenshots"] {
            tap(e("library.filter"), "filter_menu_" + filter)
            tap(app.buttons[filter].firstMatch, "filter_" + filter)
            XCTAssertEqual(e("library.filter").value as? String, filter)
            if filter == "Videos" || filter == "Screenshots" {
                XCTAssertTrue(app.buttons.matching(identifier: "media.cell").firstMatch.waitForExistence(timeout: 10),
                              "Imported \(filter) must be visible")
            }
            snap("library_" + filter)
        }
        for option in ["Alle", "Zuletzt hinzugefügt", "Quadratisch", "Seitenverhältnis"] {
            tap(e("library.filter"), "view_menu_" + option)
            tap(app.buttons[option].firstMatch, "view_" + option)
            XCTAssertTrue(app.tabBars.buttons["Fotos"].exists)
        }
        XCTAssertTrue(contains("Zuletzt hinzugefügt").exists)
        XCTAssertGreaterThan(app.buttons.matching(identifier: "media.cell").count, 0)
    }

    func test70StudioFreeTools() {
        ready()
        tab("Studio")
        XCTAssertFalse(app.images["crown"].exists)
        tap(button("Collage"), "collage_picker")
        let cells = app.buttons.matching(identifier: "picker.media")
        XCTAssertGreaterThanOrEqual(cells.count, 2)
        tap(cells.element(boundBy: 0), "collage_first_photo")
        tap(cells.element(boundBy: 1), "collage_second_photo")
        tap(app.buttons["Fertig"], "collage_editor")
        XCTAssertFalse(contains("Pro freischalten").exists)
        XCTAssertFalse(app.images["crown"].exists)
        back("collage_back")
        tap(button("Werkzeuge"), "tools_free")
        XCTAssertFalse(contains("Pro freischalten").exists)
        XCTAssertFalse(app.images["crown"].exists)
        snap("studio_tools_free")
        back("tools_back")
        feed()
        tap(app.buttons["Bearbeiten"].firstMatch, "photo_editor_free")
        XCTAssertFalse(contains("Pro freischalten").exists)
        XCTAssertFalse(app.images["crown"].exists)
        XCTAssertTrue(app.buttons["Anpassen"].waitForExistence(timeout: 10), "Photo editor must load without Pro")
        snap("studio_photo_editor_free")
    }

    private func openVault() {
        settings()
        let vault = button("Privater Tresor")
        scrollTo(vault)
        tap(vault, "vault_open")
    }
    private func unlockVault() {
        let pin = app.secureTextFields.firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        pin.tap(); pin.typeText("628491")
        snap("vault_pin_entered")
        XCTAssertTrue(app.segmentedControls.buttons["Medien"].waitForExistence(timeout: 15))
    }
    private func newVaultFolder(_ title: String, rewarded: Bool) {
        tap(button("Neuer Ordner"), "vault_new_folder_" + title)
        if rewarded {
            XCTAssertTrue(app.buttons["Video ansehen und Ordner anlegen"].waitForExistence(timeout: 5))
            tap(app.buttons["Video ansehen und Ordner anlegen"], "vault_reward_requested")
            XCTAssertTrue(waitForTestAd(timeout: 30))
            snap("vault_test_video")
            Thread.sleep(forTimeInterval: 32)
            closeTestAd()
        } else { XCTAssertFalse(app.buttons["Video ansehen und Ordner anlegen"].exists) }
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText(title)
        snap("vault_folder_name_" + title)
        tap(app.alerts.buttons["Speichern"].firstMatch, "vault_folder_created_" + title)
        XCTAssertTrue(contains(title).waitForExistence(timeout: 10))
    }

    func test80VaultPINCloseAllTabsAndFreeFolder() {
        ready()
        openVault()
        tap(app.buttons["Weiter"], "vault_intro_next")
        let fields = app.secureTextFields
        XCTAssertEqual(fields.count, 2)
        fields.element(boundBy: 0).tap(); fields.element(boundBy: 0).typeText("628491")
        fields.element(boundBy: 1).tap(); fields.element(boundBy: 1).typeText("628491")
        snap("vault_pin_setup")
        tap(app.buttons["Weiter"], "vault_code_next")
        if app.switches.matching(NSPredicate(format: "label CONTAINS 'Face ID'")).firstMatch.exists {
            let face = app.switches.matching(NSPredicate(format: "label CONTAINS 'Face ID'")).firstMatch
            setSwitch(face, on: false, "vault_face_id_off")
            tap(app.buttons["Weiter"], "vault_biometry_next")
        }
        tap(button("Ich habe ihn aufgeschrieben"), "vault_recovery_saved")
        let hidden = app.switches["Eingang verstecken"].firstMatch
        if hidden.exists { setSwitch(hidden, on: false, "vault_entry_visible") }
        tap(button("Tresor einrichten"), "vault_setup_finished")
        XCTAssertTrue(app.segmentedControls.buttons["Medien"].waitForExistence(timeout: 20))
        newVaultFolder("Gratis-Test", rewarded: true)
        for title in ["Medien", "Notizen", "Dateien"] {
            tap(app.segmentedControls.buttons[title], "vault_tab_" + title)
            let close = app.buttons["Schließen und sperren"].firstMatch
            XCTAssertTrue(close.isHittable)
            XCTAssertLessThan(close.frame.midX, app.frame.midX)
            tap(close, "vault_close_" + title)
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.secureTextFields.firstMatch.exists, "Closing must never ask for PIN")
            snap("vault_closed_no_prompt_" + title)
            if title != "Dateien" {
                back("vault_settings_back")
                openVault()
                unlockVault()
            }
        }
    }

    func test90ProStoreKitPurchaseNoAdsAndFolder() {
        ready()
        settings()
        let pro = app.buttons["settings.pro"].firstMatch
        scrollTo(pro)
        tap(pro, "pro_free")
        XCTAssertTrue(contains("ohne das Tageslimit von 100").waitForExistence(timeout: 10))
        assertNoPlaceholders()
        XCTAssertTrue(contains("Ohne Werbung").exists)
        XCTAssertTrue(contains("Tresor-Ordner").exists)
        app.swipeUp()
        snap("pro_free_benefits")
        XCTAssertTrue(contains("Alles andere").exists)
        let buy = button("PhotoMaid Pro freischalten")
        scrollTo(buy)
        tap(buy, "storekit_purchase")
        XCTAssertTrue(app.staticTexts["Pro ist aktiv"].waitForExistence(timeout: 20))
        snap("pro_active")
        XCTAssertFalse(store.allTransactions().isEmpty)
        back("pro_back"); back("pro_settings_back")
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(waitForTestAd(timeout: 8))
        snap("pro_cold_start_without_ad")
        feed(allMedia: true)
        for index in 1...50 {
            let before = position()
            e("feed.stage").swipeUp(velocity: .fast)
            snap(String(format: "pro_rapid_%02d", index))
            XCTAssertEqual(position(), before + 1)
            XCTAssertFalse(e("feed.ad").exists, "Purchased Pro has no feed ads")
        }
        closeFeed()
        openVault(); unlockVault()
        newVaultFolder("Pro-Test", rewarded: false)
        tap(app.buttons["Schließen und sperren"], "pro_vault_closed")
    }

    func test95EnglishAndArabicPlaceholdersAndArrows() {
        for language in ["en", "ar"] {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language]
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
            dismissTestAdIfPresent()
            snap(language + "_today")
            assertNoPlaceholders()
            let cleanup = app.tabBars.buttons.element(boundBy: 2)
            tap(cleanup, language + "_cleanup")
            hub("photos")
            XCTAssertTrue(e("feed.stage").waitForExistence(timeout: 10))
            snap(language + "_feed_arrows")
            assertNoPlaceholders()
            // Physical arrow rendering is reviewed in the PNGs; no locale-dependent swipe reversal.
            tap(app.buttons.element(matching: NSPredicate(format: "identifier == 'feed.close'")), language + "_feed_close")
            tap(app.tabBars.buttons.element(boundBy: 0), language + "_today_tab")
            tap(app.buttons["today.settings"], language + "_settings")
            let pro = e("settings.pro")
            scrollTo(pro); tap(pro, language + "_pro")
            snap(language + "_pro_text")
            assertNoPlaceholders()
        }
    }
}
