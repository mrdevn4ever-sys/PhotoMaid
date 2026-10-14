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
        var requestedPhotos = false
        for page in 0..<5 {
            let next = app.buttons["onboarding.next"]
            if !next.exists && !next.waitForExistence(timeout: 3) { break }
            checkpoint("\(prefix)_intro_\(page + 1)", app: app)
            XCTAssertTrue(next.isEnabled)
            next.tap()
            if page == 4 { requestedPhotos = true }
        }
        let deadline = Date().addingTimeInterval(25)
        repeat {
            resolvePrivacyPrompts(in: app, prefix: prefix, photos: requestedPhotos)
            if app.tabBars.firstMatch.exists { break }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        XCTAssertTrue(app.tabBars.firstMatch.exists, "Introduction must reach Today")
        // UMP can arrive just after the root view. It is consent, not an app-open ad.
        Thread.sleep(forTimeInterval: 2)
        resolvePrivacyPrompts(in: app, prefix: prefix)
        checkpoint(prefix + "_today", app: app)
    }

    func resolvePrivacyPrompts(in app: XCUIApplication, prefix: String, photos: Bool = false) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let usesAds = !app.launchArguments.contains("-qa-fixtures")
        var systemPromptExpected = photos
        for step in 0..<4 {
            var handled = false
            // iOS 26's rich Photos sheet is not always exposed as an XCUI Alert.
            if photos {
                let labels = ["Allow Full Access", "Vollen Zugriff erlauben", "Allow Access to All Photos",
                              "Zugriff auf alle Fotos erlauben"]
                let buttons = springboard.buttons.matching(NSPredicate(format: "label IN %@", labels as NSArray)).allElementsBoundByIndex
                if let allow = buttons.first(where: \.isHittable) {
                    checkpoint("\(prefix)_photos_permission_\(step)", app: springboard)
                    allow.tap()
                    handled = true
                }
            }
            if usesAds, app.staticTexts["Our app wants to stay free for you"].exists {
                let next = app.webViews.buttons["Continue"].firstMatch
                if next.exists && next.isHittable {
                    checkpoint("\(prefix)_tracking_explainer_\(step)", app: app)
                    next.tap()
                    handled = true
                    systemPromptExpected = true
                }
            }
            if usesAds {
                let labels = ["Consent", "I consent", "Zustimmen", "Einwilligen", "Agree"]
                let buttons = app.webViews.buttons.matching(NSPredicate(format: "label IN %@", labels as NSArray)).allElementsBoundByIndex
                if let consent = buttons.first(where: \.isHittable) {
                    checkpoint("\(prefix)_consent_\(step)", app: app)
                    consent.tap()
                    handled = true
                    systemPromptExpected = true
                }
            }
            let alert = springboard.alerts.firstMatch
            if systemPromptExpected && alert.exists {
                let text = alert.label.lowercased() + alert.staticTexts.allElementsBoundByIndex.map(\.label).joined().lowercased()
                if !text.contains("delete") && !text.contains("löschen") && (text.contains("track") || text.contains("verfolg")) {
                    for title in ["Allow", "Erlauben", "Allow Tracking", "Tracking erlauben"] {
                        let allow = alert.buttons[title]
                        if allow.exists && allow.isHittable {
                            checkpoint("\(prefix)_att_permission_\(step)", app: springboard)
                            allow.tap()
                            handled = true
                            break
                        }
                    }
                }
            }
            if !handled { break }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
