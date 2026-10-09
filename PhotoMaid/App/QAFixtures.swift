#if QA_FIXTURES
import Foundation
import PhotoMaidCore

/// Deterministische QA-Umgebung für UI-Tests und Screenshots.
///
/// Existiert ausschließlich in Builds mit `QA_FIXTURES` (Debug) und wird nur mit dem
/// Startargument `-qa-fixtures` aktiv. Release-Builds enthalten diesen Code nicht.
/// Legt synthetische Dateien im App-eigenen Container an (keine persönlichen Daten,
/// keine Downloads) und verbindet sie als Downloads-Quelle.
@MainActor
enum QAFixtures {
    static var proEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-qa-pro") }

    static func install(into app: AppModel) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("QA-Downloads", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let now = Date()
        let day: TimeInterval = 86_400
        // Name, logische Größe (Bytes), Alter in Tagen. Große Dateien sind sparse (kein echter Platzbedarf).
        let files: [(String, Int64, Double)] = [
            ("Reiseplan.pdf", 2_400_000, 0.1),
            ("Strandfotos.zip", 1_200_000_000, 0.2),
            ("Hotelbuchung.pdf", 1_800_000, 12),
            ("Karten-Offline.zip", 456_000_000, 20),
            ("Praesentation-Final.pptx", 12_000_000, 90),
            ("Notizen.txt", 4_096, 120),
            ("Urlaubsvideo.mov", 742_000_000, 150),
        ]
        for (name, size, age) in files {
            let url = dir.appendingPathComponent(name)
            fm.createFile(atPath: url.path, contents: header(for: name))
            if let h = try? FileHandle(forWritingTo: url) { try? h.truncate(atOffset: UInt64(size)); try? h.close() }
            let date = now.addingTimeInterval(-age * day)
            try? fm.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
        }
        // Exakte Duplikate: gleiche Bytes, verschiedene Namen.
        var bytes = Data(count: 2_000_000)
        for i in 0..<bytes.count { bytes[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
        for (name, age) in [("Kopie-A.jpg", 3.0), ("Kopie-B.jpg", 4.0), ("Kopie-C.jpg", 5.0)] {
            let url = dir.appendingPathComponent(name)
            try? bytes.write(to: url)
            let date = now.addingTimeInterval(-age * day)
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        try? app.sources.add(folderURL: dir, asDownloads: true)

        Task { await app.files.scan(app.sources) }
        // Eigene Sammlung als Beispiel (Pro-Ansicht), keine Medien-IDs.
        app.setCustomCollections([SmartCollection(source: .videos, filter: .largerThan(bytes: 500 * SmartCollections.mb))])
        if proEnabled { app.purchases.qaOverride(.purchased) }
    }

    private static func header(for name: String) -> Data {
        if name.hasSuffix(".pdf") { return Data("%PDF-1.4\n%QA\n".utf8) }
        if name.hasSuffix(".zip") { return Data([0x50, 0x4B, 0x03, 0x04]) }
        return Data("PHOTOMAID QA \(name)\n".utf8)
    }
}
#endif
