import Foundation

// Gespeicherte Arbeitsabläufe: mehrere vorhandene Stapel-Schritte als benannter Ablauf. Ein Ablauf erzeugt immer NEUE
// Dateien (oder nur Teil-Dateien); er löscht nie etwas, legt nichts in einen Papierkorb und trifft nie eine Aufräum-
// Entscheidung über die Quellen. Zielgrößen sind Vorgaben: das Ergebnis wird gemessen.

public enum WorkflowFormat: String, Hashable, Codable, Sendable, CaseIterable { case keep = "KEEP", jpeg = "JPEG", png = "PNG", heic = "HEIC" }

/// Was am Ende passiert: in der Mediathek speichern, nur teilen oder beides.
public enum WorkflowFinish: String, Hashable, Codable, Sendable, CaseIterable {
    case save = "SAVE", share = "SHARE", saveAndShare = "SAVE_AND_SHARE"
}

public struct Workflow: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var format = WorkflowFormat.keep
    /// Längste Seite höchstens (nie hochskaliert), `nil` = Originalgröße.
    public var longEdge: Int?
    public var quality = 85
    public var removeLocation = false
    /// Foto höchstens so groß (Bytes), `nil` = keine Vorgabe.
    public var photoMaxBytes: Int64?
    /// Untergrenzen für die Zielgröße: so klein/so schlecht wird ein Foto nie.
    public var minLongEdge = 1024
    public var minQuality = 60
    /// Video höchstens so groß (Bytes); `nil` = Videos werden übersprungen.
    public var videoMaxBytes: Int64?
    /// Neuer Dateiname „Basis_001“; `nil` = Originalname mit Zusatz.
    public var nameBase: String?
    /// Ziel-Album der Fotos-App (`localIdentifier`); `nil` = kein Album. (Android: Ordner – gleicher JSON-Schlüssel.)
    public var album: String?
    public var finish = WorkflowFinish.save

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }

    public var handlesVideos: Bool { videoMaxBytes != nil }
    public var saves: Bool { finish != .share }
    public var shares: Bool { finish != .save }

    private enum CodingKeys: String, CodingKey {
        case id, name, format, longEdge, quality, removeLocation, photoMaxBytes, minLongEdge, minQuality, videoMaxBytes,
             nameBase, finish
        case album = "folder"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        format = try c.decodeIfPresent(WorkflowFormat.self, forKey: .format) ?? .keep
        longEdge = try c.decodeIfPresent(Int.self, forKey: .longEdge)
        quality = try c.decodeIfPresent(Int.self, forKey: .quality) ?? 85
        removeLocation = try c.decodeIfPresent(Bool.self, forKey: .removeLocation) ?? false
        photoMaxBytes = try c.decodeIfPresent(Int64.self, forKey: .photoMaxBytes)
        minLongEdge = try c.decodeIfPresent(Int.self, forKey: .minLongEdge) ?? 1024
        minQuality = try c.decodeIfPresent(Int.self, forKey: .minQuality) ?? 60
        videoMaxBytes = try c.decodeIfPresent(Int64.self, forKey: .videoMaxBytes)
        nameBase = try c.decodeIfPresent(String.self, forKey: .nameBase)
        // Android speichert hier einen Ordnerpfad („Pictures/Urlaub/“, immer mit „/“ am Ende): auf iOS kein Album.
        let a = try c.decodeIfPresent(String.self, forKey: .album)
        album = a.flatMap { $0.hasSuffix("/") || $0.isEmpty ? nil : $0 }
        finish = try c.decodeIfPresent(WorkflowFinish.self, forKey: .finish) ?? .save
    }
}

/// Ein Schritt in der Beschreibung „Das passiert“ (Reihenfolge = Ausführungsreihenfolge).
public enum WorkflowStep: String, Hashable, Sendable {
    case format, resize, targetSize, quality, location, videoTarget, rename, album, save, share
}

public enum WorkflowRules {
    public static let maxName = 40
    public static let minPhotoBytes: Int64 = 50_000
    public static let minVideoBytes: Int64 = 1_000_000
    public static let photoTargets: [Int64] = [500_000, 1_000_000, 2_000_000, 5_000_000]
    public static let videoTargets: [Int64] = [10_000_000, 20_000_000, 50_000_000]
    public static let longEdges = [4096, 2048, 1600, 1080]
    public static let minEdges = [640, 1024, 1600]

