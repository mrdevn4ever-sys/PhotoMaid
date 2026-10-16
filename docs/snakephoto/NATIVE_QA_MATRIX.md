# Native Abnahme – Simulatorprüfung und offene Gerätefälle

Stand nach ausdrücklicher TestFlight-Freigabe: Native Builds, Unit-/Integrationstests und UI-Tests
wurden auf macOS mit Xcode tatsächlich ausgeführt. Einzelne noch offene Matrixfälle sind keine
Behauptung eines vollständigen Hardwaretests. Aktueller Upload- und Wiederholungsstatus:
[TESTFLIGHT_VERIFICATION.md](TESTFLIGHT_VERIFICATION.md).

**Belegt:** Core 461/461; native Tests 58/58; auf iPhone 17/iOS 26.2 acht von neun UI-Fällen und im
großen Ersatzfenster neun von neun Fällen im vollständigen Durchlauf. Die größte Schriftstufe wurde korrigiert und auf dem finalen iPhone-Stand erneut
bestanden (681pt Brett, mindestens 629,28pt gefordert); auch der große Wiederholungslauf ist bestanden. Originalbelege einschließlich ursprünglichem Fehler: [native-qa](native-qa/).

## Umfang und verbleibende Abnahmeschritte

Das bestehende XcodeGen-Projekt erzeugen. `PhotoMaidTests` einschließlich
`SnakePhotoIntegrationTests`, `PhotoSnakeModelTests`, `PhotoMemoryModelTests` und bestehender
Rekordtests ausführen. `PhotoGameVisualTests` im bestehenden UI-Test-Target ausführen.
Die angepasste UI-Prüfung erwartet ein großes Brett unter einem sicheren HUD, mindestens 44pt für
Schließen/Pause/Einstellungen und **null Richtungsbuttons**. Der alte Task-Taktgeber ist entfernt;
`test60SnakeRealtimeDriverAndPause` muss die reale SpriteKit-Uhr prüfen.
Die QA-Schritte sind ausschließlich auf einer leeren, wegwerfbaren Test-Mediathek auszuführen.
Die aktuelle TestFlight-Anweisung erlaubt den internen Upload; ein App-Store-Release bleibt ein eigener Auftrag.

