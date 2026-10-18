# TestFlight · PhotoMaid 1.0, Build 15

**PASS:** Apple hat Build 15 verarbeitet und am **18.10.2026 um 20:30:39 UTC** an die
internen TestFlight-Tester verteilt. Upload um 20:28:36 UTC. Der TestFlight-Änderungstext
ist erfolgreich gesetzt. Ausdrückliche Nutzerfreigabe: „Erledigt? Wenn ja mach testflight“.

[Erfolgreicher Lauf 39161997156](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39161997156) ·
Quellstand `c4898e78521744d5bf97c37c03700f2a3e23dea8`.

Enthalten sind Paare in allen 16 Sprachen, die vereinfachten Paare-/Snake-Startansichten,
iCloud standardmäßig an, die korrigierte Spielnavigation und der zuletzt gekürzte Galeriehinweis.
Snake wird weiterhin ausschließlich durch Wischgesten gesteuert.

| Prüfung | Tatsächliches Ergebnis |
|---|---|
| Native Unit-Tests auf dem Upload-Quellstand | 50 Swift-Testing- und 13 XCTest-Fälle bestanden, 0 Fehler |
| Cloud-Vorgabe und bewusste Abschaltung | Nativer Modelltest bestanden |
| Release-Archiv und signierte IPA | Erfolgreich exportiert und hochgeladen |
| Tatsächlich exportierte Privacy-Manifeste | Alle 3 bestanden: App, Google Mobile Ads, UMP |
| Apple-Verarbeitung | Erfolgreich, Version 1.0 / Build 15 |
| Verteilung | Intern erfolgreich; keine externe Verteilung oder App-Store-Veröffentlichung |

[Unveränderter Privacy-Bericht](../../privacy-manifests-build15.json) ·
[Echte Erfolgsnachrichten mit UTC-Zeitstempeln](success.log) ·
[Native Unit-Ergebnisse](unit-results.log) · [Maschinenlesbarer Abschluss](status.json).

Die Erfolgsnachrichten sind aus dem tatsächlichen GitHub-Joblog ausgewählt; lediglich
ANSI-Farbsteuerzeichen wurden entfernt. Die Unit-Ergebniszeilen stammen unverändert aus
`unit-tests.log` des geprüften Artefakts. Das Artefakt `testflight-report` besteht die
GitHub-SHA-256- und ZIP-CRC-Prüfung. Herkunft und Originaldatei-Prüfsummen stehen in `status.json`.
Vollständige Signing-Logs oder Schlüsselwerte werden nicht in Git abgelegt.

Der originale [CI-Kurzbericht](ci-report.md) meldet **UNBEKANNT**, weil sein Parser den
Gym-Abschluss nicht erkennt. Diese Ausgabe bleibt erhalten. Der erfolgreiche signierte
IPA-Export, die bestandenen Tests und die tatsächlichen Apple-Verarbeitungs-/Verteilungsnachrichten
belegen den Abschluss; der Kurzbericht wird nicht als erfolgreicher Buildnachweis ausgegeben.

Die vorherige [native Sichtprüfung](../README.md) umfasst vier UI-Fälle und 24 App-Checkpoints
auf iPhone und großem Ersatzfenster. Für den einzelnen zuletzt gekürzten Galeriehinweis
gibt es keine neue Aufnahme. Er ist jetzt aber im erneut nativ getesteten und signierten
Uploadstand enthalten. Keine neue persönliche iCloud-, physische Duo- oder Geräte-FPS-Abnahme.

Der vollständige Checkout benötigte in diesem Lauf 7:38 Minuten. Für künftige TestFlight-Läufe
ist dieselbe begrenzte App-/Test-Dateiauswahl wie in der bestandenen CI vorbereitet;
Store-Medienarchive werden dort nicht benötigt. Die Pfadgleichheit ist statisch geprüft.
Diese Workflow-Anpassung wurde in diesem abgeschlossenen Lauf noch nicht ausgeführt;
App-Code, Signierung und Uploadverhalten bleiben identisch.

Die vorhandenen Store-Medien bleiben Archivdateien mit erforderlicher Neuaufnahme für
Paare und die neue Einrichtung. Dieser TestFlight-Upload lädt keine neuen Store-Bilder oder
Videos hoch und veröffentlicht die App nicht im App Store.
