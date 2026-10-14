import Foundation
import Observation
import PhotoMaidCore
import SwiftUI

enum PreviewState: Equatable, Sendable { case loading, ready, failed }

/// Kurze Bestätigung nach „Später“. Nur Anzeige; der Termin ist bereits gespeichert.
struct LaterPill: Identifiable, Equatable {
    let id = UUID()
    let receiptID: UUID
    let interval: LaterInterval
}

/// Kurzer Hinweis, nur nach belegtem Erfolg (z. B. „Zum Album hinzugefügt“).
struct FeedNotice: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

/// Geschützter Favorit wurde nach links gewischt: Rückfrage statt Papierkorb. Keine Entscheidung.
struct ProtectedFavorite: Identifiable, Equatable {
    let id = UUID()
    let item: ItemReference
    let isVideo: Bool
}

/// Offene Terminauswahl (VoiceOver-Aktion „Datum für später wählen“) – noch KEINE Entscheidung.
/// Gebunden an Item und Revision beim Öffnen: Bestätigen wirkt nur, wenn beides noch stimmt.
struct CustomLaterRequest: Identifiable, Equatable {
    let id = UUID()
    let item: ItemReference
    let revision: Int
}

/// Präsentationslogik des Entscheidungs-Feeds (Port von Android `FeedViewModel`).
/// Die Entscheidungslogik selbst liegt in `FeedGestureMachine` und `FeedSession` (PhotoMaidCore); hier wird verdrahtet.
@MainActor
@Observable
final class FeedViewModel {
    let request: FeedRequest
    private let app: AppModel

    private(set) var session = FeedSession(items: [])
    // Pure gesture bookkeeping changes on every touch sample. The UI observes
    // lockedDirection, readyDirection and offset instead of invalidating for machine state.
    @ObservationIgnored private(set) var machine = FeedGestureMachine()
    private(set) var assets: [String: MediaAsset] = [:]
    private(set) var previews: [ItemReference: PreviewState] = [:]
    private(set) var retries: [ItemReference: Int] = [:]
    private(set) var isLoaded = false
    /// Versatz des aktuellen Mediums in pt (folgt dem Finger, fliegt beim Commit hinaus).
    var offset: CGSize = .zero
    private(set) var lockedDirection: SwipeDirection?
    /// In dieser Sitzung per „In Album legen“ zugeordnet (für Rückgängig): Medium → Album.
    @ObservationIgnored private var albumPlacements: [ItemReference: String] = [:]
    /// Richtung, in die Loslassen jetzt entscheiden würde (dezente Rahmenfarbe + einmal Haptik).
    private(set) var readyDirection: SwipeDirection?
    private(set) var isCommitting = false
    private(set) var laterPill: LaterPill?
    var pickerReceipt: LaterReceipt?
    private(set) var customLater: CustomLaterRequest?
    var protectedFavorite: ProtectedFavorite?
    private(set) var notice: FeedNotice?
    private(set) var mediaWriteBusy = false
    var seriesOpen: [MediaAsset]?
    var albumSheetFor: MediaAsset?
    var viewSize: CGSize = CGSize(width: 390, height: 600)
    var reduceMotion = false
    /// Sizes for „Größte zuerst“ (nur gemessen; unbekannt steht am Ende).
    @ObservationIgnored private var sizes: [String: KnownSize] = [:]
    @ObservationIgnored private let shuffleSeed = UInt64.random(in: 1...UInt64.max)
    @ObservationIgnored private var seriesByID: [String: [PhotoSeries.Member]] = [:]
    @ObservationIgnored private var sessionIndexByID: [String: Int] = [:]
    /// The active series changes only when the visible item or queue changes, not on every touch frame.
    private(set) var currentSeries: [MediaAsset]?
    @ObservationIgnored private var pillTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init(request: FeedRequest, app: AppModel) {
        self.request = request
        self.app = app
    }

    var current: ItemReference? { session.current }
    var currentAsset: MediaAsset? { current.flatMap { assets[$0.localIdentifier] } }
    var next: ItemReference? { session.items.indices.contains(session.index + 1) ? session.items[session.index + 1] : nil }
    var canReorder: Bool { request.isOrderable }
    var order: FeedOrder { app.settings.feedOrder }
    var today: LocalDay { app.today }
    var defaultLaterInterval: LaterInterval { app.settings.laterInterval }

