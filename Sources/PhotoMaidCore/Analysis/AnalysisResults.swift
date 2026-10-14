import Foundation

/// Sichtbare Treffer einer Analyse: geordnet (z. B. „am unschärfsten zuerst“), nur sichtbare und – solange nicht anders
/// gewählt – nur noch offene Medien. Bereits entschiedene Fotos verschwinden so aus der Liste, sobald im Feed
/// entschieden wurde. Reine Filterlogik: entscheidet nie etwas.
public struct AnalysisResultPage: Equatable, Sendable {
    /// Alle passenden Kennungen in Anzeigereihenfolge (Grundlage für „Durchwischen“).
    public let all: [String]
    /// Kennungen der aktuellen Seite.
    public let ids: [String]
    /// Tatsächlich gezeigte Seite (nach dem Filtern ggf. auf die letzte vorhandene Seite gekürzt).
    public let page: Int
    public let pageSize: Int

    public var total: Int { all.count }
    public var canNext: Bool { (page + 1) * pageSize < total }

    public init(ordered: [String], include: (String) -> Bool, page: Int, pageSize: Int) {
        var seen = Set<String>()
        let all = ordered.filter { include($0) && seen.insert($0).inserted }
        let size = max(1, pageSize)
        let page = min(max(0, page), max(0, (all.count - 1) / size))
        let start = min(all.count, page * size)
        self.all = all
        self.ids = Array(all[start..<min(all.count, start + size)])
        self.page = page
        self.pageSize = size
    }

    /// „Durchwischen“ ab einem angetippten Treffer: dieser zuerst, dann die folgenden, danach die davor.
    public func feedOrder(startingAt id: String?) -> [String] {
        guard let id, let i = all.firstIndex(of: id) else { return all }
        return Array(all[i...]) + Array(all[..<i])
    }
}

/// Gruppen ähnlicher Aufnahmen: nur sichtbare/offene Mitglieder, Gruppen mit weniger als zwei Mitgliedern entfallen.
/// Reihenfolge der Gruppen bleibt stabil.
public struct AnalysisGroupPage: Equatable, Sendable {
    public let all: [[String]]
    public let groups: [[String]]
    public let page: Int
    public let pageSize: Int

    public var total: Int { all.count }
    public var memberCount: Int { all.reduce(0) { $0 + $1.count } }
    public var canNext: Bool { (page + 1) * pageSize < total }

    public init(groups source: [[String]], include: (String) -> Bool, page: Int, pageSize: Int) {
        let all = source.map { $0.filter(include) }.filter { $0.count >= 2 }
        let size = max(1, pageSize)
        let page = min(max(0, page), max(0, (all.count - 1) / size))
        let start = min(all.count, page * size)
        self.all = all
        self.groups = Array(all[start..<min(all.count, start + size)])
        self.page = page
        self.pageSize = size
    }
}

/// Wärme: drosseln statt abbrechen. Gilt für die Analyse und das Messen von Größen/Duplikaten.
/// `nominal` = volle Geschwindigkeit, `fair` = halbe Parallelität mit kurzer Pause, `serious` = warten (geht von selbst
/// weiter, sobald es kühler ist), `critical` = anhalten.
public enum WorkThermalLevel: Int, Sendable, Comparable {
    case nominal, fair, serious, critical
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum WorkThrottle: Equatable, Sendable {
    /// Weiterarbeiten mit höchstens `parallel` gleichzeitigen Aufträgen und `pauseMilliseconds` Pause je Auftrag.
    case run(parallel: Int, pauseMilliseconds: Int)
    /// Nichts Neues starten, bis es kühler ist (laufende Aufträge dürfen fertig werden).
    case waitForCooling
    /// Ganz anhalten (Fortschritt bleibt gespeichert).
    case stop

    public static func decide(_ level: WorkThermalLevel, maxParallel: Int) -> WorkThrottle {
        let full = max(1, maxParallel)
        switch level {
        case .nominal: return .run(parallel: full, pauseMilliseconds: 0)
        case .fair: return .run(parallel: max(1, full / 2), pauseMilliseconds: 150)
        case .serious: return .waitForCooling
        case .critical: return .stop
        }
    }
}

/// Wann eine angehaltene Analyse von selbst weiterläuft. Ein ausdrückliches „Anhalten“ des Nutzers gewinnt immer.
public enum AnalysisStopReason: String, Codable, Sendable {
    case user, background, thermal, network, memory, finished, error
}

public enum AnalysisAutoResume {
    /// `true`, wenn nach Rückkehr in die App bzw. nach dem Abkühlen automatisch fortgesetzt werden soll.
    public static func shouldResume(after reason: AnalysisStopReason?, pendingWork: Bool, thermal: WorkThermalLevel,
                                    cloudReady: Bool) -> Bool {
        guard pendingWork, let reason, thermal < .serious else { return false }
        switch reason {
        case .background, .thermal, .memory: return true
        case .network: return cloudReady
        case .user, .finished, .error: return false
        }
    }
}
