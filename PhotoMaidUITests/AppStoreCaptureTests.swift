import XCTest
import StoreKitTest
import ImageIO
import Vision

/// Marketing capture, only invoked by app-store-assets.yml. Uses imported CC0 photos and actual app state.
@MainActor
final class AppStoreCaptureTests: XCTestCase {
    private var app: XCUIApplication!
    private var store: SKTestSession!
    private var language = "en"
    private var output = URL(fileURLWithPath: "/tmp/photomaid-store")
    private var localized: Bundle!
    private var shots: [[String: String]] = []
    private var clip: String?
    private var isConceptA: Bool { name.contains("test07ConceptAStoreScreenshots") }
    private var conceptAEvidenceLog: [[String: Any]] = []

    override func setUp() async throws {
        guard let value = ProcessInfo.processInfo.environment["STORE_CAPTURE_LOCALE"] else {
            throw XCTSkip("Only run through the explicit App Store capture workflow")
        }
        language = value
        output = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["STORE_CAPTURE_DIR"]))
        let resources = Bundle(for: Self.self)
        localized = try XCTUnwrap(Bundle(path: resources.bundlePath + "/\(language).lproj"))
        try FileManager.default.createDirectory(at: output.appendingPathComponent("screenshots"), withIntermediateDirectories: true)
        continueAfterFailure = false
        installPermissionMonitor()
        // Match the Store creative's visible currency to its storefront. The app still reads
        // Product.displayPrice from StoreKit; this is a simulator-only configuration, never a hard-coded price.
        store = try SKTestSession(configurationFileNamed: language == "en" ? "PhotoMaidUS" : "PhotoMaid")
        store.disableDialogs = true
        if name.contains("test00") || name.contains("test06") || isConceptA { store.resetToDefaultState(); try store.clearTransactions() }
    }

    override func tearDown() async throws {
        if clip != nil { try? recording("stop", name: clip!) }
        app?.terminate()
        if !shots.isEmpty {
            let data = try JSONSerialization.data(withJSONObject: shots, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("\(name.components(separatedBy: " ").last!.replacingOccurrences(of: "]", with: ""))-screens.json"))
        }
    }

    private func t(_ key: String) -> String { localized.localizedString(forKey: key, value: key, table: nil) }
    private func e(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func pause(_ seconds: Double = 1) { Thread.sleep(forTimeInterval: seconds) }
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.exists || element.waitForExistence(timeout: 15), "Missing \(element)")
        for _ in 0..<6 { if element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
        element.tap(); pause(0.7)
    }
    private func button(_ key: String) -> XCUIElement {
        // SwiftUI menu items can change between Button and PopUpButton in iOS 26 snapshots.
        // Resolve by label and index so XCTest does not retain a stale, typed identity.
        let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", t(key), t(key) + ", ")
        let buttons = app.buttons.matching(predicate)
        let popups = app.popUpButtons.matching(predicate)
        let matches = buttons.allElementsBoundByIndex + popups.allElementsBoundByIndex
        return matches.first(where: \.isHittable) ?? matches.first ?? buttons.firstMatch
    }
    private func launch(_ page: String) {
        let navigation = output.appendingPathComponent("navigation")
        if let app, app.state == .runningForeground,
           FileManager.default.fileExists(atPath:navigation.appendingPathComponent("hello").path) {
            let token = UUID().uuidString
            let command = ["page":page,"token":token]
            do {
                try JSONSerialization.data(withJSONObject:command).write(to:navigation.appendingPathComponent("request.json"),options:.atomic)
                let ack = navigation.appendingPathComponent("ack-" + token + ".json")
                for _ in 0..<400 {
                    if FileManager.default.fileExists(atPath:ack.path) {
                        let result = try JSONSerialization.jsonObject(with:Data(contentsOf:ack)) as? [String:String]
                        XCTAssertEqual(result?["page"],page)
                        XCTAssertEqual(result?["token"],token)
                        XCTAssertTrue(app.windows["store.capture." + page].exists)
                        pause(0.8)
                        return
                    }
                    pause(0.1)
                }
                XCTFail("Capture navigation did not finish: \(page)")
                return
            } catch { XCTFail("Capture navigation: \(error)"); return }
        }
        try? FileManager.default.removeItem(at:navigation.appendingPathComponent("hello"))
        app?.terminate()
        app = XCUIApplication()
        let locale = language == "en" ? "en_US" : language
        app.launchArguments = ["-store-capture", "-store-page", page, "-store-navigation", output.appendingPathComponent("navigation").path, "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        if isConceptA { app.launchArguments.append("-store-concept-a") }
        app.launch()
        if page != "introduction", XCUIApplication(bundleIdentifier:"com.apple.springboard").buttons["Allow Full Access"].exists { resolvePrivacyPrompts(in: app, prefix:"store-permissions", photos:true) }
        // Introduction can render before UIKit assigns the key window, so its
        // navigation-only window marker is not a reliable cold-launch signal.
        // Wait for the actual onboarding control instead of a timing-dependent marker.
        if page == "introduction" {
            XCTAssertTrue(e("onboarding.next").waitForExistence(timeout: 40), "Actual introduction must be ready")
        } else {
            XCTAssertTrue(app.windows["store.capture." + page].waitForExistence(timeout: 40), "Requested page must finish opening: \(page)")
        }
        if page != "introduction" {
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App did not open capture page \(page)")
        }
        pause(1.4)
    }
    private func snap(_ name: String, settle: Double = 0.7, captured: XCUIScreenshot? = nil) {
        if name.hasPrefix("editor") { waitForEditorPreview() }
        if name == "viewer-info" {
            XCTAssertTrue(app.staticTexts[t("lib_info_name")].firstMatch.waitForExistence(timeout:40),"Original filename must load")
            XCTAssertTrue(app.staticTexts["…"].firstMatch.waitForNonExistence(timeout:40),"Media size must finish loading")
        }
        pause(settle)
        let banner = XCUIApplication(bundleIdentifier:"com.apple.springboard").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                                  "NotificationShortLookView", "Ready for Apple Intelligence", "Time to experience the new personal intelligence system"))
            .firstMatch
        if banner.exists && banner.isHittable {
            XCTAssertTrue(banner.waitForNonExistence(timeout: 15), "System banner must leave before capture")
        }
        // One accessibility snapshot/query, rather than one IPC round trip per text.
        let invalid = app.descendants(matching:.any).matching(NSPredicate(
            format:"label CONTAINS %@ OR label CONTAINS %@ OR label MATCHES %@ OR label MATCHES %@",
            "%1$", "%2$", "^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$", #".*%(?:[0-9]+\$)?(?:lld|ld|d|u|@|f).*"#
        )).allElementsBoundByAccessibilityElement
        XCTAssertTrue(invalid.isEmpty, "Untranslated UI: \(invalid.map(\.label))")
        let screenshot = captured ?? XCUIScreen.main.screenshot()
        do {
            try screenshot.pngRepresentation.write(to: output.appendingPathComponent("screenshots/\(name).png"), options: .atomic)
            try app.debugDescription.write(to: output.appendingPathComponent("screenshots/\(name).txt"), atomically: true, encoding: .utf8)
        } catch { XCTFail("Cannot save \(name): \(error)") }
        shots.append(["file":name + ".png", "language":language, "appearance":"dark", "status":"PASS"])
    }
    private func capturePage(_ page: String, title: String? = nil, bottom: Bool = false) {
        launch(page)
        if let title { XCTAssertTrue(app.navigationBars[t(title)].waitForExistence(timeout: 15), page) }
        if page == "today" { awaitCurrentTodayCounts() }
        snap(page)
        if bottom { app.swipeUp(); app.swipeUp(); snap(page + "-bottom") }
    }
    private func awaitCurrentTodayCounts() {
        let photos = e("today.quick.photos")
        XCTAssertTrue(photos.waitForExistence(timeout: 30))
        let deadline = Date().addingTimeInterval(45)
        var reported = ""
        repeat {
            reported = photos.label.compactMap(\.wholeNumberValue).map(String.init).joined()
            // The actual, independently inventoried Store fixture has 55 photos.
            // Wait for the visible count; never inject a number into the app.
            if reported == "55" { return }
            pause(0.2)
        } while Date() < deadline
        XCTFail("Today must show the real loaded photo count before capture; received: \(photos.label)")
    }
    private func waitForPhotoAccess() {
        let deadline = Date().addingTimeInterval(45)
        repeat {
            resolvePrivacyPrompts(in: app, prefix:"store-photo-access", photos:true)
            // The production TabView is sidebar-adaptable. A bottom tab bar is
            // not a portable readiness signal on the genuine Duo inner display.
            // Require actual Today content instead; the following capture still
            // checks its real55-photo count and independent PhotoKit inventory.
            if e("today.quick.photos").exists { return }
            pause(0.5)
        } while Date() < deadline
        XCTFail("Photo access must finish before capture")
    }
    private func awaitStage() {
        XCTAssertTrue(e("feed.stage").waitForExistence(timeout: 20))
        pause(1)
    }
    private func feedPosition() -> Int {
        let label = e("feed.position").label
        let digits = label.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        let format = t("feed_position")
        let totalFirst = format.range(of:"%2$").map { total in
            format.range(of:"%1$").map { total.lowerBound < $0.lowerBound } ?? false
        } ?? false
        let current = totalFirst ? digits.last : digits.first
        let normalized = (current ?? "").compactMap(\.wholeNumberValue).map(String.init).joined()
        return Int(normalized) ?? -1
    }
    private func swipeFeed(_ direction: String) {
        let before = feedPosition()
        XCTAssertGreaterThan(before,0)
        switch direction {
        case "up": e("feed.stage").swipeUp()
        case "left": e("feed.stage").swipeLeft()
        case "right": e("feed.stage").swipeRight()
        default: e("feed.stage").swipeDown()
        }
        pause(1)
        XCTAssertEqual(feedPosition(),before + (direction == "down" ? -1 : 1), "Actual feed decision/navigation must advance")
    }
    /// Sichtbarer Wisch wie mit dem Finger: langsam ziehen, kurz halten (Richtungs-Pille und verschobenes Foto sind zu
    /// sehen), dann loslassen – dieselbe echte Geste und Entscheidung wie sonst. `still`: echter Simulator-Screenshot
    /// mitten im Halten (Store-Bild „Keep“/„Trash“), aufgenommen vom Aufnahme-Controller.
    private func holdSwipe(_ direction: String, still: String? = nil, offset customOffset: CGVector? = nil,
                           holdDuration: TimeInterval? = nil) throws {
        let before = feedPosition()
        XCTAssertGreaterThan(before, 0)
        let stage = e("feed.stage")
        let start = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let defaultOffset: CGVector = switch direction {
        case "up": CGVector(dx: 0, dy: -230)
        case "left": CGVector(dx: -210, dy: 0)
        case "right": CGVector(dx: 210, dy: 0)
        default: CGVector(dx: 0, dy: 230)
        }
        let offset = customOffset ?? defaultOffset
        // Ein simctl-Screenshot braucht auf CI mehrere Sekunden (Lauf 39808617005: 5–15 s); für das Store-Bild wird
        // deshalb 8 s gehalten, im Clip 1,6 s.
        if let still { try requestStill(still, delay: 1.0) }
        start.press(forDuration: 0.12, thenDragTo: start.withOffset(offset), withVelocity: XCUIGestureVelocity(rawValue: 320),
                    thenHoldForDuration: holdDuration ?? (still == nil ? 1.6 : 8))
        pause(1)
        XCTAssertEqual(feedPosition(), before + (direction == "down" ? -1 : 1), "Actual feed decision/navigation must advance")
        if let still { try awaitStill(still) }
    }
    private func requestStill(_ name: String, delay: Double, warmup: Bool = false) throws {
        let directory = output.appendingPathComponent("control")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let token = UUID().uuidString
        let request: [String: Any] = ["operation": "still", "name": name, "token": token, "delay": delay, "warmup": warmup]
        try JSONSerialization.data(withJSONObject: request).write(to: directory.appendingPathComponent("request-\(token).json"), options: .atomic)
        let ack = directory.appendingPathComponent("ack-\(token).json")
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: ack.path) {
                let value = try JSONSerialization.jsonObject(with: Data(contentsOf: ack)) as? [String: Any]
                XCTAssertEqual(value?["status"] as? String, "ok", value?["error"] as? String ?? "Still request failed")
                return
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTFail("Recording controller did not acknowledge still \(name)")
    }
    private func awaitStill(_ name: String) throws {
        let result = output.appendingPathComponent("stills/\(name).json")
        // Der erste simctl-Screenshot eines Laufs brauchte auf CI zuletzt über 30 s (Läufe 257/258): bis 120 s warten.
        for _ in 0..<1200 {
            if FileManager.default.fileExists(atPath: result.path) {
                let value = try JSONSerialization.jsonObject(with: Data(contentsOf: result)) as? [String: Any]
                XCTAssertEqual(value?["returncode"] as? Int, 0, value?["stderr"] as? String ?? "Still failed")
                if !name.hasPrefix("warmup") {
                    shots.append(["file": name + ".png", "language": language, "appearance": "dark", "status": "PASS"])
                }
                return
            }
            pause(0.1)
        }
        XCTFail("Still was not captured: \(name)")
    }
    private func editorTool(_ tool: String) {
        let target = e("editor.tool." + tool)
        let row = e("editor.tools")
        func isVisible() -> Bool {
            guard target.exists else { return false }
            let frame = target.frame
            let bounds = row.frame.intersection(app.frame)
            return !frame.isEmpty && bounds.contains(CGPoint(x:frame.midX,y:frame.midY))
        }
        for _ in 0..<6 {
            if isVisible() { break }
            if language == "ar" { row.swipeRight() } else { row.swipeLeft() }
        }
        for _ in 0..<6 {
            if isVisible() { break }
            if language == "ar" { row.swipeLeft() } else { row.swipeRight() }
        }
        XCTAssertTrue(isVisible(), "Editor tool must be scrolled into view: \(tool)")
        tap(target)
        XCTAssertTrue(e("editor.stage").exists)
        if tool == "filter" {
            XCTAssertTrue(e("editor.filter.thumbnail.NONE").waitForExistence(timeout:60),"Actual filter thumbnails must finish")
        }
        waitForEditorPreview()
    }
    private func waitForEditorPreview() {
        let deadline = Date().addingTimeInterval(60)
        while e("editor.preview.rendering").exists && Date() < deadline { pause(0.2) }
        XCTAssertFalse(e("editor.preview.rendering").exists,"Actual editor preview must finish")
    }

    func test00EveryPageInDarkMode() throws {
        launch("introduction")
        for index in 1...5 {
            XCTAssertTrue(e("onboarding.next").waitForExistence(timeout: 15))
            snap(String(format: "introduction-%02d", index))
            tap(e("onboarding.next"))
        }
        waitForPhotoAccess()
        capturePage("today")
        launch("feed"); awaitStage(); snap("feed")
        swipeFeed("up"); pause(1)
        swipeFeed("left"); pause(1)
        swipeFeed("right"); pause(1); snap("feed-later")
        let pages: [(String,String?,Bool)] = [
            ("library",nil,false),("library-favorites",nil,false),("library-photos",nil,false),("library-videos",nil,false),("library-screenshots",nil,false),("cleanup",nil,true),("studio",nil,true),("history",nil,false),
            ("trash",nil,false),("later",nil,false),("months",nil,false),
            ("large-files","large_files",false),("duplicates","duplicates",false),("storage","storage_overview",true),
            ("files","files",false),("series","series_title",false),("collections",nil,true),
            ("blurry","ana_blurry",false),("similar","ana_similar",false),("documents","ana_documents",false),("categories","ana_categories",false),
            ("albums",nil,false),("album",nil,false),("grid",nil,false),("favorites",nil,false),("selection",nil,false),("tags",nil,false),("hidden",nil,false),
            ("edits",nil,false),("collage",nil,false),("movie",nil,true),
            ("tools-resize",nil,true),("tools-convert",nil,true),("tools-removeLocation",nil,true),("tools-stitch",nil,true),("tools-gif",nil,true),("tools-batchEdit",nil,true),
            ("received",nil,false),("workflows",nil,true),("pdf",nil,true),("pdf-studio",nil,false),("archive",nil,true),
            ("settings","settings",true),("pro","pro_title",true),("privacy","privacy_title",true),("help","help",true),
            ("excluded-albums",nil,false),("backup","backup_title",true),("controls","fc_title",true),
            ("viewer",nil,false),("slideshow",nil,false)
        ]
        for (page,title,bottom) in pages {
            capturePage(page, title:title, bottom:bottom)
            if ["blurry","similar","documents","categories"].contains(page) {
                let start = button("ana2_start")
                if start.waitForExistence(timeout:10) && start.isEnabled {
                    tap(start); snap(page + "-progress")
                    let progress = e("analysis.progress")
                    let deadline = Date().addingTimeInterval(240)
                    var finished = false
                    var resumes = 0
                    var lastChange = Date()
                    var previous = ""
                    repeat {
                        let value = progress.value as? String ?? ""
                        if value != previous { previous = value; lastChange = Date() }
                        let values = value.split(separator:"/").compactMap { Int($0) }
                        let done = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@",t("ana2_stage_finished"))).firstMatch
                        if (values.count == 2 && values[1] > 0 && values[0] == values[1]) || done.exists { finished = true; break }
                        // A genuine paused run can be continued through the same controls as a user.
                        // Keep the pause evidence and still require the actual analysis to finish.
                        let paused = app.descendants(matching:.any).matching(NSPredicate(format:"label == %@",t("ana2_stage_paused"))).firstMatch
                        if resumes < 2, Date().timeIntervalSince(lastChange) > 10, paused.exists {
                            let remaining = values.count == 2 ? values[1] - values[0] : 0
                            let retry = app.buttons[String(format:t("ana2_retry_failed"),remaining)].firstMatch
                            let resume = retry.exists ? retry : button("ana2_resume")
                            if resume.exists && resume.isEnabled {
                                resumes += 1; snap(page + "-paused-resume-\(resumes)")
                                tap(resume); lastChange = Date()
                            }
                        }
                        pause(1)
                    } while Date() < deadline
                    XCTAssertTrue(finished,"Actual on-device analysis must finish: \(page)")
                    snap(page + "-results"); app.swipeUp(); snap(page + "-results-grid")
                }
            }
        }
        launch("editor")
        XCTAssertTrue(e("editor.stage").waitForExistence(timeout: 30))
        snap("editor")
        for tool in ["crop","adjust","filter","retouch","markup","frame","resize"] {
            editorTool(tool); snap("editor-" + tool)
        }
        try captureVault()
    }

    func test01DetailPagesInDarkMode() throws {
        launch("feed"); awaitStage()
        tap(button("more_actions")); snap("feed-menu")
        tap(button("feed_show_hints")); snap("feed-gesture-guide"); pause(6.5)
        launch("viewer")
        tap(button("info")); snap("viewer-info"); tap(button("done"))
        tap(button("org_add_to_album")); snap("viewer-album-picker"); tap(button("cancel"))
        launch("slideshow")
        app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        tap(button("slideshow_settings")); snap("slideshow-settings"); tap(button("done"))
        launch("workflows")
        tap(button("wf_new")); snap("workflow-editor"); tap(button("cancel"))
        launch("collage")
        tap(button("save")); snap("collage-save-options"); tap(button("cancel"))
        launch("editor")
        XCTAssertTrue(e("editor.stage").waitForExistence(timeout:30))
        editorTool("markup"); tap(button("edit_mk_draw"))
        let stage=e("editor.stage")
        stage.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.8)).press(forDuration:0.1,thenDragTo:stage.coordinate(withNormalizedOffset:CGVector(dx:0.45,dy:0.75)))
        pause(1); tap(button("save")); snap("editor-save-options"); tap(button("cancel"))
        openVault()
        snap("vault-media-before-details")
        let more = app.buttons.matching(NSPredicate(format:"label == %@",t("more_actions"))).allElementsBoundByIndex
            .first { $0.identifier != "vault.workspace.more" }
        tap(try XCTUnwrap(more)); tap(button("vault_settings")); snap("vault-settings")
        tap(button("vault_change_code")); snap("vault-change-code-empty"); tap(button("cancel")); tap(button("done"))
        tap(app.segmentedControls.buttons[t("vault2_notes")])
        tap(button("vault2_new_note"))
        tap(e("vault.note.title")); e("vault.note.title").typeText("GaleriQ")
        tap(button("done"))
        let notes = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'vault.notes.item.'"))
        XCTAssertTrue(notes.firstMatch.waitForExistence(timeout:10)); snap("vault-notes-with-note")
        tap(notes.firstMatch); snap("vault-note-editor"); tap(button("done"))
    }

    private func openVault() {
        launch("vault")
        for _ in 0..<100 {
            if app.vaultKeypad.exists || button("onb_next").exists { break }
            pause(0.1)
        }
        if app.vaultKeypad.exists {
            app.enterVaultPIN("628491")
        } else {
            snap("vault-setup-introduction"); tap(button("onb_next"))
            let fields = app.secureTextFields
            XCTAssertEqual(fields.count,2)
            snap("vault-setup-code-empty")
            fields.element(boundBy:0).tap(); fields.element(boundBy:0).typeText("628491")
            fields.element(boundBy:1).tap(); fields.element(boundBy:1).typeText("628491")
            tap(button("onb_next"))
            let face = app.switches.matching(NSPredicate(format:"label CONTAINS 'Face ID'")).firstMatch
            if face.exists {
                if face.value as? String == "1" { face.coordinate(withNormalizedOffset: CGVector(dx:0.92,dy:0.5)).tap() }
                tap(button("onb_next"))
            }
            // Never publish a recovery key in marketing assets. Skip this optional simulator key.
            tap(button("vault_recovery_skip"))
            tap(app.alerts.buttons[t("vault_recovery_skip")])
            let hidden = app.switches[t("vault_hide_entry")]
            if hidden.value as? String == "1" { hidden.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap() }
            snap("vault-setup-entry"); tap(button("vault_setup_finish"))
        }
        XCTAssertTrue(app.segmentedControls.buttons[t("vault2_media")].waitForExistence(timeout: 25))
        pause(1)
    }
    private func vaultItems() -> XCUIElementQuery { app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'vault.media.item.'")) }
    private func captureVault(deleteOriginals: Bool = false) throws {
        openVault()
        if vaultItems().count == 0 {
            tap(button("vault_add"))
            let picker = app.buttons.matching(identifier:"picker.media")
            XCTAssertTrue(picker.firstMatch.waitForExistence(timeout:15))
            for index in 0..<5 { tap(picker.element(boundBy:index)) }
            snap("vault-media-picker")
            tap(button("done")); tap(app.alerts.buttons[t("vault_import_action")])
            let springboard = XCUIApplication(bundleIdentifier:"com.apple.springboard")
            let alert = springboard.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout:60))
            if deleteOriginals {
                let confirm = alert.buttons.allElementsBoundByIndex.first { element in
                    let label = element.label.lowercased()
                    return (label.contains("delete") || label.contains("löschen"))
                        && !label.contains("don't") && !label.contains("don’t") && !label.contains("nicht")
                }
                let delete = try XCTUnwrap(confirm, "The disposable Store fixture must expose the real iOS delete confirmation")
                pause(0.5)
                delete.tap()
                XCTAssertTrue(alert.waitForNonExistence(timeout: 10), "Confirmed system deletion must finish")
            } else {
                for _ in 0..<4 {
                    guard alert.exists else { break }
                    let cancel = alert.buttons.matching(NSPredicate(format:"label IN %@",["Don't Allow","Don’t Allow","Don't Delete","Don’t Delete","Cancel","Nicht erlauben","Nicht löschen","Abbrechen"] as NSArray)).firstMatch
                    XCTAssertTrue(cancel.waitForExistence(timeout:3),"Only decline system deletion")
                    pause(0.5) // the first tap can otherwise coincide with the system alert's entrance
                    cancel.tap()
                    if alert.waitForNonExistence(timeout:3) { break }
                }
                XCTAssertFalse(alert.exists,"System deletion dialog must be dismissed by declining")
            }
            let notice = app.alerts.buttons[t("ok")]
            if notice.waitForExistence(timeout:15) {
                tap(notice)
                XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout:5))
            }
        }
        XCTAssertEqual(vaultItems().count,5)
        if deleteOriginals {
            XCTAssertTrue(button("vault_still_in_photos_action").waitForNonExistence(timeout: 20),
                          "Vault creative must not imply protected originals while copies remain in Photos")
        }
        snap("vault-media")
        tap(vaultItems().firstMatch); snap("vault-viewer")
        tap(app.buttons["vault.viewer.close"])
        tap(app.segmentedControls.buttons[t("vault2_notes")]); snap("vault-notes")
        tap(app.segmentedControls.buttons[t("vault2_files")]); snap("vault-files")
        tap(app.buttons["vault.workspace.more"]); tap(button("vault2_tools")); snap("vault-tools")
        tap(button("done"))
        tap(app.buttons["vault.workspace.more"]); tap(button("vault2_trash")); snap("vault-trash")
        tap(button("done"))
    }

    /// Separate preview jobs use a fresh library too; the vault is populated through its real UI.
    func test05PrepareMediaForPreviews() throws {
        launch("introduction")
        for _ in 0..<5 { tap(e("onboarding.next")) }
        waitForPhotoAccess()
        try captureVault()
    }

    private func recording(_ operation: String, name: String) throws {
        let directory = output.appendingPathComponent("control")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let token = UUID().uuidString
        let request:[String:String] = ["operation":operation,"name":name,"token":token]
        try JSONSerialization.data(withJSONObject:request).write(to:directory.appendingPathComponent("request-\(token).json"),options:.atomic)
        let ack = directory.appendingPathComponent("ack-\(token).json")
        for _ in 0..<900 {
            if FileManager.default.fileExists(atPath:ack.path) {
                let value = try JSONSerialization.jsonObject(with:Data(contentsOf:ack)) as? [String:Any]
                XCTAssertEqual(value?["status"] as? String,"ok",value?["error"] as? String ?? "Recording controller failed")
                clip = operation == "start" ? name : nil
                return
            }
            pause(0.1)
        }
        XCTFail("Recording controller did not acknowledge \(operation)")
    }
    private func mark(_ label: String) throws {
        let name = try XCTUnwrap(clip)
        snap("preview-\(name)-\(label)")
        let entry:[String:Any] = ["clip":name,"label":label,"time":Date().timeIntervalSince1970]
        let path=output.appendingPathComponent("markers.jsonl")
        var data=(try? Data(contentsOf:path)) ?? Data()
        data.append(try JSONSerialization.data(withJSONObject:entry));data.append(10)
        try data.write(to:path,options:.atomic)
    }

    /// Current product-page selection. The older exhaustive page archive stays available separately.
    func test06CurrentStoreScreenshots() throws {
        launch("introduction")
        for _ in 0..<5 { tap(e("onboarding.next")) }
        waitForPhotoAccess()
        capturePage("today")
        launch("feed"); awaitStage()
        // Behalten und Papierkorb sichtbar im Store-Bild: Screenshot mitten in der gehaltenen Geste.
        try requestStill("warmup", delay: 0, warmup: true); try awaitStill("warmup")
        try holdSwipe("up", still: "feed-keep"); try holdSwipe("left", still: "feed-trash"); snap("feed")
        try holdSwipe("right", still: "feed-later-drag"); snap("feed-later")
        // Add a second genuine trash decision so the safety creative shows a real review set, not an empty shell.
        swipeFeed("left"); pause(1)
        capturePage("trash")
        capturePage("library")
        // Capture the hub and then one deliberate scroll where the two promised tools are fully visible.
        launch("cleanup")
        snap("cleanup")
        app.swipeUp(); pause(1)
        snap("cleanup-tools")
        capturePage("duplicates", title: "duplicates")
        capturePage("large-files", title: "large_files")
        launch("months")
        let monthsDone = button("tour_done")
        if monthsDone.waitForExistence(timeout: 5) { tap(monthsDone) }
        snap("months")
        capturePage("collage")
        capturePage("studio")
        launch("editor")
        XCTAssertTrue(e("editor.stage").waitForExistence(timeout: 30))
        editorTool("filter")
        snap("editor-filter")
        let mono = button("edit_filter_mono")
        tap(mono)
        XCTAssertTrue(mono.isSelected, "Store screenshot must show a genuinely applied filter")
        waitForEditorPreview()
        snap("editor-filter-applied")
        editorTool("markup"); snap("editor-markup")
        capturePage("movie")
        capturePage("pro", title: "pro_title", bottom: true)
        try captureVault(deleteOriginals: true)
        try prepareMemoryForStore()
        snap("memory-play")
        tap(e("memory.close"))
        prepareSnakeForStore()
        let board = e("snake.board")
        let startingValue = board.value as? String
        var snakeMoved = false
        for _ in 0..<3 where !snakeMoved {
            board.swipeRight(); pause(0.4)
            // Under CI load a swipe can be interpreted as a tap and pause the round. Resume and retry the
            // genuine gesture, then poll the accessibility value instead of assuming one fixed frame interval.
            if app.buttons["snake.start"].exists { tap(app.buttons["snake.start"]); pause(0.4) }
            for _ in 0..<20 {
                pause(0.25)
                if board.value as? String != startingValue { snakeMoved = true; break }
            }
        }
        XCTAssertTrue(snakeMoved, "Snake must visibly advance before the store image")
        snap("snake-play")
        tap(e("snake.play").buttons["snake.pause"]); snap("snake-pause")
        tap(e("snake.play").buttons["snake.settings"])
        snap("snake-settings"); tap(button("done"))
        tap(e("snake.play").buttons["snake.close"])
        XCTAssertTrue(e("feed.stage").waitForExistence(timeout: 10))
    }

    // MARK: Fresh, genuine en-US Concept A

    /// A read-only simulator file bridge. It observes the current page without dismissing it or starting a scan.
    private func conceptAObserve(_ checkpoint: String) throws -> [String: Any] {
        let navigation = output.appendingPathComponent("navigation")
        XCTAssertTrue(FileManager.default.fileExists(atPath: navigation.appendingPathComponent("hello").path))
        let token = UUID().uuidString
        let command = ["page": "concept-a-evidence", "token": token]
        try JSONSerialization.data(withJSONObject: command).write(to: navigation.appendingPathComponent("request.json"), options: .atomic)
        let ack = navigation.appendingPathComponent("ack-" + token + ".json")
        let deadline = Date().addingTimeInterval(30)
        while !FileManager.default.fileExists(atPath: ack.path), Date() < deadline { pause(0.1) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ack.path),
                      "Read-only native evidence acknowledgement timed out at \(checkpoint); no source state is assumed")
        let result = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: ack)) as? [String: Any])
        XCTAssertEqual(result["page"] as? String, "concept-a-evidence")
        XCTAssertEqual(result["token"] as? String, token)
        XCTAssertEqual(result["status"] as? String, "ready", result["error"] as? String ?? "Native observation must succeed")
        let evidence = try XCTUnwrap(result["evidence"] as? [String: Any])
        XCTAssertEqual(evidence["setupErrors"] as? [String], [], "Native capture setup must not silently fall back")
        XCTAssertEqual(evidence["fixtureMode"] as? Bool, false, "Never use the synthetic in-memory QA library")
        conceptAEvidenceLog.append(["checkpoint": checkpoint, "state": evidence])
        try JSONSerialization.data(withJSONObject: conceptAEvidenceLog, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("concept-a-evidence.json"), options: .atomic)
        return evidence
    }

    private func conceptAWait(_ checkpoint: String, timeout: TimeInterval = 90,
                              until ready: ([String: Any]) -> Bool) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        var state = try conceptAObserve(checkpoint)
        while !ready(state), Date() < deadline { pause(0.8); state = try conceptAObserve(checkpoint) }
        XCTAssertTrue(ready(state), "Real state did not finish: \(checkpoint)")
        return state
    }

    private func conceptAAsset(_ filename: String, in state: [String: Any]) throws -> [String: Any] {
        let inventory = try XCTUnwrap(state["inventory"] as? [[String: Any]])
        let matches = inventory.filter { $0["filename"] as? String == filename }
        XCTAssertEqual(matches.count, 1, "Exactly one real PhotoKit asset must match \(filename)")
        return try XCTUnwrap(matches.first)
    }

    private func conceptAID(_ filename: String, in state: [String: Any]) throws -> String {
        try XCTUnwrap(try conceptAAsset(filename, in: state)["id"] as? String)
    }

    private func conceptAFullyVisible(_ element: XCUIElement) -> Bool {
        element.exists && !element.frame.isEmpty && app.frame.contains(element.frame)
    }

    private func conceptARequireVisible(_ element: XCUIElement, _ reason: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 20), reason)
        XCTAssertTrue(conceptAFullyVisible(element), "Not fully visible: \(reason), \(element.frame)")
    }

    private func conceptAText(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", text)).firstMatch
    }

    private func conceptAAssertPNG(_ url: URL, screen: Bool = true) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), "Missing real native PNG: \(url.lastPathComponent)")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        if screen { XCTAssertEqual(image.width, 1206); XCTAssertEqual(image.height, 2622) }
        else { XCTAssertGreaterThan(image.width, 0); XCTAssertGreaterThan(image.height, 0) }
    }

    private func conceptARequireStage(_ asset: [String: Any]) throws {
        let value = try XCTUnwrap(asset["accessibilityValue"] as? String)
        XCTAssertTrue(e("feed.stage").waitForExistence(timeout: 30))
        let deadline = Date().addingTimeInterval(30)
        while (e("feed.stage").value as? String != value || e("feed.preview.loading").exists), Date() < deadline { pause(0.2) }
        XCTAssertEqual(e("feed.stage").value as? String, value, "The selected imported original must be on top")
        XCTAssertFalse(e("feed.preview.loading").exists)
        XCTAssertFalse(e("feed.preview.failed").exists)
        XCTAssertTrue(e("feed.media").exists)
    }

    /// Fresh simulator only. No purchase, model, size, scan-result, or decision fixture is installed.
    func test07ConceptAStoreScreenshots() throws {
        XCTAssertEqual(language, "en", "Concept A is a new en-US master, not a localization/historical-source job")
        launch("introduction")
        for _ in 0..<5 { tap(e("onboarding.next")) }
        waitForPhotoAccess()
        launch("today")
        conceptARequireVisible(e("today.title"), "Actual canonical GaleriQ wordmark")
        XCTAssertTrue(e("today.quick.photos").exists)
        // Parent's recorder captures THIS native screen and imports precisely that file through simctl addmedia.
        try recording("fixture-screenshot", name: "concept-a-native-library")
        try conceptAAssertPNG(output.appendingPathComponent("stills/concept-a-native-library.png"))
        launch("concept-a-library") // Reload PhotoKit and arrange the newly imported OS screenshot as well.
        let initial = try conceptAWait("initial-library") { ($0["readReady"] as? Bool == true) && ($0["libraryLoaded"] as? Bool == true) }
        XCTAssertEqual(initial["locale"] as? String, "en_US")
        XCTAssertEqual(initial["appVersion"] as? String, "1.0.1")
        XCTAssertEqual(initial["reduceMotion"] as? Bool, false, "Native drag tilt must not be disabled by Reduce Motion")
        XCTAssertEqual(initial["eventCount"] as? Int, 0, "Use fresh persistent app data, not another capture's decisions")
        XCTAssertEqual(initial["basketIDs"] as? [String], [])
        XCTAssertEqual((initial["vault"] as? [String: Any])?["setUp"] as? Bool, false)
        let inventory = try XCTUnwrap(initial["inventory"] as? [[String: Any]])
        let names = inventory.compactMap { $0["filename"] as? String }
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(names.count, Set(names).count, "Do not import duplicate fixture filenames")
        XCTAssertTrue(names.allSatisfy { $0.hasPrefix("CA_") || $0 == "concept-a-native-library.png" }, "No default or legacy archive photos")
        for filename in ["CA_01_clutter_blur.jpg", "CA_02_clutter_shake.jpg", "CA_03_clutter_dark.jpg",
                         "CA_10_duplicate_a.jpg", "CA_11_duplicate_b.jpg"]
            + (1...6).map({ String(format: "CA_20_series_%02d.jpg", $0) })
            + (1...24).map({ String(format: "CA_30_pretty_%02d.jpg", $0) }) {
            let asset = try conceptAAsset(filename, in: initial)
            XCTAssertEqual(asset["isVideo"] as? Bool, false)
            XCTAssertGreaterThan(asset["pixelWidth"] as? Int ?? 0, 0)
        }
        let nativeScreenshot = try conceptAAsset("concept-a-native-library.png", in: initial)
        XCTAssertEqual(nativeScreenshot["pixelWidth"] as? Int, 1206)
        XCTAssertEqual(nativeScreenshot["pixelHeight"] as? Int, 2622)
        // simctl may import a genuine OS screenshot as a plain photo. Record its REAL subtype; never fake it.
        XCTAssertGreaterThanOrEqual(inventory.filter { ($0["isVideo"] as? Bool == true) && ($0["filename"] as? String ?? "").hasPrefix("CA_40_large_") }.count, 2)
        let logo = try XCTUnwrap(initial["logo"] as? [String: Any])
        XCTAssertEqual(logo["exported"] as? Bool, true)
        XCTAssertEqual(logo["component"] as? String, "VaultDialWordmark")
        XCTAssertEqual(logo["dialComponent"] as? String, "CombinationDial")
        try conceptAAssertPNG(output.appendingPathComponent("screenshots/concept-a-logo.png"), screen: false)
        shots.append(["file": "concept-a-logo.png", "language": language, "appearance": "dark", "status": "PASS", "kind": "native-component"])

        launch("concept-a-feed"); awaitStage()
        let feedState = try conceptAObserve("feed-selected-originals")
        let feedSelection = try XCTUnwrap(feedState["selection"] as? [String: Any])
        XCTAssertEqual(feedSelection["sourceFiles"] as? [String], ["CA_01_clutter_blur.jpg", "concept-a-native-library.png",
                                                               "CA_30_pretty_06.jpg", "CA_30_pretty_07.jpg", "CA_30_pretty_08.jpg"])
        try conceptARequireStage(try conceptAAsset("CA_01_clutter_blur.jpg", in: initial))
        try requestStill("warmup-concept-a", delay: 0, warmup: true); try awaitStill("warmup-concept-a")
        let heldAt = Date().timeIntervalSince1970
        // A real left drag supplies FeedMediaTransform's native offset.width / 40 rotation. No baked photo rotation.
        try holdSwipe("left", still: "concept-a-swipe", offset: CGVector(dx: -150, dy: -20), holdDuration: 25)
        let held = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("stills/concept-a-swipe.json"))) as? [String: Any])
        XCTAssertGreaterThanOrEqual(held["requested"] as? Double ?? 0, heldAt)
        XCTAssertLessThan(held["finished"] as? Double ?? .infinity, heldAt + 24, "Recorder must finish while the finger is still down")
        try conceptARequireStage(nativeScreenshot)
        swipeFeed("left") // Second real Trash decision, on the actual imported native screenshot.
        try conceptARequireStage(try conceptAAsset("CA_30_pretty_06.jpg", in: initial))
        let beforeLater = feedPosition()
        let feedBounds = app.frame
        e("feed.stage").swipeRight()
        let pill = e("later.pill")
        XCTAssertTrue(pill.waitForExistence(timeout: 2))
        let pillReadyDeadline = Date().addingTimeInterval(1)
        while (!feedBounds.contains(pill.frame) || !pill.isHittable), Date() < pillReadyDeadline { pause(0.05) }
        let pillFrame = pill.frame
        let pillLabel = pill.label
        XCTAssertTrue(feedBounds.contains(pillFrame) && pill.isHittable, "Require the actual pill onscreen, not just an offscreen accessibility node")
        // Capture BEFORE the slower full-tree/translation queries in snap(). Never extend the real four-second pill.
        let laterScreenshot = XCUIScreen.main.screenshot()
        try laterScreenshot.pngRepresentation.write(to: output.appendingPathComponent("stills/concept-a-later-timing.png"), options: .atomic)
        XCTAssertTrue(pillLabel.contains(String(format: t("later_in_days_again#other"), Int64(2))))
        // SwiftUI's combined element exposes the date as its label and the edit
        // action separately, so that label does not include the visible Button text.
        // Prove Change from the actual native pixels instead of altering production AX.
        let laterImage = try XCTUnwrap(laterScreenshot.image.cgImage)
        let nativeScale = CGFloat(laterImage.width) / feedBounds.width
        let pillPixels = CGRect(x: (pillFrame.minX - feedBounds.minX) * nativeScale,
                                y: (pillFrame.minY - feedBounds.minY) * nativeScale,
                                width: pillFrame.width * nativeScale, height: pillFrame.height * nativeScale).integral
        let pillImage = try XCTUnwrap(laterImage.cropping(to: pillPixels))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: pillImage, options: [:]).perform([request])
        let visiblePillText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        try visiblePillText.write(to: output.appendingPathComponent("concept-a-later-visible-text.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(visiblePillText.localizedCaseInsensitiveContains(t("change")), "Actual native pill pixels must show Change: \(visiblePillText)")
        XCTAssertEqual(feedPosition(), beforeLater + 1, "The actual right-swipe decision must advance")
        snap("concept-a-later", settle: 0, captured: laterScreenshot)
        try conceptARequireStage(try conceptAAsset("CA_30_pretty_07.jpg", in: initial))
        swipeFeed("up")
        let trashIDs = Set(try ["CA_01_clutter_blur.jpg", "concept-a-native-library.png"].map { try conceptAID($0, in: initial) })
        let decisions = try conceptAWait("actual-swipe-decisions") { Set($0["basketIDs"] as? [String] ?? []) == trashIDs }
        let rows = try XCTUnwrap(decisions["decisions"] as? [[String: Any]])
        let laterID = try conceptAID("CA_30_pretty_06.jpg", in: initial)
        let later = try XCTUnwrap(rows.first { $0["id"] as? String == laterID })
        XCTAssertEqual(later["disposition"] as? String, "later")
        XCTAssertEqual(later["dueDay"] as? String, decisions["twoDaysDueDay"] as? String)
        let keepID = try conceptAID("CA_30_pretty_07.jpg", in: initial)
        XCTAssertEqual(rows.first { $0["id"] as? String == keepID }?["disposition"] as? String, "kept")

        try captureConceptATrash(trashIDs: trashIDs)
        try captureConceptAScans(initial: initial)
        try captureConceptAMonthsAndSeries(initial: initial, trashIDs: trashIDs)
        try captureConceptACreativeTools(initial: initial)
        captureConceptAGames()
        try captureConceptAVault(initial: initial)
        let expected = ["concept-a-swipe", "concept-a-duplicates", "concept-a-large-files", "concept-a-trash",
                        "concept-a-delete-confirm", "concept-a-vault", "concept-a-vault-locked", "concept-a-later",
                        "concept-a-months", "concept-a-analysis", "concept-a-collage", "concept-a-editor", "concept-a-games"]
        for name in expected { try conceptAAssertPNG(output.appendingPathComponent("screenshots/\(name).png")) }
        XCTAssertEqual(Set(shots.map { $0["file"] ?? "" }), Set((expected + ["concept-a-logo"]).map { $0 + ".png" }))
    }

    private func conceptASystemDeleteAlert(expectedCount: Int) throws -> XCUIElement {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 120), "Require the real iOS PhotoKit confirmation, not the app's own dialog")
        let description = alert.debugDescription.lowercased()
        XCTAssertTrue(description.contains("galeriq") && description.contains("delete"))
        XCTAssertNotNil(description.range(of: "\\b\(expectedCount)\\b", options: .regularExpression))
        XCTAssertTrue(alert.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Delete'")).firstMatch.exists)
        return alert
    }

    private func captureConceptATrash(trashIDs: Set<String>) throws {
        launch("concept-a-trash")
        let state = try conceptAWait("trash-measured") { state in
            let measurements = state["measurements"] as? [[String: Any]] ?? []
            return trashIDs.allSatisfy { id in measurements.contains { $0["id"] as? String == id && $0["state"] as? String == "known" } }
        }
        XCTAssertEqual(Set(state["basketIDs"] as? [String] ?? []), trashIDs)
        XCTAssertEqual(trashIDs.count, 2)
        conceptARequireVisible(conceptAText(String(format: t("basket_count"), Int64(2))), "Actual two-item trash count")
        // The shipped English catalog says 'Remove 2 photos and videos', not the brief's shortened 'Remove 2 photos'.
        // Capture that actual text; never inject a marketing label into the app.
        let removeTitle = String(format: t("basket_empty_media#other"), Int64(2))
        conceptARequireVisible(app.buttons[removeTitle].firstMatch, "Actual Remove 2 photos and videos control")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", t("basket_preview_open").components(separatedBy: "%").first!)).count, 2)
        snap("concept-a-trash")
        tap(app.buttons[removeTitle].firstMatch)
        let confirm = String(format: t("basket_confirm_media_action"), Int64(2))
        tap(app.buttons[confirm].firstMatch) // App confirmation first; the following one must belong to SpringBoard.
        let alert = try conceptASystemDeleteAlert(expectedCount: 2)
        snap("concept-a-delete-confirm")
        try XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription
            .write(to: output.appendingPathComponent("screenshots/concept-a-delete-confirm-system.txt"), atomically: true, encoding: .utf8)
        let cancel = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Don't Allow", "Don’t Allow", "Don't Delete", "Don’t Delete", "Cancel"] as NSArray)).firstMatch
        XCTAssertTrue(cancel.exists, "Only Cancel/Don't Delete is permitted for the trash capture")
        pause(0.5); cancel.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.alerts.staticTexts[t("result_cancelled")].firstMatch.waitForExistence(timeout: 30))
        tap(app.alerts.buttons[t("ok")].firstMatch)
        let after = try conceptAObserve("trash-system-cancelled")
        XCTAssertEqual(Set(after["basketIDs"] as? [String] ?? []), trashIDs)
        let liveIDs = Set((after["inventory"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        XCTAssertTrue(trashIDs.isSubset(of: liveIDs), "Cancel must preserve both actual PhotoKit originals")
        conceptARequireVisible(app.buttons[removeTitle].firstMatch, "Both decisions still await explicit deletion")
    }

    private func captureConceptAScans(initial: [String: Any]) throws {
        launch("concept-a-duplicates")
        XCTAssertTrue(app.navigationBars[t("duplicates")].exists)
        tap(button("dup_start")) // Real DuplicateScanner/PhotoResource reads, launched by the production control.
        let state = try conceptAWait("duplicate-scan-finished", timeout: 300) {
            let scan = $0["duplicates"] as? [String: Any] ?? [:]
            return scan["failed"] as? Bool == true || (scan["hasResult"] as? Bool == true && scan["running"] as? Bool == false)
        }
        let scan = try XCTUnwrap(state["duplicates"] as? [String: Any])
        XCTAssertEqual(scan["failed"] as? Bool, false)
        XCTAssertEqual(scan["complete"] as? Bool, true, "No incomplete or empty scan can support found duplicates")
        XCTAssertEqual(scan["unchecked"] as? Int, 0)
        let groups = try XCTUnwrap(scan["groups"] as? [[String: Any]])
        // The fixture has exactly one intentionally byte-identical pair; no additional copied pretty photos.
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        let expectedIDs = Set(try ["CA_10_duplicate_a.jpg", "CA_11_duplicate_b.jpg"].map { try conceptAID($0, in: initial) })
        XCTAssertEqual(Set(group["assetIDs"] as? [String] ?? []), expectedIDs)
        XCTAssertGreaterThan((group["sizeEach"] as? NSNumber)?.int64Value ?? 0, 0)
        XCTAssertEqual((group["sha256"] as? String)?.count, 64)
        XCTAssertFalse(e("duplicates.progress").exists)
        XCTAssertTrue(button("dup_again").exists)
        let header = conceptAText(try XCTUnwrap(scan["header"] as? String))
        let footer = conceptAText(try XCTUnwrap(scan["footer"] as? String))
        let keep = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", t("dup_will_keep"))).firstMatch
        let trash = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", t("dup_selected_trash"))).firstMatch
        for _ in 0..<5 {
            if [header, footer, keep, trash].allSatisfy(conceptAFullyVisible) { break }
            app.swipeUp(); pause(0.3)
        }
        for element in [header, footer, keep, trash] { conceptARequireVisible(element, "Both real duplicate images and their measured-size summary") }
        snap("concept-a-duplicates")

        launch("concept-a-large-files")
        XCTAssertTrue(app.navigationBars[t("large_files")].exists)
        let inventory = try XCTUnwrap(initial["inventory"] as? [[String: Any]])
        let videoIDs = Set(inventory.filter { ($0["filename"] as? String ?? "").hasPrefix("CA_40_large_") }.compactMap { $0["id"] as? String })
        let large = try conceptAWait("large-files-measured", timeout: 300) { state in
            let rows = state["largeFiles"] as? [[String: Any]] ?? []
            return state["largeMeasuring"] as? Bool == false && videoIDs.isSubset(of: Set(rows.compactMap { $0["id"] as? String }))
        }
        XCTAssertEqual(large["largeThresholdMB"] as? Int, 100)
        let rows = try XCTUnwrap(large["largeFiles"] as? [[String: Any]])
        for row in rows where videoIDs.contains(row["id"] as? String ?? "") {
            XCTAssertEqual(row["isVideo"] as? Bool, true)
            XCTAssertGreaterThan((row["bytes"] as? NSNumber)?.int64Value ?? 0, 100_000_000, "Require measured >100 MB, never an estimate")
            let description = try XCTUnwrap(row["accessibilityValue"] as? String)
            let size = try XCTUnwrap(row["sizeText"] as? String)
            let result = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", description, size)).firstMatch
            conceptARequireVisible(result, "Measured large video and actual displayed size")
        }
        XCTAssertFalse(conceptAText(t("large_none")).exists)
        snap("concept-a-large-files")
    }

    private func captureConceptAMonthsAndSeries(initial: [String: Any], trashIDs: Set<String>) throws {
        launch("concept-a-months")
        let done = button("tour_done")
        if done.waitForExistence(timeout: 5) { tap(done) }
        XCTAssertFalse(done.exists)
        let state = try conceptAObserve("months-tour-dismissed")
        XCTAssertEqual(state["monthsTourSeen"] as? Bool, true)
        let months = try XCTUnwrap(state["months"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(months.count, 12, "Twenty-four real pretty photos must fill twelve real month groups")
        XCTAssertTrue(months.allSatisfy { ($0["total"] as? Int ?? 0) >= 2 })
        let titles = try months.map { try XCTUnwrap($0["title"] as? String) }
        var visibleMonths = 0
        for attempt in 0..<7 {
            let listState = try conceptAObserve("months-native-viewport-\(attempt)")
            let box = try XCTUnwrap(listState["nativeListViewport"] as? [String: Double])
            var viewport = CGRect(x: try XCTUnwrap(box["x"]), y: try XCTUnwrap(box["y"]),
                                  width: try XCTUnwrap(box["width"]), height: try XCTUnwrap(box["height"]))
            XCTAssertFalse(viewport.isEmpty)
            // Exclude a genuinely pinned year header as well as native adjusted insets.
            for header in app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]{4}$'")).allElementsBoundByIndex {
                let frame = header.frame
                if frame.minY <= viewport.minY + 1, frame.maxY > viewport.minY {
                    let bottom = viewport.maxY
                    viewport.origin.y = frame.maxY
                    viewport.size.height = max(0, bottom - frame.maxY)
                }
            }
            visibleMonths = 0
            for title in titles {
                let cell = app.cells.containing(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
                guard cell.exists, !cell.frame.isEmpty, viewport.contains(cell.frame) else { continue }
                let menu = cell.buttons[String(format: t("month_actions"), title)].firstMatch
                if menu.exists, viewport.contains(menu.frame) { visibleMonths += 1 }
            }
            if visibleMonths >= 6 { break }
            // Actual bounded scrolling; never shrink rows or inject month entries.
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.70)).press(forDuration: 0.05,
                thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.56)))
            pause(0.3)
        }
        XCTAssertGreaterThanOrEqual(visibleMonths, 6, "The phone must show a filled list, not one or two rows above empty space")
        snap("concept-a-months")

        launch("concept-a-analysis")
        let before = try conceptAObserve("real-series-groups")
        let seriesIDs = Set(try (1...6).map { try conceptAID(String(format: "CA_20_series_%02d.jpg", $0), in: initial) })
        let groups = try XCTUnwrap(before["series"] as? [[String]])
        XCTAssertTrue(groups.contains { Set($0) == seriesIDs }, "The production PhotoSeries rules must really find all six imported photos")
        let subtitle = String(format: t("series_subtitle"), Int64(6))
        let series = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", subtitle)).firstMatch
        tap(series)
        XCTAssertTrue(app.navigationBars[t("series_title")].waitForExistence(timeout: 20))
        conceptARequireVisible(conceptAText(subtitle), "Actual six-photo chronological comparison")
        let toggles = app.buttons.matching(NSPredicate(format: "label == %@", t("series_keep_toggle")))
        XCTAssertEqual(toggles.count, 6)
        tap(toggles.element(boundBy: 0)) // A real in-sheet selection, NOT a committed ledger decision.
        XCTAssertEqual(toggles.element(boundBy: 0).value as? String, t("series_state_trash"))
        conceptARequireVisible(app.buttons[String(format: t("series_confirm"), Int64(5), Int64(1))].firstMatch, "Actual Keep 5 / Trash 1 comparison choice")
        _ = try conceptAWait("series-large-preview-loaded", timeout: 60) { state in
            let preview = state["seriesPreview"] as? [String: Any] ?? [:]
            return preview["imageReady"] as? Bool == true && seriesIDs.contains(preview["assetID"] as? String ?? "")
        }
        snap("concept-a-analysis")
        tap(button("cancel")) // Do not add a third Trash decision.
        let after = try conceptAObserve("series-cancelled-no-extra-decisions")
        XCTAssertEqual(Set(after["basketIDs"] as? [String] ?? []), trashIDs)
        XCTAssertEqual(after["eventCount"] as? Int, before["eventCount"] as? Int)
    }

    private func captureConceptACreativeTools(initial: [String: Any]) throws {
        launch("concept-a-collage")
        let selected = try XCTUnwrap(try conceptAObserve("collage-real-sources")["selection"] as? [String: Any])
        XCTAssertEqual(selected["assetIDs"] as? [String], try (1...4).map { try conceptAID(String(format: "CA_30_pretty_%02d.jpg", $0), in: initial) })
        let save = button("save")
        XCTAssertTrue(save.waitForExistence(timeout: 45))
        let deadline = Date().addingTimeInterval(60)
        while !save.isEnabled, Date() < deadline { pause(0.2) }
        XCTAssertTrue(save.isEnabled, "The normal collage loading attempts must finish")
        let expectedCollageIDs = Set(try (1...4).map { try conceptAID(String(format: "CA_30_pretty_%02d.jpg", $0), in: initial) })
        _ = try conceptAWait("collage-four-originals-loaded", timeout: 60) { state in
            let source = state["collageSources"] as? [String: Any] ?? [:]
            return Set(source["projectIDs"] as? [String] ?? []) == expectedCollageIDs
                && expectedCollageIDs.isSubset(of: Set(source["loadedIDs"] as? [String] ?? []))
                && source["missingIDs"] as? [String] == []
        }
        conceptARequireVisible(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", t("col_stage"))).firstMatch, "Real four-photo collage canvas")
        for index in 1...4 {
            conceptARequireVisible(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", String(format: t("collage_photo_n"), Int64(index)))).firstMatch, "Each imported photo's native collage placement")
        }
        XCTAssertFalse(conceptAText(t("col_missing")).exists)
        snap("concept-a-collage")

        launch("concept-a-editor")
        XCTAssertTrue(e("editor.stage").waitForExistence(timeout: 45))
        editorTool("filter")
        let warm = button("edit_filter_warm")
        tap(warm)
        XCTAssertTrue(warm.isSelected, "Select the actual native Warm filter")
        waitForEditorPreview()
        XCTAssertTrue(e("editor.undo").isEnabled, "The real filter edit must be undoable")
        let editor = try XCTUnwrap(try conceptAObserve("editor-original-selected")["selection"] as? [String: Any])
        XCTAssertEqual(editor["assetIDs"] as? [String], [try conceptAID("CA_30_pretty_08.jpg", in: initial)])
        snap("concept-a-editor")
    }

    private func captureConceptAGames() {
        launch("today")
        tap(e("today.games"))
        let cards = [e("games.memory"), e("games.snake"), e("games.blocks")]
        XCTAssertTrue(cards[2].waitForExistence(timeout: 20))
        for _ in 0..<4 {
            if cards.allSatisfy(conceptAFullyVisible) { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.68)))
        }
        for (index, card) in cards.enumerated() {
            conceptARequireVisible(card, "Complete native game card \(index + 1), including Foto Blocks")
        }
        snap("concept-a-games")
        tap(e("games.close"))
    }

    private func captureConceptAVault(initial: [String: Any]) throws {
        launch("concept-a-vault")
        XCTAssertTrue(button("onb_next").waitForExistence(timeout: 20), "Fresh vault must be set up through its actual UI")
        tap(button("onb_next"))
        let fields = app.secureTextFields
        XCTAssertEqual(fields.count, 2)
        fields.element(boundBy: 0).tap(); fields.element(boundBy: 0).typeText("628491")
        fields.element(boundBy: 1).tap(); fields.element(boundBy: 1).typeText("628491")
        tap(button("onb_next"))
        let face = app.switches.matching(NSPredicate(format: "label CONTAINS 'Face ID'")).firstMatch
        if face.exists {
            // Own-code native capture, not a claim that simulator Face ID was security-tested.
            if face.value as? String == "1" { face.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
            tap(button("onb_next"))
        }
        // No screenshot, log or fixture exports a recovery key. Skip it via the real setup choice.
        tap(button("vault_recovery_skip"))
        tap(app.alerts.buttons[t("vault_recovery_skip")].firstMatch)
        let hidden = app.switches[t("vault_hide_entry")]
        if hidden.value as? String == "1" { hidden.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        tap(button("vault_setup_finish"))
        XCTAssertTrue(app.segmentedControls.buttons[t("vault2_media")].waitForExistence(timeout: 45))
        XCTAssertEqual(vaultItems().count, 0, "Never reuse another run's private media")
        tap(button("vault_add"))
        let filenames = (1...5).map { String(format: "CA_30_pretty_%02d.jpg", $0) }
        let originalIDs = Set(try filenames.map { try conceptAID($0, in: initial) })
        for filename in filenames {
            let source = try conceptAAsset(filename, in: initial)
            let description = try XCTUnwrap(source["accessibilityValue"] as? String)
            // The production picker deliberately exposes a date/type label, not filenames. Metadata dates are unique.
            let cell = app.buttons.matching(NSPredicate(format: "identifier == 'picker.media' AND label == %@", description)).firstMatch
            if !cell.waitForExistence(timeout: 5) {
                for _ in 0..<10 where !cell.exists { app.swipeUp() }
                for _ in 0..<10 where !cell.exists { app.swipeDown() }
            }
            tap(cell)
            XCTAssertTrue(cell.isSelected, "Actually select the imported pretty original: \(filename)")
        }
        tap(button("done"))
        tap(app.alerts.buttons[t("vault_import_action")].firstMatch)
        let system = try conceptASystemDeleteAlert(expectedCount: filenames.count)
        let delete = system.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Delete'")).firstMatch
        XCTAssertTrue(delete.isHittable)
        pause(0.5); delete.tap() // Explicitly authorized ONLY for this disposable simulator's five imported originals.
        XCTAssertTrue(system.waitForNonExistence(timeout: 30))
        let notice = app.alerts.buttons[t("ok")].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 120), "Require the actual completed import report")
        tap(notice)
        let moved = try conceptAWait("vault-real-import-and-original-removal", timeout: 120) { state in
            let vault = state["vault"] as? [String: Any] ?? [:]
            let items = vault["items"] as? [[String: Any]] ?? []
            let liveIDs = Set((state["inventory"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
            return vault["importing"] as? Bool == false && vault["stillInPhotos"] as? Int == 0
                && items.count == filenames.count && items.allSatisfy { $0["thumbnailReady"] as? Bool == true }
                && liveIDs.isDisjoint(with: originalIDs)
        }
        let vault = try XCTUnwrap(moved["vault"] as? [String: Any])
        let items = try XCTUnwrap(vault["items"] as? [[String: Any]])
        XCTAssertEqual(vault["unlocked"] as? Bool, true)
        XCTAssertEqual(Set(items.compactMap { $0["originalID"] as? String }), originalIDs)
        XCTAssertEqual(Set(items.flatMap { $0["sourceFiles"] as? [String] ?? [] }), Set(filenames))
        XCTAssertTrue(items.allSatisfy { (($0["measuredBytes"] as? NSNumber)?.int64Value ?? 0) > 0 && $0["sourceID"] as? String == "" })
        let initialCount = try XCTUnwrap(initial["inventory"] as? [[String: Any]]).count
        XCTAssertEqual((moved["inventory"] as? [[String: Any]])?.count, initialCount - filenames.count)
        XCTAssertEqual(vaultItems().count, filenames.count)
        for cell in vaultItems().allElementsBoundByIndex { conceptARequireVisible(cell, "Genuine loaded vault media") }
        XCTAssertTrue(button("vault_still_in_photos_action").waitForNonExistence(timeout: 20), "Never crop away the original-still-in-Photos warning")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        snap("concept-a-vault")
        tap(button("vault_close"))
        launch("concept-a-vault")
        XCTAssertTrue(app.vaultKeypad.waitForExistence(timeout: 20))
        conceptARequireVisible(e("vault.pin.dots"), "Real native own-code lock screen")
        for digit in 0...9 { conceptARequireVisible(e("vault.key.\(digit)"), "Complete native keypad") }
        XCTAssertFalse(vaultItems().firstMatch.exists)
        snap("concept-a-vault-locked")
        tap(button("vault_close"))
    }

    private func openStoreGame(_ game: String) {
        launch("feed"); awaitStage()
        tap(e("feed.memory"))
        XCTAssertTrue(e("games.memory").waitForExistence(timeout: 10))
        snap("games-selection")
        tap(e("games." + game))
    }

    /// Read a card only AFTER a real tap revealed it; no hidden deck or result is injected.
    private func photoNumber(_ card: XCUIElement) -> String {
        let value = card.value as? String ?? ""
        return value.split(whereSeparator: { !$0.isNumber }).last?.compactMap(\.wholeNumberValue).map(String.init).joined() ?? ""
    }

    private func prepareMemoryForStore() throws {
        openStoreGame("memory")
        snap("memory-setup")
        tap(e("memory.startPhotos"))
        XCTAssertTrue(e("memory.card.0").waitForExistence(timeout: 45))
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'"))
        XCTAssertEqual(cards.count, 24, "The actual library round must have twelve photo pairs")
        let unseen = cards.allElementsBoundByIndex.map(\.identifier)
        var known: [String: [String]] = [:]
        var solved: Set<String> = []
        for cardID in unseen {
            if solved.count >= 6 { break }
            if solved.contains(cardID) { continue }
            let card = app.buttons[cardID]
            if card.isEnabled { card.tap() }
            var number = photoNumber(card)
            if number.isEmpty {
                // XCTest can return after the ordinary 1.2s mismatch timer. Reveal
                // that same card again through the UI; never inspect a hidden face.
                pause(1.4)
                card.tap()
                number = photoNumber(card)
            }
            XCTAssertFalse(number.isEmpty, "Only a genuinely revealed photo can identify a pair")
            if known[number]?.contains(cardID) != true { known[number, default: []].append(cardID) }
            if let pair = known[number], pair.count == 2 {
                let first = app.buttons[pair[0]], second = app.buttons[pair[1]]
                if first.isEnabled { first.tap() }
                if second.isEnabled { second.tap() }
                XCTAssertTrue((first.value as? String ?? "").hasPrefix(t("memory_matched")))
                XCTAssertTrue((second.value as? String ?? "").hasPrefix(t("memory_matched")))
                solved.formUnion(pair)
                known.removeValue(forKey: number)
            } else {
                // A normal user can let the timer finish or tap the next card to
                // advance a mismatch. A vanished optional flip button is not a failure.
                pause(1.4)
            }
        }
        XCTAssertGreaterThanOrEqual(solved.count, 6, "Store images must show pairs actually found in this round")
        XCTAssertFalse(e("memory.finished").exists, "No unearned victory or best time is presented")
    }

    private func prepareSnakeForStore() {
        openStoreGame("snake")
        func selected(_ identifier: String, _ key: String) -> Bool {
            let control = e(identifier)
            return (control.label + " " + (control.value as? String ?? "")).contains(t(key))
        }
        if !selected("snake.source", "memory_source_library") {
            tap(e("snake.source")); tap(button("memory_source_library"))
        }
        if !e("snake.speed").exists { tap(e("snake.options")) }
        if !selected("snake.speed", "snake_gentle") {
            tap(e("snake.speed")); tap(button("snake_gentle"))
        }
        snap("snake-setup")
        tap(e("snake.prepare"))
        let board = e("snake.board")
        XCTAssertTrue(board.waitForExistence(timeout: 45))
        XCTAssertGreaterThanOrEqual(board.frame.width, app.frame.width - 12)
        XCTAssertGreaterThan(board.frame.height, app.frame.height * 0.72)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'snake.direction.'")).count, 0)
        XCTAssertFalse(app.launchArguments.contains("-snake-swipe-steps"))
        snap("snake-ready")
    }

    /// Two separate, genuine recordings let the final game preview retain real-time gameplay.
    func test40AppPreviewPhotoGames() throws {
        try prepareMemoryForStore()
        try recording("start", name: "04-memory")
        try mark("memory-pairs")
        let hidden = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.' AND enabled == true"))
        if hidden.count >= 2 {
            let first = hidden.element(boundBy: 0); first.tap()
            try mark("memory-reveal")
            let second = hidden.allElementsBoundByIndex.first(where: { $0.identifier != first.identifier })
            try XCTUnwrap(second).tap()
            try mark("memory-second")
        }
        pause(8)
        try recording("stop", name: "04-memory")
        tap(e("memory.close"))
        prepareSnakeForStore()
        let board = e("snake.board")
        board.swipeRight(); pause(1)
        let before = board.value as? String
        pause(0.8)
        XCTAssertNotEqual(board.value as? String, before, "Snake must move on its real clock")
        try recording("start", name: "05-snake")
        try mark("snake-right"); pause(3)
        board.swipeUp(); try mark("snake-up"); pause(3)
        board.swipeLeft(); try mark("snake-left"); pause(3)
        board.swipeDown(); try mark("snake-down"); pause(4)
        try recording("stop", name: "05-snake")
        tap(e("snake.play").buttons["snake.close"])
        XCTAssertTrue(e("feed.stage").waitForExistence(timeout: 10))
    }

    func test10AppPreviewReview() throws {
        launch("feed"); awaitStage()
        try recording("start",name:"01-review")
        // Jede Entscheidung einmal klar sichtbar: langsam ziehen, Pille „Keep“ / „Trash“ / „Later“ halten, loslassen.
        try mark("feed"); pause(1.5)
        try holdSwipe("up"); try mark("keep"); pause(1)
        try holdSwipe("left"); try mark("trash"); pause(1)
        try holdSwipe("right"); pause(0.5); try mark("later"); pause(2)
        swipeFeed("down"); pause(0.8); try mark("back"); pause(2.5)
        try recording("stop",name:"01-review")
    }
    func test20AppPreviewStudio() throws {
        launch("editor")
        XCTAssertTrue(e("editor.stage").waitForExistence(timeout:30)); pause(2)
        try recording("start",name:"02-studio")
        try mark("editor"); pause(3)
        editorTool("adjust")
        let exposure = app.otherElements.matching(NSPredicate(format:"label == %@",t("edit_adj_exposure"))).firstMatch
        XCTAssertTrue(exposure.waitForExistence(timeout:10))
        let originalExposure = exposure.value as? String
        exposure.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.75)).press(forDuration:0.1,
            thenDragTo:exposure.coordinate(withNormalizedOffset:CGVector(dx:0.58,dy:0.75)))
        waitForEditorPreview()
        XCTAssertNotEqual(exposure.value as? String,originalExposure,"Exposure must actually change")
        try mark("adjust"); pause(3)
        editorTool("filter")
        let mono = button("edit_filter_mono")
        tap(mono)
        XCTAssertTrue(mono.isSelected,"Mono filter must actually be selected")
        waitForEditorPreview()
        try mark("filter"); pause(3)
        editorTool("markup")
        tap(button("edit_mk_draw"))
        let stage=e("editor.stage")
        stage.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.77)).press(forDuration:0.1,thenDragTo:stage.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.7)))
        waitForEditorPreview()
        try mark("markup"); pause(3)
        editorTool("frame"); try mark("frame"); pause(4)
        try recording("stop",name:"02-studio")
    }
    func test30AppPreviewVault() throws {
        openVault()
        XCTAssertEqual(vaultItems().count,5)
        try recording("start",name:"03-vault")
        try mark("vault"); pause(3)
        tap(vaultItems().firstMatch); try mark("viewer"); pause(3)
        let photo=e("vault.viewer.photo")
        XCTAssertTrue(photo.waitForExistence(timeout:10))
        photo.tap()
        XCTAssertTrue(app.buttons["vault.viewer.close"].waitForNonExistence(timeout:5),"Viewer controls must hide")
        try mark("hidden-controls"); pause(3)
        photo.doubleTap(); pause(0.5)
        let zoom = (photo.value as? String ?? "").compactMap(\.wholeNumberValue).reduce(0) { $0 * 10 + $1 }
        XCTAssertGreaterThan(zoom,150,"Vault photo must actually zoom")
        try mark("zoom"); pause(3)
        photo.doubleTap(); pause(0.5)
        let restoredZoom = (photo.value as? String ?? "").compactMap(\.wholeNumberValue).reduce(0) { $0 * 10 + $1 }
        XCTAssertEqual(restoredZoom,100,"Vault photo must return to its complete frame")
        photo.tap()
        XCTAssertTrue(app.buttons["vault.viewer.close"].waitForExistence(timeout:5),"Viewer controls must return")
        try mark("controls"); pause(4)
        try recording("stop",name:"03-vault")
    }
}
