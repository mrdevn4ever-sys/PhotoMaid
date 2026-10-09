import Foundation

// Organisieren: Schlagwörter, Notizen und der Auswahlkorb sind reine PhotoMaid-Verwaltungsdaten. Sie verändern keine
// Datei, erzeugen nie eine Aufräum-Entscheidung und beruhen ausschließlich auf Nutzereingaben.
// Alben sind auf iOS die Alben der Fotos-App (Entscheidung E5); `AlbumRules` gilt für deren Namen.

/// Wiederfinden eines Mediums: zuerst über die ID (`localIdentifier`), sonst über den Fingerabdruck aus Dateiname,
/// Größe und Aufnahmezeit.
public struct MediaRef: Hashable, Codable, Sendable {
    public let id: String
    public let name: String?
    public let size: Int64?
    public let takenMillis: Int64?

    public init(id: String, name: String?, size: Int64?, takenMillis: Int64?) {
        self.id = id
        self.name = name
        self.size = size
        self.takenMillis = takenMillis
    }

    /// Fingerabdruck nur, wenn er trägt: Name plus Größe oder Aufnahmezeit.
    public var fingerprint: String? {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !n.isEmpty else { return nil }
        guard size != nil || takenMillis != nil else { return nil }
        return "\(n)|\(size.map(String.init) ?? "?")|\(takenMillis.map(String.init) ?? "?")"
    }
}

public enum Rematch {
    /// `found`: gespeicherte ID → aktuelles Medium. `moved`: alte ID → neue ID (über den Fingerabdruck).
    /// `missing`: nicht (eindeutig) auffindbar – werden sichtbar aufgelistet, nie still verworfen.
    public struct Result<T> {
        public let found: [String: T]
        public let moved: [String: String]
        public let missing: [String]
    }

    public static func resolve<T>(stored: [MediaRef], current: [T], ref: (T) -> MediaRef) -> Result<T> {
        var byId: [String: T] = [:]
        var refs: [String: MediaRef] = [:]
        var currentOrder: [String] = []
        for c in current {
            let r = ref(c)
            if byId[r.id] == nil { currentOrder.append(r.id) }
            byId[r.id] = c
            refs[r.id] = r
        }
        var found: [String: T] = [:]
        var used: Set<String> = []
        for s in stored { if let c = byId[s.id] { found[s.id] = c; used.insert(s.id) } }
        // Fingerabdruck nur eindeutig: genau ein noch nicht vergebenes aktuelles Medium mit diesem Abdruck.
        var byPrint: [String: [String]] = [:]
        for id in currentOrder where !used.contains(id) {
            if let p = refs[id]?.fingerprint { byPrint[p, default: []].append(id) }
        }
        var wanted: [String: Int] = [:]
        for s in stored where found[s.id] == nil {
            if let p = s.fingerprint { wanted[p, default: 0] += 1 }
        }
        var moved: [String: String] = [:]
        var missing: [String] = []
        for s in stored where found[s.id] == nil {
            if let p = s.fingerprint, let candidates = byPrint[p], candidates.count == 1, wanted[p] == 1,
               !used.contains(candidates[0]) {
                let id = candidates[0]
                used.insert(id)
                found[s.id] = byId[id]
                moved[s.id] = id
            } else {
                missing.append(s.id)
            }
        }
        return Result(found: found, moved: moved, missing: missing)
    }
}

/// Eigene Schlagwörter: kurz, ohne „#“, ohne Unterschied bei Groß/klein und Akzenten.
public enum TagRules {
    public static let maxLength = 40
    public static let maxPerMedia = 30

