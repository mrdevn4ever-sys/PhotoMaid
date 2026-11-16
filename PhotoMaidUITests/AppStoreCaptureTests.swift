import XCTest
import StoreKitTest
import ImageIO
import Vision
import CryptoKit

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
    private var isConceptA: Bool { name.contains("test07ConceptAStoreScreenshots") || isConceptAV4 }
    private var isConceptAV4: Bool { name.contains("test08ConceptAV4StoreScreenshots") }
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
    @discardableResult
    private func holdSwipe(_ direction: String, still: String? = nil, offset customOffset: CGVector? = nil,
                           holdDuration: TimeInterval? = nil, captureAfterRelease: Bool = false) throws -> XCUIScreenshot? {
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
        // Native rapid burst first, offline OCR after. Failed C12 left a measured
        // 4.08-second gap between frames while synchronous Vision occupied the
        // four-second receipt window. No OCR, PNG encoding, disk I/O or AX in burst.
        var releasedScreenshot: XCUIScreenshot?
        if captureAfterRelease {
            let acquisitionStarted = Date().timeIntervalSince1970
            let deadline = Date().addingTimeInterval(6)
            var nativeFrames: [(shot: XCUIScreenshot, start: TimeInterval, finish: TimeInterval)] = []
            repeat {
                let started = Date().timeIntervalSince1970
                let shot = XCUIScreen.main.screenshot()
                let finished = Date().timeIntervalSince1970
                nativeFrames.append((shot: shot, start: started, finish: finished))
                Thread.sleep(forTimeInterval: 0.05)
            } while Date() < deadline && nativeFrames.count < 128
            let acquisitionFinished = Date().timeIntervalSince1970
            var captureStarted = nativeFrames.last!.start
            var captureFinished = nativeFrames.last!.finish
            releasedScreenshot = nativeFrames.last!.shot
            var frames: [[String: Any]] = []
            // Preserve every actual frame and its original capture times BEFORE OCR.
            for (index, frame) in nativeFrames.enumerated() {
                if let still {
                    try frame.shot.pngRepresentation.write(to: output.appendingPathComponent("stills/\(still)-after-release-frame-\(index).png"), options: .atomic)
                }
                frames.append(["index": index, "captureStarted": frame.start, "captureFinished": frame.finish,
                               "ocrPerformed": false])
            }
            let analysisStarted = Date().timeIntervalSince1970
            let expectedDate = String(format: t("later_in_days_again#other"), Int64(2))
            var visible = false
            var selectedFrameIndex: Int?
            func writeReadinessProof() throws {
                if let still {
                    let timing: [String: Any] = ["method": "six-second actual native screenshot burst, then offline Vision before AX reads",
                                                 "captureStarted": captureStarted, "captureFinished": captureFinished,
                                                 "acquisitionStarted": acquisitionStarted, "acquisitionFinished": acquisitionFinished,
                                                 "analysisStarted": analysisStarted, "frames": frames,
                                                 "selectedFrameIndex": selectedFrameIndex.map { $0 as Any } ?? NSNull(),
                                                 "actualDateAndChangeVisible": visible, "deadlineSeconds": 6,
                                                 "ocrAfterAllCaptures": true, "realTransientLifetimeUnchanged": true]
                    guard JSONSerialization.isValidJSONObject(timing) else {
                        throw NSError(domain: "GaleriQStoreCapture", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Capture evidence must contain only JSON primitives"])
                    }
                    try JSONSerialization.data(withJSONObject: timing, options: [.prettyPrinted, .sortedKeys])
                        .write(to: output.appendingPathComponent("stills/\(still)-after-release.json"), options: .atomic)
                }
            }
            try writeReadinessProof()
            // Read immutable captured pixels, never the now-later live UI state.
            for (index, frame) in nativeFrames.enumerated() {
                let actualImage = try XCTUnwrap(frame.shot.image.cgImage)
                let readiness = VNRecognizeTextRequest()
                readiness.recognitionLevel = .accurate
                readiness.recognitionLanguages = ["en-US"]
                readiness.usesLanguageCorrection = false
                let recognitionStarted = Date().timeIntervalSince1970
                try VNImageRequestHandler(cgImage: actualImage, options: [:]).perform([readiness])
                let recognitionFinished = Date().timeIntervalSince1970
                let actualText = (readiness.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                visible = actualText.localizedCaseInsensitiveContains(expectedDate) && actualText.localizedCaseInsensitiveContains(t("change"))
                frames[index]["ocrPerformed"] = true
                frames[index]["recognitionStarted"] = recognitionStarted
                frames[index]["recognitionFinished"] = recognitionFinished
                frames[index]["recognizedText"] = actualText
                frames[index]["actualDateAndChangeVisible"] = visible
                if visible {
                    selectedFrameIndex = index
                    releasedScreenshot = frame.shot
                    captureStarted = frame.start
                    captureFinished = frame.finish
                }
                try writeReadinessProof()
                if visible { break }
            }
        }
        pause(1)
        XCTAssertEqual(feedPosition(), before + (direction == "down" ? -1 : 1), "Actual feed decision/navigation must advance")
        if let still { try awaitStill(still) }
        return releasedScreenshot
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
        // Genuine device accessibility setting, not a painted/modified alert.
        // This disposable simulator starts without a personal Settings account.
        let preferences = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        preferences.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        preferences.launch()
        var actualSettingsLabels: [String] = []
        // The preceding native failure proved this disposable device's system
        // language was German, even though the target app itself was en-US.
        // Resolve the observed labels across roles; do not assume StaticText.
        for labels in [["Accessibility", "Bedienungshilfen"], ["Display & Text Size", "Anzeige & Textgröße"]] {
            let row = preferences.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", labels as NSArray)).firstMatch
            for _ in 0..<8 {
                if row.exists && row.isHittable { break }
                preferences.swipeUp(); pause(0.4)
            }
            try preferences.debugDescription.write(to: output.appendingPathComponent("settings-route-\(actualSettingsLabels.count).txt"), atomically: true, encoding: .utf8)
            XCTAssertTrue(row.exists && row.isHittable, "Native Settings route unavailable: \(labels)")
            actualSettingsLabels.append(row.label)
            row.tap(); pause(0.5)
        }
        let transparency = preferences.switches.matching(NSPredicate(format: "label CONTAINS[c] 'Reduce Transparency' OR label CONTAINS[c] 'Transparenz reduzieren'")).firstMatch
        for _ in 0..<8 {
            if transparency.exists && transparency.isHittable { break }
            preferences.swipeUp(); pause(0.4)
        }
        XCTAssertTrue(transparency.exists && transparency.isHittable)
        try preferences.debugDescription.write(to: output.appendingPathComponent("settings-reduce-transparency-before.txt"), atomically: true, encoding: .utf8)
        try preferences.screenshot().pngRepresentation.write(to: output.appendingPathComponent("settings-reduce-transparency-before.png"))
        let switchFrame = transparency.frame
        var targetedToggleTap = false
        var switchTapAttempts: [[String: Any]] = []
        // C13 retained an observed OFF->OFF no-op. Its AX tree exposes an
        // actual 63pt nested switch inside a 330pt row proxy: tap that leaf.
        // Reacquire and retry only a freshly observed OFF state, never ON.
        for attempt in 0..<3 {
            let beforeValue = transparency.value as? String ?? "unknown"
            if beforeValue == "1" { break }
            XCTAssertEqual(beforeValue, "0", "Do not blindly toggle an unknown Settings state")
            guard beforeValue == "0" else { break }
            let nestedToggle = transparency.switches.firstMatch
            let useLeaf = nestedToggle.exists && nestedToggle.isHittable
            let target = useLeaf ? nestedToggle : transparency
            let targetFrame = target.frame
            let tapStarted = Date().timeIntervalSince1970
            if useLeaf {
                target.tap()
            } else {
                // Retain the observed trailing-control fallback, never row center.
                target.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                targetedToggleTap = true
            }
            let tapFinished = Date().timeIntervalSince1970
            let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: transparency)
            let observedResult = XCTWaiter.wait(for: [observed], timeout: 8)
            let afterValue = transparency.value as? String ?? "unknown"
            switchTapAttempts.append(["attempt": attempt, "beforeValue": beforeValue, "afterValue": afterValue,
                                      "target": useLeaf ? "nested native Switch.tap" : "row-relative trailing toggle",
                                      "targetFrame": ["x": targetFrame.minX, "y": targetFrame.minY,
                                                      "width": targetFrame.width, "height": targetFrame.height],
                                      "tapStarted": tapStarted, "tapFinished": tapFinished,
                                      "waitResult": observedResult.rawValue])
            // Save the actual result of each input before deciding whether to retry.
            try preferences.debugDescription.write(to: output.appendingPathComponent("settings-reduce-transparency-attempt-\(attempt).txt"), atomically: true, encoding: .utf8)
            try preferences.screenshot().pngRepresentation.write(to: output.appendingPathComponent("settings-reduce-transparency-attempt-\(attempt).png"))
            try JSONSerialization.data(withJSONObject: switchTapAttempts, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("settings-reduce-transparency-attempts.json"), options: .atomic)
            if observedResult == .completed && afterValue == "1" { break }
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: transparency)
        let enabledResult = XCTWaiter.wait(for: [enabled], timeout: 8)
        // Retain the real failing surface and proof before any final assertion.
        try preferences.debugDescription.write(to: output.appendingPathComponent("settings-reduce-transparency-after.txt"), atomically: true, encoding: .utf8)
        try preferences.screenshot().pngRepresentation.write(to: output.appendingPathComponent("settings-reduce-transparency-after.png"))
        let settingsProof: [String: Any] = ["path": ["Accessibility", "Display & Text Size", "Reduce Transparency"],
                                          "actualNavigationLabels": actualSettingsLabels, "actualSwitchLabel": transparency.label,
                                          "actualSwitchValue": transparency.value as? String ?? "unknown",
                                          "actualSwitchFrame": ["x": switchFrame.minX, "y": switchFrame.minY, "width": switchFrame.width, "height": switchFrame.height],
                                          "targetedTrailingToggleTap": targetedToggleTap,
                                          "toggleTapAttempts": switchTapAttempts,
                                          "method": "real native Settings UI leaf control with bounded observed-OFF retries, not private defaults"]
        try JSONSerialization.data(withJSONObject: settingsProof, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("concept-a-system-settings.json"), options: .atomic)
        XCTAssertEqual(enabledResult, .completed, "Require observed native Reduce Transparency state, not input delivery alone")
        XCTAssertEqual(transparency.value as? String, "1")
        preferences.terminate()
        launch("introduction")
        for _ in 0..<5 { tap(e("onboarding.next")) }
        waitForPhotoAccess()
        launch("today")
        conceptARequireVisible(e("today.title"), "Actual canonical GaleriQ wordmark")
        XCTAssertTrue(e("today.quick.photos").exists)
        // Owner policy: no app/UI screenshot may appear as a photo, including
        // the next card, small thumbnails, delete previews, collages or games.
        // Import only the hash-allowlisted stock-photo/video fixture; never add
        // a captured screen to PhotoKit in this current Concept A route.
        launch("concept-a-library")
        let initial = try conceptAWait("initial-library") { ($0["readReady"] as? Bool == true) && ($0["libraryLoaded"] as? Bool == true) }
        XCTAssertEqual(initial["locale"] as? String, "en_US")
        XCTAssertEqual(initial["appVersion"] as? String, "1.0.1")
        XCTAssertEqual(initial["reduceMotion"] as? Bool, false, "Native drag tilt must not be disabled by Reduce Motion")
        XCTAssertEqual(initial["reduceTransparency"] as? Bool, true, "Require the real device setting for the clean system confirmation")
        XCTAssertEqual(initial["eventCount"] as? Int, 0, "Use fresh persistent app data, not another capture's decisions")
        XCTAssertEqual(initial["basketIDs"] as? [String], [])
        XCTAssertEqual((initial["vault"] as? [String: Any])?["setUp"] as? Bool, false)
        let inventory = try XCTUnwrap(initial["inventory"] as? [[String: Any]])
        let names = inventory.compactMap { $0["filename"] as? String }
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(names.count, Set(names).count, "Do not import duplicate fixture filenames")
        XCTAssertTrue(names.allSatisfy { $0.hasPrefix("CA_") }, "Only the approved photo/video fixture, no app screenshots or legacy archive photos")
        XCTAssertTrue(inventory.allSatisfy { $0["isScreenshot"] as? Bool == false }, "No screenshot assets anywhere in the capture library")
        XCTAssertFalse(names.contains { $0.lowercased().hasSuffix(".png") || $0.localizedCaseInsensitiveContains("screenshot") || $0.localizedCaseInsensitiveContains("native-library") })
        XCTAssertEqual(inventory.filter { $0["isVideo"] as? Bool == false }.count, 35)
        XCTAssertEqual(inventory.filter { $0["isVideo"] as? Bool == true }.count, 2)
        for filename in ["CA_01_clutter_blur.jpg", "CA_02_clutter_shake.jpg", "CA_03_clutter_dark.jpg",
                         "CA_10_duplicate_a.jpg", "CA_11_duplicate_b.jpg"]
            + (1...6).map({ String(format: "CA_20_series_%02d.jpg", $0) })
            + (1...24).map({ String(format: "CA_30_pretty_%02d.jpg", $0) }) {
            let asset = try conceptAAsset(filename, in: initial)
            XCTAssertEqual(asset["isVideo"] as? Bool, false)
            XCTAssertGreaterThan(asset["pixelWidth"] as? Int ?? 0, 0)
        }
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
        XCTAssertEqual(feedSelection["sourceFiles"] as? [String], ["CA_30_pretty_23.jpg", "CA_30_pretty_24.jpg",
                                                               "CA_30_pretty_06.jpg", "CA_30_pretty_07.jpg", "CA_30_pretty_08.jpg"])
        let sharpHero = try conceptAAsset("CA_30_pretty_23.jpg", in: initial)
        try conceptARequireStage(sharpHero)
        let sceneProof: [String: Any] = ["schema": 1, "reduceTransparency": initial["reduceTransparency"] as? Bool ?? false,
                                       "sourceFiles": feedSelection["sourceFiles"] as? [String] ?? [],
                                       "heroAssetID": sharpHero["id"] as? String ?? ""]
        try JSONSerialization.data(withJSONObject: sceneProof, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("concept-a-v3-scenes.json"), options: .atomic)
        try requestStill("warmup-concept-a", delay: 0, warmup: true); try awaitStill("warmup-concept-a")
        let heldAt = Date().timeIntervalSince1970
        // A real left drag supplies FeedMediaTransform's native offset.width / 40 rotation. No baked photo rotation.
        try holdSwipe("left", still: "concept-a-swipe", offset: CGVector(dx: -150, dy: -20), holdDuration: 25)
        let held = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("stills/concept-a-swipe.json"))) as? [String: Any])
        XCTAssertGreaterThanOrEqual(held["requested"] as? Double ?? 0, heldAt)
        XCTAssertLessThan(held["finished"] as? Double ?? .infinity, heldAt + 24, "Recorder must finish while the finger is still down")
        try conceptARequireStage(try conceptAAsset("CA_30_pretty_24.jpg", in: initial))
        swipeFeed("left") // Second real Trash decision on a neutral photo, never on an app screenshot.
        try conceptARequireStage(try conceptAAsset("CA_30_pretty_06.jpg", in: initial))
        let beforeLater = feedPosition()
        let feedBounds = app.frame
        // Warm the public Vision recognizer BEFORE the real transient window.
        // Cold OCR initialization must not consume a four-second native pill.
        let recognitionWarmup = VNRecognizeTextRequest()
        recognitionWarmup.recognitionLevel = .accurate
        recognitionWarmup.recognitionLanguages = ["en-US"]
        recognitionWarmup.usesLanguageCorrection = false
        let warmupImage = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        try VNImageRequestHandler(cgImage: warmupImage, options: [:]).perform([recognitionWarmup])
        // Owner revision: show the genuine rightward drag and native Later badge,
        // not only the reminder after committing. Never redraw or overlay the UI.
        let laterHeldAt = Date().timeIntervalSince1970
        let laterScreenshot = try XCTUnwrap(try holdSwipe("right", still: "concept-a-later-swipe",
                                                        offset: CGVector(dx: 150, dy: -20), holdDuration: 25,
                                                        captureAfterRelease: true))
        // C9 proved the native decision advanced, but its normal AX post-check
        // consumed the four-second pill. Inspect the already-saved real pixels,
        // not an expired accessibility node. Do not extend any production timer.
        try laterScreenshot.pngRepresentation.write(to: output.appendingPathComponent("stills/concept-a-later-timing.png"), options: .atomic)
        let laterImage = try XCTUnwrap(laterScreenshot.image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: laterImage, options: [:]).perform([request])
        let visiblePillText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        try visiblePillText.write(to: output.appendingPathComponent("concept-a-later-visible-text.txt"), atomically: true, encoding: .utf8)
        let dateText = String(format: t("later_in_days_again#other"), Int64(2))
        let dateObservation = try XCTUnwrap((request.results ?? []).first {
            $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains(dateText) == true
        }, "Actual saved native reminder must visibly show its unchanged two-day date")
        let changeObservation = try XCTUnwrap((request.results ?? []).first {
            $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains(t("change")) == true
        }, "Actual saved native reminder must visibly show Change")
        func textPixelRect(_ observation: VNRecognizedTextObservation) -> CGRect {
            let box = observation.boundingBox
            return CGRect(x: box.minX * CGFloat(laterImage.width), y: (1 - box.maxY) * CGFloat(laterImage.height),
                          width: box.width * CGFloat(laterImage.width), height: box.height * CGFloat(laterImage.height))
        }
        let pillPixels = textPixelRect(dateObservation).union(textPixelRect(changeObservation)).insetBy(dx: -18, dy: -18).integral
        let nativeImageBounds = CGRect(x: 0, y: 0, width: CGFloat(laterImage.width), height: CGFloat(laterImage.height))
        XCTAssertTrue(nativeImageBounds.contains(pillPixels), "The actual reminder text and surrounding margin must be wholly onscreen")
        XCTAssertTrue(visiblePillText.localizedCaseInsensitiveContains(dateText), "Actual native reminder pixels must show the two-day date")
        XCTAssertTrue(visiblePillText.localizedCaseInsensitiveContains(t("change")), "Actual native pill pixels must show Change: \(visiblePillText)")
        XCTAssertEqual(feedPosition(), beforeLater + 1, "The actual right-swipe decision must advance")
        snap("concept-a-later", settle: 0, captured: laterScreenshot)
        let laterHeld = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("stills/concept-a-later-swipe.json"))) as? [String: Any])
        XCTAssertGreaterThanOrEqual(laterHeld["requested"] as? Double ?? 0, laterHeldAt)
        XCTAssertLessThan(laterHeld["finished"] as? Double ?? .infinity, laterHeldAt + 24, "Later screenshot must finish while the finger is still down")
        let laterHeldURL = output.appendingPathComponent("screenshots/concept-a-later-swipe.png")
        let laterHeldSource = try XCTUnwrap(CGImageSourceCreateWithURL(laterHeldURL as CFURL, nil))
        let laterHeldImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(laterHeldSource, 0, nil))
        // Only inspect the upper photo area: the static footer also says Later
        // and must not accidentally satisfy the active swipe-badge requirement.
        let activeBadgeArea = try XCTUnwrap(laterHeldImage.cropping(to: CGRect(x: 0, y: 250, width: 1206, height: 1000)))
        let swipeRequest = VNRecognizeTextRequest()
        swipeRequest.recognitionLevel = .accurate
        swipeRequest.recognitionLanguages = ["en-US"]
        swipeRequest.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: activeBadgeArea, options: [:]).perform([swipeRequest])
        let activeSwipeText = (swipeRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        try activeSwipeText.write(to: output.appendingPathComponent("concept-a-later-swipe-visible-text.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(activeSwipeText.localizedCaseInsensitiveContains("Later"), "Actual upper-photo swipe badge must show Later, not just its static footer: \(activeSwipeText)")
        try conceptARequireStage(try conceptAAsset("CA_30_pretty_07.jpg", in: initial))
        swipeFeed("up")
        let trashPhotoFiles = ["CA_30_pretty_23.jpg", "CA_30_pretty_24.jpg"]
        let trashIDs = Set(try trashPhotoFiles.map { try conceptAID($0, in: initial) })
        XCTAssertFalse(names.contains("concept-a-native-library.png"), "No app screenshot may exist in this sample library or appear over Delete")
        for filename in trashPhotoFiles {
            let photo = try conceptAAsset(filename, in: initial)
            XCTAssertEqual(photo["isVideo"] as? Bool, false, "Deletion preview must contain actual neutral photos")
        }
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
        try captureConceptAGames()
        try captureConceptAVault(initial: initial)
        let expected = ["concept-a-swipe", "concept-a-duplicates", "concept-a-large-files", "concept-a-trash",
                        "concept-a-delete-confirm", "concept-a-vault", "concept-a-vault-locked", "concept-a-later", "concept-a-later-swipe",
                        "concept-a-months", "concept-a-analysis", "concept-a-collage", "concept-a-editor", "concept-a-games", "concept-a-games-menu"]
        for name in expected { try conceptAAssertPNG(output.appendingPathComponent("screenshots/\(name).png")) }
        XCTAssertEqual(Set(shots.map { $0["file"] ?? "" }), Set((expected + ["concept-a-logo"]).map { $0 + ".png" }))
    }

    // MARK: Additive Concept A V4 evidence (QA UI test only)

    /// Select ONLY this test in the V4 workflow; retain all legacy scenarios and helpers unchanged.
    /// Evidence schemas are versioned independently from the creative version; all objects are JSON primitives.
    func test08ConceptAV4StoreScreenshots() throws {
        do {
            try conceptAV4Require(isConceptAV4 && language == "en", "V4 requires its explicit en-US test selector")
            try captureConceptAV4BaseScreenshots()
            let initial = try XCTUnwrap(conceptAEvidenceLog.first {
                $0["checkpoint"] as? String == "initial-library"
            }?["state"] as? [String: Any], "Retain the actual initial 35-photo/two-video inventory from the complete base scenario")
            try captureConceptAV4Months(initial: initial)
            try captureConceptAV4Editor(initial: initial)
            for name in ["months", "editor-before", "editor-filter-selected", "editor-after", "editor-undo",
                         "editor-redo", "editor-copy-default"] {
                try conceptAAssertPNG(output.appendingPathComponent("screenshots/concept-a-v4-\(name).png"))
            }
        } catch {
            // Preserve the real failing UI before surfacing a throwing V4 gate. No fallback source is accepted.
            try? conceptAV4Still("concept-a-v4-failure", directory: "stills")
            let failure: [String: Any] = ["schema": 1, "status": "FAIL", "error": String(describing: error),
                                         "lastObservation": conceptAEvidenceLog.last ?? [:]]
            try? conceptAV4Write(failure, to: "concept-a-v4-failure.json")
            throw error
        }
    }

    // V4 forks only QA orchestration; all legacy method/helper bodies remain byte-for-byte equivalent.
    // Its base scenario is otherwise the unchanged test07 sequence, including every native gate.
    private func captureConceptAV4BaseScreenshots() throws {
        XCTAssertEqual(language, "en", "Concept A is a new en-US master, not a localization/historical-source job")
        // Genuine device accessibility setting, not a painted/modified alert.
        // This disposable simulator starts without a personal Settings account.
        let preferences = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        preferences.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        preferences.launch()
        var actualSettingsLabels: [String] = []
        // The preceding native failure proved this disposable device's system
        // language was German, even though the target app itself was en-US.
        // Resolve the observed labels across roles; do not assume StaticText.
        for labels in [["Accessibility", "Bedienungshilfen"], ["Display & Text Size", "Anzeige & Textgröße"]] {
            let row = preferences.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", labels as NSArray)).firstMatch
            for _ in 0..<8 {
                if row.exists && row.isHittable { break }
                preferences.swipeUp(); pause(0.4)
            }
            try preferences.debugDescription.write(to: output.appendingPathComponent("settings-route-\(actualSettingsLabels.count).txt"), atomically: true, encoding: .utf8)
            XCTAssertTrue(row.exists && row.isHittable, "Native Settings route unavailable: \(labels)")
            actualSettingsLabels.append(row.label)
            row.tap(); pause(0.5)
        }
        let transparency = preferences.switches.matching(NSPredicate(format: "label CONTAINS[c] 'Reduce Transparency' OR label CONTAINS[c] 'Transparenz reduzieren'")).firstMatch
        for _ in 0..<8 {
            if transparency.exists && transparency.isHittable { break }
            preferences.swipeUp(); pause(0.4)
        }
        XCTAssertTrue(transparency.exists && transparency.isHittable)
        try preferences.debugDescription.write(to: output.appendingPathComponent("settings-reduce-transparency-before.txt"), atomically: true, encoding: .utf8)
        try preferences.screenshot().pngRepresentation.write(to: output.appendingPathComponent("settings-reduce-transparency-before.png"))
        let switchFrame = transparency.frame
        var targetedToggleTap = false
        var switchTapAttempts: [[String: Any]] = []
        // C13 retained an observed OFF->OFF no-op. Its AX tree exposes an
        // actual 63pt nested switch inside a 330pt row proxy: tap that leaf.
        // Reacquire and retry only a freshly observed OFF state, never ON.
        for attempt in 0..<3 {
            let beforeValue = transparency.value as? String ?? "unknown"
            if beforeValue == "1" { break }
            XCTAssertEqual(beforeValue, "0", "Do not blindly toggle an unknown Settings state")
            guard beforeValue == "0" else { break }
            let nestedToggle = transparency.switches.firstMatch
            let useLeaf = nestedToggle.exists && nestedToggle.isHittable
            let target = useLeaf ? nestedToggle : transparency
            let targetFrame = target.frame
            let tapStarted = Date().timeIntervalSince1970
            if useLeaf {
                target.tap()
            } else {
                // Retain the observed trailing-control fallback, never row center.
                target.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                targetedToggleTap = true
            }
            let tapFinished = Date().timeIntervalSince1970
            let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: transparency)
            let observedResult = XCTWaiter.wait(for: [observed], timeout: 8)
            let afterValue = transparency.value as? String ?? "unknown"
            switchTapAttempts.append(["attempt": attempt, "beforeValue": beforeValue, "afterValue": afterValue,
                                      "target": useLeaf ? "nested native Switch.tap" : "row-relative trailing toggle",
                                      "targetFrame": ["x": targetFrame.minX, "y": targetFrame.minY,
                                                      "width": targetFrame.width, "height": targetFrame.height],
                                      "tapStarted": tapStarted, "tapFinished": tapFinished,
                                      "waitResult": observedResult.rawValue])
            // Save the actual result of each input before deciding whether to retry.
            try preferences.debugDescription.write(to: output.appendingPathComponent("settings-reduce-transparency-attempt-\(attempt).txt"), atomically: true, encoding: .utf8)
            try preferences.screenshot().pngRepresentation.write(to: output.appendingPathComponent("settings-reduce-transparency-attempt-\(attempt).png"))
            try JSONSerialization.data(withJSONObject: switchTapAttempts, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("settings-reduce-transparency-attempts.json"), options: .atomic)
            if observedResult == .completed && afterValue == "1" { break }
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: transparency)
        let enabledResult = XCTWaiter.wait(for: [enabled], timeout: 8)
        // Retain the real failing surface and proof before any final assertion.
        try preferences.debugDescription.write(to: output.appendingPathComponent("settings-reduce-transparency-after.txt"), atomically: true, encoding: .utf8)
        try preferences.screenshot().pngRepresentation.write(to: output.appendingPathComponent("settings-reduce-transparency-after.png"))
        let settingsProof: [String: Any] = ["path": ["Accessibility", "Display & Text Size", "Reduce Transparency"],
                                          "actualNavigationLabels": actualSettingsLabels, "actualSwitchLabel": transparency.label,
                                          "actualSwitchValue": transparency.value as? String ?? "unknown",
                                          "actualSwitchFrame": ["x": switchFrame.minX, "y": switchFrame.minY, "width": switchFrame.width, "height": switchFrame.height],
                                          "targetedTrailingToggleTap": targetedToggleTap,
                                          "toggleTapAttempts": switchTapAttempts,
                                          "method": "real native Settings UI leaf control with bounded observed-OFF retries, not private defaults"]
        try JSONSerialization.data(withJSONObject: settingsProof, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("concept-a-system-settings.json"), options: .atomic)
        XCTAssertEqual(enabledResult, .completed, "Require observed native Reduce Transparency state, not input delivery alone")
        XCTAssertEqual(transparency.value as? String, "1")
        preferences.terminate()
        launch("introduction")
        for _ in 0..<5 { tap(e("onboarding.next")) }
        waitForPhotoAccess()
        launch("today")
        conceptARequireVisible(e("today.title"), "Actual canonical GaleriQ wordmark")
        XCTAssertTrue(e("today.quick.photos").exists)
        // Owner policy: no app/UI screenshot may appear as a photo, including
        // the next card, small thumbnails, delete previews, collages or games.
        // Import only the hash-allowlisted stock-photo/video fixture; never add
        // a captured screen to PhotoKit in this current Concept A route.
        launch("concept-a-library")
        let initial = try conceptAWait("initial-library") { ($0["readReady"] as? Bool == true) && ($0["libraryLoaded"] as? Bool == true) }
        XCTAssertEqual(initial["locale"] as? String, "en_US")
        XCTAssertEqual(initial["appVersion"] as? String, "1.0.1")
        XCTAssertEqual(initial["reduceMotion"] as? Bool, false, "Native drag tilt must not be disabled by Reduce Motion")
        XCTAssertEqual(initial["reduceTransparency"] as? Bool, true, "Require the real device setting for the clean system confirmation")
        XCTAssertEqual(initial["eventCount"] as? Int, 0, "Use fresh persistent app data, not another capture's decisions")
        XCTAssertEqual(initial["basketIDs"] as? [String], [])
        XCTAssertEqual((initial["vault"] as? [String: Any])?["setUp"] as? Bool, false)
        let inventory = try XCTUnwrap(initial["inventory"] as? [[String: Any]])
        let names = inventory.compactMap { $0["filename"] as? String }
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(names.count, Set(names).count, "Do not import duplicate fixture filenames")
        XCTAssertTrue(names.allSatisfy { $0.hasPrefix("CA_") }, "Only the approved photo/video fixture, no app screenshots or legacy archive photos")
        XCTAssertTrue(inventory.allSatisfy { $0["isScreenshot"] as? Bool == false }, "No screenshot assets anywhere in the capture library")
        XCTAssertFalse(names.contains { $0.lowercased().hasSuffix(".png") || $0.localizedCaseInsensitiveContains("screenshot") || $0.localizedCaseInsensitiveContains("native-library") })
        XCTAssertEqual(inventory.filter { $0["isVideo"] as? Bool == false }.count, 35)
        XCTAssertEqual(inventory.filter { $0["isVideo"] as? Bool == true }.count, 2)
        for filename in ["CA_01_clutter_blur.jpg", "CA_02_clutter_shake.jpg", "CA_03_clutter_dark.jpg",
                         "CA_10_duplicate_a.jpg", "CA_11_duplicate_b.jpg"]
            + (1...6).map({ String(format: "CA_20_series_%02d.jpg", $0) })
            + (1...24).map({ String(format: "CA_30_pretty_%02d.jpg", $0) }) {
            let asset = try conceptAAsset(filename, in: initial)
            XCTAssertEqual(asset["isVideo"] as? Bool, false)
            XCTAssertGreaterThan(asset["pixelWidth"] as? Int ?? 0, 0)
        }
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
        XCTAssertEqual(feedSelection["sourceFiles"] as? [String], ["CA_30_pretty_23.jpg", "CA_30_pretty_24.jpg",
                                                               "CA_30_pretty_06.jpg", "CA_30_pretty_07.jpg", "CA_30_pretty_08.jpg"])
        let sharpHero = try conceptAAsset("CA_30_pretty_23.jpg", in: initial)
        try conceptARequireStage(sharpHero)
        let sceneProof: [String: Any] = ["schema": 1, "reduceTransparency": initial["reduceTransparency"] as? Bool ?? false,
                                       "sourceFiles": feedSelection["sourceFiles"] as? [String] ?? [],
                                       "heroAssetID": sharpHero["id"] as? String ?? ""]
        try JSONSerialization.data(withJSONObject: sceneProof, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("concept-a-v3-scenes.json"), options: .atomic)
        try requestStill("warmup-concept-a", delay: 0, warmup: true); try awaitStill("warmup-concept-a")
        let heldAt = Date().timeIntervalSince1970
        // A real left drag supplies FeedMediaTransform's native offset.width / 40 rotation. No baked photo rotation.
        try holdSwipe("left", still: "concept-a-swipe", offset: CGVector(dx: -150, dy: -20), holdDuration: 25)
        let held = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("stills/concept-a-swipe.json"))) as? [String: Any])
        XCTAssertGreaterThanOrEqual(held["requested"] as? Double ?? 0, heldAt)
        XCTAssertLessThan(held["finished"] as? Double ?? .infinity, heldAt + 24, "Recorder must finish while the finger is still down")
        try conceptARequireStage(try conceptAAsset("CA_30_pretty_24.jpg", in: initial))
        swipeFeed("left") // Second real Trash decision on a neutral photo, never on an app screenshot.
        try conceptARequireStage(try conceptAAsset("CA_30_pretty_06.jpg", in: initial))
        let beforeLater = feedPosition()
        let feedBounds = app.frame
        // Warm the public Vision recognizer BEFORE the real transient window.
        // Cold OCR initialization must not consume a four-second native pill.
        let recognitionWarmup = VNRecognizeTextRequest()
        recognitionWarmup.recognitionLevel = .accurate
        recognitionWarmup.recognitionLanguages = ["en-US"]
        recognitionWarmup.usesLanguageCorrection = false
        let warmupImage = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        try VNImageRequestHandler(cgImage: warmupImage, options: [:]).perform([recognitionWarmup])
        // Owner revision: show the genuine rightward drag and native Later badge,
        // not only the reminder after committing. Never redraw or overlay the UI.
        let laterHeldAt = Date().timeIntervalSince1970
        let laterScreenshot = try XCTUnwrap(try holdSwipe("right", still: "concept-a-later-swipe",
                                                        offset: CGVector(dx: 150, dy: -20), holdDuration: 25,
                                                        captureAfterRelease: true))
        // C9 proved the native decision advanced, but its normal AX post-check
        // consumed the four-second pill. Inspect the already-saved real pixels,
        // not an expired accessibility node. Do not extend any production timer.
        try laterScreenshot.pngRepresentation.write(to: output.appendingPathComponent("stills/concept-a-later-timing.png"), options: .atomic)
        let laterImage = try XCTUnwrap(laterScreenshot.image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: laterImage, options: [:]).perform([request])
        let visiblePillText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        try visiblePillText.write(to: output.appendingPathComponent("concept-a-later-visible-text.txt"), atomically: true, encoding: .utf8)
        let dateText = String(format: t("later_in_days_again#other"), Int64(2))
        let dateObservation = try XCTUnwrap((request.results ?? []).first {
            $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains(dateText) == true
        }, "Actual saved native reminder must visibly show its unchanged two-day date")
        let changeObservation = try XCTUnwrap((request.results ?? []).first {
            $0.topCandidates(1).first?.string.localizedCaseInsensitiveContains(t("change")) == true
        }, "Actual saved native reminder must visibly show Change")
        func textPixelRect(_ observation: VNRecognizedTextObservation) -> CGRect {
            let box = observation.boundingBox
            return CGRect(x: box.minX * CGFloat(laterImage.width), y: (1 - box.maxY) * CGFloat(laterImage.height),
                          width: box.width * CGFloat(laterImage.width), height: box.height * CGFloat(laterImage.height))
        }
        let pillPixels = textPixelRect(dateObservation).union(textPixelRect(changeObservation)).insetBy(dx: -18, dy: -18).integral
        let nativeImageBounds = CGRect(x: 0, y: 0, width: CGFloat(laterImage.width), height: CGFloat(laterImage.height))
        XCTAssertTrue(nativeImageBounds.contains(pillPixels), "The actual reminder text and surrounding margin must be wholly onscreen")
        XCTAssertTrue(visiblePillText.localizedCaseInsensitiveContains(dateText), "Actual native reminder pixels must show the two-day date")
        XCTAssertTrue(visiblePillText.localizedCaseInsensitiveContains(t("change")), "Actual native pill pixels must show Change: \(visiblePillText)")
        XCTAssertEqual(feedPosition(), beforeLater + 1, "The actual right-swipe decision must advance")
        snap("concept-a-later", settle: 0, captured: laterScreenshot)
        let laterHeld = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("stills/concept-a-later-swipe.json"))) as? [String: Any])
        XCTAssertGreaterThanOrEqual(laterHeld["requested"] as? Double ?? 0, laterHeldAt)
        XCTAssertLessThan(laterHeld["finished"] as? Double ?? .infinity, laterHeldAt + 24, "Later screenshot must finish while the finger is still down")
        let laterHeldURL = output.appendingPathComponent("screenshots/concept-a-later-swipe.png")
        let laterHeldSource = try XCTUnwrap(CGImageSourceCreateWithURL(laterHeldURL as CFURL, nil))
        let laterHeldImage = try XCTUnwrap(CGImageSourceCreateImageAtIndex(laterHeldSource, 0, nil))
        // Only inspect the upper photo area: the static footer also says Later
        // and must not accidentally satisfy the active swipe-badge requirement.
        let activeBadgeArea = try XCTUnwrap(laterHeldImage.cropping(to: CGRect(x: 0, y: 250, width: 1206, height: 1000)))
        let swipeRequest = VNRecognizeTextRequest()
        swipeRequest.recognitionLevel = .accurate
        swipeRequest.recognitionLanguages = ["en-US"]
        swipeRequest.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: activeBadgeArea, options: [:]).perform([swipeRequest])
        let activeSwipeText = (swipeRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        try activeSwipeText.write(to: output.appendingPathComponent("concept-a-later-swipe-visible-text.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(activeSwipeText.localizedCaseInsensitiveContains("Later"), "Actual upper-photo swipe badge must show Later, not just its static footer: \(activeSwipeText)")
        try conceptARequireStage(try conceptAAsset("CA_30_pretty_07.jpg", in: initial))
        swipeFeed("up")
        let trashPhotoFiles = ["CA_30_pretty_23.jpg", "CA_30_pretty_24.jpg"]
        let trashIDs = Set(try trashPhotoFiles.map { try conceptAID($0, in: initial) })
        XCTAssertFalse(names.contains("concept-a-native-library.png"), "No app screenshot may exist in this sample library or appear over Delete")
        for filename in trashPhotoFiles {
            let photo = try conceptAAsset(filename, in: initial)
            XCTAssertEqual(photo["isVideo"] as? Bool, false, "Deletion preview must contain actual neutral photos")
        }
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
        try captureConceptAGames()
        try captureConceptAV4Vault(initial: initial)
        let expected = ["concept-a-swipe", "concept-a-duplicates", "concept-a-large-files", "concept-a-trash",
                        "concept-a-delete-confirm", "concept-a-vault", "concept-a-vault-locked", "concept-a-later", "concept-a-later-swipe",
                        "concept-a-months", "concept-a-analysis", "concept-a-collage", "concept-a-editor", "concept-a-games", "concept-a-games-menu"]
        for name in expected { try conceptAAssertPNG(output.appendingPathComponent("screenshots/\(name).png")) }
        XCTAssertEqual(Set(shots.map { $0["file"] ?? "" }), Set((expected + ["concept-a-logo"]).map { $0 + ".png" }))
    }

    private func captureConceptAV4Vault(initial: [String: Any]) throws {
        launch("concept-a-vault")
        let fields = try conceptAV4AdvanceVaultIntro()
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

    private func conceptAV4AdvanceVaultIntro() throws -> XCUIElementQuery {
        // Real UI only. C2 returned from a delivered Next tap before two fields existed.
        // Never change the production wizard, legacy test07 or its helpers to hide that failure.
        let intro = app.staticTexts[t("vault_intro_title")].firstMatch
        let fields = app.secureTextFields
        try conceptAV4Require(intro.waitForExistence(timeout: 20) && fields.count == 0,
                             "A fresh real Vault introduction, not a reused configured vault, is required")
        var attempts: [[String: Any]] = []
        var proof: [String: Any] = ["schema": 1, "kind": "concept-a-v4-vault-ui-readiness", "status": "IN_PROGRESS",
                                    "source": "actual native Next taps and observed secure-field existence; no setup state injection",
                                    "attempts": attempts]
        try conceptAV4Write(proof, to: "concept-a-v4-vault-ui-readiness.json")
        for attempt in 0..<2 {
            let next = button("onb_next")
            try conceptAV4Require(intro.exists && fields.count == 0 && conceptAFullyVisible(next)
                                 && next.isEnabled && next.isHittable,
                                 "Retry Next only on the actual unchanged introduction, never on a partially opened code page")
            let before = try conceptAV4Still("concept-a-v4-vault-next-\(attempt + 1)-before", directory: "stills")
            let action = try conceptAV4Tap(next)
            let ready = fields.element(boundBy: 1).waitForExistence(timeout: 15)
                && fields.element(boundBy: 0).exists && fields.count == 2
            let after = try conceptAV4Still("concept-a-v4-vault-next-\(attempt + 1)-after", directory: "stills")
            attempts.append(["attempt": attempt + 1, "action": action, "beforeScreenshot": before,
                             "afterScreenshot": after, "actualSecureFieldCount": fields.count,
                             "bothFieldsExist": ready, "introStillExists": intro.exists])
            proof["attempts"] = attempts
            proof["status"] = ready ? "PASS" : "IN_PROGRESS"
            try conceptAV4Write(proof, to: "concept-a-v4-vault-ui-readiness.json")
            if ready { return fields } // No field value or recovery key is captured in this receipt.
        }
        proof["status"] = "FAIL"
        try conceptAV4Write(proof, to: "concept-a-v4-vault-ui-readiness.json")
        throw NSError(domain: "GaleriQConceptAV4", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Two real vault code fields did not appear after bounded observed-intro Next taps"])
    }

    private func conceptAV4Require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError(domain: "GaleriQConceptAV4", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func conceptAV4JSON(_ value: Any) throws -> Data {
        try conceptAV4Require(JSONSerialization.isValidJSONObject(value), "V4 evidence must contain only valid JSON primitives")
        return try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }

    private func conceptAV4Write(_ value: [String: Any], to path: String) throws {
        try conceptAV4JSON(value).write(to: output.appendingPathComponent(path), options: .atomic)
    }

    private func conceptAV4Rect(_ rect: CGRect) -> [String: Double] {
        ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
    }

    private func conceptAV4AX(_ element: XCUIElement) -> [String: Any] {
        ["identifier": element.identifier, "label": element.label, "value": element.value as? String ?? "",
         "elementType": element.elementType.rawValue, "frame": conceptAV4Rect(element.frame),
         "exists": element.exists, "enabled": element.isEnabled, "hittable": element.isHittable, "selected": element.isSelected]
    }

    private func conceptAV4SHA(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private func conceptAV4Still(_ name: String, directory: String = "stills", shot: XCUIScreenshot? = nil) throws -> String {
        let folder = output.appendingPathComponent(directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let screenshot = shot ?? XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(to: folder.appendingPathComponent(name + ".png"), options: .atomic)
        try app.debugDescription.write(to: folder.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        return directory + "/" + name + ".png"
    }

    @discardableResult
    private func conceptAV4Tap(_ element: XCUIElement) throws -> [String: Any] {
        try conceptAV4Require(element.exists && element.isHittable && element.isEnabled, "Real V4 tap unavailable: \(element)")
        let target = conceptAV4AX(element)
        let started = Date().timeIntervalSince1970
        element.tap()
        let finished = Date().timeIntervalSince1970
        pause(0.3)
        return ["action": "tap", "targetAX": target, "started": started, "finished": finished]
    }

    /// conceptAObserve has a 30s acknowledgement bound. Reserve that budget so no new request can
    /// extend a V4 render/ledger/publication poll past its 60s wall-clock budget (never an unbounded retry).
    private func conceptAV4Wait(_ checkpoint: String, until ready: ([String: Any]) -> Bool) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(60)
        var state = try conceptAObserve(checkpoint)
        while !ready(state), Date().addingTimeInterval(30.3) < deadline {
            pause(0.3)
            state = try conceptAObserve(checkpoint)
        }
        try conceptAV4Require(ready(state) && Date() <= deadline, "60s bounded real-state gate failed: \(checkpoint)")
        return state
    }

    private func conceptAV4SortedRows(_ state: [String: Any], _ key: String, excluding ids: Set<String> = []) throws -> [[String: Any]] {
        let rows = try XCTUnwrap(state[key] as? [[String: Any]], "Missing actual \(key)")
        let observedIDs = try rows.map { try XCTUnwrap($0["id"] as? String) }
        try conceptAV4Require(Set(observedIDs).count == rows.count, "Ambiguous duplicate IDs in \(key)")
        return rows.filter { !ids.contains($0["id"] as? String ?? "") }.sorted {
            ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "")
        }
    }

    /// Compare complete observed records, not just totals. Only the named extra Keep decisions may change.
    private func conceptAV4Preserved(_ before: [String: Any], _ after: [String: Any], keptIDs: Set<String>) throws {
        try conceptAV4Require(try conceptAV4JSON(conceptAV4SortedRows(before, "inventory")) ==
                             conceptAV4JSON(conceptAV4SortedRows(after, "inventory")), "V4 must not create, remove or alter PhotoKit inventory")
        let oldBasket = try XCTUnwrap(before["basketIDs"] as? [String])
        let newBasket = try XCTUnwrap(after["basketIDs"] as? [String])
        try conceptAV4Require(oldBasket.sorted() == newBasket.sorted(), "Preserve both real trash decisions")
        try conceptAV4Require(try conceptAV4JSON(conceptAV4SortedRows(before, "decisions", excluding: keptIDs)) ==
                             conceptAV4JSON(conceptAV4SortedRows(after, "decisions", excluding: keptIDs)), "Unrelated decisions/revisions/due dates must remain identical")
        let oldCount = try XCTUnwrap(before["eventCount"] as? Int)
        let newCount = try XCTUnwrap(after["eventCount"] as? Int)
        try conceptAV4Require(newCount == oldCount + keptIDs.count, "One and only one ledger event per actual upward Keep")
        let decisions = try XCTUnwrap(after["decisions"] as? [[String: Any]])
        for id in keptIDs {
            try conceptAV4Require(decisions.first { $0["id"] as? String == id }?["disposition"] as? String == "kept", "Missing committed Keep: \(id)")
        }
    }

    private func conceptAV4Month(_ key: String, in state: [String: Any]) throws -> [String: Any] {
        let rows = try XCTUnwrap(state["months"] as? [[String: Any]])
        let matches = rows.filter { $0["month"] as? String == key }
        try conceptAV4Require(matches.count == 1, "Require one actual month row for \(key)")
        return try XCTUnwrap(matches.first)
    }

    private func conceptAV4MonthStatus(_ row: [String: Any]) throws -> String {
        let total = try XCTUnwrap(row["total"] as? Int)
        let reviewed = try XCTUnwrap(row["reviewed"] as? Int)
        try conceptAV4Require(total > 0 && (0...total).contains(reviewed), "Invalid observed month progress")
        if reviewed == total { return t("month_done") }
        if reviewed == 0 { return String(format: t("month_not_started#" + (total == 1 ? "one" : "other")), Int64(total)) }
        return String(format: t("month_progress#" + (total == 1 ? "one" : "other")), Int64(reviewed), Int64(total))
    }

    private func conceptAV4MonthCell(_ row: [String: Any]) throws -> XCUIElement {
        let title = try XCTUnwrap(row["title"] as? String)
        // Use the actual observed title prefix; SwiftUI combines visible title and status on the row button.
        let cells = app.cells.containing(NSPredicate(format: "label BEGINSWITH %@", title))
        try conceptAV4Require(cells.count == 1, "Actual complete month cell must be unambiguous: \(title)")
        return cells.firstMatch
    }

    private func conceptAV4MonthPublished(_ key: String, reviewed: Int, total: Int) throws -> [String: Any] {
        try conceptAV4Wait("v4-month-published-" + key) { state in
            guard !self.e("feed.close").exists, self.app.navigationBars[self.t("months_title")].exists,
                  let months = state["months"] as? [[String: Any]],
                  let row = months.first(where: { $0["month"] as? String == key }),
                  row["reviewed"] as? Int == reviewed, row["total"] as? Int == total,
                  let title = row["title"] as? String, let status = try? self.conceptAV4MonthStatus(row) else { return false }
            let cells = self.app.cells.containing(NSPredicate(format: "label BEGINSWITH %@", title))
            guard cells.count == 1 else { return false }
            return cells.firstMatch.descendants(matching: .any).allElementsBoundByIndex.contains { $0.label.contains(status) }
                || cells.firstMatch.label.contains(status)
        }
    }

    private func conceptAV4OpenMonth(_ row: [String: Any]) throws -> [String: Any] {
        let cell = try conceptAV4MonthCell(row)
        let title = try XCTUnwrap(row["title"] as? String)
        let buttons = cell.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        try conceptAV4Require(buttons.count == 1, "Tap the real month row, not its actions menu")
        return try conceptAV4Tap(buttons.firstMatch)
    }

    private func conceptAV4Keep(_ filename: String, initial: [String: Any], baseline: [String: Any],
                               keptIDs: inout Set<String>, index: Int) throws -> [String: Any] {
        let asset = try conceptAAsset(filename, in: initial)
        let id = try XCTUnwrap(asset["id"] as? String)
        let metadata = try XCTUnwrap(asset["accessibilityValue"] as? String)
        let inventory = try XCTUnwrap(baseline["inventory"] as? [[String: Any]])
        let matches = inventory.filter { $0["accessibilityValue"] as? String == metadata }
        try conceptAV4Require(matches.count == 1 && matches.first?["id"] as? String == id,
                             "Stage identity must match exactly one actual inventory entry, never a guessed ID/dimension")
        try conceptAV4Require((asset["pixelWidth"] as? Int ?? 0) > 0 && (asset["pixelHeight"] as? Int ?? 0) > 0,
                             "Retain actual source dimensions from the initial inventory")
        let before = try conceptAV4Wait("v4-stage-before-keep-\(index)") { state in
            // C3 displayed the actual photo but SwiftUI omitted feed.media from AX.
            // Require its real assigned poster AND session readiness, not that child ID.
            guard let media = state["feedV4"] as? [String: Any], media["assetID"] as? String == id,
                  (media["isVideo"] as? Bool) == (asset["isVideo"] as? Bool),
                  media["loadState"] as? String == "ready", media["isLoaded"] as? Bool == true,
                  media["isCommitting"] as? Bool == false, media["previewState"] as? String == "ready",
                  media["sessionPreviewReady"] as? Bool == true, media["posterAssigned"] as? Bool == true,
                  (media["posterPixelWidth"] as? Int ?? 0) > 0, (media["posterPixelHeight"] as? Int ?? 0) > 0,
                  (media["posterProviderByteCount"] as? Int ?? 0) > 0,
                  let pixels = media["posterPixelDataSHA256"] as? String,
                  pixels.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { return false }
            return self.e("feed.stage").exists && self.e("feed.stage").value as? String == metadata
                && !self.e("feed.preview.loading").exists && !self.e("feed.preview.failed").exists
                && (state["inventory"] as? [[String: Any]] ?? []).contains { $0["id"] as? String == id }
        }
        let oldRows = try XCTUnwrap(before["decisions"] as? [[String: Any]])
        try conceptAV4Require(oldRows.first { $0["id"] as? String == id }?["disposition"] as? String == nil
                             || oldRows.first { $0["id"] as? String == id }?["disposition"] as? String == "undecided", "Only review a genuinely undecided asset")
        let stageAX = conceptAV4AX(e("feed.stage"))
        let prefix = String(format: "concept-a-v4-month-keep-%02d", index)
        let beforeScreen = try conceptAV4Still(prefix + "-before")
        let started = Date().timeIntervalSince1970
        // Raw genuine gesture: the last asset cannot advance feedPosition, so swipeFeed is intentionally NOT used.
        e("feed.stage").swipeUp()
        let finished = Date().timeIntervalSince1970
        keptIDs.insert(id)
        let expectedIDs = keptIDs
        let after = try conceptAV4Wait("v4-committed-keep-\(index)") { state in
            let rows = state["decisions"] as? [[String: Any]] ?? []
            return expectedIDs.allSatisfy { id in rows.contains { $0["id"] as? String == id && $0["disposition"] as? String == "kept" } }
                && state["eventCount"] as? Int == (baseline["eventCount"] as? Int ?? -1) + expectedIDs.count
        }
        let afterScreen = try conceptAV4Still(prefix + "-after")
        try conceptAV4Preserved(baseline, after, keptIDs: keptIDs)
        return ["action": "feed.stage.swipeUp", "filename": filename, "assetID": id, "asset": asset,
                "stageAX": stageAX, "identityMatchCount": matches.count, "identityMethod": "unique actual AX date/type/duration in complete PhotoKit inventory; dimensions from matched initial asset",
                "started": started, "finished": finished, "before": before, "after": after,
                "feedObservation": try XCTUnwrap(before["feedV4"] as? [String: Any]),
                "beforeScreenshot": beforeScreen, "afterScreenshot": afterScreen]
    }

    private func conceptAV4MonthGeometry(_ keys: [String], roles: [String]) throws -> [String: Any] {
        let screen = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage)
        try conceptAV4Require(screen.width == 1206 && screen.height == 2622, "V4 crop gate is pinned to the actual medium iPhone source")
        let scale = CGFloat(screen.width) / app.frame.width
        let crop = CGRect(x: app.frame.minX, y: app.frame.minY, width: app.frame.width, height: 2263 / scale)
        for attempt in 0..<8 {
            let state = try conceptAObserve("v4-month-viewport-\(attempt)")
            let box = try XCTUnwrap(state["nativeListViewport"] as? [String: Double])
            var viewport = CGRect(x: try XCTUnwrap(box["x"]), y: try XCTUnwrap(box["y"]),
                                  width: try XCTUnwrap(box["width"]), height: try XCTUnwrap(box["height"]))
            let adjustedViewport = viewport
            for header in app.staticTexts.matching(NSPredicate(format: "label MATCHES '^[0-9]{4}$'")).allElementsBoundByIndex {
                let frame = header.frame
                if frame.minY <= viewport.minY + 1 && frame.maxY > viewport.minY {
                    let bottom = viewport.maxY
                    viewport.origin.y = frame.maxY
                    viewport.size.height = max(0, bottom - frame.maxY)
                }
            }
            viewport = viewport.intersection(app.frame).intersection(crop)
            try conceptAV4Require(!viewport.isEmpty && !viewport.isNull, "Real adjusted list viewport must intersect the common phone crop")
            var rows: [[String: Any]] = []
            var union = CGRect.null
            for (index, key) in keys.enumerated() {
                let row = try conceptAV4Month(key, in: state)
                let title = try XCTUnwrap(row["title"] as? String)
                let cells = app.cells.containing(NSPredicate(format: "label BEGINSWITH %@", title))
                guard cells.count == 1 else { continue }
                let cell = cells.firstMatch
                let menu = cell.buttons[String(format: t("month_actions"), title)].firstMatch
                guard menu.exists, !cell.frame.isEmpty else { continue }
                union = union.union(cell.frame).union(menu.frame)
                let status = try conceptAV4MonthStatus(row)
                let labels = ([cell.label] + cell.descendants(matching: .any).allElementsBoundByIndex.map(\.label)).joined(separator: "\n")
                guard viewport.contains(cell.frame), viewport.contains(menu.frame), menu.isHittable, labels.contains(status) else { continue }
                var record = row
                record["role"] = roles[index]
                record["visibleStatus"] = status
                record["actualAXText"] = labels
                record["cellAX"] = conceptAV4AX(cell)
                record["menuAX"] = conceptAV4AX(menu)
                record["cellNativeFrame"] = conceptAV4Rect(CGRect(x: (cell.frame.minX - app.frame.minX) * scale,
                    y: (cell.frame.minY - app.frame.minY) * scale, width: cell.frame.width * scale, height: cell.frame.height * scale))
                record["menuNativeFrame"] = conceptAV4Rect(CGRect(x: (menu.frame.minX - app.frame.minX) * scale,
                    y: (menu.frame.minY - app.frame.minY) * scale, width: menu.frame.width * scale, height: menu.frame.height * scale))
                rows.append(record)
            }
            if rows.count == keys.count {
                return ["nativeListViewport": conceptAV4Rect(adjustedViewport), "unobscuredViewport": conceptAV4Rect(viewport),
                        "screenAXFrame": conceptAV4Rect(app.frame), "screenPixels": [screen.width, screen.height],
                        "commonPhoneNativeVisibleRect": [0, 0, screen.width, 2263], "nativeVisibleYMax": 2263,
                        "completeCellsAndMenus": rows.count, "scrollAttempts": attempt, "rows": rows]
            }
            if !union.isNull { try conceptAV4Require(union.height <= viewport.height, "Three complete rows cannot fit; do not shrink or manufacture them") }
            let shift: CGFloat = union.isNull ? -36 : (union.minY < viewport.minY ? viewport.minY + 6 - union.minY : viewport.maxY - 6 - union.maxY)
            let list = app.collectionViews.firstMatch
            try conceptAV4Require(list.exists && list.isHittable, "Real months list must accept a bounded user scroll")
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.55))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: max(-80, min(80, shift)))))
            pause(0.3)
        }
        throw NSError(domain: "GaleriQConceptAV4", code: 2, userInfo: [NSLocalizedDescriptionKey: "Three complete native status cells and menus did not fit above native Y=2263 after eight real scrolls"])
    }

    private func captureConceptAV4Months(initial: [String: Any]) throws {
        launch("concept-a-months")
        let before = try conceptAObserve("v4-months-before-additional-keeps")
        let initialInventory = try XCTUnwrap(initial["inventory"] as? [[String: Any]])
        let inventory = try XCTUnwrap(before["inventory"] as? [[String: Any]])
        let removed = Set(try (1...5).map { try conceptAID(String(format: "CA_30_pretty_%02d.jpg", $0), in: initial) })
        try conceptAV4Require(Set(inventory.compactMap { $0["id"] as? String }) ==
                             Set(initialInventory.compactMap { $0["id"] as? String }).subtracting(removed), "Only test07's real five vault-original removals may precede V4")
        try conceptAV4Require(try conceptAV4JSON(conceptAV4SortedRows(initial, "inventory", excluding: removed)) ==
                             conceptAV4JSON(conceptAV4SortedRows(before, "inventory")), "All surviving initial filenames, dates, media types and dimensions must remain unchanged")
        let rows = try XCTUnwrap(before["months"] as? [[String: Any]])
        let keys = rows.compactMap { $0["month"] as? String }.sorted(by: >).prefix(3)
        try conceptAV4Require(Array(keys) == ["2026-11", "2026-10", "2026-09"], "Preserve the actual top-three metadata month roles")
        for (key, total) in [("2026-10", 2), ("2026-11", 3), ("2026-09", 8)] {
            let row = try conceptAV4Month(key, in: before)
            try conceptAV4Require(row["total"] as? Int == total && row["reviewed"] as? Int == 0 && row["later"] as? Int == 0, "Unexpected genuine post-vault baseline for \(key)")
            _ = try conceptAV4MonthPublished(key, reviewed: 0, total: total)
        }
        var proof: [String: Any] = ["schema": 1, "kind": "concept-a-v4-month-progress", "status": "IN_PROGRESS",
                                    "initialInventory": initialInventory, "before": before, "actions": [[String: Any]](),
                                    "navigationActions": [[String: Any]](), "source": "screenshots/concept-a-v4-months.png"]
        try conceptAV4Write(proof, to: "month-progress-proof.json")
        var actions: [[String: Any]] = []
        var navigation: [[String: Any]] = []
        var keptIDs: Set<String> = []
        navigation.append(try conceptAV4OpenMonth(conceptAV4Month("2026-10", in: before)))
        for filename in ["CA_30_pretty_14.jpg", "CA_02_clutter_shake.jpg"] {
            actions.append(try conceptAV4Keep(filename, initial: initial, baseline: before, keptIDs: &keptIDs, index: actions.count + 1))
            proof["actions"] = actions; proof["navigationActions"] = navigation
            try conceptAV4Write(proof, to: "month-progress-proof.json")
        }
        navigation.append(try conceptAV4Tap(e("feed.close"))) // Real close: permit the production MonthsView task to recount.
        let complete = try conceptAV4MonthPublished("2026-10", reviewed: 2, total: 2)
        proof["afterCompleteMonth"] = complete
        navigation.append(try conceptAV4OpenMonth(conceptAV4Month("2026-11", in: complete)))
        actions.append(try conceptAV4Keep("CA_40_large_02.mp4", initial: initial, baseline: before, keptIDs: &keptIDs, index: 3))
        proof["actions"] = actions; proof["navigationActions"] = navigation
        try conceptAV4Write(proof, to: "month-progress-proof.json")
        navigation.append(try conceptAV4Tap(e("feed.close")))
        let after = try conceptAV4MonthPublished("2026-11", reviewed: 1, total: 3)
        _ = try conceptAV4MonthPublished("2026-10", reviewed: 2, total: 2)
        _ = try conceptAV4MonthPublished("2026-09", reviewed: 0, total: 8)
        try conceptAV4Preserved(before, after, keptIDs: keptIDs)
        let oldMonths = rows.filter { !["2026-10", "2026-11"].contains($0["month"] as? String ?? "") }
        let newMonths = try XCTUnwrap(after["months"] as? [[String: Any]]).filter { !["2026-10", "2026-11"].contains($0["month"] as? String ?? "") }
        try conceptAV4Require(try conceptAV4JSON(oldMonths) == conceptAV4JSON(newMonths), "Every unrelated month, including untouched September, must remain identical")
        let geometry = try conceptAV4MonthGeometry(["2026-11", "2026-10", "2026-09"], roles: ["partial", "complete", "untouched"])
        let shot = XCUIScreen.main.screenshot()
        snap("concept-a-v4-months", settle: 0, captured: shot) // Never overwrite concept-a-months.png.
        proof["status"] = "PASS"; proof["after"] = after; proof["geometry"] = geometry
        proof["navigationActions"] = navigation; proof["actionFiles"] = actions.compactMap { $0["filename"] as? String }
        proof["actionAssetIDs"] = actions.compactMap { $0["assetID"] as? String }; proof["keptAssetIDs"] = keptIDs.sorted()
        proof["screenshotSHA256"] = conceptAV4SHA(shot.pngRepresentation)
        proof["preservation"] = ["inventoryUnchanged": true, "basketIDsUnchanged": true, "unrelatedDecisionsUnchanged": true,
                                  "unrelatedMonthsUnchanged": true, "additionalLedgerEvents": keptIDs.count]
        try conceptAV4Write(proof, to: "month-progress-proof.json")
    }

    /// Compare only the agreed publication schema. Extra read-only diagnostics (for example the selected
    /// tool) legitimately change between Filters and Adjust and must not masquerade as a new render.
    private func conceptAV4EditorCore(_ observation: [String: Any]) throws -> [String: Any] {
        let keys = ["assetID", "loadState", "originalReady", "previewReady", "rendering", "requestedRecipeHash",
                    "publishedRecipeHash", "renderGeneration", "publishedRenderGeneration", "publishedFilter",
                    "publishedFilterStrength", "publishedIsIdentity", "sourceOriginalPixelSHA256", "publishedPreviewPixelSHA256"]
        var core: [String: Any] = [:]
        for key in keys { core[key] = try XCTUnwrap(observation[key], "Missing actual editorV4.\(key)") }
        return core
    }

    private func conceptAV4EditorReady(_ checkpoint: String, assetID: String, identity: Bool, filter: String,
                                      recipeHash: String? = nil, pixelHash: String? = nil) throws -> [String: Any] {
        let state = try conceptAV4Wait(checkpoint) { state in
            guard let editor = state["editorV4"] as? [String: Any], editor["assetID"] as? String == assetID,
                  editor["loadState"] as? String == "ready", editor["originalReady"] as? Bool == true,
                  editor["previewReady"] as? Bool == true, editor["rendering"] as? Bool == false,
                  let requested = editor["requestedRecipeHash"] as? String,
                  let published = editor["publishedRecipeHash"] as? String, requested == published,
                  let generation = editor["renderGeneration"] as? Int, generation >= 0,
                  editor["publishedRenderGeneration"] as? Int == generation,
                  editor["publishedIsIdentity"] as? Bool == identity, editor["publishedFilter"] as? String == filter,
                  let original = editor["sourceOriginalPixelSHA256"] as? String,
                  let preview = editor["publishedPreviewPixelSHA256"] as? String else { return false }
            let hashes = [requested, published, original, preview]
            guard hashes.allSatisfy({ $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }),
                  !identity || original == preview,
                  identity || (editor["publishedFilterStrength"] as? Double == 1 && original != preview),
                  recipeHash == nil || published == recipeHash, pixelHash == nil || preview == pixelHash else { return false }
            return self.e("editor.stage").exists && !self.e("editor.preview.rendering").exists
        }
        return try conceptAV4EditorCore(XCTUnwrap(state["editorV4"] as? [String: Any]))
    }

    /// Canonical actual screenshot pixel buffer, not a re-encoded PNG/claimed rendering flag.
    private func conceptAV4PixelSHA(_ image: CGImage, rect: CGRect) throws -> String {
        let crop = try XCTUnwrap(image.cropping(to: rect))
        var pixels = Data(count: crop.width * crop.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                          bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return true
        }
        try conceptAV4Require(drawn, "Must decode the actual saved screenshot photo pixels")
        return conceptAV4SHA(pixels)
    }

    private func conceptAV4EditorShot(_ name: String, asset: [String: Any], editor: [String: Any], tool: String) throws -> [String: Any] {
        let stage = e("editor.stage")
        let frame = stage.frame
        try conceptAV4Require(stage.exists && !frame.isEmpty && app.frame.contains(frame) && e("editor.tool." + tool).isSelected,
                             "Actual selected tool and complete editor.stage must be visible")
        let width = CGFloat(try XCTUnwrap(asset["pixelWidth"] as? Int))
        let height = CGFloat(try XCTUnwrap(asset["pixelHeight"] as? Int))
        try conceptAV4Require(width > 0 && height > 0, "Photo fit must derive from actual original dimensions")
        let fit = min(frame.width / width, frame.height / height)
        let photo = CGRect(x: frame.midX - width * fit / 2, y: frame.midY - height * fit / 2, width: width * fit, height: height * fit)
        var samples: [[String: Any]] = []
        var lastHash = ""
        var finalShot: XCUIScreenshot?
        var nativeRect = CGRect.zero
        // Two consecutive immutable native stills must agree in the real aspect-fit photo area.
        for index in 0..<6 {
            let started = Date().timeIntervalSince1970
            let shot = XCUIScreen.main.screenshot()
            let finished = Date().timeIntervalSince1970
            let image = try XCTUnwrap(shot.image.cgImage)
            let scale = CGFloat(image.width) / app.frame.width
            nativeRect = CGRect(x: (photo.minX - app.frame.minX) * scale, y: (photo.minY - app.frame.minY) * scale,
                                width: photo.width * scale, height: photo.height * scale).insetBy(dx: 2, dy: 2).integral
            try conceptAV4Require(CGRect(x: 0, y: 0, width: image.width, height: image.height).contains(nativeRect) && !nativeRect.isEmpty,
                                 "Actual fitted photo crop must remain within its native screenshot")
            let hash = try conceptAV4PixelSHA(image, rect: nativeRect)
            let path = try conceptAV4Still(name + "-stability-\(index)", shot: shot)
            samples.append(["file": path, "captureStarted": started, "captureFinished": finished,
                            "photoPixelSHA256": hash, "screenshotSHA256": conceptAV4SHA(shot.pngRepresentation)])
            if hash == lastHash { finalShot = shot; break }
            lastHash = hash
            pause(0.35)
        }
        let shot = try XCTUnwrap(finalShot, "Actual photo area did not become stable in six real stills")
        try conceptAV4Require(stage.frame == frame, "Editor stage geometry changed while capturing")
        let observed = try conceptAObserve(name + "-capture-readback")
        let observation = try XCTUnwrap(observed["editorV4"] as? [String: Any])
        let readback = try conceptAV4EditorCore(observation)
        try conceptAV4Require(try conceptAV4JSON(editor) == conceptAV4JSON(readback), "Published source/recipe/generation changed during the actual still pair")
        snap(name, settle: 0, captured: shot)
        return ["file": "screenshots/" + name + ".png", "screenshotSHA256": conceptAV4SHA(shot.pngRepresentation),
                "photoPixelSHA256": try XCTUnwrap(samples.last?["photoPixelSHA256"] as? String),
                "editorV4": readback, "editorObservation": observation, "stageAX": conceptAV4AX(stage), "photoAXFrame": conceptAV4Rect(photo),
                "photoNativeFrame": conceptAV4Rect(nativeRect), "selectedToolAX": conceptAV4AX(e("editor.tool." + tool)),
                "undoAX": conceptAV4AX(e("editor.undo")), "redoAX": conceptAV4AX(e("editor.redo")),
                "stability": ["method": "two consecutive real native photo-area RGBA8 pixel hashes", "samples": samples, "consecutiveEqualSamples": 2]]
    }

    private func captureConceptAV4Editor(initial: [String: Any]) throws {
        let asset = try conceptAAsset("CA_30_pretty_08.jpg", in: initial)
        let id = try XCTUnwrap(asset["id"] as? String)
        let baseline = try conceptAObserve("v4-editor-inventory-before")
        launch("concept-a-editor") // Existing native route constructs a fresh EditorModel for the SAME real source.
        var actions: [[String: Any]] = []
        var checkpoints: [String: Any] = [:]
        var proof: [String: Any] = ["schema": 1, "kind": "concept-a-v4-editor-pair", "status": "IN_PROGRESS",
                                    "assetID": id, "filename": "CA_30_pretty_08.jpg", "asset": asset,
                                    "beforeState": baseline, "matchedTool": "adjust", "actions": actions, "checkpoints": checkpoints]
        try conceptAV4Write(proof, to: "editor-pair-proof.json")
        let original = try conceptAV4EditorReady("v4-editor-original-loaded", assetID: id, identity: true, filter: "original")
        actions.append(try conceptAV4Tap(e("editor.tool.adjust")))
        let before = try conceptAV4EditorReady("v4-editor-original-adjust", assetID: id, identity: true, filter: "original")
        let selection = try XCTUnwrap(try conceptAObserve("v4-editor-same-original")["selection"] as? [String: Any])
        try conceptAV4Require(selection["assetIDs"] as? [String] == [id] && selection["sourceFiles"] as? [String] == ["CA_30_pretty_08.jpg"], "Native editor route must select exactly the inventoried original")
        // The real default tool is Crop. Switching to Adjust legitimately republishes an
        // identical identity image, so compare actual recipe/pixels and allow that real generation.
        let originalStable = ["assetID", "requestedRecipeHash", "publishedRecipeHash", "publishedIsIdentity",
                              "sourceOriginalPixelSHA256", "publishedPreviewPixelSHA256"]
        for key in originalStable {
            try conceptAV4Require(try conceptAV4JSON([key: try XCTUnwrap(original[key])]) ==
                                  conceptAV4JSON([key: try XCTUnwrap(before[key])]), "Selecting Adjust must preserve identity recipe/pixels: \(key)")
        }
        try conceptAV4Require((before["renderGeneration"] as? Int ?? -1) >= (original["renderGeneration"] as? Int ?? 0),
                              "The real Crop-to-Adjust publication generation must not go backwards")
        try conceptAV4Require(!e("editor.undo").isEnabled && !e("editor.redo").isEnabled, "Require a fresh unedited model, not test07's Warm history")
        checkpoints["before"] = try conceptAV4EditorShot("concept-a-v4-editor-before", asset: asset, editor: before, tool: "adjust")
        proof["checkpoints"] = checkpoints; proof["actions"] = actions
        try conceptAV4Write(proof, to: "editor-pair-proof.json")

        actions.append(try conceptAV4Tap(e("editor.tool.filter")))
        _ = try conceptAV4Wait("v4-editor-filter-thumbnails") { _ in self.e("editor.filter.thumbnail.NONE").exists }
        let warm = button("edit_filter_warm")
        actions.append(try conceptAV4Tap(warm)) // No recipe, exposure or filter-strength injection.
        let filtered = try conceptAV4EditorReady("v4-editor-warm-published", assetID: id, identity: false, filter: "warm")
        let strength = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == '100'", t("edit_filter_strength"))).firstMatch
        try conceptAV4Require(warm.isSelected && strength.exists && conceptAFullyVisible(strength), "The actual selected Warm filter and native Strength=100 must be visible")
        var filterScreen = try conceptAV4EditorShot("concept-a-v4-editor-filter-selected", asset: asset, editor: filtered, tool: "filter")
        filterScreen["warmAX"] = conceptAV4AX(warm); filterScreen["strengthAX"] = conceptAV4AX(strength)
        checkpoints["filterSelection"] = filterScreen
        actions.append(try conceptAV4Tap(e("editor.tool.adjust")))
        let after = try conceptAV4EditorReady("v4-editor-warm-matched-adjust", assetID: id, identity: false, filter: "warm")
        try conceptAV4Require(try conceptAV4JSON(filtered) == conceptAV4JSON(after), "Return to matched Adjust layout without changing the applied recipe")
        try conceptAV4Require(after["sourceOriginalPixelSHA256"] as? String == before["sourceOriginalPixelSHA256"] as? String
                             && after["publishedRecipeHash"] as? String != before["publishedRecipeHash"] as? String
                             && (after["renderGeneration"] as? Int ?? -1) > (before["renderGeneration"] as? Int ?? -1), "Warm must publish a genuinely new render of the same original")
        try conceptAV4Require(e("editor.undo").isEnabled && !e("editor.redo").isEnabled, "The genuine Warm edit must enable Undo only")
        let afterScreen = try conceptAV4EditorShot("concept-a-v4-editor-after", asset: asset, editor: after, tool: "adjust")
        let beforeScreen = try XCTUnwrap(checkpoints["before"] as? [String: Any])
        try conceptAV4Require(try conceptAV4JSON(beforeScreen["stageAX"] as? [String: Any] ?? [:]) ==
                             conceptAV4JSON(afterScreen["stageAX"] as? [String: Any] ?? [:]), "Before/after editor.stage AX frame and layout must match")
        try conceptAV4Require(try conceptAV4JSON(beforeScreen["photoNativeFrame"] as? [String: Any] ?? [:]) ==
                             conceptAV4JSON(afterScreen["photoNativeFrame"] as? [String: Any] ?? [:]), "Matched comparison must show precisely the same native photo rectangle")
        try conceptAV4Require(beforeScreen["photoPixelSHA256"] as? String != afterScreen["photoPixelSHA256"] as? String,
                             "Warm must also change the actual captured photo pixels, not just the observed model")
        checkpoints["after"] = afterScreen
        proof["checkpoints"] = checkpoints; proof["actions"] = actions
        try conceptAV4Write(proof, to: "editor-pair-proof.json")

        actions.append(try conceptAV4Tap(e("editor.undo")))
        let undo = try conceptAV4EditorReady("v4-editor-real-undo", assetID: id, identity: true, filter: "original",
            recipeHash: before["publishedRecipeHash"] as? String, pixelHash: before["publishedPreviewPixelSHA256"] as? String)
        try conceptAV4Require(undo["sourceOriginalPixelSHA256"] as? String == before["sourceOriginalPixelSHA256"] as? String
                             && (undo["renderGeneration"] as? Int ?? -1) > (after["renderGeneration"] as? Int ?? -1)
                             && !e("editor.undo").isEnabled && e("editor.redo").isEnabled, "Actual Undo must restore original pixels/identity and enable Redo")
        let undoScreen = try conceptAV4EditorShot("concept-a-v4-editor-undo", asset: asset, editor: undo, tool: "adjust")
        try conceptAV4Require(undoScreen["photoPixelSHA256"] as? String == beforeScreen["photoPixelSHA256"] as? String,
                             "The actual Undo still must restore the original comparison photo pixels")
        checkpoints["undo"] = undoScreen
        proof["checkpoints"] = checkpoints; proof["actions"] = actions
        try conceptAV4Write(proof, to: "editor-pair-proof.json")
        actions.append(try conceptAV4Tap(e("editor.redo")))
        let redo = try conceptAV4EditorReady("v4-editor-real-redo", assetID: id, identity: false, filter: "warm",
            recipeHash: after["publishedRecipeHash"] as? String, pixelHash: after["publishedPreviewPixelSHA256"] as? String)
        try conceptAV4Require(redo["sourceOriginalPixelSHA256"] as? String == before["sourceOriginalPixelSHA256"] as? String
                             && (redo["renderGeneration"] as? Int ?? -1) > (undo["renderGeneration"] as? Int ?? -1)
                             && e("editor.undo").isEnabled && !e("editor.redo").isEnabled, "Actual Redo must restore Warm pixels/recipe and enable Undo")
        let redoScreen = try conceptAV4EditorShot("concept-a-v4-editor-redo", asset: asset, editor: redo, tool: "adjust")
        try conceptAV4Require(redoScreen["photoPixelSHA256"] as? String == afterScreen["photoPixelSHA256"] as? String,
                             "The actual Redo still must restore the Warm comparison photo pixels")
        checkpoints["redo"] = redoScreen
        proof["checkpoints"] = checkpoints; proof["actions"] = actions
        try conceptAV4Write(proof, to: "editor-pair-proof.json")

        let save = button("save")
        try conceptAV4Require(save.identifier != "editor.save.confirm", "Open only the real editor header Save, never execute an export")
        actions.append(try conceptAV4Tap(save))
        let bar = app.navigationBars[t("edit_save_title")].firstMatch
        _ = try conceptAV4Wait("v4-editor-real-save-options") { _ in bar.exists && self.e("editor.save.confirm").exists }
        let options = [button("edit_save_copy"), button("edit_save_replace"), button("edit_save_original")]
        for _ in 0..<2 {
            if options.allSatisfy(conceptAFullyVisible) { break }
            let target = conceptAV4AX(bar)
            let started = Date().timeIntervalSince1970
            // Expand the actual medium native sheet by its real navigation bar; never change a presentation detent in code.
            bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
            actions.append(["action": "native save sheet expand drag", "targetAX": target,
                            "started": started, "finished": Date().timeIntervalSince1970])
            pause(0.4)
        }
        try conceptAV4Require(options.allSatisfy(conceptAFullyVisible) && options[0].isSelected
                             && !options[1].isSelected && !options[2].isSelected, "Copy must be the untouched real default; Replace and Edit original must be visibly unselected")
        try conceptAV4Require(e("editor.save.confirm").label == t("edit_save_copy_action"), "Real confirmation action must still say Save copy")
        let copyShot = XCUIScreen.main.screenshot()
        snap("concept-a-v4-editor-copy-default", settle: 0, captured: copyShot)
        checkpoints["copyDefault"] = ["file": "screenshots/concept-a-v4-editor-copy-default.png",
            "screenshotSHA256": conceptAV4SHA(copyShot.pngRepresentation), "underlyingEditorCheckpoint": "redo",
            "optionsAX": options.map(conceptAV4AX), "confirmationAX": conceptAV4AX(e("editor.save.confirm")),
            "defaultSelectionUntouched": true, "saveExecuted": false]
        proof["checkpoints"] = checkpoints; proof["actions"] = actions
        try conceptAV4Write(proof, to: "editor-pair-proof.json")
        actions.append(try conceptAV4Tap(bar.buttons[t("cancel")].firstMatch))
        let final = try conceptAV4Wait("v4-editor-save-options-cancelled") { _ in !bar.exists && self.e("editor.stage").exists }
        try conceptAV4Preserved(baseline, final, keptIDs: [])
        let cancelled = try conceptAV4EditorReady("v4-editor-warm-after-save-cancel", assetID: id, identity: false, filter: "warm",
            recipeHash: after["publishedRecipeHash"] as? String, pixelHash: after["publishedPreviewPixelSHA256"] as? String)
        try conceptAV4Require(try conceptAV4JSON(redo) == conceptAV4JSON(cancelled), "Cancelling save options must not edit or republish the photo")
        proof["status"] = "PASS"; proof["actions"] = actions; proof["afterState"] = final
        proof["sourceOriginalPixelSHA256"] = before["sourceOriginalPixelSHA256"]
        proof["beforePreviewPixelSHA256"] = before["publishedPreviewPixelSHA256"]
        proof["afterPreviewPixelSHA256"] = after["publishedPreviewPixelSHA256"]
        proof["beforeRecipeHash"] = before["publishedRecipeHash"]; proof["afterRecipeHash"] = after["publishedRecipeHash"]
        proof["saveCancelled"] = true; proof["noAssetCreated"] = true
        proof["preservation"] = ["inventoryUnchanged": true, "basketIDsUnchanged": true, "allDecisionsUnchanged": true, "additionalLedgerEvents": 0]
        try conceptAV4Write(proof, to: "editor-pair-proof.json")
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
        let captureBounds = app.frame
        tap(app.buttons[removeTitle].firstMatch)
        let confirm = String(format: t("basket_confirm_media_action"), Int64(2))
        tap(app.buttons[confirm].firstMatch) // App confirmation first; the following one must belong to SpringBoard.
        let alert = try conceptASystemDeleteAlert(expectedCount: 2)
        XCTAssertEqual(state["reduceTransparency"] as? Bool, true)
        // Wait for the real PhotoKit photo preview and the actual alert animation.
        // Keep the original native pixels; the app's legitimate busy spinner below
        // the dialog is excluded only by the user's common bottom-cropped phone.
        pause(3)
        let dialogFrame = alert.frame
        var settled = XCUIScreen.main.screenshot()
        let image = try XCTUnwrap(settled.image.cgImage)
        let scale = CGFloat(image.width) / captureBounds.width
        let nativeRect = CGRect(x: (dialogFrame.minX - captureBounds.minX) * scale,
                                y: (dialogFrame.minY - captureBounds.minY) * scale,
                                width: dialogFrame.width * scale, height: dialogFrame.height * scale).integral
        XCTAssertTrue(CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)).contains(nativeRect))
        XCTAssertLessThan(nativeRect.width, CGFloat(image.width) * 0.95, "Use the actual alert frame, not its whole host screen")
        func cropPNG(_ shot: XCUIScreenshot) throws -> Data {
            let cg = try XCTUnwrap(shot.image.cgImage)
            let crop = try XCTUnwrap(cg.cropping(to: nativeRect))
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, crop, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return data as Data
        }
        var previousPNG = try cropPNG(settled)
        var previousShot = settled
        var consecutiveStable = 0
        for _ in 0..<16 {
            pause(0.5)
            let candidate = XCUIScreen.main.screenshot()
            let candidatePNG = try cropPNG(candidate)
            consecutiveStable = candidatePNG == previousPNG ? consecutiveStable + 1 : 0
            previousShot = settled
            settled = candidate
            previousPNG = candidatePNG
            if consecutiveStable >= 3 { break }
        }
        XCTAssertGreaterThanOrEqual(consecutiveStable, 3, "Actual system dialog/photo crop must stop changing before capture")
        try previousShot.pngRepresentation.write(to: output.appendingPathComponent("stills/concept-a-delete-confirm-before.png"), options: .atomic)
        let dialogProof: [String: Any] = ["nativeRect": [Int(nativeRect.minX), Int(nativeRect.minY), Int(nativeRect.maxX), Int(nativeRect.maxY)],
                                         "screenPixels": [image.width, image.height], "consecutiveStableSamples": consecutiveStable,
                                         "reduceTransparency": state["reduceTransparency"] as? Bool ?? false,
                                         "previousSource": "stills/concept-a-delete-confirm-before.png",
                                         "finalSource": "screenshots/concept-a-delete-confirm.png",
                                         "appBusyIndicatorRetouched": false]
        try JSONSerialization.data(withJSONObject: dialogProof, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("concept-a-delete-confirm-frame.json"), options: .atomic)
        snap("concept-a-delete-confirm", settle: 0, captured: settled)
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

    private func captureConceptAGames() throws {
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
        snap("concept-a-games-menu") // Preserve all three real cards as additional evidence.
        tap(e("games.memory"))
        tap(e("memory.startPhotos"))
        XCTAssertTrue(e("memory.card.0").waitForExistence(timeout: 45))
        let board = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'memory.card.'"))
        XCTAssertEqual(board.count, 24)
        let unseen = board.allElementsBoundByIndex.map(\.identifier)
        var known: [String: [String]] = [:]
        var solved: Set<String> = []
        // Only learn a card's identity AFTER an ordinary user tap reveals it.
        // Same real-play algorithm as the legacy preview, without its fixture route.
        for cardID in unseen {
            if solved.count >= 6 { break }
            if solved.contains(cardID) { continue }
            let card = app.buttons[cardID]
            if card.isEnabled { card.tap() }
            var number = photoNumber(card)
            if number.isEmpty {
                pause(1.4); card.tap(); number = photoNumber(card)
            }
            XCTAssertFalse(number.isEmpty, "Never inspect a hidden card/deck or inject matches")
            if known[number]?.contains(cardID) != true { known[number, default: []].append(cardID) }
            if let pair = known[number], pair.count == 2 {
                let first = app.buttons[pair[0]], second = app.buttons[pair[1]]
                if first.isEnabled { first.tap() }
                if second.isEnabled { second.tap() }
                XCTAssertTrue((first.value as? String ?? "").hasPrefix(t("memory_matched")))
                XCTAssertTrue((second.value as? String ?? "").hasPrefix(t("memory_matched")))
                solved.formUnion(pair); known.removeValue(forKey: number)
            } else { pause(1.4) }
        }
        XCTAssertGreaterThanOrEqual(solved.count, 6)
        XCTAssertFalse(e("memory.finished").exists, "No fake victory or best result")
        pause(2)
        let roundProof: [String: Any] = ["cardCount": board.count, "matchedCardIDs": solved.sorted(),
                                        "matchedPrefix": t("memory_matched"),
                                        "matchedValues": solved.sorted().map { app.buttons[$0].value as? String ?? "" },
                                        "finished": e("memory.finished").exists, "source": "actual library-photo round through native taps"]
        try JSONSerialization.data(withJSONObject: roundProof, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("concept-a-games-round.json"), options: .atomic)
        snap("concept-a-games") // A genuine, filled photo board instead of a half-empty menu.
        tap(e("memory.close"))
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
