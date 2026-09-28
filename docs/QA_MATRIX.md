# QA-Matrix

Status: PASS / FAIL / NOT RUN / BLOCKED. Stand: siehe `IMPLEMENTATION_STATUS.md`.

## Automatisiert – PhotoMaidCore (Linux, Swift 6.4, `swift test`)

| Bereich (Suite) | Status |
|---|---|
| Gesten: jede Richtung, feste Bedeutung, Diagonale, zu kurz, Flick, Gegenschwung, Hysterese, Achse, Suspendierung, kein Doppel-Commit, Systemabbruch | PASS |
| Ledger: Grundentscheidungen, Idempotenz, doppelte Command-ID, veraltete Revision, Korrektur, Undo, Undo-Konflikt, verschachteltes Undo, Termin gehört zu Später, Persistenzfehler, Neustart, Termin-Auflösung, Zurückstellung entfernen, generierte Folgen (5 Seeds × 300) | PASS |
| Feed-Session: 1 Keep/Swipe, Runter ohne Entscheidung, passive Navigation, Vorschaupflicht, Callback A≠B, schnelle Folge, Persistenzfehler, Terminleiste, Korrektur ohne Doppelzählen, Session-Ende, 100 Entscheidungen | PASS |
| Später: Presets, Sommerzeit (Zürich, Frühjahr/Herbst), Mitternacht, Zeitzonenwechsel, Queues, Neustart, Gruppen | PASS |
| Operationen: Erfolg, Abbruch, Fehler, Teilerfolg, wiederholte Callbacks, Doppeltap, Limit 0/1/14/15/16, 40 vs. 7, Konkurrenz, Pro, verlorener Callback, prepared-nie-gestartet, System ok + DB-Fehler, Alias, Uhrwechsel | PASS |
| Duplikate: gleiche Bytes/anderer Name, 3×14 MB, Streaming 3 MB, Nullbyte, unbekannt, nicht vergleichbar, nicht lokal, Alias, SHA-256-Vektor, Abbruch | PASS |
| Regeln: älter als, Idempotenz, Filter, wöchentlich, neu entdeckt | PASS |
| Capabilities: Kaufzustände, Reward (Dauer, Idempotenz, 1/Tag), Uhr zurück, Pro ohne Ads, Arbeitseinheit, Speicher ohne Überlappung | PASS |

Gesamt: **74 Testfunktionen in 8 Suites PASS** (parametrisierte Fälle zählen als eine Funktion) (`swift test`, Log in `docs/evidence/swift-test.log`).

## Automatisiert – App (iOS)

| Test | Status |
|---|---|
| `PhotoMaidTests` (Core-Data-Roundtrip, Journal nach Neustart, Key-Value, `safeURL` Traversal/Symlink, Scanner) | NOT RUN (kein Xcode) |
| `PhotoMaidUITests` (4 Tabs, Gestenlegende, Pro ohne erfundenen Preis, Feed-Gesten mit QA-Medien) | NOT RUN |
| Syntaxprüfung aller 35 App-/Test-Dateien (`swiftc -parse`) | PASS |
| Typprüfung gegen iOS-27-SDK | BLOCKED |

## Manuell / Gerät (alle NOT RUN)

Matrix: kleines/Standard/großes iPhone × Portrait/Landscape × Light/Dark/System × Dynamic Type bis
AX5 × VoiceOver × Reduce Motion × Reduce Transparency × Increase Contrast.
Medien: hoch, quer, Panorama, Video mit/ohne Ton, lokal, nur iCloud.
Reales iPhone: PhotoKit-Löschung, Systemrechte, Video-Decoding, Audio-Session, Speicher,
Hintergrund, Liquid-Glass-Performance. Instruments: Hitches, Time Profiler, Leaks, Player-Lifecycle.
Läufe: 100 schnelle Fotoentscheidungen, 30 Videowechsel, wiederholtes Undo.

## QA-Sicherheit

- Nur synthetische Medien: `scripts/qa_seed_simulator.sh` (Simulator). Kein privates iPhone zurücksetzen.
- Vor destruktiven Tests: IDs gegen QA-Allowlist (Dateinamen `QA_*`, Präfix `QA-ALLOWLIST`) prüfen.
- Keine echten Käufe (StoreKit-Testdatei / Sandbox), keine Live-Ad-Klicks (offizielle Testanzeigen).
