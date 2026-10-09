import XCTest

/// UI-Tests laufen ausschließlich mit synthetischen QA-Medien (siehe docs/QA_MATRIX.md,
/// `scripts/qa_seed_simulator.sh`). Keine echten Käufe, keine Live-Ads.
@MainActor
final class PhotoMaidUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-qa-fixtures", "-AppleLanguages", "(de)"]
        addUIInterruptionMonitor(withDescription: "Fotozugriff") { alert in
            for label in ["Vollen Zugriff erlauben", "Allow Full Access", "Zugriff auf alle Fotos erlauben"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
        app.launch()
        // Onboarding beim ersten Start schließen.
        for _ in 0..<5 {
            let next = app.buttons["Weiter"]
            let allow = app.buttons["Zugriff erlauben"]
            if next.waitForExistence(timeout: 2) { next.tap() }
            else if allow.waitForExistence(timeout: 2) { allow.tap(); app.tap() }
        }
    }

    func testFiveTabsExist() {
        for tab in ["Heute", "Fotos", "Aufräumen", "Studio", "Verlauf"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 5), "Tab \(tab) fehlt")
        }
    }

    func testStudioRoutesAreReachable() {
        app.tabBars.buttons["Studio"].tap()
        XCTAssertTrue(app.staticTexts["Collage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Film"].exists || app.staticTexts["Video zusammenfügen"].exists)
        XCTAssertTrue(app.staticTexts["PDF aus Fotos"].exists)
    }

    func testSettingsShowsDecisionControls() {
        app.buttons["Einstellungen"].firstMatch.tap()
        XCTAssertTrue(app.switches["Haptik"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Favoriten schützen"].exists)
        XCTAssertTrue(app.staticTexts["Standard für Später"].exists)
    }

    func testProWithoutConfigurationShowsNoInventedPrice() {
        app.buttons["Einstellungen"].firstMatch.tap()
        // Zeile fasst Titel und Status zusammen („PhotoMaid Pro, Einmalkauf“).
        let pro = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'PhotoMaid Pro'")).firstMatch
        // Listenzeilen außerhalb des Bildschirms existieren erst nach dem Scrollen.
        for _ in 0..<5 where !pro.waitForExistence(timeout: 1) { app.swipeUp() }
        XCTAssertTrue(pro.waitForExistence(timeout: 5))
        pro.tap()
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '9.99'")).firstMatch.exists)
    }

    /// Feed-Flow mit QA-Medien: hoch behalten, links Papierkorb, rechts später, runter zurück.
    func testFeedGesturesWithQAMedia() throws {
        app.tabBars.buttons["Aufräumen"].tap()
        let photos = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Fotos'")).firstMatch
        guard photos.waitForExistence(timeout: 5), photos.isEnabled else {
            throw XCTSkip("Keine QA-Medien bzw. kein Fotozugriff im Simulator")
        }
        photos.tap()
        app.tap() // Interruption-Monitor auslösen
        let stage = app.otherElements["Aktuelles Medium"]
        guard stage.waitForExistence(timeout: 5) else { throw XCTSkip("Keine Medien im Feed") }
        stage.swipeUp()     // Behalten
        stage.swipeLeft()   // Papierkorb
        stage.swipeRight()  // Später mit Standardtermin → Pille
        XCTAssertTrue(app.descendants(matching: .any)["later.pill"].waitForExistence(timeout: 3))
        stage.swipeDown()   // Zurück, keine Entscheidung
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Papierkorb: 1'")).firstMatch.exists)
    }
}
