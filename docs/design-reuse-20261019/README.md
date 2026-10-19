# Design-Übernahme auf dem vollständigen PhotoMaid-Stand

Nutzerauftrag vom 19.10.2026: nur die gefallenen Designelemente aus dem Experiment wiederverwenden, alle aktuellen Funktionen erhalten, danach TestFlight von `main`.

## Basis und Umfang

- Funktionsbasis: Build 17, Branch `feat/iphone-duo-games`, `a614cdb6b365104bf60c31528a8eeb85262a6cdb` (App-Quellstand des Builds `575313d`). GitHub-main steht zu Beginn noch auf dessen Vorfahren `ca6f81850a0a4032bbf8093f241f99a7584ab4c6`. Für main wird der vollständige aktuelle Stand erhalten; keine Rückkehr zum älteren Experiment-Quellcode und kein Merge des Experimentier-Branches.
- Neue blau-neutrale Farben, deckende Karten, dezente Rahmen, passende Light-/Dark-/Kontrastfarben und zugängliche Glass-Fallbacks.
- Gemeinsame rein darstellende Kopfzeilen und Aktionskacheln; Studio gliedert vorhandene Erstellen-, Werkzeug-, Dokument-, Gespeichert- und Entwurfsaktionen. Aufräumen erhält direkte bestehende Papierkorb-/Später-Ziele. Vorhandene Route-Handler werden weiterverwendet.
- Native Navigation, gesamte Feed-/Spiel-/iCloud-Logik, Pro-/Free-/Werberegeln, Vault-Kryptografie, Persistenz und Signing/Workflows bleiben auf der vollständigen Release-Basis. Foto-Lader und Caches werden ausdrücklich nicht aus dem älteren Experiment übernommen.
- Entwürfe behalten Öffnen, sichtbaren Löschen-Button, Kontextmenü, Bestätigungsdialog und unveränderte Persistenz. Hero-/Tour-/Geheimeingang-Logik unter Heute unverändert.

## Quellenprüfung

[source-audit.json](source-audit.json) dokumentiert 242 unveränderte geschützte Swift-Dateien samt aggregiertem SHA-256, unveränderte Build-/Signing-/Package-Dateien und gezielte Bytevergleiche der Foto-Lader, Studio-Picker-/Löschlogik sowie Heute-/Aufräumen-Fachlogik. Diese Prüfung belegt den begrenzten Quellcodeumfang, keine vollständige Geräteabnahme.

Vorhandene Übersetzungen sind unverändert. Drei reine UI-Beschriftungen kommen mit je 16 Übersetzungen hinzu, einschliesslich Generatorquelle. Swift-Frontend-Syntaxprüfung für die zehn geänderten/neuen Swift-Dateien bestanden; kein Apple-SDK-Typnachweis dadurch.

## Dateiinventar gegenüber Build 17

- `PhotoMaid/DesignSystem/Tokens.swift`: Farbrollen.
- `PhotoMaid/DesignSystem/Glass.swift`: deckende Accessibility-Fallbacks.
- `PhotoMaid/DesignSystem/Components.swift`: Seitengrund, lesbare Zeilen/Kennzahlen; Foto-/Cache-Teil bytegleich.
- `PhotoMaid/DesignSystem/FeatureChrome.swift`: Header, Aktionskachel, dezente Druckrückmeldung.
- `PhotoMaid/Features/Today/TodayView.swift`: adaptive rein visuelle Gestenhinweise, Kartenschatten entfernt.
- `PhotoMaid/Features/Cleanup/CleanUpHubView.swift`: Header und bestehende Papierkorb-/Später-Ziele als Karten.
- `PhotoMaid/Features/Studio/StudioView.swift`: Anordnung/Darstellung vorhandener Funktionen und stabile UI-Testkennungen.
- `PhotoMaid/Resources/ios_strings.json`, `PhotoMaid/Resources/Localizable.xcstrings`, `scripts/i18n/ios_strings_part_visuals.py`: drei UI-Texte in 16 Sprachen.
- `PhotoMaidUITests/PhotoGameVisualTests.swift`: zusätzliche Dark-Mode-, Aktions-, Touchflächen- und Rücknavigation-Prüfungen im bestehenden Workspace-Test.
- `PhotoMaidUITests/PhotoMaidUITests.swift`, `PhotoMaidUITests/RealLibraryTests.swift`: bestehende Studio-Tests verwenden die neuen stabilen UI-Kennungen.
- Diese Dokumentation und Quellenbelege.

## Tatsächliche native Ergebnisse

Geprüfter App-Quellstand: `8fc221c238df4ef09921ed3b5f3d82c810bc216e`. [CI-Lauf 39214988097](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39214988097) ist vollständig erfolgreich. Nach diesem Quellstand wurden nur Dokumentation und echte Testbelege ergänzt.

