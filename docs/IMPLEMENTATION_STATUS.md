# Implementierungsstatus

Stand: 14.10.2026 · Branch `claude/fixes-analysis-library-vault-20261014` (auf Build 5) · kein PR, kein GitHub-Actions-Lauf.

## Fixes nach Build 5 (14.10.2026, Branch `claude/fixes-analysis-library-vault-20261014`)

Auf Nutzermeldung (Screenshots Build 5) – alles ohne neue Netzwerk-, Konto- oder Löschwege:

- **Tresor:** Schließen löste Face ID aus. Ursache: `lock()` setzte erst „gesperrt“, die Vollbild-Ebene zeigte während
  des Ausblendens kurz den Sperrbildschirm, dessen `.task` Face ID startete (Bestätigen entsperrte unsichtbar). Jetzt:
  beim Schließen nur Abdeckung, Face ID startet nur bei sichtbarem Tresor und aktiver App, Entsperren bei geschlossenem
  Tresor wird abgelehnt. Regel „sperrt sofort beim Verlassen“ unverändert.
- **Analyse-Ergebnisse:** Raster war unsichtbar nach Monaten gruppiert (Reihen mit 1/2/3 Bildern) → ein durchgehendes
  Raster (`AnalysisResultPage`), Reihenfolge der Analyse. Nur noch offene Fotos (Schalter „Auch entschiedene zeigen“).
  „Durchwischen (n)“ öffnet alle Treffer im normalen Feed (Gesten, Ledger); Tipp auf ein Foto startet dort.
  Ähnliche Aufnahmen als Gruppen mit „Vergleichen“ (`SeriesCompareView`, nie „bestes Foto“). Gilt für alle vier Analysen.
- **Analyse-Ablauf:** Wärme drosselt statt abzubrechen (`ThrottledWork`/`WorkThrottle`: warm → warten und von selbst
  weiter, nur kritisch → anhalten); Fortsetzen nach Rückkehr in die App, nach dem Abkühlen und nach App-Neustart, außer
  der Nutzer hat selbst angehalten (`AnalysisAutoResume`). iCloud bis 3 Fotos gleichzeitig (WLAN). „iCloud einbeziehen“
  bleibt gespeichert. Neue Option „Weiterlaufen, wenn ich die App verlasse“ (Standard aus, Nutzerwunsch 14.10.2026):
  `BGContinuedProcessingTask` mit iOS-Fortschritt; endet die Aufgabe, geht es beim nächsten Öffnen weiter. Bildschirm
  bleibt an, solange die Analyse sichtbar läuft.
