import Foundation

/// Gesamter lokaler Zustand, der transaktional gemeinsam gespeichert wird:
/// Entscheidungen, Verlauf, Undo-Historie, Operation-Journal und Tageskontingent.
public struct LedgerState: Hashable, Codable, Sendable {
    public var records: [ItemReference: ItemRecord] = [:]
    public var events: [DecisionEvent] = []
    public var undoStack: [UndoEntry] = []
    public var intents: [OperationID: OperationIntent] = [:]
    public var usage: [LocalDay: DayUsage] = [:]

    public init() {}
}

/// Eine atomare Änderung. Die Persistenz schreibt sie ganz oder gar nicht.
public struct LedgerChange: Hashable, Sendable {
    public var records: [ItemRecord] = []
    public var events: [DecisionEvent] = []
    /// Vollständige neue Undo-Historie, wenn geändert.
    public var undoStack: [UndoEntry]?
    public var intents: [OperationIntent] = []
    public var usage: [LocalDay: DayUsage] = [:]

    public init() {}

    public var isEmpty: Bool {
        records.isEmpty && events.isEmpty && undoStack == nil && intents.isEmpty && usage.isEmpty
    }
}

/// Einzige Persistenzquelle für Entscheidungen (Produktion: Core Data ohne CloudKit).
///
/// `commit` ist bewusst synchron: Der `DecisionLedger`-Actor darf zwischen Berechnung
/// und Speicherung nicht suspendieren, sonst könnten sich Befehle überholen.
public protocol LedgerPersistence: Sendable {
    func load() throws -> LedgerState
    func commit(_ change: LedgerChange) throws
}

extension LedgerState {
    mutating func merge(_ change: LedgerChange) {
        for r in change.records { records[r.item] = r }
        events.append(contentsOf: change.events)
        if let u = change.undoStack { undoStack = u }
        for i in change.intents { intents[i.id] = i }
        for (day, u) in change.usage { usage[day] = u }
    }
}
