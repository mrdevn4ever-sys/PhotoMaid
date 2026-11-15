#if QA_FIXTURES && targetEnvironment(simulator)
import Photos
import PhotoMaidCore
import SwiftUI
import UIKit

/// Navigation shortcuts for the disposable App Store capture simulator only.
/// Uses the real PhotoKit library, persistence, analysis and editors. No fake results or purchases.
@MainActor
enum StoreCapture {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-store-capture") }
    private static var openedInitialPage = false
    private static var navigationTask: Task<Void, Never>?
    private static var conceptAEnabled: Bool { enabled && ProcessInfo.processInfo.arguments.contains("-store-concept-a") }
    private static var conceptAArrangedIDs: Set<String> = []
    private static var conceptAErrors: [String] = []
    private static var conceptASelection: [String: Any] = [:]
    private static var conceptALogo: [String: Any] = [:]
    private static var conceptASeriesPreview: [String: Any] = [:]
    private static var conceptACollageSources: [String: Any] = [:]

    /// Read-only reports of the actual view's completed image assignments, never setters.
    static func observeSeriesPreview(assetID: String, imageReady: Bool) {
        guard conceptAEnabled else { return }
        conceptASeriesPreview = ["assetID": assetID, "imageReady": imageReady]
    }

    static func observeCollageSources(projectIDs: [String], loadedIDs: [String], missingIDs: [String]) {
        guard conceptAEnabled else { return }
        conceptACollageSources = ["projectIDs": projectIDs, "loadedIDs": loadedIDs.sorted(), "missingIDs": missingIDs.sorted()]
    }

