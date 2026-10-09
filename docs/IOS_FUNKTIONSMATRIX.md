# Funktionsmatrix Android → iOS

Stand 09.10.2026, Branch `claude/ios-native-liquid-glass`.
Referenz: Android-Repository `mrdevn4ever-sys/photomaid-android`, Branch `claude/product-ux-favorites`
(`docs/FUNKTIONSLISTE.md`, gleiche Kennungen in Klammern), `:core` (6 060 Zeilen Kotlin, 3 451 Zeilen Tests),
`:app` (28 183 Zeilen Kotlin, 9 971 Zeilen Tests).

Spalten:
- **Apple-API**: öffentliches Framework, mit dem die Funktion auf iOS umgesetzt wird.
- **iOS-Umsetzung**: wie die Produktlogik übertragen wird.
- **Abweichung / Grenze**: was iOS anders macht oder nicht erlaubt (nie simuliert).
- **Status**: `KERN PASS` = Logik in `PhotoMaidCore` auf Linux getestet · `APP CODE` = SwiftUI/Framework-Code
  geschrieben, nur syntaxgeprüft (`swiftc -parse`), **nicht kompiliert** (kein Mac, CI-Lauf nur auf Anweisung) ·
  `OFFEN` = noch nicht umgesetzt · `ENTSCHEIDUNG` = wartet auf `docs/IOS_ENTSCHEIDUNGEN.md` ·
  `PLATTFORMGRENZE` = auf iOS nicht möglich, Alternative beschrieben.

Ein Status ist nie eine Geräteabnahme. Simulator- und iPhone-Prüfungen: `docs/QA_MATRIX.md`.

## 0. Grundsätze (gelten überall)

| Android | iOS |
|---|---|
| Lokal, kein Konto, kein Server, kein Upload | gleich; zusätzlich kein CloudKit, keine App Groups ohne Bedarf |
| PhotoMaid löscht nie von selbst | gleich; PhotoKit-Löschung immer mit Systembestätigung |
| Ansehen/Auswählen/Verschieben/Bearbeiten ≠ Entscheidung | gleich (`DecisionLedger` nur über Feed, Papierkorb, Serien, Auslagern) |
| Zahlen gemessen, unbekannt ≠ 0 | gleich; Fotogrößen nur gemessen (Streaming), siehe C6/C9 |
| Nie verzerren | gleich (`.scaledToFit`/`.scaledToFill` + Clip, `AVLayerVideoGravity.resizeAspect`) |
| Keine KI/Bilderkennung | **geändert durch Masterprompt iOS §5**: lokale Apple-Frameworks (Vision/VisionKit) erlaubt, nur auf dem Gerät, nie Upload. Android bleibt ohne Bildanalyse. Siehe Abschnitt 13 und Entscheidung E7 |
| 16 Sprachen, Hell/Dunkel, Schrift 200 %, TalkBack, RTL, Querformat | 16 Sprachen aus den Android-Übersetzungen (`scripts/android_strings_to_xcstrings.py`), Dynamic Type bis AX5, VoiceOver, RTL, Querformat |

## 1. Start, Einführung, Berechtigungen

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| S1 | Einführung 5 Schritte mit Demo-Karten | SwiftUI `TabView(.page)` | gleiche Schritte, Demo-Stapel ohne Speicherung | – | OFFEN |
| S2 | Angebotsseite | StoreKit 2 `Product.displayPrice` | Preis nur aus dem Store | – | OFFEN |
| S3 | Zugriff erlauben/ablehnen/„nur ausgewählte“ | `PHPhotoLibrary.requestAuthorization(for: .readWrite)`, `presentLimitedLibraryPicker(from:)` | 5 Zustände: notDetermined, authorized, limited, denied, restricted | `restricted` (Bildschirmzeit/MDM) zusätzlich; „Einstellungen öffnen“ nur über `UIApplication.openSettingsURLString` | OFFEN |
| S4 | Rundgang 8 Schritte, Hinweise beim ersten Besuch | SwiftUI Overlay | gleiche Schritte | – | OFFEN |

