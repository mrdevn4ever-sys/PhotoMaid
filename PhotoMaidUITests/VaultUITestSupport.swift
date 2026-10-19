import XCTest

/// Shared support for the imported vault UI tests. Photos permission only: never accept deletion,
/// tracking, purchases or any other unrelated system prompt.
@MainActor
extension XCTestCase {
    func checkpoint(_ name: String, app: XCUIApplication, hierarchy: Bool = true) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        if hierarchy {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = name + ".hierarchy"
            tree.lifetime = .keepAlways
            add(tree)
        }
    }

    func installPermissionMonitor() {
        addUIInterruptionMonitor(withDescription: "Photos permission only; never deletion") { alert in
            let text = alert.debugDescription.lowercased()
            guard text.contains("photo") || text.contains("foto") else { return false }
            guard !text.contains("delete"), !text.contains("löschen") else { return false }
            for label in ["Allow Full Access", "Vollen Zugriff erlauben", "Allow Access to All Photos", "Zugriff auf alle Fotos erlauben"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
    }

    func finishIntroduction(in app: XCUIApplication, prefix: String) {
        for page in 0..<5 {
            let next = app.buttons["onboarding.next"]
            if !next.exists && !next.waitForExistence(timeout: 3) { break }
            checkpoint("\(prefix)_intro_\(page)", app: app)
            XCTAssertTrue(next.isEnabled)
            next.tap()
        }
        if !app.tabBars.firstMatch.exists {
            // Trigger the narrowly scoped XCTest permission monitor without a feed decision.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.02)).tap()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 25), "Introduction must reach Today")
    }
}
