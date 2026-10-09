import Foundation

/// Reine Übergangsregeln für Entscheidungen. Keine Seiteneffekte.
public enum DecisionRules {
    public static func transition(_ record: ItemRecord, _ action: DecisionAction) -> Result<DecisionSnapshot, DecisionError> {
        let from = record.disposition
        // `.removed` ist endgültig – außer das Medium ist wieder da (aus „Zuletzt gelöscht“ zurückgeholt,
        // gleiche ID). Dann darf es neu entschieden werden; Termin- und Markierungsaktionen bleiben ungültig.
        if from == .removed {
            switch action {
            case .keep, .markForCleanup, .later: break
            default: return .failure(.invalidTransition(from: from, action: name(action)))
            }
        }
        switch action {
        case .keep:
            return .success(DecisionSnapshot(disposition: .kept))
        case .markForCleanup:
            return .success(DecisionSnapshot(disposition: .markedForCleanup))
        case .later(let session):
            // Ein vorhandener Termin bleibt bestehen (fälliges Item erneut ohne Datum auf Später).
            let due = from == .later ? record.dueDay : nil
            return .success(DecisionSnapshot(disposition: .later, dueDay: due, skippedInSession: session))
        case .schedule(let day):
            guard from == .later else { return .failure(.invalidTransition(from: from, action: name(action))) }
            return .success(DecisionSnapshot(disposition: .later, dueDay: day, skippedInSession: record.skippedInSession))
        case .bookmark:
            guard from == .later else { return .failure(.invalidTransition(from: from, action: name(action))) }
            return .success(DecisionSnapshot(disposition: .later, dueDay: nil,
                                             skippedInSession: record.skippedInSession, bookmarked: true))
        case .removeDeferral:
            guard from == .later else { return .failure(.invalidTransition(from: from, action: name(action))) }
            return .success(DecisionSnapshot(disposition: .undecided))
        case .unmark:
            guard from == .markedForCleanup else { return .failure(.invalidTransition(from: from, action: name(action))) }
            return .success(DecisionSnapshot(disposition: .undecided))
        }
    }

    static func historyKind(from: DecisionSnapshot, action: DecisionAction) -> HistoryKind {
        switch action {
        case .keep, .markForCleanup, .later:
            return from.disposition == .undecided || from.disposition == .removed ? .decision : .correction
        case .schedule, .bookmark: return .scheduleChanged
        case .removeDeferral: return .deferralRemoved
        case .unmark: return .unmarked
        }
    }

    static func name(_ action: DecisionAction) -> String {
        switch action {
        case .keep: "keep"
        case .markForCleanup: "markForCleanup"
        case .later: "later"
        case .schedule: "schedule"
        case .bookmark: "bookmark"
        case .removeDeferral: "removeDeferral"
        case .unmark: "unmark"
        }
    }
}

