import XCTest
import UIKit

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
        installPermissionMonitor()
    }

    // MARK: Hilfen

    private func launch(pro: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-qa-fixtures", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
            + (pro ? ["-qa-pro"] : [])
        app.launch()
    }

    private func settle(_ seconds: TimeInterval = 1.2) { Thread.sleep(forTimeInterval: seconds) }

    private func snap(_ name: String, settleFor seconds: TimeInterval = 1.2) {
        settle(seconds)
        checkpoint(name, app: app)
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

    private func waitForEditorPreview() {
        let busy = element("editor.preview.rendering")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: busy)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 20), .completed, "The latest preview must finish")
    }

    /// The QA photo is blue; red markup must appear/disappear in the actual rendered image.
    private func redPixels(in element: XCUIElement) -> Int {
        guard let image = element.screenshot().image.cgImage else { XCTFail("Missing stage pixels"); return 0 }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        XCTAssertTrue(drawn)
        return stride(from: 0, to: bytes.count, by: 4).reduce(0) { count, i in
            count + (bytes[i] > 200 && bytes[i + 1] < 120 && bytes[i + 2] < 120 ? 1 : 0)
        }
    }

    private func tap(_ id: String, _ what: String) -> Bool {
        let e = element(id)
        guard waitFor(e, 10, what) else { return false }
        for _ in 0..<6 where !e.isHittable { app.swipeUp() }
        guard e.isHittable else { XCTFail("Nicht erreichbar: \(what)"); return false }
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
        let close = app.buttons["feed.close"].firstMatch
        if close.waitForExistence(timeout: 3) { close.tap() }
        settle(0.8)
    }

    private func onboarding(capture: Bool) {
        finishIntroduction(in: app, prefix: capture ? "qa_intro" : "qa_\(name)")
        let skip = app.buttons["Tutorial überspringen"].firstMatch
        if skip.waitForExistence(timeout: 2) { skip.tap(); snap("qa_today_tour_skipped") }
    }

    // MARK: Hauptdurchgang

    func testMainScreens() {
        launch(pro: true)
        onboarding(capture: true)

        // 03 Heute
        waitFor(app.tabBars.buttons["Heute"], 10, "Heute")
        settle(2.5)
        snap("03_home")

        // Foto-Feed mit echter Gestenlogik
        tab("Aufräumen")
        if tap("hub.photos", "Fotos im Aufräumen-Hub") {
            let stage = element("feed.stage")
            if waitFor(stage, 10, "Feed-Bühne") {
                let skip = app.buttons["Tutorial überspringen"].firstMatch
                if skip.waitForExistence(timeout: 2) { skip.tap() }
                snap("04a_gesture_hints", settleFor: 0.9)
                settle(6.5)
                if skip.waitForExistence(timeout: 1) { skip.tap() }
                snap("04_review_photo")
                stage.swipeUp()                      // HOCH = Behalten + weiter
                settle(1.5)
                snap("04b_after_up_keep")
                XCTAssertTrue(element("feed.stage").exists)
                stage.swipeLeft()                    // LINKS = Papierkorb + weiter
                settle(1.5)
                snap("04c_after_left_cleanup")
                stage.swipeLeft()
                settle(1.5)
                stage.swipeRight()                   // RECHTS = Später mit Standardtermin + weiter
                snap("06_later_pill", settleFor: 0.9) // Pille „In 2 Tagen wieder · Ändern“
                XCTAssertTrue(element("later.pill").exists)
                settle(2.5)
                stage.swipeDown()                    // RUNTER = Vorheriges, keine Entscheidung
                settle(1.5)
                snap("04d_after_down_previous")

                if tap("feed.dock", "Papierkorb-Leiste") {
                    settle(1.5)
                    snap("07_cleanup_basket")
                    let remove = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Fotos und Videos entfernen'")).firstMatch
                    if waitFor(remove, 6, "Papierkorb leeren") {
                        remove.tap()
                        snap("08_cleanup_confirm")
                        // iOS 26 can expose this as a popover without a hittable Cancel.
                        // Termination dismisses it safely, without touching the destructive action.
                        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'entfernen'")).firstMatch.exists)
                        app.terminate()
                        launch(pro: true)
                        onboarding(capture: false)
                        tab("Aufräumen")
                    }
                }
            }
            closeFeed()
        }

        // 05 Video-Feed
        if tap("hub.videos", "Videos im Aufräumen-Hub") {
            if waitFor(element("feed.stage"), 10, "Video-Feed") {
                // This fresh QA launch shows the hints before the delayed feed tutorial.
                // Waiting only for the tutorial immediately after opening misses it.
                settle(6.5)
                let skip = app.buttons["Tutorial überspringen"].firstMatch
                if skip.waitForExistence(timeout: 2) { skip.tap() }
                XCTAssertFalse(skip.exists)
                settle(1)
                snap("05_review_video")
            }
            closeFeed()
        }

        // 09 Duplikate (wie alle Werkzeuge kostenlos)
        if tap("hub.duplicates", "Duplikate") {
            let cloud = app.switches["duplicates.includeCloud"]
            XCTAssertTrue(cloud.waitForExistence(timeout: 5))
            // Die Geräteaufnahme bleibt lokal. Der Schalter muss sichtbar und bedienbar sein.
            if cloud.value as? String == "1" { cloud.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
            XCTAssertEqual(cloud.value as? String, "0")
            snap("09a_duplicates_all_resources_and_cloud_option")
            let start = app.buttons["Kopien suchen"]
            if waitFor(start, 8, "Kopien suchen") {
                start.tap()
                XCTAssertTrue(app.buttons["Erneut suchen"].waitForExistence(timeout: 180))
            }
            settle(1.5)
            snap("09_duplicates")
            back()
        }

        if tap("hub.large", "Große Dateien") { settle(4); snap("10_large_files"); back() }
        if tap("hub.storage", "Speicherübersicht") { settle(2.5); snap("11_storage_insights"); back() }
        if tap("hub.files", "Downloads") { settle(2.5); snap("11b_downloads"); back() }

        // Studio
        tab("Studio")
        settle(1)
        snap("13_studio")

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

    /// Ein Finger zeichnet auch bei Zoom; Zoomen allein darf keine Bearbeitung erzeugen.
    func testZoomedPhotoMarkupAndUndo() {
        launch(pro: false)
        onboarding(capture: false)
        tab("Aufräumen")
        guard tap("hub.photos", "Fotos für Zeichenregression") else { return }
        XCTAssertTrue(element("feed.stage").waitForExistence(timeout: 15))
        settle(6.5)
        let skip = app.buttons["Tutorial überspringen"].firstMatch
        if skip.waitForExistence(timeout: 2) { skip.tap() }
        let edit = app.buttons["Bearbeiten"].firstMatch
        guard waitFor(edit, 5, "Foto bearbeiten") else { return }
        edit.tap()
        XCTAssertTrue(element("editor.stage").waitForExistence(timeout: 30))
        waitForEditorPreview()
        snap("editor_01_loaded_no_changes")

        let markup = element("editor.tool.markup")
        // Querying isHittable for an offscreen iOS 26 button can itself fail
        // XCTest. Bring its frame into the strip before asking for hit points.
        for _ in 0..<4 where !element("editor.tools").frame.contains(CGPoint(x: markup.frame.midX, y: markup.frame.midY)) {
            element("editor.tools").swipeLeft()
            snap("editor_02_reveal_markup")
        }
        XCTAssertTrue(markup.isHittable)
        markup.tap()
        snap("editor_03_markup")
        let draw = app.buttons["Zeichnen"].firstMatch
        XCTAssertTrue(draw.waitForExistence(timeout: 5))
        draw.tap()
        snap("editor_04_draw_selected")

        let stage = element("editor.stage")
        let undo = app.buttons["editor.undo"]
        let redo = app.buttons["editor.redo"]
        XCTAssertFalse(undo.isEnabled)
        stage.pinch(withScale: 2.5, velocity: 1)
        waitForEditorPreview()
        snap("editor_05_zoomed_no_edit")
        let percentage = (stage.value as? String ?? "").filter(\.isNumber)
        XCTAssertGreaterThan(Int(percentage) ?? 0, 150, "Zoom must actually be active")
        XCTAssertFalse(undo.isEnabled, "A two-finger view gesture must not create a stroke")
        let baselineRed = redPixels(in: stage)

        stage.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: stage.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6)))
        waitForEditorPreview()
        snap("editor_06_stroke_at_zoom")
        XCTAssertTrue(undo.isEnabled, "Drawing must work while zoomed")
        XCTAssertGreaterThan(redPixels(in: stage), baselineRed + 100, "The stroke must actually be visible")
        undo.tap()
        waitForEditorPreview()
        snap("editor_07_zoomed_stroke_undone")
        XCTAssertFalse(undo.isEnabled, "One physical stroke is exactly one undo step")
        XCTAssertTrue(redo.isEnabled)
        XCTAssertLessThanOrEqual(abs(redPixels(in: stage) - baselineRed), max(30, baselineRed / 100), "Undo must remove the visible stroke")
        redo.tap()
        waitForEditorPreview()
        snap("editor_08_zoomed_stroke_redone")
        XCTAssertTrue(undo.isEnabled)
        XCTAssertGreaterThan(redPixels(in: stage), baselineRed + 100)

        for attempt in 1...4 where (stage.value as? String ?? "").filter(\.isNumber) != "100" {
            // XCTest synthesizes finger distances, not an exact final scale;
            // small stages can reach the minimum touch spacing before 1×.
            stage.pinch(withScale: 0.25, velocity: -1)
            snap("editor_09_zoom_out_attempt_\(attempt)")
        }
        snap("editor_09_full_image_stroke_alignment")
        XCTAssertEqual((stage.value as? String ?? "").filter(\.isNumber), "100")
        XCTAssertTrue(undo.isEnabled)
        // No save or overwrite: the original and Photos library stay intact.
        app.terminate()
    }

    /// Pro-Screen im Free-Zustand (ohne -qa-pro), damit Kauf-/Vorschau-Optionen sichtbar sind.
    func testProScreen() {
        launch(pro: false)
        onboarding(capture: false)
        let gear = app.buttons["Einstellungen"].firstMatch
        guard waitFor(gear, 8, "Einstellungen-Zahnrad") else { return }
        gear.tap()
        let pro = app.buttons["settings.pro"].firstMatch
        for _ in 0..<5 where !pro.waitForExistence(timeout: 1) { app.swipeUp() }
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
        if done.exists { done.tap() } else { back() }
        settle(1.5)
        snap("18_dark_home")
        tab("Aufräumen")
        if tap("hub.photos", "Fotos (dunkel)") {
            settle(3.5)
            snap("19_dark_review_photo")
            closeFeed()
        }
    }
}
