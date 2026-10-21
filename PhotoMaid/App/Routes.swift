import Foundation
import PhotoMaidCore
import SwiftUI

/// Unterseiten innerhalb eines Tabs (NavigationStack je Tab, eigener Verlauf je Tab).
enum Route: Hashable {
    // Aufräumen
    case trash
    case later
    case months
    case largeFiles
    case duplicates
    case storage
    case files
    case series
    case collections
    case smartReview(SmartReviewKind)
    // Fotos
    case grid(GridSource)
    case album(id: String, title: String)
    case albums
    case favorites
    case selectionBasket
    case tags
    case hidden
    // Studio
    case edits
    case collage(draftID: UUID?)
    case movie(ids: [String])
    case tools(ToolKind)
    case workflows
    case pdfFromPhotos(ids: [String])
    case pdfStudio
    case archive(ids: [String])
    // Einstellungen
    case settings
    case pro
    case privacy
    case help
    case excludedAlbums
    case backup
    /// Einstellungen › Wischen & Tasten (E18).
    case feedControls
    /// Erfolge (Gamification): Level, Serie, Tagesziel, Abzeichen.
    case achievements
    // Von außen
    case received([URL])
}

/// Raster mit Mehrfachauswahl (nie eine Entscheidung).
enum GridSource: Hashable, Sendable {
    case collection(SmartCollection)
    case items([String], titleKey: String)
    case month(MonthKey)
    case category(MediaCategory)
}

enum SmartReviewKind: String, Hashable, Sendable, CaseIterable, Identifiable {
    /// Unscharfe oder verwackelte Fotos (Schärfemaß, Vision-Ästhetik).
    case blurry
    /// Ähnliche Aufnahmen (Vision-Merkmalsabstand), nie „bestes Foto“.
    case similar
    /// Bildschirmfotos und Dokumentfotos mit Text (Texterkennung).
    case documents
    /// Kategorien (Vision-Klassifikation) als Filter.
    case categories
    var id: String { rawValue }
}

enum ToolKind: String, Hashable, Sendable, CaseIterable, Identifiable {
    case resize, convert, removeLocation, stitch, gif, batchEdit
    var id: String { rawValue }
}

/// Vollbild-Seiten über den Tabs (immer dunkel bzw. eigene Kopfzeile).
enum FullScreenRequest: Identifiable, Equatable {
    case viewer(ids: [String], index: Int)
    case editor(assetID: String)
    case videoEditor(assetID: String)
    case slideshow(ids: [String])
    case scanner

    var id: String {
        switch self {
        case .viewer(let ids, let i): "viewer-\(ids.count)-\(i)-\(ids.first ?? "")"
        case .editor(let id): "editor-\(id)"
        case .videoEditor(let id): "video-\(id)"
        case .slideshow(let ids): "slideshow-\(ids.count)-\(ids.first ?? "")"
        case .scanner: "scanner"
        }
    }
}

/// Zielseite je Route.
struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .trash: TrashView()
        case .later: LaterView()
        case .months: MonthsView()
        case .largeFiles: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .storage: StorageView()
        case .files: FilesView()
        case .series: SeriesListView()
        case .collections: CollectionsView()
        case .smartReview(let k): SmartReviewView(kind: k)
        case .grid(let s): MediaGridView(source: s)
        case .album(let id, let title): AlbumView(albumID: id, title: title)
        case .albums: AlbumsView()
        case .favorites: FavoritesView()
        case .selectionBasket: SelectionBasketView()
        case .tags: TagsView()
        case .hidden: HiddenView()
        case .edits: EditsView()
        case .collage(let id): CollageView(draftID: id)
        case .movie(let ids): MovieView(initialIDs: ids)
        case .tools(let k): ToolsView(kind: k)
        case .workflows: WorkflowsView()
        case .pdfFromPhotos(let ids): PdfFromPhotosView(initialIDs: ids)
        case .pdfStudio: PdfStudioView()
        case .archive(let ids): ArchiveView(initialIDs: ids)
        case .settings: SettingsView()
        case .pro: ProView()
        case .privacy: PrivacyView()
        case .help: HelpView()
        case .excludedAlbums: ExcludedAlbumsView()
        case .backup: BackupView()
        case .feedControls: FeedControlsView()
        case .achievements: AchievementsView()
        case .received(let urls): ReceivedView(urls: urls)
        }
    }
}