## 2. Heute (Tab 1)

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| H1 | „Jetzt aufräumen“ mit echter Anzahl | PhotoKit `PHFetchResult.count` | `AppModel.pendingQueue` | – | OFFEN |
| H2 | „Wieder fällig“ | – | `ReviewQueues.due` | – | KERN PASS |
| H3 | Zeilen Papierkorb/Später | – | gleich | – | OFFEN |
| H4 | Schnellzugriffe (max. 6, nur Abfragen) | – | `QuickAccessItem` (Kern) | – | OFFEN |
| H5 | Gerätespeicher-Zeile | `URLResourceValues.volumeAvailableCapacityForImportantUsage`, `volumeTotalCapacity` | gleich | Privacy-Manifest-Grund `85F4.1` | OFFEN |
| H6 | Dezenter Pro-Hinweis | – | gleich | – | OFFEN |

## 3. Aufräum-Feed

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| F1–F5 | hoch Behalten · links Papierkorb · rechts Später (≤ 45°) · runter vorheriges · Totzonen | SwiftUI `DragGesture(minimumDistance: 0)` | `FeedGestureMachine` (eine State-Machine), Android-Schwellen 72/380/20, lockRatio 1,3 | Diagonale entfällt wie Android (Entscheidung E2) | OFFEN |
| F6 | Richtungs-Pille (nicht bei runter) | SwiftUI `.glassEffect` | Kapsel oben | – | OFFEN |
| F7 | Rückgängig in der Kopfzeile | – | `DecisionLedger.undo` | – | KERN PASS |
| F8 | Video: Tippen = Pause/Play, Zeitleiste | AVFoundation `AVPlayer`, `AVPlayerLayer(.resizeAspect)` | ein Player | iCloud-Video: nur mit lokaler Kopie, sonst „nicht auf diesem iPhone“ | OFFEN |
| F9 | Aktionsleiste ♡ · Teilen · Ordner · ✏️ · ⋯ | `PHAssetChangeRequest.isFavorite`, `ShareLink`/`UIActivityViewController`, `PHAssetCollectionChangeRequest.addAssets` | ♡ · Teilen · Zu Album · ✏️ · ⋯ | „In Ordner verschieben“ → **„Zu Album hinzufügen“** (iOS kennt keine Ordner für Fotos; siehe E5) | OFFEN |
| F2 | Favoriten schützen | `PHAsset.isFavorite` | Wisch links auf Favorit fragt nach | – | OFFEN |
| F10 | Tasten zum Entscheiden | `UIAccessibility.isVoiceOverRunning`, `isSwitchControlRunning`, `accessibilityAction(named:)` | Tasten rufen `FeedViewModel.perform` | – | OFFEN |
| F11 | Werbekarte im Feed (Free) | – | – | **nicht übernommen**: Masterprompt iOS „keine Tracker“ (E1) | ENTSCHEIDUNG |
| F12 | Sitzungs-Zusammenfassung | – | gleiche Zahlen, Pro-Angebot einmalig | ohne Werbezeile (E1) | OFFEN |
| F13 | Tageslimit 20 + Video-Bonus +20 | – | Limit 20 (Android-Quellcode); Bonus nur mit Werbe-SDK | Bonus entfällt ohne Werbung (E1, E4) | KERN PASS (Limit) |
| F14 | Reihenfolge wählbar | `PHFetchOptions.sortDescriptors` | `FeedOrder` | – | OFFEN |