| Bereich | Native Schritte / Annahmebedingung | Status |
|---|---|---|
| Build / Ressourcen | iOS-26-SDK, Swift 6 Strict Concurrency; alle vier Atlanten kompiliert, PNG/WAV im App-Bundle, keine SpriteKit-Platzhalter-Warnungen | PASS: nativer Build, alle vier Atlanten, Bilder und WAV im Testhost geladen |
| Memory-Fehlpaar | 12 und 18 Paare, auch scrollend und große Schrift; verschiedene Karten aufdecken, sofort dritte geschlossene Karte tippen; sie öffnet, vorheriges Fehlpaar schließt; keine drei gleichzeitig | PARTIAL: nativer Dritt-Karten-/Timer-Test PASS; reale 12-Paare-Runde PASS; 18 Paare/Scrollen manuell offen |
| Memory-Unterbrechung | Fehlpaar → Hintergrund/Ansichtswechsel → zurück; Karten bedienbar, keine fremde Runde durch alten Timer geschlossen | PARTIAL: Modell-/Timer-Regression PASS; manuelle Unterbrechungsmatrix offen |
| Memory-Rekord | Runde gewinnen, aktive Zeit und richtiger Rekord sichtbar; Pause/Sheet-Zeit zählt nicht; schnelleres manuelles Schließen bleibt separate bestehende Kategorie | PASS: native Modelltests, UI-Sieg und Rekord nach Prozessneustart |
| Null / ein Foto | Null Fotos zeigt Kit-Platzhalter; ein echtes ausgewähltes Foto wiederholt sich zyklisch | PARTIAL: Null-Foto-Symbolrunde nativ; Einzelbildzyklus Core PASS |
| 10 / 100 Fotos | PhotosPicker bestellt, Fotos lokal restauriert; Reihenfolge per Drag und VoiceOver ändern, entfernen; keine unerwarteten Fotos, entfernte Texturen verschwinden | PARTIAL: Core-Archiv und native Reorder/Remove/Restore PASS; Systempicker/Drag mit 100 offen |
| Bildformate | HEIC/JPEG/PNG mit EXIF 1/6/8; Hochformat, Querformat und sehr große Originale; maximal 256px gespeicherte Kopie, aufrecht/rund mit Ring | PARTIAL: nativer JPEG/EXIF-6-Thumbnail-Test PASS; vollständige Formatauswahl offen |
| iCloud / Zugriff | Noch nicht geladene Auswahl, Offline/Downloadabbruch und erneuter Versuch; nur erfolgreiche Auswahl hinzufügen, vorherige Fotos erhalten; manuelle Auswahl fordert keine PhotoKit-Vollfreigabe | BLOCKED |
| Bibliothek / Favoriten / Ordner | Nur explizit gewählte Quelle; leere/kleine/verschachtelte Alben; keine Ersatzfotos aus anderer Quelle; bestehende Zugriffs- und Tresorfilter | PARTIAL: reale Simulator-PhotoKit-Quellen PASS; verschachtelte/leere Alben manuell offen |
| Vier Köpfe | Standard Schlange, Drache, Dino, Monster; Auswahl nach Neustart erhalten; rechts/oben/links/unten anatomisch korrekt, kürzester Drehweg ca.130ms | PARTIAL: alle Kopfframes nativ geladen, Preferences Core PASS; vier Skins visuell manuell offen |
| Mimik | Idle/Blink/Zunge/Blick, Essen ≤180ms und ≤1.08×, Gefahr, Pause/Schlaf, Hurt → Dead; Reduce Motion unterdrückt Zusatzbewegungen | PARTIAL: Timing/Zustände Core PASS, Cartoon-Kopf tatsächlich gerendert; alle Mimiken manuell offen |
| Pfad / Wachstum | Mehrfaches Essen, enge Kurven, legaler auslaufender Schwanz; Abstand und Verbindung ohne diagonale Abkürzung; Fotos bleiben aufrecht | PARTIAL: Core-Regeln/Interpolation PASS, UI-Fressen/Wachstum und Screenshot PASS; langer Körper auf Gerät offen |
| Ränder | Klassische Wand erkennbar, Todesmeldung erst nach sichtbarem Kontakt; Relaxed horizontal/vertikal und an Ecken ohne Querlinie oder fehlende Wrap-Kopie | PARTIAL: Wrap/Kollision Core PASS, native verzögerte Game-Over-Präsentation PASS; alle Ränder visuell offen |
| Steuerung | Nur Wischgesten; schnelle zwei Kurven, kein 180°-Turn; HUD-Taps starten keine Bewegung; keine Richtungsbuttons oder D-Pad-Einstellung | PASS: tatsächliche UI-Swipes, keine Richtungsbuttons, Core-Richtungsregeln; VoiceOver-Hardware offen |
| Pause / Fortsetzen | Pause, Fotos-/Einstellungssheet, Spielwahl, Schließen, Hintergrund, Anruf, erneutes Öffnen; keine unbeabsichtigten Ticks; Swipe setzt ausdrücklich fort | PARTIAL: UI-Schließen/Fortsetzen/Hintergrund/echte SpriteKit-Uhr PASS; Anruf auf Hardware offen |
| Speicherwarnung | Spiel pausiert, komponierte Fototexturen freigegeben; nächster Swipe baut sie einmalig neu auf; Auswahl, Score und Körper bleiben | BLOCKED |
| Rekorde / Einstellungen | Höchste gefressene Anzahl je bestehender Kategorie, Neustart der App, Speicherfehleranzeige; neuer Preferences-Key, alte Keys unverändert | PARTIAL: bestehende native Rekordtests und UI-Rekord PASS; alle Einstellungen manuell offen |
| Kleine / große Fenster | Kleine iPhones und große Innenfenster; Safe Areas, HUD, keine elliptischen Fotos; laufende Runde bei Größenwechsel unverändert; neue Runde nutzt neue Maße | PARTIAL: iPhone-Hochformat-/Fenstertest PASS; großer separater Simulatorlauf und größter Schrift-Nachtest PASS; genaue Quellen im Bericht |
| Orientierung | Bestehendes iPhone-Hochformat bleibt gesperrt; kein vorgetäuschter Fold-Hardwaretest | PASS: bestehende Portrait-Konfiguration und iPhone-Orientierungs-UI-Test; kein Fold-Hardwaretest |
| Barrierefreiheit | VoiceOver-Schrittmodus, beschriftete HUD-/Galerieaktionen, große Schrift, Deutsch/Englisch/Arabisch, LTR-Spielkoordinaten | PARTIAL: größte Schrift/Arabisch, getrennte HUD-Ziele und 44pt-Treffflächen PASS auf iPhone; echtes VoiceOver manuell offen |
| Sound / Haptik | Silent Mode, Ton aus, lokale und globale Haptik aus, Hintergrund/Anruf, Musik einer anderen App und Rückkehr zum Feed | BLOCKED |
| 60 / 120Hz | Ziel 60 FPS; 3 / 100 / 300 Segmente und 1 / 100 Fototexturen auf echten 60/120Hz-Geräten mit Instruments/Game Performance messen, Aufnahme und Messwerte ablegen | BLOCKED |
| Restliche App | Feed/iCloud/Überspringen, Analyse, Spielwechsel, Käufe/Ads/Onboarding unverändert durchlaufen | PARTIAL: UI für dauerhaftes Überspringen, Video ohne Poster, langsames Foto PASS; gesamte Kauf-/Analyse-Matrix offen |

Die bestehende Snake beginnt mit drei Körperzellen. Ein einzelnes Foto ist testbar; eine einzelne
Körperzelle wird nicht künstlich eingeführt. Die laufende Runde bleibt wie zuvor im App-Prozess;
über einen Prozessneustart bleiben Galerie, Einstellungen und Rekorde erhalten, nicht die komplette Runde.
