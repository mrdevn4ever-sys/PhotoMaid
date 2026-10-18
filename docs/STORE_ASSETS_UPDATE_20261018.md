# Aktualisierung der Store-Assets – 18.10.2026

**Normale iPhones: PASS. Duo: IN PROGRESS.** Maßgeblich sind die tatsächlich vorhandenen Dateien und
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
visuell geprüft. Fehlende Serien laufen auf dem korrigierten Stand `cf9c42e`:
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

Der offizielle Runner `xcode-27` liefert Xcode 27.1, Build 27A9275, und den genuinen
Gerätetyp `com.apple.CoreSimulator.SimDeviceType.iPhone-Duo`. Die offizielle iOS-27.1-Runtime
wurde erfolgreich installiert. Der [native Prüf-Lauf 39124764082](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39124764082)
hat das echte Gerät gebootet und beide Displays gemeldet: außen 1398 × 2034, innen
2007 × 2853. Sein unverändertes Diagnosebild war vollständig schwarz und wurde
visuell abgelehnt. Es ist kein akzeptiertes App- oder Store-Bild.

Der erste tatsächliche [PhotoMaid-Duo-App-Pilot 39126669768](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39126669768)
verwendet den nativen SDK-27.1-Build und das echte Innendisplay. Die dokumentierte
Simulator-Displaysteuerung schaltet dafür das äußere Display aus und das innere an;
keine Größenänderung oder Ersatzgeräte. Die Aufnahme muss zusätzlich einen vollständigen
nativen UI-Test, die Original-Prüfsummen, 2007 × 2853 Pixel und die visuelle Kontrolle
bestehen. Vollständig einfarbige/leere Frames weist der Audit zurück.
[Aktueller Duo-Status](../app-store/current/DUO_STATUS.json).

Der native SDK-27.1-App-Build des Duo-Piloten ist **PASS** (Job `117673139925`).
Der erste Aufnahmeversuch scheiterte vor dem UI-Test: LaunchServices konnte `open -a Simulator`
nicht auflösen. Der echte Duo-Simulator war bereits gebootet. Jetzt wird `Simulator.app`
über den vollständigen Pfad der ausgewählten Xcode-Version gestartet;
[Wiederholung 39128651889](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39128651889).
Auch der zweite Versuch scheiterte vor dem App-Test: Der vollständige klassische
`Simulator.app`-Pfad fehlt tatsächlich auf diesem Runner (`NSCocoaErrorDomain 260`).
[Unveränderter Fehlernachweis](../app-store/current/validation/duo-second-app-attempt.json).

Die anschließende reine Pfadprüfung [39132957505](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39132957505)
findet stattdessen die echte `Contents/Applications/DeviceHub.app` aus Xcode 27.1,
mit Bundle-ID `com.apple.dt.Devices` und vorhandenem Programm. Auch Apples
[öffentliche Duo-Anleitung](https://developer.apple.com/iphone-duo/prepare/) nennt Device Hub.
Der Workflow öffnet nun dieses vorhandene Programm; die konkrete UDID bleibt
bei simctl und XCTest eindeutig ausgewählt.
[App-Pilot 39133181324](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39133181324)
öffnet Device Hub erfolgreich und bestätigt beide echten Display-Power-Operationen
(Screen 1 aus, Screen 3 an). Beide Boots und das bewachte Leeren der Wegwerf-Mediathek
bestehen; danach endet das zehnminütige Gesamtlimit der Vorbereitung noch vor
der App-Installation. [Unveränderte Display-/Gerätedaten und genauer Befund](../app-store/current/validation/duo-devicehub-preparation-timeout/review.json).
Die Wiederholung entfernt den ersten unnötigen GUI-Start vor dem bewachten Leeren
und erlaubt ausschließlich der Duo-Vorbereitung 20 Minuten. Native Abnahme, echte
55 Fotos, unveränderte Dimensionen und Leerbild-Ablehnung bleiben gleich:
[Lauf 39134787534](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39134787534).
Die Vorbereitung und App-Installation dieses Versuchs sind **PASS**. Der
Testläufer kann danach nicht starten: `NSPOSIXErrorDomain 64 / Host is down`.
Xcode vermutet einen System-Shell-Absturz; ein unabhängiger Crashbericht wurde
nicht exportiert. Die anschließende Diagnosesammlung endet nach 600 Sekunden.
Der native Ergebnisbericht zeigt 0 PASS, 1 Runner-Fehler, 0 SKIP; kein
PhotoMaid-UI-Fall wurde ausgeführt und kein Store-Bild erzeugt.
[Unveränderte Ergebnisse und Startfehler](../app-store/current/validation/duo-test-runner-launch-failure/review.json).

Der anschließende Pilot [39137466424](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39137466424)
behält die nativen Display-Power-Standards bei und lässt den bisher erfolglosen
optionalen Apple-Skill-Export weg. Ob einer dieser zusätzlichen Vorgänge den
Startfehler verursacht hat, ist nicht nachgewiesen. Keine Geometrieänderung
und keine Lockerung der Bild-/Testabnahme.
Dieser Lauf erreicht den tatsächlichen UI-Fall, scheitert jedoch nach 99,723 Sekunden
an `waitForPhotoAccess()`. Dessen bisherige Bedingung verlangt ausschließlich eine
untere Tab-Leiste; die produktive App verwendet `sidebarAdaptable`. Diese konkrete
Testannahme wurde durch den vorhandenen tatsächlichen Heute-Foto-Schnellzugriff
ersetzt. Der folgende unabhängige Nachweis der 55 Fotos bleibt bestehen.
Die unveränderte Diagnoseaufnahme (1398 × 2034, Außendisplay) zeigt Einführung und
später schwarze Frames; sie beweist keine gültige Aufnahme des Innendisplays.
[Abgelehnter Versuch und Befund](../app-store/current/validation/duo-default-display-readiness-failure/review.json).
[Native Validierung der Testkorrektur 39140177705](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39140177705).
Keine produktive App-Funktion oder Berechtigung wurde geändert.
Bisher sind **keine Duo-App-Aufnahmen freigegeben**. Native UI-Ergebnisse,
äußere App-Aufnahmen, Duo-Vorschauformate, physische Faltabnahme und Hardware-FPS-Messung
sind damit noch nicht nachgewiesen. Der statische Apple-Skill-Export wird nach zuvor
begrenzten CLI-Zeitüberschreitungen mit geöffneter Xcode-Oberfläche erneut versucht.
Dabei wird kein KI-/Modellaufruf ausgelöst.

## Reproduzieren

`ci.yml` bleibt manuell: `ui_phase=store-refresh`, `store_locales=all` oder Sprachliste,
`store_devices=iphone-large` bzw. `iphone-medium`. Der gemeinsame native Testbuild wird
einmal erstellt. Jedes Gerät erhält eine eigene überprüfte 55-Foto-Mediathek. Quellen
werden vor dem Export archiviert, damit ein Exportproblem keine Wiederholung bestandener
Aufnahmen erfordert. Lauf, Commit, Gerät, tatsächliche Ergebnisse und Artefakt-Hashes
stehen beim jeweiligen Sprachsatz.

App-Store-Connect-Asset-Upload und App-Veröffentlichung: **NOT RUN** in diesem Auftrag.
Der zuletzt von Apple verarbeitete interne TestFlight-Build bleibt 1.0 (14).
