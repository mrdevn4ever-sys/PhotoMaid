import Foundation
import Observation
import PhotoMaidCore
import SwiftUI

enum PreviewState: Equatable {
    case loading
    case ready(UIImage)
    case notLocallyAvailable
    case failed
}

/// Presentation-Logik des Entscheidungs-Feeds. Die Entscheidungslogik selbst liegt in
/// `FeedGestureMachine` und `FeedSession` (PhotoMaidCore); hier wird nur verdrahtet.
@MainActor
@Observable
final class FeedViewModel {
    let request: FeedRequest
    private(set) var session = FeedSession(items: [])
    var machine = FeedGestureMachine()
    private(set) var assets: [String: MediaAsset] = [:]
    private(set) var previews: [ItemReference: PreviewState] = [:]
    private(set) var isLoaded = false
    /// Visueller Versatz des aktuellen Mediums (folgt dem Finger, fliegt beim Commit hinaus).
    var offset: CGSize = .zero
    private(set) var bumpCount = 0
    private(set) var commitCount = 0
    private(set) var errorMessage: String?
    /// Synchron gesetzt, solange ein Commit läuft: Buttons, VoiceOver-Aktionen, Zurück und
    /// Überspringen können das sichtbare Item währenddessen nicht verschieben.
    private(set) var isCommitting = false

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var loadTasks: [ItemReference: Task<Void, Never>] = [:]
    @ObservationIgnored var viewSize: CGSize = CGSize(width: 390, height: 600)
    @ObservationIgnored var displayScale: CGFloat = 3

    init(request: FeedRequest, app: AppModel) {
        self.request = request
        self.app = app
    }

    var current: ItemReference? { session.current }
    var currentAsset: MediaAsset? { current.flatMap { assets[$0.localIdentifier] } }

    // MARK: Warteschlange

    func load() async {
        let s = ReviewSessionID()
        var candidates: [ItemReference] = []
        switch request.source {
        case .category(let c):
            let list = app.photos.assets(c)
            for a in list { assets[a.id] = a }
            let refs = list.map(\.reference)
            let records = await app.ledger.records(for: refs)
            candidates = ReviewQueues.normalQueue(candidates: refs, records: records, session: s, today: app.today)
        case .due:
            let all = await app.ledger.allRecords()
            candidates = ReviewQueues.dueQueue(records: all, session: s, today: app.today)
                .filter { $0.provider == .photoLibrary }
        case .task(let t):
            candidates = t.items.filter { $0.provider == .photoLibrary }
        case .items(let items, _):
            candidates = items.filter { $0.provider == .photoLibrary }
        }
        let known = app.photos.assets(ids: candidates.map(\.localIdentifier).filter { assets[$0] == nil })
        for a in known { assets[a.id] = a }
        // Nicht (mehr) zugängliche Assets nicht anzeigen und nicht entscheiden.
        candidates = candidates.filter { assets[$0.localIdentifier] != nil }
        session = FeedSession(id: s, items: candidates)
        isLoaded = true
        refreshWindow()
    }

    // MARK: Vorschau

    /// Vorheriges, aktuelles und zwei nächste Items puffern; ältere Requests abbrechen.
    func refreshWindow() {
        let items = session.items
        guard !items.isEmpty else { return }
        let lo = max(0, session.index - 1), hi = min(items.count - 1, session.index + 2)
        guard lo <= hi else { return }
        let window = Array(items[lo...hi])
        let target = PreviewPipeline.targetSize(for: viewSize, scale: displayScale)
        app.preview.updateCache(window: window.map(\.localIdentifier), targetSize: target)
        for (ref, task) in loadTasks where !window.contains(ref) {
            task.cancel()
            loadTasks[ref] = nil
            if case .ready = previews[ref] {} else { previews[ref] = nil }
        }
        // Speicher begrenzen: Bitmaps außerhalb des Fensters freigeben.
        for ref in previews.keys where !window.contains(ref) { previews[ref] = nil; session.markPreviewUnavailable(ref) }
        for ref in window where previews[ref] == nil && loadTasks[ref] == nil {
            previews[ref] = .loading
            loadTasks[ref] = Task { [weak self] in
                guard let self else { return }
                let result = await app.preview.image(for: ref.localIdentifier, targetSize: target)
                guard !Task.isCancelled else { return }
                // Antwort gegen ID prüfen: nur übernehmen, wenn das Item noch im Fenster ist.
                guard self.loadTasks[ref] != nil else { return }
                self.loadTasks[ref] = nil
                switch result {
                case .image(let img):
                    self.previews[ref] = .ready(img)
                    self.session.markPreviewReady(ref)
                case .notLocallyAvailable:
                    self.previews[ref] = .notLocallyAvailable
                case .failed:
                    self.previews[ref] = .failed
                }
            }
        }
    }

