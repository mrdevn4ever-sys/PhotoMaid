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
        installPermissionMonitor()
        app.launch()
        finishIntroduction(in: app, prefix: "qa_\(name)")
        let skip = app.buttons["Tutorial überspringen"].firstMatch
        if skip.waitForExistence(timeout: 1) { skip.tap() }
    }

    func testFiveTabsExist() {
        for tab in ["Heute", "Fotos", "Aufräumen", "Studio", "Verlauf"] {
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 5), "Tab \(tab) fehlt")
        }
        checkpoint("qa_five_tabs", app: app)
    }

    func testStudioRoutesAreReachable() {
        app.tabBars.buttons["Studio"].tap()
        XCTAssertTrue(app.staticTexts["Collage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Film"].exists || app.staticTexts["Video zusammenfügen"].exists)
        XCTAssertTrue(app.staticTexts["PDF erstellen"].exists)
        checkpoint("qa_studio", app: app)
    }

    func testSettingsShowsDecisionControls() {
        app.buttons["Einstellungen"].firstMatch.tap()
        XCTAssertTrue(app.switches["Vibration bei Aktionen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Favoriten schützen"].exists)
        XCTAssertTrue(app.staticTexts["Später: Standardabstand"].exists)
        checkpoint("qa_settings_controls", app: app)
    }

    func testProWithoutConfigurationShowsNoInventedPrice() {
        app.buttons["Einstellungen"].firstMatch.tap()
        // Zeile fasst Titel und Status zusammen („PhotoMaid Pro, Einmalkauf“).
        let pro = app.buttons["settings.pro"].firstMatch
        // Listenzeilen außerhalb des Bildschirms existieren erst nach dem Scrollen.
        for _ in 0..<5 where !pro.waitForExistence(timeout: 1) { app.swipeUp() }
        XCTAssertTrue(pro.waitForExistence(timeout: 5))
        pro.tap()
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '9.99'")).firstMatch.exists)
        checkpoint("qa_pro", app: app)
    }

    /// Feed-Flow mit QA-Medien: hoch behalten, links Papierkorb, rechts später, runter zurück.
    func testFeedGesturesWithQAMedia() throws {
        app.tabBars.buttons["Aufräumen"].tap()
        let photos = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Fotos'")).firstMatch
        guard photos.waitForExistence(timeout: 5), photos.isEnabled else {
            throw XCTSkip("Keine QA-Medien bzw. kein Fotozugriff im Simulator")
        }
        photos.tap()
        let stage = app.otherElements["feed.stage"]
        guard stage.waitForExistence(timeout: 5) else { throw XCTSkip("Keine Medien im Feed") }
        Thread.sleep(forTimeInterval: 1.2)
        stage.tap()
        let skip = app.buttons["Tutorial überspringen"].firstMatch
        if skip.waitForExistence(timeout: 2) { skip.tap() }
        stage.swipeUp()     // Behalten
        checkpoint("qa_feed_keep", app: app)
        stage.swipeLeft()   // Papierkorb
        checkpoint("qa_feed_trash", app: app)
        stage.swipeRight()  // Später mit Standardtermin → Pille
        checkpoint("qa_feed_later", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["later.pill"].waitForExistence(timeout: 3))
        stage.swipeDown()   // Zurück, keine Entscheidung
        checkpoint("qa_feed_previous", app: app)
        XCTAssertEqual(app.descendants(matching: .any)["feed.dock"].firstMatch.label, "Papierkorb: 1")
    }
}
