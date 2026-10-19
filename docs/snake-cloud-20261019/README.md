# Snake-Spielfeld und iCloud für Paare/Snake – 19.10.2026

Auftrag: größeres bestehendes Snake-Spielfeld, Tempovergleich, iCloud-Ladefehler beider Spiele
beheben und anschließend einen geprüften internen TestFlight-Build bereitstellen.

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

## Bisherige Prüfungen

- **PASS:** 499 lokale Core-Tests (475 Swift Testing, 24 XCTest), einschließlich vergrößerter
  Felder auf fünf iPhone-Flächen, unverändertem Tempo, Rand/Portal, Kopfrotation, 300 Segmenten,
  Wachstum/Kollisionen sowie Blocks-Regressionsfällen. Original: `core-tests.log`.
- **PASS:** Syntaxprüfung sechs geänderter nativer Swift-Dateien; kein Ersatz für SDK-Typechecking.
- **PASS:** Ressourcen-/Regel-/Rekord-/Lokalisierungsaudits und Shell-/Whitespace-Prüfung.
  Historischer Blocks-Snake-Baseline bleibt unverändert; drei ausdrücklich beauftragte Snake-Dateien
  sind im Quellaudit als Folgeauftrag ausgewiesen.
- **PENDING:** nativer iOS-Build, native Tests einschließlich sechs neuer PhotoKit-Callback-Fälle,
  echte Simulatoroberfläche auf iPhone und großem Fenster, TestFlight/Apple-Verarbeitung.

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

Nach nativer Abnahme werden Lauf-IDs, echte Screenshots, exakte Ergebnisse und Apple-Status ergänzt.
