import Foundation
import Photos
import PhotoMaidCore

struct AnalysisSource: Sendable {
    let id: String
    let fingerprint: AnalysisFingerprint
    let captured: Date?
    let screenshot: Bool
    init(_ asset: MediaAsset) {
        id = asset.id
        fingerprint = AnalysisFingerprint(modified: asset.modificationDate, width: asset.pixelWidth, height: asset.pixelHeight)
        captured = asset.creationDate; screenshot = asset.kind == .screenshot
    }
}
enum AnalysisRunStage: String, Sendable {
    /// `cooling`: wartet, bis das iPhone abgekühlt ist, und macht dann von selbst weiter. `thermal`: kritisch heiß, angehalten.
    case idle, preparing, local, cloud, comparing, paused, waitingWiFi, cooling, thermal, storageError, privacy, changed, finished
}
enum AnalysisRunEvent: Sendable {
    case counts(AnalysisCounts, AnalysisRunStage)
    case download(Double)
}
private enum AnalysisStop: Error { case network, thermal, privacy, changed }

/// At most two local or three cloud requests (throttled by temperature), never one task per asset in a large library.
/// An owned utility task coordinates the work; Vision and SQLite never run on MainActor.
enum AnalysisRunner {
    static func run(sources: [AnalysisSource], kind: AnalysisKind, includeCloud: Bool,
                    retryFailures: Bool, background: Bool = false,
                    emit: @escaping @Sendable (AnalysisRunEvent) async -> Void) async -> AnalysisRunStage {
        do {
            try checkConditions(cloud: false)
            let db = try AnalysisDatabase.shared()
            let current = Dictionary(sources.map { ($0.id, $0.fingerprint) }, uniquingKeysWith: { a, _ in a })
            let algorithm = LocalPhotoAnalyzer.algorithm(kind)
            // Inputs must be an already-loaded, authorized snapshot. Removing index rows never deletes photos.
            for storedKind in AnalysisKind.allCases {
                let rows = try db.rows(storedKind)
                let stale = Set(rows.filter { current[$0.id] != $0.fingerprint || VaultConcealment.shared.isConcealed($0.id) }.map(\.id))
                try db.remove(stale)
            }
            var saved = try db.rows(kind)
            try db.remove(Set(saved.filter { $0.algorithm != algorithm }.map(\.id)), kind: kind)
            saved = try db.rows(kind)
            let byID = Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var items = sources.sorted {
                if kind == .documents, $0.screenshot != $1.screenshot { return $0.screenshot }
                if $0.captured != $1.captured { return ($0.captured ?? .distantPast) > ($1.captured ?? .distantPast) }
                return $0.id < $1.id
            }.map { source -> AnalysisItem in
                var item = byID[source.id] ?? AnalysisItem(id: source.id, kind: kind,
                    fingerprint: source.fingerprint, algorithm: algorithm, captured: source.captured)
                if retryFailures, item.state == .failed { item.failures = 0; item.retryAfter = nil }
                return item
            }
            var counts = AnalysisCounts()
            for item in items { counts.add(item.state) }
            var graph = AnalysisSimilarityGraph()
            for pair in try db.links() { graph.join(pair.0, pair.1) }
            await emit(.counts(counts, .local))
            let local = items.indices.filter {
                let item = items[$0]
                guard item.canAttempt(now: Date(), retryFailures: retryFailures) else { return false }
                // Resume does not retry every known cloud-only asset. Explicit retry can recheck local availability.
                return retryFailures || (item.state != .waitingForCloud && item.state != .insufficientQuality)
            }
            try await pass(indices: local, items: &items, counts: &counts, graph: &graph,
                           db: db, cloud: false, background: background, emit: emit)
            if includeCloud {
                let remote = items.indices.filter {
                    items[$0].state == .waitingForCloud || items[$0].state == .insufficientQuality
                }.filter { kind != .blurry || max(items[$0].fingerprint.width, items[$0].fingerprint.height) >= 512 }
                if !remote.isEmpty {
                    guard AnalysisNetwork.shared.permitsCloud else { throw AnalysisStop.network }
                    try await pass(indices: remote, items: &items, counts: &counts, graph: &graph,
                                   db: db, cloud: true, background: background, emit: emit)
                }
            }
            try Task.checkCancellation()
            await emit(.counts(counts, .finished))
            return .finished
        } catch is CancellationError { return .paused }
        catch AnalysisStop.network { return .waitingWiFi }
        catch AnalysisStop.thermal { return .thermal }
        catch AnalysisStop.privacy { return .privacy }
        catch AnalysisStop.changed { return .changed }
        catch { return .storageError }
    }

