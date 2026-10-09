# Plan: wie es weitergeht (iOS)

Stand 09.10.2026 · Branch `claude/ios-native-liquid-glass` · kein PR, kein Merge, **kein GitHub-Actions-Lauf**
(nur auf deine ausdrückliche Anweisung, siehe E11).

## 1. Wo wir stehen (ehrlich)

| Bereich | Stand | Prüfung |
|---|---|---|
| `PhotoMaidCore` (Android-Kern portiert) | fertig: Gesten, Ledger, Limit 20 + Bonus, Später, Sammlungen, Monate, Mediathek, Organisieren, Editor-Rezept/Geometrie/Farbe/Ebenen, Collage, Video/Film-Planung, Stapel/Abläufe, PDF-Layout, Auslagern/Sicherung, Verlauf | `swift build` + `swift test` **PASS** (220 Tests, 27 Suites, Linux) |
| App: Fundament, Feed, Heute, Aufräumen, Papierkorb, Später, Verlauf, Monate, Serien, Duplikate, Große Dateien, Speicher, Dateien, Tab Fotos (Zeitachse, Betrachter, Alben, Favoriten, Suche, Auswahl, Schlagwörter, Auswahlkorb, Diashow) | geschrieben | nur `swiftc -parse` **PASS**; Typprüfung/Build **NOT RUN** |
| App: Foto-Editor (Core Image, Vorschau = Export, Kopie / Ersetzen über „Zuletzt gelöscht“ / Original bearbeiten E15, Liste „Bearbeitet“) | geschrieben | nur Syntax **PASS**; Build **NOT RUN** |
| App: Video-Editor (eigener Compositor, Kürzen, Bereiche entfernen, Tempo, Ton bis 200 % mit Blenden, Format Füllen/Einpassen, Farbe/Filter live, Text/Sticker mit Zeitfenster, Standbild, Ton als M4A über „Dateien“, schneller Weg ohne Neuberechnung, Profile mit „ca.“-Schätzung) + `ExportCoordinator` (`BGContinuedProcessingTask`, sonst `beginBackgroundTask`) | geschrieben | nur Syntax **PASS**; Build **NOT RUN** |
| Texte | 782 benutzte Kennungen, 2089 Einträge, 16 Sprachen | `android_strings_to_xcstrings.py --check` **PASS** |
| **App-Target als Ganzes** | **nicht baubar**: 19 Ansichten sind in `Routes.swift`/`RootView.swift` verlinkt, aber noch nicht geschrieben (Liste unten) | Build **BLOCKED** bis Schritt A fertig |

Fehlende Ansichten: `StudioView`, `CollageView`, `MovieView`, `ToolsView`, `WorkflowsView`, `PdfFromPhotosView`,
`PdfStudioView`, `DocumentScannerHost`, `SmartReviewView`, `ArchiveView`, `BackupView`, `SettingsView`, `ProView`,
`PrivacyView`, `HelpView`, `ExcludedAlbumsView`, `ReceivedView`, `OnboardingFlow`, `CollectionsView`.

Bewusst **keine Platzhalter**: Leere „Kommt bald“-Seiten wären tote Buttons (Verbot). Deshalb bleibt der Build
blockiert, bis jede Seite echte Funktion hat.

## 2. Reihenfolge der nächsten Schritte

Jeder Schritt endet mit: Syntaxprüfung aller Dateien, `swift test`, Textprüfung, Commit, Push. Kein CI-Lauf.