| Prüfung | Ergebnis |
|---|---|
| Quellen-/Funktionsumfang, unveränderte Fachdateien | PASS |
| Lokalisierung | PASS: 1732 verwendete Kennungen, 2749 Einträge, 16 Sprachen |
| Swift-Frontend-Parser | PASS: 10 Dateien, nur Syntax |
| `git diff --check` | PASS |
| Core, Swift 6.4 | PASS: 475 vom Runner gemeldete Tests in 54 Suites |
| Nativer App-/Test-Build | PASS: `TEST BUILD SUCCEEDED`, danach `TEST EXECUTE SUCCEEDED` |
| Native Unit-Tests | PASS: 13 XCTest-Methoden + 69 Swift-Testing-Tests = 82; einschliesslich realem Keychain-Roundtrip |
| Erweiterter Workspace-/Studio-UI-Test auf iPhone | PASS: 1/1, 0 Fehler, 0 übersprungen; iPhone 17 / iOS Simulator 26.2 |
| Derselbe UI-Test im breiten Fenster | PASS: 1/1, 0 Fehler, 0 übersprungen; iPad mini (A17 Pro) / iOS Simulator 26.4.1 |
| Text-/CTA-Kontraste | PASS: 24 Farbpaare in vier Modi >= 4,5:1 (Minimum 4,7:1); keine Messung sämtlicher Fotos/Glasflächen |
| TestFlight von `main` | PASS: PhotoMaid **1.0 (19)**, Apple-Verarbeitung abgeschlossen und intern verteilt |
| Privacy-Prüfung im Uploadlauf | PASS: 8 Prüfer-Regressionstests, App-Quellmanifest sowie alle 3 Manifeste in der tatsächlich signierten IPA |

Der vorhandene Workspace-Test prüft Feed-/Fensteranpassung und öffnet Heute, Fotos, Aufräumen, Studio, Verlauf, Editor, Collage, Einstellungen und Tresor. Zusätzlich wurden deutsche Dark-Mode-Ansichten, alle vier Erstellen-Einstiege, Werkzeug-/PDF-/Gespeichert-Zugänge, deren Touchflächen und der tatsächliche Weg Verkleinern → Zurück zu Studio geprüft. Alle bestehenden Assertions sind erhalten. Die Prüfung ist keine vollständige Ausführung jeder Export-/Spiel-/Tresoroperation mit produktiven Daten.

Sieben echte native Aufnahmen wurden angesehen. Abgelegt sind ausgewählte unveränderte PNGs für [Heute dunkel](screenshots/design_dark_today.png), [Aufräumen dunkel](screenshots/design_dark_cleanup.png), [Studio dunkel](screenshots/design_studio_dark_create.png), [Studio-Werkzeuge](screenshots/design_studio_dark_tools.png), [Studio hell](screenshots/workspace_studio.png) und [Studio im breiten Fenster](screenshots/expanded-studio-dark.png). Keine Mockups oder nachgezeichneten Screenshots.

Weitere Belege: [native-results.json](native-results.json), [iPhone-Ergebnis](iphone-summary.json), [breites Fenster](wide-summary.json), [Kontraste](contrast.json). Vollständige Protokolle, Screenshot-Anhänge und Hierarchien sind in den CI-Artefakten `ios-build-report`, `core-test-log`, `game-visual-iphone` und `game-visual-evidence` des verlinkten Laufs erhalten.

Ein breites Simulatorfenster ist kein Nachweis echter Fold-/Unfold-Hardware. Reales iPhone, echter iCloud-Download, Face ID und sämtliche Accessibility-/Berechtigungs-/Migrationskombinationen wurden in diesem Design-Auftrag nicht neu auf Hardware geprüft. Fachdateien und Datenformate sind unverändert; daraus folgt keine allgemeine Sicherheitszertifizierung. Kein App-Store-Release oder externe Tester-Verteilung.

## Main und TestFlight

Nach grüner CI wurde GitHub-main ohne Force-Push auf `f1ccc2be1bc097f7249f718cabc4516d181fa6c7` vorgezogen. Dieser Commit enthält gegenüber dem geprüften App-Quellstand `8fc221c` ausschliesslich Dokumentation und Testbelege. Die bestehende Feature- und die Experimentier-Branch wurden nicht geändert.

[TestFlight-Lauf 39218181169](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39218181169) lief nachweislich auf Branch `main`, Commit `f1ccc2b`. Reguläres Release-Archiv, vorhandene manuelle Signierung und Export bestanden. **Version 1.0, Build 19** wurde am **19.10.2026 um 07:54:16 UTC** hochgeladen; Apple schloss die Verarbeitung um **07:59:58 UTC** ab. Changelog und **Verteilung an interne Tester** wurden anschliessend bestätigt. Keine externe Verteilung oder App-Store-Veröffentlichung.

Die bereits auf identischem App-Code bestandenen Unit-Tests wurden im Uploadlauf über den vorhandenen Parameter `run_tests=false` nicht erneut ausgeführt. Privacy-Prüfer-Tests und die Prüfung der tatsächlichen IPA liefen regulär. Belege: [testflight.json](testflight.json), [Privacy-Bericht der signierten IPA](privacy-manifests.json), vollständige Logs und `testflight-report` im verlinkten Workflow. Nach dem hochgeladenen Commit ändern weitere Abschlussbelege nur diesen Dokumentationsordner.
