import Foundation

// Privater Tresor (E16): plattformneutrale Regeln. Verschlüsselung, Schlüsselbund und PhotoKit liegen in der App.
// Medien im Tresor gibt es für die übrige App nicht: kein Prüfstand, keine Entscheidung, keine Statistik.

/// Art eines Mediums im Tresor.
public enum VaultMediaKind: String, Codable, Sendable, Hashable {
    case photo, video, livePhoto
}

/// Rolle einer gesicherten Datei (entspricht `PHAssetResourceType`, plattformneutral benannt).
public enum VaultResourceRole: String, Codable, Sendable, Hashable, CaseIterable {
    case photo, video, pairedVideo, fullSizePhoto, fullSizeVideo, fullSizePairedVideo, alternatePhoto, adjustmentData
}

/// Eine verschlüsselt gespeicherte Datei eines Mediums. `file` ist ein Zufallsname ohne Bezug zum Original.
public struct VaultResource: Codable, Sendable, Hashable {
    public let role: VaultResourceRole
    public let file: String
    public let uti: String
    public let originalFilename: String
    /// Gemessene Größe des Klartexts in Bytes.
    public let size: Int64
    /// SHA-256 des Klartexts (beim Ablegen gegen die Quelle geprüft).
    public let sha256: String

    public init(role: VaultResourceRole, file: String, uti: String, originalFilename: String, size: Int64, sha256: String) {
        self.role = role
        self.file = file
        self.uti = uti
        self.originalFilename = originalFilename
        self.size = size
        self.sha256 = sha256
    }
}

public struct VaultItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var kind: VaultMediaKind
    public var folderID: String?
    public var resources: [VaultResource]
    public var creationMs: Int64?
    public var addedMs: Int64
    public var latitude: Double?
    public var longitude: Double?
    public var isFavorite: Bool
    public var duration: Double
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Verschlüsseltes Vorschaubild (Zufallsname), falls erzeugt.
    public var thumbnail: String?
    /// Kennung in der Fotos-App, solange iOS das Löschen dort noch nicht bestätigt hat; danach `nil`.
    public var sourceID: String?
    /// Ursprüngliche Kennung in der Fotos-App – bleibt dauerhaft (nur im verschlüsselten Index), damit das Medium in
    /// PhotoMaid verborgen bleibt, auch wenn es in der Fotos-App noch liegt oder aus „Zuletzt gelöscht“ zurückkommt.
    /// Einträge aus Build 3/4 haben sie nur, solange `sourceID` gesetzt war (siehe `migrateOriginalIDs`).
    public var originalID: String?

    public init(id: String, kind: VaultMediaKind, folderID: String? = nil, resources: [VaultResource], creationMs: Int64?,
                addedMs: Int64, latitude: Double? = nil, longitude: Double? = nil, isFavorite: Bool = false,
                duration: Double = 0, pixelWidth: Int = 0, pixelHeight: Int = 0, thumbnail: String? = nil,
                sourceID: String? = nil, originalID: String? = nil) {
        self.id = id
        self.kind = kind
        self.folderID = folderID
        self.resources = resources
        self.creationMs = creationMs
        self.addedMs = addedMs
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.thumbnail = thumbnail
        self.sourceID = sourceID
        self.originalID = originalID ?? sourceID
    }

    /// Summe der gemessenen Dateigrößen.
    public var size: Int64 { resources.reduce(0) { $0 + $1.size } }
    public var isVideo: Bool { kind == .video }
    /// Die sichtbare Fassung (Bearbeitung vor Original).
    public var current: VaultResource? { VaultRestorePlan.current(resources) }
    public var displayName: String { current?.originalFilename ?? resources.first?.originalFilename ?? "" }
}

public struct VaultFolder: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public let createdMs: Int64

    public init(id: String, name: String, createdMs: Int64) {
        self.id = id
        self.name = name
        self.createdMs = createdMs
    }
}