## 4. Aufräumen (Tab 3)

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| C1 | Kategorien Fotos/Videos/Screenshots… | `PHAssetMediaSubtype.photoScreenshot`, `.photoLive`, `.videoHighFrameRate`, `PHAssetCollectionSubtype.smartAlbumSelfPortraits` usw. | Smart-Alben des Systems | genauer als Android (keine Ordner-Heuristik) | OFFEN |
| C2 | Sammlungen = reine Filter (eigene Pro) | `NSPredicate` auf `PHFetchOptions` + Kernfilter | `SmartCollections` | – | OFFEN |
| C3 | Monate, Weitermachen, Neu seit | `creationDate` | `MonthProgress` | „Neu seit“ über `creationDate` (iOS hat kein `DATE_ADDED`; Import-Datum nicht öffentlich) | OFFEN |
| L2 | Später ohne Termin (Beiseitegelegt) | – | `DecisionAction.bookmark` | – | OFFEN |
| C4 | Fotoserien (Pro), ≤ 10 s, ≥ 3 | `PHAsset.burstIdentifier`, `creationDate` | `PhotoSeries` | „gleicher Ordner“ → gleiche Aufnahmeart; Serienbilder (`burstIdentifier`) zusätzlich | OFFEN |
| C5 | Raster mit Mehrfachauswahl | `LazyVGrid`, `PHCachingImageManager` | nie Entscheidung | – | OFFEN |
| C6 | Große Dateien, unbekannte Größe getrennt | `PHAssetResourceManager.requestData` (Bytes zählen), `URLResourceValues.fileSize` (Dateien) | Größen werden **gemessen** (Streaming, `isNetworkAccessAllowed = false`) und je `localIdentifier` + `modificationDate` zwischengespeichert | keine öffentliche Metadaten-API für Fotogrößen; nicht lokale iCloud-Originale bleiben „unbekannt“ | OFFEN |
| C7 | Exakte Duplikate (Pro) | `PHAssetResourceManager`, CryptoKit `SHA256` | Größe → Teilhash → SHA-256 | nur Assets mit genau einer Hauptressource vergleichbar | KERN PASS |
| C8 | Ordner verbinden (SAF) | `fileImporter([.folder])`, `URL.bookmarkData()`, `startAccessingSecurityScopedResource`, `NSFileCoordinator` | Quellen mit Bookmark | Dateien: nur endgültig löschen (kein universeller Papierkorb auf iOS) | OFFEN |
| C9 | Speicherübersicht gemessen | wie H5 + C6 | – | – | OFFEN |
| C10 | Ausgenommene Ordner | `PHAssetCollection` | **Ausgenommene Alben** | iOS hat keine Ordner (E5) | OFFEN |

## 5. Papierkorb & Löschen

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| P1 | PhotoMaid-Papierkorb sortierbar, Vorschau | – | gleich | – | OFFEN |
| P2 | Leeren → System-Papierkorb mit Systembestätigung | `PHPhotoLibrary.performChanges { PHAssetChangeRequest.deleteAssets }` | gleich, danach Abgleich je Asset (`PHAsset.fetchAssets(withLocalIdentifiers:)`) | landet in „Zuletzt gelöscht“ der Fotos-App (30 Tage) | OFFEN |
| P3 | „Endgültig löschen“ (Einstellung) | – | – | **PLATTFORMGRENZE**: keine öffentliche API zum endgültigen Löschen; Hinweis auf „Zuletzt gelöscht“ in der Fotos-App | PLATTFORMGRENZE |
| P4 | Ansicht des System-Papierkorbs | – | – | **PLATTFORMGRENZE**: „Zuletzt gelöscht“ ist für Apps nicht lesbar; nur Hinweistext, kein Deep Link (undokumentierte URLs verboten) | PLATTFORMGRENZE |
| P5 | RAW+JPEG-Paare | `PHAssetResource.type == .alternatePhoto` | iOS hält RAW+JPEG als **ein** Asset; Löschen nimmt beide mit; Kennzeichen „RAW+JPEG“ | nichts zu koppeln | OFFEN |

## 6. Später & Verlauf (Tab 5)

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| L1 | Später-Liste nach Fälligkeit | – | `ReviewQueues`, `LaterGroup` | – | KERN PASS |
| L3 | Erinnerung (Opt-in) | `UNUserNotificationCenter`, `UNCalendarNotificationTrigger` | max. 8 ausstehend, keine Dateinamen | – | OFFEN |
| V1 | Verlauf mit Filtern | – | gleich | – | OFFEN |
| V2 | „Bearbeitet“ | – | Liste gespeicherter Fassungen | „Original wiederherstellen“ für Bearbeitungen am Original über `PHContentEditingOutput` (Fotos-App „Original“) | OFFEN |

