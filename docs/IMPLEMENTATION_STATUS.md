# Implementierungsstatus

Stand: 09.10.2026 · Branch `claude/ios-native-liquid-glass` · A1–A9 gepusht, kein PR, kein GitHub-Actions-Lauf.

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