/// Inhaltsverzeichnis des Tresors (wird als Ganzes verschlüsselt gespeichert).
public struct VaultIndex: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public var version = VaultIndex.currentVersion
    public var folders: [VaultFolder] = []
    public var items: [VaultItem] = []

    public init(folders: [VaultFolder] = [], items: [VaultItem] = []) {
        self.folders = folders
        self.items = items
    }

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    public func items(inFolder folderID: String?) -> [VaultItem] {
        guard let folderID else { return items }
        return items.filter { $0.folderID == folderID }
    }

    public func count(inFolder folderID: String) -> Int { items.filter { $0.folderID == folderID }.count }

    public mutating func add(_ item: VaultItem) {
        items.removeAll { $0.id == item.id }
        items.append(item)
    }

    /// Entfernt Einträge und liefert sie zurück (die App löscht danach die Dateien).
    @discardableResult
    public mutating func remove(ids: Set<String>) -> [VaultItem] {
        let removed = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        return removed
    }

    /// Verschieben in einen Ordner (`nil` = ohne Ordner). Unbekannte Ordner werden ignoriert.
    public mutating func move(ids: Set<String>, to folderID: String?) {
        if let folderID, !folders.contains(where: { $0.id == folderID }) { return }
        for i in items.indices where ids.contains(items[i].id) { items[i].folderID = folderID }
    }

    /// Neuer Ordner; leere oder doppelte Namen (ohne Groß/Klein) werden abgelehnt.
    @discardableResult
    public mutating func createFolder(name: String, id: String, nowMs: Int64) -> VaultFolder? {
        guard let clean = VaultIndex.cleanName(name), !hasFolder(named: clean, except: nil) else { return nil }
        let folder = VaultFolder(id: id, name: clean, createdMs: nowMs)
        folders.append(folder)
        return folder
    }

    @discardableResult
    public mutating func renameFolder(_ id: String, to name: String) -> Bool {
        guard let clean = VaultIndex.cleanName(name), let i = folders.firstIndex(where: { $0.id == id }),
              !hasFolder(named: clean, except: id) else { return false }
        folders[i].name = clean
        return true
    }

    /// Ordner löschen: die Medien bleiben im Tresor (ohne Ordner).
    public mutating func deleteFolder(_ id: String) {
        folders.removeAll { $0.id == id }
        for i in items.indices where items[i].folderID == id { items[i].folderID = nil }
    }

    public mutating func markRemovedFromLibrary(sourceIDs: Set<String>) {
        for i in items.indices where items[i].sourceID.map(sourceIDs.contains) == true { items[i].sourceID = nil }
    }

    /// Noch zusätzlich in der Fotos-App (iOS-Löschabfrage abgelehnt).
    public var stillInLibrary: [String] { items.compactMap(\.sourceID) }

    /// Alle bekannten Kennungen der Originale in der Fotos-App (für die Verbergen-Liste).
    public var originalIDs: Set<String> { Set(items.compactMap { $0.originalID ?? $0.sourceID }) }

    /// Einträge älterer Fassungen: ursprüngliche Kennung aus `sourceID` übernehmen, solange sie noch bekannt ist.
    /// Fehlt beides, wird nichts geraten (keine unsichere Zuordnung zu fremden Medien).
    @discardableResult
    public mutating func migrateOriginalIDs() -> Bool {
        var changed = false
        for i in items.indices where items[i].originalID == nil {
            if let source = items[i].sourceID {
                items[i].originalID = source
                changed = true
            }
        }
        return changed
    }

    private func hasFolder(named name: String, except id: String?) -> Bool {
        folders.contains { $0.id != id && $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    static func cleanName(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return String(t.prefix(60))
    }
}

public enum VaultSort: String, Codable, Sendable, CaseIterable {
    /// Aufnahmedatum, neueste zuerst; ohne Datum am Ende.
    case captured
    /// Abgelegt am, neueste zuerst.
    case added
    /// Dateiname A–Z (Zahlen natürlich sortiert).
    case name
    /// Größe, größte zuerst.
    case size

    public func sorted(_ items: [VaultItem]) -> [VaultItem] {
        items.sorted { a, b in
            switch self {
            case .captured:
                switch (a.creationMs, b.creationMs) {
                case let (x?, y?) where x != y: return x > y
                case (.some, nil): return true
                case (nil, .some): return false
                default: break
                }
            case .added:
                if a.addedMs != b.addedMs { return a.addedMs > b.addedMs }
            case .name:
                let r = a.displayName.compare(b.displayName, options: [.caseInsensitive, .numeric])
                if r != .orderedSame { return r == .orderedAscending }
            case .size:
                if a.size != b.size { return a.size > b.size }
            }
            return a.id < b.id
        }
    }
}

/// Free: höchstens 50 Medien im Tresor. Pro: unbegrenzt (Entscheidung des Inhabers, E16).
public enum VaultPolicy {
    public static let freeItemLimit = 50

    /// Freie Plätze; `nil` = unbegrenzt.
    public static func remaining(existing: Int, unlimited: Bool) -> Int? {
        unlimited ? nil : max(0, freeItemLimit - existing)
    }

    /// Wie viele der gewünschten Medien abgelegt werden dürfen.
    public static func allowed(requested: Int, existing: Int, unlimited: Bool) -> Int {
        guard let left = remaining(existing: existing, unlimited: unlimited) else { return max(0, requested) }
        return min(max(0, requested), left)
    }
}

public enum VaultCodeKind: String, Codable, Sendable, CaseIterable {
    /// Sechs Ziffern.
    case pin
    /// Freies Passwort, mindestens sechs Zeichen.
    case password
}

public enum VaultCodeRules {
    public static let pinLength = 6
    public static let minPasswordLength = 6

    public enum Problem: Equatable, Sendable {
        case tooShort, notDigits, mismatch
    }

    public static func validate(_ code: String, kind: VaultCodeKind, confirmation: String) -> Problem? {
        switch kind {
        case .pin:
            guard code.count == pinLength else { return .tooShort }
            guard code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return .notDigits }
        case .password:
            guard code.count >= minPasswordLength else { return .tooShort }
        }
        return code == confirmation ? nil : .mismatch
    }
}

