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
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing \(element)")
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
        element.tap(); pause(0.7)
    }
    private func button(_ key: String) -> XCUIElement { app.buttons[t(key)].firstMatch }
    private func launch(_ page: String) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-store-capture", "-store-page", page, "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        if page != "introduction" {
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "App did not open capture page \(page)")
        }
        pause(1.4)
    }
    private func snap(_ name: String) {
        pause(0.7)
        let texts = app.staticTexts.allElementsBoundByIndex.filter(\.isHittable).map(\.label)
        let invalid = texts.filter { $0.contains("%1$") || $0.contains("%2$") || $0.hasPrefix("pro2_") || $0.hasPrefix("ana2_") || $0.hasPrefix("vault2_") }
        XCTAssertTrue(invalid.isEmpty, "Untranslated UI: \(invalid)")
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
        snap(page)
        if bottom { app.swipeUp(); app.swipeUp(); snap(page + "-bottom") }
    }
    private func awaitStage() {
        XCTAssertTrue(e("feed.stage").waitForExistence(timeout: 20))
        pause(1)
    }
    private func editorTool(_ tool: String) {
        let target = e("editor.tool." + tool)
        let row = e("editor.tools")
        for _ in 0..<6 where !target.isHittable { row.swipeLeft() }
        tap(target)
        XCTAssertTrue(e("editor.stage").exists)
    }

    func test00EveryPageInDarkMode() throws {
        launch("introduction")
        for index in 1...5 {
            XCTAssertTrue(e("onboarding.next").waitForExistence(timeout: 15))
            snap(String(format: "introduction-%02d", index))
            tap(e("onboarding.next"))
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 25))
        capturePage("today")
        launch("feed"); awaitStage(); snap("feed")
        e("feed.stage").swipeUp(); pause(1)
        e("feed.stage").swipeLeft(); pause(1)
        e("feed.stage").swipeRight(); pause(1); snap("feed-later")
        let pages: [(String,String?,Bool)] = [
            ("library",nil,false),("cleanup",nil,true),("studio",nil,true),("history",nil,false),
            ("trash",nil,false),("later",nil,false),("months",nil,false),
            ("large-files","large_files",false),("duplicates","duplicates",false),("storage","storage_overview",true),
            ("files","files",false),("series","series_title",false),("collections",nil,true),
            ("blurry","ana_blurry",false),("similar","ana_similar",false),("documents","ana_documents",false),("categories","ana_categories",false),
            ("albums",nil,false),("favorites",nil,false),("search",nil,false),("selection",nil,false),("tags",nil,false),("hidden",nil,false),
            ("edits",nil,false),("collage",nil,false),("movie",nil,true),
            ("tools-resize",nil,true),("tools-convert",nil,true),("tools-removeLocation",nil,true),("tools-stitch",nil,true),("tools-gif",nil,true),("tools-batchEdit",nil,true),
            ("workflows",nil,true),("pdf",nil,true),("pdf-studio",nil,false),("archive",nil,true),
            ("settings","settings",true),("pro","pro_title",true),("privacy","privacy_title",true),("help","help",true),
            ("excluded-albums",nil,false),("backup","backup_title",true),("controls","fc_title",true),
            ("viewer",nil,false),("slideshow",nil,false)
        ]
        for (page,title,bottom) in pages { capturePage(page, title:title, bottom:bottom) }
        launch("editor")
        XCTAssertTrue(e("editor.stage").waitForExistence(timeout: 30))
        snap("editor")
        for tool in ["crop","adjust","filter","retouch","markup","frame","resize"] {
            editorTool(tool); snap("editor-" + tool)
        }
        try captureVault()
    }

    private func openVault() {
        launch("vault")
        if app.secureTextFields.firstMatch.waitForExistence(timeout: 2) {
            let code = app.secureTextFields.firstMatch; code.tap(); code.typeText("628491")
        } else {
            snap("vault-setup-introduction"); tap(button("onb_next"))
            let fields = app.secureTextFields
            XCTAssertEqual(fields.count,2)
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
            let cancel = alert.buttons.matching(NSPredicate(format:"label IN %@",["Don't Allow","Don’t Allow","Don't Delete","Don’t Delete","Cancel","Nicht erlauben","Nicht löschen","Abbrechen"] as NSArray)).firstMatch
            XCTAssertTrue(cancel.exists,"Only decline system deletion")
            cancel.tap()
            if app.alerts.buttons[t("ok")].waitForExistence(timeout:15) { tap(app.alerts.buttons[t("ok")]) }
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
        let entry:[String:Any] = ["clip":try XCTUnwrap(clip),"label":label,"time":Date().timeIntervalSince1970]
        let path=output.appendingPathComponent("markers.jsonl")
        var data=(try? Data(contentsOf:path)) ?? Data()
        data.append(try JSONSerialization.data(withJSONObject:entry));data.append(10)
        try data.write(to:path,options:.atomic)
    }

    func test10AppPreviewReview() throws {
        launch("feed"); awaitStage()
        try recording("start",name:"01-review")
        try mark("feed"); pause(2)
        e("feed.stage").swipeUp(); pause(1); try mark("keep"); pause(2)
        e("feed.stage").swipeLeft(); pause(1); try mark("trash"); pause(2)
        e("feed.stage").swipeRight(); pause(0.8); try mark("later"); pause(3)
        e("feed.stage").swipeDown(); pause(0.8); try mark("back"); pause(4)
        try recording("stop",name:"01-review")
    }
    func test20AppPreviewStudio() throws {
        launch("editor")
        XCTAssertTrue(e("editor.stage").waitForExistence(timeout:30)); pause(2)
        try recording("start",name:"02-studio")
        try mark("editor"); pause(3)
        editorTool("adjust"); try mark("adjust"); pause(3)
        editorTool("filter"); try mark("filter"); pause(3)
        editorTool("markup"); try mark("markup"); pause(3)
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
        photo.tap(); try mark("hidden-controls"); pause(3)
        photo.doubleTap(); try mark("zoom"); pause(3)
        photo.doubleTap(); photo.tap(); try mark("controls"); pause(4)
        try recording("stop",name:"03-vault")
    }
}
