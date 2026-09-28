# Implementierungsstatus

Stand: 2026-09-28 · Branch `claude/photomaid-ios-phase0` · nur lokale Commits, kein Push.

## Umgebung

Linux-Cloud-Container (Ubuntu 24.04). **Kein macOS, kein Xcode, kein Simulator, kein iPhone.**
Verfügbar: Swift 6.4 (Linux), XcodeGen 2.46.0 (aus Quellcode gebaut).
→ Domain-Kern vollständig kompiliert und getestet; iOS-App-Target geschrieben, syntaxgeprüft,
aber **nicht kompiliert**.

## Phasen

| Phase | Inhalt | Stand |
|---|---|---|
| 0 Preflight | Mockups zugeordnet, Toolchain geprüft (BLOCKED für Xcode), Fähigkeitsmatrix, Produktvertrag | erledigt; Spikes auf macOS offen |
| 1 Foundation | Paket + XcodeGen-Projekt, Core-Data-Modell v1, Domain-Protokolle, Design-Tokens, 4 Tabs | Code fertig; App-Build NOT RUN |
| 2 Foto-Feed | Gesten-State-Machine, Session, Persistenz, Rückwärtskorrektur, Undo, PhotoKit-Vorschau | Domain PASS; UI NOT RUN |
| 3 Sicherheit | Auswahlkorb, PhotoKit-Löschung, Journal, Abgleich, Verlauf, Free-Limit | Domain PASS; UI/Gerät NOT RUN |
| 4 Video & Später | Ein-Player-Lifecycle, Terminleiste, Due Queue, Später-Verwaltung | Domain PASS; UI NOT RUN |
| 5 Dateien | Bookmarks, koordinierter Scan, sichere Pfadauflösung, endgültiges Löschen, Quick Look | Code fertig; NOT RUN |
| 6 Duplikate & Speicher | Streaming-SHA-256 (Dateien + einfache PhotoKit-Assets), Gruppenmathematik, A/B/C-Übersicht | Domain PASS; UI NOT RUN |
| 7 Ordnung | Regeln, Aufgaben, lokale Erinnerungen, Quellenverwaltung | Domain PASS; UI NOT RUN |
| 8 Monetarisierung | RevenueCat-Gateway, Capabilities, Rewarded-Protokoll | Domain PASS; Kauf/Ads BLOCKED |
| 9 Finish | 15 Screens vereinheitlicht (Code), String Catalog | visuelle/a11y-Abnahme NOT RUN |
| 10 Abnahme | Review, Evidenz | offen |

## Geprüft

- `swift build` / `swift test` (PhotoMaidCore): 74 Testfunktionen, 8 Suites – **PASS**.
- `swiftc -parse` für 35 App-/Testdateien – **PASS** (nur Syntax).
- `xcodegen generate` – **PASS** (Projekt mit Shared Scheme, StoreKit-Testdatei im Scheme).
- `scripts/extract_strings.py --check` – **PASS** (361 Einträge, Quellsprache de).

- Unabhängiger Read-only-Review: 9 Befunde, alle behoben.
- CI-Workflow `.github/workflows/ci.yml`: Linux-Kern-Tests + macOS-Build/Test des App-Targets (erste echte Typprüfung, Ergebnis im PR #1).

## Nächster konkreter Schritt

Auf einem Mac mit stabilem Xcode (iOS-27-SDK):
1. `xcodebuild -version && xcodebuild -showsdks && xcrun simctl list devices available` dokumentieren.
2. `brew install xcodegen && xcodegen generate` (oder eingechecktes Projekt öffnen).
3. `xcodebuild -scheme PhotoMaid -destination 'platform=iOS Simulator,name=<iPhone>' build test`
   und alle Compilerfehler im App-Target beheben (erste echte Typprüfung).
4. `scripts/qa_seed_simulator.sh`, dann Feed-Durchgang und Screenshots aller 15 Screens.
5. Phase-0-Spikes (PhotoKit-Löschung, Ordner-Bookmarks, Videogröße) auf einem Test-iPhone.
