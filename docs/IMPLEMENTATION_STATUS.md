# Implementierungsstatus

Stand: 09.10.2026 · Branch `claude/ios-native-liquid-glass` · A1–A9 gepusht, kein PR, kein GitHub-Actions-Lauf.

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
