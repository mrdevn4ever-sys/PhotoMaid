# Einfachere Spieleinrichtung · 18.10.2026

Paare und Foto-Snake führen jetzt über eine beschriftete Fotoquelle zu einem großen
Startknopf. iCloud-Fotos werden standardmäßig bei Bedarf geladen. Eine ausdrückliche
Abschaltung bleibt beim Vorbereiten und Fortsetzen einer Runde erhalten.

## Ergebnis

- **Paare:** kurze Einführung, getrennte Beschriftungen für Fotoquelle und Paaranzahl,
  verständlicher iCloud-Schalter, „Spielen“ als Hauptaktion und „Ohne Fotos spielen“ als Alternative.
- **Foto-Snake:** kompakter Kopf; Mediathek als Startquelle; Modus, Tempo sowie Aussehen/Ton
  unter „Spiel anpassen“. Leere manuelle Fotoauswahl führt zuerst zu „Fotos auswählen“
  und der vorhandenen Galerie. Reihenfolge, lokale Speicherung und PhotosPicker bleiben erhalten.
- **Navigation:** „Spiele“ aus der Snake-Pause führt zur Spieleauswahl. Nach Snake verwenden
  Paare und Spieleauswahl wieder die tatsächliche App-Darstellung. Die dunkle Snake-Szene
  hat lesbare Systemelemente. Abgebrochenes/fehlgeschlagenes Laden lässt die Einrichtung offen.
- **Erhalten:** gespeicherte Bestwerte, laufende Runden, Fotoreihenfolge, Spiellogik und
  ausschließlich Wischgesten zur Snake-Bewegung. Das Kartenspiel heißt in allen 16 Sprachen Paare/Pairs.

[Native Paare-Ansicht](iphone/pairs_setup_default_cloud_on.png) ·
[Native Snake-Ansicht](iphone/snake_setup_default_library_cloud_on.png) ·
[Rückweg zu Paare](iphone/pairs_after_snake_uses_app_appearance.png)

## Tatsächliche Prüfung

Nativer Quellstand: `7d7c842f5390df4fe935e9a02aeb4ba02e7f5cb3`.
[Manueller CI-Lauf 39155751429](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39155751429),
gezielter Umfang `games_case=setup`.

**PASS:** Lauf erfolgreich abgeschlossen, Originalaufnahmen auf beiden Simulatoren angesehen.

| Prüfung | Tatsächliches Ergebnis |
|---|---|
| Core unter Linux | 437 Swift-Testing- und 24 XCTest-Fälle bestanden |
| Nativer iOS-Simulator-Build | Bestanden, 0 Fehler, 8 gemeldete Warnungen |
| Native Unit-Tests | 50 Swift-Testing- und 13 XCTest-Fälle bestanden, 0 Fehler |
| iPhone 17 · iOS 26.2 | 2 UI-Fälle bestanden, 0 Fehler, 0 übersprungen |
| Großes Fenster: iPad mini (A17 Pro) · iOS 26.4.1 | 2 UI-Fälle bestanden, 0 Fehler, 0 übersprungen |
| Sichtprüfung | 24 App-Checkpoints und 2 echte Berechtigungsdiagnosen angesehen |

Xcode 26.6 (`17F113`), iPhoneSimulator-SDK 26.5. Der native Cloud-Vorgabe-/Abschaltfall
`cloudDefaultsOnAndAnExplicitOptOutSurvivesPreparedRounds` besteht. Die Originalprotokolle
bleiben erhalten; bestehende Deprecation-/Testwarnungen wurden nicht als fehlerfreier
Warnungsstand ausgegeben. Ein lokaler iOS-Build wurde mangels Apple-SDK nicht durchgeführt.

[Maschinenlesbarer Abschluss](report.json) · [Original-Buildbericht](ci-report-final.md) ·
[Native Unit-Protokolle](unit-tests-final.log) · [Core-Protokolle](core-final.log) ·
[Große Ansichten](expanded-window/receipt.json)

