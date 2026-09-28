import XCTest

/// UI-Tests laufen ausschließlich mit synthetischen QA-Medien (siehe docs/QA_MATRIX.md,
/// `scripts/qa_seed_simulator.sh`). Keine echten Käufe, keine Live-Ads.
@MainActor
final class PhotoMaidUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-qa-fixtures", "-qa-unconfigured-purchases"]
        addUIInterruptionMonitor(withDescription: "Fotozugriff") { alert in
            for label in ["Vollen Zugriff erlauben", "Allow Full Access", "Zugriff auf alle Fotos erlauben"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
        app.launch()
    }

    func testFourTabsExist() {
        for tab in ["Heute", "Aufräumen", "Ordnen", "Verlauf"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 5), "Tab \(tab) fehlt")
        }
    }

    func testSettingsShowsFixedGestureLegend() {
        app.buttons["Einstellungen"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Behalten + weiter"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Vormerken"].exists)
        XCTAssertTrue(app.staticTexts["Später"].exists)
        XCTAssertTrue(app.staticTexts["Vorheriges"].exists)
    }

    func testProWithoutConfigurationShowsNoInventedPrice() {
        app.buttons["Einstellungen"].firstMatch.tap()
        app.buttons["PhotoMaid Pro"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Käufe sind in dieser Version noch nicht verfügbar."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '9.99'")).firstMatch.exists)
    }

    /// Feed-Flow mit QA-Medien: hoch behalten, links vormerken, rechts später, runter zurück.
    func testFeedGesturesWithQAMedia() throws {
        app.tabBars.buttons["Aufräumen"].tap()
        let photos = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Fotos'")).firstMatch
        guard photos.waitForExistence(timeout: 5), photos.isEnabled else {
            throw XCTSkip("Keine QA-Medien bzw. kein Fotozugriff im Simulator")
        }
        photos.tap()
        app.tap() // Interruption-Monitor auslösen
        if app.buttons["Verstanden"].waitForExistence(timeout: 3) { app.buttons["Verstanden"].tap() }
        let stage = app.otherElements["Aktuelles Medium"]
        guard stage.waitForExistence(timeout: 5) else { throw XCTSkip("Keine Medien im Feed") }
        stage.swipeUp()     // Behalten
        stage.swipeLeft()   // Vormerken
        stage.swipeRight()  // Später → Terminleiste
        XCTAssertTrue(app.buttons["Morgen"].waitForExistence(timeout: 3))
        stage.swipeDown()   // Zurück, keine Entscheidung
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Auswahlkorb: 1'")).firstMatch.exists)
    }
}
