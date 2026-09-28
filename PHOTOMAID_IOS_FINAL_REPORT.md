# PhotoMaid iOS – Bericht (Zwischenstand, keine Fertigmeldung)

**Status: NICHT FERTIG.** Die App ist als natives Swift/SwiftUI-Projekt vollständig angelegt, der
Domain-Kern ist kompiliert und getestet. Das iOS-App-Target wurde in dieser Umgebung **nie kompiliert**:
Es gibt hier kein macOS/Xcode. Ein Build ist keine Geräteabnahme, und hier gab es nicht einmal einen Build.

## Umgebung

| Prüfung | Status | Beleg |
|---|---|---|
| `xcodebuild -version` / `-showsdks` / `simctl list` | BLOCKED | Linux-Container, kein Xcode |
| Swift-Toolchain | Swift 6.4 Linux | `docs/evidence/swift-test.log` |
| XcodeGen | 2.46.0 (aus Quellcode) | `PhotoMaid.xcodeproj` erzeugt |

## Prüfstatus

| Prüfung | Status |
|---|---|
| PhotoMaidCore `swift build` | PASS |
| PhotoMaidCore `swift test`: 74 Testfunktionen, 8 Suites (Gesten, Ledger, Feed-Session, Später/DST/TZ, Journal/Limit/Konkurrenz/Crash, Duplikate/SHA-256, Regeln, Capabilities) | PASS |
| `swiftc -parse` aller 35 App-/Testdateien (nur Syntax) | PASS |
| `xcodegen generate` (Shared Scheme, StoreKit-Testdatei, Core-Data-Modell, String Catalog, Privacy Manifest) | PASS |
| String Catalog vollständig (`scripts/extract_strings.py --check`) | PASS |
| App-Target kompilieren / Typprüfung iOS-27-SDK | BLOCKED |
| `PhotoMaidTests` (Core-Data-Integration, Pfadsicherheit) | NOT RUN |
| `PhotoMaidUITests` | NOT RUN |
| 15 Runtime-Screenshots, visueller Vergleich | NOT RUN |
| Feed-Video (hoch/links/rechts/runter/korrigieren/Review) | NOT RUN |
| Reale PhotoKit-Löschung mit QA-Material | NOT RUN |
| Dynamic Type / VoiceOver / Reduce Motion/Transparency / Increase Contrast / Dark | NOT RUN |
| Instruments (Hitches, Memory, Player-Lifecycle), 100 Entscheidungen, 30 Videowechsel | NOT RUN |
| Kauf / Restore (RevenueCat) | BLOCKED – keine Konfiguration |
| Rewarded-Werbung | BLOCKED – Anbieter nicht entschieden |
| Unabhängiger Read-only-Review (Phase 10) | durchgeführt; 9 Befunde, alle behoben (siehe unten) |
| CI (GitHub Actions: Linux `swift test`, macOS `xcodebuild build test`) | eingerichtet, Ergebnis im PR |

## Was umgesetzt ist

- **Feste Gestenlogik** in genau einer State Machine (`FeedGestureMachine`) mit Totzone,
  Richtungsbindung, Hysterese, Flick, Suspendierung (Zoom/VoiceOver/Controls); `FeedSession` bindet
  jeden Commit an Item-ID, Revision und Command-ID, verwirft veraltete Callbacks, verlangt geladene Vorschau.
- **Ledger** (Actor + synchroner Core-Data-Commit): atomare Entscheidungen, Korrekturen, Idempotenz,
  Undo mit Revisionsschutz, Terminwahl gehört zur Später-Aktion, Persistenzfehler setzen zurück.
- **Später 2.0**: lokaler Kalendertag, Kalenderarithmetik, Due Queue, Session-Skip, Verwaltung.
- **Sichere Bereinigung**: Operation-Journal vor Systemoperation, genau-einmal-Abgleich,
  `reconciliationRequired` nach Crash, keine automatische Wiederholung, Free-Limit 15 mit atomarer
  Reservierung; PhotoKit-Löschung und endgültiges Datei-Löschen getrennt bestätigt.
- **Dateien**: security-scoped Bookmarks, koordinierter Scan ohne Symlinks, sichere Pfadauflösung,
  kein rekursives Löschen, Quick Look, iCloud-Drive-Ordner abgelehnt.
- **Duplikate**: Größe → Teilhash → Streaming-SHA-256; PhotoKit nur einfache Assets, ohne Netzwerk.
- **Ehrliche Zahlen**: unbekannte Größen bleiben unbekannt, keine „x GB freigegeben“, Speicher A/B/C.
- **Monetarisierung**: zentrale Capability-Auflösung, RevenueCat-Gateway, Rewarded idempotent.
- **Design System** nach den hellblauen Referenzen, Liquid Glass nur für schwebende Controls.
- **Unterlagen**: `CLAUDE.md`, `docs/*` (12 Dokumente), `docs/reference/` (Mockups).

## Bekannte Abweichungen von den Mockups

Siehe `docs/REFERENCE_MAP.md`. Wichtigste: keine GB-Angaben je Fotokategorie (ohne private API unbekannt),
keine Permission-Toggles, kein Beispielpreis, keine „Similar/Blurry“-Erkennung (keine KI).

## Artefakte

- Commit: siehe `git log` auf Branch `claude/photomaid-ios-phase0` (lokal, **nicht gepusht**).
- Kein App-Build-Artefakt (kein Xcode). Quellstand-Hash: `git archive HEAD | sha256sum`.

## Unabhängiger Review – Befunde und Behebung

| # | Befund | Behebung |
|---|---|---|
| 1 | `DuplicateGroup` ohne public init (Compilerfehler) | public init in PhotoMaidCore |
| 2 | Trailing Closure in `if let … await Task.detached {}.value` (Parse-Fehler) | Task vorher binden |
| 3 | UI-Tests nicht `@MainActor` (Swift 6) | Klasse `@MainActor`, `setUp() async throws` |
| 4 | PhotoKit-Callbacks auf Hintergrundqueues in MainActor-Kontext (Laufzeit-Assert) | Closures explizit `@Sendable` |
| 5 | Schneller zweiter Tap konnte Entscheidung auf falsches Item legen | `isCommitting`-Sperre + Item-Gleichheitsprüfung |
| 6 | Vollständiger Seitwärts-Swipe in Listen löste „Behalten“ aus | `allowsFullSwipe: false` |
| 7 | Rewarded-Vorschau lief bis zum nächsten Resume weiter | Capabilities mit aktueller Zeit, 30-s-Tick |
| 8 | Existenzprüfung umging Pfadschutz | `containedURL`, sonst `unknown` |
| 9 | Hintergrundaufgabe registriert, aber wirkungslos | entfernt; Prüfung bei Start/Resume |

## Restpunkte

Vollständig in `docs/RELEASE_BLOCKERS.md`. Der nächste Schritt ist der erste echte Build auf macOS
(`docs/IMPLEMENTATION_STATUS.md` → „Nächster konkreter Schritt“).
