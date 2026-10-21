import Foundation
import PhotoMaidCore
import SwiftUI

enum AppearanceChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Reihenfolge im PhotoMaid-Papierkorb (nur Ansicht).
enum BasketSort: String, Codable, CaseIterable, Sendable { case added, taken, largest }

/// Einstellungen und kleine App-Zustände (Port von Android `AppSettingsData`). Tolerant: fehlende Felder = Standard.
struct AppSettingsData: Codable, Equatable, Sendable {
    var haptics = true
    /// Gestenhilfe zusätzlich bei jedem Öffnen des Feeds (Standard aus; einmal von selbst beim ersten Feed).
    var showGestureHintOnOpen = false
    var gestureHintSeen = false
    var appearance: AppearanceChoice = .system
    /// Experiment-Design: eigenes Erscheinungsbild, Standard dunkel (wie das Artefakt), hell auf Wunsch.
    var designAppearance: AppearanceChoice = .dark
    var largeFileThresholdMB = 100
    var privacyIntroSeen = false
    /// Standardabstand beim Wisch nach rechts (Tage).
    var laterDefaultDays = LaterInterval.defaultQuick.value
    var notificationsOptIn = false
    /// Favoriten schützen: Wisch nach links auf einen Favoriten fragt nach (Standard an).
    var protectFavorites = true
    var firstSeenDay: LocalDay?
    var proOfferShown = false
    var onboardingVersion = 0
    var todayTourSeen = false
    var feedTourSeen = false
    var monthsTourSeen = false
    var seriesTourSeen = false
    var gridTourSeen = false
    var editorTourSeen = false
    /// Summe „gespart“ über alle Leerungen (nur bekannte Größen bestätigt entfernter Medien).
    var savedTotalBytes: Int64 = 0
    var savedTotalLowerBound = false
    /// Summe enthält geschätzte Größen (Anzeige „ca.“, E17).
    var savedTotalApproximate = false
    /// Vom Aufräumen ausgenommene Alben der Fotos-App (`localIdentifier`, inkl. Unteralben eines Ordners). E5.
    var excludedAlbums: [String] = []
    /// Früherer Schalter „Tasten zum Entscheiden“ – nur noch zum Übernehmen in `feedControls.visibility`.
    var decisionButtons = false
    /// Wischen & Tasten: eigene Belegung je Richtung, Tasten, Position, Sichtbarkeit (E18). Standard = feste Gesten.
    var feedControls = FeedControls()
    var feedOrder: FeedOrder = .newest
    /// Ende der letzten Sitzung mit mindestens einer Entscheidung – für „Neu seit dem letzten Aufräumen“.
    var lastSessionEnd: Date?
    /// Stand der Fotos-Änderungshistorie am Ende dieser Sitzung (`PHPersistentChangeToken`, keine Medien-IDs).
    var lastSessionChangeToken: Data?
    /// Zuletzt benutzter Monat im Feed (yyyy-MM) – für „Weitermachen“. Keine Medien-IDs.
    var continueMonth: String?
    /// Angepinnte und zuletzt verwendete Ziel-Alben (Kennungen der Fotos-App).
    var pinnedAlbums: [String] = []
    var recentAlbums: [String] = []
    /// Vorauswahl beim Speichern im Editor: immer Kopie, bis der Nutzer ausdrücklich anders wählt.
    var editSaveMode: SaveMode = .copy
    /// „In PhotoMaid ausblenden“: einzelne Medien (nur in der App, Datei unverändert, kein Tresor).
    var hiddenMedia: [String] = []
    var hiddenAlbums: [String] = []
    var albumSorts: [String: MediaSort] = [:]
    var defaultAlbumSort: MediaSort = .newest
    var albumListSort: AlbumListSort = .recent
    var slideshow = SlideshowSettings()
    var basketSort: BasketSort = .added
    /// Bildanalyse-Funktionen anbieten (lokal, Vision). Standard an; jede Analyse startet erst auf Tipp.
    var analysisEnabled = true
    /// Tab „Fotos“: Filter wie in der Fotos-App (nur Ansicht) und Raster quadratisch oder im Seitenverhältnis.
    var libraryFilter: LibraryFilter = .all
    var libraryAspectFit = false
    /// Tab „Fotos“: nach Aufnahmedatum (Zeitachse) oder zuletzt hinzugefügt zuerst.
    var libraryOrder: LibraryOrder = .captured

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettingsData()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        haptics = v(.haptics, d.haptics)
        showGestureHintOnOpen = v(.showGestureHintOnOpen, d.showGestureHintOnOpen)
        gestureHintSeen = v(.gestureHintSeen, d.gestureHintSeen)
        appearance = v(.appearance, d.appearance)
        designAppearance = v(.designAppearance, d.designAppearance)
        largeFileThresholdMB = v(.largeFileThresholdMB, d.largeFileThresholdMB)
        privacyIntroSeen = v(.privacyIntroSeen, d.privacyIntroSeen)
        laterDefaultDays = v(.laterDefaultDays, d.laterDefaultDays)
        notificationsOptIn = v(.notificationsOptIn, d.notificationsOptIn)
        protectFavorites = v(.protectFavorites, d.protectFavorites)
        firstSeenDay = v(.firstSeenDay, d.firstSeenDay)
        proOfferShown = v(.proOfferShown, d.proOfferShown)
        onboardingVersion = v(.onboardingVersion, d.onboardingVersion)
        todayTourSeen = v(.todayTourSeen, d.todayTourSeen)
        feedTourSeen = v(.feedTourSeen, d.feedTourSeen)
        monthsTourSeen = v(.monthsTourSeen, d.monthsTourSeen)
        seriesTourSeen = v(.seriesTourSeen, d.seriesTourSeen)
        gridTourSeen = v(.gridTourSeen, d.gridTourSeen)
        editorTourSeen = v(.editorTourSeen, d.editorTourSeen)
        savedTotalBytes = v(.savedTotalBytes, d.savedTotalBytes)
        savedTotalLowerBound = v(.savedTotalLowerBound, d.savedTotalLowerBound)
        savedTotalApproximate = v(.savedTotalApproximate, d.savedTotalApproximate)
        excludedAlbums = v(.excludedAlbums, d.excludedAlbums)
        decisionButtons = v(.decisionButtons, d.decisionButtons)
        feedControls = v(.feedControls, d.feedControls)
        // Übernahme: wer „Tasten zum Entscheiden“ eingeschaltet hatte, sieht die Tasten weiterhin immer.
        if !c.contains(.feedControls) && decisionButtons { feedControls.visibility = .always }
        feedOrder = v(.feedOrder, d.feedOrder)
        lastSessionEnd = v(.lastSessionEnd, d.lastSessionEnd)
        lastSessionChangeToken = v(.lastSessionChangeToken, d.lastSessionChangeToken)
        continueMonth = v(.continueMonth, d.continueMonth)
        pinnedAlbums = v(.pinnedAlbums, d.pinnedAlbums)
        recentAlbums = v(.recentAlbums, d.recentAlbums)
        editSaveMode = v(.editSaveMode, d.editSaveMode)
        hiddenMedia = v(.hiddenMedia, d.hiddenMedia)
        hiddenAlbums = v(.hiddenAlbums, d.hiddenAlbums)
        albumSorts = v(.albumSorts, d.albumSorts)
        defaultAlbumSort = v(.defaultAlbumSort, d.defaultAlbumSort)
        albumListSort = v(.albumListSort, d.albumListSort)
        slideshow = v(.slideshow, d.slideshow)
        basketSort = v(.basketSort, d.basketSort)
        analysisEnabled = v(.analysisEnabled, d.analysisEnabled)
        libraryFilter = v(.libraryFilter, d.libraryFilter)
        libraryAspectFit = v(.libraryAspectFit, d.libraryAspectFit)
        libraryOrder = v(.libraryOrder, d.libraryOrder)
    }

    /// Später-Intervall beim Wisch nach rechts (nur erlaubte Werte).
    var laterInterval: LaterInterval {
        LaterInterval(value: LaterInterval.allowedQuickDays.contains(laterDefaultDays) ? laterDefaultDays : 2, unit: .days)
    }
}
