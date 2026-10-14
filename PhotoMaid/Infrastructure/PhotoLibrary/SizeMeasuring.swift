import Foundation
import Observation
import Photos
import PhotoMaidCore
import UIKit

/// Ein gemessenes Medium (für die Übergabe aus parallelen Messungen).
struct MeasuredPair: Sendable {
    let id: String
    let record: SizeRecord
}

/// Ein app-weiter Mess-Auftrag für „Große Dateien“: misst, was noch fehlt (Videos zuerst, längste zuerst; danach Fotos
/// nach Pixelzahl), bis zu 4 gleichzeitig, gedrosselt bei Wärme. Läuft weiter, wenn die Seite verlassen wird; beim
/// Verlassen der App angehalten und bei der Rückkehr von selbst fortgesetzt. Bereits Gemessenes wird nie erneut
/// gelesen (`SizeInventory.needsMeasure`).
@MainActor @Observable
final class SizeMeasuring {
    static let shared = SizeMeasuring()

    private(set) var running = false
    private(set) var done = 0
    private(set) var total = 0
    /// Spiegel der Messungen für die Anzeige (gebündelt aktualisiert, höchstens zweimal pro Sekunde).
    private(set) var records: [String: SizeRecord] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var wanted: [MediaAsset] = []
    @ObservationIgnored private var sizer: MediaSizer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: nil, using: Self.backgroundHandler(self)))
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: nil, using: Self.foregroundHandler(self)))
    }

    private nonisolated static func backgroundHandler(_ owner: SizeMeasuring) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in owner?.suspend() } }
    }
    private nonisolated static func foregroundHandler(_ owner: SizeMeasuring) -> @Sendable (Notification) -> Void {
        { [weak owner] _ in Task { @MainActor in owner?.resume() } }
    }

    /// Diese Medien messen lassen (gültig Gemessenes wird übersprungen).
    func ensure(_ assets: [MediaAsset], sizer: MediaSizer) {
        self.sizer = sizer
        wanted = assets
        restart()
    }

    private func suspend() {
        task?.cancel()
        task = nil
        running = false
    }

    private func resume() {
        guard task == nil, !wanted.isEmpty else { return }
        restart()
    }

    private func restart() {
        task?.cancel()
        guard let sizer, !wanted.isEmpty else { return }
        let assets = wanted
        running = true
        task = Task { [weak self] in
            await self?.run(assets, sizer: sizer)
        }
    }

    private func run(_ assets: [MediaAsset], sizer: MediaSizer) async {
        let current = await sizer.records(for: assets)
        records.merge(current) { _, new in new }
        let now = Date()
        let byID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let todo = SizeInventory.order(assets.map { InventoryItem($0) })
            .filter { SizeInventory.needsMeasure($0, record: current[$0.id], now: now) }
            .compactMap { byID[$0.id] }
        done = 0
        total = todo.count
        if !todo.isEmpty {
            await Self.measureAll(todo, sizer: sizer) { [weak self] batch, done in
                await self?.publish(batch, done: done)
            }
        }
        guard !Task.isCancelled else { return }
        running = false
        task = nil
        wanted = []
    }

    private func publish(_ batch: [String: SizeRecord], done: Int) {
        if !batch.isEmpty { records.merge(batch) { _, new in new } }
        self.done = done
    }

    /// In Paketen zu 200 (eine PhotoKit-Abfrage je Paket), je Paket bis zu 4 Messungen gleichzeitig.
    nonisolated private static func measureAll(_ todo: [MediaAsset], sizer: MediaSizer,
                                               report: @escaping @Sendable ([String: SizeRecord], Int) async -> Void) async {
        var batch: [String: SizeRecord] = [:]
        var done = 0
        var last = ProcessInfo.processInfo.systemUptime
        var start = 0
        while start < todo.count, !Task.isCancelled {
            let chunk = Array(todo[start..<min(todo.count, start + 200)])
            start += chunk.count
            let fetched = PhotoLibraryService.phAssetBoxes(chunk.map(\.id))
            do {
                try await ThrottledWork.run(
                    chunk, maxParallel: 4, thermal: { AnalysisRunner.thermalLevel() },
                    work: { asset -> MeasuredPair in
                        MeasuredPair(id: asset.id, record: await sizer.measured(asset, prefetched: fetched[asset.id]))
                    },
                    result: { _, pair in
                        batch[pair.id] = pair.record
                        done += 1
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - last >= 0.5 {
                            last = now
                            await report(batch, done)
                            batch = [:]
                        }
                    })
            } catch {
                break // abgebrochen oder kritisch heiß: Fortschritt ist gespeichert
            }
        }
        await sizer.flush()
        await report(batch, done)
    }
}