## 7. Fotos – Mediathek (Tab 2)

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| G1 | Zeitachse Tag/Monat/Jahr (zwei Finger) | `LazyVGrid`, `MagnifyGesture` | `Timeline` | – | OFFEN |
| G2 | Filter + Suche ohne Akzente | `String.folding(options: .diacriticInsensitive)` | Suche über Albumname, Schlagwort, Notiz, Datum; optional erkannter Text (E7) | – | OFFEN |
| G3 | Auswahl mit Aktionen | – | gleich | – | OFFEN |
| G4 | Vollbild-Betrachter, Zoom | `UIScrollView` (Zoom) via `UIViewRepresentable` | blättern, runter = schließen | – | OFFEN |
| G5 | Betrachter-Video | `AVPlayer` | gleich | – | OFFEN |
| G6 | Favorit im Betrachter | `isFavorite` | gleich | – | OFFEN |
| G7 | Info (Datum, Größe, Ordner, Kamera) | `PHAsset`, ImageIO `CGImageSourceCopyPropertiesAtIndex` (EXIF aus lokalen Daten) | Datum, gemessene Größe, Alben, Kamera, Ort (nur Anzeige) | – | OFFEN |
| G8 | Ordneransicht/-baum | `PHCollectionList`, `PHAssetCollection` | **Alben-Baum der Fotos-App** (Ordner + Alben), neues Album | iOS-Gegenstück zu Ordnern (E5) | OFFEN |
| G9 | Favoriten-Ansicht | `smartAlbumFavorites` | gleich | – | OFFEN |
| G10 | In PhotoMaid ausblenden | – | PhotoMaid-eigen (lokale IDs) | der System-„Ausgeblendet“-Ordner wird nicht benutzt | OFFEN |
| G11 | Diashow | SwiftUI | `Slideshow` | – | OFFEN |
| G12 | Kopfhörer-Tasten nur Play/Pause/Spulen | `MPRemoteCommandCenter` (`togglePlayPauseCommand`, `skipForward/BackwardCommand`) | `nextTrackCommand` bleibt aus | – | OFFEN |

## 7a. Organisieren

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| O1 | PhotoMaid-eigene Alben | `PHAssetCollectionChangeRequest` | **Alben der Fotos-App** (Mehrfachzuordnung, ohne Kopie) | E5: auf iOS sind System-Alben genau „bewusste Zusammenstellung“; Änderung sichtbar in der Fotos-App | ENTSCHEIDUNG |
| O2 | Schlagwörter | – | PhotoMaid-eigen | keine öffentliche Keyword-API in PhotoKit | OFFEN |
| O3 | Notiz je Medium | – | PhotoMaid-eigen | Bildunterschriften der Fotos-App sind nicht öffentlich schreibbar | OFFEN |
| O4 | Auswahlkorb | – | gleich | – | OFFEN |
| O5 | Wiederfinden über ID/Fingerabdruck | `localIdentifier`, `PHCloudIdentifier` (geräteübergreifend) | `Rematch` | `PHPhotoLibrary.cloudIdentifierMappings` für iCloud-Fotos | OFFEN |

## 8. Studio (Tab 4)

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| T1 | Übersicht | – | gleich | – | OFFEN |
| T2 | Medienauswahl | PhotoKit-Raster (eigene Auswahl; `PhotosPicker` nur für eingeschränkten Zugriff) | nie Entscheidung | – | OFFEN |
| T3/T4 | Collage Raster/Frei/Streifen | Core Graphics `UIGraphicsImageRenderer` | `Collage` (Kern) + ein Renderer für Vorschau und Export | – | OFFEN |
| T5 | Video zusammenfügen | `AVMutableComposition`, `AVMutableVideoComposition`, `AVAssetExportSession` | `MoviePlan` | – | OFFEN |
| T6 | Diashow als Video | `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor` | Dauer je Bild, sanfter Zoom | – | OFFEN |
| T7 | Verkleinern | ImageIO `CGImageSourceCreateThumbnailAtIndex`, `CGImageDestination` | `BatchPlan` | – | OFFEN |
| T8 | Umwandeln (HEIC → JPEG/PNG) | ImageIO (`UTType.jpeg/.png/.heic`) | HEIC-Ausgabe zusätzlich möglich | – | OFFEN |
| T9 | Standort entfernen | ImageIO `kCGImageDestinationMetadata` ohne GPS | gleich | – | OFFEN |
| T10 | Originale auf Wunsch in den Papierkorb | `deleteAssets` | Standard aus | landet in „Zuletzt gelöscht“ | OFFEN |
| T11 | Screenshots zusammenfügen | Core Graphics | gleich | – | OFFEN |
| T12/T13 | GIF aus Fotos/Video | ImageIO `UTType.gif`, `AVAssetImageGenerator` | nativer GIF-Encoder | – | OFFEN |
| T14 | Teilen ohne Speichern | `ShareLink` (temporäre Datei) | gleich | – | OFFEN |

