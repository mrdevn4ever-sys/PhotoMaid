import Foundation

// Auslagern: Fotos und Videos auf einen anderen Speicher kopieren, jede Kopie danach neu lesen und mit dem Original
// vergleichen. Erst dann gilt sie als „geprüft“. Nichts hier löscht ein Original.
// Grenzen, die die App ehrlich sagt:
// - Eine zweite Kopie auf demselben Gerätespeicher ist kein Auslagern (`.sameDevice`).
// - iCloud Drive / Speicherorte anderer Apps können online sein – nie automatisch „lokal“ (`.provider`).
// - „Geprüft“ heißt: die Bytes am Ziel stimmen jetzt überein. Keine Garantie für die Haltbarkeit des Datenträgers.

/// Wo der gewählte Zielordner liegt.
public enum TargetKind: String, Hashable, Codable, Sendable {
    /// Gerätespeicher dieses iPhones („Auf meinem iPhone“, auch Ordner, die eine App online abgleicht).
    case sameDevice = "SAME_DEVICE"
    /// Eigener Datenträger (USB-Stick, SSD, SD-Karten-Leser).
    case removable = "REMOVABLE"
    /// iCloud Drive oder ein Speicherort, den das System nicht als lokal ausweist.
    case provider = "PROVIDER"

    /// Nur bei einem eigenen Datenträger bietet PhotoMaid an, die geprüften Originale danach in den Papierkorb zu legen.
    public var allowsCleanupOffer: Bool { self == .removable }
}

/// Fakten aus `URLResourceValues` des Zielordners (in der App gelesen, hier eingeordnet).
public struct VolumeFacts: Hashable, Sendable {
    public var isUbiquitous: Bool?
    public var volumeIsInternal: Bool?
    public var volumeIsRemovable: Bool?
    public var volumeIsEjectable: Bool?
    public var volumeIsLocal: Bool?

    public init(isUbiquitous: Bool? = nil, volumeIsInternal: Bool? = nil, volumeIsRemovable: Bool? = nil,
                volumeIsEjectable: Bool? = nil, volumeIsLocal: Bool? = nil) {
        self.isUbiquitous = isUbiquitous
        self.volumeIsInternal = volumeIsInternal
        self.volumeIsRemovable = volumeIsRemovable
        self.volumeIsEjectable = volumeIsEjectable
        self.volumeIsLocal = volumeIsLocal
    }
}

public enum ArchiveTargets {
    /// Einordnung nur aus belegten Systemangaben. Unklar → `.provider` (nie „lokal“ raten).
    public static func classify(_ f: VolumeFacts) -> TargetKind {
        if f.isUbiquitous == true || f.volumeIsLocal == false { return .provider }
        if f.volumeIsRemovable == true || f.volumeIsEjectable == true || f.volumeIsInternal == false { return .removable }
        if f.volumeIsInternal == true { return .sameDevice }
        return .provider
    }
}

/// Ein zu kopierendes Medium (nur, was für Namen, Ordner und Prüfung nötig ist).
public struct ArchiveSource: Hashable, Sendable {
    public let id: String
    public let name: String?
    public let uti: String?
    /// Gemessene Größe; `nil` = unbekannt (nie 0).
    public let size: Int64?
    public let takenMillis: Int64?

    public init(id: String, name: String?, uti: String?, size: Int64?, takenMillis: Int64?) {
        self.id = id
        self.name = name
        self.uti = uti
        self.size = size
        self.takenMillis = takenMillis
    }
}

public struct ArchiveOptions: Hashable, Codable, Sendable {
    /// Unterordner nach Jahr und Monat der Aufnahme („2026/10“).
    public var byMonth = true
    /// Prüfliste (CSV) mit Name, Datum, Größe, Prüfsumme und eigenen Infos in den Zielordner legen.
    public var writeList = true
    public init(byMonth: Bool = true, writeList: Bool = true) { self.byMonth = byMonth; self.writeList = writeList }
}

public enum ArchivePlan {
    static let maxName = 120

    /// Unterordner für ein Medium. Ohne bekanntes Aufnahmedatum: ein eigener Ordner – nie ein erfundenes Datum.
    /// Immer ASCII-Ziffern: Ordnernamen hängen nie von der Gerätesprache ab.
    public static func folder(for s: ArchiveSource, options: ArchiveOptions, undatedLabel: String,
                              timeZone: TimeZone) -> [String] {
        guard options.byMonth else { return [] }
        guard let t = s.takenMillis else { return [safeName(undatedLabel, fallback: "_")] }
        let d = LocalDay(Date(timeIntervalSince1970: Double(t) / 1000), timeZone: timeZone)
        return [pad(d.year, 4), pad(d.month, 2)]
    }

    static func pad(_ v: Int, _ n: Int) -> String {
        let s = String(v)
        return String(repeating: "0", count: max(0, n - s.count)) + s
    }

