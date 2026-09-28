# PhotoMaid-iOS: verbindliche Regeln

Native iPhone-App (iOS 27, Swift 6, SwiftUI, Liquid Glass). Neubau.
Kein Flutter, Dart, Kotlin, React Native, keine WebView-Oberfläche.

## Gesten (FEST, tatsächliche Fingerbewegung)

| Finger | Bedeutung | Danach |
|---|---|---|
| hoch | **Behalten** (echte Entscheidung) | nächstes Medium |
| links | **Papierkorb** (PhotoMaid-eigen, nichts gelöscht) | nächstes Medium |
| rechts (gerade oder schräg nach unten, ≤ 45°) | **Später** mit Standardtermin (Einstellung, Vorgabe 2 Tage) | nächstes Medium + kurze Pille „In 2 Tagen wieder · Ändern“ |
| schräg rechts oben (≈ 25°–50°) | **Später, Datum selbst wählen** | nächstes Medium + Drehrad (Tage/Wochen/Monate oder Kalender); Abbrechen = Standardtermin |
| runter | **Vorheriges Medium** (keine Entscheidung, kein Undo) | – |

- Zwischen rechts-oben und hoch sowie rechts-unten und runter liegen Totzonen (keine Aktion).
- Keine Aktions-Buttons im Feed (nur bei VoiceOver/Schaltersteuerung). Gestenhilfe blendet beim
  Öffnen kurz ein und von selbst aus (abwählbar); Rückgängig oben in der Kopfzeile.

- Nichts tun = keine Entscheidung. Kein Keep aus onAppear/onDisappear, Scrolloffset,
  programmatischem Springen, Rotation, Hintergrund, Videoende.
- Eine Geste bewirkt maximal einen Schritt. Commit trägt Item-ID, Revision, Command-ID, Aktion.
- Eine einzige Gesture-/Decision-State-Machine: `PhotoMaidCore/Feed/FeedGestureMachine.swift`.

## Verbote

- Keine automatische Löschung. Regeln erzeugen nur Review-Aufgaben.
- Kein Backend, kein Konto, kein CloudKit, kein Upload, keine KI/ML/Vision/Core ML.
- Keine privaten APIs (z. B. `value(forKey: "fileSize")`), keine undokumentierten Settings-URLs.
- Keine erfundenen Zahlen: keine „x GB freigegeben“ aus Kandidatengrößen, unbekannte Größe ≠ 0.
- Keine simulierten Scans, Berechtigungen, Käufe; keine toten Buttons in Produktion.
- Synthetische Daten nur in Previews, Tests, QA-Builds (`QAFixtures`).
- Keine Medien, Hashes, Dateinamen, Pfade, IDs an RevenueCat/Werbung.
- Kein automatischer Push/Merge/TestFlight/Release.

## Architektur in Kürze

- `PhotoMaidCore` (Swift Package, plattformneutral, auf Linux testbar): Domain, State Machines,
  Ledger, Allowance, Operation Journal, Duplikate, Regeln, Capabilities.
- `PhotoMaid/` (App-Target, nur iOS): SwiftUI-Features, Design System, Infrastructure
  (PhotoKit, Dateien, AVPlayer, RevenueCat, Rewarded, Notifications), Core-Data-Persistenz.
- Eine Wahrheit je Zustand: Entscheidungen = Core Data über `LedgerPersistence`.
- UI-Texte ausschließlich über `Localizable.xcstrings` (Deutsch zuerst).

## Befehle

```sh
swift build && swift test            # PhotoMaidCore (Linux/macOS)
xcodegen generate                    # erzeugt PhotoMaid.xcodeproj aus project.yml (macOS)
xcodebuild -scheme PhotoMaid -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Status: `docs/IMPLEMENTATION_STATUS.md`. Blocker: `docs/RELEASE_BLOCKERS.md`.
Prüfstatus immer PASS / FAIL / NOT RUN / BLOCKED. Ein Build ist keine Geräteabnahme.
