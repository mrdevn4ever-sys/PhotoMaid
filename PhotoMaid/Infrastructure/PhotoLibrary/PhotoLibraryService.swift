import CoreLocation
import Foundation
import Observation
import Photos
import PhotosUI
import PhotoMaidCore
import UIKit

/// Tatsächlicher Systemzustand der Mediathek-Berechtigung (readWrite).
/// iOS kennt keine getrennten Foto-/Videoberechtigungen wie Android.
enum PhotoAccess: Equatable, Sendable {
    case notDetermined, authorized, limited, denied, restricted

    init(_ s: PHAuthorizationStatus) {
        switch s {
        case .authorized: self = .authorized
        case .limited: self = .limited
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }

    var canRead: Bool { self == .authorized || self == .limited }
}

enum MediaCategory: String, CaseIterable, Sendable, Identifiable, Codable {
    case photos, videos, screenshots
    var id: String { rawValue }
}

/// Leichtgewichtige, Sendable-Beschreibung eines PhotoKit-Assets. Größe steht hier bewusst NICHT: PhotoKit liefert
/// keine öffentliche Dateigröße; gemessen wird getrennt (`MediaSizer`), unbekannt bleibt unbekannt.
struct MediaAsset: Hashable, Sendable, Identifiable {
    let id: String
    let kind: MediaKind
    let creationDate: Date?
    let modificationDate: Date?
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    let isLivePhoto: Bool
    let isFavorite: Bool
    let canDelete: Bool
    let canEditProperties: Bool
    let latitude: Double?
    let longitude: Double?
    let subtypes: UInt
    let burstIdentifier: String?
    /// In der Fotos-App bearbeitet (`hasAdjustments`) – nur für den Filter „Bearbeitet“.
    var isEdited = false

    var reference: ItemReference { .photo(id) }
    var aspectRatio: CGFloat { pixelHeight > 0 && pixelWidth > 0 ? CGFloat(pixelWidth) / CGFloat(pixelHeight) : 1 }
    var isVideo: Bool { kind == .video }
    var hasLocation: Bool { latitude != nil && longitude != nil }
    var isPanorama: Bool { subtypes & PHAssetMediaSubtype.photoPanorama.rawValue != 0 }
    var isHDR: Bool { subtypes & PHAssetMediaSubtype.photoHDR.rawValue != 0 }
    var isPortrait: Bool { subtypes & PHAssetMediaSubtype.photoDepthEffect.rawValue != 0 }
    var isSlowMotion: Bool { subtypes & PHAssetMediaSubtype.videoHighFrameRate.rawValue != 0 }
    var isTimelapse: Bool { subtypes & PHAssetMediaSubtype.videoTimelapse.rawValue != 0 }
    var isCinematic: Bool { subtypes & PHAssetMediaSubtype.videoCinematic.rawValue != 0 }
}

/// Album oder Ordner der Fotos-App (E5: an Stelle der Android-Ordner).
struct PhotoAlbum: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let isFolder: Bool
    let count: Int
    let latest: Date?
    let canAddAssets: Bool
    let children: [PhotoAlbum]
}

/// Ergebnis eines Schreibwunschs an die Mediathek (Favorit, Album). Erfolg nur nach erneutem Lesen.
enum MediaWriteResult: Equatable, Sendable {
    case done
    case cancelled
    /// Technisch gescheitert oder nicht belegbar (Grund nur fürs Protokoll, nie im UI).
    case failed
}