    // MARK: Warteschlange

    func load() async {
        let s = ReviewSessionID()
        let today = app.today
        let records = app.read.records
        func open(_ list: [MediaAsset]) -> [ItemReference] {
            for a in list { assets[a.id] = a }
            return ReviewQueues.normalQueue(candidates: list.map(\.reference), records: records, session: s, today: today)
        }
        if !app.snapshot.loaded { app.reloadLibraryIfNeeded() }
        // Auf den ersten Stand der Mediathek warten (läuft im Hintergrund).
        var waited = 0
        while !app.snapshot.loaded && waited < 200 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        let media = app.cleanupMedia
        let candidates: [ItemReference]
        switch request.source {
        case .category(let c):
            candidates = open(media.filter { Self.matches($0, c) })
        case .allMedia:
            candidates = open(media)
        case .quick(let q):
            // „Zufällig“ wählt nur aus offenen Medien und mischt bei jedem Öffnen neu.
            candidates = open(QuickAccessQuery.assets(q, in: media, now: app.now, open: Set(app.pending.map(\.localIdentifier))))
        case .due:
            candidates = ReviewQueues.dueQueue(records: Array(records.values), session: s, today: today)
                .filter { $0.provider == .photoLibrary }
        case .collection(let c):
            let result = await CollectionEvaluator.evaluate(c, app: app)
            candidates = result.items.filter { $0.provider == .photoLibrary }
        case .items(let refs, _):
            candidates = refs.filter { $0.provider == .photoLibrary }
        case .month(let m, let again):
            let tz = TimeZone.autoupdatingCurrent
            let list = media.filter { a in a.creationDate.map { MonthKey($0, timeZone: tz) } == m }
            if again {
                for a in list { assets[a.id] = a }
                candidates = list.map(\.reference)
            } else {
                candidates = open(list)
            }
            app.updateSettings { $0.continueMonth = m.description }
        case .newSince:
            candidates = open(NewSinceQuery.assets(in: media, settings: app.settings))
        case .album(let id, _):
            let ids = await Task.detached { PhotoLibraryService.orderedAssetIDs(inAlbum: id) }.value
            let set = Set(ids)
            candidates = open(media.filter { set.contains($0.id) })
        }
        let missing = candidates.map(\.localIdentifier).filter { assets[$0] == nil }
        for a in app.library.assets(ids: missing) { assets[a.id] = a }
        // Nicht (mehr) zugängliche Medien nicht anzeigen und nicht entscheiden.
        let present = candidates.filter { assets[$0.localIdentifier] != nil }
        if canReorder && order == .largest {
            sizes = await app.sizer.cachedSizes(present.compactMap { assets[$0.localIdentifier] })
        }
        session = FeedSession(id: s, items: canReorder ? ordered(present, order) : present)
        rebuildSeries()
        isLoaded = true
        refreshWindow()
    }

    nonisolated static func matches(_ a: MediaAsset, _ c: MediaCategory) -> Bool {
        switch c {
        case .photos: a.kind == .photo || a.kind == .screenshot
        case .videos: a.kind == .video
        case .screenshots: a.kind == .screenshot
        }
    }

    private func ordered(_ refs: [ItemReference], _ order: FeedOrder) -> [ItemReference] {
        FeedOrdering.apply(refs, order: order, date: { self.assets[$0.localIdentifier]?.creationDate },
                           size: { self.sizes[$0.localIdentifier]?.bytes }, id: { $0.localIdentifier }, seed: shuffleSeed)
    }

    /// Reihenfolge wechseln: nur die noch kommenden Medien werden neu geordnet, nichts wird entschieden.
    func setOrder(_ order: FeedOrder) async {
        guard canReorder, !isCommitting else { return }
        app.updateSettings { $0.feedOrder = order }
        if order == .largest {
            let upcoming = session.items.dropFirst(session.index).compactMap { assets[$0.localIdentifier] }
            sizes = await app.sizer.cachedSizes(Array(upcoming))
        }
        session.reorderUpcoming { self.ordered($0, order) }
        rebuildSessionIndex()
        app.player.stop()
        refreshWindow()
    }