Die UI-Fälle prüfen die deutsche Einrichtung, iCloud an/aus und Beibehalten der Abschaltung,
24 echte Fotokarten, das Öffnen der leeren manuellen Snake-Galerie, Foto-Snake mit normaler
Spieluhr, Pause → Spiele → Paare sowie arabische Oberfläche bei Accessibility XXXL.
Der Schlangenkopf muss nach einer Wischgeste tatsächlich weiterlaufen; das Spielfeld darf
keine Richtungstasten enthalten. Beim großen Text wird die Einrichtung gescrollt, um die
normale Startaktion zu erreichen.

Die Tests verwenden eine wegwerfbare Simulator-Fotomediathek mit synthetischen QA-Bildern.
Fotos werden über die wirklichen nativen Ladewege abgerufen. Kein persönliches iCloud-Konto,
keine physische Duo-Faltprüfung und keine Geräte-FPS-Messung. Ein großes Ersatzfenster ist
kein Nachweis für ein faltbares iPhone.

## Umfang der Bilder und nachträgliche Textkorrektur

Die PNGs sind unveränderte native XCTest-Anhänge. Herkunft, native Gerätenamen,
Bildgrößen und SHA-256-Werte stehen in den jeweiligen `receipt.json` und `screenshots.json`.
Die `review-*.jpg` sind ausschließlich Kontaktbögen zur Sichtprüfung; keine Store-Dateien.
Zusätzliche echte Berechtigungsdialoge sind als Diagnose gekennzeichnet.

Nach dem Aufnahmequellstand wurde in `2528ffd` **nur** `snake_gallery_empty` in allen 16 Sprachen gekürzt:
„Wähle bis zu 100 Fotos für deine Schlange.“ Die vorherige Zusage, in der Galerie mit
„Platzhaltern“ zu spielen, entfällt. Swift-Code und übrige Katalogeinträge sind identisch
mit dem nativen Prüfstand. Die Galerieaufnahme zeigt bewusst noch den früheren Hinweis;
sie wurde nicht retuschiert. Zum Abschluss der Sichtprüfung gab es für diese Textkorrektur
noch keinen weiteren nativen Build oder Screenshotlauf. Der anschließend ausdrücklich
beauftragte **TestFlight-Build 15** baut und signiert sie im Quellstand `c4898e7` erneut;
63 native Unit-Tests bestehen. **Keine neue visuelle Aufnahme für diesen Hinweis.**
Quellen-/JSON-/Katalogabgleich und vorhandener
Lokalisierungscheck bestehen: 1681 verwendete Kennungen, 2702 Einträge, 16 Sprachen;
Details in [localization-final.json](localization-final.json).

## Korrigierte visuelle Befunde

Die erste Aufnahme bestand die nativen Fälle, wurde aber wegen schlechter Snake-Kontraste
im hellen App-Modus visuell abgelehnt. Die zweite korrigierte Snake, ließ jedoch die
Paare-Ansicht nach der Rückkehr fälschlich dunkel. Auch sie wurde visuell abgelehnt und
der überholte Lauf nach Sicherung der iPhone-Belege abgebrochen. Sein großer Durchlauf
zählt nicht als bestanden. Die gemeinsame Spieleansicht setzt die Darstellung jetzt
ausdrücklich für das aktuelle Spiel; die finalen Aufnahmen prüfen den tatsächlichen Rückweg.
Originale und Befunde bleiben unter `rejected-light-snake/` und
`rejected-snake-appearance-return/` erhalten. Historische Tests werden nicht als zusätzliche
finale Tests gezählt.

## Lieferung

Änderung im bestehenden Projekt und Branch `feat/iphone-duo-games`; keine neue App,
kein neues Repository. Anschließend auf ausdrücklichen Nutzerauftrag als **Version 1.0,
TestFlight Build 15** hochgeladen, von Apple verarbeitet und intern verteilt.
[Uploadbericht und tatsächliche Bestätigungen](testflight/README.md).
Die alten Store-Medien bleiben unveränderte Archivdateien mit erforderlicher Neuaufnahme
für den neuen Spielnamen und die neue Einrichtung. Diese QA-Bilder ersetzen keinen
Store-Satz für alle Sprachen. Kein neuer Store-Medienupload und keine App-Store-Veröffentlichung.
