# Aktualisierung der Store-Assets – 18.10.2026

> **Hinweis (22.10.2026):** Die hier beschriebenen Aufnahmen (`app-store/locales`, `app-store/current`) wurden auf
> Wunsch entfernt und durch die englischen Store-Einträge im Experiment-Design ersetzt, siehe `app-store/README.md`.
> Sie bleiben in der Git-Historie.

**Archivstand vor der Umbenennung in Paare:** Die folgenden PASS-Werte beschreiben die ursprünglichen nativen Aufnahmen. Spielbilder und Spiele-Vorschauen enthalten noch den bisherigen Namen und müssen für einen neuen Store-Upload nativ neu aufgenommen werden. Die Originale und ihre Prüfsummen bleiben erhalten. [Aktueller Namensstatus](../app-store/current/STATUS.json).

**Normale iPhones: PASS. Duo: BLOCKED.** Maßgeblich sind die tatsächlich vorhandenen Dateien und
[Audit-Ergebnisse](../app-store/current/audit.json), nicht die Zahl gestarteter Jobs.
[Aktuelle Sprachübersicht](../app-store/current/README.md).

## Umfang

Für alle 16 App-Sprachen liegen aktuelle Aufnahmen des bestehenden Projekts mit Foto-Snake
und Memory. Die ursprüngliche Sammlung vom 15.10.2026 bleibt unverändert als
[Seitenarchiv](../app-store/INDEX.md) erreichbar. Kein neues Repository und keine neue App.

Fertig für die normalen iPhones: **320 ausgewählte Screenshots**, je zehn pro Sprache
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

- Aktuell bestanden und visuell geprüft: **32 Geräte-/Sprachserien**, 320 ausgewählte
  Screenshots, 48 ausgewählte Videos und 16 Tresor-Alternativen. Der vollständige
  abschließende Audit aller 32 Serien ist PASS; 96 akzeptierte native Aufnahmefälle,
  jeweils ohne Fehler oder Skip. Die ursprünglichen fehlgeschlagenen Versuche bleiben
  getrennt dokumentiert. Englisch/mittel
  stammt aus dem erfolgreichen Pilot; jeder akzeptierte native Fall hat 0 FAIL und 0 SKIP. [Originaler Herkunftsbericht](../app-store/current/locales/en/iphone-medium/provenance.json),
  [Sichtprüfung](../app-store/current/locales/en/iphone-medium/review/manifest.json).
- Große iPhones in allen 16 Sprachen: [Lauf 39120101094](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39120101094).
  Mittlere iPhones in den übrigen 15 Sprachen: [Lauf 39120189289](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39120189289).
  Beide verwenden Quellstand `bbf8999a9e0f4da13d02f598e7402a4bb2a1bf1d`.
  Die noch ausstehenden alten Jobs wurden nach zwei abgelehnten Heute-Bildern gestoppt;
  die bereits geprüften Serien bleiben erhalten.
- Sieben lokale Prüfungen der Evidenzvalidierung bestehen. Ein isolierter synthetischer
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

## Sprachpakete und lokale Übersicht

Alle **16 ZIP-Sprachpakete** sind lokal erstellt und vollständig auf ZIP-Integrität
geprüft. Sie enthalten je 20 Upload-PNGs, drei ausgewählte Videos, die getrennte
Tresor-Alternative, Poster und Herkunfts-/Prüfberichte.
[Dateinamen, Größen und SHA-256](../app-store/current/packages/manifest.json),
[Hinweise zu den lokalen Paketen](../app-store/current/packages/README.md).
Die großen ZIPs sind nicht zusätzlich in Git gespeichert; alle nativen Einzeldateien
und die Auswahl sind bereits im bestehenden Projekt und in den nativen Actions-Artefakten.

Die interaktive Übersicht besteht den lokalen Chromium-Test für alle 32 Serien
und 320 Bildverweise. Desktop (1440 px) und mobile Ansicht (390 px, arabische
Aufnahmen) wurden außerdem tatsächlich angesehen; kein horizontaler Überlauf
oder Browser-Skriptfehler. Das ist ein Test der Übersicht, kein zusätzlicher iOS-Test.
[Browser-Prüfbericht](../app-store/current/validation/local-review-gallery-complete.json).

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
Status der neuen nativen Validierung: **PASS**. Spanisch/groß: fünf native Fälle,
Italienisch/mittel: ein nativer Fall, jeweils 0 Fehler/Skips; beide neuen Heute-Bilder
zeigen den tatsächlichen Foto-Schnellzugriff mit 55 Medien. Beide Serien sind vollständig
visuell geprüft. Die weiteren Serien wurden auf dem korrigierten Stand `cf9c42e` aufgenommen:
[groß, zehn Sprachen](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39125897166),
[mittel, elf Sprachen](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39125899164).

## Einzelner Simulator-Systemabsturz

Koreanisch/mittel im Lauf `39125899164` wurde mit 0 bestandenen und einem fehlgeschlagenen
nativen Fall ausgeschlossen. Der unveränderte Crashbericht benennt **SpringBoard**, nicht
PhotoMaid: `EXC_BREAKPOINT / SIGTRAP` während eines Trait-Wechsels. Die native Diagnoseaufnahme
zeigt den weiterhin sichtbaren englischen Dialog „Allow Full Access“. Der genaue interne
Apple-Absturzgrund ist nicht etabliert. Es gibt daraus keinen Nachweis eines Fehlers der
Spielsteuerung oder koreanischen Übersetzung.

