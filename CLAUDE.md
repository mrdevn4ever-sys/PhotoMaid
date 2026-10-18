# PhotoMaid-iOS: verbindliche Regeln

Native iPhone-App (iOS 26+, Swift 6 strikte Concurrency, SwiftUI + Observation, Liquid Glass).
Funktionale Referenz: Android-App `mrdevn4ever-sys/photomaid-android` (Funktionsmatrix `docs/IOS_FUNKTIONSMATRIX.md`).
Kein Flutter, Dart, Kotlin, React Native, keine WebView-Oberfläche, keine nachgebaute Android-Oberfläche.
Offene/getroffene Entscheidungen: `docs/IOS_ENTSCHEIDUNGEN.md` (E1–E19) – nichts davon still ändern.

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
- Kein Backend, kein Konto, kein CloudKit, kein Upload, kein Abo. Einziges Werbe-SDK: Google Mobile Ads, nur in Free
  (E1/E19, Nutzerentscheidung 14.10.2026): erst UMP-Einwilligung, dann ATT-Abfrage, dann SDK; Anfragen nie mit Medien,
  Namen, Pfaden, Hashes oder IDs. Echte AdMob-IDs nur über CI (`PM_ADMOB_*`), sonst Googles Test-IDs.
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
- **GitHub Actions sind ausdrücklich freigegeben** (Nutzer, 16.10.2026: „Minutes kannst du jederzeit brauchen“).
  Workflows bleiben `workflow_dispatch`; kein automatischer Merge oder Release.
- **Aktueller SnakePhoto-Umbau (neuer Nutzerauftrag, 16.10.2026): keine GitHub Actions, bezahlten Runner/APIs
  oder TestFlight-Uploads ohne neue ausdrückliche Freigabe. Diese auftragsbezogene Sperre hat Vorrang.**
  Snake-Bewegung ausschließlich mit Wischgesten; keine Richtungstasten, auch nicht optional.
- **Anschließende ausdrückliche Freigabe (16.10.2026: „Testfloght build“):** aktuellen SnakePhoto-/Memory-Stand
  pushen, notwendige native CI-/Spieletests ausführen, Fehler beheben und als internen TestFlight-Build hochladen.
  Keine App-Store-Veröffentlichung oder externe Tester-Verteilung dadurch autorisiert.
- **Erneute ausdrückliche Freigabe (17.10.2026: „Testflight“):** den bereits getesteten Video-Swipe-Fix
  über den vorhandenen Workflow als internen TestFlight-Build hochladen und Apples Verarbeitung prüfen.
  Keine App-Store-Veröffentlichung oder externe Tester-Verteilung dadurch autorisiert.
- **Store-Aktualisierung (18.10.2026: „Mach das für alle sprachen“):** aktuelle native Store-Bilder und
  Vorschauen einschließlich Foto-Snake/Memory für alle 16 Sprachen erzeugen, notwendige manuelle
  Actions ausführen und geprüfte Assets im bestehenden Projekt ablegen. Duo-Aufnahmen nur mit echtem
  passendem Simulator/SDK; Ersatzfenster nicht als Duo-Store-Assets ausgeben. Kein App-Release dadurch.
- **TestFlight-Freigabe (18.10.2026: „Erledigt? Wenn ja mach testflight“):** den geprüften Paare-/Snake-
  Einrichtungsstand einschließlich der letzten Textkorrektur mit dem vorhandenen Workflow als internen
  TestFlight-Build hochladen, vorgeschaltete Unit-Tests und Privacy-Prüfung ausführen und Apples
  Verarbeitung prüfen. Keine App-Store-Veröffentlichung oder externe Tester-Verteilung dadurch.
- **Neuester Snake-Auftrag (18.10.2026: größere Fotos/Vogelperspektive): ausschließlich lokale und
  statische Prüfungen. Keine GitHub Actions oder bezahlten CI-Builds starten. Für diesen Auftrag
  keine Uploads starten; ältere TestFlight-Freigaben gelten nicht für diesen neuen Umbau.**

## Geschäftsregeln (aus dem Android-Quellcode)

