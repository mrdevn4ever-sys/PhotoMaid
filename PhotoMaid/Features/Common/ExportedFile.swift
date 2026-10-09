import SwiftUI
import UniformTypeIdentifiers

/// Datei für `fileExporter`: der Nutzer wählt selbst den Ort in „Dateien“ (iCloud Drive, „Auf meinem iPhone“, USB …).
/// Verweist nur auf die Datei im Zwischenspeicher (kein Einlesen in den Speicher).
struct ExportedFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let url: URL

    init(url: URL) { self.url = url }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: [])
    }
}
