import XCTest

@MainActor
extension XCTestCase {
    /// Every checkpoint keeps the image AND the accessibility tree for review.
    func checkpoint(_ name: String, app: XCUIApplication, hierarchy: Bool = true) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if hierarchy {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = name + ".hierarchy"
            tree.lifetime = .keepAlways
            add(tree)
        }
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            do {
                let url = URL(fileURLWithPath: dir, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try shot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"))
            } catch { XCTFail("Screenshot \(name): \(error)") }
        }
    }

    func installPermissionMonitor() {
        addUIInterruptionMonitor(withDescription: "Photos, ATT and consent — never deletion") { alert in
            let text = alert.label.lowercased()
            // Explicitly refuse system deletion; no generic first-button/Allow fallback.
            if text.contains("delete") || text.contains("löschen") { return false }
            if text.contains("track"), alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
                return true
            }
            for label in ["Allow Full Access", "Vollen Zugriff erlauben", "Allow Access to All Photos",
                          "Zugriff auf alle Fotos erlauben", "Allow Tracking", "Tracking erlauben",
                          "Ask App Not to Track", "App-Tracking ablehnen", "Consent", "Zustimmen", "Einwilligen"] {
                if alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            }
            return false
        }
    }

    func finishIntroduction(in app: XCUIApplication, prefix: String) {
        for page in 0..<5 {
            let next = app.buttons["onboarding.next"]
            if !next.exists && !next.waitForExistence(timeout: 3) { break }
            checkpoint("\(prefix)_intro_\(page + 1)", app: app)
            XCTAssertTrue(next.isEnabled)
            next.tap()
        }
        if !app.tabBars.firstMatch.waitForExistence(timeout: 5),
           XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists {
            app.tap() // Only trigger the monitor for a real system alert.
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "Introduction must reach Today")
        checkpoint(prefix + "_today", app: app)
    }
}
