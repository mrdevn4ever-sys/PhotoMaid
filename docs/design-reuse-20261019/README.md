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

## Prüfstatus vor dem nativen Lauf

| Prüfung | Ergebnis |
|---|---|
| Quellen-/Funktionsumfang, unveränderte Fachdateien | PASS |
| Lokalisierung | PASS: 1732 verwendete Kennungen, 2749 Einträge, 16 Sprachen |
| Swift-Frontend-Parser | PASS: 10 Dateien, nur Syntax |
| `git diff --check` | PASS |
| Aktueller nativer Build und Unit-Tests | noch nicht ausgeführt |
| Aktuelle native UI-/Screenshot-Prüfung | noch nicht ausgeführt |
| Aktueller TestFlight-Upload | noch nicht ausgeführt |

Geplant sind die vorhandene manuelle CI mit vollständigen Core-/nativen Unit-Tests und der erweiterte Workspace-UI-Test auf iPhone und einem ausdrücklich als breitem Simulatorfenster bezeichneten zweiten Gerät. Ein breites Fenster ist kein Nachweis echter Fold-/Unfold-Hardware. Ergebnisse und tatsächliche Screenshots werden nach dem Lauf ergänzt. Kein App-Store-Release oder externe Tester-Verteilung.
