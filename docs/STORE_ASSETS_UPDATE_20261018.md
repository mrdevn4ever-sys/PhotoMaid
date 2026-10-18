# Aktualisierung der Store-Assets – 18.10.2026

**Status: IN PROGRESS.** Maßgeblich sind die tatsächlich vorhandenen Dateien und
[Audit-Ergebnisse](../app-store/current/audit.json), nicht die Zahl gestarteter Jobs.
[Aktuelle Sprachübersicht](../app-store/current/README.md).

## Umfang

Alle 16 App-Sprachen erhalten aktuelle Aufnahmen des bestehenden Projekts mit Foto-Snake
und Memory. Die ursprüngliche Sammlung vom 15.10.2026 bleibt unverändert als
[Seitenarchiv](../app-store/INDEX.md) erreichbar. Kein neues Repository und keine neue App.

Ziel für die normalen iPhones: **320 ausgewählte Screenshots**, je zehn pro Sprache
und Format, **48 ausgewählte Vorschauen** und **16 Tresor-Alternativen**. Apple erlaubt
höchstens drei Vorschauen gleichzeitig je Sprache/Geräteformat. Die zusätzliche
Tresor-Vorschau ist eine Alternative und kein viertes gleichzeitig vorgesehenes Video.

| Format | Tatsächliches Gerät | Upload-PNG |
|---|---|---|
| `iphone-large` | iPhone 17 Pro Max / iOS 26.2 | 1320 × 2868 |
| `iphone-medium` | iPhone 17 Pro / iOS 26.2 | 1206 × 2622 |

Die Auswahl zeigt Heute, Feed, Fotos, Aufräumen, Foto-Snake, Memory, Collage, Fotoeditor,
Fotofilm und Tresor. Videos: `01-review.mp4`, `02-photo-games.mp4`, `03-studio.mp4`;
zusätzlich `alternatives/04-vault.mp4`. Gemeinsames iPhone-Vorschauformat: 886 × 1920,
H.264, 30 fps, AAC-Stereo mit 48 kHz und Stille, 15–30 Sekunden.

## Nachweise

- Aktuell bestanden und visuell geprüft: **neun Geräte-/Sprachserien**, 90 ausgewählte
  Screenshots, 15 ausgewählte Videos und fünf Tresor-Alternativen. Englisch/mittel
  stammt aus dem erfolgreichen Pilot; jeder akzeptierte native Fall hat 0 FAIL und 0 SKIP. [Originaler Herkunftsbericht](../app-store/current/locales/en/iphone-medium/provenance.json),
  [Sichtprüfung](../app-store/current/locales/en/iphone-medium/review/manifest.json).
- Große iPhones in allen 16 Sprachen: [Lauf 39120101094](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39120101094).
  Mittlere iPhones in den übrigen 15 Sprachen: [Lauf 39120189289](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39120189289).
  Beide verwenden Quellstand `bbf8999a9e0f4da13d02f598e7402a4bb2a1bf1d`.
  Die noch ausstehenden alten Jobs wurden nach zwei abgelehnten Heute-Bildern gestoppt;
  die bereits geprüften Serien bleiben erhalten.
- Fünf lokale Prüfungen der Evidenzvalidierung bestehen. Ein isolierter synthetischer
  Codec-Test hat den Videoexport mit vollständiger Bild-/Tondekodierung geprüft:
  der Spieleclip hat exakt 27 Sekunden und 810 Bilder. Diese Testmuster gehören
  **nicht** zu den nativen App-Aufnahmen; [getrennter Format-Prüfbericht](../app-store/current/validation/local-export-format-smoke.json).

Erst nach visueller Kontrolle der unveränderten Bilder und tatsächlichen Videobildstichproben
werden Prüfblätter auf PASS gesetzt. Ein grüner Workflow-Schritt genügt nicht: der Audit
verlangt die korrekte Zahl bestandener nativer Fälle, keine Fehler/Skips, die genaue
55-Foto-Mediathek, übereinstimmende Prüfsummen und unveränderte Upload-Pixel ohne Alpha-Kanäle.