/// Fehlversuche: die ersten fünf ohne Wartezeit, danach wachsend. Der Tresor wird nie gelöscht (E16).
public struct VaultLockout: Codable, Sendable, Equatable {
    public static let freeAttempts = 5
    public var failures = 0
    public var lockedUntilMs: Int64?

    public init(failures: Int = 0, lockedUntilMs: Int64? = nil) {
        self.failures = failures
        self.lockedUntilMs = lockedUntilMs
    }

    /// Wartezeit nach dem n-ten Fehlversuch in Sekunden.
    public static func penaltySeconds(failures: Int) -> Int64 {
        switch failures {
        case ..<freeAttempts: 0
        case freeAttempts: 60
        case freeAttempts + 1: 5 * 60
        case freeAttempts + 2: 15 * 60
        default: 60 * 60
        }
    }

    public mutating func registerFailure(nowMs: Int64) {
        failures += 1
        let wait = VaultLockout.penaltySeconds(failures: failures)
        lockedUntilMs = wait > 0 ? nowMs + wait * 1000 : nil
    }

    public mutating func registerSuccess() {
        failures = 0
        lockedUntilMs = nil
    }

    /// Verbleibende Sperrzeit in ganzen Sekunden (aufgerundet), 0 = frei.
    public func remainingSeconds(nowMs: Int64) -> Int64 {
        guard let until = lockedUntilMs, until > nowMs else { return 0 }
        return (until - nowMs + 999) / 1000
    }
}

/// Notfallschlüssel: 16 Zufallsbytes als 26 Zeichen Crockford-Base32 in Vierergruppen (ohne I, L, O, U).
public enum VaultRecoveryKey {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    public static let byteCount = 16
    public static let length = 26

    public static func format(_ bytes: [UInt8]) -> String {
        precondition(bytes.count == byteCount)
        var bits = 0
        var value = 0
        var chars: [Character] = []
        for b in bytes {
            value = (value << 8) | Int(b)
            bits += 8
            while bits >= 5 {
                chars.append(alphabet[(value >> (bits - 5)) & 31])
                bits -= 5
            }
            value &= (1 << bits) - 1
        }
        if bits > 0 { chars.append(alphabet[(value << (5 - bits)) & 31]) }
        return stride(from: 0, to: chars.count, by: 4).map { String(chars[$0..<min($0 + 4, chars.count)]) }
            .joined(separator: "-")
    }

    /// Eingabe vereinheitlichen (Leerzeichen/Striche weg, Großbuchstaben, O→0, I/L→1). `nil` bei falscher Form.
    public static func normalize(_ input: String) -> String? {
        var out = ""
        for c in input.uppercased() {
            switch c {
            case " ", "-", "\n", "\t": continue
            case "O": out.append("0")
            case "I", "L": out.append("1")
            default:
                guard alphabet.contains(c) else { return nil }
                out.append(c)
            }
        }
        return out.count == length ? out : nil
    }
}

/// Mit einem Geheimnis (Code oder Notfallschlüssel) verschlüsselter Hauptschlüssel.
public struct VaultWrappedKey: Codable, Sendable, Equatable {
    public var salt: Data
    public var rounds: UInt32
    /// AES-GCM (Nonce + Geheimtext + Prüfwert).
    public var box: Data

    public init(salt: Data, rounds: UInt32, box: Data) {
        self.salt = salt
        self.rounds = rounds
        self.box = box
    }
}

