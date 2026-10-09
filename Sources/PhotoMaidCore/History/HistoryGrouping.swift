import Foundation

/// Eine sichtbare Verlaufszeile. Reine Darstellung: das Journal bleibt unverändert, jedes Event bleibt erhalten.
/// `schedule` ist der unmittelbar zugehörige erste Termin eines „Auf später gelegt“.
public struct HistoryEntry: Hashable, Sendable, Identifiable {
    public let primary: DecisionEvent
    public var schedule: DecisionEvent?
    /// Weitere Items desselben Systemvorgangs (gleiche `operationID`, gleiche Art), z. B. ein abgebrochenes Leeren.
    public var batch: [DecisionEvent]

    public init(primary: DecisionEvent, schedule: DecisionEvent? = nil, batch: [DecisionEvent] = []) {
        self.primary = primary
        self.schedule = schedule
        self.batch = batch
    }

    public var id: UUID { primary.id }
    public var events: [DecisionEvent] { [primary] + (schedule.map { [$0] } ?? []) + batch }
    /// Anzahl betroffener Items dieser Zeile.
    public var itemCount: Int { 1 + batch.count }
}

public enum HistoryGrouping {
    /// Fasst „Auf später gelegt“ und den direkt folgenden ersten Termin zu einem Vorgang zusammen – nur bei eindeutiger
    /// Beziehung (gleiches Item, unmittelbar folgende Revision, Termin setzt den Zustand ohne Datum fort). Direkt
    /// aufeinanderfolgende Events desselben Systemvorgangs (gleiche `operationID`, gleiche Art) werden eine Zeile mit
    /// Anzahl. Alles andere bleibt einzeln. `chronological` ist aufsteigend sortiert (wie das Journal). Port von Android.
    public static func group(_ chronological: [DecisionEvent]) -> [HistoryEntry] {
        struct Key: Hashable { let item: ItemReference; let revision: Int }
        var laterByItemRevision: [Key: Int] = [:]
        var out: [HistoryEntry] = []
        out.reserveCapacity(chronological.count)
        for e in chronological {
            if e.kind == .scheduleChanged,
               let idx = laterByItemRevision.removeValue(forKey: Key(item: e.item, revision: e.revision - 1)),
               out[idx].primary.to == e.from, e.from.dueDay == nil {
                out[idx].schedule = e
                continue
            }
            if let op = e.operationID, let last = out.last, last.schedule == nil,
               last.primary.operationID == op, last.primary.kind == e.kind {
                out[out.count - 1].batch.append(e)
                continue
            }
            let isLater = (e.kind == .decision || e.kind == .correction) && e.to.disposition == .later && e.to.dueDay == nil
            if isLater { laterByItemRevision[Key(item: e.item, revision: e.revision)] = out.count }
            out.append(HistoryEntry(primary: e))
        }
        return out
    }
}
