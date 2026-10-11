import Foundation
import Photos
import PhotoMaidCore

/// Coordinates public isolation only. Does not delete files, change credentials,
/// import media, or claim to repair the existing vault's storage transactions.
@MainActor
final class VaultIsolationCoordinator {
    static let shared = VaultIsolationCoordinator()
    weak var app: AppModel?
    private var job: Task<Void, Never>?
    private var generation = UUID()

    func reconcileAuthenticatedVault() {
        let vault = VaultStore.shared
        guard vault.phase == .unlocked else { return }
        let items = vault.index.items
        let edits = app?.kv?.vaultMigrationValue(StoreKeys.edits) ?? []
        let stamp = UUID(); generation = stamp
        job?.cancel()
        job = Task {
            let ledger = await app?.ledger.snapshotState()
            let references = Set((ledger?.records.keys.filter { $0.provider == .photoLibrary }.map(\.localIdentifier) ?? []) +
                                 edits.flatMap { [$0.newId, $0.sourceId] }.filter { !$0.isEmpty })
            let hidden = await Task.detached(priority: .userInitiated) { () -> Set<String> in
                let fingerprints = items.map(VaultIsolation.Fingerprint.init)
                guard !fingerprints.isEmpty else { return [] }
                var result = Set<String>()
                let all = PHAsset.fetchAssets(with: PhotoLibraryService.fetchOptions(nil))
                all.enumerateObjects { asset, _, _ in
                    let candidates = fingerprints.filter { fingerprint in
                        guard fingerprint.video == (asset.mediaType == .video) else { return false }
                        guard let ms = fingerprint.creationMs, let date = asset.creationDate else { return true }
                        return abs(date.timeIntervalSince1970 * 1000 - Double(ms)) < 1000
                    }
                    if !candidates.isEmpty {
                        let names = Set(PHAssetResource.assetResources(for: asset).map { $0.originalFilename.lowercased() })
                        if candidates.contains(where: { $0.matches(asset, names: names) }) { result.insert(asset.localIdentifier) }
                    }
                }
                var present = Set<String>()
                PHAsset.fetchAssets(withLocalIdentifiers: Array(references), options: nil).enumerateObjects { asset, _, _ in present.insert(asset.localIdentifier) }
                result.formUnion(references.subtracting(present))
                return result
            }.value
            guard !Task.isCancelled, generation == stamp, vault.phase == .unlocked, vault.index.items == items else { return }
            do {
                try VaultIsolation.shared.reconcile(items: items, retainedSourceIDs: Set(items.compactMap(\.sourceID)),
                                                   edits: edits, additionalPrivateIDs: hidden)
                app?.applyVaultIsolation()
            } catch {
                // The reference monitor remains fail-closed on a write failure.
                app?.applyVaultIsolation()
            }
        }
    }
    func invalidate() { generation = UUID(); job?.cancel(); job = nil }
}

extension VaultStore {
    func attach(app: AppModel) { VaultIsolationCoordinator.shared.app = app }
}

extension PreviewPipeline {
    /// Clearing the working set also stops PhotoKit's preheating for old assets.
    func clear() { updateCache(window: [], targetSize: .zero) }
}
