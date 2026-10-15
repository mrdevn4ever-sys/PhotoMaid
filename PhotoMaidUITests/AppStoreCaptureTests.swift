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
        if name.contains("test00") { store.resetToDefaultState(); try store.clearTransactions() }
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
        let query = app.buttons.matching(NSPredicate(format:"label == %@", t(key)))
        return query.allElementsBoundByAccessibilityElement.first(where: \.isHittable) ?? query.firstMatch
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
        XCTAssertTrue(app.windows["store.capture." + page].waitForExistence(timeout: 40), "Requested page must finish opening: \(page)")
        if page != "introduction" {
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App did not open capture page \(page)")
        }
        pause(1.4)
    }
    private func snap(_ name: String) {
        if name.hasPrefix("editor") { waitForEditorPreview() }
        pause(0.7)
        let banner = XCUIApplication(bundleIdentifier:"com.apple.springboard").otherElements["NotificationShortLookView"].firstMatch
        if banner.exists { XCTAssertTrue(banner.waitForNonExistence(timeout:12),"System banner must leave before capture") }
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
        if page == "search" {
            let deadline = Date().addingTimeInterval(45)
            while app.activityIndicators.firstMatch.exists && Date() < deadline { pause(0.2) }
            XCTAssertFalse(app.activityIndicators.firstMatch.exists,"Filename indexing must finish")
        }
        snap(page)
        if bottom { app.swipeUp(); app.swipeUp(); snap(page + "-bottom") }
    }
    private func waitForPhotoAccess() {
        let deadline = Date().addingTimeInterval(45)
        repeat {
            resolvePrivacyPrompts(in: app, prefix:"store-photo-access", photos:true)
            if app.tabBars.firstMatch.exists { return }
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
            ("albums",nil,false),("album",nil,false),("grid",nil,false),("favorites",nil,false),("search",nil,false),("selection",nil,false),("tags",nil,false),("hidden",nil,false),
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
        tap(e("vault.note.title")); e("vault.note.title").typeText("PhotoMaid")
        tap(button("done"))
        let notes = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'vault.notes.item.'"))
        XCTAssertTrue(notes.firstMatch.waitForExistence(timeout:10)); snap("vault-notes-with-note")
        tap(notes.firstMatch); snap("vault-note-editor"); tap(button("done"))
    }

    private func openVault() {
        launch("vault")
        for _ in 0..<100 {
            if app.secureTextFields.firstMatch.exists || button("onb_next").exists { break }
            pause(0.1)
        }
        if app.secureTextFields.firstMatch.exists {
            let code = app.secureTextFields.firstMatch; code.tap(); code.typeText("628491")
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
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath:ack.path) {
                let value = try JSONSerialization.jsonObject(with:Data(contentsOf:ack)) as? [String:Any]
                XCTAssertEqual(value?["status"] as? String,"ok")
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

    func test10AppPreviewReview() throws {
        launch("feed"); awaitStage()
        try recording("start",name:"01-review")
        try mark("feed"); pause(2)
        swipeFeed("up"); pause(1); try mark("keep"); pause(2)
        swipeFeed("left"); pause(1); try mark("trash"); pause(2)
        swipeFeed("right"); pause(0.8); try mark("later"); pause(3)
        swipeFeed("down"); pause(0.8); try mark("back"); pause(4)
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
