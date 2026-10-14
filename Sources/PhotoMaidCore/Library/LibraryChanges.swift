import Foundation

/// Was sich in der Mediathek seit der letzten Verarbeitung geändert hat. Fotos meldet bei großen Mediatheken laufend
/// Änderungen (iCloud-Abgleich, eigene Analyse von Fotos, geladene Vorschauen). Nur wenn Medien dazukommen oder
/// verschwinden, wird alles neu gelesen; sonst werden nur die geänderten Medien aktualisiert. Laufende Arbeit
/// (Analyse, Feed, Messen) läuft dabei weiter.
public struct LibraryChangeSummary: Equatable, Sendable {
    /// Medien dazu oder weg – oder iOS lieferte keine Einzelheiten.
    public var membership = false
    /// Geänderte Medien (Favorit, bearbeitet, Datum …).
    public var changed: Set<String> = []
    /// Nur Alben/Ordner geändert (keine Medien).
    public var collections = false

    public init() {}

    public var isEmpty: Bool { !membership && changed.isEmpty && !collections }

    /// Eine Meldung von Fotos. `details == nil`: die Abfrage aller Medien ist nicht betroffen (nur Alben o. Ä.).
    public mutating func add(incremental: Bool?, inserted: Int, removed: Int, changed ids: [String]) {
        guard let incremental else { collections = true; return }
        if !incremental || inserted > 0 || removed > 0 { membership = true }
        changed.formUnion(ids)
    }

    public enum Reaction: Equatable, Sendable {
        case none
        /// Nur diese Medien neu beschreiben (ohne Neuladen, ohne Ladeanzeige).
        case patch(Set<String>)
        /// Alles neu lesen (im Hintergrund; der bisherige Stand bleibt bis dahin sichtbar).
        case reload
    }

    /// `albumsMatter`: ausgeblendete oder vom Aufräumen ausgenommene Alben sind eingestellt – dann zählt auch eine
    /// reine Album-Änderung (deren Mitglieder werden mitgelesen).
    public func reaction(albumsMatter: Bool) -> Reaction {
        if membership || (collections && albumsMatter) { return .reload }
        return changed.isEmpty ? .none : .patch(changed)
    }
}

/// Fasst schnell aufeinanderfolgende Meldungen zusammen: gemeldet wird nach `quiet` Sekunden Ruhe, spätestens aber
/// `maxDelay` Sekunden nach der ersten noch offenen Meldung.
public struct ChangeCoalescer: Sendable {
    public let quiet: TimeInterval
    public let maxDelay: TimeInterval
    private var first: TimeInterval?

    public init(quiet: TimeInterval = 0.8, maxDelay: TimeInterval = 3) {
        self.quiet = quiet
        self.maxDelay = max(quiet, maxDelay)
    }

    /// Neue Meldung um `now`: so lange bis zum Melden warten (ein früherer Zeitgeber wird verworfen).
    public mutating func register(now: TimeInterval) -> TimeInterval {
        let start = first ?? now
        first = start
        let deadline = min(now + quiet, start + maxDelay)
        return max(0, deadline - now)
    }

    /// Gemeldet: die nächste Meldung beginnt eine neue Runde.
    public mutating func flushed() { first = nil }
}
