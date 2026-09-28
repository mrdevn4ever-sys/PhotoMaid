import Foundation

public struct ReviewSessionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public var description: String { rawValue.uuidString }
}

public struct CommandID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public var description: String { rawValue.uuidString }
}

/// PhotoMaid-Status eines Items. „Behalten“ ist ein PhotoMaid-Status und
/// setzt keinen Apple-Fotos-Favoriten.
public enum Disposition: String, Hashable, Codable, Sendable {
    case undecided
    case kept
    case markedForCleanup
    case later
    /// Nach bestätigter Systemoperation entfernt (Fotos: in „Zuletzt gelöscht“, Dateien: je Operation).
    case removed
}

/// Aktueller, persistierter Zustand eines Items.
public struct ItemRecord: Hashable, Codable, Sendable {
    public let item: ItemReference
    /// Monoton steigend; jede Mutation erhöht die Revision, auch Undo.
    public var revision: Int
    public var disposition: Disposition
    /// Höchstens ein aktiver Termin. Nur bei `.later` gesetzt.
    public var dueDay: LocalDay?
    /// Nur in dieser Review-Session übersprungen (Wischen nach rechts ohne neues Datum).
    public var skippedInSession: ReviewSessionID?

    public init(item: ItemReference) {
        self.item = item
        self.revision = 0
        self.disposition = .undecided
        self.dueDay = nil
        self.skippedInSession = nil
    }

    /// Der fachliche Anteil ohne Revision (für Idempotenz- und Undo-Vergleiche).
    public var snapshot: DecisionSnapshot {
        DecisionSnapshot(disposition: disposition, dueDay: dueDay, skippedInSession: skippedInSession)
    }

    mutating func apply(_ s: DecisionSnapshot) {
        disposition = s.disposition
        dueDay = s.dueDay
        skippedInSession = s.skippedInSession
    }
}

public struct DecisionSnapshot: Hashable, Codable, Sendable {
    public var disposition: Disposition
    public var dueDay: LocalDay?
    public var skippedInSession: ReviewSessionID?

    public init(disposition: Disposition, dueDay: LocalDay? = nil, skippedInSession: ReviewSessionID? = nil) {
        self.disposition = disposition
        self.dueDay = dueDay
        self.skippedInSession = skippedInSession
    }
}

/// Eine ausdrückliche Nutzeraktion auf einem Item.
public enum DecisionAction: Hashable, Codable, Sendable {
    /// Finger nach oben.
    case keep
    /// Finger nach links. Vormerken, nicht löschen.
    case markForCleanup
    /// Finger nach rechts. Nur diese Session zurückstellen; ein vorhandener Termin bleibt.
    case later(session: ReviewSessionID)
    /// Termin für ein zurückgestelltes Item setzen/ändern (Receipt-Leiste oder Später-Verwaltung).
    case schedule(LocalDay)
    /// Zurückstellung entfernen. Löscht keine Datei; Item wird wieder unentschieden.
    case removeDeferral
    /// Aus dem Auswahlkorb abwählen. Item wird wieder unentschieden.
    case unmark
}

/// Befehl mit stabiler Item-ID, erwarteter Revision und Command-ID.
/// Entscheidungen werden niemals über einen veränderlichen `currentItem`-Zeiger getroffen.
public struct DecisionCommand: Hashable, Codable, Sendable {
    public let id: CommandID
    public let item: ItemReference
    public let expectedRevision: Int
    public let action: DecisionAction
    /// Gehört dieser Befehl zu einem früheren Befehl (z. B. Terminwahl nach Swipe rechts),
    /// wird er beim Undo gemeinsam mit diesem zurückgenommen.
    public let amends: CommandID?

    public init(id: CommandID = CommandID(), item: ItemReference, expectedRevision: Int,
                action: DecisionAction, amends: CommandID? = nil) {
        self.id = id
        self.item = item
        self.expectedRevision = expectedRevision
        self.action = action
        self.amends = amends
    }
}

public enum HistoryKind: String, Hashable, Codable, Sendable {
    case decision
    case correction
    case scheduleChanged
    case deferralRemoved
    case unmarked
    case undo
    case cleanupConfirmed
    case cleanupNotPerformed
    case reconciledMissing
}

/// Nachvollziehbarer Verlaufseintrag. Zeitpunkt als UTC-Instant.
public struct DecisionEvent: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let commandID: CommandID?
    public let operationID: OperationID?
    public let item: ItemReference
    public let kind: HistoryKind
    public let from: DecisionSnapshot
    public let to: DecisionSnapshot
    public let revision: Int
    public let at: Date
    public let sessionID: ReviewSessionID?

    public init(id: UUID = UUID(), commandID: CommandID?, operationID: OperationID? = nil,
                item: ItemReference, kind: HistoryKind, from: DecisionSnapshot, to: DecisionSnapshot,
                revision: Int, at: Date, sessionID: ReviewSessionID?) {
        self.id = id
        self.commandID = commandID
        self.operationID = operationID
        self.item = item
        self.kind = kind
        self.from = from
        self.to = to
        self.revision = revision
        self.at = at
        self.sessionID = sessionID
    }
}

/// Eintrag der gemeinsamen Command-Historie für Undo.
public struct UndoEntry: Hashable, Codable, Sendable {
    public let commandID: CommandID
    public let item: ItemReference
    /// Exakter Zustand vor dem Befehl.
    public let before: DecisionSnapshot
    /// Revision vor dem Befehl.
    public let beforeRevision: Int
    /// Revision nach dem (ggf. ergänzten) Befehl. Undo nur, wenn das Item noch diese Revision hat.
    public var afterRevision: Int
}

public enum DecisionError: Error, Hashable, Sendable {
    /// Das Item wurde inzwischen verändert (andere Revision).
    case staleRevision(expected: Int, actual: Int)
    /// Aktion in diesem Zustand nicht zulässig.
    case invalidTransition(from: Disposition, action: String)
    /// Item ist Teil einer laufenden Systemoperation.
    case itemBusy
    /// Nichts zum Rückgängigmachen.
    case nothingToUndo
    /// Undo würde eine neuere Entscheidung überschreiben.
    case undoConflict
    /// Persistenz fehlgeschlagen; Zustand unverändert.
    case persistenceFailed(String)
}

public enum CommitOutcome: Hashable, Sendable {
    /// Zustand geändert und persistiert.
    case applied(ItemRecord)
    /// Dieselbe Entscheidung erneut: keine Änderung, keine doppelten Zähler.
    case unchanged(ItemRecord)
    /// Dieselbe Command-ID wurde bereits verarbeitet (Wiederholung).
    case duplicate(ItemRecord)

    public var record: ItemRecord {
        switch self {
        case .applied(let r), .unchanged(let r), .duplicate(let r): r
        }
    }
}