    /// Externe Änderung (Favorit in der Fotos-App, Löschen, Zugriff entzogen): sichtbares Fenster frisch lesen.
    func refreshWindowAssets() {
        let refs = windowItems()
        guard !refs.isEmpty else { return }
        let fresh = app.library.assets(ids: refs.map(\.localIdentifier))
        for a in fresh { assets[a.id] = a }
        let present = Set(fresh.map(\.id))
        for ref in refs where !present.contains(ref.localIdentifier) && previews[ref] != nil {
            previews[ref] = .failed
            session.markPreviewUnavailable(ref)
        }
        refreshCurrentSeries()
    }

    // MARK: Fotoserien (nur Erkennung, Auswahl trifft der Nutzer)

    private func rebuildSeries() {
        let members = session.items.compactMap { assets[$0.localIdentifier] }.filter { !$0.isVideo }
            // iOS kennt keine Speicherordner: Kamera-Fotos und Bildschirmfotos bilden getrennte Gruppen.
            .map { PhotoSeries.Member(id: $0.id, group: $0.kind == .screenshot ? "screenshots" : "camera", takenAt: $0.creationDate) }
        seriesByID = PhotoSeries.index(members)
        rebuildSessionIndex()
    }

    private func rebuildSessionIndex() {
        sessionIndexByID = Dictionary(uniqueKeysWithValues:
            session.items.enumerated().map { ($0.element.localIdentifier, $0.offset) })
    }

    /// Compute once per card, never when the finger merely moves the visible card.
    private func refreshCurrentSeries() {
        guard let id = current?.localIdentifier, let group = seriesByID[id] else {
            currentSeries = nil
            return
        }
        let list = group.compactMap { member -> MediaAsset? in
            guard let position = sessionIndexByID[member.id], position >= session.index else { return nil }
            return assets[member.id]
        }
        currentSeries = list.count >= PhotoSeries.minSize ? list : nil
    }

    func openSeries() {
        guard !isCommitting else { return }
        seriesOpen = currentSeries
    }

    /// `keep` werden behalten, alle anderen kommen in den PhotoMaid-Papierkorb (nichts gelöscht). Ein Befehl je Medium.
    func confirmSeries(_ members: [MediaAsset], keep: Set<String>) async {
        guard !isCommitting else { return }
        seriesOpen = nil
        isCommitting = true
        defer { isCommitting = false }
        var failed = false
        for a in members {
            let intent: FeedIntent = keep.contains(a.id) ? .keep : .markForCleanup
            do {
                let r = await app.ledger.record(for: a.reference)
                _ = try await app.ledger.apply(DecisionCommand(item: a.reference, expectedRevision: r.revision,
                                                               action: intent == .keep ? .keep : .markForCleanup),
                                               sessionID: session.id)
                session.recordDecision(a.reference, intent: intent)
            } catch {
                failed = true
            }
        }
        await app.publishRead()
        laterPill = nil
        session.dropUpcoming(Set(members.map(\.reference)))
        rebuildSessionIndex()
        app.player.stop()
        refreshWindow()
        Haptics.commit()
        showNotice(L("series_done", keep.count, members.count - keep.count))
        if failed { app.showError(L("error_decision_not_saved")) }
    }

    // MARK: Album vom Aufräumen ausnehmen (keine Entscheidung)

    func excludeAlbum(_ albumID: String, title: String) async {
        guard !isCommitting else { return }
        app.setExcluded(album: albumID, true)
        let members = await Task.detached { PhotoLibraryService.assetIDs(inCollection: albumID) }.value
        session.dropUpcoming(Set(session.items.filter { members.contains($0.localIdentifier) }))
        rebuildSessionIndex()
        app.player.stop()
        refreshWindow()
        showNotice(L("excl_done", title))
    }

    // MARK: Vorschau

    /// Vorheriges, aktuelles und zwei nächste Medien puffern; Rest freigeben.
    func windowItems() -> [ItemReference] {
        let items = session.items
        guard !items.isEmpty else { return [] }
        let lo = max(0, session.index - 1), hi = min(items.count - 1, session.index + 2)
        return lo <= hi ? Array(items[lo...hi]) : []
    }