## 8a. Arbeitsabläufe

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| W1–W4 | Abläufe mit Zielgröße, Vorschau „Das passiert“, Ergebnisliste | ImageIO, `AVAssetExportSession`/`AVAssetWriter` (Bitrate) | `Workflow`, `TargetSize`, `VideoTarget` (Kern) | – | OFFEN |

## 8b. Teilen-Ziel und Shortcuts

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| S1–S3 | „An PhotoMaid senden“ | Share Extension (`NSExtensionActivationRule`), App Group | Erweiterung legt Dateien in den App-Group-Container; die App zeigt „Übernommen“ beim nächsten Öffnen | eine Share Extension darf die App nicht öffnen; App Group braucht Signierung (E9) | ENTSCHEIDUNG |
| S4 | Shortcuts am App-Symbol | `UIApplicationShortcutItem` (Schnellaktionen), App Intents `AppShortcutsProvider` | öffnen nur Ansichten | – | OFFEN |

## 8c. Dokumente – PDF

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| D1–D4 | PDF aus Fotos, Kontaktbogen, Beschriftung | `UIGraphicsPDFRenderer`, PDFKit | `PdfLayout` (Kern) + Renderer; Bilder neu als JPEG, keine Metadaten | Speichern über `fileExporter` (Dateien-App) statt `Documents/PhotoMaid` | OFFEN |
| neu | Dokumente scannen | VisionKit `VNDocumentCameraViewController` | Masterprompt §7 | Kamera nötig (`NSCameraUsageDescription`) | OFFEN |
| neu | Seiten sortieren/drehen/entfernen, zusammenführen/aufteilen | PDFKit `PDFDocument.insert/removePage/exchangePage`, `PDFPage.rotation` | PDF Studio | – | OFFEN |
| neu | Textsuche | `PDFDocument.findString` | – | nur PDFs mit Textebene | OFFEN |
| neu | Annotationen, Zeichnen, Unterschrift | PDFKit `PDFAnnotation`, PencilKit `PKCanvasView` | Unterschrift als Bild-Stempel, beim Export in die Seite eingezeichnet | – | OFFEN |
| neu | OCR für Scans | Vision `RecognizeTextRequest` | unsichtbare Textebene im PDF (`CGContext.setTextDrawingMode(.invisible)`) | Sprachen laut `supportedRecognitionLanguages` | OFFEN |
| neu | Konvertierung Office/Archiv | QuickLook (`QLPreviewController`) nur Ansicht; ZIP erstellen über `NSFileCoordinator(.forUploading)` | Office → PDF und ZIP-Entpacken: **keine öffentliche API** → nicht angeboten, dokumentiert | PLATTFORMGRENZE | PLATTFORMGRENZE |

## 8d. Auslagern und Sichern

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| AR1–AR6 | Kopie auf gewählten Ordner, SHA-256 + erneutes Lesen, Journal | `fileImporter([.folder])` + Bookmark, `PHAssetResourceManager.writeData`, CryptoKit, `URLResourceValues.volumeIsRemovable`/`volumeIsInternal`/`isUbiquitousItem` | `Archive` (Kern) | Ziel-Einordnung über Volume-Eigenschaften: externer Datenträger (USB-C) / gleicher Speicher / Cloud-Anbieter (File Provider, nie „lokal“) | OFFEN |
| BK1–BK3 | Sicherung als JSON, Wiederherstellen per Rematch | `fileExporter`/`fileImporter` | `Backup` (Kern), gleiches Format `photomaid-backup` v1 | Android-Sicherungen lesbar; IDs gerätespezifisch → Fingerabdruck | OFFEN |