/// Einziger Zugang zu PhotoKit. Alle Requests ohne automatische Netzwerkfreigabe (iCloud nur auf Tipp).
@MainActor
@Observable
final class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var access: PhotoAccess = .init(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    /// Erhöht sich bei jeder Mediatheksänderung (Seiten laden daraufhin neu).
    private(set) var changeToken = 0
    @ObservationIgnored private var observing = false

    override init() {
        super.init()
        startObservingIfAllowed()
    }

    /// Bei Resume erneut prüfen (Berechtigung kann in den Einstellungen geändert worden sein).
    func refreshAccess() {
        let new = PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        if new != access { access = new; changeToken += 1 }
        startObservingIfAllowed()
    }

    func bumpChangeToken() { changeToken += 1 }

    /// Kontextuelle Anfrage – nur nach einer Nutzeraktion aufrufen.
    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        access = PhotoAccess(status)
        changeToken += 1
        startObservingIfAllowed()
    }

    /// Auswahl bei eingeschränktem Zugriff verwalten (Systemdialog).
    func presentLimitedLibraryPicker() {
        guard access == .limited, let root = UIApplication.shared.topViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root) { [weak self] (_: [String]) in
            Task { @MainActor in self?.changeToken += 1 }
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.changeToken += 1 }
    }

    private func startObservingIfAllowed() {
        guard access.canRead, !observing else { return }
        PHPhotoLibrary.shared().register(self)
        observing = true
    }

    // MARK: Abfragen

    nonisolated static func fetchOptions(_ category: MediaCategory?) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        switch category {
        case .photos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        case .videos:
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        case .screenshots:
            options.predicate = NSPredicate(format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
                                            PHAssetMediaType.image.rawValue, PHAssetMediaSubtype.photoScreenshot.rawValue)
        case nil:
            options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        }
        return options
    }

    /// Alle prüfbaren Medien (Fotos inkl. Screenshots + Videos), neueste zuerst. Abseits des Main-Threads
    /// (PhotoKit-Abfragen sind threadsicher); bei 50 000 Medien dauert das spürbar.
    nonisolated static func loadAll() async -> [MediaAsset] {
        await Task.detached(priority: .userInitiated) {
            guard PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead else { return [] }
            let result = PHAsset.fetchAssets(with: PhotoLibraryService.fetchOptions(nil))
            var out: [MediaAsset] = []
            out.reserveCapacity(result.count)
            result.enumerateObjects { a, _, _ in out.append(PhotoLibraryService.describe(a)) }
            // Medien im Tresor gibt es für die übrige App nicht (auch wenn das Original noch in Fotos liegt).
            return VaultConcealment.shared.visible(out) { $0.id }
        }.value
    }

    func count(_ category: MediaCategory) -> Int {
        guard access.canRead else { return 0 }
        let result = PHAsset.fetchAssets(with: Self.fetchOptions(category))
        return Self.visibleCount(result)
    }

    /// Anzahl ohne Medien im Tresor (ohne verborgene Medien ohne Aufzählen).
    nonisolated static func visibleCount(_ result: PHFetchResult<PHAsset>) -> Int {
        let concealment = VaultConcealment.shared
        guard !concealment.isEmpty else { return result.count }
        var n = 0
        result.enumerateObjects { a, _, _ in if !concealment.isConcealed(a.localIdentifier) { n += 1 } }
        return n
    }

    func assets(ids: [String]) -> [MediaAsset] {
        let ids = VaultConcealment.shared.visible(ids) { $0 }
        guard access.canRead, !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byID: [String: MediaAsset] = [:]
        result.enumerateObjects { a, _, _ in byID[a.localIdentifier] = Self.describe(a) }
        return ids.compactMap { byID[$0] }
    }

    func asset(_ id: String) -> MediaAsset? { assets(ids: [id]).first }

    /// Medien im Tresor liefert diese Abfrage nie (`nil`, als gäbe es sie nicht).
    nonisolated static func phAsset(_ id: String) -> PHAsset? {
        guard !VaultConcealment.shared.isConcealed(id) else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Mitglieder eines Smart-Albums der Fotos-App (z. B. Selfies, RAW) – für den Mediathek-Filter.
    nonisolated static func smartAlbumIDs(_ subtype: PHAssetCollectionSubtype) -> Set<String> {
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
        guard let album = albums.firstObject else { return [] }
        return assetIDs(inCollection: album.localIdentifier)
    }

    /// Mehrere Assets mit EINER Abfrage (statt einer je Medium) – für Messungen über die ganze Mediathek.
    /// Tresor-Medien werden nie geliefert.
    nonisolated static func phAssetBoxes(_ ids: [String]) -> [String: UncheckedBox<PHAsset>] {
        let visible = ids.filter { !VaultConcealment.shared.isConcealed($0) }
        guard !visible.isEmpty else { return [:] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: visible, options: nil)
        var out: [String: UncheckedBox<PHAsset>] = [:]
        for i in 0..<result.count {
            let asset = result.object(at: i)
            out[asset.localIdentifier] = UncheckedBox(asset)
        }
        return out
    }

    /// Nur für den Tresor selbst (Ablegen, „Dort löschen“) und Existenzprüfungen: auch verborgene Originale.
    nonisolated static func phAssetIncludingConcealed(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    nonisolated static func describe(_ a: PHAsset) -> MediaAsset {
        let isScreenshot = a.mediaSubtypes.contains(.photoScreenshot)
        let kind: MediaKind = a.mediaType == .video ? .video : (isScreenshot ? .screenshot : .photo)
        let coord = a.location?.coordinate
        return MediaAsset(id: a.localIdentifier, kind: kind, creationDate: a.creationDate,
                          modificationDate: a.modificationDate, duration: a.duration,
                          pixelWidth: a.pixelWidth, pixelHeight: a.pixelHeight,
                          isLivePhoto: a.mediaSubtypes.contains(.photoLive), isFavorite: a.isFavorite,
                          canDelete: a.canPerform(.delete), canEditProperties: a.canPerform(.properties),
                          latitude: coord?.latitude, longitude: coord?.longitude,
                          subtypes: a.mediaSubtypes.rawValue, burstIdentifier: a.burstIdentifier,
                          isEdited: a.hasAdjustments)
    }

    /// Originaler Dateiname (für Suche, Info und den Fingerabdruck bei Schlagwörtern/Sicherung). Nie übertragen.
    nonisolated static func originalFilename(_ id: String) -> String? {
        guard let a = phAsset(id) else { return nil }
        let resources = PHAssetResource.assetResources(for: a)
        let main = resources.first { $0.type == .photo || $0.type == .video } ?? resources.first
        return main?.originalFilename
    }

    /// RAW + JPEG in einem Asset (iOS speichert beide als ein Medium – sie bleiben immer zusammen).
    nonisolated static func hasRawAlternate(_ id: String) -> Bool {
        guard let a = phAsset(id) else { return false }
        return PHAssetResource.assetResources(for: a).contains { $0.type == .alternatePhoto }
    }

    // MARK: Alben (E5)

    /// Alben und Ordner des Nutzers als Baum. Geteilte Alben und intelligente Alben bleiben außen vor
    /// (nicht beschreibbar bzw. vom System verwaltet).
    nonisolated static func loadAlbums() async -> [PhotoAlbum] {
        await Task.detached(priority: .userInitiated) {
            guard PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead else { return [] }
            return PhotoLibraryService.collect(PHCollectionList.fetchTopLevelUserCollections(with: nil), depth: 0)
        }.value
    }

    nonisolated private static func collect(_ result: PHFetchResult<PHCollection>, depth: Int) -> [PhotoAlbum] {
        var out: [PhotoAlbum] = []
        result.enumerateObjects { c, _, _ in
            if let album = c as? PHAssetCollection {
                let o = PHFetchOptions()
                o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                o.includeHiddenAssets = false
                let assets = PHAsset.fetchAssets(in: album, options: o)
                let concealment = VaultConcealment.shared
                var latest: Date?
                if concealment.isEmpty {
                    latest = assets.firstObject?.creationDate
                } else {
                    assets.enumerateObjects { a, _, stop in
                        if !concealment.isConcealed(a.localIdentifier) { latest = a.creationDate; stop.pointee = true }
                    }
                }
                out.append(PhotoAlbum(id: album.localIdentifier, title: album.localizedTitle ?? "",
                                      isFolder: false, count: PhotoLibraryService.visibleCount(assets), latest: latest,
                                      canAddAssets: album.canPerform(.addContent), children: []))
            } else if let list = c as? PHCollectionList, depth < 8 {
                let children = PhotoLibraryService.collect(PHCollection.fetchCollections(in: list, options: nil), depth: depth + 1)
                out.append(PhotoAlbum(id: list.localIdentifier, title: list.localizedTitle ?? "", isFolder: true,
                                      count: children.reduce(0) { $0 + $1.count },
                                      latest: children.compactMap(\.latest).max(), canAddAssets: false,
                                      children: children))
            }
        }
        return out
    }

    nonisolated static func albumTitle(_ id: String) -> String? {
        if let a = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            return a.localizedTitle
        }
        return PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [id], options: nil).firstObject?.localizedTitle
    }

    // MARK: „Neu seit dem letzten Aufräumen“ (dauerhafte Änderungshistorie, iOS 16+)

    /// Aktueller Stand der Änderungshistorie als Daten (gespeichert am Sitzungsende, keine Medien-IDs).
    nonisolated static func currentChangeTokenData() -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: PHPhotoLibrary.shared().currentChangeToken,
                                          requiringSecureCoding: true)
    }

    /// Seit dem gespeicherten Stand hinzugefügte Medien. `nil`, wenn die Historie nicht mehr so weit zurückreicht
    /// (dann gilt ersatzweise das Aufnahmedatum).
    nonisolated static func insertedSince(_ data: Data) -> Set<String>? {
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
        else { return nil }
        do {
            let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: token)
            var ids = Set<String>()
            for change in changes {
                if let details = try? change.changeDetails(for: .asset) {
                    ids.formUnion(details.insertedLocalIdentifiers)
                    ids.subtract(details.deletedLocalIdentifiers)
                }
            }
            return VaultConcealment.shared.visible(ids)
        } catch {
            return nil
        }
    }

    /// Mitglieder eines Albums bzw. aller Alben eines Ordners (inkl. Unterordner).
    nonisolated static func assetIDs(inCollection id: String) -> Set<String> {
        var ids = Set<String>()
        if let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { a, _, _ in ids.insert(a.localIdentifier) }
        } else if let list = PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [id], options: nil).firstObject {
            PHCollection.fetchCollections(in: list, options: nil).enumerateObjects { c, _, _ in
                ids.formUnion(PhotoLibraryService.assetIDs(inCollection: c.localIdentifier))
            }
        }
        return VaultConcealment.shared.visible(ids)
    }

    /// Mitglieder eines Albums in Album-Reihenfolge.
    nonisolated static func orderedAssetIDs(inAlbum id: String) -> [String] {
        guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
        else { return [] }
        var ids: [String] = []
        PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { a, _, _ in ids.append(a.localIdentifier) }
        return VaultConcealment.shared.visible(ids) { $0 }
    }

    /// Zu einem Album hinzufügen. Änderung ist in der Fotos-App sichtbar (und mit iCloud-Fotos synchronisiert).
    func add(_ ids: [String], toAlbum albumID: String) async -> MediaWriteResult {
        guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
              album.canPerform(.addContent) else { return .failed }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        let box = UncheckedBox((album, assets))
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetCollectionChangeRequest(for: box.value.0)?.addAssets(box.value.1)
            }
        } catch {
            return Self.writeResult(error)
        }
        let members = Self.assetIDs(inCollection: albumID)
        return Set(ids).isSubset(of: members) ? .done : .failed
    }

    func remove(_ ids: [String], fromAlbum albumID: String) async -> MediaWriteResult {
        guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
              album.canPerform(.removeContent) else { return .failed }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        let box = UncheckedBox((album, assets))
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetCollectionChangeRequest(for: box.value.0)?.removeAssets(box.value.1)
            }
        } catch {
            return Self.writeResult(error)
        }
        return Self.assetIDs(inCollection: albumID).isDisjoint(with: ids) ? .done : .failed
    }

    /// Neues Album der Fotos-App anlegen; liefert dessen Kennung.
    func createAlbum(named name: String) async -> String? {
        let holder = PlaceholderBox()
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let r = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                holder.set(r.placeholderForCreatedAssetCollection.localIdentifier)
            }
        } catch {
            Diagnostics.error(.library, "album-create-failed", error)
            return nil
        }
        return holder.value
    }

    // MARK: Favoriten

    func setFavorite(_ ids: [String], _ favorite: Bool) async -> MediaWriteResult {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var targets: [PHAsset] = []
        assets.enumerateObjects { a, _, _ in if a.canPerform(.properties) { targets.append(a) } }
        guard !targets.isEmpty else { return .failed }
        let box = UncheckedBox(targets)
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                for a in box.value { PHAssetChangeRequest(for: a).isFavorite = favorite }
            }
        } catch {
            return Self.writeResult(error)
        }
        let after = self.assets(ids: ids)
        return after.count == ids.count && after.allSatisfy({ $0.isFavorite == favorite }) ? .done : .failed
    }

    // MARK: Existenzprüfung für den Abgleich

    /// Fehlender Zugriff ist kein Löschbeweis: nur bei vollem Zugriff gilt „fehlt“ als belastbar.
    func probe(_ ids: [String]) -> [ItemReference: ExistenceProbe] {
        var out: [ItemReference: ExistenceProbe] = [:]
        guard access.canRead else {
            for id in ids { out[.photo(id)] = .unknown }
            return out
        }
        // Existenz unabhängig vom Tresor prüfen: ein verborgenes Original ist nicht „entfernt“.
        let found = Self.existingIDs(ids)
        for id in ids {
            if found.contains(id) { out[.photo(id)] = .exists }
            else { out[.photo(id)] = access == .authorized ? .missingWithFullAccess : .unknown }
        }
        return out
    }

    /// Tatsächlich vorhandene Medien (auch verborgene) – nur für Existenzprüfungen, nie zum Anzeigen.
    nonisolated static func existingIDs(_ ids: [String]) -> Set<String> {
        guard !ids.isEmpty else { return [] }
        var found = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { a, _, _ in found.insert(a.localIdentifier) }
        return found
    }

    // MARK: Löschen (nur nach ausdrücklicher Bestätigung im PhotoMaid-Papierkorb)

    /// `PHAssetChangeRequest.deleteAssets` – das System zeigt seine eigene Bestätigung (nicht unterdrückbar);
    /// Medien landen 30 Tage in „Zuletzt gelöscht“. Danach wird jedes Medium einzeln nachgeprüft: nur, was wirklich
    /// fehlt, gilt als entfernt.
    func delete(ids: [String]) async -> OperationOutcome {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { a, _, _ in if a.canPerform(.delete) { assets.append(a) } }
        guard !assets.isEmpty else { return .failed(reason: "no-deletable-assets") }
        let targets = UncheckedBox(assets as NSArray)
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetChangeRequest.deleteAssets(targets.value)
            }
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return .cancelled
        } catch {
            Diagnostics.error(.cleanup, "delete-failed", error)
            return .failed(reason: (error as NSError).domain + ":\((error as NSError).code)")
        }
        let stillThere = Self.existingIDs(ids)
        let removed = Set(ids).subtracting(stillThere)
        if removed.count == ids.count { return .succeeded }
        return .partial(removed: Set(removed.map { ItemReference.photo($0) }))
    }

    // MARK: Neue Medien speichern (Bearbeitungen, Collagen, Videos)

    struct SaveRequest: Sendable {
        var fileURL: URL
        var isVideo: Bool
        var creationDate: Date?
        var latitude: Double?
        var longitude: Double?
        var favorite: Bool = false
        var albumID: String?
        /// Originaler Dateiname für die neue Datei (z. B. „IMG_1234 bearbeitet.heic“).
        var filename: String?
    }

    enum SaveResult: Equatable, Sendable {
        case saved(id: String)
        case failed
    }

    /// Legt ein neues Medium an (nie Überschreiben). Erfolg nur, wenn das neue Asset danach lesbar ist.
    func save(_ r: SaveRequest) async -> SaveResult {
        let holder = PlaceholderBox()
        let albumID = r.albumID
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let req = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = r.filename
                options.shouldMoveFile = false
                req.addResource(with: r.isVideo ? .video : .photo, fileURL: r.fileURL, options: options)
                req.creationDate = r.creationDate ?? Date()
                if let lat = r.latitude, let lon = r.longitude { req.location = CLLocation(latitude: lat, longitude: lon) }
                req.isFavorite = r.favorite
                if let placeholder = req.placeholderForCreatedAsset {
                    holder.set(placeholder.localIdentifier)
                    if let albumID,
                       let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
                       album.canPerform(.addContent) {
                        PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
                    }
                }
            }
        } catch {
            Diagnostics.error(.library, "save-failed", error)
            return .failed
        }
        guard let id = holder.value else {
            Diagnostics.log(.library, "save-missing-placeholder")
            return .failed
        }
        // PhotoKit may finish the write before its read-side fetch index is updated.
        // Retry visibility for a bounded period rather than reporting a false save failure.
        for attempt in 0..<12 {
            if Self.phAsset(id) != nil {
                changeToken += 1
                return .saved(id: id)
            }
            if attempt < 11 { try? await Task.sleep(for: .milliseconds(150)) }
        }
        Diagnostics.log(.library, "save-asset-not-yet-visible")
        return .failed
    }

    private static func writeResult(_ error: any Error) -> MediaWriteResult {
        if let e = error as? PHPhotosError, e.code == .userCancelled { return .cancelled }
        Diagnostics.error(.library, "write-failed", error)
        return .failed
    }
}

/// Kennung aus einem `performChanges`-Block nach außen reichen.
final class PlaceholderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    var value: String? { lock.withLock { _value } }
    func set(_ v: String) { lock.withLock { _value = v } }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