- **Große Dateien:** „Größe unbekannt (31'951)“ zählte noch nicht Gemessenes mit. Jetzt getrennt: gemessen / wird noch
  gemessen / nur in iCloud / nicht lesbar (`SizeInventory`, `MeasureState`). Größen in SQLite (`SizeIndexDatabase`)
  statt eines JSON-Blocks, der bei jeder Messung komplett neu geschrieben wurde; „nur in iCloud“ wird gespeichert und
  erst nach 12 h erneut geprüft. App-weiter Mess-Auftrag (`SizeMeasuring`): Videos zuerst (Dateigröße ohne Lesen),
  bis 4 parallel, PhotoKit-Abfragen in Paketen, läuft weiter beim Verlassen der Seite. Abschnitt „Videos nur in iCloud –
  längste zuerst“ (keine Größe, nichts geschätzt). iOS nennt die Größe von iCloud-Originalen ohne Download nicht
  öffentlich; private API bleibt verboten.
- **Duplikate:** hing bei „0 / 1“, weil vorher ALLE Größen gemessen wurden (ohne Fortschritt). Jetzt: Vorfilter
  (gleiche Art + Pixelmaße + Dauer, `DuplicatePrefilter`), nur vergleichbare Assets messen, Fortschritt je Phase,
  Prüfsummen gespeichert (`DuplicateHashCache`) – zweiter Lauf liest kaum noch; Suchlauf läuft weiter beim Verlassen.
- **Fotos-Tab:** Filter wie in der Fotos-App (Alle · Favoriten · Bearbeitet · Fotos · Videos · Bildschirmfotos, Medienarten:
  Selfies, Live Photos, Porträts, Panoramen, Zeitlupe, Zeitraffer, Kinomodus, RAW) und Ansicht quadratisch/Seitenverhältnis
  (`LibraryFilter`, gespeichert). Aktiver Filter als Chip mit Anzahl und ✕; gilt für Betrachter, Auswahl, Diashow.
- 33 neue Texte in 16 Sprachen (`ios_strings.json`), `ana2_stage_thermal` angepasst.
- Nachtrag C: `AppModel.sizes` (Papierkorb, Sammlungen) misst über `SizeMeasuring.measureParallel` (gespeicherte Werte
  sofort, Rest parallel in Paketen, Wärme-Drosselung). „Speicher“ nutzt den app-weiten Mess-Auftrag (läuft beim
  Verlassen weiter, zeigt „mind.“, solange noch gemessen wird); ein zweiter Auftrag bricht den ersten nicht mehr ab.
- E17 (Nutzerentscheidung 14.10.2026): beim Löschen steht immer eine Zahl. `SizeEstimator` (Kern) kalibriert sich aus
  den gemessenen Medien dieser Mediathek (Median Bytes/Pixel bzw. Bytes/(Pixel·s), Dateien: Median je Typ; zu wenige
  Messungen → Richtwerte HEIC/HEVC). Papierkorb: Größe je Eintrag, „Auswahl: …“, Bestätigungsdialog, „Gespart“ und
  Gesamtsumme mit „ca.“, sobald ein Teil geschätzt ist (`SizeValue`, `SizeSum`, `CleanupSavings.display`,
  `savedTotalApproximate`). „Große Dateien“: Medien nur in iCloud/nicht lesbar mit „ca.“ und iCloud-Symbol in der Liste.
  „Dateien“: ohne lesbare Größe „ca.“; Dateigröße zusätzlich über `totalFileSize`. 7 Texte (davon 1 geändert).
- E18 (Nutzerentscheidung 14.10.2026): Einstellungen › Wischen & Tasten (`FeedControlsView`, Kern `FeedControls`).
  Jede Richtung frei belegbar (auch „In Album „…“ legen“ = hinzufügen + Behalten, ein Schritt, Rückgängig nimmt beides
  zurück), Tasten frei wählbar/sortierbar/platzierbar, anzeigen nur mit Bedienungshilfen oder immer. Feed: Geste →
  Belegung (`perform(action:direction:)`), Medium fliegt in die gewischte Richtung, Richtungs-Pille, Gestenhilfe,
  Tasten und Färbung zeigen die eigene Belegung; Album-Aktionen auch als VoiceOver-Aktionen. 24 Texte.
- Nachtrag B: Medienart „Bildschirmaufnahmen“ (`videoScreenRecording`) und Sortierung „Zuletzt hinzugefügt“
  (`LibraryOrder`, Reihenfolge des Systemalbums „Aufnahmen“/`smartAlbumUserLibrary`; ohne Datumsüberschriften). 2 Texte.

| Prüfung | Ergebnis |
|---|---|
| `swift build` / `swift test` (Linux, Swift 6.4) | PASS: 361 Tests (28 neu: Ergebnisse/Drosselung, Inventur/Vorfilter/Prüfsummen, Filter/Reihenfolge, Schätzung/„ca.“-Summen) |
| Typprüfung neuer Infrastruktur gegen Platzhalter (Swift 6 strikt: `MediaSizer`, `SizeMeasuring`, `SizeIndexDatabase`, `DuplicateScanner`, `AnalysisRunner`, `AnalysisController`, `AnalysisDatabase`) | PASS (nur Linux-Platzhalter für Photos/UIKit/BackgroundTasks, kein Apple-SDK) |
| `SizeIndexDatabase` mit echtem SQLite (Linux) | PASS |
| `swiftc -parse` aller 123 App-Dateien | PASS |
| `android_strings_to_xcstrings.py --check` | PASS: 1520 benutzte Kennungen, 2506 Einträge, 16 Sprachen |
| App-Target bauen (`xcodebuild`), SwiftUI-Dateien typgeprüft | NOT RUN: kein macOS/Xcode; kein GitHub-Actions-Lauf ohne Freigabe |
| Gerät: Geschwindigkeit bei 30k Medien, Wärme, Face ID beim Schließen, PhotoKit-Fehlercode „nur in iCloud“, Reihenfolge „Zuletzt hinzugefügt“, Plausibilität der „ca.“-Schätzung gegenüber der Fotos-App | NOT RUN |

## Build 5 (11.10.2026, Branch `claude/build5-all-20261011`)

Enthält alles: Release-Stand `24b41a0` (Build 4) + Tresor-Isolation + Retusche-Absturz-Fix + K5 + Tresor-Notizen/Dateien/
Papierkorb (`claude/vault-workspace-20261011`) + schrittweise iCloud-Analyse (PR #10, `2f9d4ec`) + Integration:

- Analyse an die Oberfläche angebunden (`SmartReviewView` auf `AnalysisController`: Fortschritt, Anhalten/Fortsetzen,
  Fehlgeschlagene erneut, iCloud nur auf Wunsch und nur im WLAN, Textsuche, Motiv-Filter, Seiten). 34 Texte, 16 Sprachen.
- Kompilierlücken aus PR #10 geschlossen: fehlender Hintergrunddienst (`AnalysisBackground`) entfernt – keine
  Hintergrundanalyse, beim Verlassen der App wird angehalten; `hits(…, offset:)` ergänzt.
- Verbergen-Liste: PR #10 machte die ganze App „fail-closed“ (bei vorhandenem Tresor ohne Liste wären alle Fotos
  verschwunden; die nötige Abdeckungsbestätigung wurde nie aufgerufen). Zurück auf die sichere Fassung; für die Analyse
  ergänzt: Speichern nur unter derselben Sperre wie das Verbergen (`withAnalysisAccess`), keine Analyse bei
  beschädigter Liste, beim Verbergen werden Analyse-Daten (Text, Merkmale, Gruppen) gelöscht, Änderungsmeldung.
- Prüfung: `swift test` 333 PASS (davon 20 Analyse-Kern), Strings `--check` OK, `swiftc -parse` OK.
  iOS-Build/Gerät: siehe TestFlight-Lauf.

## Umgebung

Windows-Arbeitsumgebung ohne Swift, SwiftC, Xcode, Simulator oder iPhone. Die iOS-App ist geschrieben, aber in
dieser Umgebung weder geparst noch typgeprüft oder ausgeführt. Frühere Linux-Ergebnisse gelten nur für den damaligen
Commit und werden für den aktuellen Stand nicht als erneuter PASS ausgegeben.

## Prüfstatus

| Prüfung | Ergebnis |
|---|---|
| `swift build` / `swift test` (aktueller Commit) | BLOCKED: `swift` ist lokal nicht installiert |
| `swiftc -parse` aller 96 Swift-Dateien | BLOCKED: `swiftc` ist lokal nicht installiert |
| `scripts/i18n/build_ios_strings.py` | PASS: 97 iOS-Texte + 4 InfoPlist-Texte |
| `scripts/android_strings_to_xcstrings.py --check` | PASS: 1008 benutzte Kennungen, 2092 Einträge, 16 Sprachen |
| App-Target bauen (`xcodebuild`) | NOT RUN: kein macOS/Xcode; kein GitHub-Actions-Lauf autorisiert |
| XCTest / XCUITest | NOT RUN |
| Simulator, Gerät, VoiceOver, Performance | NOT RUN |

## Fertig geschrieben (App)

Fundament (Texte, AppModel, 5 Tabs, Design-System, StoreKit 2, Diagnose) · Feed (Gesten, Aktionsleiste,
Favoritenschutz, Später-Pille, Zusammenfassung, Limit-Blatt) · Heute · Aufräumen · Papierkorb · Später · Verlauf ·
Monate · Serien · Duplikate · Große Dateien · Speicher · Dateien · Tab Fotos (Zeitachse, Betrachter, Alben,
Favoriten, Suche, Auswahl, Schlagwörter/Notizen, Auswahlkorb, Diashow) · Foto-Editor · Video-Editor ·
Export-Koordinator · Studio/Collage · Film/Diashow · Werkzeuge/Stapel/GIF · Abläufe · PDF aus Fotos · PDF-Studio ·
VisionKit-Scan · lokale Smart-Review-Analyse · verifiziertes Archiv · JSON-Sicherung/Wiederherstellung · Einstellungen ·
StoreKit-Pro-Seite · Datenschutz/Hilfe · ausgeschlossene Alben · Sammlungen · „Öffnen in“ · Onboarding.

## Noch nicht als produktionsreif verifiziert

Der Code für A1–A9 ist vorhanden und alle zuvor fehlenden View-Typen existieren. Ohne Apple-Compiler ist die
Produktionsreife jedoch **nicht belegt**. Insbesondere PDF-Annotation/Unterschrift/OCR-Textebene, echte HDR-/4K-Medien,
security-scoped File-Provider, StoreKit-Sandbox, Vision-Ergebnisse, Hintergrundexport und alle Geräte-/Accessibility-
Matrizen benötigen einen macOS-Build und reale Gerätetests. Bis dahin ist der App-Gesamtstatus `NOT RUN`, nicht PASS.

## Nachtrag 10.10.2026 (nach TestFlight-Build 2, für Build 3)

| Bereich | Stand | Prüfstatus |
|---|---|---|
| iCloud-Vorschau wie Fotos-App (lokal sofort, volle Qualität nachladen, „!“ unten rechts) | gebaut | NOT RUN (Gerät) |
| Einführung mit Bildern/Übungskarten, Rundgang auf echte Stellen | gebaut | NOT RUN |
| Pro: ehrlicher Zustand statt „Preis wird geladen“; TestFlight-Produkt-ID `com.mrdevn4ever.photomaid.pro` | gebaut | BLOCKED (IAP in App Store Connect anlegen) |
| Tab-Leiste fest, App-Sprache (iOS-Einstellungen), Entwürfe löschen, „Gespeichert“ vollständig | gebaut | NOT RUN |
| Rasterauswahl trifft die getippte Zelle, Teilen mehrerer Medien, neue Schnellzugriffe (Zufällig u. a.) | gebaut | Kern PASS, App NOT RUN |
| Collage neu (Layout-Vorschauen, Zuschnitt je Feld, Frei/Streifen, Text/Sticker, Speicherort) | gebaut | Kern PASS, App NOT RUN |
| Video zusammenfügen, Verkleinern/Werkzeuge, Auslagern verständlich | gebaut | NOT RUN |
| Privater Tresor (E16) | gebaut | Kern PASS (11 Tests), App NOT RUN, Geräteabnahme NOT RUN |
| Neues App-Icon | eingebaut | NOT RUN |
