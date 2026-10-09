import Foundation

/// Reihenfolge der Albenliste (Android: Ordnerliste).
public enum AlbumListSort: String, Hashable, Codable, Sendable, CaseIterable {
    case recent, name, count
}

/// Knoten im Alben-Baum der Fotos-App (iOS-Gegenstück zum Android-Ordnerbaum, Entscheidung E5).
/// `isFolder` = Ordner (`PHCollectionList`) ohne eigene Medien; `own` = Medien direkt im Album,
/// `total` = inkl. aller Alben darunter (ein Medium in zwei Alben zählt zweimal – so zeigt es auch die Fotos-App).
public struct AlbumNode: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let isFolder: Bool
    public let own: Int
    public let total: Int
    public let latest: Date?
    public let children: [AlbumNode]
    public let depth: Int

    public init(id: String, title: String, isFolder: Bool, own: Int, latest: Date?, children: [AlbumNode] = [],
                depth: Int = 0) {
        self.id = id
        self.title = title
        self.isFolder = isFolder
        self.own = own
        self.total = own + children.reduce(0) { $0 + $1.total }
        self.latest = ([latest].compactMap { $0 } + children.compactMap(\.latest)).max()
        self.children = children
        self.depth = depth
    }

    public var hasChildren: Bool { !children.isEmpty }

    func with(depth: Int, children: [AlbumNode]) -> AlbumNode {
        AlbumNode(id: id, title: title, isFolder: isFolder, own: own, latest: latest, children: children, depth: depth)
    }
}

public enum AlbumTree {
    /// Ordnet rekursiv und setzt die Einrückung. Leere Ordner ohne Alben darunter entfallen.
    public static func order(_ nodes: [AlbumNode], sort: AlbumListSort, depth: Int = 0) -> [AlbumNode] {
        let visible = nodes.filter { !$0.isFolder || $0.total > 0 || $0.hasChildren }
        let sorted = visible.sorted { a, b in
            switch sort {
            case .recent:
                let la = a.latest ?? .distantPast, lb = b.latest ?? .distantPast
                if la != lb { return la > lb }
            case .count:
                if a.total != b.total { return a.total > b.total }
            case .name: break
            }
            return NaturalOrder.less(a.title, b.title)
        }
        return sorted.map { $0.with(depth: depth, children: order($0.children, sort: sort, depth: depth + 1)) }
    }

    /// Sichtbare Zeilen: aufgeklappte Knoten zeigen ihre Kinder (eingerückt über `depth`).
    public static func rows(_ roots: [AlbumNode], expanded: Set<String>) -> [AlbumNode] {
        var out: [AlbumNode] = []
        func walk(_ n: AlbumNode) {
            out.append(n)
            if expanded.contains(n.id) { n.children.forEach(walk) }
        }
        roots.forEach(walk)
        return out
    }

    /// Suche in Albennamen (ohne Akzente): flache Trefferliste, tiefe Treffer eingeschlossen.
    public static func search(_ roots: [AlbumNode], query: String) -> [AlbumNode] {
        let t = SearchText.tokens(query)
        guard !t.isEmpty else { return roots }
        var out: [AlbumNode] = []
        func walk(_ n: AlbumNode) {
            if SearchText.matches(t, fields: [SearchText.normalize(n.title)]) { out.append(n.with(depth: 0, children: n.children)) }
            n.children.forEach(walk)
        }
        roots.forEach(walk)
        return out
    }

    public static func find(_ roots: [AlbumNode], id: String) -> AlbumNode? {
        for r in roots {
            if r.id == id { return r }
            if let f = find(r.children, id: id) { return f }
        }
        return nil
    }

    /// Alle Album-IDs unter einem Knoten (für „Ausgenommene Alben“ inkl. Unteralben).
    public static func descendantIDs(_ node: AlbumNode) -> Set<String> {
        var out: Set<String> = [node.id]
        for c in node.children { out.formUnion(descendantIDs(c)) }
        return out
    }
}
