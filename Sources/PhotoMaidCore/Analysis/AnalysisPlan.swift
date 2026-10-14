import Foundation

/// Reihenfolge der Analysen auf diesem iPhone: eine läuft, weitere warten. Das Öffnen einer anderen Analyse hält die
/// laufende nie an – „Analyse starten“ reiht dann nur ein; „Jetzt zuerst“ zieht vor, die bisherige wartet danach
/// vorne weiter. Reine Planungslogik (wird als JSON gespeichert), entscheidet nie über Fotos.
public struct AnalysisPlan: Codable, Equatable, Sendable {
    /// Läuft gerade bzw. lief zuletzt (und wird beim Fortsetzen weitergeführt).
    public private(set) var current: AnalysisKind?
    /// Warten in dieser Reihenfolge (ohne `current`, ohne Doppelte).
    public private(set) var waiting: [AnalysisKind]

    public enum Request: Equatable, Sendable {
        /// Jetzt starten (bzw. fortsetzen).
        case start
        /// Läuft bereits.
        case alreadyRunning
        /// Wartet; Position 1 = als Nächstes.
        case queued(position: Int)
    }

    public init(current: AnalysisKind? = nil, waiting: [AnalysisKind] = []) {
        self.current = current
        var seen: Set<AnalysisKind> = current.map { [$0] } ?? []
        self.waiting = waiting.filter { seen.insert($0).inserted }
    }

    /// Wartet `kind`? 1 = als Nächstes.
    public func position(of kind: AnalysisKind) -> Int? {
        waiting.firstIndex(of: kind).map { $0 + 1 }
    }

    /// „Analyse starten“ für `kind`. `running`: ein Lauf ist gerade aktiv (für `current`).
    /// `keepCurrent`: die bisherige, nicht laufende Analyse soll später weiterlaufen (sie wurde nicht ausdrücklich
    /// angehalten und hat noch Arbeit) – sie wartet dann vorne.
    public mutating func request(_ kind: AnalysisKind, running: Bool, keepCurrent: Bool) -> Request {
        if current == kind { return running ? .alreadyRunning : .start }
        if running {
            if !waiting.contains(kind) { waiting.append(kind) }
            return .queued(position: position(of: kind) ?? waiting.count)
        }
        waiting.removeAll { $0 == kind }
        if let previous = current, keepCurrent { waiting.insert(previous, at: 0) }
        current = kind
        return .start
    }

    /// „Jetzt zuerst“: `kind` wird die laufende Analyse, die bisherige wartet als Nächste.
    public mutating func prioritize(_ kind: AnalysisKind) {
        guard current != kind else { return }
        waiting.removeAll { $0 == kind }
        if let previous = current { waiting.insert(previous, at: 0) }
        current = kind
    }

    /// Die laufende Analyse ist fertig (oder wartet nur noch auf WLAN für iCloud): die nächste wartende beginnt.
    public mutating func advance() -> AnalysisKind? {
        guard !waiting.isEmpty else { current = nil; return nil }
        current = waiting.removeFirst()
        return current
    }

    /// Nicht mehr warten lassen.
    public mutating func remove(_ kind: AnalysisKind) {
        waiting.removeAll { $0 == kind }
    }
}

/// Was eine Analyse über die Verfügbarkeit auf dem Gerät schon weiß, gilt ohne neue Anfrage auch für andere:
/// Ist die Vorschau einer Größe nur in iCloud, ist es jede größere erst recht. So prüft nur die erste Analyse die
/// „nur in iCloud“-Fotos (bei großen Mediatheken Tausende), alle weiteren überspringen sie sofort.
public enum AnalysisAvailability {
    /// Kennungen, die eine andere Analyse mit höchstens gleich großer Vorschau als „nur in iCloud“ gespeichert hat.
    public static func knownCloudOnly(for kind: AnalysisKind,
                                      states: [AnalysisKind: [String: AnalysisItemState]]) -> Set<String> {
        var result = Set<String>()
        for (other, map) in states where other != kind && other.pixelLimit <= kind.pixelLimit {
            for (id, state) in map where state == .waitingForCloud { result.insert(id) }
        }
        return result
    }
}
