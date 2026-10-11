import CoreLocation
import Foundation
import Observation
import Photos
import PhotosUI
import PhotoMaidCore
import UIKit

enum PhotoAccess: Equatable, Sendable {
    case notDetermined, authorized, limited, denied, restricted
    init(_ status: PHAuthorizationStatus) {
        switch status {
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
struct PhotoAlbum: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let isFolder: Bool
    let count: Int
    let latest: Date?
    let canAddAssets: Bool
    let children: [PhotoAlbum]
}
enum MediaWriteResult: Equatable, Sendable { case done, cancelled, failed }

/// PUBLIC PhotoKit facade. VaultImporter/VaultRestorer own their explicit,
/// authenticated private paths; every ordinary UI and processor uses this gate.
@MainActor @Observable
final class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var access: PhotoAccess = .init(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    private(set) var changeToken = 0
    @ObservationIgnored private var observing = false
    override init() { super.init(); startObservingIfAllowed() }
    func refreshAccess() {
        let new = PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        if new != access { access = new; changeToken += 1 }
        startObservingIfAllowed()
    }
    func bumpChangeToken() { changeToken += 1 }
    func requestAccess() async {
        access = PhotoAccess(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
        changeToken += 1; startObservingIfAllowed()
    }
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
        PHPhotoLibrary.shared().register(self); observing = true
    }
    nonisolated static func fetchOptions(_ category: MediaCategory?) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        switch category {
        case .photos: options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        case .videos: options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        case .screenshots:
            options.predicate = NSPredicate(format: "mediaType == %d AND (mediaSubtypes & %d) != 0", PHAssetMediaType.image.rawValue, PHAssetMediaSubtype.photoScreenshot.rawValue)
        case nil:
            options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        }
        return options
    }
    nonisolated static func loadAll() async -> [MediaAsset] {
        await Task.detached(priority: .userInitiated) {
            let policy = VaultIsolation.shared.snapshot
            guard policy.ready, PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead else { return [] }
            let result = PHAsset.fetchAssets(with: fetchOptions(nil))
            var out: [MediaAsset] = []; out.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                if VaultIsolation.shared.isPublic(asset, in: policy) { out.append(describe(asset)) }
            }
            return VaultIsolation.shared.snapshot.epoch == policy.epoch ? out : []
        }.value
    }
    func count(_ category: MediaCategory) -> Int {
        guard access.canRead else { return 0 }
        let policy = VaultIsolation.shared.snapshot
        guard policy.ready else { return 0 }
        var count = 0
        PHAsset.fetchAssets(with: Self.fetchOptions(category)).enumerateObjects { asset, _, _ in
            if VaultIsolation.shared.isPublic(asset, in: policy) { count += 1 }
        }
        return VaultIsolation.shared.snapshot.epoch == policy.epoch ? count : 0
    }
    func assets(ids: [String]) -> [MediaAsset] {
        let policy = VaultIsolation.shared.snapshot
        guard access.canRead, policy.ready, !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids.filter(policy.allows), options: nil)
        var byID: [String: MediaAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            if VaultIsolation.shared.isPublic(asset, in: policy) { byID[asset.localIdentifier] = Self.describe(asset) }
        }
        guard VaultIsolation.shared.snapshot.epoch == policy.epoch else { return [] }
        return ids.compactMap { byID[$0] }
    }
    func asset(_ id: String) -> MediaAsset? { assets(ids: [id]).first }
    nonisolated static func phAsset(_ id: String) -> PHAsset? { VaultIsolation.shared.publicAsset(id) }
    nonisolated static func describe(_ asset: PHAsset) -> MediaAsset {
        let screenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        let kind: MediaKind = asset.mediaType == .video ? .video : (screenshot ? .screenshot : .photo)
        let coordinate = asset.location?.coordinate
        return MediaAsset(id: asset.localIdentifier, kind: kind, creationDate: asset.creationDate, modificationDate: asset.modificationDate,
                          duration: asset.duration, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight,
                          isLivePhoto: asset.mediaSubtypes.contains(.photoLive), isFavorite: asset.isFavorite,
                          canDelete: asset.canPerform(.delete), canEditProperties: asset.canPerform(.properties),
                          latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                          subtypes: asset.mediaSubtypes.rawValue, burstIdentifier: asset.burstIdentifier)
    }
    nonisolated static func originalFilename(_ id: String) -> String? {
        guard let asset = phAsset(id) else { return nil }
        let resources = PHAssetResource.assetResources(for: asset)
        return (resources.first { $0.type == .photo || $0.type == .video } ?? resources.first)?.originalFilename
    }
    nonisolated static func hasRawAlternate(_ id: String) -> Bool {
        guard let asset = phAsset(id) else { return false }
        return PHAssetResource.assetResources(for: asset).contains { $0.type == .alternatePhoto }
    }
    nonisolated static func loadAlbums() async -> [PhotoAlbum] {
        await Task.detached(priority: .userInitiated) {
            guard VaultIsolation.shared.snapshot.ready, PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead else { return [] }
            return collect(PHCollectionList.fetchTopLevelUserCollections(with: nil), depth: 0)
        }.value
    }
    nonisolated private static func collect(_ result: PHFetchResult<PHCollection>, depth: Int) -> [PhotoAlbum] {
        let policy = VaultIsolation.shared.snapshot
        guard policy.ready else { return [] }
        var out: [PhotoAlbum] = []
        result.enumerateObjects { collection, _, _ in
            if let album = collection as? PHAssetCollection {
                let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.includeHiddenAssets = false
                var count = 0; var latest: Date?
                PHAsset.fetchAssets(in: album, options: options).enumerateObjects { asset, _, _ in
                    if VaultIsolation.shared.isPublic(asset, in: policy) {
                        count += 1
                        if latest == nil { latest = asset.creationDate }
                    }
                }
                out.append(PhotoAlbum(id: album.localIdentifier, title: album.localizedTitle ?? "", isFolder: false, count: count,
                                      latest: latest, canAddAssets: album.canPerform(.addContent), children: []))
            } else if let list = collection as? PHCollectionList, depth < 8 {
                let children = collect(PHCollection.fetchCollections(in: list, options: nil), depth: depth + 1)
                out.append(PhotoAlbum(id: list.localIdentifier, title: list.localizedTitle ?? "", isFolder: true,
                                      count: children.reduce(0) { $0 + $1.count }, latest: children.compactMap(\.latest).max(),
                                      canAddAssets: false, children: children))
            }
        }
        return VaultIsolation.shared.snapshot.epoch == policy.epoch ? out : []
    }
    nonisolated static func albumTitle(_ id: String) -> String? {
        guard VaultIsolation.shared.snapshot.ready else { return nil }
        if let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject { return album.localizedTitle }
        return PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [id], options: nil).firstObject?.localizedTitle
    }
    nonisolated static func currentChangeTokenData() -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: PHPhotoLibrary.shared().currentChangeToken, requiringSecureCoding: true)
    }
    nonisolated static func insertedSince(_ data: Data) -> Set<String>? {
        guard VaultIsolation.shared.snapshot.ready,
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data) else { return nil }
        do {
            let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: token)
            var ids = Set<String>()
            for change in changes {
                if let details = try? change.changeDetails(for: .asset) {
                    ids.formUnion(details.insertedLocalIdentifiers); ids.subtract(details.deletedLocalIdentifiers)
                }
            }
            return Set(ids.filter { phAsset($0) != nil })
        } catch { return nil }
    }
    nonisolated static func assetIDs(inCollection id: String) -> Set<String> {
        let policy = VaultIsolation.shared.snapshot
        guard policy.ready else { return [] }
        var ids = Set<String>()
        if let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
                if VaultIsolation.shared.isPublic(asset, in: policy) { ids.insert(asset.localIdentifier) }
            }
        } else if let list = PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [id], options: nil).firstObject {
            PHCollection.fetchCollections(in: list, options: nil).enumerateObjects { collection, _, _ in ids.formUnion(assetIDs(inCollection: collection.localIdentifier)) }
        }
        return VaultIsolation.shared.snapshot.epoch == policy.epoch ? ids : []
    }
    nonisolated static func orderedAssetIDs(inAlbum id: String) -> [String] {
        let policy = VaultIsolation.shared.snapshot
        guard policy.ready, let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else { return [] }
        var ids: [String] = []
        PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
            if VaultIsolation.shared.isPublic(asset, in: policy) { ids.append(asset.localIdentifier) }
        }
        return VaultIsolation.shared.snapshot.epoch == policy.epoch ? ids : []
    }
    func add(_ ids: [String], toAlbum albumID: String) async -> MediaWriteResult {
        guard let ticket = try? VaultIsolation.shared.ticket(for: ids),
              let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
              album.canPerform(.addContent) else { return .failed }
        let assets = ids.compactMap(Self.phAsset)
        guard !assets.isEmpty, assets.count == ids.count else { return .failed }
        let box = UncheckedBox((album, assets as NSArray))
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                guard ticket.isValid else { return }
                PHAssetCollectionChangeRequest(for: box.value.0)?.addAssets(box.value.1)
            }
        } catch { return Self.writeResult(error) }
        return ticket.isValid && Set(ids).isSubset(of: Self.assetIDs(inCollection: albumID)) ? .done : .failed
    }
    func remove(_ ids: [String], fromAlbum albumID: String) async -> MediaWriteResult {
        guard let ticket = try? VaultIsolation.shared.ticket(for: ids),
              let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
              album.canPerform(.removeContent) else { return .failed }
        let assets = ids.compactMap(Self.phAsset)
        guard !assets.isEmpty, assets.count == ids.count else { return .failed }
        let box = UncheckedBox((album, assets as NSArray))
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                guard ticket.isValid else { return }
                PHAssetCollectionChangeRequest(for: box.value.0)?.removeAssets(box.value.1)
            }
        } catch { return Self.writeResult(error) }
        return ticket.isValid && Self.assetIDs(inCollection: albumID).isDisjoint(with: ids) ? .done : .failed
    }
    func createAlbum(named name: String) async -> String? {
        guard VaultIsolation.shared.snapshot.ready else { return nil }
        let holder = PlaceholderBox()
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                holder.set(PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name).placeholderForCreatedAssetCollection.localIdentifier)
            }
        } catch { Diagnostics.error(.library, "album-create-failed", error); return nil }
        return holder.value
    }
    func setFavorite(_ ids: [String], _ favorite: Bool) async -> MediaWriteResult {
        guard let ticket = try? VaultIsolation.shared.ticket(for: ids) else { return .failed }
        let targets = ids.compactMap(Self.phAsset).filter { $0.canPerform(.properties) }
        guard targets.count == ids.count, !targets.isEmpty else { return .failed }
        let box = UncheckedBox(targets)
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                guard ticket.isValid else { return }
                for asset in box.value { PHAssetChangeRequest(for: asset).isFavorite = favorite }
            }
        } catch { return Self.writeResult(error) }
        let after = assets(ids: ids)
        return ticket.isValid && after.count == ids.count && after.allSatisfy { $0.isFavorite == favorite } ? .done : .failed
    }
    func probe(_ ids: [String]) -> [ItemReference: ExistenceProbe] {
        var out: [ItemReference: ExistenceProbe] = [:]
        let policy = VaultIsolation.shared.snapshot
        for id in ids {
            guard access.canRead, policy.allows(id) else { out[.photo(id)] = .unknown; continue }
            // A blocked legacy fingerprint is not a deletion proof.
            if let raw = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                out[.photo(id)] = VaultIsolation.shared.isPublic(raw, in: policy) ? .exists : .unknown
            } else { out[.photo(id)] = access == .authorized ? .missingWithFullAccess : .unknown }
        }
        return out
    }
    func delete(ids: [String]) async -> OperationOutcome {
        guard let ticket = try? VaultIsolation.shared.ticket(for: ids) else { return .failed(reason: "private-media") }
        let assets = ids.compactMap(Self.phAsset).filter { $0.canPerform(.delete) }
        guard assets.count == ids.count, !assets.isEmpty else { return .failed(reason: "no-deletable-assets") }
        let box = UncheckedBox(assets as NSArray)
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                guard ticket.isValid else { return }
                PHAssetChangeRequest.deleteAssets(box.value)
            }
        } catch let error as PHPhotosError where error.code == .userCancelled { return .cancelled }
        catch { Diagnostics.error(.cleanup, "delete-failed", error); return .failed(reason: "photo-delete-failed") }
        guard ticket.isValid else { return .failed(reason: "privacy-boundary-changed") }
        var stillThere = Set<String>()
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in stillThere.insert(asset.localIdentifier) }
        let removed = Set(ids).subtracting(stillThere)
        return removed.count == ids.count ? .succeeded : .partial(removed: Set(removed.map(ItemReference.photo)))
    }

    struct SaveRequest: Sendable {
        var fileURL: URL
        var isVideo: Bool
        var creationDate: Date?
        var latitude: Double?
        var longitude: Double?
        var favorite: Bool = false
        var albumID: String?
        var filename: String?
        /// Complete source lineage, not just the first photo of a collage/movie.
        var sourceIDs: [String] = []
        var originatingEpoch: UUID? = nil
    }
    enum SaveResult: Equatable, Sendable { case saved(id: String), failed }
    func save(_ request: SaveRequest) async -> SaveResult {
        guard let ticket = try? VaultIsolation.shared.ticket(for: request.sourceIDs),
              request.originatingEpoch == nil || request.originatingEpoch == ticket.epoch,
              request.sourceIDs.allSatisfy({ Self.phAsset($0) != nil }) else { return .failed }
        let holder = PlaceholderBox()
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                guard ticket.isValid else { return }
                let asset = PHAssetCreationRequest.forAsset(), options = PHAssetResourceCreationOptions()
                options.originalFilename = request.filename; options.shouldMoveFile = false
                asset.addResource(with: request.isVideo ? .video : .photo, fileURL: request.fileURL, options: options)
                asset.creationDate = request.creationDate ?? Date()
                if let lat = request.latitude, let lon = request.longitude { asset.location = CLLocation(latitude: lat, longitude: lon) }
                asset.isFavorite = request.favorite
                if let placeholder = asset.placeholderForCreatedAsset {
                    holder.set(placeholder.localIdentifier)
                    if let albumID = request.albumID,
                       let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject,
                       album.canPerform(.addContent) { PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray) }
                }
            }
            guard let id = holder.value else { return .failed }
            // Persist ownership even if an already submitted PhotoKit write
            // finishes after the user has moved its source into the vault.
            try VaultIsolation.shared.registerOutput(id, sources: Set(request.sourceIDs), originatingEpoch: ticket.epoch)
            guard ticket.isValid else { return .failed }
            for attempt in 0..<12 {
                guard ticket.isValid, !Task.isCancelled else { return .failed }
                if Self.phAsset(id) != nil { changeToken += 1; return .saved(id: id) }
                if attempt < 11 { try await Task.sleep(for: .milliseconds(150)) }
            }
        } catch { Diagnostics.error(.library, "save-failed", error) }
        return .failed
    }
    private static func writeResult(_ error: any Error) -> MediaWriteResult {
        if let photos = error as? PHPhotosError, photos.code == .userCancelled { return .cancelled }
        Diagnostics.error(.library, "write-failed", error); return .failed
    }
}

final class PlaceholderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? { lock.withLock { stored } }
    func set(_ value: String) { lock.withLock { stored = value } }
}
extension UIApplication {
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}
