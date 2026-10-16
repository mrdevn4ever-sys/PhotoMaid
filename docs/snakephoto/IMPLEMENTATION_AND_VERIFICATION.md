# SnakePhoto und Memory – Implementierung und Prüfnachweise

> **Historischer Erstbericht vor der anschließenden TestFlight-Freigabe.** Die unten genannten
> Einschränkungen „kein iOS-Build / keine Actions“ beschreiben ausschließlich diesen früheren Stand.
> Nach „Testfloght build“ wurden native Builds und Simulator-Tests tatsächlich ausgeführt und
> gefundene Compiler-, Barrierefreiheits- und Layoutfehler korrigiert.
> Der aktuelle Status steht in [TESTFLIGHT_VERIFICATION.md](TESTFLIGHT_VERIFICATION.md) und
> [NATIVE_QA_MATRIX.md](NATIVE_QA_MATRIX.md); Originalbelege liegen unter [native-qa](native-qa/).

Stand: 16.10.2026. **Quellcode umgesetzt; native Abnahme offen.**
Kein erfolgreicher iOS-Build, keine visuelle Abnahme und keine erreichten 60 FPS werden behauptet.
Keine GitHub Actions, bezahlten Runner/APIs, TestFlight-Uploads oder App-Store-Aufrufe gestartet.
Alles befindet sich im vorhandenen PhotoMaid-Projekt und auf dem vorhandenen Branch.

## Ergebnis

- Snake wird ausschließlich mit Wischgesten gesteuert. Kein D-Pad, keine optionale Richtungstasten-Einstellung.
  VoiceOver behält benannte, nicht sichtbare Richtungsaktionen und den bestehenden Schrittmodus.
- `PhotoSnakeGame` bleibt bytegleich zur Ausgangsbasis: Kollision, zwei gepufferte Kurven, Wachstum,
  Relaxed-Randumlauf, Classic-Wände, Sieg und Punkte bleiben im vorhandenen Modell.
- Der vorhandene `PhotoSnakeBoard` hostet jetzt SpriteKit. Ein einziger Taktgeber in `update(_:)`,
  zeitbasierte Positionsinterpolation auf einer begrenzten Arc-Length-History, organischer Körperpfad hinter
  aufrechten Fotokreisen, gepoolte Sprites, getrennte Randkopien auch an Ecken. Kein Crop-Node pro Segment.
  Rastergröße und Score einer aktiven Runde werden beim Fensterwechsel bewahrt.
- Cartoon-Köpfe Schlange/Drache/Dino/Monster; Idle, Blinzeln, Zunge, Blick, Essen, Gefahr, Schlaf,
  Hurt/Dead mit vorhandenen Kit-Frames. Drehung über den kürzesten Winkelweg in ca.130ms.
  Die sichtbare Kollision endet vor der Game-Over-Meldung; Reduce Motion schaltet Zusatzbewegungen ab.
- PhotosPicker-Mehrfachauswahl bis 100 Bilder, geordnete Auswahl, Drag-Reorder, Entfernen und VoiceOver-Aktionen.
  Ausgewählte Dateien werden über ImageIO EXIF-korrigiert auf höchstens 256px reduziert und als JPEG gespeichert.
  Keine Originaldateien dauerhaft, keine Foto-Uploads, keine neuen Backend-/Trackingaufrufe.
  Runde bleibt bei Galerie-/Einstellungssheets erhalten und pausiert.
- UUID-Dateien und atomarer Galerieindex im lokalen Application Support, `NSFileProtectionComplete`,
  aus Backups ausgeschlossen; temporäre Originalübertragungen werden gelöscht und Crash-Reste beim nächsten
  Öffnen bereinigt. Fehlende Bilder ergeben Platzhalter, Fehler werden angezeigt. Löschen entfernt lokale
  Bytes und komponierte Texturen; verwaiste Dateien werden beim Laden bereinigt.
  Nur über PhotosPicker importierte Kopien bleiben nach Entzug des allgemeinen PhotoKit-Zugriffs nutzbar;
  das entspricht dessen einzelner Dateifreigabe. Bekannte Tresor-Quellkennungen werden weiterhin ausgeblendet.
- Bestehende Zufallsquellen Mediathek/Favoriten/Album bzw. Ordner bleiben explizit verfügbar, weiterhin
  mit bestehenden PhotoKit-/Sichtbarkeitsfiltern und begrenzten Vorschauen. Keine beliebigen Galerieimporte beim Essen.
