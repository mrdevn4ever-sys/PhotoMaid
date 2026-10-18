import Observation
import Photos
import PhotoMaidCore
import UIKit

enum PhotoGameSource: Equatable, Sendable {
    case library, favorites, collection(id: String, title: String)
}

/// Separate preview storage per game: loading Snake pictures never replaces a Memory round.
@MainActor @Observable
final class PhotoGamePhotos {
    /// Single authoritative safe scope for Blocks backgrounds AND its existing app photo picker.
    /// Availability in iCloud never bypasses the same permission, album and vault filters.
    static func gameCandidates(app: AppModel) -> [MediaAsset] {
        guard app.gamePhotoScopeReady,
              PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead,
              VaultConcealment.shared.analysisReady else { return [] }
        return VaultConcealment.shared.visible(app.cleanupMedia.filter { !$0.isVideo }, id: \.id)
    }
    private(set) var photoIDs: [String] = []
    private(set) var images: [String: UIImage] = [:]
    private(set) var isLoading = false
    private(set) var randomSource: PhotoGameSource?
    private(set) var allowsCloud = true
    var error: String?
    @ObservationIgnored private var loadingTask: Task<Void, Never>?
    @ObservationIgnored private var loadID = UUID()
    private var visibleIDs: Set<String>?
    @ObservationIgnored private let canUsePhotos: @MainActor ([String]) -> Bool

    init(canUsePhotos: (@MainActor ([String]) -> Bool)? = nil) { self.canUsePhotos = canUsePhotos ?? Self.allowed }

    func clear() {
        cancelLoading()
        photoIDs = []; images = [:]; randomSource = nil; error = nil
    }

    func startPhotos(_ selection: [String], previews: PreviewPipeline, allowNetwork: Bool,
                     minimumCount: Int = 2, ready: @escaping @MainActor () -> Void) {
        startPhotos(selection, allowNetwork: allowNetwork, minimumCount: minimumCount, load: { id in
            let result = await previews.image(for: id, targetSize: CGSize(width: 512, height: 512), allowNetwork: allowNetwork, contentMode: .aspectFill)
            if case .image(let image) = result { return image }
            return nil
        }, ready: ready)
    }

    func startPhotos(_ selection: [String], allowNetwork: Bool = false, minimumCount: Int = 2,
                     load: @escaping @MainActor (String) async -> UIImage?, ready: @escaping @MainActor () -> Void) {
        var seen = Set<String>()
        let ids = selection.filter { !$0.isEmpty && seen.insert($0).inserted }
        prepare(count: ids.count, source: nil, allowNetwork: allowNetwork, minimumCount: minimumCount,
                exactCount: true, candidates: { ids }, load: load, ready: ready)
    }

    func startRandom(source: PhotoGameSource, count: Int, app: AppModel, allowNetwork: Bool,
                     minimumCount: Int = 2, exactCount: Bool = true, ready: @escaping @MainActor () -> Void) {
        prepare(count: count, source: source, allowNetwork: allowNetwork, minimumCount: minimumCount,
                exactCount: exactCount, candidates: {
            let scope: PhotoMemorySelection.Scope
            switch source {
            case .library: scope = .library
            case .favorites: scope = .favorites
            case .collection(let id, _):
                scope = .collection(await Task.detached(priority: .utility) {
                    PhotoLibraryService.assetIDs(inCollection: id)
                }.value)
            }
            return PhotoMemorySelection.pool(app.visibleMedia.map {
                .init(id: $0.id, isPhoto: !$0.isVideo, isFavorite: $0.isFavorite)
            }, scope: scope)
        }, load: { id in
            let result = await app.previews.image(for: id, targetSize: CGSize(width: 512, height: 512), allowNetwork: allowNetwork, contentMode: .aspectFill)
            if case .image(let image) = result { return image }
            return nil
        }, ready: ready)
    }

    func startRandom(_ candidates: [String], count: Int, minimumCount: Int = 2, exactCount: Bool = true,
                     load: @escaping @MainActor (String) async -> UIImage?, ready: @escaping @MainActor () -> Void) {
        prepare(count: count, source: .library, allowNetwork: false, minimumCount: minimumCount,
                exactCount: exactCount, candidates: { candidates }, load: load, ready: ready)
    }

