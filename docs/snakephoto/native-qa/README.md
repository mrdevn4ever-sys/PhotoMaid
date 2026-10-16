# Native SnakePhoto-Abnahme

Die PNG-Dateien sind unveränderte XCTest-Screenshots aus GitHub Actions, keine Kit-Referenzen,
keine nachgebauten Mockups. `SCREENSHOTS.json` dokumentiert SHA-256, Run, Quellstand und originale
Anhangsmetadaten. Die Mediathek enthält ausschließlich öffentliche Simulatorbilder und QA-Fixtures.

Der vollständige iPhone-Durchlauf auf `6799fe7` bestand acht von neun Fällen. Die einzige fehlgeschlagene
Prüfung betraf die Spielfeldhöhe mit größter Schrift und Arabisch; `full-suite-iphone-summary.json`
enthält diesen ursprünglichen Fehler unverändert. Der kompakte, weiterhin barrierefrei beschriftete
Punktebereich auf `3d7ab1a` erreichte noch 621pt statt 629,28pt. `cd1d40b` ordnet beide Werte in einer
gemeinsamen Zeile an. Beide finalen Nachtests bestehen mit Exit 0; `NATIVE_RESULTS.json` und
`final-*-summary.json` dokumentieren dies. `testflight-build13-success.log` bestätigt Apples Verarbeitung.

`iphone-snake-eaten.png` zeigt Fotos, Cartoon-Kopf, verbundenen Körper und Punkt/Rekord nach tatsächlicher
Wischsteuerung. `iphone-memory-won.png` zeigt einen echten Sieg mit zwölf Paaren;
`iphone-record-after-relaunch.png` die nach Prozessneustart gespeicherten Rekorde.

Simulatorergebnisse belegen weder gemessene Geräte-FPS noch iCloud-Downloads im System-PhotosPicker,
Silent Mode auf Hardware oder einen realen Fold-/Unfold-Vorgang.
