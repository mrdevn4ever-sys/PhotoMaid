# PhotoMaid-iOS: verbindliche Regeln

Native iPhone-App (iOS 26+, Swift 6 strikte Concurrency, SwiftUI + Observation, Liquid Glass).
Funktionale Referenz: Android-App `mrdevn4ever-sys/photomaid-android` (Funktionsmatrix `docs/IOS_FUNKTIONSMATRIX.md`).
Kein Flutter, Dart, Kotlin, React Native, keine WebView-Oberfläche, keine nachgebaute Android-Oberfläche.
Offene/getroffene Entscheidungen: `docs/IOS_ENTSCHEIDUNGEN.md` (E1–E18) – nichts davon still ändern.

## Gesten (Standardbelegung, tatsächliche Fingerbewegung, wie Android – frei belegbar: Einstellungen › Wischen & Tasten, E18)

| Finger | Bedeutung | Danach |
|---|---|---|
| hoch | **Behalten** | nächstes Medium |
| links | **Papierkorb** (PhotoMaid-eigen, nichts gelöscht) | nächstes Medium |
| rechts (gerade oder schräg nach oben/unten, ≤ 45°) | **Später** mit Standardtermin (Vorgabe 2 Tage) | nächstes Medium + Pille „In 2 Tagen wieder · Ändern“ |
| runter | **Vorheriges Medium** (keine Entscheidung) | – |

- Keine Diagonalgeste (E2): zwischen 45° und „hoch“ bzw. „runter“ liegen Totzonen. Schwellen wie Android.
- Eine einzige Gesture-/Decision-State-Machine: `Sources/PhotoMaidCore/Feed/FeedGestureMachine.swift`.
- Nichts tun = keine Entscheidung (kein Keep aus onAppear/onDisappear, Scrollen, Rotation, Hintergrund, Videoende).
  Eine Geste = maximal ein Schritt. Commit trägt Item-ID, Revision, Command-ID, Aktion.
- Eigene Belegung (E18, `FeedControls`): je Richtung Behalten, Papierkorb, Später, Später – Termin wählen,
  In Album „…“ legen (= hinzufügen + Behalten, Rückgängig nimmt beides zurück), Zurück oder Nichts. Gesten und Tasten
  nutzen dieselbe Belegung und denselben Weg; die Invarianten oben gelten unverändert. Löschen ist nie belegbar.
- Keine Entscheidungs-Buttons im Feed – außer VoiceOver/Schaltersteuerung oder „Wischen & Tasten › Tasten anzeigen:
  Immer“. Tasten (Auswahl, Reihenfolge, Position frei) rufen exakt `FeedViewModel.perform(action:)`.
  Aktionsleiste ♡ · Teilen · Zu Album · ✏️ · ⋯ ist nie eine Entscheidung.
- „Favoriten schützen“ (Standard an): „Papierkorb“ auf einen Favoriten (gleich welche Richtung oder Taste) fragt nach.

## Verbote

- Keine automatische Löschung. Löschen nur über `PHAssetChangeRequest.deleteAssets` mit Systembestätigung.
- Kein Backend, kein Konto, kein CloudKit, kein Upload, keine Tracker, kein Werbe-SDK (E1 offen), kein Abo.
- Bildanalyse nur mit Apple-Frameworks auf dem Gerät (Vision/VisionKit/Core Image, E7). Ergebnisse sind
  Vorschläge/Filter, nie Entscheidung oder Löschung. Kein LLM, keine Cloud-KI, keine Zusatzmodelle ohne Freigabe (E8).
- Keine privaten APIs (z. B. `value(forKey: "fileSize")`), keine undokumentierten URL-Schemata.
- Keine erfundenen Zahlen: Größen nur gemessen, unbekannt ≠ 0. Keine simulierten Scans, Berechtigungen, Käufe.
  Ausnahme E17 (Nutzerentscheidung 14.10.2026): beim Löschen, in „Große Dateien“ und „Dateien“ steht immer eine Zahl –
  ohne Messung (z. B. nur in iCloud) eine Schätzung aus den eigenen Messungen (`SizeEstimator`), immer als „ca.“.
  Keine toten Buttons in Produktion. Synthetische Daten nur in Previews, Tests, `QA_FIXTURES`.
- Nie verzerren: einpassen oder beschneiden; Größe nur proportional; nie hochskalieren.
- Originale nie ohne ausdrückliche Wahl ändern. Vorauswahl immer „Als Kopie speichern“.
- Keine Zertifikate, Schlüssel, API-Keys im Repo. Kein automatischer Push/Merge/TestFlight/Release.
- **GitHub Actions nur auf ausdrückliche Anweisung des Nutzers** (alle Workflows `workflow_dispatch`).

## Geschäftsregeln (aus dem Android-Quellcode)

- Free: 20 endgültige Entfernungen pro lokalem Tag. Pro: Einmalkauf (StoreKit 2, Non-Consumable), unbegrenzt.
- `hasProToolsAccess` ≠ `hasUnlimitedTrashAccess`. Preis nur `Product.displayPrice`.
- Pro-Test und Video-Bonus nur, wenn E1 entschieden ist.

## Architektur in Kürze

- `PhotoMaidCore` (SwiftPM, plattformneutral, Linux-Tests): Port von `photomaid-android/core`.
- `PhotoMaid/` (App-Target): SwiftUI-Features, Design System, Infrastructure (PhotoKit, AVFoundation, Core Image,
  PDFKit, Vision, StoreKit 2, Notifications, Dateien), Core-Data-Persistenz.
- Eine Wahrheit je Zustand: Entscheidungen = Core Data über `LedgerPersistence`.
- UI-Texte nur über `Localizable.xcstrings` (16 Sprachen, generiert aus Android + `ios_strings.json`), in Swift
  nur `L()`/`LP()`. Neue Kennung immer in allen 16 Sprachen. Gestenpfeile in RTL nie spiegeln.

## Befehle

```sh
export PATH=/opt/swift/swift-6.4.0-RELEASE-ubuntu24.04/usr/bin:$PATH   # Linux-Container
swift build && swift test                                              # PhotoMaidCore
python3 scripts/android_strings_to_xcstrings.py                        # Texte erzeugen
xcodegen generate                                                       # macOS
xcodebuild -scheme PhotoMaid -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Status: `docs/IMPLEMENTATION_STATUS.md`. Blocker: `docs/RELEASE_BLOCKERS.md`. CI/TestFlight: `docs/CI_TESTFLIGHT.md`.
Prüfstatus immer PASS / FAIL / NOT RUN / BLOCKED. Ein Build ist keine Geräteabnahme.