    /// Lokal höchstens 2, iCloud (nur WLAN) höchstens 3 Fotos gleichzeitig. Wird das iPhone warm, wird gedrosselt
    /// bzw. gewartet und danach von selbst weitergemacht (`ThrottledWork`); nur bei „kritisch“ wird angehalten.
    private static func pass(indices: [Int], items: inout [AnalysisItem], counts: inout AnalysisCounts,
                             graph: inout AnalysisSimilarityGraph, db: AnalysisDatabase, cloud: Bool, background: Bool,
                             emit: @escaping @Sendable (AnalysisRunEvent) async -> Void) async throws {
        let stage: AnalysisRunStage = cloud ? .cloud : .local
        await emit(.counts(counts, stage))
        let queued = items
        do {
            try await ThrottledWork.run(
                indices, maxParallel: cloud ? 3 : 2, thermal: { Self.thermalLevel() },
                beforeStart: { try Self.checkConditions(cloud: cloud) },
                waiting: { await emit(.counts(counts, .cooling)) },
                work: { index -> AnalysisOutput in
                    let item = queued[index]
                    try Task.checkCancellation()
                    if item.kind == .similar, let feature = try db.feature(item.id), !feature.isEmpty {
                        var ready = item; ready.state = .featuresReady
                        return AnalysisOutput(item: ready)
                    }
                    return await LocalPhotoAnalyzer.analyze(item, cloud: cloud, background: background) { value in
                        Task { await emit(.download(value)) }
                    }
                },
                result: { position, output in
                    let index = indices[position]
                    try Task.checkCancellation()
                    if output.interrupted { try Self.checkConditions(cloud: cloud); throw CancellationError() }
                    var updated = output.item
                    guard let asset = PhotoLibraryService.phAsset(updated.id),
                          updated.fingerprint == AnalysisFingerprint(modified: asset.modificationDate,
                              width: asset.pixelWidth, height: asset.pixelHeight) else {
                        try db.remove([updated.id]); throw AnalysisStop.changed
                    }
                    guard try VaultConcealment.shared.withAnalysisAccess([updated.id], {
                        try db.save(updated, feature: output.feature); return true
                    }) == true else { throw AnalysisStop.privacy }
                    if updated.kind == .similar, updated.state == .featuresReady {
                        do {
                            await emit(.counts(counts, .comparing))
                            guard let feature = try db.feature(updated.id) else { throw AnalysisDatabaseError.corrupt }
                            for neighbor in try db.neighbors(updated) {
                                try Task.checkCancellation()
                                guard !VaultConcealment.shared.isConcealed(neighbor), let other = try db.feature(neighbor) else { continue }
                                // A failed or nonfinite distance is an error, never a zero-distance match.
                                if try LocalPhotoAnalyzer.distance(feature, other) <= 0.45 {
                                    var proposed = graph
                                    if proposed.join(updated.id, neighbor) {
                                        guard try VaultConcealment.shared.withAnalysisAccess([updated.id, neighbor], {
                                            try db.link(updated.id, neighbor); return true
                                        }) == true else { throw AnalysisStop.privacy }
                                        graph = proposed
                                    }
                                }
                            }
                            updated.state = .complete
                        } catch is CancellationError { throw CancellationError() }
                        catch AnalysisStop.privacy { throw AnalysisStop.privacy }
                        catch { updated.fail(now: Date()) }
                        guard try VaultConcealment.shared.withAnalysisAccess([updated.id], {
                            try db.save(updated); return true
                        }) == true else { throw AnalysisStop.privacy }
                    }
                    counts.add(items[index].state, delta: -1); counts.add(updated.state)
                    items[index] = updated
                    await emit(.counts(counts, stage))
                })
        } catch ThrottledWorkError.critical {
            throw AnalysisStop.thermal
        }
    }

    /// Wärmestufe des Geräts für die Drosselung.
    static func thermalLevel() -> WorkThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .fair
        }
    }
    /// Wärme wird nicht hier, sondern über `ThrottledWork` behandelt (drosseln/warten statt abbrechen).
    private static func checkConditions(cloud: Bool) throws {
        try Task.checkCancellation()
        guard VaultConcealment.shared.analysisReady else { throw AnalysisStop.privacy }
        if cloud && !AnalysisNetwork.shared.permitsCloud { throw AnalysisStop.network }
    }
}
