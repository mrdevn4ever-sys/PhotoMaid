import CoreGraphics
import Foundation
import Observation
import PhotoMaidCore

/// Bereiche unter der Collage-Vorschau.
enum CollageTab: String, CaseIterable, Identifiable {
    case layout, spacing, background, photo, decor
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .layout: "col_tab_layout"
        case .spacing: "col_tab_spacing"
        case .background: "col_tab_background"
        case .photo: "col_tab_photo"
        case .decor: "collage_tab_decor"
        }
    }

    var symbol: String {
        switch self {
        case .layout: "square.grid.2x2"
        case .spacing: "square.dashed"
        case .background: "paintpalette"
        case .photo: "photo"
        case .decor: "textformat"
        }
    }

    /// Raster: alle Bereiche. Frei/Streifen: Abstand und Ecken stecken im Layout-Bereich.
    static func tabs(for kind: CollageKind) -> [CollageTab] {
        kind == .grid ? allCases : [.layout, .background, .photo, .decor]
    }
}

/// Zustand des Collage-Editors: Entwurf, geladene Vorschaubilder, Auswahl. Eine Wahrheit: `project` (wird als Entwurf
/// gespeichert); Geometrie kommt immer aus `CollageGeometry` – dieselbe wie beim Export.
@MainActor
@Observable
final class CollageModel {
    var project: CollageProject?
    /// Aufrechte Vorschaubilder je Medien-ID.
    private(set) var sources: [String: CGImage] = [:]
    /// Gedrehte/gespiegelte Fassungen (nur wenn nötig).
    private var oriented: [String: CGImage] = [:]
    /// Medien, die nicht mehr geladen werden können.
    private(set) var missing: Set<String> = []
    /// Ausgewähltes Foto (Index in `project.items`).
    var selected: Int?
    /// Ausgewählter Text/Sticker.
    var selectedLayer: String?
    var tab: CollageTab = .layout

    var count: Int { project?.items.count ?? 0 }

    /// Seitenverhältnisse der aufrechten Fotos (unbekannt → quadratischer Platzhalter bis zum Laden).
    var imageAspects: [Float] {
        (project?.items ?? []).map { item in
            guard let img = sources[item.mediaId], img.height > 0 else { return 1 }
            return Float(img.width) / Float(img.height)
        }
    }

    var scene: CollageScene? {
        project.map { CollageGeometry.scene($0, imageAspects: imageAspects) }
    }

    var allLoaded: Bool {
        guard let project else { return false }
        return project.items.allSatisfy { sources[$0.mediaId] != nil || missing.contains($0.mediaId) }
    }

    func update(_ change: (inout CollageProject) -> Void) {
        guard var p = project else { return }
        change(&p)
        project = p
        validateSelection()
        refreshOriented()
    }

    func replace(_ p: CollageProject) {
        project = p
        validateSelection()
        refreshOriented()
    }

    /// Bild für ein Foto der Collage (Drehung/Spiegeln eingerechnet).
    func image(for item: CollageItem) -> CGImage? {
        guard let src = sources[item.mediaId] else { return nil }
        if Self.isUpright(item) { return src }
        return oriented[Self.key(item)] ?? src
    }

    func setSource(_ image: CGImage?, for mediaId: String) {
        if let image {
            sources[mediaId] = image
            missing.remove(mediaId)
        } else {
            missing.insert(mediaId)
        }
        refreshOriented()
    }

    func validateSelection() {
        if let s = selected, s >= count { selected = nil }
        if let id = selectedLayer, !(project?.layers.contains { $0.id == id } ?? false) { selectedLayer = nil }
        if let p = project, !CollageTab.tabs(for: p.kind).contains(tab) { tab = .layout }
    }

    private func refreshOriented() {
        guard let project else { return }
        var keep: [String: CGImage] = [:]
        for item in project.items where !Self.isUpright(item) {
            let k = Self.key(item)
            if let hit = oriented[k] { keep[k] = hit; continue }
            guard let src = sources[item.mediaId] else { continue }
            keep[k] = CollageRenderer.oriented(src, quarterTurns: item.quarterTurns, flipH: item.flipH)
        }
        // Nur bei Änderung zuweisen (Gesten ändern das Projekt in jedem Bild).
        if Set(keep.keys) != Set(oriented.keys) { oriented = keep }
    }

    private static func isUpright(_ item: CollageItem) -> Bool { ((item.quarterTurns % 4) + 4) % 4 == 0 && !item.flipH }

    private static func key(_ item: CollageItem) -> String {
        "\(item.mediaId)#\(((item.quarterTurns % 4) + 4) % 4)#\(item.flipH)"
    }
}

/// Wohin die fertige Collage geht. Standard: als neues Bild in „Fotos“.
enum CollageDestination: Hashable {
    case photos
    case album(id: String, title: String)
    case files
    case share
}

struct CollageSaveOptions: Hashable {
    var destination: CollageDestination = .photos
    /// Raster/Frei: längere Kante; Streifen: Breite bzw. Höhe.
    var resolution = 2048
    var format: EditFormat = .jpeg

    static let resolutions = [1080, 2048, 4096]
}