## 9. Foto-Editor

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| E1 | Editor wie Fotos-App, immer dunkel | SwiftUI, `.preferredColorScheme(.dark)` | Kapseln ✕/✓, Reiterkapsel mit Liquid Glass | – | OFFEN |
| E2 | Zuschnitt, Drehen, Spiegeln, Begradigen, Perspektive | Core Image `CIPerspectiveCorrection`, `CGAffineTransform` | `EditRecipe` + `EditGeometry` (Kern) | – | OFFEN |
| E3 | Anpassen (Belichtung … Körnung) | Core Image (`CIExposureAdjust`, `CIColorControls`, `CIHighlightShadowAdjust`, `CITemperatureAndTint`, `CIVibrance`, `CISharpenLuminance`, `CINoiseReduction`, `CIVignette`, `CIToneCurve`) | gleiche Regler + Rauschreduzierung (Masterprompt §4) | Werte-Abbildung auf CI-Parameter eigenständig, Vorschau = Export (gleicher CI-Graph) | OFFEN |
| E4 | Filter mit Stärke, Vorlagen | `CIColorMatrix`, `CIPhotoEffect*` | gleiche Farbmatrizen wie Android | – | OFFEN |
| E5 | Rote Augen, Bereiche | Core Image Masken (`CIRadialGradient`, `CILinearGradient`, `CIBlendWithMask`) | gleich (rein manuell) | – | OFFEN |
| E6 | Text, Sticker, Zeichnen, Formen, Abdecken | Core Graphics, PencilKit | `Layers` (Kern) | – | OFFEN |
| E7 | Rahmen | Core Graphics | gleich | – | OFFEN |
| E8 | Größe proportional, nie hochskalieren | – | `ResizeRules` | – | OFFEN |
| E9 | Speichern: Kopie (Standard) / Kopie + Original in Papierkorb | `PHAssetCreationRequest`, `PHContentEditingOutput` + `PHAdjustmentData` | **Als Kopie speichern** (Standard) · **Original bearbeiten** (nicht destruktiv, in der Fotos-App „Original wiederherstellen“; Systembestätigung) · Kopie + Original in „Zuletzt gelöscht“ | „Original bearbeiten“ ist das iOS-Gegenstück zum nicht destruktiven Rezept | OFFEN |
| E10 | Pro-Sperre | – | `hasProToolsAccess` | – | OFFEN |
| E11 | Lupe, Histogramm, Clipping | `CIAreaHistogram` | gleich | – | OFFEN |
| neu | Stapelbearbeitung | Core Image | Rezept auf Auswahl anwenden (Masterprompt §4) | – | OFFEN |

## 10. Video-Editor

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| EV1–EV8 | Kürzen, Bereiche entfernen, Tempo, Ton, Format, Farbe, Text/Sticker, Standbild, Export mit Profilen | `AVMutableComposition` (`removeTimeRange`, `scaleTimeRange`), `AVMutableAudioMix`, `AVVideoComposition(asset:applyingCIFiltersWithHandler:)`, `AVAssetImageGenerator`, `AVAssetExportSession` (Fortschritt, Abbruch) | `VideoPlan` (Kern); Vorschau und Export über dieselbe `AVVideoComposition` | Ton ersetzen (Masterprompt §6): eigene Audiodatei über `fileImporter`; schneller Weg = `AVAssetExportPresetPassthrough` | OFFEN |

## 11. Pro, Einstellungen, Bedienungshilfen

