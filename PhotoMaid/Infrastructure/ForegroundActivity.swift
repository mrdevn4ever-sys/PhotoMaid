import Foundation
import PhotoMaidCore

/// Der Nutzer wischt gerade im Feed: Hintergrundarbeit (Analyse, Größen messen, Duplikate) tritt zurück – halbe
/// Parallelität mit kurzer Pause, wie bei einem warmen iPhone (`WorkThrottle`). So teilen sich Analyse-Downloads
/// aus iCloud und die Vorschauen im Feed nicht Netz und Rechenzeit.
enum ForegroundActivity {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var feeds = 0

    static var feedVisible: Bool { lock.withLock { feeds > 0 } }
    static func feedAppeared() { lock.withLock { feeds += 1 } }
    static func feedDisappeared() { lock.withLock { feeds = max(0, feeds - 1) } }

    /// Wärmestufe für die Drosselung von Hintergrundarbeit: mindestens „fair“, solange der Feed offen ist.
    static func workLevel() -> WorkThermalLevel {
        let thermal = AnalysisRunner.thermalLevel()
        return feedVisible ? max(thermal, .fair) : thermal
    }
}
