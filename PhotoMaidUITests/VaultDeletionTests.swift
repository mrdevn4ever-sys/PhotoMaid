import XCTest

/// Echte Tresor-Persistenz mit synthetischen PhotoKit-Medien und eigenen QA-Dateien.
/// Ausschließlich die SYSTEM-Löschabfrage beim Import wird abgebrochen; Tresor-Aktionen sind explizit.
@MainActor
final class VaultDeletionTests: XCTestCase {
    private var app: XCUIApplication!
    private let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let trashTitle = "In den Tresor-Papierkorb"

    override func setUp() async throws {
        continueAfterFailure = false
        installPermissionMonitor()
        app = XCUIApplication()
        app.launchArguments = ["-qa-fixtures", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
        app.launch()
        finishIntroduction(in: app, prefix: "vault_delete_intro")
        let skip = app.buttons["Tutorial überspringen"].firstMatch
        if skip.waitForExistence(timeout: 1) { tap(skip, "tour_skipped") }
        openVault()
    }

    override func tearDown() async throws {
        if let app { snap("end_" + name); app.terminate() }
    }

    private func snap(_ name: String) {
        Thread.sleep(forTimeInterval: 0.6) // Keep completed iOS sheet/list transitions in the evidence.
        checkpoint("vault_delete_" + name, app: app)
    }
    private func tap(_ element: XCUIElement, _ name: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), name)
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, name)
        element.tap()
        snap(name)
    }
    private func gone(_ element: XCUIElement) {
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)], timeout: 8) == .completed)
    }
    private func items(_ scope: String) -> [XCUIElement] {
        // Keep item identity after a row moves/disappears; an index-bound
        // element otherwise silently starts referring to the next row.
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "vault.\(scope).item.")).allElementsBoundByIndex
            .map { app.buttons[$0.identifier] }
    }
    private func id(_ item: XCUIElement) -> String { item.identifier.components(separatedBy: ".").last! }
    private func select(_ scope: String) -> XCUIElement { app.buttons["vault.\(scope).select"] }
    private func openVault() {
        app.revealTabBar(); tap(app.pmTab("Heute"), "today")
        tap(app.buttons["Einstellungen"].firstMatch, "settings")
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Privater Tresor'")).firstMatch
        tap(entry, "open")
        if app.vaultKeypad.waitForExistence(timeout: 2) {
            app.enterVaultPIN("628491"); snap("pin")
        } else {
            tap(app.buttons["Weiter"], "setup_intro")
            let fields = app.secureTextFields
            XCTAssertEqual(fields.count, 2)
            fields.element(boundBy: 0).tap(); fields.element(boundBy: 0).typeText("628491")
            fields.element(boundBy: 1).tap(); fields.element(boundBy: 1).typeText("628491")
            snap("setup_pin")
            tap(app.buttons["Weiter"], "setup_code")
            let face = app.switches.matching(NSPredicate(format: "label CONTAINS 'Face ID'")).firstMatch
            if face.exists {
                if face.value as? String == "1" { face.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
                XCTAssertEqual(face.value as? String, "0")
                tap(app.buttons["Weiter"], "setup_face_off")
            }
            tap(app.buttons["Ich habe ihn aufgeschrieben"], "setup_recovery")
            let hidden = app.switches["Eingang verstecken"]
            if hidden.value as? String == "1" { hidden.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
            XCTAssertEqual(hidden.value as? String, "0")
            snap("setup_visible")
            tap(app.buttons["Tresor einrichten"], "setup_done")
        }
        XCTAssertTrue(app.segmentedControls.buttons["Medien"].waitForExistence(timeout: 20))
    }
    private func confirmTrash(_ name: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'bleiben verschlüsselt'")).firstMatch.exists)
        snap(name + "_confirmation")
        tap(alert.buttons[trashTitle], name + "_confirmed")
    }
    private func swipeToTrash(_ item: XCUIElement, scope: String) {
        let itemID = id(item)
        item.swipeLeft(); snap(scope + "_swipe")
        if scope != "media" { tap(app.buttons[trashTitle].firstMatch, scope + "_swipe_action") }
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        tap(app.alerts.buttons["Abbrechen"], scope + "_swipe_cancelled")
        XCTAssertTrue(item.exists, "Cancel must preserve the item")
        item.swipeLeft(); snap(scope + "_swipe_again")
        if scope != "media" { tap(app.buttons[trashTitle].firstMatch, scope + "_swipe_action_again") }
        confirmTrash(scope + "_swipe")
        gone(item)
        verifyTrash([itemID], restore: true)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        snap(scope + "_swipe_restored")
    }
    private func bulkTrash(_ selected: [XCUIElement], scope: String) -> [String] {
        XCTAssertGreaterThanOrEqual(selected.count, 2)
        let ids = selected.map(id)
        XCTAssertEqual(select(scope).label, "Auswählen", "Selection must be directly visible")
        tap(select(scope), scope + "_select")
        XCTAssertFalse(app.buttons["vault.\(scope).trash"].isEnabled)
        for (index, item) in selected.enumerated() {
            tap(item, scope + "_selected_\(index)")
            XCTAssertTrue(item.isSelected)
        }
        let trash = app.buttons["vault.\(scope).trash"]
        tap(trash, scope + "_bulk_requested")
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\(ids.count) Elemente")).firstMatch.exists)
        tap(app.alerts.buttons["Abbrechen"], scope + "_bulk_cancelled")
        for item in selected { XCTAssertTrue(item.exists && item.isSelected) }
        tap(trash, scope + "_bulk_requested_again")
        confirmTrash(scope + "_bulk")
        for item in selected { gone(item) }
        XCTAssertEqual(select(scope).label, "Auswählen")
        snap(scope + "_bulk_removed")
        return ids
    }
    private func verifyTrash(_ ids: [String], restore: Bool) {
        tap(app.buttons["vault.workspace.more"], "more")
        tap(app.buttons["Tresor-Papierkorb"], "trash_open")
        for value in ids {
            XCTAssertTrue(app.descendants(matching: .any)["vault.trash.item." + value].firstMatch.exists)
        }
        snap("trash_contains_\(ids.count)")
        if restore {
            for value in ids {
                tap(app.buttons["vault.trash.restore." + value], "restored_" + value)
                gone(app.descendants(matching: .any)["vault.trash.item." + value].firstMatch)
            }
        }
        tap(app.buttons["Fertig"].firstMatch, "trash_closed")
    }

    func test10PhotosAndVideosSwipeAndSelection() {
        XCTAssertTrue(items("media").isEmpty)
        tap(app.buttons["In den Tresor legen"], "media_import_picker")
        let picker = app.buttons.matching(identifier: "picker.media")
        XCTAssertTrue(picker.firstMatch.waitForExistence(timeout: 15))
        let photos = picker.allElementsBoundByIndex.filter { !$0.label.contains("Video") }
        let videos = picker.allElementsBoundByIndex.filter { $0.label.contains("Video") }
        XCTAssertGreaterThanOrEqual(photos.count, 3)
        XCTAssertGreaterThanOrEqual(videos.count, 2)
        for (index, item) in (Array(photos.prefix(3)) + Array(videos.prefix(2))).enumerated() {
            tap(item, "import_selected_\(index)")
        }
        tap(app.buttons["Fertig"], "import_picker_done")
        tap(app.alerts.buttons["In den Tresor"], "import_confirmed")
        // Originale bleiben in Fotos. NIE den destruktiven Systemknopf betätigen.
        XCTAssertTrue(system.alerts.firstMatch.waitForExistence(timeout: 60))
        checkpoint("vault_delete_system_photos_deletion_declined", app: system)
        let cancel = system.alerts.buttons.matching(NSPredicate(format: "label IN %@",
            ["Don't Allow", "Don’t Allow", "Don't Delete", "Don’t Delete", "Nicht erlauben", "Nicht löschen", "Abbrechen", "Cancel"] as NSArray)).firstMatch
        XCTAssertTrue(cancel.exists)
        cancel.tap()
        XCTAssertTrue(app.alerts.buttons["OK"].waitForExistence(timeout: 15))
        tap(app.alerts.buttons["OK"], "import_notice")
        XCTAssertEqual(items("media").count, 5)
        snap("five_encrypted_media")
        let photo = items("media").first { $0.label.hasPrefix("Foto") }!
        let video = items("media").first { $0.label.hasPrefix("Video") }!
        swipeToTrash(photo, scope: "media")
        swipeToTrash(video, scope: "media")
        let selected = Array(items("media").filter { $0.label.hasPrefix("Foto") }.prefix(2))
            + Array(items("media").filter { $0.label.hasPrefix("Video") }.prefix(2))
        let removed = bulkTrash(selected, scope: "media")
        XCTAssertEqual(items("media").count, 1, "The unselected photo must remain")
        verifyTrash(removed, restore: true)
        XCTAssertEqual(items("media").count, 5)
        snap("photos_and_videos_restored")
    }

    func test11ViewerContinuesAfterDeletion() {
        let before = items("media")
        XCTAssertGreaterThanOrEqual(before.count, 2)
        let photo = before.first { $0.label.hasPrefix("Foto") }!
        let photoID = id(photo)
        tap(photo, "viewer_open")
        XCTAssertTrue(app.staticTexts["vault.viewer.date"].waitForExistence(timeout: 5))
        tap(app.buttons["vault.viewer.trash"], "viewer_trash")
        confirmTrash("viewer")
        XCTAssertTrue(app.staticTexts["vault.viewer.date"].waitForExistence(timeout: 5), "A remaining item must become current, instead of a blank deleted page")
        snap("viewer_next_item")
        tap(app.buttons["vault.viewer.close"], "viewer_closed")
        gone(photo)
        XCTAssertEqual(items("media").count, before.count - 1)
        verifyTrash([photoID], restore: true)
        XCTAssertEqual(items("media").count, before.count)
    }

    func test12ViewerControlsPhotoZoomAndVideo() {
        let before = items("media")
        XCTAssertGreaterThanOrEqual(before.count, 2)
        guard let photo = before.first(where: { $0.label.hasPrefix("Foto") }),
              let video = before.first(where: { $0.label.hasPrefix("Video") }) else {
            XCTFail("The encrypted photo/video imports must exist")
            return
        }
        tap(photo, "photo_viewer_open")
        let image = app.images["vault.viewer.photo"]
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        let close = app.buttons["vault.viewer.close"]
        let trash = app.buttons["vault.viewer.trash"]
        XCTAssertLessThanOrEqual(close.frame.maxY, image.frame.minY + 1, "Header must reserve space above the photo")
        XCTAssertGreaterThanOrEqual(trash.frame.minY, image.frame.maxY - 1, "Actions must reserve space below the photo")
        tap(image, "photo_controls_hidden")
        gone(close); gone(trash)
        image.tap(); snap("photo_controls_shown")
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        image.doubleTap(); snap("photo_double_tap_zoom")
        XCTAssertEqual((image.value as? String ?? "").filter(\.isNumber), "250")
        image.doubleTap(); snap("photo_double_tap_fit")
        XCTAssertEqual((image.value as? String ?? "").filter(\.isNumber), "100")
        tap(close, "photo_viewer_closed")

        tap(video, "video_viewer_open")
        let surface = app.descendants(matching: .any)["vault.viewer.video"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 20))
        let play = app.buttons["Abspielen"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(close.frame.maxY, surface.frame.minY + 1)
        XCTAssertGreaterThanOrEqual(play.frame.minY, surface.frame.maxY - 1, "Playback controls must not cover the video")
        tap(play, "video_playing")
        let pause = app.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        tap(pause, "video_paused")
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        tap(surface, "video_controls_hidden")
        gone(close); gone(trash); gone(play)
        surface.tap(); snap("video_controls_shown")
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        tap(close, "video_viewer_closed")
        XCTAssertEqual(items("media").count, before.count, "Viewing never moves or deletes content")
        snap("viewer_media_preserved")
    }

    func test20NotesSwipeAndSelection() {
        tap(app.segmentedControls.buttons["Notizen"], "notes_tab")
        for i in 1...3 {
            tap(app.buttons["Neue Notiz"], "note_new_\(i)")
            let title = app.descendants(matching: .any)["vault.note.title"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            title.tap(); title.typeText("Loeschtest \(i)"); snap("note_title_\(i)")
            let status = app.descendants(matching: .any)["vault.note.save-status"].firstMatch
            XCTAssertTrue(status.label.contains("Gespeichert"))
            tap(app.buttons["Fertig"], "note_saved_\(i)")
        }
        XCTAssertEqual(items("notes").count, 3)
        swipeToTrash(items("notes")[0], scope: "notes")
        let removed = bulkTrash(Array(items("notes").prefix(2)), scope: "notes")
        XCTAssertEqual(items("notes").count, 1)
        verifyTrash(removed, restore: true)
        XCTAssertEqual(items("notes").count, 3)
        snap("notes_restored")
    }

    func test30FilesSwipeAndSelection() {
        tap(app.segmentedControls.buttons["Dateien"], "files_tab")
        for name in ["Notizen", "Hotelbuchung", "Reiseplan"] {
            tap(app.buttons["In den Tresor legen"], "file_add_" + name)
            tap(app.buttons["Dateien importieren"], "file_picker_" + name)
            let browse = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "Durchsuchen"] as NSArray)).firstMatch
            XCTAssertTrue(browse.waitForExistence(timeout: 15))
            tap(browse, "browse_" + name)
            let local = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["On My iPhone", "Auf meinem iPhone"] as NSArray)).firstMatch
            if local.waitForExistence(timeout: 8) { tap(local, "local_files_" + name) }
            let appFolder = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'PhotoMaid'")).firstMatch
            if appFolder.waitForExistence(timeout: 8) { tap(appFolder, "app_folder_" + name) }
            let downloads = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'QA-Downloads'")).firstMatch
            if downloads.waitForExistence(timeout: 8) { tap(downloads, "qa_folder_" + name) }
            // "Notizen" also names the vault tab behind the document picker.
            // Restrict the target to the native Files grid, not the whole app tree.
            let file = app.collectionViews["File View"].cells.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            tap(file, "file_chosen_" + name)
            let open = app.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "Öffnen"] as NSArray)).firstMatch
            if open.waitForExistence(timeout: 2) { tap(open, "file_opened_" + name) }
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'vault.files.item.' AND label CONTAINS %@", name)).firstMatch.waitForExistence(timeout: 20))
            snap("file_imported_" + name)
        }
        XCTAssertEqual(items("files").count, 3)
        swipeToTrash(items("files")[0], scope: "files")
        let removed = bulkTrash(Array(items("files").prefix(2)), scope: "files")
        XCTAssertEqual(items("files").count, 1)
        verifyTrash(removed, restore: true)
        XCTAssertEqual(items("files").count, 3)
        snap("files_restored")
    }

    func test40EmptyTrashAtOnceAndDialEntry() {
        tap(app.segmentedControls.buttons["Notizen"], "empty_notes_tab")
        let existing = Set(items("notes").map(id))
        for i in 1...2 {
            tap(app.buttons["Neue Notiz"], "empty_note_new_\(i)")
            let title = app.descendants(matching: .any)["vault.note.title"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            title.tap(); title.typeText("Leeren \(i)"); snap("empty_note_title_\(i)")
            tap(app.buttons["Fertig"], "empty_note_saved_\(i)")
        }
        let created = items("notes").filter { !existing.contains(id($0)) }
        XCTAssertEqual(created.count, 2)
        let removed = bulkTrash(created, scope: "notes")
        tap(app.buttons["vault.workspace.more"], "empty_more")
        tap(app.buttons["Tresor-Papierkorb"], "empty_trash_open")
        let emptyAll = app.buttons["vault.trash.empty"]
        tap(emptyAll, "empty_requested")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'unwiderruflich'")).firstMatch.exists)
        tap(alert.buttons["Abbrechen"], "empty_cancelled")
        for value in removed {
            XCTAssertTrue(app.descendants(matching: .any)["vault.trash.item." + value].firstMatch.exists, "Cancel must keep everything")
        }
        tap(emptyAll, "empty_requested_again")
        tap(app.alerts.firstMatch.buttons["Alles endgültig löschen"], "empty_confirmed")
        for value in removed { gone(app.descendants(matching: .any)["vault.trash.item." + value].firstMatch) }
        XCTAssertTrue(app.staticTexts["Der Tresor-Papierkorb ist leer."].waitForExistence(timeout: 5))
        gone(emptyAll)
        tap(app.buttons["Fertig"].firstMatch, "empty_trash_closed")
        XCTAssertEqual(Set(items("notes").map(id)), existing, "Only trashed content is removed")

        // Versteckter Eingang: Titel „PhotoMaid“ (Tresor-Rad im „o“) 2 Sekunden halten öffnet den gesperrten Tresor.
        tap(app.buttons["vault.workspace.more"], "dial_more")
        tap(app.buttons["Jetzt sperren"], "dial_locked")
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 5) { tap(back, "dial_settings_closed") }
        let title = app.descendants(matching: .any)["today.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "PhotoMaid")
        snap("dial_title")
        title.press(forDuration: 0.6)
        XCTAssertFalse(app.vaultKeypad.waitForExistence(timeout: 2), "A short press must not open the vault")
        title.press(forDuration: 2.6)
        XCTAssertTrue(app.vaultKeypad.waitForExistence(timeout: 10), "Holding the title must open the vault")
        snap("dial_opened_lock_screen")
    }
}
