import Foundation
import Observation
import Photos
import PhotoMaidCore

/// Ein app-weiter Duplikat-Suchlauf (läuft weiter, wenn die Seite verlassen wird):
/// 1. Vorfilter: nur Medien, deren Art/Pixelmaße/Dauer ein anderes teilt (byte-gleich setzt das zwingend voraus).
/// 2. Nur vergleichbare Assets (genau eine Ressource) werden gemessen – parallel, gedrosselt bei Wärme, mit Fortschritt.
/// 3. Byte-Vergleich per SHA-256 (`DuplicateFinder`); Prüfsummen werden gespeichert, ein zweiter Lauf liest kaum noch.
/// Nichts wird entschieden: gewählte Kopien kommen erst auf Tipp in den PhotoMaid-Papierkorb.
@MainActor @Observable
final class DuplicateScanner {
    static let shared = DuplicateScanner()

    enum Phase: Equatable { case idle, measuring, comparing }

    private(set) var phase = Phase.idle
    private(set) var done = 0
    private(set) var total = 0
    private(set) var result: DuplicateScanResult?
    private(set) var failed = false
    var selection: [String: Set<ItemReference>] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    func start(app: AppModel) {
        guard task == nil else { return }
        failed = false
        result = nil
        selection = [:]
        phase = .measuring
        done = 0
        total = 0
        let media = app.cleanupMedia
        let files = app.files.entries
        let sizer = app.sizer
        let provider = CombinedByteProvider(photos: app.bytes, files: files, sources: app.sources)
        task = Task { [weak self] in
            let scanned = await Self.scan(media: media, files: files, sizer: sizer, provider: provider) { [weak self] phase, done, total in
                await self?.report(phase, done: done, total: total)
            }
            provider.close()
            self?.finish(scanned, app: app)
        }
    }

    func cancel() { task?.cancel() }

    /// Nach „In den Papierkorb“: Ergebnis verwerfen (nächster Lauf nutzt die gespeicherten Prüfsummen).
    func clear() {
        result = nil
        selection = [:]
    }

    private func report(_ phase: Phase, done: Int, total: Int) {
        guard task != nil else { return }
        self.phase = phase
        self.done = done
        self.total = total
    }

    private func finish(_ scanned: Outcome, app: AppModel) {
        task = nil
        phase = .idle
        switch scanned {
        case .cancelled:
            break
        case .failed:
            failed = true
        case .done(let r):
            result = r
            // Vorauswahl: die älteste Kopie bleibt, die übrigen sind für den Papierkorb gewählt.
            var sel: [String: Set<ItemReference>] = [:]
            for g in r.groups {
                let keep = g.members.min {
                    (app.asset($0.localIdentifier)?.creationDate ?? .distantFuture) < (app.asset($1.localIdentifier)?.creationDate ?? .distantFuture)
                } ?? g.members[0]
                sel[g.id] = g.defaultSelection(keeping: keep)
            }
            selection = sel
        }
    }

    enum Outcome: Sendable {
        case done(DuplicateScanResult)
        case cancelled
        case failed
    }

    nonisolated private static func scan(media: [MediaAsset], files: [FileEntry], sizer: MediaSizer,
                                         provider: CombinedByteProvider,
                                         report: @escaping @Sendable (Phase, Int, Int) async -> Void) async -> Outcome {
        let shared = Set(DuplicatePrefilter.candidates(media.map { InventoryItem($0) }))
        let candidates = media.filter { shared.contains($0.id) }
        await report(.measuring, 0, candidates.count)
        var comparable: [MediaAsset] = []
        var notComparable: [MediaAsset] = []
        var measured: [String: SizeRecord] = [:]
        var done = 0
        var start = 0
        while start < candidates.count {
            if Task.isCancelled { return .cancelled }
            let chunk = Array(candidates[start..<min(candidates.count, start + 200)])
            start += chunk.count
            let fetched = PhotoLibraryService.phAssetBoxes(chunk.map(\.id))
            var toMeasure: [MediaAsset] = []
            for a in chunk {
                guard let box = fetched[a.id] else { continue } // gelöscht oder im Tresor
                // Live Photos, Bearbeitetes, RAW+JPEG: mehrere Ressourcen – nicht als exakt gleich behandelbar.
                if PHAssetResource.assetResources(for: box.value).count == 1 { toMeasure.append(a) } else { notComparable.append(a) }
            }
            do {
                try await ThrottledWork.run(
                    toMeasure, maxParallel: 4, thermal: { ForegroundActivity.workLevel() },
                    work: { a -> MeasuredPair in
                        MeasuredPair(id: a.id, record: await sizer.measured(a, prefetched: fetched[a.id]))
                    },
                    result: { _, pair in measured[pair.id] = pair.record })
            } catch {
                return Task.isCancelled ? .cancelled : .failed
            }
            comparable += toMeasure
            done += chunk.count
            await report(.measuring, done, candidates.count)
        }
        await sizer.flush()

        var list = comparable.map { DuplicateCandidate(item: $0.reference, size: measured[$0.id]?.size ?? .unknown) }
        list += notComparable.map { DuplicateCandidate(item: $0.reference, size: .unknown, isComparable: false) }
        for f in files { list.append(DuplicateCandidate(item: f.reference, size: f.size, aliasKey: f.aliasKey)) }
        let cache = SizerHashCache(records: measured)
        await report(.comparing, 0, 1)
        let candidatesList = list
        // Der Vergleich liest blockierend (Ströme): eigener Thread, Abbrechen wird weitergegeben.
        let job = Task.detached(priority: .userInitiated) {
            try DuplicateFinder().scan(candidatesList, source: provider, cache: cache) { p in
                Task { await report(.comparing, p.processed, p.total) }
            }
        }
        let scanned: DuplicateScanResult?
        do {
            scanned = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        } catch {
            scanned = nil
        }
        await sizer.storeHashes(cache.pendingUpdates)
        if Task.isCancelled { return .cancelled }
        guard let scanned else { return .failed }
        return .done(scanned)
    }
}

/// Prüfsummen aus den gespeicherten Messungen (nur aktuelle, bekannte Größen) und neu berechnete zum Speichern.
private final class SizerHashCache: DuplicateHashCache, @unchecked Sendable {
    private let lock = NSLock()
    private var partial: [ItemReference: String] = [:]
    private var full: [ItemReference: String] = [:]
    private var updates: [String: DuplicateHashes] = [:]
    private let modified: [String: Date?]

    init(records: [String: SizeRecord]) {
        var modified: [String: Date?] = [:]
        for (id, r) in records where r.state == .known {
            modified[id] = r.modified
            if let p = r.partialHash { partial[.photo(id)] = p }
            if let f = r.fullHash { full[.photo(id)] = f }
        }
        self.modified = modified
    }

    func partialHash(_ item: ItemReference) -> String? { lock.withLock { partial[item] } }
    func fullHash(_ item: ItemReference) -> String? { lock.withLock { full[item] } }

    func store(_ item: ItemReference, partial p: String?, full f: String?) {
        guard item.provider == .photoLibrary else { return }
        let id = item.localIdentifier
        lock.withLock {
            guard let changed = modified[id] else { return }
            if let p { partial[item] = p }
            if let f { full[item] = f }
            var u = updates[id] ?? DuplicateHashes(modified: changed)
            if let p { u.partial = p }
            if let f { u.full = f }
            updates[id] = u
        }
    }

    var pendingUpdates: [String: DuplicateHashes] { lock.withLock { updates } }
}