- Waldmenü, Tag/Nacht, HUD mit Punkten/Rekord, Pause, Galerie, Skin-/Sound-/Futtereinstellungen und Game Over.
  Neun Futterbilder sind reine Grafikvarianten. Alle sechs Sounds sind eingebunden; Silent Mode,
  andere Audiowiedergabe und die globale Haptikeinstellung werden berücksichtigt.
- Bestehender Rekordschlüssel `games.personalRecords.v1` bleibt erhalten. Neue Snake-Einstellungen unter
  `games.snake.preferences.v1`; keine Änderung an Bundle-ID, Signing, Käufen, Ads, Feed oder Originalfotos.
  Das Menü zeigt den höchsten Bestwert für Modus/Tempo/Schrittsteuerung über Fenstergrößen hinweg;
  im laufenden Spiel gilt unverändert die genaue Rasterkategorie.
  Speicherwarnungen pausieren und geben komponierte Fototexturen frei; Hintergrund/Anruf pausieren ebenfalls.
- Memory: Ein offenes Fehlpaar blockiert geschlossene Karten nicht mehr. Eine neue bewusste Auswahl
  schließt das alte Fehlpaar und öffnet genau die neue Karte. Automatisches Schließen funktioniert auch
  auf einem scrollbaren Brett; alte Timer prüfen Runde und Kartenpaar. Ganze Kartenfläche ist tippbar.
  Bestehende Bestzeitkategorien bleiben erhalten; vorzeitiges manuelles Schließen wird separat gewertet.

## Tatsächlich ausgeführte Prüfungen

| Prüfung | Ergebnis | Beleg / Grenze |
|---|---|---|
| Gesamte Core-Suite, Swift 6.4 im lokalen Docker | **PASS: 461 Tests**, 437 Swift Testing + 24 XCTest, 0 Fehler | `validation/core-tests.log`; kein iOS-Testhost |
| Gezielte Snake-/Memory-Core-Tests | **PASS: 29 Tests / 4 Suites** | `validation/game-tests.log` |
| Pfad mit ≥303 Körperzellen, Wachstum, Kurven und Wrap | **PASS: Core** | Tests mit unverändertem autoritativem Spiel, kein GPU-/FPS-Test |
| Galerie 0/1/10/100, zyklische Ordnung, Umordnen, Löschen, Shuffle | **PASS: Core** | `PhotoSnakeGalleryTests`; Bilddekodierung benötigt iOS |
| Lokale Archivdateien, erneutes Öffnen, Größenlimit, fehlende Bilder, Crash-Reste, beschädigter Index, Symlink-Lesezugriff | **PASS: Core** | echte temporäre Dateien; kein vorgetäuschter UIKit-Test |
| Animationszustände, Priorität, Timing, kürzester Drehwinkel, Preferences-Roundtrip | **PASS: Core** | `PhotoSnakePresentationTests`; Darstellung nativ offen |
| Alle 77 Ressourcen, SHA-256, 71 PNG / 6 WAV, PNG-Alpha/-Maße, Target-Einträge und Namen | **PASS: statisch** | `scripts/check_snakephoto_integration.py`, `ASSET_INTEGRATION.json`, `validation/resource-audit.log` |
| Lokalisierung | **PASS: 16 Sprachen, 2690 Einträge**, 2657 bestehende Einträge unverändert | `validation/localization.log`; 33 neue Texte |
| Swift-Dateien des App-/Unit-/UI-Targets | **PASS: Syntax-Parse, 170 Dateien** | `validation/swift-parse.json`; ausdrücklich keine SDK-Typprüfung |
| iOS-Build / XcodeGen / kompilierte App-Ressourcen | **BLOCKED** | Linux, kein Xcode/iOS-SDK |
| Neue/erweiterte native Unit- und UI-Tests | **NOT RUN / BLOCKED** | Dateien liegen im vorhandenen Test-Target |
| Tatsächliche Screenshots, FotosPicker/iCloud, Gerät, 60/120Hz und gemessene FPS | **BLOCKED** | `NATIVE_QA_MATRIX.md`; keine neuen Simulator-/Gerätebilder vorhanden |

