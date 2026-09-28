import Foundation
import Observation
import Photos
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

enum MediaCategory: String, CaseIterable, Sendable, Identifiable {
    case photos, videos, screenshots
    var id: String { rawValue }
}

/// Leichtgewichtige, Sendable-Beschreibung eines PhotoKit-Assets.
struct MediaAsset: Hashable, Sendable, Identifiable {
    let id: String
    let kind: MediaKind
    let creationDate: Date?
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    let isLivePhoto: Bool
    let isFavorite: Bool
    let canDelete: Bool

    var reference: ItemReference { .photo(id) }
    var aspectRatio: CGFloat { pixelHeight > 0 ? CGFloat(pixelWidth) / CGFloat(pixelHeight) : 1 }
}

/// Einziger Zugang zu PhotoKit. Alle Requests ohne automatische Netzwerkfreigabe.
@MainActor
@Observable
final class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver {
    private(set) var access: PhotoAccess = .init(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    /// Erhöht sich bei jeder Mediatheksänderung (Screens laden daraufhin neu).
    private(set) var changeToken = 0
    @ObservationIgnored private var observing = false
    @ObservationIgnored let imageManager = PHCachingImageManager()

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
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root) { [weak self] _ in
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

    private func fetchResult(_ category: MediaCategory) -> PHFetchResult<PHAsset> {
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
        }
        return PHAsset.fetchAssets(with: options)
    }

    func count(_ category: MediaCategory) -> Int {
        guard access.canRead else { return 0 }
        return fetchResult(category).count
    }

    func assets(_ category: MediaCategory, limit: Int? = nil) -> [MediaAsset] {
        guard access.canRead else { return [] }
        let result = fetchResult(category)
        var out: [MediaAsset] = []
        out.reserveCapacity(min(result.count, limit ?? result.count))
        result.enumerateObjects { asset, idx, stop in
            if let limit, idx >= limit { stop.pointee = true; return }
            out.append(Self.describe(asset))
        }
        return out
    }

    func assets(ids: [String]) -> [MediaAsset] {
        guard access.canRead, !ids.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byID: [String: MediaAsset] = [:]
        result.enumerateObjects { a, _, _ in byID[a.localIdentifier] = Self.describe(a) }
        return ids.compactMap { byID[$0] }
    }

    func phAsset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    static func describe(_ a: PHAsset) -> MediaAsset {
        let isScreenshot = a.mediaSubtypes.contains(.photoScreenshot)
        let kind: MediaKind = a.mediaType == .video ? .video : (isScreenshot ? .screenshot : .photo)
        return MediaAsset(id: a.localIdentifier, kind: kind, creationDate: a.creationDate,
                          duration: a.duration, pixelWidth: a.pixelWidth, pixelHeight: a.pixelHeight,
                          isLivePhoto: a.mediaSubtypes.contains(.photoLive), isFavorite: a.isFavorite,
                          canDelete: a.canPerform(.delete))
    }

    // MARK: Existenzprüfung für den Abgleich

    /// Fehlender Zugriff ist kein Löschbeweis: nur bei vollem Zugriff gilt „fehlt“ als belastbar.
    func probe(_ ids: [String]) -> [ItemReference: ExistenceProbe] {
        var out: [ItemReference: ExistenceProbe] = [:]
        guard access.canRead else {
            for id in ids { out[.photo(id)] = .unknown }
            return out
        }
        let found = Set(assets(ids: ids).map(\.id))
        for id in ids {
            if found.contains(id) { out[.photo(id)] = .exists }
            else { out[.photo(id)] = access == .authorized ? .missingWithFullAccess : .unknown }
        }
        return out
    }

    // MARK: Löschung (nur nach ausdrücklicher Review-Aktion)

    /// `PHPhotoLibrary.performChanges` + `PHAssetChangeRequest.deleteAssets`.
    /// Das System zeigt seine eigene Bestätigung; sie wird nicht unterdrückt.
    /// PhotoKit belegt keinen Teilerfolg einzelner IDs: Erfolg gilt für den gesamten Request.
    func delete(ids: [String]) async -> OperationOutcome {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { a, _, _ in if a.canPerform(.delete) { assets.append(a) } }
        guard !assets.isEmpty else { return .failed(reason: "no-deletable-assets") }
        let requested = Set(assets.map(\.localIdentifier))
        let targets = UncheckedBox(assets as NSArray)
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                PHAssetChangeRequest.deleteAssets(targets.value)
            }
            if requested.count == ids.count { return .succeeded }
            return .partial(removed: Set(requested.map { ItemReference.photo($0) }))
        } catch let error as PHPhotosError where error.code == .userCancelled {
            return .cancelled
        } catch {
            return .failed(reason: (error as NSError).domain + ":\((error as NSError).code)")
        }
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