    private func prepare(count: Int, source: PhotoGameSource?, allowNetwork: Bool, minimumCount: Int, exactCount: Bool,
                         candidates: @escaping @MainActor () async -> [String],
                         load: @escaping @MainActor (String) async -> UIImage?, ready: @escaping @MainActor () -> Void) {
        cancelLoading()
        guard minimumCount >= 1, minimumCount <= PhotoMemoryGame.maximumPairs,
              (minimumCount...PhotoMemoryGame.maximumPairs).contains(count) else { error = L("memory_unavailable"); return }
        isLoading = true; error = nil
        let token = loadID
        loadingTask = Task { [weak self] in
            let pool = await candidates()
            guard let self, !Task.isCancelled, self.loadID == token else { return }
            var seen = Set<String>()
            let unique = pool.filter { !$0.isEmpty && seen.insert($0).inserted }
            let wanted = exactCount ? count : min(count, unique.count)
            let ids = source == nil ? unique : PhotoMemorySelection.sample(unique, pairCount: wanted, minimumCount: minimumCount)
            var loaded: [String: UIImage] = [:]
            var used: [String] = []
            if wanted >= minimumCount, ids.count >= wanted {
                for id in ids {
                    guard !Task.isCancelled else { return }
                    guard self.permitted([id]) else { if source != nil { continue }; break }
                    if let image = await load(id) {
                        loaded[id] = image; used.append(id)
                        if used.count == wanted { break }
                    } else if source == nil { break }
                }
            }
            guard !Task.isCancelled, self.loadID == token else { return }
            self.isLoading = false; self.loadingTask = nil
            let enough = exactCount ? used.count == wanted : used.count >= minimumCount
            guard wanted >= minimumCount, enough, self.permitted(used) else {
                self.error = source == nil ? L("memory_unavailable") : L("game_photos_missing", exactCount ? count : minimumCount)
                return
            }
            self.photoIDs = used; self.images = loaded; self.randomSource = source; self.allowsCloud = allowNetwork
            ready()
        }
    }

    func cancelLoading() { loadID = UUID(); loadingTask?.cancel(); loadingTask = nil; isLoading = false }

    /// Secure background window for Foto Blocks, reusing this central loader and PreviewPipeline.
    /// At most current + next are retained. iCloud downloads use Apple's existing Photos pipeline.
    func prepareBackgroundWindow(_ selection: [String], previews: PreviewPipeline, targetSize: CGSize) {
        prepareBackgroundWindow(selection) { id, allowNetwork in
            let result = await previews.image(for: id, targetSize: targetSize, allowNetwork: allowNetwork,
                                              contentMode: .aspectFit, exactSize: true)
            if case .image(let image) = result { return image }
            return nil
        }
    }

    func prepareBackgroundWindow(_ selection: [String], allowNetwork: Bool = true,
                                 load: @escaping @MainActor (String, Bool) async -> UIImage?) {
        var seen = Set<String>()
        let wanted = selection.filter { seen.insert($0).inserted && permitted([$0]) }.prefix(2)
        let ids = Array(wanted)
        let sameWindow = ids == photoIDs && allowsCloud == allowNetwork
        // Library metadata refreshes must not restart an in-flight iCloud download.
        guard !sameWindow || (!isLoading && ids.contains(where: { images[$0] == nil })) else { return }
        cancelLoading()
        photoIDs = ids; images = images.filter { ids.contains($0.key) && permitted([$0.key]) }
        allowsCloud = allowNetwork; randomSource = nil; error = nil
        let token = loadID
        isLoading = !ids.isEmpty
        loadingTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.loadID == token { self.isLoading = false; self.loadingTask = nil }
            }
            for id in ids {
                guard !Task.isCancelled, self.loadID == token else { return }
                if self.images[id] != nil { continue }
                let image = await load(id, allowNetwork)
                guard !Task.isCancelled, self.loadID == token, self.permitted([id]) else { return }
                if let image { self.images[id] = image }
            }
        }
    }

    /// Fail closed when permissions/exclusions change, including pending requests and cached images.
    func restrictBackgroundWindow(to visible: Set<String>) {
        guard visibleIDs != visible || photoIDs.contains(where: { !permitted([$0]) }) else { return }
        visibleIDs = visible
        cancelLoading()
        photoIDs = photoIDs.filter { permitted([$0]) }
        images = images.filter { photoIDs.contains($0.key) }
    }

    func permittedIDs(_ selection: [String]) -> [String] { selection.filter { permitted([$0]) } }

    @discardableResult func validatePhotos() -> Bool {
        guard !photoIDs.isEmpty, !permitted(photoIDs) else { return false }
        clear(); error = L("memory_unavailable")
        return true
    }

    /// Updated atomically with AppModel.visibleMedia, including hidden photos and hidden albums.
    func updateVisibility(_ ids: Set<String>) { visibleIDs = ids }

    private func permitted(_ ids: [String]) -> Bool {
        (visibleIDs.map { Set(ids).isSubset(of: $0) } ?? true) && canUsePhotos(ids)
    }

    func image(for id: String) -> UIImage? {
        guard photoIDs.contains(id), visibleIDs?.contains(id) != false,
              PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead,
              VaultConcealment.shared.analysisReady,
              !VaultConcealment.shared.isConcealed(id) else { return nil }
        return images[id]
    }

    private static func allowed(_ ids: [String]) -> Bool {
        guard PhotoAccess(PHPhotoLibrary.authorizationStatus(for: .readWrite)).canRead,
              VaultConcealment.shared.analysisReady,
              !ids.contains(where: { VaultConcealment.shared.isConcealed($0) }) else { return false }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count == ids.count else { return false }
        return (0..<assets.count).allSatisfy { assets.object(at: $0).mediaType == .image }
    }
}
