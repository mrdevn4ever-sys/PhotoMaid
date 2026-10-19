# Snake-Spielfeld und iCloud für Paare/Snake – 19.10.2026

Auftrag: größeres bestehendes Snake-Spielfeld, Tempovergleich, iCloud-Ladefehler beider Spiele
beheben und anschließend einen geprüften internen TestFlight-Build bereitstellen.

**Erledigt: PhotoMaid 1.0, Build 17 ist von Apple verarbeitet und intern in TestFlight verteilt.**
Upload **04:47:52 UTC**, Apple-Bestätigung **04:50:26 UTC**, jeweils am 19.10.2026.
[Upload-/Privacy-Bericht und Originalbelege](testflight/README.md).

## Änderungen

- Snake reserviert 20 statt 42 pt Rand. Die äußeren Zellzentren und begrenzte Portal-Kopien
  halten Fotos und den drehenden Kopf vollständig innerhalb der Szene. Raster und Rendering
  verwenden weiterhin dieselbe Geometrie; aktive Runden ändern ihre Kollisionsgröße beim
  Fensterwechsel nicht. Runde Fotos, 12,5 % Überlappung, dünne Rahmen und 44–50 pt bleiben erhalten.
- Beispiel 402 × 874 pt: vorher 8 × 20 Zellen / 316 × 790 pt, jetzt 9 × 21 Zellen /
  ungefähr 357 × 834 pt. Rund 19 % mehr nutzbare Spielfeldfläche.
- Normal bleibt **0,22 s pro Schritt**. Vergleich mit `e9da9db` (Build 15) und dem seit Build 11
  unveränderten `PhotoGameRecords.swift`: keine Tempoänderung. Sanft 0,32 s, schnell 0,14 s.
- Paare/Snake laden Vorschauen über den vorhandenen zweistufigen PhotoKit-Weg: lokale Vorschau,
  dann ausdrücklich netzwerkerlaubter iCloud-Versuch, auch wenn PhotoKit kein Cloud-Flag liefert.
  Ein brauchbares lokales 256-px-Bild beendet die Anfrage ohne Originaldownload. Bei einem
  Cloud-Fehler bleibt eine vorhandene kleinere Vorschau nutzbar, statt die gesamte Auswahl zu
  verwerfen. Der bisherige Einzelaufruf ignorierte degradierte Vorschauen.
- Snake-PhotosPicker fordert die aktuelle Dateirepräsentation an und vermeidet zusätzliche
  Formatkonvertierungen beim Import aus iCloud. Bestehendes lokales Galeriearchiv bleibt erhalten.
- Die zentrale Zulässigkeitsprüfung bleibt vor/nach dem Laden erhalten; keine externen Foto-Uploads.
  Blocks behält seinen bestehenden sicheren Zwei-Bilder-Hintergrundcache und iCloud-Ladeweg.

## Prüfungen

- **PASS:** 499 lokale Core-Tests (475 Swift Testing, 24 XCTest), einschließlich vergrößerter
  Felder auf fünf iPhone-Flächen, unverändertem Tempo, Rand/Portal, Kopfrotation, 300 Segmenten,
  Wachstum/Kollisionen sowie Blocks-Regressionsfällen. Original: `core-tests.log`.
- **PASS:** Syntaxprüfung sechs geänderter nativer Swift-Dateien; kein Ersatz für SDK-Typechecking.
- **PASS:** Ressourcen-/Regel-/Rekord-/Lokalisierungsaudits und Shell-/Whitespace-Prüfung.
  Historischer Blocks-Snake-Baseline bleibt unverändert; drei ausdrücklich beauftragte Snake-Dateien
  sind im Quellaudit als Folgeauftrag ausgewiesen.
- **PASS:** [native CI 39181482674](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39181482674),
  Quellstand `575313d9f1f9a6f2a806bc87b19060f0379bcd3a`, Xcode 26.6 / SDK 26.5.
  82 native Unit-Tests (69 Swift Testing + 13 XCTest), kein Fehler. Alle sechs neuen
  PhotoKit-Callback-Tests bestanden. Linux-CI bestätigt zusätzlich alle 499 Core-Tests.