    /// Schritte in Ausführungsreihenfolge (nur, was der Ablauf wirklich tut).
    public static func steps(_ w: Workflow) -> [WorkflowStep] {
        var s: [WorkflowStep] = []
        if w.format != .keep { s.append(.format) }
        if w.longEdge != nil { s.append(.resize) }
        if w.photoMaxBytes != nil { s.append(.targetSize) } else if w.format != .png { s.append(.quality) }
        if w.removeLocation { s.append(.location) }
        if w.videoMaxBytes != nil { s.append(.videoTarget) }
        if w.nameBase != nil { s.append(.rename) }
        if w.album != nil && w.saves { s.append(.album) }
        if w.saves { s.append(.save) }
        if w.shares { s.append(.share) }
        return s
    }

    public static func normalizeName(_ raw: String) -> String? {
        let s = String(TagRules.collapseSpaces(raw.trimmingCharacters(in: .whitespacesAndNewlines)).prefix(maxName))
            .trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    /// Dateinamen-Basis ohne verbotene Zeichen; `nil`, wenn nichts übrig bleibt.
    public static func sanitizeBase(_ raw: String) -> String? {
        let bad = Set("\\/:*?\"<>|")
        let cleaned = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            .map(Character.init).filter { !bad.contains($0) })
        let underscored = cleaned.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "_")
        var s = String(underscored.prefix(maxName))
        let trim = Set("_. ")
        while let f = s.first, trim.contains(f) { s.removeFirst() }
        while let l = s.last, trim.contains(l) { s.removeLast() }
        return s.isEmpty ? nil : s
    }

    /// Ein gültiger Ablauf: Name, sinnvolle Grenzen, nichts Widersprüchliches.
    public static func isValid(_ w: Workflow) -> Bool {
        normalizeName(w.name) != nil
            && (w.longEdge.map { $0 >= 320 } ?? true) && (30...100).contains(w.quality)
            && w.minQuality >= 30 && w.minQuality <= max(30, w.quality)
            && (w.photoMaxBytes.map { $0 >= minPhotoBytes } ?? true)
            && (w.videoMaxBytes.map { $0 >= minVideoBytes } ?? true)
            && (w.longEdge.map { w.minLongEdge <= $0 } ?? true)
            && (w.nameBase.map { sanitizeBase($0) != nil } ?? true)
    }

    /// Ausgabeformat eines Fotos. KEEP: PNG bleibt PNG, HEIC bleibt HEIC, alles andere wird JPEG.
    public static func outputFormat(_ w: Workflow, uti: String?) -> WorkflowFormat {
        guard w.format == .keep else { return w.format }
        switch uti?.lowercased() {
        case "public.png": return .png
        case "public.heic", "public.heif": return .heic
        default: return .jpeg
        }
    }

    /// Längste Seite des Ergebnisses: nie größer als das Original.
    public static func targetEdge(_ w: Workflow, width: Int, height: Int) -> Int {
        let src = max(1, max(width, height))
        return min(src, w.longEdge ?? src)
    }

    /// Dateiname ohne Endung. Mit Basis: „Basis_001“ (mindestens dreistellig). Ohne Basis: Originalname + Zusatz.
    public static func fileStem(_ w: Workflow, index: Int, total: Int, originalName: String?, suffix: String) -> String {
        if let base = w.nameBase.flatMap(sanitizeBase) {
            let digits = max(3, String(total).count)
            let n = String(index + 1)
            return base + "_" + String(repeating: "0", count: max(0, digits - n.count)) + n
        }
        var stem = originalName ?? ""
        if let dot = stem.lastIndex(of: ".") { stem = String(stem[..<dot]) }
        return (sanitizeBase(stem) ?? "PhotoMaid") + "_" + (sanitizeBase(suffix) ?? "PhotoMaid")
    }

    /// Gemeinsames Budget für eine Auswahl: Anteile nach Originalgröße; sind Größen unbekannt, gleich verteilt.
    public static func budgetShares(_ sizes: [Int64?], total: Int64) -> [Int64] {
        guard !sizes.isEmpty else { return [] }
        let known = sizes.compactMap { $0 }
        let sum = known.reduce(0, +)
        if known.count < sizes.count || sum <= 0 { return Array(repeating: total / Int64(sizes.count), count: sizes.count) }
        return sizes.map { Int64(Double(total) * (Double($0!) / Double(sum))) }
    }
}

/// Zielgröße für Fotos: erst die höchste Qualität, die passt; reicht die Mindestqualität nicht, wird die Kante
/// stufenweise verkleinert (bis zur Mindestkante). Jeder Versuch wird tatsächlich kodiert und gemessen.
public enum TargetSize {
    public struct Attempt: Hashable, Sendable {
        public let longEdge: Int
        public let quality: Int
        public init(longEdge: Int, quality: Int) { self.longEdge = longEdge; self.quality = quality }
    }

