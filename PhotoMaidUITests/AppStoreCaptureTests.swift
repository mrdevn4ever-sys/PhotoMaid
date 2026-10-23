import XCTest
import StoreKitTest

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
        store = try SKTestSession(configurationFileNamed: "PhotoMaid")
        store.disableDialogs = true
        if name.contains("test00") || name.contains("test06") { store.resetToDefaultState(); try store.clearTransactions() }
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
        app.launchArguments = ["-store-capture", "-store-page", page, "-store-navigation", output.appendingPathComponent("navigation").path, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
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
    private func snap(_ name: String) {
        if name.hasPrefix("editor") { waitForEditorPreview() }
        if name == "viewer-info" {
            XCTAssertTrue(app.staticTexts[t("lib_info_name")].firstMatch.waitForExistence(timeout:40),"Original filename must load")
            XCTAssertTrue(app.staticTexts["…"].firstMatch.waitForNonExistence(timeout:40),"Media size must finish loading")
        }
        pause(0.7)
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
        let screenshot = XCUIScreen.main.screenshot()
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
    private func holdSwipe(_ direction: String, still: String? = nil) throws {
        let before = feedPosition()
        XCTAssertGreaterThan(before, 0)
        let stage = e("feed.stage")
        let start = stage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let offset: CGVector = switch direction {
        case "up": CGVector(dx: 0, dy: -230)
        case "left": CGVector(dx: -210, dy: 0)
        case "right": CGVector(dx: 210, dy: 0)
        default: CGVector(dx: 0, dy: 230)
        }
        // Ein simctl-Screenshot braucht auf CI mehrere Sekunden (Lauf 39808617005: 5–15 s); für das Store-Bild wird
        // deshalb 8 s gehalten, im Clip 1,6 s.
        if let still { try requestStill(still, delay: 1.0) }
        start.press(forDuration: 0.12, thenDragTo: start.withOffset(offset), withVelocity: XCUIGestureVelocity(rawValue: 320),
                    thenHoldForDuration: still == nil ? 1.6 : 8)
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
        for _ in 0..<300 {
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
        tap(e("vault.note.title")); e("vault.note.title").typeText("Arrumo")
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
    private func captureVault() throws {
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
            for _ in 0..<4 {
                guard alert.exists else { break }
                let cancel = alert.buttons.matching(NSPredicate(format:"label IN %@",["Don't Allow","Don’t Allow","Don't Delete","Don’t Delete","Cancel","Nicht erlauben","Nicht löschen","Abbrechen"] as NSArray)).firstMatch
                XCTAssertTrue(cancel.waitForExistence(timeout:3),"Only decline system deletion")
                pause(0.5) // the first tap can otherwise coincide with the system alert's entrance
                cancel.tap()
                if alert.waitForNonExistence(timeout:3) { break }
            }
            XCTAssertFalse(alert.exists,"System deletion dialog must be dismissed by declining")
            let notice = app.alerts.buttons[t("ok")]
            if notice.waitForExistence(timeout:15) {
                tap(notice)
                XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout:5))
            }
        }
        XCTAssertEqual(vaultItems().count,5); snap("vault-media")
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
        capturePage("library")
        capturePage("cleanup")
        capturePage("collage")
        capturePage("studio")
        launch("editor")
        XCTAssertTrue(e("editor.stage").waitForExistence(timeout: 30))
        editorTool("filter"); snap("editor-filter")
        editorTool("markup"); snap("editor-markup")
        capturePage("movie")
        try captureVault()
        try prepareMemoryForStore()
        snap("memory-play")
        tap(e("memory.close"))
        prepareSnakeForStore()
        let board = e("snake.board")
        board.swipeRight(); pause(1.5)
        // Unter Last kann ein Wisch als Tippen ankommen und das Spiel pausieren (Lauf 39808617005) – dann wie ein
        // Mensch „Fortsetzen“ tippen und erst aufnehmen, wenn sich die Schlange wirklich bewegt.
        if app.buttons["snake.start"].exists { tap(app.buttons["snake.start"]); pause(1.5) }
        let moving = board.value as? String
        pause(0.8)
        XCTAssertNotEqual(board.value as? String, moving, "Snake must be running for the store image")
        snap("snake-play")
        tap(e("snake.play").buttons["snake.pause"]); snap("snake-pause")
        tap(e("snake.play").buttons["snake.settings"])
        snap("snake-settings"); tap(button("done"))
        tap(e("snake.play").buttons["snake.close"])
        XCTAssertTrue(e("feed.stage").waitForExistence(timeout: 10))
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