    func refreshWindow() {
        refreshCurrentSeries()
        let window = Set(windowItems())
        for ref in previews.keys where !window.contains(ref) {
            previews[ref] = nil
            session.markPreviewUnavailable(ref)
        }
        for ref in window where previews[ref] == nil { previews[ref] = .loading }
        let size = PreviewPipeline.targetSize(for: viewSize, scale: UITraitCollection.current.displayScale)
        app.previews.updateCache(window: window.map(\.localIdentifier), targetSize: size)
    }

    func retryPreview(_ ref: ItemReference) {
        guard previews[ref] != nil else { return }
        previews[ref] = .loading
        retries[ref, default: 0] += 1
    }

    /// Rückmeldung des Bildladers. Nur übernehmen, wenn das Medium noch im Fenster ist.
    func previewResult(_ ref: ItemReference, ok: Bool) {
        guard previews[ref] != nil else { return }
        previews[ref] = ok ? .ready : .failed
        if ok { session.markPreviewReady(ref) } else { session.markPreviewUnavailable(ref) }
    }

    // MARK: Gesten

    func dragChanged(_ t: CGSize) {
        guard customLater == nil else { return }
        machine.update(translation: Vector2(t.width, t.height))
        let locked = machine.lockedDirection
        if lockedDirection != locked { lockedDirection = locked }
        let ready = machine.readyToCommit ? locked : nil
        if let ready, ready != readyDirection { Haptics.threshold() }
        if readyDirection != ready { readyDirection = ready }
        let o = machine.displayOffset
        let nextOffset = CGSize(width: o.dx, height: o.dy)
        if offset != nextOffset { offset = nextOffset }
    }

    func dragEnded(_ t: CGSize, velocity v: CGSize) {
        readyDirection = nil
        guard customLater == nil else { dragCancelled(); return }
        switch machine.end(translation: Vector2(t.width, t.height), velocity: Vector2(v.width, v.height)) {
        case .commit(let d): perform(action: app.settings.feedControls.action(for: d), direction: d, velocity: v)
        case .cancelled, .ignored: resetOffset()
        }
    }

    func dragCancelled() {
        machine.cancel()
        readyDirection = nil
        lockedDirection = nil
        withAnimation(AppMotion.standard(reduceMotion)) { offset = .zero }
    }

    /// Während Zoom, VoiceOver oder Steuerelement-Bedienung: keine Entscheidungsgesten.
    func setSuspended(_ suspended: Bool) {
        guard machine.isSuspended != suspended else { return }
        machine.isSuspended = suspended
        if suspended { dragCancelled() }
    }

    private func resetOffset() {
        lockedDirection = machine.lockedDirection
        withAnimation(AppMotion.standard(reduceMotion)) { offset = .zero }
    }

    /// Gemeinsamer Pfad für Gesten, Tasten und VoiceOver-Aktionen.
    /// Belegte Aktion einer Wischrichtung oder Taste (E18). Derselbe Weg für Geste und Taste: Entscheidungen laufen
    /// über `perform(_ intent:)`; „In Album legen“ fügt hinzu und behält in einem Schritt; „Nichts“ springt zurück.
    func perform(action: FeedAction, direction: SwipeDirection? = nil, velocity: CGSize = .zero) {
        switch action {
        case .nothing:
            machine.finishCommit()
            lockedDirection = nil
            resetOffset()
            Haptics.boundary()
        case .album(let id, let title):
            performAlbum(id: id, title: title, direction: direction, velocity: velocity)
        default:
            guard let intent = action.intent else { return }
            perform(intent, direction: direction, velocity: velocity)
        }
    }