/// Unverschlüsselte Einstellungen des Tresors (verraten nichts über den Inhalt).
public struct VaultSettings: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public var version = VaultSettings.currentVersion
    public var codeKind: VaultCodeKind
    public var hideEntry: Bool
    public var biometrics: Bool
    public var lockout = VaultLockout()
    /// Mit dem Notfallschlüssel verschlüsselter Hauptschlüssel (hohe Entropie, darf in der Datei liegen).
    public var recovery: VaultWrappedKey?
    public var sort = VaultSort.captured
    public let createdMs: Int64

    public init(codeKind: VaultCodeKind, hideEntry: Bool, biometrics: Bool, recovery: VaultWrappedKey?, createdMs: Int64) {
        self.codeKind = codeKind
        self.hideEntry = hideEntry
        self.biometrics = biometrics
        self.recovery = recovery
        self.createdMs = createdMs
    }
}

/// Dateiformat einer verschlüsselten Datei: Kopf (Kennung, Version, Blockgröße, Salz) und Blöcke aus
/// AES-GCM (12 Byte Nonce + Geheimtext + 16 Byte Prüfwert). Blocknummer und „letzter Block“ sind zusätzliche
/// authentifizierte Daten: Vertauschen, Weglassen und Abschneiden fallen beim Entschlüsseln auf.
public enum VaultChunkLayout {
    public static let magic: [UInt8] = Array("PMV1".utf8)
    public static let version: UInt8 = 1
    public static let saltLength = 16
    public static let headerLength = 4 + 1 + 4 + saltLength
    /// Nonce + Prüfwert je Block.
    public static let overhead = 12 + 16
    public static let defaultChunkSize = 1 << 20

    public struct Chunk: Equatable, Sendable {
        public let index: UInt64
        public let offset: Int64
        public let length: Int
        public let isLast: Bool
    }

    public static func header(chunkSize: Int, salt: [UInt8]) -> [UInt8] {
        precondition(salt.count == saltLength && chunkSize > 0)
        let size = UInt32(chunkSize)
        return magic + [version, UInt8(size >> 24), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)] + salt
    }

    public static func parseHeader(_ bytes: [UInt8]) -> (chunkSize: Int, salt: [UInt8])? {
        guard bytes.count >= headerLength, Array(bytes[0..<4]) == magic, bytes[4] == version else { return nil }
        let size = Int(bytes[5]) << 24 | Int(bytes[6]) << 16 | Int(bytes[7]) << 8 | Int(bytes[8])
        guard size > 0, size <= 64 << 20 else { return nil }
        return (size, Array(bytes[9..<headerLength]))
    }

    /// Blöcke einer Datei der Länge `fileLength`. Der Schreiber gibt Volle Blöcke nur aus, wenn danach noch Daten
    /// folgen; der letzte Block ist daher 0…chunkSize Bytes groß (0 nur bei leerer Datei). `nil` = beschädigt.
    public static func chunks(fileLength: Int64, chunkSize: Int) -> [Chunk]? {
        let body = fileLength - Int64(headerLength)
        let full = Int64(chunkSize + overhead)
        guard body >= Int64(overhead) else { return nil }
        let count = (body + full - 1) / full
        let lastLength = body - (count - 1) * full
        guard lastLength >= Int64(overhead) else { return nil }
        if count > 1 && lastLength == Int64(overhead) { return nil }
        var out: [Chunk] = []
        out.reserveCapacity(Int(count))
        for i in 0..<count {
            let isLast = i == count - 1
            out.append(Chunk(index: UInt64(i), offset: Int64(headerLength) + i * full,
                             length: Int(isLast ? lastLength : full), isLast: isLast))
        }
        return out
    }

    public static func plaintextLength(fileLength: Int64, chunkSize: Int) -> Int64? {
        guard let list = chunks(fileLength: fileLength, chunkSize: chunkSize) else { return nil }
        return list.reduce(0) { $0 + Int64($1.length - overhead) }
    }

    /// Geschätzte Dateilänge für `plaintext` Bytes (für Tests und Platzprüfung).
    public static func fileLength(plaintext: Int64, chunkSize: Int) -> Int64 {
        let count = max(1, (plaintext + Int64(chunkSize) - 1) / Int64(chunkSize))
        return Int64(headerLength) + plaintext + count * Int64(overhead)
    }

    public static func aad(index: UInt64, isLast: Bool) -> [UInt8] {
        (0..<8).map { UInt8((index >> (56 - 8 * UInt64($0))) & 0xFF) } + [isLast ? 1 : 0]
    }
}

/// Was beim Zurücklegen in die Fotos-App angelegt wird.
public enum VaultRestorePlan {
    /// Sichtbare Fassung: Bearbeitung vor Original.
    public static func current(_ resources: [VaultResource]) -> VaultResource? {
        resources.first { $0.role == .fullSizePhoto } ?? resources.first { $0.role == .photo }
            ?? resources.first { $0.role == .fullSizeVideo } ?? resources.first { $0.role == .video }
    }

