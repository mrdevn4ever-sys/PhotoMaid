import Foundation

/// Prüfsumme einer vollständigen PhotoKit-Ressource; Dateinamen und Kennungen sind kein Inhaltsmerkmal.
public struct DuplicateResourceDigest: Sendable, Equatable {
    public let role: Int
    public let bytes: Int64
    public let partial: String
    public let full: String

    public init(role: Int, bytes: Int64, partial: String, full: String) {
        self.role = role; self.bytes = bytes; self.partial = partial; self.full = full
    }
}

public enum DuplicateResourceSet {
    /// Einzelressourcen bleiben mit Dateien vergleichbar. Mehrteilige Medien erhalten einen getrennten Namensraum.
    /// Reihenfolge ist irrelevant, Rolle, Länge und jede einzelne Ressource sind dagegen Bestandteil der Signatur.
    public static func hash(_ resources: [DuplicateResourceDigest], partial: Bool) -> String? {
        guard !resources.isEmpty else { return nil }
        if resources.count == 1 { return partial ? resources[0].partial : resources[0].full }
        let rows = resources.map { part in
            "\(part.role):\(part.bytes):\(partial ? part.partial : part.full)"
        }.sorted()
        var sha = CoreSHA256()
        sha.update(data: Data(("PhotoMaid.resource-set.v1\n\(rows.count)\n" + rows.joined(separator: "\n")).utf8))
        return "resources-v1:" + sha.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
