# SnakePhoto / Memory – TestFlight Build 13

Die anschließende Nutzeranweisung „Testfloght build“ autorisiert Push, notwendige GitHub Actions,
Fehlerkorrekturen und den internen TestFlight-Upload. Kein App-Store-Release und keine externe Verteilung.

## Quellstand und Ergebnis

Aktueller Quellstand: `cd1d40bda5a2b04c75c5e4b3251d8f9222e5c244` auf dem bestehenden Branch
`feat/iphone-duo-games`. [TestFlight-Lauf 38981991475](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38981991475)
**PASS: Version 1.0, Build 13.** Upload am 16.10.2026 um 23:41 UTC; Apple-Verarbeitung um
23:43 UTC erfolgreich, anschließend interne Verteilung bestätigt. Kein externer Beta-Release.
Der signierte Release-Build wurde tatsächlich mit Xcode archiviert und exportiert. Alle **drei
Privacy-Manifeste der exportierten IPA** bestanden; [Originalbericht](../privacy-manifests-build13.json).
[Native Ergebnisse](native-qa/NATIVE_RESULTS.json) und [Upload-/Verarbeitungsbelege](native-qa/testflight-build13-success.log).
Die identischen 58 nativen Tests waren im CI auf genau diesem Quellstand bereits bestanden;
im anschließenden Upload-Lauf wurden sie deshalb nicht erneut ausgeführt.
Der erste Archivierungsversuch [38980583746](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38980583746)
wurde vor dem Upload abgebrochen, nachdem der tatsächliche iPhone-Wiederholungsbericht noch einen
Layoutfehler zeigte. Ein grüner Schritt mit `continue-on-error` wurde nicht als Abnahme übernommen;
maßgeblich sind der gespeicherte Exitcode und die xcresult-Zusammenfassung.

## Tatsächliche native Prüfungen

- [Vollständiger Spieledurchlauf](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38977261521),
  Quellstand `6799fe7`: Core **461 PASS** (437 Swift Testing + 24 XCTest).
  Nativer iOS-Build und **58 Unit-/Integrationstests PASS** (45 Swift Testing + 13 XCTest).
  iPhone 17, iOS-Simulator 26.2: **8/9 UI-Tests PASS**, ein Layoutfehler mit größter Schrift/Arabisch.
  Der Gesamtworkflow wird deshalb nicht als erfolgreich gewertet.
  Großes Ersatzfenster (iPad mini A17 Pro, iOS 26.4.1): **9/9 UI-Tests PASS, 0 Fehler, 0 übersprungen**.
  Xcode 26.6 (17F113); ausdrücklich kein Duo-Hardwareprofil.
- Bestanden auf dem iPhone: Memory-Sieg mit zwölf Paaren und Rekord nach App-Neustart;
  Snake mit echten PhotoKit-Testfotos, Wischsteuerung, Fressen, Rekord, Pause/Fortsetzen;
  Hochformat und Fensterwechsel; Favoriten-/Albumquellen; reale SpriteKit-Uhr mit Hintergrundpause;
  nicht verfügbare Videos weitergeben; Video ohne Poster; noch ladendes Foto weitergeben.
- Der fehlgeschlagene Layouttest maß 496pt Spielfeldhöhe statt mindestens 629,28pt.
  `3d7ab1a` ersetzt bei Accessibility-Schriftgrößen die mehrzeiligen Punktetexte durch Symbol und Zahl.
  Vollständige VoiceOver-Beschriftungen und individuelle HUD-Kennungen bleiben erhalten.
  [Erster gezielter Wiederholungslauf](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38979321613):
  iPhone **FAIL**, 621pt statt 629,28pt. `cd1d40b` ordnet die beiden Zahlen deshalb in einer gemeinsamen
  Zeile an, mit vollständigen getrennten Accessibility-Labels; die Mindesthöhe wurde nicht gelockert.
  [Erneuter Wiederholungslauf](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38980898046)
  auf diesem Stand: iPhone **PASS 1/1, 0 Fehler, 0 übersprungen, Exitcode 0**.
  Unveränderten Screenshot mit größter Schrift/Arabisch tatsächlich angesehen: Spielfeld
  **681pt** hoch (gefordert ≥629,28pt); alle drei HUD-Treffflächen **44×44pt**. Großes Fenster ebenfalls **PASS 1/1, 0 Fehler, 0 übersprungen, Exitcode 0**.
  Der Workflow ist insgesamt erfolgreich. Beide endgültigen Ergebnisdateien liegen unter `native-qa/`.
  Auf genau `cd1d40b` außerdem **461 Core-Tests und 58 native Tests PASS**, einschließlich Bundle-/
  Thumbnail-/Textur-Cache-/Galerie-/Memory-/Fortsetzungsprüfungen. Die vorherige vollständige große
  Suite auf `6799fe7` bestand 9/9; die acht anderen iPhone-Fälle werden nicht als erneuter Lauf auf
  dem letzten HUD-Commit ausgegeben.
- Zusätzlich korrigiert: SwiftUI-Import für PhotosPicker, Fehlerbindung und Typprüfungsaufwand der
  Galerie, getrennte Accessibility-Kinder des Spiels und Foto-Cache-Invalidierung bei geänderter
  sichtbarer Reihenfolge. Die Spiellogik `PhotoSnakeGame` bleibt bytegleich zur gesicherten Basis.
  Die Atlantenprüfung toleriert ausschließlich numerisches UV-Rundungsrauschen unter 0,001px.

## Belege und Grenzen

[Unveränderte Screenshots, Logs und Zusammenfassungen](native-qa/) enthalten die tatsächlich gerenderte
App. `SCREENSHOTS.json` ordnet jeden Screenshot Original-Anhang und Prüflauf zu.
Die Tests verwenden ausschließlich wegwerfbare Simulator-Mediatheken.

Statische Integrationsprüfung erneut PASS: alle 77 Kit-Dateien bytegleich, vier Atlanten korrekt
konfiguriert, ausschließlich Wischsteuerung, bestehende Regeln und 2657 vorhandene Übersetzungen
bewahrt. Lokalisierung: 2690 Einträge, 16 Sprachen, 1676 verwendete Kennungen.

Nicht gemessen: 60/120Hz-Geräte-FPS, echtes iCloud-PhotosPicker-Verhalten, Hardware-Sound/Silent Mode
und ein tatsächlicher faltbarer iPhone-Innenbildschirm. Ein großes Simulatorfenster ersetzt diese
Hardware-Abnahme nicht. Die vollständige manuelle Matrix steht in [NATIVE_QA_MATRIX.md](NATIVE_QA_MATRIX.md).