    public enum Outcome: Hashable, Sendable {
        case met(Attempt, bytes: Int64)
        /// Nicht erreichbar innerhalb der Grenzen; der kleinste gemessene Versuch.
        case unreachable(Attempt, bytes: Int64)

        public var attempt: Attempt {
            switch self { case .met(let a, _), .unreachable(let a, _): a }
        }
        public var bytes: Int64 {
            switch self { case .met(_, let b), .unreachable(_, let b): b }
        }
    }

    public static let edgeStep = 0.8
    public static let maxAttempts = 24

    public static func search(maxBytes: Int64, startEdge: Int, startQuality: Int, minEdge: Int, minQuality: Int,
                              lossless: Bool, isolation: isolated (any Actor)? = #isolation,
                              encode: (Attempt) async throws -> Int64) async rethrows -> Outcome {
        var best: (Attempt, Int64)?
        var attempts = 0
        func record(_ a: Attempt, _ b: Int64) {
            attempts += 1
            if best == nil || b < best!.1 { best = (a, b) }
        }
        var edge = max(1, startEdge)
        let floorEdge = max(1, min(minEdge, startEdge))
        let qMin = min(minQuality, startQuality)
        while attempts < maxAttempts {
            if lossless {
                let a = Attempt(longEdge: edge, quality: 100)
                let b = try await encode(a); record(a, b)
                if b <= maxBytes { return .met(a, bytes: b) }
            } else {
                let top = Attempt(longEdge: edge, quality: startQuality)
                let bTop = try await encode(top); record(top, bTop)
                if bTop <= maxBytes { return .met(top, bytes: bTop) }
                let low = Attempt(longEdge: edge, quality: qMin)
                let bLow: Int64
                if qMin == startQuality { bLow = bTop } else { bLow = try await encode(low); record(low, bLow) }
                if bLow <= maxBytes {
                    // Höchste passende Qualität zwischen qMin (passt) und startQuality (passt nicht).
                    var lo = qMin, hi = startQuality
                    var fit = (low, bLow)
                    while hi - lo > 2 && attempts < maxAttempts {
                        let mid = (lo + hi) / 2
                        let a = Attempt(longEdge: edge, quality: mid)
                        let b = try await encode(a); record(a, b)
                        if b <= maxBytes { lo = mid; fit = (a, b) } else { hi = mid }
                    }
                    return .met(fit.0, bytes: fit.1)
                }
            }
            if edge <= floorEdge { break }
            edge = max(floorEdge, Int((Double(edge) * edgeStep).rounded()))
        }
        let (a, b) = best!
        return b <= maxBytes ? .met(a, bytes: b) : .unreachable(a, bytes: b)
    }
}

/// Zielgröße für Videos: Bitrate aus Ziel und Dauer (abzüglich Ton und Container), Auflösung nur verkleinert, wenn die
/// Bitrate für die Originalhöhe zu knapp wäre. `nil` = nicht sinnvoll erreichbar (zu lang für das Ziel).
public enum VideoTarget {
    public static let audioBps = 128_000
    public static let containerFactor = 0.95
    public static let minVideoBps = 250_000
    public static let minBpp = 0.035
    public static let heights = [2160, 1440, 1080, 720, 480]

    public struct Plan: Hashable, Sendable {
        public let videoBitrate: Int
        public let maxHeight: Int
    }

    public static func plan(maxBytes: Int64, durationMs: Int64, hasAudio: Bool, width: Int, height: Int,
                            fps: Float = 30) -> Plan? {
        guard durationMs > 0 else { return nil }
        let seconds = Double(durationMs) / 1000
        let total = Double(maxBytes) * 8 * containerFactor / seconds
        let video = Int64((total - Double(hasAudio ? audioBps : 0)).rounded())
        guard video >= Int64(minVideoBps) else { return nil }
        let shortSide = max(1, min(width, height)), longSide = max(1, max(width, height))
        let f = Double(min(max(fps, 1), 60))
        let options = [shortSide] + heights.filter { $0 < shortSide }
        let h = options.first { s in
            Double(video) / (Double(s) * (Double(longSide) * Double(s) / Double(shortSide)) * f) >= minBpp
        } ?? options.last!
        return Plan(videoBitrate: Int(min(video, Int64(Int32.max))), maxHeight: h)
    }
}
