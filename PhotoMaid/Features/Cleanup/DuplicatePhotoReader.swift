import CryptoKit
import Foundation
import Photos
import PhotoMaidCore

/// Ausschließlich für Duplikate: ALLE PhotoKit-Ressourcen, unverändert, ohne Klartext-Tempdateien.
/// Unbekannte Größen und beide Prüfsummen entstehen in einem einzigen Streaming-Durchlauf.
final class DuplicatePhotoReader: @unchecked Sendable {
    // ResourceStream.read waits for PhotoKit callbacks. Never occupy Swift's
    // cooperative executor with all four readers: their callbacks need workers too.
    private static let reads = DispatchQueue(label: "app.photomaid.duplicate-reads", qos: .utility, attributes: .concurrent)
    private struct Digests: Sendable {
        let bytes: Int64
        let partial: String
        let full: String
        let checkedAt: Date
    }
    private struct Key: Hashable { let id: String; let prefix: Int }
    private let lock = NSLock()
    private var cached: [Key: Digests] = [:]
    private let media: [String: MediaAsset]
    private let includeCloud: Bool
    private let cloudChanged: @Sendable (Bool) -> Void
    private var cloudRequests = 0

    init(media: [MediaAsset], includeCloud: Bool, cloudChanged: @escaping @Sendable (Bool) -> Void) {
        self.media = Dictionary(media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.includeCloud = includeCloud
        self.cloudChanged = cloudChanged
    }

    func prepare(_ asset: MediaAsset, prefetched: UncheckedBox<PHAsset>?, record: SizeRecord?) async throws -> SizeRecord {
        guard let prefetched, prefetched.value.modificationDate == asset.modificationDate else {
            return SizeRecord(modified: asset.modificationDate, state: .unreadable, checkedAt: Date())
        }
        // Schlechte Messungen werden bei „Erneut suchen“ sofort erneut versucht, nicht erst nach 12/24 Stunden.
        if let record, record.state == .known, record.isCurrent(modified: asset.modificationDate) { return record }
        let cancellation = DuplicateReadCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                Self.reads.async { [self] in
                    do {
                        let hashes = try read(asset.id, prefetched: prefetched, prefix: 64 * 1024, cancellation: cancellation)
                        continuation.resume(returning: SizeRecord(modified: asset.modificationDate, state: .known, bytes: hashes.bytes,
                            checkedAt: Date(), partialHash: hashes.partial, fullHash: hashes.full))
                    } catch is CancellationError { continuation.resume(throwing: CancellationError()) }
                    catch {
                        let cloud: Bool
                        if let issue = error as? ResourceStream.ResourceStreamError {
                            switch issue {
                            case .networkRequired, .networkUnavailable: cloud = true
                            default: cloud = false
                            }
                        } else { cloud = false }
                        continuation.resume(returning: SizeRecord(modified: asset.modificationDate,
                            state: cloud ? .notLocal : .unreadable, checkedAt: Date()))
                    }
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    func hash(_ id: String, limit: Int?, expectedSize: Int64?) throws -> String? {
        let value = try read(id, prefetched: nil, prefix: limit ?? 64 * 1024)
        if let expectedSize, value.bytes != expectedSize { throw DuplicateReadError.incompleteOrChanged }
        return limit == nil ? value.full : value.partial
    }

    var measurements: [String: SizeRecord] {
        lock.withLock {
            var values: [String: SizeRecord] = [:]
            for (key, value) in cached where key.prefix == 64 * 1024 {
                values[key.id] = SizeRecord(modified: media[key.id]?.modificationDate, state: .known,
                    bytes: value.bytes, checkedAt: value.checkedAt, partialHash: value.partial, fullHash: value.full)
            }
            return values
        }
    }

    private func read(_ id: String, prefetched: UncheckedBox<PHAsset>?, prefix: Int,
                      cancellation: DuplicateReadCancellation? = nil) throws -> Digests {
        try Task.checkCancellation()
        try cancellation?.check()
        guard !VaultConcealment.shared.isConcealed(id), let expected = media[id] else { throw DuplicateReadError.incompleteOrChanged }
        let key = Key(id: id, prefix: prefix)
        if let ready = lock.withLock({ cached[key] }) { return ready }
        guard let asset = prefetched?.value ?? PhotoLibraryService.phAsset(id), asset.modificationDate == expected.modificationDate else {
            throw DuplicateReadError.incompleteOrChanged
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { throw ResourceStream.ResourceStreamError.notAvailable }
        var parts: [DuplicateResourceDigest] = []
        for resource in resources {
            try Task.checkCancellation()
            try cancellation?.check()
            guard !VaultConcealment.shared.isConcealed(id) else { throw CancellationError() }
            do {
                parts.append(try digest(resource, id: id, prefix: prefix, network: false, cancellation: cancellation))
            } catch ResourceStream.ResourceStreamError.networkRequired {
                guard includeCloud else { throw ResourceStream.ResourceStreamError.networkRequired }
                guard AnalysisNetwork.shared.permitsCloud else { throw ResourceStream.ResourceStreamError.networkUnavailable }
                cloudActivity(1)
                defer { cloudActivity(-1) }
                parts.append(try digest(resource, id: id, prefix: prefix, network: true, cancellation: cancellation))
            }
        }
        guard !VaultConcealment.shared.isConcealed(id) else { throw CancellationError() }
        guard let partial = DuplicateResourceSet.hash(parts, partial: true), let full = DuplicateResourceSet.hash(parts, partial: false) else {
            throw DuplicateReadError.incompleteOrChanged
        }
        let value = Digests(bytes: parts.reduce(0) { $0 + $1.bytes }, partial: partial, full: full, checkedAt: Date())
        lock.withLock { cached[key] = value }
        return value
    }

    private func digest(_ resource: PHAssetResource, id: String, prefix: Int, network: Bool,
                        cancellation: DuplicateReadCancellation?) throws -> DuplicateResourceDigest {
        let stream = ResourceStream(resource: resource, allowNetwork: network,
                                    networkPermitted: { AnalysisNetwork.shared.permitsCloud },
                                    accessAllowed: { cancellation?.isCancelled != true && !VaultConcealment.shared.isConcealed(id) })
        defer { stream.close() }
        var full = SHA256(), partial = SHA256()
        var bytes: Int64 = 0
        var left = prefix
        while true {
            try Task.checkCancellation()
            try cancellation?.check()
            let data = try stream.read(maxLength: 1 << 20)
            if data.isEmpty { break }
            full.update(data: data)
            bytes += Int64(data.count)
            if left > 0 {
                let n = min(left, data.count)
                partial.update(data: Data(data.prefix(n)))
                left -= n
            }
        }
        return DuplicateResourceDigest(role: resource.type.rawValue, bytes: bytes,
            partial: partial.finalize().map { String(format: "%02x", $0) }.joined(),
            full: full.finalize().map { String(format: "%02x", $0) }.joined())
    }

    private func cloudActivity(_ delta: Int) {
        lock.withLock {
            cloudRequests += delta
            cloudChanged(cloudRequests > 0)
        }
    }
}

private final class DuplicateReadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
    func check() throws { if isCancelled { throw CancellationError() } }
}