/// Actor-geschützte Command-Instanz für alle zustandsändernden Aktionen.
///
/// Jede Methode berechnet eine `LedgerChange`, schreibt sie synchron über `LedgerPersistence`
/// und übernimmt sie erst nach erfolgreichem Schreiben in den Speicherzustand.
/// Bei Persistenzfehler bleibt der Zustand unverändert und der Fehler wird geworfen.
public actor DecisionLedger {
    public static let undoLimit = 200

    private var state: LedgerState
    private var processedCommands: [CommandID: ItemReference]
    private let persistence: any LedgerPersistence
    private let clock: any Clock

    public init(persistence: any LedgerPersistence, clock: any Clock = SystemClock()) throws {
        self.persistence = persistence
        self.clock = clock
        self.state = try persistence.load()
        var processed: [CommandID: ItemReference] = [:]
        for e in state.events { if let c = e.commandID { processed[c] = e.item } }
        self.processedCommands = processed
    }

    // MARK: Abfragen

    public func record(for item: ItemReference) -> ItemRecord {
        state.records[item] ?? ItemRecord(item: item)
    }

    public func records(for items: [ItemReference]) -> [ItemReference: ItemRecord] {
        var out: [ItemReference: ItemRecord] = [:]
        for i in items { out[i] = record(for: i) }
        return out
    }

    public func allRecords() -> [ItemRecord] { Array(state.records.values) }

    public func events() -> [DecisionEvent] { state.events }

    public func canUndo() -> Bool { !state.undoStack.isEmpty }

    public func openIntents() -> [OperationIntent] {
        state.intents.values.filter { !$0.state.isTerminal }.sorted { $0.createdAt < $1.createdAt }
    }

    public func intent(_ id: OperationID) -> OperationIntent? { state.intents[id] }

    public func snapshotState() -> LedgerState { state }

    /// Items, die aktuell zur Bereinigung vorgemerkt sind (= Auswahlkorb).
    public func basket() -> [ItemRecord] {
        state.records.values.filter { $0.disposition == .markedForCleanup }
            .sorted { $0.item.description < $1.item.description }
    }

    public func allowance(limit: Int?) -> AllowanceSnapshot {
        Self.allowance(in: state, day: clock.today, limit: limit)
    }

    /// Tageskontingent aus einem bereits gelesenen Zustand (Lesemodelle der UI).
    public nonisolated static func allowance(in state: LedgerState, day: LocalDay, limit: Int?) -> AllowanceSnapshot {
        let u = state.usage[day] ?? DayUsage()
        return AllowanceSnapshot(day: day, limit: limit, confirmed: u.confirmed, reserved: u.reserved)
    }

    // MARK: Entscheidungen

    @discardableResult
    public func apply(_ command: DecisionCommand, sessionID: ReviewSessionID? = nil) throws -> CommitOutcome {
        if let seen = processedCommands[command.id], seen == command.item {
            return .duplicate(record(for: command.item))
        }
        let current = record(for: command.item)
        guard current.revision == command.expectedRevision else {
            throw DecisionError.staleRevision(expected: command.expectedRevision, actual: current.revision)
        }
        if isBusy(command.item) { throw DecisionError.itemBusy }

        let target: DecisionSnapshot
        switch DecisionRules.transition(current, command.action) {
        case .success(let s): target = s
        case .failure(let e): throw e
        }
        if target == current.snapshot { return .unchanged(current) }

        var next = current
        next.apply(target)
        next.revision += 1

        var change = LedgerChange()
        change.records = [next]
        change.events = [DecisionEvent(
            commandID: command.id, item: command.item,
            kind: DecisionRules.historyKind(from: current.snapshot, action: command.action),
            from: current.snapshot, to: target, revision: next.revision,
            at: clock.now, sessionID: sessionID)]

        var undo = state.undoStack
        if let amended = command.amends,
           let idx = undo.lastIndex(where: { $0.commandID == amended && $0.item == command.item }),
           undo[idx].afterRevision == current.revision {
            undo[idx].afterRevision = next.revision
        } else {
            undo.append(UndoEntry(commandID: command.id, item: command.item,
                                  before: current.snapshot, beforeRevision: current.revision,
                                  afterRevision: next.revision))
            if undo.count > Self.undoLimit { undo.removeFirst(undo.count - Self.undoLimit) }
        }
        change.undoStack = undo

        try persist(change)
        processedCommands[command.id] = command.item
        return .applied(next)
    }

    /// Nimmt den jüngsten Befehl exakt zurück. Überschreibt keine neuere Entscheidung.
    @discardableResult
    public func undo() throws -> ItemRecord {
        guard let entry = state.undoStack.last else { throw DecisionError.nothingToUndo }
        var undo = state.undoStack
        undo.removeLast()
        let current = record(for: entry.item)
        // Laufende Systemoperation: Eintrag bleibt erhalten, Undo ist nur gerade nicht möglich.
        if isBusy(entry.item) { throw DecisionError.itemBusy }
        guard current.revision == entry.afterRevision else {
            // Nicht mehr anwendbar (neuere Entscheidung oder Bereinigung): Eintrag verwerfen.
            var change = LedgerChange()
            change.undoStack = undo
            try persist(change)
            throw DecisionError.undoConflict
        }
        var next = current
        next.apply(entry.before)
        next.revision += 1
        // Der vorherige Befehl desselben Items bleibt rücknehmbar: sein Zielzustand ist wiederhergestellt.
        if let idx = undo.lastIndex(where: { $0.item == entry.item }),
           undo[idx].afterRevision == entry.beforeRevision {
            undo[idx].afterRevision = next.revision
        }
        var change = LedgerChange()
        change.records = [next]
        change.undoStack = undo
        change.events = [DecisionEvent(
            commandID: nil, item: entry.item, kind: .undo,
            from: current.snapshot, to: entry.before, revision: next.revision,
            at: clock.now, sessionID: nil)]
        try persist(change)
        return next
    }

    // MARK: Bereinigung (Operation-Journal + Tageskontingent)

    /// Schreibt die Absicht dauerhaft und reserviert Tageskapazität atomar.
    /// - Parameter dailyLimit: `nil` = unbegrenzt (Pro).
    /// - Parameter aliasKeys: gleiche Ressource über mehrere Quellen; Konflikte werden abgelehnt.
    public func prepareCleanup(_ items: [ItemReference], kind: CleanupOperationKind,
                               dailyLimit: Int?, aliasKeys: [ItemReference: String] = [:]) throws -> OperationIntent {
        let unique = Array(Set(items)).sorted { $0.description < $1.description }
        guard !unique.isEmpty else { throw CleanupError.emptySelection }
        var seenAliases: [String: ItemReference] = [:]
        var revisions: [ItemReference: Int] = [:]
        for item in unique {
            let r = record(for: item)
            guard r.disposition == .markedForCleanup else { throw CleanupError.notMarked(item) }
            if isBusy(item) { throw CleanupError.itemBusy(item) }
            if let key = aliasKeys[item] {
                if seenAliases[key] != nil { throw CleanupError.aliasConflict(item) }
                seenAliases[key] = item
            }
            revisions[item] = r.revision
        }
        let day = clock.today
        var usage = state.usage[day] ?? DayUsage()
        var reserved = 0
        if let limit = dailyLimit {
            let available = max(0, limit - usage.confirmed - usage.reserved)
            guard unique.count <= available else {
                throw CleanupError.allowanceExceeded(requested: unique.count, available: available)
            }
            reserved = unique.count
        }
        let intent = OperationIntent(id: OperationID(), kind: kind, items: revisions,
                                     allowanceDay: day, reservedCount: reserved,
                                     state: .prepared, createdAt: clock.now)
        usage.reservations[intent.id] = reserved
        var change = LedgerChange()
        change.intents = [intent]
        change.usage = [day: usage]
        try persistCleanup(change)
        return intent
    }

    /// Muss unmittelbar vor dem Start der Systemoperation gespeichert werden.
    public func markSubmitted(_ id: OperationID) throws {
        guard var intent = state.intents[id] else { throw CleanupError.unknownOperation }
        guard intent.state == .prepared else { throw CleanupError.invalidState(intent.state) }
        intent.state = .submitted
        intent.updatedAt = clock.now
        var change = LedgerChange()
        change.intents = [intent]
        try persistCleanup(change)
    }

    /// Gleicht das Ergebnis genau einmal ab. Wiederholte Callbacks sind wirkungslos.
    @discardableResult
    public func reconcile(_ id: OperationID, outcome: OperationOutcome) throws -> OperationIntent {
        guard let intent = state.intents[id] else { throw CleanupError.unknownOperation }
        if intent.state.isTerminal { return intent }
        let all = Set(intent.items.keys)
        let removed: Set<ItemReference>
        switch outcome {
        case .succeeded: removed = all
        case .partial(let r): removed = r.intersection(all)
        case .cancelled, .failed: removed = []
        }
        let final: OperationState
        switch outcome {
        case .cancelled: final = .cancelled
        case .failed: final = removed.isEmpty ? .failed : .partiallySucceeded
        case .succeeded, .partial:
            final = removed == all ? .succeeded : (removed.isEmpty ? .failed : .partiallySucceeded)
        }
        return try finalize(intent, removed: removed, state: final, kind: .cleanupConfirmed)
    }

    /// Nach App-Start: offene Absichten klären. Nie automatisch erneut löschen.
    /// - `prepared` (Systemoperation nie gestartet) → abgebrochen, Kapazität frei.
    /// - `submitted` (Ergebnis unbekannt) → `reconciliationRequired`, Kapazität bleibt reserviert.
    @discardableResult
    public func recoverAfterLaunch() throws -> [OperationIntent] {
        var result: [OperationIntent] = []
        for intent in openIntents() {
            switch intent.state {
            case .prepared:
                _ = try finalize(intent, removed: [], state: .cancelled, kind: .cleanupNotPerformed)
            case .submitted:
                var i = intent
                i.state = .reconciliationRequired
                i.updatedAt = clock.now
                var change = LedgerChange()
                change.intents = [i]
                try persistCleanup(change)
                result.append(i)
            case .reconciliationRequired:
                result.append(intent)
            default: break
            }
        }
        return result
    }

    /// Abgleich eines unklaren Ergebnisses über Existenzprüfungen.
    /// Fehlender Zugriff (`.unknown`) ist kein Löschbeweis: dann bleibt der Status bestehen.
    @discardableResult
    public func resolveReconciliation(_ id: OperationID, probes: [ItemReference: ExistenceProbe]) throws -> OperationIntent {
        guard let intent = state.intents[id] else { throw CleanupError.unknownOperation }
        guard intent.state == .reconciliationRequired else { throw CleanupError.invalidState(intent.state) }
        var missing: Set<ItemReference> = []
        for item in intent.items.keys {
            switch probes[item] ?? .unknown {
            case .exists: continue
            case .missingWithFullAccess: missing.insert(item)
            case .unknown: return intent
            }
        }
        let final: OperationState = missing.isEmpty ? .failed
            : (missing.count == intent.items.count ? .succeeded : .partiallySucceeded)
        return try finalize(intent, removed: missing, state: final, kind: .reconciledMissing)
    }

    // MARK: Intern

    private func isBusy(_ item: ItemReference) -> Bool {
        state.intents.values.contains { !$0.state.isTerminal && $0.items[item] != nil }
    }

    private func finalize(_ intent: OperationIntent, removed: Set<ItemReference>,
                          state final: OperationState, kind: HistoryKind) throws -> OperationIntent {
        var i = intent
        i.state = final
        i.updatedAt = clock.now
        i.confirmedRemoved = removed

        var change = LedgerChange()
        for item in intent.items.keys.sorted(by: { $0.description < $1.description }) {
            let current = record(for: item)
            if removed.contains(item) {
                var next = current
                next.apply(DecisionSnapshot(disposition: .removed))
                next.revision += 1
                change.records.append(next)
                change.events.append(DecisionEvent(
                    commandID: nil, operationID: intent.id, item: item, kind: kind,
                    from: current.snapshot, to: next.snapshot, revision: next.revision,
                    at: clock.now, sessionID: nil))
            } else if final == .failed || final == .cancelled || final == .partiallySucceeded {
                change.events.append(DecisionEvent(
                    commandID: nil, operationID: intent.id, item: item, kind: .cleanupNotPerformed,
                    from: current.snapshot, to: current.snapshot, revision: current.revision,
                    at: clock.now, sessionID: nil))
            }
        }
        var usage = state.usage[intent.allowanceDay] ?? DayUsage()
        usage.reservations[intent.id] = nil
        if intent.reservedCount > 0 { usage.confirmed += removed.count }
        change.usage = [intent.allowanceDay: usage]
        change.intents = [i]
        try persistCleanup(change)
        return i
    }

    private func persist(_ change: LedgerChange) throws {
        do { try persistence.commit(change) } catch {
            throw DecisionError.persistenceFailed(String(describing: error))
        }
        state.merge(change)
    }

    private func persistCleanup(_ change: LedgerChange) throws {
        do { try persistence.commit(change) } catch {
            throw CleanupError.persistenceFailed(String(describing: error))
        }
        state.merge(change)
    }
}

/// Speicher ohne Datei. Nur für Tests, Previews und QA-Builds.
public final class InMemoryLedgerPersistence: LedgerPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: LedgerState
    /// Testhilfe: nächste `commit`-Aufrufe schlagen fehl.
    public var failNextCommits = 0
    public private(set) var commitCount = 0

    public init(_ initial: LedgerState = LedgerState()) { self.stored = initial }

    public func load() throws -> LedgerState {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func commit(_ change: LedgerChange) throws {
        lock.lock(); defer { lock.unlock() }
        if failNextCommits > 0 {
            failNextCommits -= 1
            throw InMemoryLedgerPersistence.Failure.injected
        }
        stored.merge(change)
        commitCount += 1
    }

    public var storedState: LedgerState {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public enum Failure: Error { case injected }
}