    func perform(_ intent: FeedIntent, direction: SwipeDirection? = nil, velocity: CGSize = .zero) {
        // Solange eine Terminauswahl offen ist, kann nichts anderes entschieden oder navigiert werden.
        if customLater != nil { machine.finishCommit(); resetOffset(); return }
        guard !isCommitting else { return }
        if intent == .laterCustom { openCustomLater(); return }
        if intent == .previous {
            let nav = session.goBack()
            machine.finishCommit()
            lockedDirection = nil
            if case .moved = nav, !reduceMotion {
                // Vorheriges Medium gleitet von oben herein.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { offset = CGSize(width: 0, height: -viewSize.height * 0.35) }
                withAnimation(AppMotion.standard(false)) { offset = .zero }
            } else {
                resetOffset()
            }
            if nav == .atStart { Haptics.boundary() }
            app.player.stop()
            refreshWindow()
            return
        }
        guard let item = current else { machine.finishCommit(); lockedDirection = nil; return }
        if protectedFavorite != nil { machine.finishCommit(); resetOffset(); return }
        // Favoriten schützen: kein stiller Papierkorb für einen Favoriten – Rückfrage, Medium bleibt.
        if intent == .markForCleanup && app.settings.protectFavorites, let a = currentAsset, a.isFavorite {
            machine.finishCommit()
            lockedDirection = nil
            resetOffset()
            protectedFavorite = ProtectedFavorite(item: item, isVideo: a.isVideo)
            return
        }
        isCommitting = true
        Task { await commit(intent, item: item, customDay: nil, velocity: velocity, direction: direction) }
    }

    /// „In Album legen“: erst zum Album der Fotos-App hinzufügen, dann behalten. Scheitert eins, gilt beides nicht
    /// (die Album-Zuordnung wird zurückgenommen). Rückgängig nimmt später beides zurück.
    private func performAlbum(id albumID: String, title: String, direction: SwipeDirection?, velocity: CGSize) {
        if customLater != nil { machine.finishCommit(); resetOffset(); return }
        guard !isCommitting, let item = current, item.provider == .photoLibrary, protectedFavorite == nil else {
            machine.finishCommit(); lockedDirection = nil; resetOffset(); return
        }
        isCommitting = true
        Task {
            let added = await app.library.add([item.localIdentifier], toAlbum: albumID)
            guard added == .done else {
                isCommitting = false
                machine.finishCommit()
                lockedDirection = nil
                resetOffset()
                if added == .failed { app.showError(L("album_failed")) }
                return
            }
            app.rememberRecentAlbum(albumID)
            if await commit(.keep, item: item, customDay: nil, velocity: velocity, direction: direction) {
                albumPlacements[item] = albumID
                showNotice(L("feed_album_done", title))
            } else {
                _ = await app.library.remove([item.localIdentifier], fromAlbum: albumID)
            }
        }
    }

    private func openCustomLater() {
        machine.finishCommit()
        resetOffset()
        guard let item = current else { return }
        customLater = CustomLaterRequest(item: item, revision: app.record(item).revision)
    }

    /// Ergebnis der Terminauswahl aus der VoiceOver-Aktion. `nil` = nichts ändern, gleiches Medium.
    func customLaterFinished(_ request: CustomLaterRequest, day: LocalDay?) {
        guard customLater?.id == request.id else { return }
        customLater = nil
        guard let day, !isCommitting, let item = current, item == request.item,
              app.record(item).revision == request.revision else { return }
        isCommitting = true
        Task { await commit(.laterCustom, item: item, customDay: day, velocity: .zero, direction: nil) }
    }

