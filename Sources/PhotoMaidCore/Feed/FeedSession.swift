import Foundation

/// Offener Commit: an Item, Revision und Command-ID gebunden – nie an `currentIndex`.
public struct PendingCommit: Hashable, Sendable {
    public let command: DecisionCommand
    public let intent: FeedIntent
    public let index: Int
}

/// Terminleiste nach Swipe rechts. Gehört zum zurückgestellten Item,
/// nicht zum inzwischen angezeigten nächsten Item.
public struct LaterReceipt: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let item: ItemReference
    /// Command-ID der ursprünglichen Später-Aktion (Undo nimmt Termin + Später gemeinsam zurück).
    public let laterCommandID: CommandID
    /// Revision nach der Später-Aktion.
    public let revision: Int
    /// `true` nach Wisch schräg nach rechts oben: Termin im Drehrad selbst wählen.
    public let wantsCustomDate: Bool
}

public enum BackNavigation: Hashable, Sendable {
    case moved(to: Int)
    /// Anfang der Session: dezenter Anschlag, keine Aktion.
    case atStart
}

public struct SessionSummary: Hashable, Sendable {
    public var kept = 0
    public var marked = 0
    public var later = 0
    public var reviewed: Int { kept + marked + later }
}

/// Eine Review-Session im Feed. Reiner Wert, testbar ohne UI.
public struct FeedSession: Hashable, Sendable {
    public let id: ReviewSessionID
    public let items: [ItemReference]
    public private(set) var index: Int = 0
    public private(set) var pending: PendingCommit?
    public private(set) var receipt: LaterReceipt?
    /// Letzte Entscheidung je Item in dieser Session (Korrekturen ersetzen, kein Doppelzählen).
    public private(set) var decisions: [ItemReference: FeedIntent] = [:]
    /// Nur Items, deren Vorschau tatsächlich geladen ist, dürfen entschieden werden.
    private var previewReady: Set<ItemReference> = []

    public init(id: ReviewSessionID = ReviewSessionID(), items: [ItemReference]) {
        self.id = id
        var seen = Set<ItemReference>()
        self.items = items.filter { seen.insert($0).inserted }
    }

    public var current: ItemReference? { items.indices.contains(index) ? items[index] : nil }
    public var isFinished: Bool { index >= items.count }
    public var position: (current: Int, total: Int) { (min(index + 1, items.count), items.count) }

    public var summary: SessionSummary {
        var s = SessionSummary()
        for d in decisions.values {
            switch d {
            case .keep: s.kept += 1
            case .markForCleanup: s.marked += 1
            case .later, .laterCustom: s.later += 1
            case .previous: break
            }
        }
        return s
    }

    public mutating func markPreviewReady(_ item: ItemReference) { previewReady.insert(item) }
    public mutating func markPreviewUnavailable(_ item: ItemReference) { previewReady.remove(item) }
    public func isPreviewReady(_ item: ItemReference) -> Bool { previewReady.contains(item) }

    /// Erzeugt einen Befehl für das aktuell sichtbare Item.
    /// `nil`, wenn bereits ein Commit läuft, die Session zu Ende ist oder die Vorschau fehlt.
    public mutating func requestDecision(_ intent: FeedIntent, currentRevision: Int,
                                         commandID: CommandID = CommandID()) -> PendingCommit? {
        guard intent.isDecision, pending == nil, let item = current, previewReady.contains(item) else { return nil }
        let action: DecisionAction
        switch intent {
        case .keep: action = .keep
        case .markForCleanup: action = .markForCleanup
        case .later, .laterCustom: action = .later(session: id)
        case .previous: return nil
        }
        let p = PendingCommit(
            command: DecisionCommand(id: commandID, item: item, expectedRevision: currentRevision, action: action),
            intent: intent, index: index)
        pending = p
        receipt = nil // Neue Entscheidung schließt die alte Terminleiste.
        return p
    }

    /// Persistenz erfolgreich. Veraltete Callbacks (andere Command-ID) werden verworfen.
    /// - Returns: `true`, wenn der Callback zum offenen Commit gehörte.
    @discardableResult
    public mutating func commitSucceeded(_ commandID: CommandID, record: ItemRecord) -> Bool {
        guard let p = pending, p.command.id == commandID, record.item == p.command.item else { return false }
        pending = nil
        decisions[p.command.item] = p.intent
        if p.intent == .later || p.intent == .laterCustom {
            receipt = LaterReceipt(id: UUID(), item: p.command.item,
                                   laterCommandID: commandID, revision: record.revision,
                                   wantsCustomDate: p.intent == .laterCustom)
        }
        index = min(p.index + 1, items.count) // Genau ein Medium weiter.
        return true
    }

    /// Persistenz fehlgeschlagen: Item bleibt sichtbar, keine Entscheidung gezählt.
    @discardableResult
    public mutating func commitFailed(_ commandID: CommandID) -> Bool {
        guard let p = pending, p.command.id == commandID else { return false }
        pending = nil
        index = p.index
        return true
    }

    /// Finger nach unten: vorheriges Medium, keine Entscheidung.
    public mutating func goBack() -> BackNavigation {
        guard pending == nil, index > 0 else { return .atStart }
        index -= 1
        return .moved(to: index)
    }

    /// Programmgesteuertes Springen. Erzeugt niemals eine Entscheidung.
    public mutating func jump(to newIndex: Int) {
        guard pending == nil else { return }
        index = max(0, min(newIndex, items.count))
    }

    /// Befehl für einen Termin aus der Terminleiste.
    /// `nil`, wenn die Leiste inzwischen veraltet ist.
    public func scheduleCommand(receiptID: UUID, day: LocalDay) -> DecisionCommand? {
        guard let r = receipt, r.id == receiptID else { return nil }
        return DecisionCommand(item: r.item, expectedRevision: r.revision,
                               action: .schedule(day), amends: r.laterCommandID)
    }

    /// Nach gespeichertem Termin: Leiste/Pille bleibt änderbar, jetzt auf der neuen Revision.
    public mutating func receiptScheduled(_ receiptID: UUID, revision: Int) {
        guard let r = receipt, r.id == receiptID else { return }
        receipt = LaterReceipt(id: r.id, item: r.item, laterCommandID: r.laterCommandID,
                               revision: revision, wantsCustomDate: false)
    }

    public mutating func dismissReceipt(_ receiptID: UUID) {
        if receipt?.id == receiptID { receipt = nil }
    }

    /// Nach erfolgreichem Undo: Session-Zählung an den tatsächlichen Zustand anpassen.
    public mutating func applyUndo(_ record: ItemRecord) {
        if receipt?.item == record.item { receipt = nil }
        switch record.disposition {
        case .kept: decisions[record.item] = .keep
        case .markedForCleanup: decisions[record.item] = .markForCleanup
        case .later where record.skippedInSession == id: decisions[record.item] = .later
        default: decisions[record.item] = nil
        }
        if let i = items.firstIndex(of: record.item), pending == nil { index = i }
    }
}
