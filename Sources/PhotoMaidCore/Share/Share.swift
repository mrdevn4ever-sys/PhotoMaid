import Foundation

/// Übergabe von außen („Öffnen in PhotoMaid“, später Share Extension) und App-Shortcuts. Grundsatz: Ein Einstieg von
/// außen öffnet nur eine Ansicht oder eine Auswahl von Aktionen – er entscheidet nie, löscht nie und legt keine
/// dauerhafte Kopie an.
public enum ShareRules {
    /// Höchstzahl je Übergabe (wie die Medienauswahl).
    public static let maxItems = 500

    /// Nur Fotos und Videos (MIME oder Uniform Type Identifier).
    public static func accepts(_ type: String?) -> Bool {
        guard let m = type?.trimmingCharacters(in: .whitespaces).lowercased(), !m.isEmpty else { return false }
        return m.hasPrefix("image/") || m.hasPrefix("video/") || m == "public.image" || m == "public.movie"
            || m.hasPrefix("public.jpeg") || m == "public.heic" || m == "public.png" || m == "com.apple.quicktime-movie"
            || m == "public.mpeg-4"
    }
}

/// Eine übergebene Datei, bevor sie einem Medium der Mediathek zugeordnet ist.
public struct SharedItem: Hashable, Sendable {
    public let url: String
    public let type: String?
    public let name: String?
    public let size: Int64?
    public init(url: String, type: String?, name: String? = nil, size: Int64? = nil) {
        self.url = url
        self.type = type
        self.name = name
        self.size = size
    }
}

/// Kandidat aus der Mediathek für den Abgleich.
public struct LibraryFingerprint: Hashable, Sendable {
    public let id: String
    public let name: String?
    public let size: Int64?
    public init(id: String, name: String?, size: Int64?) {
        self.id = id
        self.name = name
        self.size = size
    }
}

public enum ShareMatch {
    /// Zuordnung über den Dateinamen UND die Größe – nur, wenn genau ein Medium passt (nie raten).
    public static func unique(name: String?, size: Int64?, candidates: [LibraryFingerprint]) -> String? {
        guard let n = name?.trimmingCharacters(in: .whitespaces).lowercased(), !n.isEmpty,
              let s = size, s > 0 else { return nil }
        let hits = candidates.filter { $0.size == s && $0.name?.trimmingCharacters(in: .whitespaces).lowercased() == n }
        return hits.count == 1 ? hits[0].id : nil
    }
}

/// Ergebnis einer Übergabe: `matched` = Medien-IDs der Mediathek (Reihenfolge wie übergeben, ohne Doppelte),
/// `unmatched` = nicht eindeutig gefunden (sichtbar gezählt), `rejected` = keine Fotos/Videos, `overflow` = über Grenze.
public struct ShareIntake: Hashable, Sendable {
    public let matched: [String]
    public let unmatched: Int
    public let rejected: Int
    public let overflow: Int

    public var isEmpty: Bool { matched.isEmpty }

    public static func of(_ items: [SharedItem], resolve: (SharedItem) -> String?) -> ShareIntake {
        let accepted = items.filter { ShareRules.accepts($0.type) }
        let rejected = items.count - accepted.count
        let kept = accepted.prefix(ShareRules.maxItems)
        var ids: [String] = []
        var seen = Set<String>()
        var unmatched = 0
        for i in kept {
            if let id = resolve(i) {
                if seen.insert(id).inserted { ids.append(id) }
            } else {
                unmatched += 1
            }
        }
        return ShareIntake(matched: ids, unmatched: unmatched, rejected: rejected, overflow: accepted.count - kept.count)
    }
}

/// Aktionen für übergebene Medien. Keine davon ist eine Aufräum-Entscheidung.
public enum ShareAction: String, Hashable, Sendable, CaseIterable { case workflow, edit, pdf, album, basket }

public enum ShareActions {
    /// Bearbeiten nur für genau ein Medium; alles andere ab einem zugeordneten Medium.
    public static func available(matched: Int) -> [ShareAction] {
        if matched <= 0 { return [] }
        return matched == 1 ? [.workflow, .edit, .pdf, .album, .basket] : [.workflow, .pdf, .album, .basket]
    }
}

/// Ziel eines App-Shortcuts (Schnellaktion am App-Symbol, Kurzbefehle). Nur Ansichten öffnen – kein Ziel löscht,
/// entscheidet oder startet etwas ohne weiteren Tipp. Enthält nie Medien-IDs.
public enum ShortcutTarget: Hashable, Sendable {
    case clean, due, basket, workflows
    case workflow(String)

    public static let prefix = "wf:"
    public static let fixed: [ShortcutTarget] = [.clean, .due, .basket, .workflows]

    public var id: String {
        switch self {
        case .clean: "clean"
        case .due: "due"
        case .basket: "basket"
        case .workflows: "workflows"
        case .workflow(let w): Self.prefix + w
        }
    }

    public static func parse(_ id: String?) -> ShortcutTarget? {
        guard let id else { return nil }
        if id.hasPrefix(prefix) {
            let w = String(id.dropFirst(prefix.count))
            return w.trimmingCharacters(in: .whitespaces).isEmpty ? nil : .workflow(w)
        }
        return fixed.first { $0.id == id }
    }

    /// Feste Einträge plus die ersten Abläufe, insgesamt höchstens `max` (iOS zeigt bis zu 4 Schnellaktionen).
    public static func plan(workflowIDs: [String], max: Int, maxWorkflows: Int = 4) -> [ShortcutTarget] {
        let fixedPart = Array(fixed.prefix(Swift.max(0, max)))
        let room = Swift.min(maxWorkflows, Swift.max(0, max - fixedPart.count))
        var seen = Set<String>()
        let wfs = workflowIDs.filter { seen.insert($0).inserted }.prefix(room).map { ShortcutTarget.workflow($0) }
        return fixedPart + wfs
    }
}
