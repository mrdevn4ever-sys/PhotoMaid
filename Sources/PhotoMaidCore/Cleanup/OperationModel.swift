import Foundation

public struct OperationID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public var description: String { rawValue.uuidString }
}

/// Konkrete Systemoperation. Fotos und Dateien verwenden bewusst verschiedene APIs.
public enum CleanupOperationKind: String, Hashable, Codable, Sendable {
    /// `PHPhotoLibrary.performChanges` + `PHAssetChangeRequest.deleteAssets`.
    /// Das System zeigt eine eigene Bestätigung; Assets landen in „Zuletzt gelöscht“.
    case photoLibraryDelete
    /// `FileManager.trashItem`, nur wenn die Quelle nachweislich einen Papierkorb anbietet.
    case fileMoveToTrash
    /// `FileManager.removeItem` nach eigener, deutlicher Bestätigung. Kein Undo.
    case fileDeletePermanently
}

public enum OperationState: String, Hashable, Codable, Sendable {
    /// Journal geschrieben, Kapazität reserviert, Systemoperation noch nicht gestartet.
    case prepared
    /// Systemoperation wurde gestartet. Ergebnis ausstehend.
    case submitted
    case succeeded
    case partiallySucceeded
    case cancelled
    case failed
    /// Prozessabbruch mit unklarem Ergebnis. Keine automatische Wiederholung.
    case reconciliationRequired

    public var isTerminal: Bool {
        switch self {
        case .succeeded, .partiallySucceeded, .cancelled, .failed: true
        case .prepared, .submitted, .reconciliationRequired: false
        }
    }
}

/// Dauerhaft gespeicherte Absicht vor einer Systemoperation.
public struct OperationIntent: Hashable, Codable, Sendable, Identifiable {
    public let id: OperationID
    public let kind: CleanupOperationKind
    /// Item → Revision zum Zeitpunkt der Freigabe.
    public let items: [ItemReference: Int]
    /// Tag, auf den die Kapazität gebucht wird (lokaler Kalendertag bei Freigabe).
    public let allowanceDay: LocalDay
    /// Reservierte Tageskapazität (0 bei unbegrenzter Pro-Bereinigung).
    public let reservedCount: Int
    public var state: OperationState
    public let createdAt: Date
    public var updatedAt: Date
    /// Tatsächlich bestätigt entfernte Items (nach Abgleich).
    public var confirmedRemoved: Set<ItemReference>

    public init(id: OperationID, kind: CleanupOperationKind, items: [ItemReference: Int],
                allowanceDay: LocalDay, reservedCount: Int, state: OperationState,
                createdAt: Date) {
        self.id = id
        self.kind = kind
        self.items = items
        self.allowanceDay = allowanceDay
        self.reservedCount = reservedCount
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.confirmedRemoved = []
    }
}

/// Ergebnis einer Provider-Operation, so wie die jeweilige API es belegt.
public enum OperationOutcome: Hashable, Sendable {
    /// Gesamter Request erfolgreich (PhotoKit: `performChanges` meldet Erfolg).
    case succeeded
    /// Nur bei Providern, die Einzelergebnisse belegen (Dateien).
    case partial(removed: Set<ItemReference>)
    /// Nutzer hat die System-Bestätigung abgebrochen.
    case cancelled
    /// Fehler. PhotoKit belegt keinen Teilerfolg; es gilt: nichts entfernt.
    case failed(reason: String)
}

/// Ergebnis einer Existenzprüfung beim Abgleich nach Prozessabbruch.
public enum ExistenceProbe: Hashable, Sendable {
    case exists
    /// Nicht mehr auffindbar, und der Zugriff war vollständig (nicht limited/denied).
    case missingWithFullAccess
    /// Kein Beweis möglich (fehlender Zugriff, Provider-Fehler). Kein Löschbeweis.
    case unknown
}

public enum CleanupError: Error, Hashable, Sendable {
    case emptySelection
    case notMarked(ItemReference)
    case staleRevision(ItemReference)
    case itemBusy(ItemReference)
    /// Mehr gewählt als heute verfügbar. Nutzer muss auswählen.
    case allowanceExceeded(requested: Int, available: Int)
    case unknownOperation
    case invalidState(OperationState)
    case aliasConflict(ItemReference)
    case persistenceFailed(String)
}

/// Tageskontingent für bestätigte Bereinigungen (Free: 15 pro lokalem Kalendertag).
public struct DayUsage: Hashable, Codable, Sendable {
    public var confirmed: Int = 0
    public var reservations: [OperationID: Int] = [:]
    public init() {}
    public var reserved: Int { reservations.values.reduce(0, +) }
}

public struct AllowanceSnapshot: Hashable, Sendable {
    public let day: LocalDay
    public let limit: Int?
    public let confirmed: Int
    public let reserved: Int
    /// `nil` = unbegrenzt.
    public var available: Int? {
        guard let limit else { return nil }
        return max(0, limit - confirmed - reserved)
    }
}
