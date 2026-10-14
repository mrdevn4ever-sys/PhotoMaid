import Foundation
import MetricKit
import OSLog

/// Lokale Diagnose für Testbuilds ohne Mac: „Einstellungen › Hilfe › Diagnose teilen“ erzeugt eine Textdatei aus
/// dem eigenen Protokoll dieser App (`OSLogStore`, nur dieser Prozess) und den MetricKit-Berichten (Abstürze, Hänger).
///
/// Datenschutz: Es werden nur feste Ereigniskürzel geschrieben – nie Medien, Dateinamen, Pfade, Medien-IDs, Texte des
/// Nutzers oder Zahlen über die Mediathek. Nichts verlässt das Gerät, außer der Nutzer teilt die Datei selbst.
enum Diagnostics {
    enum Area: String, Sendable {
        case app, feed, cleanup, library, purchase, editor, video, pdf, analysis, archive, files, persistence, ads
    }

    static let subsystem = "app.photomaid"

    /// Nur Kürzel aus dem Quellcode (StaticString-ähnlich), keine Laufzeitdaten des Nutzers.
    static func log(_ area: Area, _ event: String) {
        Logger(subsystem: subsystem, category: area.rawValue).notice("\(event, privacy: .public)")
    }

    static func error(_ area: Area, _ event: String, _ error: any Error) {
        let ns = error as NSError
        // Nur Fehlerdomäne und Code – keine Beschreibung (kann Pfade enthalten).
        Logger(subsystem: subsystem, category: area.rawValue)
            .error("\(event, privacy: .public) \(ns.domain, privacy: .public):\(ns.code, privacy: .public)")
    }

    private static var reportsDirectory: URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    /// Erzeugt die Datei zum Teilen. Läuft abseits des Main-Threads (OSLogStore kann dauern).
    static func makeReport(appVersion: String, build: String) async -> URL? {
        await Task.detached(priority: .utility) { () -> URL? in
            var lines: [String] = []
            lines.append("PhotoMaid \(appVersion) (\(build))")
            lines.append("iOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
            lines.append("Erstellt: \(ISO8601DateFormatter().string(from: Date()))")
            lines.append("")
            lines.append("== Protokoll (dieser Start, letzte 24 h) ==")
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let since = store.position(date: Date().addingTimeInterval(-24 * 3600))
                let entries = try store.getEntries(at: since)
                    .compactMap { $0 as? OSLogEntryLog }
                    .filter { $0.subsystem == subsystem }
                for e in entries.suffix(2000) {
                    lines.append("\(ISO8601DateFormatter().string(from: e.date)) [\(e.category)] \(e.composedMessage)")
                }
            } catch {
                lines.append("(Protokoll nicht lesbar)")
            }
            lines.append("")
            lines.append("== MetricKit ==")
            if let dir = reportsDirectory,
               let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).suffix(10) {
                    if let s = try? String(contentsOf: f, encoding: .utf8) { lines.append(s) }
                }
            }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoMaid-Diagnose.txt")
            do {
                try lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
                return out
            } catch {
                return nil
            }
        }.value
    }

    /// MetricKit-Berichte lokal ablegen (höchstens 10 Dateien).
    static func store(_ json: Data, name: String) {
        guard let dir = reportsDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(name)-\(Int(Date().timeIntervalSince1970)).json")
        try? json.write(to: file, options: .atomic)
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil), files.count > 10 {
            for old in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(files.count - 10) {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }
}

/// Empfängt MetricKit-Berichte (Abstürze, Hänger, Energie). Apple liefert sie höchstens täglich, lokal.
final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricsSubscriber()

    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads { Diagnostics.store(p.jsonRepresentation(), name: "diagnostic") }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads { Diagnostics.store(p.jsonRepresentation(), name: "metric") }
    }
}
