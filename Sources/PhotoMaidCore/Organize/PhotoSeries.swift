import Foundation

/// Fotoserien OHNE Bildanalyse: Medien derselben Gruppe (iOS: gleiche Aufnahmeart bzw. gleiche Serienbild-Kennung),
/// kurz hintereinander aufgenommen. Bewusst nur so benannt („Kurz hintereinander aufgenommen“) – nie „bestes Foto“.
/// Ähnlichkeit per Bildanalyse ist eine getrennte Funktion (`SimilarPhotos`, Entscheidung E7).
public enum PhotoSeries {
    /// Höchster Abstand zur jeweils vorigen Aufnahme.
    public static let maxGap: TimeInterval = 10
    public static let minSize = 3

    public struct Member: Hashable, Sendable {
        public let id: String
        public let group: String?
        public let takenAt: Date?
        public init(id: String, group: String?, takenAt: Date?) {
            self.id = id
            self.group = group
            self.takenAt = takenAt
        }
    }

    /// Gruppen in Aufnahme-Reihenfolge (älteste zuerst). Medien ohne Zeit oder Gruppe gehören zu keiner Serie.
    /// Gruppen werden ohne Groß-/Kleinschreibung verglichen; Serien kleiner `minSize` fallen weg.
    public static func groups(_ items: [Member], maxGap: TimeInterval = maxGap, minSize: Int = minSize) -> [[Member]] {
        var byGroup: [String: [Member]] = [:]
        for m in items {
            guard m.takenAt != nil, let g = m.group?.trimmingCharacters(in: .whitespaces), !g.isEmpty else { continue }
            byGroup[g.lowercased(), default: []].append(m)
        }
        var out: [[Member]] = []
        for key in byGroup.keys.sorted() {
            let sorted = byGroup[key]!.sorted { ($0.takenAt!, $0.id) < ($1.takenAt!, $1.id) }
            var run: [Member] = []
            for m in sorted {
                if let last = run.last, m.takenAt!.timeIntervalSince(last.takenAt!) > maxGap {
                    if run.count >= minSize { out.append(run) }
                    run = []
                }
                run.append(m)
            }
            if run.count >= minSize { out.append(run) }
        }
        return out.sorted { ($0.first!.takenAt!, $0.first!.id) < ($1.first!.takenAt!, $1.first!.id) }
    }

    /// Zuordnung Medium → seine Serie.
    public static func index(_ items: [Member]) -> [String: [Member]] {
        var out: [String: [Member]] = [:]
        for g in groups(items) { for m in g { out[m.id] = g } }
        return out
    }
}