| Schritt | Inhalt | Grundlage (Android / Kern) | Aufwand |
|---|---|---|---|
| **A1** Studio + Collage | `StudioView` (4. Tab: Collage, Video zusammenfügen, Diashow, Werkzeuge, Abläufe, PDF, Bearbeitet, Entwürfe), `CollageView` mit `CollageRenderer` (Vorschau = Export, Raster/Frei/Streifen, Entwürfe Free 3 / Pro 50) | `CollageScreen.kt`, Kern `Studio/Collage.swift` | groß |
| **A2** Film/Diashow | `MovieView`: Clips wählen/ordnen, Fotodauer, sanfter Zoom, Übergang „über Schwarz“, Format, Qualität, Musik aus eigener Datei (`fileImporter`), Speichern mit Pro über `VideoExportJob.renderMovie` | `MovieScreen.kt`, `MoviePlan` | mittel |
| **A3** Werkzeuge | `ToolsView`: Verkleinern, Umwandeln, Standort entfernen (Free bis 10), Screenshots zusammenfügen, GIF (`CGImageDestination`, Pro), **Stapelbearbeitung** (Rezept auf viele Fotos, Pro) – Ersparnis nur gemessen (`BatchSummary`) | `ToolsScreen.kt`, Kern `Batch/` | mittel |
| **A4** Abläufe | `WorkflowsView`: Liste, Bearbeiten, „Das passiert“, Ergebnisliste; Zielgröße gemessen, nicht erreichbar → keine Datei | `WorkflowScreens.kt`, Kern `Workflow.swift` | mittel |
| **A5** PDF | `PdfFromPhotosView` (Kern `PdfLayout`, Vorschau = Export, keine EXIF), `PdfStudioView` (PDFKit: Seiten sortieren/drehen/entfernen, zusammenführen/teilen, Suche, Anmerkungen, Unterschrift), `DocumentScannerHost` (VisionKit-Scan), Texterkennung (Vision, lokal) | `PdfScreen.kt`, Masterprompt §4 | groß |
| **A6** Lokale Analyse | `SmartReviewView`: unscharf, ähnlich, Dokumente/Text, Kategorien – nur Vorschläge/Filter, nie Entscheidung (E7) | Masterprompt §5 | mittel |
| **A7** Auslagern + Sichern | `ArchiveView` (Kopie in gewählten Ordner, SHA-256-Prüfung, Journal), `BackupView` (JSON ohne Fotos, Wiederherstellen über `Rematch`) | Kern `Archive/` | mittel |
| **A8** Einstellungen & Rest | `SettingsView`, `ProView` (StoreKit 2, nur `displayPrice`, Wiederherstellen), `PrivacyView`, `HelpView` (Diagnose teilen), `ExcludedAlbumsView`, `CollectionsView`, `ReceivedView` („Öffnen in“), `OnboardingFlow` (mit `version`) | Android-Einstellungen, Onboarding O1–O5 | mittel |
| **A9** Tests | XCTest für Ledger/Editor-Speichern/Video-Plan-Übergabe, UI-Tests Feed-Gesten, Screenshots; alte Tests an die neue API anpassen | — | mittel |
| **A10** Doku | `IMPLEMENTATION_STATUS`, `QA_MATRIX`, `IOS_FUNKTIONSMATRIX` mit PASS / FAIL / NOT RUN / BLOCKED je Funktion | — | klein |

## 3. Danach: erster echter Build (braucht dich)

1. **Du entscheidest E11**: einen macOS-Lauf von `ci.yml` (manuell, `workflow_dispatch`) freigeben. Ein Lauf
   kostet macOS-Minuten (zählen zehnfach); ich starte ihn nie selbst.
2. Erwartung ehrlich: Der erste Lauf findet Typfehler (die App wurde noch nie kompiliert). Ich werte das Protokoll
   aus, behebe alles in einem Durchgang und bitte erst dann um den nächsten Lauf.
3. Wenn Build + Unit-Tests grün sind: TestFlight nur nach E9/E12 (Developer-Konto, Bundle-ID, Secrets) und deiner
   Freigabe – `testflight.yml`, ebenfalls nur manuell.

## 4. Was nur du entscheiden kannst (blockiert nichts im Code, aber den Release)

- **E1** Werbung/Rewarded auf iOS (Standard jetzt: ganz ohne, also auch kein Pro-Test und kein Video-Bonus).
- **E4** Preis in App Store Connect.
- **E5** Alben der Fotos-App statt Android-Ordner – passt das?
- **E8** LaMa/MobileSAM (Objekt entfernen / Segmentierung) – einbauen oder nicht.
- **E9/E12** Apple-Developer-Konto, Bundle-ID, App Group (für „An PhotoMaid senden“), Secrets in GitHub.
- **E10** Free/Pro-Aufteilung der iOS-eigenen Funktionen (Scan, Texterkennung, PDF bearbeiten, Freistellen,
  ähnliche/unscharfe Fotos, Stapelbearbeitung) – vorläufig an einer Stelle in `Capabilities`.
- **E11** wann ein macOS-CI-Lauf gestartet werden darf.

## 5. Bekannte Risiken für den ersten Build

- iOS-26-SDK-Signaturen, die ohne Compiler nicht bestätigt sind: `AVVideoCompositing` (Sendable-Attribute),
  `BGContinuedProcessingTaskRequest`, `AVAssetExportSession.export(to:as:)`/`states(updateInterval:)`,
  Liquid-Glass-Modifikatoren. Alles an wenigen Stellen gekapselt, damit Korrekturen klein bleiben.
- `BGContinuedProcessingTask` braucht ein Gerät für die echte Prüfung (Simulator zeigt das Verhalten nur teilweise).
- Video-Export auf echten Medien (HDR, Zeitlupe, 4K/60) nur auf dem Gerät prüfbar.

## 6. Android

Repo `photomaid-android`, Branch `claude/product-ux-favorites`: sauber und gepusht. Paket 5 (Auslagern/Sichern) ist
nicht gemergt – PR nur auf deine ausdrückliche Anweisung.