    /// Bereinigt eine Eingabe; `nil`, wenn nichts übrig bleibt.
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") { s.removeFirst() }
        s = collapseSpaces(s.trimmingCharacters(in: .whitespacesAndNewlines))
        s = String(s.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// Vergleichsschlüssel: „Café“ = „cafe“.
    public static func key(_ tag: String) -> String { SearchText.normalize(tag) }

    /// Fügt hinzu (erste Schreibweise bleibt), höchstens `maxPerMedia`.
    public static func merge(_ existing: [String], _ added: [String]) -> [String] {
        var keys: [String] = []
        var names: [String: String] = [:]
        for t in existing + added.compactMap(normalize) {
            let k = key(t)
            if names[k] == nil { names[k] = t; keys.append(k) }
        }
        return Array(keys.prefix(maxPerMedia)).map { names[$0]! }
    }

    public static func remove(_ existing: [String], _ tag: String) -> [String] {
        existing.filter { key($0) != key(tag) }
    }

    /// Zustand eines Schlagworts für eine Auswahl.
    public enum State: Hashable, Sendable { case all, some, none }

    public static func state(_ tag: String, tagsOfSelection: [[String]]) -> State {
        guard !tagsOfSelection.isEmpty else { return .none }
        let k = key(tag)
        let n = tagsOfSelection.filter { list in list.contains { key($0) == k } }.count
        if n == 0 { return .none }
        return n == tagsOfSelection.count ? .all : .some
    }

    /// Alle Schlagwörter mit Anzahl, häufigste zuerst, dann alphabetisch; gleiche Schlüssel zusammengefasst.
    public static func counts(_ tagsByMedia: [String: [String]]) -> [(tag: String, count: Int)] {
        var name: [String: String] = [:]
        var count: [String: Int] = [:]
        for id in tagsByMedia.keys.sorted() {
            for t in tagsByMedia[id]! {
                let k = key(t)
                if name[k] == nil { name[k] = t }
                count[k, default: 0] += 1
            }
        }
        return name.map { (tag: $0.value, count: count[$0.key]!) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : key($0.tag) < key($1.tag) }
    }

    static func collapseSpaces(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Notizen: freier Text, begrenzt, leer = keine Notiz.
public enum NoteRules {
    public static let maxLength = 500
    public static func normalize(_ raw: String) -> String? {
        let s = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}

/// Albennamen: eindeutig (ohne Groß/klein/Akzente). Reihenfolge wie hinzugefügt, keine Dubletten.
public enum AlbumRules {
    public static let maxName = 60
    public static let maxItems = 5000

    public static func normalizeName(_ raw: String) -> String? {
        let s = String(TagRules.collapseSpaces(raw.trimmingCharacters(in: .whitespacesAndNewlines)).prefix(maxName))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// „Ferien“ → „Ferien (2)“, wenn es „Ferien“ schon gibt.
    public static func uniqueName(existing: [String], wanted: String, ignore: String? = nil) -> String {
        let taken = Set(existing.filter { $0 != ignore }.map(SearchText.normalize))
        if !taken.contains(SearchText.normalize(wanted)) { return wanted }
        var i = 2
        while taken.contains(SearchText.normalize("\(wanted) (\(i))")) { i += 1 }
        return "\(wanted) (\(i))"
    }

    /// Hängt neue IDs hinten an (bereits enthaltene bleiben an ihrem Platz). Liefert die neue Liste und die Zahl neuer.
    public static func add(_ existing: [String], _ added: [String]) -> (list: [String], added: Int) {
        appendUnique(existing, added, max: maxItems)
    }
}

/// Auswahlkorb: dauerhafter Arbeitsvorrat in Reihenfolge des Hinzufügens. Ohne jede Aufräum-Bedeutung.
public enum BasketRules {
    public static let max = 1000
    public static func add(_ existing: [String], _ added: [String]) -> (list: [String], added: Int) {
        appendUnique(existing, added, max: max)
    }
}

func appendUnique(_ existing: [String], _ added: [String], max: Int) -> (list: [String], added: Int) {
    var seen = Set(existing)
    let fresh = added.filter { seen.insert($0).inserted }
    let room = Swift.max(0, max - existing.count)
    let taken = Array(fresh.prefix(room))
    return (existing + taken, taken.count)
}