[Unveränderte Testergebnisse, Crashbericht und separat markiertes Diagnosebild](../app-store/current/validation/ko-medium-system-crash/)
sind erhalten. Die Wiederholung nutzt einen frischen Simulator, unveränderte App-/Testlogik
und unverändert strenge Abnahmeregeln:
[Lauf 39130602845](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39130602845).
Die Wiederholung ist **PASS**: ein nativer Fall, 0 Fehler/Skips; alle drei
Prüfblätter und beide ausgewählten Spielbilder wurden angesehen, der strenge Audit
ist bestanden. Die erste fehlgeschlagene Serie bleibt ausgeschlossen.

## Duo

**BLOCKED; keine freigegebenen Duo-Store-Assets.** Der echte Runner `xcode-27`
liefert Xcode 27.1 / 27A9275, den genuinen Typ
`com.apple.CoreSimulator.SimDeviceType.iPhone-Duo` und die installierte iOS-27.1-Runtime.
Beide nativen Displays sind nachgewiesen: außen 1398 × 2034 und innen 2007 × 2853.
Der passende Device Hub liegt tatsächlich unter
`/Applications/Xcode_27.1.app/Contents/Applications/DeviceHub.app`.

Der letzte [native Pilot 39140177705](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39140177705)
auf Quellstand `18e0986` besteht SDK-27.1-Build, Gerätevorbereitung und App-Installation.
Die vorherige Bereitschaftsprüfung war an eine untere Tab-Leiste gebunden, obwohl die
produktive App `sidebarAdaptable` verwendet. Der Test wartet jetzt auf den tatsächlichen
Heute-Foto-Schnellzugriff. Diese Korrektur erreicht den echten Inhalt und die unabhängig
inventarisierte 55-Foto-Mediathek; keine Berechtigung oder Zahl wird simuliert.

Der tatsächlich ausgeführte UI-Fall dauert **353,415 Sekunden** und scheitert später
an der Snake-Breitenprüfung: **374 Punkte Spielfeldbreite**, bei **466 Punkten App-Breite**
und mindestens **454 geforderten Punkten**. Native Zusammenfassung: **0 PASS, 1 FAIL,
0 SKIP**. Die 24 bis dahin erzeugten PNGs haben außerdem **1398 × 2034 Pixel** und stammen
somit vom Außendisplay; sie erfüllen das vorgesehene Innendisplayformat nicht.
`XCUIScreen.main.screenshot()` hat keinen gültigen inneren Bildsatz geliefert.

Heute, Memory und Snake-Einrichtung sowie das unverändert dekodierte letzte
Snake-Diagnosebild wurden tatsächlich angesehen. Memory zeigt drei durch echte Tipps
gefundene Fotopaare. Die Diagnosebilder sind ausdrücklich **EXCLUDE** und gehören weder
zur Upload-Auswahl noch zu den Sprachpaketen. Die vollständigen unveränderten Quellen
bleiben im nativen Artefakt `12142810383`; dessen 213.064.318 Bytes, SHA-256 und ZIP-Integrität
sind verifiziert. [Originale Ergebnisse, Bilder und genauer Befund](../app-store/current/validation/duo-snake-width-and-display-failure/review.json).

Die genaue Ursache von Fenster-/Displayzustand und kleinerer gemessener Spielfeldbreite
ist damit noch nicht etabliert. Der tatsächliche Audio-Main-Thread-Warnhinweis steht
unverändert im Ergebnisbericht; eine Ursache für diesen Fehlschlag ist daraus nicht
nachgewiesen. Es gibt keine bestätigte App-Absturzursache, keine physische Faltabnahme
und keine Hardware-FPS-Messung. Kein iPad-Ersatz, keine künstliche Fenstergröße,
keine Skalierung und keine gelockerten Abnahmekriterien.

Die weiteren 15 Duo-Sprachläufe wurden nach diesem fehlgeschlagenen Pilot **nicht gestartet**.
Vor einer Duo-Freigabe sind eine zuverlässige echte Innendisplay-Aufnahme und eine bestandene
Snake-Geometrieprüfung mit anschließend vollständigem nativen Fall und Sichtprüfung nötig.
Alle vorherigen nativen Fehlschläge bleiben mit Originalnachweisen getrennt erhalten:
[Duo-Status und Versuchshistorie](../app-store/current/DUO_STATUS.json),
[Aufnahmeläufe](../app-store/current/CAPTURE_ATTEMPTS.json).
Der optionale statische Apple-Skill-Export wurde nach Zeitüberschreitungen aus dem Ablauf
entfernt; kein exportierter Skill wurde gelesen oder angewendet.

## Reproduzieren

`ci.yml` bleibt manuell: `ui_phase=store-refresh`, `store_locales=all` oder Sprachliste,
`store_devices=iphone-large` bzw. `iphone-medium`. Der gemeinsame native Testbuild wird
einmal erstellt. Jedes Gerät erhält eine eigene überprüfte 55-Foto-Mediathek. Quellen
werden vor dem Export archiviert, damit ein Exportproblem keine Wiederholung bestandener
Aufnahmen erfordert. Lauf, Commit, Gerät, tatsächliche Ergebnisse und Artefakt-Hashes
stehen beim jeweiligen Sprachsatz.

App-Store-Connect-Asset-Upload und App-Veröffentlichung: **NOT RUN** in diesem Auftrag.
Der zuletzt von Apple verarbeitete interne TestFlight-Build bleibt 1.0 (14).
