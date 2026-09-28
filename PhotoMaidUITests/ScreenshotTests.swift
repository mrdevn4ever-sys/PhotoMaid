import XCTest

/// Nimmt echte Screenshots der kompilierten App im Simulator auf (QA-Modus `-qa-fixtures`,
/// synthetische Medien aus `scripts/qa_media.swift`). Bestätigt NIE eine Löschung.
///
/// Ablageort: Umgebungsvariable `SCREENSHOT_DIR` (von der CI per `TEST_RUNNER_SCREENSHOT_DIR` gesetzt),
/// zusätzlich als XCTAttachment im Ergebnisbündel.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = true // fehlende Screens sollen die übrigen nicht verhindern
    }

    // MARK: Hilfen

    private func launch(pro: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-qa-fixtures", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
            + (pro ? ["-qa-pro"] : [])
        app.launch()
    }

    private func settle(_ seconds: TimeInterval = 1.2) { Thread.sleep(forTimeInterval: seconds) }

    private func snap(_ name: String) {
        settle()
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        do { try shot.pngRepresentation.write(to: url.appendingPathComponent("\(name).png")) }
        catch { XCTFail("Screenshot \(name) nicht gespeichert: \(error)") }
    }

    @discardableResult
    private func waitFor(_ element: XCUIElement, _ timeout: TimeInterval = 10, _ what: String) -> Bool {
        let ok = element.waitForExistence(timeout: timeout)
        if !ok { XCTFail("Nicht gefunden: \(what)") }
        return ok
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func tap(_ id: String, _ what: String) -> Bool {
        let e = element(id)
        guard waitFor(e, 10, what) else { return false }
        e.tap()
        return true
    }

    /// Tab wechseln: iPhone = Tab-Leiste unten, iPad = Tab-Leiste oben (kein XCUI-TabBar-Typ).
    private func tab(_ name: String) {
        let bar = app.tabBars.buttons[name]
        if bar.waitForExistence(timeout: 2) { bar.tap() }
        else {
            let top = app.buttons[name].firstMatch
            if waitFor(top, 5, "Tab \(name)") { top.tap() }
        }
        settle(0.8)
    }

    private func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.waitForExistence(timeout: 3) { b.tap() }
        settle(0.6)
    }

    private func closeFeed() {
        let close = app.buttons["Schließen"].firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() }
        settle(0.8)
    }

    private func dismissGestureHintIfShown(snapshot: String? = nil) {
        let ok = app.buttons["Verstanden"]
        if ok.waitForExistence(timeout: 6) {
            if let snapshot { snap(snapshot) }
            ok.tap()
        }
    }

    /// Systemabfrage Fotozugriff (Sprache des Simulators).
    private func allowPhotosAlert() {
        let labels = ["Allow Full Access", "Vollen Zugriff erlauben", "Allow Access to All Photos",
                      "Zugriff auf alle Fotos erlauben", "Allow", "Erlauben"]
        for _ in 0..<2 {
            for l in labels where springboard.buttons[l].waitForExistence(timeout: 2) {
                springboard.buttons[l].tap()
                settle(1)
                break
            }
        }
    }

    private func onboarding(capture: Bool) {
        guard waitFor(app.staticTexts["Deine Privatsphäre zuerst"], 15, "Onboarding") else { return }
        if capture { snap("01_onboarding") }
        let allow = app.buttons["Zugriff erlauben"]
        if allow.exists {
            allow.tap()
            allowPhotosAlert()
        }
        if capture { snap("02_permissions") }
        let next = app.buttons["Weiter"]
        if next.waitForExistence(timeout: 5) {
            if !next.isHittable { app.swipeUp() }
            next.tap()
        }
        settle(1.5)
    }

    // MARK: Hauptdurchgang

    func testMainScreens() {
        launch(pro: true)
        onboarding(capture: true)

        // 03 Heute
        waitFor(app.staticTexts["PhotoMaid"], 10, "Heute")
        settle(2.5)
        snap("03_home")

        // Foto-Feed mit echter Gestenlogik
        tab("Aufräumen")
        if tap("hub.photos", "Fotos im Aufräumen-Hub") {
            dismissGestureHintIfShown(snapshot: "04a_gesture_hints")
            let stage = element("feed.stage")
            if waitFor(stage, 10, "Feed-Bühne") {
                settle(2.5)                          // Vorschau laden
                snap("04_review_photo")
                stage.swipeUp()                      // HOCH = Behalten + weiter
                settle(1.5)
                snap("04b_after_up_keep")
                stage.swipeLeft()                    // LINKS = Vormerken + weiter
                settle(1.5)
                snap("04c_after_left_cleanup")
                stage.swipeLeft()
                settle(1.5)
                stage.swipeRight()                   // RECHTS = Später + weiter, Terminleiste
                settle(1.5)
                snap("06_later_sheet")
                if tap("later.more", "Terminleiste „…“") {
                    snap("06b_later_date_picker")
                    let cancel = app.buttons["Abbrechen"].firstMatch
                    if cancel.waitForExistence(timeout: 4) { cancel.tap() }
                    settle(0.8)
                }
                stage.swipeDown()                    // RUNTER = Vorheriges, keine Entscheidung
                settle(1.5)
                snap("04d_after_down_previous")

                if tap("feed.dock", "Auswahlkorb-Dock") {
                    settle(1.5)
                    snap("07_cleanup_basket")
                    let remove = app.buttons.matching(NSPredicate(format: "label CONTAINS 'prüfen und entfernen'")).firstMatch
                    if waitFor(remove, 6, "Entfernen-Button im Auswahlkorb") {
                        remove.tap()
                        snap("08_cleanup_confirm")
                        // Niemals bestätigen: Dialog abbrechen (Button oder Tipp außerhalb des Popovers).
                        let cancel = app.buttons["Abbrechen"].firstMatch
                        if cancel.exists && cancel.isHittable { cancel.tap() }
                        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap() }
                        settle(1)
                        if app.buttons.matching(NSPredicate(format: "label CONTAINS 'über die Fotos-App entfernen'")).firstMatch.exists {
                            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
                            settle(1)
                        }
                    }
                    let done = app.buttons["Fertig"].firstMatch
                    if done.waitForExistence(timeout: 3) { done.tap() } else { app.swipeDown(velocity: .fast) }
                    settle(1.2)
                    waitFor(element("feed.stage"), 5, "Feed nach Schließen des Auswahlkorbs")
                }
            }
            closeFeed()
        }

        // 05 Video-Feed
        if tap("hub.videos", "Videos im Aufräumen-Hub") {
            dismissGestureHintIfShown()
            if waitFor(element("feed.stage"), 10, "Video-Feed") {
                settle(3.5)
                snap("05_review_video")
            }
            closeFeed()
        }

        // 09 Duplikate (Pro-Werkzeug; QA-Modus mit -qa-pro)
        if tap("hub.duplicates", "Duplikate") {
            let start = app.buttons["Prüfung starten"]
            if waitFor(start, 8, "Prüfung starten") {
                start.tap()
                _ = app.buttons["Erneut prüfen"].waitForExistence(timeout: 90)
            }
            settle(1.5)
            snap("09_duplicates")
            back()
        }

        if tap("hub.large", "Große Dateien") { settle(4); snap("10_large_files"); back() }
        if tap("hub.storage", "Speicherübersicht") { settle(2.5); snap("11_storage_insights"); back() }
        if tap("hub.files", "Downloads") { settle(2.5); snap("11b_downloads"); back() }

        // Ordnen
        tab("Ordnen")
        settle(1)
        if tap("organize.later", "Später") { settle(2); snap("12_later"); back() }
        if tap("organize.rules", "Regeln & Routinen") { settle(1.5); snap("13_rules"); back() }

        // Verlauf
        tab("Verlauf")
        settle(1.5)
        snap("14_history")

        // Einstellungen
        tab("Heute")
        let gear = app.buttons["Einstellungen"].firstMatch
        if waitFor(gear, 5, "Einstellungen-Zahnrad") {
            gear.tap()
            settle(1.5)
            snap("16_settings")
        }
    }

    /// Pro-Screen im Free-Zustand (ohne -qa-pro), damit Kauf-/Vorschau-Optionen sichtbar sind.
    func testProScreen() {
        launch(pro: false)
        onboarding(capture: false)
        let gear = app.buttons["Einstellungen"].firstMatch
        guard waitFor(gear, 8, "Einstellungen-Zahnrad") else { return }
        gear.tap()
        let pro = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'PhotoMaid Pro'")).firstMatch
        if waitFor(pro, 6, "PhotoMaid Pro in Einstellungen") {
            pro.tap()
            settle(2)
            snap("15_pro")
        }
    }

    /// Dunkelmodus über die echte App-Einstellung „Erscheinungsbild“.
    func testDarkModeScreens() {
        launch(pro: true)
        onboarding(capture: false)
        let gear = app.buttons["Einstellungen"].firstMatch
        guard waitFor(gear, 8, "Einstellungen-Zahnrad") else { return }
        gear.tap()
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Erscheinungsbild'")).firstMatch
        if waitFor(picker, 6, "Erscheinungsbild") {
            picker.tap()
            let dark = app.buttons["Dunkel"].firstMatch
            if dark.waitForExistence(timeout: 4) { dark.tap() }
        }
        settle(1.5)
        snap("17_dark_settings")
        let done = app.buttons["Fertig"].firstMatch
        if done.exists { done.tap() }
        settle(1.5)
        snap("18_dark_home")
        tab("Aufräumen")
        if tap("hub.photos", "Fotos (dunkel)") {
            dismissGestureHintIfShown()
            settle(2.5)
            snap("19_dark_review_photo")
            closeFeed()
        }
    }
}