Memory-Paare werden ausschließlich durch echte Kartentipps gefunden. Der Test lernt keine
verdeckten Kartenwerte. Snake verwendet echte PhotoKit-Vorschauen, seine normale Spieluhr
und Wischgesten; keine Schrittuhr oder erfundenen Punkte. Der Spieleclip kombiniert acht
Sekunden Memory und 16 Sekunden Snake bei normalem Tempo und hält das echte Schlussbild
drei Sekunden. Die bestehenden separaten Foto- und Video-Entscheidungen bleiben erhalten.

Die Fotos stammen aus dem bereits belegten CC0-Bildsatz; persönliche Mediatheken werden
nicht benutzt. Beim echten Tresorimport werden die Systemlöschungen stets abgelehnt.
Ein beiläufig erfasster Systemhinweis in einer nicht ausgewählten Einrichtungsszene bleibt
als Original archiviert und ist ausdrücklich für Store-Uploads ausgeschlossen. Der Audit
weist jede solche Datei in der Upload-Auswahl zurück.

## Beobachtete Zähler-Race und neue Aufnahmen

Spanisch/groß und Italienisch/mittel wurden trotz bestandener nativer Aufnahmefälle
visuell abgelehnt: der Heute-Hero zeigte 55 offene Medien, der Foto-Schnellzugriff
jedoch noch „Leer“. Die unveränderten Fehlerbilder und Herkunftsnachweise stehen unter
`app-store/current/validation/rejected-*-today/`; die gesamten ursprünglichen
Artefakte bleiben im jeweiligen Actions-Lauf. Sie gehören nicht zur freigegebenen Auswahl.

`QuickAccessSection.recount()` prüft jetzt nach der ausgelagerten Abfrage die
Task-Abbruchmarkierung, damit ein überholtes leeres Ergebnis keinen neueren Zähler
überschreibt. Das ist ein Schutz gegen eine im Quellcode vorhandene mögliche Race;
die genaue zeitliche Reihenfolge der ursprünglichen Runner-Abfragen wurde nicht
aufgezeichnet. Der Aufnahmetest wartet zusätzlich über eine semantische Kennung auf
den tatsächlich sichtbaren Wert 55 der unabhängig inventarisierten Fotomediathek.
Keine Zahl wird in die App injiziert. Neuer Quellstand: `6a86a77`.

Native Korrektur-Piloten: Spanisch/groß [39124084071](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39124084071),
Italienisch/mittel [39124085765](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39124085765).
Status der neuen nativen Validierung: **IN PROGRESS**; kein Erfolg vor Abschluss behauptet.
Danach werden die fehlenden Sprachen auf dem korrigierten Stand fortgesetzt.

## Duo

Der bisherige `macos-26`-Runner hat Xcode 26.6 und keinen Duo-Simulator. Zusätzlich wurde der
neu verfügbare offizielle GitHub-Runner `xcode-27` geprüft: Xcode 27.1, Build 27A9275,
genuiner Gerätetyp `com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`, Mindest-Runtime 27.1.
Vorinstalliert ist dort bislang iOS 27.0. Die offizielle Runtime-Vorbereitung läuft separat:
[39120476761](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39120476761).
[Aktueller Duo-Status](../app-store/current/DUO_STATUS.json).

Es wird kein iPad oder umbenanntes/vergrößertes iPhone als Duo-Store-Aufnahme ausgegeben.
Die tatsächlichen Duo-Aufnahmen hängen von der erfolgreichen Runtime-Vorbereitung und
nativen Geräteprüfung ab. Eine echte physische Faltabnahme oder Hardware-FPS-Messung
ist damit nicht behauptet.

## Reproduzieren

`ci.yml` bleibt manuell: `ui_phase=store-refresh`, `store_locales=all` oder Sprachliste,
`store_devices=iphone-large` bzw. `iphone-medium`. Der gemeinsame native Testbuild wird
einmal erstellt. Jedes Gerät erhält eine eigene überprüfte 55-Foto-Mediathek. Quellen
werden vor dem Export archiviert, damit ein Exportproblem keine Wiederholung bestandener
Aufnahmen erfordert. Lauf, Commit, Gerät, tatsächliche Ergebnisse und Artefakt-Hashes
stehen beim jeweiligen Sprachsatz.

App-Store-Connect-Asset-Upload und App-Veröffentlichung: **NOT RUN** in diesem Auftrag.
Der zuletzt von Apple verarbeitete interne TestFlight-Build bleibt 1.0 (14).