    /// - Returns: `true`, wenn die Entscheidung gespeichert wurde.
    @discardableResult
    private func commit(_ intent: FeedIntent, item: ItemReference, customDay: LocalDay?, velocity: CGSize,
                        direction: SwipeDirection?) async -> Bool {
        defer {
            isCommitting = false
            if case .commitRequested = machine.phase { machine.finishCommit() }
        }
        let revision = await app.ledger.record(for: item).revision
        // Entscheidung nur für das Medium, auf dem die Aktion ausgelöst wurde.
        guard session.current == item, let pending = session.requestDecision(intent, currentRevision: revision),
              pending.command.item == item else {
            machine.finishCommit()
            resetOffset()
            return false
        }
        let target = exitOffset(intent, direction: direction)
        let duration = reduceMotion ? 0.01 : flyDuration(velocity)
        let animationStarted = ProcessInfo.processInfo.systemUptime
        withAnimation(.easeOut(duration: duration)) { offset = target }
        app.player.stop()
        do {
            let out = try await app.apply(pending.command, session: session.id, deferPublish: true)
            // Persistence can overlap the exit animation. Never add the *full*
            // animation duration on top of the actual commit latency.
            let remaining = max(0, duration - (ProcessInfo.processInfo.systemUptime - animationStarted))
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                session.commitSucceeded(pending.command.id, record: out.record)
                offset = .zero
            }
            Haptics.commit()
            // Mehrere „Später“ hintereinander: die Pille bleibt stehen und wird nur ersetzt.
            if intent != .later || customDay != nil { laterPill = nil }
            machine.finishCommit()
            lockedDirection = nil
            refreshWindow()
            if let receipt = session.receipt, receipt.item == item {
                if let customDay { _ = await schedule(receipt, customDay) } else { await applyDefaultLater(receipt) }
            }
            return true
        } catch {
            session.commitFailed(pending.command.id)
            app.showError(L("error_decision_not_saved"))
            machine.finishCommit()
            resetOffset()
            return false
        }
    }

    /// Fliegt mit der Wischgeschwindigkeit hinaus: schneller Wisch, schneller Wechsel (0,12–0,24 s).
    private func flyDuration(_ v: CGSize) -> Double {
        let speed = hypot(v.width, v.height)
        guard speed > 0 else { return 0.22 }
        return min(0.24, max(0.12, 900 / speed * 0.2))
    }

    /// Ziel außerhalb des Bildschirms; die Querbewegung des Fingers bleibt erhalten. Bei einer Geste fliegt das Medium
    /// in die gewischte Richtung (auch wenn sie anders belegt ist), bei einer Taste in die Richtung der Aktion.
    private func exitOffset(_ intent: FeedIntent, direction: SwipeDirection?) -> CGSize {
        let w = viewSize.width, h = viewSize.height
        if let direction {
            switch direction {
            case .up: return CGSize(width: offset.width, height: -h * 1.2)
            case .down: return CGSize(width: offset.width, height: h * 1.2)
            case .left: return CGSize(width: -w * 1.3, height: offset.height)
            case .right: return CGSize(width: w * 1.3, height: offset.height)
            }
        }
        switch intent {
        case .keep: return CGSize(width: offset.width, height: -h * 1.2)
        case .markForCleanup: return CGSize(width: -w * 1.3, height: offset.height)
        case .later: return CGSize(width: w * 1.3, height: offset.height)
        case .laterCustom: return CGSize(width: w * 1.3, height: -h * 0.6)
        case .previous: return .zero
        }
    }

    /// Nicht darstellbare Medien überspringen – ausdrücklich OHNE Entscheidung.
    func skipWithoutDecision() {
        guard !isCommitting, customLater == nil else { return }
        session.jump(to: session.index + 1)
        app.player.stop()
        refreshWindow()
    }

    // MARK: Später-Termin

    /// Wisch nach rechts: sofort Standardtermin setzen und kurz als Pille zeigen.
    private func applyDefaultLater(_ receipt: LaterReceipt) async {
        let interval = defaultLaterInterval
        guard await schedule(receipt, interval.dueDay(from: app.today)) else { laterPill = nil; return }
        let pill = LaterPill(receiptID: receipt.id, interval: interval)
        laterPill = pill
        pillTask?.cancel()
        pillTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self?.laterPill?.id == pill.id else { return }
            self?.laterPill = nil
        }
    }

    /// Ergebnis des Drehrads aus „Ändern“. Abbrechen = bisheriger Termin bleibt.
    func pickerFinished(_ receipt: LaterReceipt, day: LocalDay?) async {
        pickerReceipt = nil
        guard let day else { return }
        if await schedule(receipt, day) { Haptics.tick() }
        laterPill = nil
    }

    /// „Ohne Termin beiseitelegen“: kommt nicht von selbst zurück (gemeinsames Undo mit der Später-Aktion).
    func pickerNoDate(_ receipt: LaterReceipt) async {
        pickerReceipt = nil
        laterPill = nil
        guard let cur = session.receipt, cur.id == receipt.id, let cmd = session.bookmarkCommand(receiptID: cur.id) else { return }
        do {
            let out = try await app.apply(cmd, deferPublish: true)
            session.receiptScheduled(cur.id, revision: out.record.revision)
            Haptics.tick()
            showNotice(L("later_nodate_done"))
        } catch {
            app.showError(L("error_date_not_saved"))
        }
    }

    /// „Ändern“ in der Pille.
    func editLater() {
        guard let pill = laterPill, let r = session.receipt, r.id == pill.receiptID else { return }
        laterPill = nil
        pickerReceipt = r
    }

    /// Speichert den Termin als Ergänzung der ursprünglichen Später-Aktion (gemeinsames Undo).
    private func schedule(_ receipt: LaterReceipt, _ day: LocalDay) async -> Bool {
        guard let cur = session.receipt, cur.id == receipt.id,
              let cmd = session.scheduleCommand(receiptID: cur.id, day: day) else { return false }
        do {
            let out = try await app.apply(cmd, deferPublish: true)
            session.receiptScheduled(cur.id, revision: out.record.revision)
            await app.reminders.scheduleDueReminder(for: day, optedIn: app.settings.notificationsOptIn)
            return true
        } catch {
            app.showError(L("error_date_not_saved"))
            return false
        }
    }

    // MARK: Favorit, Album (keine Entscheidungen, kein Weiterblättern, nicht im Undo-Stapel)

    func toggleFavorite() async {
        guard let a = currentAsset, !mediaWriteBusy, !isCommitting else { return }
        await writeFavorite(a.id, !a.isFavorite)
    }

    @discardableResult
    private func writeFavorite(_ id: String, _ value: Bool) async -> Bool {
        mediaWriteBusy = true
        defer { mediaWriteBusy = false }
        let result = await app.library.setFavorite([id], value)
        if let fresh = app.library.asset(id) { assets[id] = fresh }
        switch result {
        case .done:
            Haptics.tick()
            return true
        case .cancelled:
            return false
        case .failed:
            app.showError(L("fav_failed"))
            return false
        }
    }

    /// Schutzdialog → „Favorit entfernen“: nur die Markierung. Das Medium bleibt; erneut wischen = Papierkorb.
    func unfavoriteProtected() async {
        guard let p = protectedFavorite else { return }
        protectedFavorite = nil
        if await writeFavorite(p.item.localIdentifier, false) { showNotice(L("fav_removed_hint")) }
    }

    func addCurrent(toAlbum albumID: String, title: String) async {
        guard let a = albumSheetFor ?? currentAsset, !mediaWriteBusy, !isCommitting else { return }
        albumSheetFor = nil
        mediaWriteBusy = true
        defer { mediaWriteBusy = false }
        switch await app.library.add([a.id], toAlbum: albumID) {
        case .done:
            app.rememberRecentAlbum(albumID)
            showNotice(L("album_added", title))
        case .cancelled: break
        case .failed: app.showError(L("album_failed"))
        }
    }

    func showNotice(_ text: String) {
        laterPill = nil
        let n = FeedNotice(text: text)
        notice = n
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self?.notice?.id == n.id else { return }
            self?.notice = nil
        }
    }

    // MARK: Undo

    func undo() async {
        guard !isCommitting, customLater == nil else { return }
        laterPill = nil
        let before = session.index
        guard let record = await app.undo() else { return }
        session.applyUndo(record)
        // „In Album legen“ war ein Schritt: mit der Entscheidung auch die Album-Zuordnung zurücknehmen.
        if let albumID = albumPlacements.removeValue(forKey: record.item) {
            if await app.library.remove([record.item.localIdentifier], fromAlbum: albumID) == .failed {
                app.showError(L("album_failed"))
            }
        }
        Haptics.tick()
        if session.index < before && !reduceMotion {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { offset = CGSize(width: 0, height: -viewSize.height * 0.35) }
            withAnimation(AppMotion.standard(false)) { offset = .zero }
        }
        if let a = app.library.asset(record.item.localIdentifier) { assets[a.id] = a }
        refreshWindow()
    }

    func close() {
        app.closeFeed(reviewed: session.summary.reviewed)
    }
}

/// „Neu seit dem letzten Aufräumen“: über die dauerhafte Änderungshistorie der Fotos-App (eingefügte Medien), sonst
/// ersatzweise nach Aufnahmedatum seit dem Ende der letzten Sitzung.
enum NewSinceQuery {
    static func assets(in media: [MediaAsset], settings: AppSettingsData) -> [MediaAsset] {
        if let token = settings.lastSessionChangeToken, let inserted = PhotoLibraryService.insertedSince(token) {
            return media.filter { inserted.contains($0.id) }
        }
        guard let end = settings.lastSessionEnd else { return [] }
        return media.filter { ($0.creationDate ?? .distantPast) > end }
    }
}
