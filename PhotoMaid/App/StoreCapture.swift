#if QA_FIXTURES && targetEnvironment(simulator)
import Photos
import PhotoMaidCore
import SwiftUI

/// Navigation shortcuts for the disposable App Store capture simulator only.
/// Uses the real PhotoKit library, persistence, analysis and editors. No fake results or purchases.
@MainActor
enum StoreCapture {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-store-capture") }
    private static var openedInitialPage = false
    private static var navigationTask: Task<Void, Never>?

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
            $0.appearance = .dark
            $0.todayTourSeen = true
            $0.feedTourSeen = true
            $0.gestureHintSeen = true
            $0.showGestureHintOnOpen = false
            if page != "introduction" { $0.onboardingVersion = OnboardingFlow.version }
        }
        guard page != "introduction" else { return }
        await arrangeImportedPhotos()
        try? await Task.sleep(for: .milliseconds(700)) // let the real PhotoKit change notification settle
        app.reloadLibraryIfNeeded(force: true)
        // PhotoKit loads asynchronously. Routes must receive real identifiers after that read completes.
        for _ in 0..<200 where !app.snapshot.loaded || app.isLoadingLibrary || !app.readReady || app.visibleMedia.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let photos = app.visibleMedia.filter { !$0.isVideo }
        let ids = photos.map(\.id)
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
        case "feed": app.open(FeedRequest(.allMedia)); return
        case "viewer":
            if !ids.isEmpty { app.fullScreen = .viewer(ids: ids, index: 0) }; return
        case "editor":
            if let id = ids.first { app.fullScreen = .editor(assetID: id) }; return
        case "slideshow": app.fullScreen = .slideshow(ids: ids); return
        case "scanner": app.fullScreen = .scanner; return
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
            let options = PHFetchOptions(); options.predicate = NSPredicate(format: "title == %@", "PhotoMaid")
            if let album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject {
                tab = .library; route = .album(id: album.localIdentifier, title: "PhotoMaid")
            } else { return }
        case "grid": tab = .library; route = .grid(.items(ids, titleKey: "tab_library"))
        case "favorites": tab = .library; route = .favorites
        case "search": tab = .library; route = .search
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
        if let route { app.navigate(route, in: tab) }
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
                    edit.creationDate = Date(timeIntervalSince1970: 1_792_022_400 - Double(index) * 3_600)
                    edit.isFavorite = [13, 21, 25, 31, 36, 42].contains(index)
                }
                let album = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: "PhotoMaid")
                album.addAssets(PHAsset.fetchAssets(withLocalIdentifiers: assets.filter { $0.1 <= 12 }.map(\.0), options: nil))
            }
            UserDefaults.standard.set(true, forKey: "storeCapture.arranged")
        } catch { Diagnostics.error(.app, "store-capture-library-arrangement", error) }
    }
}
#endif