| ID | Android | Apple-API | iOS-Umsetzung | Abweichung / Grenze | Status |
|---|---|---|---|---|---|
| X1 | Einmalkauf + Wiederherstellen | StoreKit 2 `Product.purchase()`, `Transaction.currentEntitlements`, `Transaction.updates`, `AppStore.sync()` | Non-Consumable; RevenueCat entfällt (E3) | Produkt-ID per Build-Einstellung | OFFEN |
| X2 | Pro-Test 30 min per Video | – | nur mit Werbe-SDK | E1 | ENTSCHEIDUNG |
| X3 | Werbung nur Free nach UMP | – | – | E1 | ENTSCHEIDUNG |
| X4 | Einstellungen | `@AppStorage`/Core Data `CDKeyValue` | gleiche Punkte außer „Endgültig löschen“ (P3) | – | OFFEN |
| X5 | Dunkelmodus | Systemfarben + Asset-Farben | gleich | – | OFFEN |
| X6 | Große Schrift | Dynamic Type bis `accessibility5` | `ViewThatFits`, Scrollen statt Schrumpfen | – | OFFEN |
| X7 | TalkBack | VoiceOver, `accessibilityLabel/Action` | gleich | – | OFFEN |
| X8 | 16 Sprachen, RTL, Gestenpfeile physisch | `Localizable.xcstrings`, `.environment(\.layoutDirection)` | Pfeile nie gespiegelt (`.flipsForRightToLeftLayoutDirection(false)`) | – | OFFEN |
| X9 | Querformat | `horizontalSizeClass` | Werkzeuge neben der Bühne | – | OFFEN |
| X10 | Zurück ohne Animation | `NavigationStack` | Systemverhalten (Wischen vom Rand) | iOS-Standard-Navigation wird nicht abgeschaltet | OFFEN |

## 12. iOS-eigene Ergänzungen aus dem Masterprompt

| Bereich | Apple-API | Umsetzung | Status |
|---|---|---|---|
| Liquid Glass | `glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)`, `TabView` + `Tab`, `tabBarMinimizeBehavior(.onScrollDown)`, `ToolbarSpacer` | nur Navigation und schwebende Bedienelemente; Inhalte (Fotos, Listen) ohne Glas | OFFEN |
| Dateien | `fileImporter`/`fileExporter`, `QLPreviewController`, `UTType` | Dokumente, Bilder, Videos, Archive (nur Ansicht/ZIP erstellen), suchen/filtern/sortieren | OFFEN |
| iCloud-Platzhalter | `PHImageRequestOptions.isNetworkAccessAllowed = false`, `PHImageResultIsInCloudKey` | „Nicht auf diesem iPhone“ statt Laden; Bearbeiten/Auslagern lädt nur auf ausdrücklichen Tipp | OFFEN |

## 13. Lokale Bildanalyse (Masterprompt §5, nur iOS)

| Funktion | Apple-API | Umsetzung | Status |
|---|---|---|---|
| Motiv freistellen / Hintergrund entfernen | Vision `GenerateForegroundInstanceMaskRequest` (iOS 17+), VisionKit `ImageAnalysisInteraction` (`.imageSubject`) | Ergebnis als neues PNG mit Transparenz (Kopie) | OFFEN |
| Text erkennen | Vision `RecognizeTextRequest`, VisionKit Live Text | Kopieren/Suchen; Index nur lokal | OFFEN |
| Dokumente scannen | VisionKit `VNDocumentCameraViewController` | PDF Studio | OFFEN |
| Kategorisieren | Vision `ClassifyImageRequest` | Vorschläge als Filter („Dokumente“, „Essen“ …), nie automatische Aktion | OFFEN |
| Ähnliche Fotos | Vision `GenerateImageFeaturePrintRequest` + Abstand | Gruppen „ähnlich aussehend“, Entscheidung nur durch Nutzer | OFFEN |
| Unscharfe Fotos | Core Image Laplace-Varianz (`CIConvolution3X3` + `CIAreaAverage`) | „möglicherweise unscharf“ mit Schwelle, nie automatische Aktion | OFFEN |
| Doppelte Aufnahmen | Zeit + Feature-Print | als Gruppe zum Vergleichen | OFFEN |
| Bildqualität | Vision `CalculateImageAestheticsScoresRequest` (iOS 18+, `isUtility`) | Hinweis „Schnappschuss/Beleg“, nie Bewertung als „schlecht“ ohne Erklärung | OFFEN |
| Objektentfernung (LaMa), Segmentierung (MobileSAM) | Core ML | **nur Prüfung**, keine Integration ohne Freigabe (E8, `docs/IOS_MODELLPRUEFUNG.md`) | ENTSCHEIDUNG |
