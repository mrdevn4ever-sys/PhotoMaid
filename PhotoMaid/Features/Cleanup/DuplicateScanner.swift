import Foundation
import Observation
import Photos
import PhotoMaidCore

/// Ein app-weiter Duplikat-Suchlauf (läuft weiter, wenn die Seite verlassen wird):
/// Alle freigegebenen Medien und verbundenen Dateien, einschließlich kompletter mehrteiliger PhotoKit-Assets.
/// Größen- und Hash-Cache sparen erneutes Lesen; iCloud-Originale nur nach ausdrücklicher Wahl über WLAN.
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
    private(set) var usingCloud = false
    var selection: [String: Set<ItemReference>] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    // SwiftUI reads this before a scan starts. `task` is deliberately ignored by
    // Observation; derive the public state from the observed phase instead.
    var isRunning: Bool { phase != .idle }

    func start(app: AppModel, includeCloud: Bool = false) {
        guard task == nil else { return }
        failed = false
        result = nil
        selection = [:]
        phase = .measuring
        done = 0
        total = 0
        task = Task { [weak self] in
            // Dateien neu inventarisieren, statt nur die zuletzt anderswo geöffnete Liste zu durchsuchen.
            while app.files.isScanning && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
            if !Task.isCancelled { await app.files.scan(app.sources, limit: .max) }
            guard !Task.isCancelled else { self?.finish(.cancelled, app: app); return }
            if includeCloud {
                // Beim ersten Öffnen hat NWPathMonitor noch keinen Pfad geliefert.
                for _ in 0..<10 where !AnalysisNetwork.shared.permitsCloud {
                    if Task.isCancelled { self?.finish(.cancelled, app: app); return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            let media = app.cleanupMedia
            let files = app.files.entries
            let reader = DuplicatePhotoReader(media: media, includeCloud: includeCloud) { [weak self] active in
                Task { @MainActor in if self?.isRunning == true { self?.usingCloud = active } }
            }
            let provider = CombinedByteProvider(photos: app.bytes, reader: reader, files: files, sources: app.sources)
            let scanned = await Self.scan(media: media, files: files, sizer: app.sizer, reader: reader, provider: provider,
                                         unavailableSources: app.files.failedSources.count) { [weak self] phase, done, total in
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
        // Fortschrittsmeldungen aus dem Hash-Thread dürfen nicht verspätet zurückspringen.
        if self.phase == .comparing && phase == .measuring { return }
        if self.phase == phase && self.total == total && done < self.done { return }
        self.phase = phase
        self.done = done
        self.total = total
    }

    private func finish(_ scanned: Outcome, app: AppModel) {
        task = nil
        phase = .idle
        usingCloud = false
        switch scanned {
        case .cancelled:
            break
        case .failed:
            failed = true
        case .done(let scanned):
            // Inzwischen in den Tresor gelegte oder ausgeblendete Originale niemals im Ergebnis zeigen.
            app.files.applyConcealment()
            let allowed = Set(app.cleanupMedia.filter { !VaultConcealment.shared.isConcealed($0.id) }.map(\.reference))
                .union(app.files.entries.map(\.reference))
            var r = scanned
            r.groups = r.groups.compactMap { group in
                let members = group.members.filter { allowed.contains($0) }
                return members.count > 1 ? DuplicateGroup(sha256: group.sha256, sizeEach: group.sizeEach, members: members) : nil
            }
            r.notChecked = r.notChecked.filter { allowed.contains($0) }
            r.notComparable = r.notComparable.filter { allowed.contains($0) }
            r.zeroByte = r.zeroByte.filter { allowed.contains($0) }
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

    nonisolated private static func scan(media: [MediaAsset], files: [FileEntry], sizer: MediaSizer, reader: DuplicatePhotoReader,
                                         provider: CombinedByteProvider,
                                         unavailableSources: Int,
                                         report: @escaping @Sendable (Phase, Int, Int) async -> Void) async -> Outcome {
        // Ein Foto mit einzigartigen Pixelmaßen kann als Datei nochmals vorhanden sein.
        // Deshalb alle zulässigen Medien aufnehmen, nicht nur gleich geformte Foto-Paare.
        let candidates = media
        let measureTotal = candidates.count + files.filter { $0.size.bytes == nil }.count
        await report(.measuring, 0, measureTotal)
        let previous = await sizer.records(for: candidates)
        var measured: [String: SizeRecord] = [:]
        var done = 0
        var start = 0
        var lastReport = ProcessInfo.processInfo.systemUptime
        while start < candidates.count {
            if Task.isCancelled { return .cancelled }
            let chunk = Array(candidates[start..<min(candidates.count, start + 200)])
            start += chunk.count
            let fetched = PhotoLibraryService.phAssetBoxes(chunk.map(\.id))
            var updated: [String: SizeRecord] = [:]
            do {
                try await ThrottledWork.run(
                    chunk, maxParallel: 4, thermal: { ForegroundActivity.workLevel() },
                    work: { a -> MeasuredPair in
                        MeasuredPair(id: a.id, record: try await reader.prepare(a, prefetched: fetched[a.id], record: previous[a.id]))
                    },
                    result: { _, pair in
                        measured[pair.id] = pair.record
                        if pair.record != previous[pair.id] { updated[pair.id] = pair.record }
                        done += 1
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastReport >= 0.25 || done == measureTotal {
                            lastReport = now
                            await report(.measuring, done, measureTotal)
                        }
                    })
            } catch {
                await sizer.storeDuplicateMeasurements(updated)
                return Task.isCancelled ? .cancelled : .failed
            }
            await sizer.storeDuplicateMeasurements(updated)
        }
        await sizer.flush()

        var list = candidates.map { DuplicateCandidate(item: $0.reference, size: measured[$0.id]?.size ?? .unknown) }
        for f in files {
            var size = f.size
            if size.bytes == nil {
                let job = Task.detached(priority: .utility) { try provider.measureFile(f.reference) }
                do {
                    size = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
                } catch { return Task.isCancelled ? .cancelled : .failed }
                done += 1
                await report(.measuring, done, measureTotal)
            }
            list.append(DuplicateCandidate(item: f.reference, size: size, aliasKey: f.aliasKey))
        }
        let cache = SizerHashCache(records: measured)
        await report(.comparing, 0, 1)
        let candidatesList = list
        let pacer = DuplicateProgressPacer()
        // Der Vergleich liest blockierend (Ströme): eigener Thread, Abbrechen wird weitergegeben.
        let job = Task.detached(priority: .userInitiated) {
            try DuplicateFinder().scan(candidatesList, source: provider, cache: cache) { p in
                if pacer.due(p) { Task { await report(.comparing, p.processed, p.total) } }
            }
        }
        let scanned: DuplicateScanResult?
        do {
            scanned = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        } catch {
            scanned = nil
        }
        await sizer.storeHashes(cache.pendingUpdates)
        // Auch ein überholter Größen-Cache wird durch den tatsächlichen vollständigen Lesedurchlauf berichtigt.
        await sizer.storeDuplicateMeasurements(reader.measurements)
        if Task.isCancelled { return .cancelled }
        guard var scanned else { return .failed }
        scanned.unavailableSources = unavailableSources
        return .done(scanned)
    }
}

/// Auch 30 000 bereits gecachte Kandidaten dürfen keine 60 000 UI-Aufgaben auf einmal erzeugen.
private final class DuplicateProgressPacer: @unchecked Sendable {
    private let lock = NSLock()
    private var last = 0.0
    func due(_ progress: DuplicateScanProgress) -> Bool {
        lock.withLock {
            let now = ProcessInfo.processInfo.systemUptime
            guard progress.processed == 0 || progress.processed == progress.total || now - last >= 0.25 else { return false }
            last = now
            return true
        }
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