- **PASS:** iPhone 17 / iOS 26.2 **3/3 UI-Tests** und iPad mini (A17 Pro) / iOS 26.4.1
  **3/3 UI-Tests**, jeweils ohne Fehler oder Skip. Geprüft: iCloud-Vorgabe und bewusster Opt-out,
  echte PhotoKit-Vorschaubilder der Simulatorbibliothek, 24 Paare-Karten, manuelle leere
  Snake-Auswahl, Fullscreen-Swipe-Steuerung, Wachstum/Score/Rekord, Fortsetzen, echte Spieluhr,
  Pause bei App-Unterbrechung und korrekte Rückkehr zur Spieleauswahl/hellen Paare-Ansicht.
- **PASS:** alle 28 nativen PNGs visuell angesehen (26 App-Checkpoints, zwei Systemdialoge).
  Originaldateien und 28 zugehörige Textbelege unter `native/`, SHA-256 und ursprüngliche
  Exportnamen in [captures.json](native/captures.json). Das große Fenster ist keine Faltgeräteabnahme.
- **CANCELLED:** erster Lauf `39181328945` auf `b54d913`, vor der Abnahme zugunsten der
  zusätzlich abgesicherten Wandkollision abgebrochen; zählt nicht als bestandener Prüflauf.
- **PASS:** [interner TestFlight-Lauf 39200627021](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39200627021)
  baut exakt denselben nativ geprüften App-Quellstand. Zusätzlicher Unit-Durchlauf im Upload-Job
  bewusst deaktiviert; Signatur, Release-Archiv, Export, IPA-Privacyprüfung und Apple-Verarbeitung
  wurden tatsächlich ausgeführt. Version **1.0 (17)** ist von Apple verarbeitet und intern verteilt.

Native Aufnahmen:

- [Vergrößertes iPhone-Spielfeld](native/iphone/snake_02_fullscreen_ready_dark.png)
- [Wachstum und Rekord](native/iphone/snake_03_fullscreen_collected_record_dark.png)
- [Pause und eindeutige Aktionen](native/iphone/snake_realtime_fullscreen_paused.png)
- [iCloud standardmäßig an bei Paare](native/iphone/pairs_setup_default_cloud_on.png)
- [Großes Spielfeld und Fotos am Rand](native/expanded-window/snake_simple_setup_real_photo_game.png)

Ein echter Download aus einer angemeldeten privaten iCloud-Mediathek und physische Geräte-FPS
sind in dieser Umgebung nicht prüfbar. Native Callback-Tests prüfen die tatsächliche verwendete
Anfragelogik; sie sind kein Test eines realen iCloud-Kontos. Keine Fotos, Rekorde oder Secrets gelöscht.

## Geänderte Implementierungsdateien

- `Sources/PhotoMaidCore/Games/PhotoSnakeLayout.swift` – Rand, Kopf-Freiraum, sichere Portalpositionen.
- `PhotoMaid/Features/Snake/PhotoSnakeBoard.swift` – Renderer verwendet angepasste Portalgeometrie.
- `PhotoMaid/Features/Snake/SnakeGalleryView.swift` – PhotosPicker-Dateirepräsentation.
- `PhotoMaid/Infrastructure/PhotoLibrary/PreviewPipeline.swift` – wiederverwendete lokale/iCloud-Vorschau.
- `PhotoMaid/Features/Games/PhotoGamePhotos.swift` – beide bestehenden Spiel-Ladewege verwenden sie.
- `PhotoMaidTests/PreviewRecoveryTests.swift` – Cloud-Recovery, lokale Qualität, Fallback,
  Opt-out, Abbruch und Vorbereitung beider Spiele.
- `PhotoMaidTests/PhotoSnakeModelTests.swift`, `Tests/PhotoMaidCoreTests/PhotoSnakeGameTests.swift`,
  `Tests/PhotoMaidCoreTests/PhotoSnakeReadableLayoutTests.swift` – Raster-/Rand-/Tempo-Regressionen.
- `scripts/ci/game_visual_tests.sh` – gezielter manueller Lauf `snake-cloud`.
- `scripts/check_photo_blocks.py`, `CLAUDE.md` – expliziter neuer Auftragsumfang.
- `docs/snake-cloud-20261019/` und `docs/IMPLEMENTATION_STATUS.md` – Prüfbericht und Originalbelege.

Die nativen Build-/Testprotokolle stehen unter `native/`, Release-/Apple-Belege unter `testflight/`.