    private static func conceptANativeListViewport() -> [String: Double] {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else { return [:] }
        @MainActor func lists(in view: UIView) -> [UICollectionView] {
            guard !view.isHidden, view.alpha > 0 else { return [] }
            return (view as? UICollectionView).map { [$0] } ?? view.subviews.flatMap { lists(in: $0) }
        }
        guard let list = lists(in: window).filter({ $0.bounds.height > 300 && $0.contentSize.height > $0.bounds.height })
            .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return [:] }
        let rect = list.convert(list.bounds.inset(by: list.adjustedContentInset), to: window).intersection(window.bounds)
        return ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
    }

    static func openRequestedPage(in app: AppModel) async {
        guard enabled, !openedInitialPage else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-store-page"), arguments.indices.contains(index + 1) else { return }
        openedInitialPage = true
        await open(page: arguments[index + 1], in: app)
    }

    /// Keeps the normal app alive between page captures. Public file I/O, simulator-only,
    /// and explicit test arguments; no URL scheme, entitlement, fake media or purchase state.
    static func startNavigation(in app: AppModel) {
        guard enabled, navigationTask == nil else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-store-navigation"), arguments.indices.contains(index + 1) else { return }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        let request = directory.appendingPathComponent("request.json")
        let initialToken = (try? Data(contentsOf: request)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }?["token"]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("ready".utf8).write(to: directory.appendingPathComponent("hello"), options: .atomic)
        } catch { return } // XCTest retains its ordinary cold-launch fallback.
        navigationTask = Task { @MainActor in
            var lastToken = initialToken
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard UIApplication.shared.applicationState == .active,
                      let data = try? Data(contentsOf: request),
                      let command = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                      let page = command["page"], let token = command["token"],
                      UUID(uuidString: token) != nil, token != lastToken else { continue }
                lastToken = token
                // Read-only observation while XCTest operates the visible page; never navigate away from a scan.
                if conceptAEnabled, page == "concept-a-evidence" {
                    let evidence = await conceptAEvidence(in: app)
                    var result: [String: Any] = ["page": page, "token": token, "status": "ready", "evidence": evidence]
                    // JSONSerialization can raise an Objective-C exception for a Swift
                    // struct in an Any graph. Reject that wire shape before encoding.
                    if !JSONSerialization.isValidJSONObject(result) {
                        let invalid = evidence.keys.filter {
                            !JSONSerialization.isValidJSONObject(["value": evidence[$0]!])
                        }.sorted()
                        result = ["page": page, "token": token, "status": "error",
                                  "error": "Non-JSON read-only evidence fields: " + invalid.joined(separator: ", ")]
                    }
                    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
                        try? data.write(to: directory.appendingPathComponent("ack-" + token + ".json"), options: .atomic)
                    }
                    continue
                }
                app.feed = nil
                app.fullScreen = nil
                if VaultStore.shared.isPresented { VaultStore.shared.lock() }
                for tab in AppTab.allCases { app.popToRoot(tab) }
                app.selectedTab = .today
                try? await Task.sleep(for: .milliseconds(700))
                await open(page: page, in: app)
                let result = ["page": page, "token": token, "status": "ready"]
                if let data = try? JSONSerialization.data(withJSONObject: result) {
                    try? data.write(to: directory.appendingPathComponent("ack-" + token + ".json"), options: .atomic)
                }
            }
        }
    }

    private static func open(page: String, in app: AppModel) async {
        // XCTest waits for this identifier, including when a full-screen page covers the tab bar.
        // No additional visible controls or accessibility text are inserted into the app.
        defer {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow)?.accessibilityIdentifier = "store.capture." + page
        }
        app.updateSettings {
            $0.appearance = ProcessInfo.processInfo.arguments.contains("-capture-light") ? .light : .dark
            $0.designAppearance = $0.appearance
            $0.todayTourSeen = true
            $0.feedTourSeen = true
            $0.gestureHintSeen = true
            $0.showGestureHintOnOpen = false
            if page != "introduction" { $0.onboardingVersion = OnboardingFlow.version }
        }
        guard page != "introduction" else { return }
        if ProcessInfo.processInfo.arguments.contains("-game-visual-tests") {
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined { await app.library.requestAccess() }
            await arrangeGameSources()
        }
        if conceptAEnabled {
            // Concept A is not the legacy 55-photo archive. Never run its arrangement here.
            await arrangeConceptAImportedPhotos()
            if conceptALogo.isEmpty {
                do { try exportConceptAWordmark() }
                catch { conceptAErrors.append("Native wordmark export: \(error)") }
            }
        } else {
            await arrangeImportedPhotos()
        }
        try? await Task.sleep(for: .milliseconds(700)) // let the real PhotoKit change notification settle
        app.reloadLibraryIfNeeded(force: true)
        // PhotoKit loads asynchronously. Routes must receive real identifiers after that read completes.
        for _ in 0..<200 where !app.snapshot.loaded || app.isLoadingLibrary || !app.readReady || app.visibleMedia.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let photos = app.visibleMedia.filter { !$0.isVideo }
        let ids = photos.map(\.id)
        if page.hasPrefix("concept-a-") {
            guard conceptAEnabled else { return }
            await openConceptAPage(page, in: app)
            return
        }
        var tab: AppTab = .cleanup
        let route: Route?
        switch page {
        case "today": app.selectedTab = .today; return
        case "library":
            app.updateSettings { $0.libraryFilter = .all }; app.selectedTab = .library; return
        case "library-favorites", "library-photos", "library-videos", "library-screenshots":
            if let filter = LibraryFilter(rawValue: String(page.dropFirst(8))) { app.updateSettings { $0.libraryFilter = filter } }
            app.selectedTab = .library; return
        case "cleanup": app.selectedTab = .cleanup; return
        case "studio": app.selectedTab = .studio; return
        case "history": app.selectedTab = .history; return
        case "feed-failures":
            app.selectedTab = .cleanup
            let videos = Array(app.visibleMedia.filter(\.isVideo).prefix(2))
            let items = videos + Array(photos.prefix(1))
            app.previews.unavailableForTesting = Set(videos.map(\.id))
            app.open(FeedRequest(.items(items.map(\.reference), titleKey: "feed_title_all"))); return
        case "feed-posterless":
            let videos = Array(app.visibleMedia.filter(\.isVideo).prefix(1))
            app.previews.posterlessForTesting = Set(videos.map(\.id))
            app.open(FeedRequest(.items((videos + Array(photos.prefix(1))).map(\.reference), titleKey: "feed_title_all"))); return
        case "feed-slow":
            let items = Array(photos.prefix(2))
            app.previews.slowForTesting = Set(items.prefix(1).map(\.id))
            app.open(FeedRequest(.items(items.map(\.reference), titleKey: "feed_title_all"))); return
        case "feed-video-posters":
            let videos = Array(app.visibleMedia.filter(\.isVideo).prefix(2))
            let items = Array(photos.prefix(1)) + videos + Array(photos.dropFirst().prefix(1))
            app.previews.slowVideosForTesting = Set(videos.map(\.id))
            app.open(FeedRequest(.items(items.map(\.reference), titleKey: "feed_title_all"))); return
        case "feed": app.open(FeedRequest(.allMedia)); return
        case "viewer":
            if !ids.isEmpty { app.fullScreen = .viewer(ids: ids, index: 0) }; return
        case "editor":
            if let id = ids.first { app.fullScreen = .editor(assetID: id) }; return
        case "slideshow": app.fullScreen = .slideshow(ids: ids); return
        case "vault": VaultStore.shared.present(); return
        case "trash": route = .trash
        case "later": route = .later
        case "months": route = .months
        case "large-files": route = .largeFiles
        case "duplicates": route = .duplicates
        case "storage": route = .storage
        case "files": route = .files
        case "series": route = .series
        case "collections": route = .collections
        case "blurry": route = .smartReview(.blurry)
        case "similar": route = .smartReview(.similar)
        case "documents": route = .smartReview(.documents)
        case "categories": route = .smartReview(.categories)
        case "albums": tab = .library; route = .albums
        case "album":
            let options = PHFetchOptions(); options.predicate = NSPredicate(format: "title == %@", AppConfig.brandName)
            if let album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject {
                tab = .library; route = .album(id: album.localIdentifier, title: AppConfig.brandName)
            } else { return }
        case "grid": tab = .library; route = .grid(.items(ids, titleKey: "tab_library"))
        case "favorites": tab = .library; route = .favorites
        case "selection": tab = .library; route = .selectionBasket
        case "tags": tab = .library; route = .tags
        case "hidden": tab = .library; route = .hidden
        case "edits": tab = .studio; route = .edits
        case "received": tab = .studio; route = .received([])
        case "collage": StudioHandoff.shared.ids = Array(ids.prefix(4)); tab = .studio; route = .collage(draftID: nil)
        case "movie": tab = .studio; route = .movie(ids: Array(ids.prefix(5)))
        case "pdf": tab = .studio; route = .pdfFromPhotos(ids: Array(ids.prefix(4)))
        case "pdf-studio": tab = .studio; route = .pdfStudio
        case "archive": tab = .studio; route = .archive(ids: Array(ids.prefix(4)))
        case "workflows": tab = .studio; route = .workflows
        case "settings": tab = .today; route = .settings
        case "pro": tab = .today; route = .pro
        case "privacy": tab = .today; route = .privacy
        case "help": tab = .today; route = .help
        case "excluded-albums": tab = .today; route = .excludedAlbums
        case "backup": tab = .today; route = .backup
        case "controls": tab = .today; route = .feedControls
        default:
            if page.hasPrefix("tools-"), let kind = ToolKind(rawValue: String(page.dropFirst(6))) {
                tab = .studio; route = .tools(kind)
            } else { return }
        }
        app.selectedTab = tab
        if let route {
            // Let the selected tab mount its NavigationStack before changing its path.
            // Pushing into an inactive stack in the same update leaves iOS 26's large
            // title and scroll-content insets out of sync in simulator captures.
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation { app.navigate(route, in: tab) }
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    /// Public original filename; never a synthetic ID or a private resource property.
    private static func originalFilename(_ asset: PHAsset) -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        return (resources.first { $0.type == .photo || $0.type == .video } ?? resources.first)?.originalFilename
    }

    // MARK: Fresh Concept A — navigation/source selection only; all decisions/imports/scans use the UI.
    private static func openConceptAPage(_ page: String, in app: AppModel) async {
        conceptASelection = ["page": page, "assetIDs": [String](), "sourceFiles": [String]()]
        var byFilename: [String: [String]] = [:]
        let all = PHAsset.fetchAssets(with: nil)
        for index in 0..<all.count {
            let asset = all.object(at: index)
            if let filename = originalFilename(asset) { byFilename[filename, default: []].append(asset.localIdentifier) }
        }
        func select(_ filenames: [String]) -> [MediaAsset]? {
            var selected: [MediaAsset] = []
            for filename in filenames {
                guard let matches = byFilename[filename], matches.count == 1,
                      let asset = app.visibleMedia.first(where: { $0.id == matches[0] }) else {
                    conceptAErrors.append("\(page): expected one visible imported asset named \(filename)")
                    return nil
                }
                selected.append(asset)
            }
            conceptASelection = ["page": page, "assetIDs": selected.map(\.id), "sourceFiles": filenames,
                                 "accessibilityValues": selected.map(MediaInfoLine.describe)]
            return selected
        }
        var tab: AppTab = .cleanup
        let route: Route?
        switch page {
        case "concept-a-library":
            app.updateSettings { $0.libraryFilter = .all }; app.selectedTab = .library; return
        case "concept-a-feed":
            guard let selected = select(["CA_01_clutter_blur.jpg", "concept-a-native-library.png",
                                         "CA_30_pretty_06.jpg", "CA_30_pretty_07.jpg", "CA_30_pretty_08.jpg"]) else { return }
            app.open(FeedRequest(.items(selected.map(\.reference), titleKey: "feed_title_all"))); return
        case "concept-a-editor":
            guard let selected = select(["CA_30_pretty_08.jpg"]), let asset = selected.first else { return }
            app.fullScreen = .editor(assetID: asset.id); return
        case "concept-a-collage":
            guard let selected = select((1...4).map { String(format: "CA_30_pretty_%02d.jpg", $0) }) else { return }
            StudioHandoff.shared.ids = selected.map(\.id); tab = .studio; route = .collage(draftID: nil)
        case "concept-a-vault": VaultStore.shared.present(); return
        case "concept-a-trash": route = .trash
        case "concept-a-duplicates": route = .duplicates
        case "concept-a-large-files": route = .largeFiles
        case "concept-a-months": route = .months
        case "concept-a-analysis": route = .series
        default: conceptAErrors.append("Unknown Concept A page: \(page)"); return
        }
        app.selectedTab = tab
        if let route {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation { app.navigate(route, in: tab) }
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    /// Public PhotoKit metadata edits only, restricted to CA assets in the disposable simulator.
    /// New arrivals (the recorder's real OS screenshot) are arranged independently on the next navigation.
    private static func arrangeConceptAImportedPhotos() async {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            conceptAErrors.append("Concept A requires actual full PhotoKit access"); return
        }
        let all = PHAsset.fetchAssets(with: nil)
        var sources: [(id: String, filename: String)] = []
        for index in 0..<all.count {
            let asset = all.object(at: index)
            guard let filename = originalFilename(asset),
                  filename.hasPrefix("CA_") || filename == "concept-a-native-library.png" else { continue }
            sources.append((asset.localIdentifier, filename))
        }
        sources.sort { $0.filename < $1.filename }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var edits: [(String, Date, Bool)] = []
        for (rank, source) in sources.enumerated() where !conceptAArrangedIDs.contains(source.id) {
            var bucket = rank % 12, day = 1 + rank % 24, second = 60 * rank
            if source.filename.hasPrefix("CA_20_series_"),
               let number = Int(source.filename.dropFirst("CA_20_series_".count).prefix(2)) {
                // Genuine SeriesListView grouping by capture time; not an invented Vision/similarity result.
                bucket = 2; day = 18; second = 2 * (number - 1)
            } else if source.filename.hasPrefix("CA_30_pretty_"),
                      let number = Int(source.filename.dropFirst("CA_30_pretty_".count).prefix(2)) {
                bucket = (number - 1) % 12; day = 10 + (number - 1) / 12; second = 0
            } else if source.filename == "concept-a-native-library.png" {
                bucket = 0; day = 13; second = 0
            }
            guard let anchor = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12)),
                  let date = calendar.date(byAdding: .month, value: -bucket, to: anchor),
                  let taken = calendar.date(byAdding: .second, value: second, to: date) else { continue }
            edits.append((source.id, taken, source.filename == "CA_30_pretty_08.jpg"))
        }
        guard !edits.isEmpty else { return }
        let changes = edits // Only Sendable values cross PhotoKit's changes block.
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                for (id, date, favorite) in changes {
                    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { continue }
                    let edit = PHAssetChangeRequest(for: asset)
                    edit.creationDate = date; edit.isFavorite = favorite
                }
            }
            conceptAArrangedIDs.formUnion(changes.map(\.0))
        } catch {
            conceptAErrors.append("Concept A PhotoKit arrangement: \(error)")
            Diagnostics.error(.app, "store-concept-a-library-arrangement", error)
        }
    }

    /// Offscreen export of the ORIGINAL wordmark, including CombinationDial and its original private QTail.
    /// No overlay, extra window, retouching, replacement letter or visible debug control.
    private static func exportConceptAWordmark() throws {
        guard conceptAEnabled else { return }
        let content = VaultDialWordmark().padding(8)
            .environment(\.dynamicTypeSize, .large).environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "en_US")).environment(\.layoutDirection, .leftToRight)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 8
        renderer.isOpaque = false // Internal native master only. Final Store exports must be RGB.
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { image = renderer.uiImage }
        guard let image, let cg = image.cgImage, let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        try data.write(to: documents.appendingPathComponent("store-concept-a-wordmark.png"), options: .atomic)
        conceptALogo = ["exported": true, "component": "VaultDialWordmark", "dialComponent": "CombinationDial",
                        "source": "PhotoMaid/Features/Today/VaultDialWordmark.swift", "width": cg.width, "height": cg.height,
                        "rendererScale": renderer.scale, "transparentInternalMaster": true, "appVersion": AppConfig.appVersion,
                        "foreground": "lightForeground", "colorScheme": "light"]
        try JSONSerialization.data(withJSONObject: conceptALogo, options: [.prettyPrinted, .sortedKeys])
            .write(to: documents.appendingPathComponent("store-concept-a-wordmark.json"), options: .atomic)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-store-navigation"), arguments.indices.contains(index + 1) {
            let root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true).deletingLastPathComponent()
            let screenshots = root.appendingPathComponent("screenshots", isDirectory: true)
            try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
            try data.write(to: screenshots.appendingPathComponent("concept-a-logo.png"), options: .atomic)
        }
    }

    /// Read-only evidence: never starts work or writes models, measurements, scan results or entitlements.
    private static func conceptAEvidence(in app: AppModel) async -> [String: Any] {
        let all = PHAsset.fetchAssets(with: nil)
        var inventory: [[String: Any]] = []
        for index in 0..<all.count {
            let asset = all.object(at: index)
            var row: [String: Any] = ["id": asset.localIdentifier, "filename": originalFilename(asset) ?? "",
                                      "isVideo": asset.mediaType == .video,
                                      "isScreenshot": asset.mediaSubtypes.contains(.photoScreenshot),
                                      "pixelWidth": asset.pixelWidth, "pixelHeight": asset.pixelHeight,
                                      "duration": asset.duration, "favorite": asset.isFavorite]
            if let date = asset.creationDate { row["creationDate"] = date.timeIntervalSince1970 }
            if let media = app.asset(asset.localIdentifier) { row["accessibilityValue"] = MediaInfoLine.describe(media) }
            inventory.append(row)
        }
        inventory.sort { ($0["filename"] as? String ?? "") < ($1["filename"] as? String ?? "") }
        // Retain the first actual inventory (after the recorder import), before intentional vault removals.
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let file = documents.appendingPathComponent("store-concept-a-library.json")
            if !FileManager.default.fileExists(atPath: file.path) {
                let library: [String: Any] = ["count": inventory.count,
                    "photoCount": inventory.filter { $0["isVideo"] as? Bool == false }.count,
                    "videoCount": inventory.filter { $0["isVideo"] as? Bool == true }.count,
                    "sourceFiles": inventory.compactMap { $0["filename"] as? String }, "assets": inventory,
                    "arrangedIDs": conceptAArrangedIDs.sorted(), "source": "actual PhotoKit fetch; original resources unchanged"]
                do {
                    try JSONSerialization.data(withJSONObject: library, options: [.prettyPrinted, .sortedKeys])
                        .write(to: file, options: .atomic)
                } catch { conceptAErrors.append("Concept A native library inventory export: \(error)") }
            }
        }
        let records = await app.sizer.records(for: app.cleanupMedia) // Cache read, NOT a measurement.
        let measurements: [[String: Any]] = records.keys.sorted().compactMap { id in
            guard let record = records[id] else { return nil }
            var row: [String: Any] = ["id": id, "state": record.state.rawValue]
            if let bytes = record.bytes { row["bytes"] = bytes; row["sizeText"] = SizeText.bytes(bytes) }
            return row
        }
        let scanner = DuplicateScanner.shared
        var duplicates: [String: Any] = ["running": scanner.isRunning, "failed": scanner.failed,
                                          "hasResult": scanner.result != nil]
        if let result = scanner.result {
            let groups: [[String: Any]] = result.groups.map { group in
                ["assetIDs": group.members.map(\.localIdentifier), "sha256": group.sha256,
                 "sizeEach": group.sizeEach, "extraCopiesBytes": group.extraCopiesBytes]
            }
            let extra = result.groups.reduce(Int64(0)) { $0 + $1.extraCopiesBytes }
            let selected = result.groups.reduce(Int64(0)) { $0 + $1.selectedBytes(scanner.selection[$1.id] ?? []) }
            duplicates["complete"] = result.isComplete
            duplicates["groups"] = groups
            duplicates["header"] = L("dup_header", result.groups.reduce(0) { $0 + $1.members.count }, SizeText.bytes(extra))
            duplicates["footer"] = L("dup_footer", SizeText.bytes(selected))
            duplicates["unchecked"] = result.uncheckedCount
        }
        let pending = Set(app.pending.map(\.localIdentifier))
        var largeRows: [[String: Any]] = []
        for asset in app.cleanupMedia {
            guard pending.contains(asset.id), let record = SizeMeasuring.shared.records[asset.id],
                  record.isCurrent(modified: asset.modificationDate), record.state == .known,
                  let bytes = record.bytes, bytes >= Int64(app.settings.largeFileThresholdMB) * 1_000_000 else { continue }
            largeRows.append(["id": asset.id, "isVideo": asset.isVideo, "bytes": bytes,
                              "sizeText": SizeText.bytes(bytes), "accessibilityValue": MediaInfoLine.describe(asset)])
        }
        largeRows.sort { ($0["bytes"] as? Int64 ?? 0) > ($1["bytes"] as? Int64 ?? 0) }
        let monthProgress = ProgressRules.months(app.cleanupMedia, date: \.creationDate,
                                               record: { app.read.records[$0.reference] }, timeZone: .autoupdatingCurrent)
        let months: [[String: Any]] = monthProgress.map {
            ["month": $0.month.description, "title": MonthText.title($0.month),
             "total": $0.total, "reviewed": $0.reviewed, "later": $0.later]
        }
        let seriesCandidates = app.cleanupMedia.filter { !$0.isVideo && pending.contains($0.id) }
        let series = PhotoSeries.groups(seriesCandidates.map {
            PhotoSeries.Member(id: $0.id, group: $0.kind == .screenshot ? "screenshots" : "camera", takenAt: $0.creationDate)
        }).map { $0.map(\.id) } // Observe actual group IDs as JSON primitives, never serialize Member structs.
        let decisions: [[String: Any]] = app.read.records.values.map { record in
            var row: [String: Any] = ["id": record.item.localIdentifier, "disposition": record.disposition.rawValue,
                                      "revision": record.revision]
            if let day = record.dueDay { row["dueDay"] = day.description }
            return row
        }
        let vault = VaultStore.shared
        let vaultRows: [[String: Any]] = vault.index.items.map { item in
            ["id": item.id, "originalID": item.originalID ?? "", "sourceID": item.sourceID ?? "",
             "sourceFiles": item.resources.map(\.originalFilename),
             "measuredBytes": item.resources.reduce(Int64(0)) { $0 + $1.size },
             "thumbnailReady": vault.thumbnails[item.id] != nil]
        }
        return ["locale": Locale.current.identifier, "appVersion": AppConfig.appVersion,
                "fixtureMode": app.isQAFixtureMode, "readReady": app.readReady, "libraryLoaded": app.snapshot.loaded,
                "reduceMotion": UIAccessibility.isReduceMotionEnabled, "setupErrors": conceptAErrors,
                "inventory": inventory, "selection": conceptASelection, "measurements": measurements,
                "duplicates": duplicates, "largeFiles": largeRows, "largeMeasuring": SizeMeasuring.shared.running,
                "largeThresholdMB": app.settings.largeFileThresholdMB, "months": months, "series": series,
                "seriesPreview": conceptASeriesPreview, "collageSources": conceptACollageSources,
                "nativeListViewport": conceptANativeListViewport(),
                "monthsTourSeen": app.settings.monthsTourSeen, "decisions": decisions,
                "basketIDs": app.read.basket.map(\.item.localIdentifier), "eventCount": app.read.events.count,
                "defaultLaterText": LaterText.inInterval(app.settings.laterInterval),
                "twoDaysDueDay": LaterInterval.defaultQuick.dueDay(from: app.today).description, "logo": conceptALogo,
                "vault": ["setUp": vault.isSetUp, "items": vaultRows, "stillInPhotos": vault.stillInLibraryCount,
                           "unlocked": vault.phase == .unlocked, "importing": vault.progress != nil]]
    }

    /// A bounded PhotoKit fixture for source-selection tests, restricted to explicitly labelled synthetic QA assets.
    private static func arrangeGameSources() async {
        guard !UserDefaults.standard.bool(forKey: "gameVisual.sourcesPrepared") else { return }
        let all = PHAsset.fetchAssets(with: .image, options: nil)
        let ids = (0..<all.count).compactMap { index -> String? in
            let asset = all.object(at: index)
            guard PHAssetResource.assetResources(for: asset).first?.originalFilename.hasPrefix("QA_") == true else { return nil }
            return asset.localIdentifier
        }.prefix(12).map { $0 }
        guard ids.count == 12 else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                for index in 0..<min(6, assets.count) { PHAssetChangeRequest(for: assets.object(at: index)).isFavorite = true }
                let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "QA Game Album")
                album.addAssets(assets)
                let folder = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: "QA Game Folder")
                folder.addChildCollections([album.placeholderForCreatedAssetCollection] as NSArray)
            }
            UserDefaults.standard.set(true, forKey: "gameVisual.sourcesPrepared")
        } catch { Diagnostics.error(.app, "game-visual-sources", error) }
    }

    /// Actual test-library edits, confined to the disposable simulator. No change to image bytes.
    private static func arrangeImportedPhotos() async {
        guard !UserDefaults.standard.bool(forKey: "storeCapture.arranged") else { return }
        let all = PHAsset.fetchAssets(with: .image, options: nil)
        var imported: [(String, Int)] = []
        var filenames: [String] = []
        for index in 0..<all.count {
            let asset = all.object(at: index)
            guard let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename,
                  let number = Int(filename.prefix(2)), (1...55).contains(number) else { continue }
            imported.append((asset.localIdentifier, number)); filenames.append(filename)
        }
        let inventory: [String: Any] = ["count": all.count, "sourceFiles": filenames.sorted()]
        if let data = try? JSONSerialization.data(withJSONObject: inventory, options: [.prettyPrinted, .sortedKeys]),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: documents.appendingPathComponent("store-library.json"), options: .atomic)
        }
        guard all.count == 55, imported.count == 55 else { return }
        let assets = imported
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                for (id, index) in assets {
                    guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { continue }
                    let edit = PHAssetChangeRequest(for: asset)
                    // Spread the real imported fixtures across four genuine month groups. This edits only metadata in
                    // the disposable capture library and lets the real MonthsView demonstrate its actual grouping.
                    let monthBucket = (index - 1) / 14
                    edit.creationDate = Date(timeIntervalSince1970: 1_792_022_400
                                             - Double(monthBucket) * 35 * 86_400
                                             - Double((index - 1) % 14) * 3_600)
                    edit.isFavorite = [13, 21, 25, 31, 36, 42].contains(index)
                }
                let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: AppConfig.brandName)
                album.addAssets(PHAsset.fetchAssets(withLocalIdentifiers: assets.filter { $0.1 <= 12 }.map(\.0), options: nil))
            }
            UserDefaults.standard.set(true, forKey: "storeCapture.arranged")
        } catch { Diagnostics.error(.app, "store-capture-library-arrangement", error) }
    }
}
#endif
