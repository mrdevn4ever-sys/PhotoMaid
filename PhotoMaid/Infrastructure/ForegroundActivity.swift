import Foundation
import PhotoMaidCore

/// Der Nutzer wischt gerade im Feed: Hintergrundarbeit (Analyse, Größen messen, Duplikate) wartet, bis der Feed
/// geschlossen ist oder ein Blatt darüber liegt (z. B. der Papierkorb mit seinen Größen), und macht dann von selbst
/// weiter (`WorkThrottle.waitForCooling`, höchstens 3 s später). Laufende Einzelaufträge werden noch fertig.
/// Keine Meldung, kein Hitzestopp: Ergebnisse kommen nur später, nicht schlechter. Beim Wischen bleiben Rechenzeit,
/// Netz und Wärme so ganz für die Vorschauen (Wärme-Audit 22.10.2026: im Feed lief die Analyse sonst mit).
enum ForegroundActivity {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var feeds = 0

    static var feedVisible: Bool { lock.withLock { feeds > 0 } }
    static func feedAppeared() { lock.withLock { feeds += 1 } }
    static func feedDisappeared() { lock.withLock { feeds = max(0, feeds - 1) } }

    /// Stufe für Hintergrundarbeit: „warten“, solange der Feed vorne ist, sonst die gedeckelte Wärmestufe.
    static func workLevel() -> WorkThermalLevel {
        let thermal = AnalysisRunner.thermalLevel()
        return feedVisible ? max(thermal, .serious) : thermal
    }
}