    // MARK: Gesten

    func dragChanged(_ translation: CGSize) {
        machine.update(translation: Vector2(translation.width, translation.height))
        let o = machine.displayOffset
        offset = CGSize(width: o.dx, height: o.dy)
    }

    func dragEnded(_ translation: CGSize, velocity: CGSize, reduceMotion: Bool) {
        let resolution = machine.end(translation: Vector2(translation.width, translation.height),
                                     velocity: Vector2(velocity.width, velocity.height))
        switch resolution {
        case .commit(let direction):
            perform(FeedIntent(direction), reduceMotion: reduceMotion)
        case .cancelled, .ignored:
            withAnimation(AppMotion.standard(reduceMotion)) { offset = .zero }
        }
    }

    func dragCancelled() {
        machine.cancel()
        offset = .zero
    }

    /// Gemeinsamer Pfad für Gesten, Buttons und VoiceOver-Aktionen.
    func perform(_ intent: FeedIntent, reduceMotion: Bool) {
        guard !isCommitting else { return }
        if intent == .previous {
            let nav = session.goBack()
            machine.finishCommit()
            withAnimation(AppMotion.standard(reduceMotion)) { offset = .zero }
            if nav == .atStart { bumpCount += 1 } // dezenter Anschlag, keine Aktion
            app.player.stop()
            refreshWindow()
            return
        }
        guard let item = current else { machine.finishCommit(); return }
        isCommitting = true
        Task { await commit(intent, item: item, reduceMotion: reduceMotion) }
    }

    private func commit(_ intent: FeedIntent, item: ItemReference, reduceMotion: Bool) async {
        defer { isCommitting = false }
        let revision = await app.ledger.record(for: item).revision
        // Entscheidung nur für das Item, auf dem die Aktion ausgelöst wurde.
        guard session.current == item,
              let pending = session.requestDecision(intent, currentRevision: revision),
              pending.command.item == item else {
            machine.finishCommit()
            withAnimation(AppMotion.standard(reduceMotion)) { offset = .zero }
            return
        }
        withAnimation(AppMotion.commit(reduceMotion)) { offset = Self.exitOffset(intent, size: viewSize) }
        app.player.stop() // ausgehenden Player sofort pausieren
        do {
            let out = try await app.apply(pending.command, session: session.id)
            session.commitSucceeded(pending.command.id, record: out.record)
            commitCount += 1
            offset = .zero
        } catch {
            session.commitFailed(pending.command.id)
            errorMessage = String(localized: "Die Entscheidung wurde nicht gespeichert. Bitte erneut versuchen.")
            withAnimation(AppMotion.standard(reduceMotion)) { offset = .zero }
        }
        machine.finishCommit()
        refreshWindow()
    }

    static func exitOffset(_ intent: FeedIntent, size: CGSize) -> CGSize {
        switch intent {
        case .keep: CGSize(width: 0, height: -size.height * 1.2)
        case .markForCleanup: CGSize(width: -size.width * 1.3, height: 0)
        case .later: CGSize(width: size.width * 1.3, height: 0)
        case .previous: .zero
        }
    }

    /// Nicht lokal verfügbare Items überspringen – ausdrücklich OHNE Entscheidung.
    func skipWithoutDecision() {
        guard !isCommitting else { return }
        session.jump(to: session.index + 1)
        app.player.stop()
        refreshWindow()
    }

    // MARK: Terminleiste

    func schedule(_ day: LocalDay) async {
        guard let receipt = session.receipt,
              let cmd = session.scheduleCommand(receiptID: receipt.id, day: day) else { return }
        do {
            _ = try await app.apply(cmd)
            session.dismissReceipt(receipt.id)
            await app.reminders.scheduleDueReminder(for: day)
        } catch {
            errorMessage = String(localized: "Der Termin wurde nicht gespeichert.")
        }
    }

    func dismissReceipt() {
        if let r = session.receipt { session.dismissReceipt(r.id) }
    }

    // MARK: Undo

    func undo() async {
        guard !isCommitting else { return }
        guard let record = await app.undo() else { return }
        session.applyUndo(record)
        refreshWindow()
    }

    func clearError() { errorMessage = nil }
}