    /// Alle Teile (Original, Bearbeitung mit Anpassungsdaten, Live-Photo-Video, RAW). Nur sinnvoll, wenn eine
    /// Bearbeitung vollständig vorliegt; sonst wie `simple`.
    public static func full(_ resources: [VaultResource]) -> [VaultResource] {
        let roles = Set(resources.map(\.role))
        let edited = roles.contains(.adjustmentData) && (roles.contains(.fullSizePhoto) || roles.contains(.fullSizeVideo))
        guard edited else { return simple(resources) }
        let order: [VaultResourceRole] = [.photo, .video, .pairedVideo, .alternatePhoto, .adjustmentData, .fullSizePhoto,
                                          .fullSizeVideo, .fullSizePairedVideo]
        return order.compactMap { r in resources.first { $0.role == r } }
    }

    /// Einfach: aktuelle Fassung als Original, dazu Live-Photo-Video (Bearbeitung vor Original) und RAW.
    public static func simple(_ resources: [VaultResource]) -> [VaultResource] {
        var out: [VaultResource] = []
        if let main = current(resources) { out.append(main) }
        if let paired = resources.first(where: { $0.role == .fullSizePairedVideo }) ?? resources.first(where: { $0.role == .pairedVideo }) {
            out.append(paired)
        }
        if let raw = resources.first(where: { $0.role == .alternatePhoto }) { out.append(raw) }
        return out
    }

    /// Rolle, unter der eine Datei im einfachen Plan angelegt wird (Bearbeitungen werden zum Original).
    public static func simpleRole(_ role: VaultResourceRole) -> VaultResourceRole {
        switch role {
        case .fullSizePhoto: .photo
        case .fullSizeVideo: .video
        case .fullSizePairedVideo: .pairedVideo
        default: role
        }
    }
}

/// Verbergen-Liste: Kennungen der Originale von Medien im Tresor – gesalzene Prüfsummen, keine Klartext-Kennungen.
/// Muss auch bei gesperrtem Tresor lesbar sein, damit PhotoMaid diese Medien nirgends zeigt (auch wenn iOS das
/// Löschen nicht bestätigt hat oder ein Original aus „Zuletzt gelöscht“ zurückkommt). Die Prüfsumme berechnet die
/// App (SHA-256 über Salz und Kennung); der Kern kennt nur die Regeln.
public struct VaultConcealmentSet: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public var version = VaultConcealmentSet.currentVersion
    public var salt: Data
    public private(set) var digests: Set<String>

    public init(salt: Data, digests: Set<String> = []) {
        self.salt = salt
        self.digests = digests
    }

    public var isEmpty: Bool { digests.isEmpty }

    public func contains(_ id: String, digest: (Data, String) -> String) -> Bool {
        !digests.isEmpty && digests.contains(digest(salt, id))
    }

    /// `true`, wenn sich etwas geändert hat.
    @discardableResult
    public mutating func insert(_ ids: some Sequence<String>, digest: (Data, String) -> String) -> Bool {
        let before = digests.count
        for id in ids where !id.isEmpty { digests.insert(digest(salt, id)) }
        return digests.count != before
    }

    @discardableResult
    public mutating func remove(_ ids: some Sequence<String>, digest: (Data, String) -> String) -> Bool {
        let before = digests.count
        for id in ids { digests.remove(digest(salt, id)) }
        return digests.count != before
    }
}

/// Von PhotoMaid erzeugte Kopien (Bearbeitungen, Collagen, Filme, GIFs), die ein Medium enthalten – auch über mehrere
/// Stufen (Kopie einer Kopie). Grundlage ist die Liste „Gespeichert“; ältere Collagen/Filme ohne gespeicherte Quellen
/// lassen sich nicht zuordnen und werden nie geraten.
public enum VaultDerivation {
    public static func parents(of record: EditRecord) -> Set<String> {
        var out = Set(record.sources ?? [])
        if !record.sourceId.isEmpty { out.insert(record.sourceId) }
        return out
    }

    /// Kennungen aller abgeleiteten Kopien von `roots` (ohne die Wurzeln selbst).
    public static func copies(of roots: Set<String>, records: [EditRecord]) -> Set<String> {
        var parents: [String: Set<String>] = [:]
        for r in records { parents[r.newId, default: []].formUnion(Self.parents(of: r)) }
        return VaultVisibilityPolicy.closure(roots: roots, parentsByOutput: parents).subtracting(roots)
    }
}