Die Resource-Prüfung kontrolliert Quellressourcen und XcodeGen-Einträge. Ob Xcode die Atlanten tatsächlich
korrekt kompiliert und der iOS-Testhost sie lädt, prüft erst `SnakePhotoIntegrationTests` auf macOS.
Unveränderte Store-/Werbe-/Feed-Dateien plus grüne Core-Regressionen ersetzen keinen nativen App-Smoke-Test.

## Dateien und Zweck

- `PhotoMaid/Features/Snake/PhotoSnakeModel.swift`, `PhotoSnakeBoard.swift`, `PhotoSnakeView.swift`:
  vorhandene Modell-/Ansichtswege erweitert, alter Canvas-/Kamerakopf und Task-Takt ersetzt.
- `SnakeArt.swift`, `SnakePhotoLibrary.swift`, `SnakeGalleryView.swift`, `SnakeAudio.swift`:
  Kit-Anbindung, einmalige Texturkomposition, lokale Fotoauswahl, Thumbnail-Speicherung und Audio.
- `Sources/PhotoMaidCore/Games/PhotoSnakeMotion.swift`, `PhotoSnakeStyle.swift`, `PhotoSnakeGallery.swift`:
  reine Darstellungsmathematik, Animation/Preferences sowie Reihenfolge und serialisierter Dateispeicher.
- `PhotoMaid/Features/Memory/PhotoMemoryModel.swift`, `PhotoMemoryView.swift`, Core-`PhotoMemoryGame.swift`:
  blockierte Kartenauswahl und veraltete Fehlpaar-Timer behoben.
- `AppModel.swift`, `KeyValueStore.swift`, `PhotoGamesView.swift`: bestehende App-Anbindung und neuer Einstellungskey,
  Spielauswahl mit Kit-Kopf statt Kameraplatzhalter.
- `PhotoMaid/Resources/SnakePhoto/`, `project.yml`: 77 unveränderte Originalressourcen in vier Atlanten,
  Hintergründe und Sounds im bestehenden App-Target; SpriteKit-Abhängigkeit.
- `Tests/PhotoMaidCoreTests/PhotoSnakeGalleryTests.swift`, `PhotoSnakePresentationTests.swift`,
  `PhotoMemoryGameTests.swift`: zusätzliche tatsächlich ausgeführte Core-Regressionsfälle.
- `PhotoMaidTests/SnakePhotoIntegrationTests.swift`, `PhotoSnakeModelTests.swift`, `PhotoMemoryModelTests.swift`,
  `PhotoMaidUITests/PhotoGameVisualTests.swift`: native Integration/Regression, hier **nicht ausgeführt**.
- `scripts/i18n/ios_strings_part16_snakephoto.py`, `ios_strings.json`, `Localizable.xcstrings`:
  33 neue Texte in allen 16 App-Sprachen. Der Lokalisierungsprüfer erkennt die vorhandenen Kit-Dateinamen
  ausdrücklich als Ressourcen statt fälschlich als Übersetzungskennungen.
- `scripts/check_snakephoto_integration.py`, `docs/snakephoto/*`: reproduzierbare Integration,
  Ausgangsinventar, Kit-Lizenz/Anforderungen und ehrliche Prüfnachweise.
- `CLAUDE.md`: aktuelle Kosten- und Swipe-only-Vorgabe gegen ältere allgemeine Freigaben festgehalten.

## Sicherung und Commits

Ausgangsbasis `4bfba4f`, Sicherungsbranch `backup/snakephoto-before-20261016-4bfba4f`.
Memory-Fix: `a317a73` – `Fix Memory cards staying blocked after a mismatch`.
Der folgende lokale SnakePhoto-Commit enthält Implementierung und diesen Bericht; den Hash liefert `git log`.
Kein Push und kein Workflow-Dispatch.

## Noch offene Abnahme

Erst nach einem echten iOS-Build und den nativen Schritten der QA-Matrix ist der gesamte Masterprompt
abgenommen. Es fehlen insbesondere SDK-Typprüfung, tatsächliches SpriteKit-/PhotosPicker-Verhalten,
visuelle Prüfung aller Ansichten, Geräte-Sound/Silent Mode und gemessene 60 FPS. Diese Schritte werden
wegen der ausdrücklich gesperrten CI-/Runner-/Upload-Aufrufe hier nicht ausgelöst.