    /// Dateiname ohne Zeichen, die Speicher wie FAT/exFAT ablehnen; nie leer.
    public static func safeName(_ raw: String?, fallback: String) -> String {
        let bad = Set("\\/:*?\"<>|")
        var cleaned = String((raw ?? "").unicodeScalars.map { u -> Character in
            (u.value < 0x20 || u.value == 0x7F || bad.contains(Character(u))) ? "_" : Character(u)
        })
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        while cleaned.hasSuffix(".") { cleaned.removeLast() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        let name = cleaned.isEmpty ? fallback : cleaned
        if name.count <= maxName { return name }
        let ext = fileExtension(name)
        return String(name.dropLast(ext.count).prefix(maxName - ext.count)) + ext
    }

    /// „.jpg“ inklusive Punkt, sonst leer.
    public static func fileExtension(_ name: String) -> String {
        guard let i = name.lastIndex(of: "."), i > name.startIndex else { return "" }
        let ext = String(name[i...])
        return ext.count <= 7 ? ext : ""
    }

    /// Fallback-Name, wenn das Medium keinen hat: „PhotoMaid_0007.jpg“ (Endung aus dem Dateityp).
    public static func fallbackName(index: Int, uti: String?) -> String {
        "PhotoMaid_" + pad(index + 1, 4) + extensionFor(uti: uti)
    }

    public static func extensionFor(uti: String?) -> String {
        switch uti?.lowercased() {
        case "public.jpeg": ".jpg"
        case "public.png": ".png"
        case "public.heic": ".heic"
        case "public.heif": ".heif"
        case "org.webmproject.webp": ".webp"
        case "com.compuserve.gif": ".gif"
        case "com.adobe.raw-image", "com.adobe.dng": ".dng"
        case "public.mpeg-4": ".mp4"
        case "com.apple.quicktime-movie": ".mov"
        default: ""
        }
    }

    /// „IMG.jpg“ → „IMG (2).jpg“, solange der Name im Ordner vergeben ist (ohne Groß/klein).
    public static func uniqueName(taken: Set<String>, wanted: String) -> String {
        let lower = Set(taken.map { $0.lowercased() })
        if !lower.contains(wanted.lowercased()) { return wanted }
        let ext = fileExtension(wanted)
        let base = String(wanted.dropLast(ext.count))
        var i = 2
        while lower.contains("\(base) (\(i))\(ext)".lowercased()) { i += 1 }
        return "\(base) (\(i))\(ext)"
    }
}

/// Freier Platz am Ziel: nur gemessene Zahlen. Unbekannte Größen oder unbekannter Platz → `.unknown`, nie „passt“.
public enum SpaceCheck: Hashable, Sendable { case enough, notEnough, unknown }

public enum ArchiveSpace {
    public static func check(sizes: [Int64?], availableBytes: Int64?) -> SpaceCheck {
        let known = sizes.compactMap { $0 }.reduce(0, +)
        guard let availableBytes else { return .unknown }
        if known > availableBytes { return .notEnough }
        return sizes.contains { $0 == nil } ? .unknown : .enough
    }
}

/// Zustand einer Datei im Journal. Nur `.verified` und `.alreadyThere` zählen als geprüfte Kopie.
public enum EntryState: String, Hashable, Codable, Sendable {
    case pending = "PENDING", copying = "COPYING", verified = "VERIFIED", alreadyThere = "ALREADY_THERE",
         failed = "FAILED", notDone = "NOT_DONE"
}

public enum EntryReason: String, Hashable, Codable, Sendable {
    /// Original nicht lesbar (gelöscht, nicht mehr freigegeben, nur in iCloud).
    case readFailed = "READ_FAILED"
    /// Ziel hat das Schreiben abgelehnt (voll, schreibgeschützt, entfernt).
    case writeFailed = "WRITE_FAILED"
    /// Die neu gelesene Kopie weicht vom Original ab – sie wurde wieder entfernt.
    case mismatch = "MISMATCH"
    case cancelled = "CANCELLED"
    /// App wurde unterbrochen; eine halbe Kopie wurde entfernt.
    case interrupted = "INTERRUPTED"
    case noSpace = "NO_SPACE"
}

public struct JournalEntry: Hashable, Codable, Sendable {
    public let sourceId: String
    /// Name am Ziel (nach Bereinigung und Konfliktauflösung).
    public var name: String
    public var folder: [String] = []
    /// Gemessene Größe des Originals (`nil` = unbekannt).
    public var size: Int64?
    public var state = EntryState.pending
    public var reason: EntryReason?
    /// Ziel-Datei relativ zum Zielordner (für das Entfernen einer halben Kopie nach Unterbrechung).
    public var targetUri: String?
    /// Gemessene Bytes der geprüften Kopie.
    public var bytes: Int64?
    /// SHA-256 (hex) von Original und geprüfter Kopie.
    public var sha256: String?