- E19 (Nutzerentscheidung 14.10.2026, Abweichung von Android): alle Werkzeuge für alle frei (`hasProToolsAccess` immer
  wahr). Free: 100 endgültige Entfernungen pro lokalem Tag, +100 einmal täglich per Belohnungsvideo (nur nach
  SDK-Callback); Werbung beim Kaltstart ab dem 4. Start; native Werbekarte im Feed nach jeder 50. Entscheidung (nie eine
  Entscheidung); neuer Tresor-Ordner je ein Belohnungsvideo. Pro: Einmalkauf (StoreKit 2, Non-Consumable) = ohne Werbung,
  unbegrenzt entfernen, Tresor-Ordner frei (`isLifetimePro`, `hasUnlimitedTrashAccess`). Kein Pro-Test.
- Preis nur `Product.displayPrice`.

## Architektur in Kürze

- `PhotoMaidCore` (SwiftPM, plattformneutral, Linux-Tests): Port von `photomaid-android/core`.
- `PhotoMaid/` (App-Target): SwiftUI-Features, Design System, Infrastructure (PhotoKit, AVFoundation, Core Image,
  PDFKit, Vision, StoreKit 2, Notifications, Dateien), Core-Data-Persistenz.
- Eine Wahrheit je Zustand: Entscheidungen = Core Data über `LedgerPersistence`.
- UI-Texte nur über `Localizable.xcstrings` (16 Sprachen, generiert aus Android + `ios_strings.json`), in Swift
  nur `L()`/`LP()`. Neue Kennung immer in allen 16 Sprachen. Gestenpfeile in RTL nie spiegeln.
- Spiele-Startansichten (Nutzer, 18.10.2026): einfach und klar beschriften; das Kartenspiel heißt Paare.
  iCloud-Fotos für beide Spiele standardmäßig laden, eine bewusste Abschaltung beibehalten.
  Snake startet mit zufälligen Mediathek-Fotos; eine leere manuelle Auswahl öffnet die Fotoauswahl.
- Neuester Snake-UX-Auftrag (18.10.2026): gut erkennbare Fotogröße beibehalten, runde Fotosegmente
  mit leichter Überlappung und dünnem Rahmen. Klare Start-/Foto-Buttons, „Andere Spiele“, „Score“ und
  „Rekord“. Starten ist ausdrücklich auch per Button möglich; Richtungssteuerung bleibt ausschließlich
  per Wischgeste. iCloud ist unter „Spiel anpassen“. Weiterhin keine Actions, bezahlte CI oder Uploads.

## Befehle

Aktuellster Foto-Blocks-Auftrag (18.10.2026): Foto-Enthüllung und eigene Blocklogik im bestehenden
Spielebereich; ausschließlich lokale Fotos, einschließlich der Auswahldialog-Vorschauen. Tresor,
ausgeblendete und ausgenommene Medien zentral ausschließen. Snake bleibt gegenüber dem Arbeitsstand
vor diesem Auftrag unverändert. TestFlight ist mit „Sobald fertig mach testflight“ ausdrücklich beauftragt.
Anschließend „Du kannst jederzeit minutes brauchen zum testen“: CI-Minuten für native Prüfungen
sind wieder freigegeben; der geprüfte Stand darf über den vorhandenen internen TestFlight-Workflow
gebaut und hochgeladen werden. Keine externe Tester-Verteilung oder App-Store-Veröffentlichung.

```sh
export PATH=/opt/swift/swift-6.4.0-RELEASE-ubuntu24.04/usr/bin:$PATH   # Linux-Container
swift build && swift test                                              # PhotoMaidCore
python3 scripts/android_strings_to_xcstrings.py                        # Texte erzeugen
xcodegen generate                                                       # macOS
xcodebuild -scheme PhotoMaid -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Status: `docs/IMPLEMENTATION_STATUS.md`. Blocker: `docs/RELEASE_BLOCKERS.md`. CI/TestFlight: `docs/CI_TESTFLIGHT.md`.
Prüfstatus immer PASS / FAIL / NOT RUN / BLOCKED. Ein Build ist keine Geräteabnahme.
