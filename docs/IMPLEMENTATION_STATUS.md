# Implementierungsstatus

Stand: 09.10.2026 · Branch `claude/ios-native-liquid-glass` · gepusht, kein PR, kein GitHub-Actions-Lauf.
Plan für die nächsten Schritte: `docs/PLAN_WEITER.md`.

## Umgebung

Linux-Cloud-Container (Ubuntu 24.04), Swift 6.4. **Kein macOS, kein Xcode, kein Simulator, kein iPhone.**
→ `PhotoMaidCore` wird gebaut und getestet; das App-Target ist geschrieben und syntaxgeprüft, aber **nie kompiliert**.

## Prüfstatus

| Prüfung | Ergebnis |
|---|---|
| `swift build` (PhotoMaidCore) | PASS |
| `swift test` (PhotoMaidCore): 220 Tests, 27 Suites | PASS |
| `swiftc -parse` aller 69 App-Dateien | PASS (nur Syntax, keine Typprüfung) |
| `scripts/android_strings_to_xcstrings.py --check`: 782 Kennungen, 16 Sprachen | PASS |
| App-Target bauen (`xcodebuild`) | BLOCKED: 19 verlinkte Ansichten fehlen noch (`docs/PLAN_WEITER.md` §1), danach NOT RUN (braucht macOS-Lauf, E11) |
| XCTest / XCUITest | NOT RUN |
| Simulator, Gerät, VoiceOver, Performance | NOT RUN |

## Fertig geschrieben (App)

Fundament (Texte, AppModel, 5 Tabs, Design-System, StoreKit 2, Diagnose) · Feed (Gesten, Aktionsleiste,
Favoritenschutz, Später-Pille, Zusammenfassung, Limit-Blatt) · Heute · Aufräumen · Papierkorb · Später · Verlauf ·
Monate · Serien · Duplikate · Große Dateien · Speicher · Dateien · Tab Fotos (Zeitachse, Betrachter, Alben,
Favoriten, Suche, Auswahl, Schlagwörter/Notizen, Auswahlkorb, Diashow) · Foto-Editor · Video-Editor ·
Export-Koordinator.

## Offen (App)

Studio, Collage, Film/Diashow, Werkzeuge inkl. Stapelbearbeitung und GIF, Abläufe, PDF aus Fotos, PDF-Studio mit
Scan/Texterkennung, lokale Analyse, Auslagern/Sichern, Einstellungen, Pro-Seite, Datenschutz, Hilfe, Ausgenommene
Alben, Sammlungen, „Öffnen in“, Einführung, Tests. Reihenfolge und Aufwand: `docs/PLAN_WEITER.md` §2.