    public init(sourceId: String, name: String, folder: [String] = [], size: Int64? = nil) {
        self.sourceId = sourceId
        self.name = name
        self.folder = folder
        self.size = size
    }

    public var isVerified: Bool { state == .verified || state == .alreadyThere }
}

public struct ArchiveJournal: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    /// Anzeigename des Ziels („USB-Stick › Archiv“).
    public var targetLabel: String
    public var targetKind: TargetKind
    public var startedAt: Int64
    public var finishedAt: Int64?
    public var options = ArchiveOptions()
    public var entries: [JournalEntry] = []
    /// Prüfliste geschrieben (Name am Ziel), sonst `nil`.
    public var listName: String?

    public init(id: String, targetLabel: String, targetKind: TargetKind, startedAt: Int64,
                options: ArchiveOptions = ArchiveOptions(), entries: [JournalEntry] = []) {
        self.id = id
        self.targetLabel = targetLabel
        self.targetKind = targetKind
        self.startedAt = startedAt
        self.options = options
        self.entries = entries
    }

    public var finished: Bool { finishedAt != nil }
    public var verified: [JournalEntry] { entries.filter(\.isVerified) }
    public var summary: ArchiveSummary { ArchiveSummary.of(entries) }

    public func update(_ sourceId: String, _ change: (inout JournalEntry) -> Void) -> ArchiveJournal {
        var j = self
        for i in j.entries.indices where j.entries[i].sourceId == sourceId { change(&j.entries[i]) }
        return j
    }
}

/// Zahlen für die Ergebnisseite – nur gemessene Bytes geprüfter Kopien.
public struct ArchiveSummary: Hashable, Sendable {
    public let total: Int
    public let verified: Int
    public let alreadyThere: Int
    public let failed: Int
    public let notDone: Int
    public let verifiedBytes: Int64

    public static func of(_ entries: [JournalEntry]) -> ArchiveSummary {
        ArchiveSummary(total: entries.count,
                       verified: entries.filter { $0.state == .verified }.count,
                       alreadyThere: entries.filter { $0.state == .alreadyThere }.count,
                       failed: entries.filter { $0.state == .failed }.count,
                       notDone: entries.filter { [.notDone, .pending, .copying].contains($0.state) }.count,
                       verifiedBytes: entries.filter(\.isVerified).reduce(0) { $0 + ($1.bytes ?? 0) })
    }
}

public enum ArchiveJournalRules {
    /// Nach einem Abbruch oder Prozessende: Was nicht geprüft ist, gilt nicht. Eine begonnene Kopie wird beendet – ihre
    /// (halbe) Zieldatei muss entfernt werden; Offenes wird `.notDone`. Liefert Journal und zu entfernende Ziel-Dateien.
    public static func close(_ j: ArchiveJournal, reason: EntryReason, now: Int64) -> (ArchiveJournal, [String]) {
        var remove: [String] = []
        var out = j
        out.entries = j.entries.map { e in
            var n = e
            switch e.state {
            case .copying:
                if let t = e.targetUri { remove.append(t) }
                n.state = .notDone; n.reason = reason; n.targetUri = nil
            case .pending:
                n.state = .notDone; n.reason = reason
            default: break
            }
            return n
        }
        out.finishedAt = j.finishedAt ?? now
        return (out, remove)
    }
}

public extension Sequence where Element == UInt8 {
    /// Hex-Darstellung einer Prüfsumme (ASCII, Kleinbuchstaben).
    var hexString: String {
        let digits = Array("0123456789abcdef")
        var s = ""
        for b in self { s.append(digits[Int(b >> 4)]); s.append(digits[Int(b & 0x0F)]) }
        return s
    }
}

/// Prüfliste als CSV (RFC 4180, UTF-8 mit BOM). Zellen, die mit = + - @ beginnen, bekommen ein vorangestelltes Apostroph,
/// damit ein Tabellenprogramm sie nie als Formel ausführt.
public enum ArchiveList {
    public struct Row: Hashable, Sendable {
        public let folder, name, taken, bytes, sha256, albums, tags, note: String
        public init(folder: String, name: String, taken: String, bytes: String, sha256: String, albums: String,
                    tags: String, note: String) {
            self.folder = folder; self.name = name; self.taken = taken; self.bytes = bytes; self.sha256 = sha256
            self.albums = albums; self.tags = tags; self.note = note
        }
    }

    public static func render(header: [String], rows: [Row]) -> String {
        var s = "\u{FEFF}"
        s += header.map(cell).joined(separator: ",") + "\r\n"
        for r in rows {
            s += [r.folder, r.name, r.taken, r.bytes, r.sha256, r.albums, r.tags, r.note].map(cell).joined(separator: ",") + "\r\n"
        }
        return s
    }

    public static func cell(_ raw: String) -> String {
        let v = raw.first.map { "=+-@\t\r".contains($0) } == true ? "'" + raw : raw
        return v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }
}
