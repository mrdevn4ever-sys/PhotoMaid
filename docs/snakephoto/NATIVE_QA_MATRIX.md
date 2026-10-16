# Native Abnahme – noch nicht durchgeführt

Stand 16.10.2026: **Alle Zeilen BLOCKED / NOT RUN.** Dieser Arbeitsbereich ist Linux ohne Xcode,
iOS-SDK oder Simulator. Keine Screenshots des neuen Umbaus, kein gemessener FPS-Wert, kein iOS-Build.
Die Referenzbilder im gelieferten Kit und frühere PhotoMaid-Builds sind dafür kein Nachweis.
Keine Actions/Runner/Uploads starten, bis der Nutzer diesen konkreten nächsten Schritt freigibt.

## Ausführbare native Tests nach Freigabe einer geeigneten Umgebung

Das bestehende XcodeGen-Projekt erzeugen. `PhotoMaidTests` einschließlich
`SnakePhotoIntegrationTests`, `PhotoSnakeModelTests`, `PhotoMemoryModelTests` und bestehender
Rekordtests ausführen. `PhotoGameVisualTests` im bestehenden UI-Test-Target ausführen.
Die angepasste UI-Prüfung erwartet ein großes Brett unter einem sicheren HUD, mindestens 44pt für
Schließen/Pause/Einstellungen und **null Richtungsbuttons**. Der alte Task-Taktgeber ist entfernt;
`test60SnakeRealtimeDriverAndPause` muss die reale SpriteKit-Uhr prüfen.
Die QA-Schritte sind ausschließlich auf einer leeren, wegwerfbaren Test-Mediathek auszuführen.
Keine neuen TestFlight-/Release-/CI-Schritte sind dadurch automatisch autorisiert.

| Bereich | Native Schritte / Annahmebedingung | Status |
|---|---|---|
| Build / Ressourcen | iOS-26-SDK, Swift 6 Strict Concurrency; alle vier Atlanten kompiliert, PNG/WAV im App-Bundle, keine SpriteKit-Platzhalter-Warnungen | BLOCKED |
| Memory-Fehlpaar | 12 und 18 Paare, auch scrollend und große Schrift; verschiedene Karten aufdecken, sofort dritte geschlossene Karte tippen; sie öffnet, vorheriges Fehlpaar schließt; keine drei gleichzeitig | BLOCKED |
| Memory-Unterbrechung | Fehlpaar → Hintergrund/Ansichtswechsel → zurück; Karten bedienbar, keine fremde Runde durch alten Timer geschlossen | BLOCKED |
| Memory-Rekord | Runde gewinnen, aktive Zeit und richtiger Rekord sichtbar; Pause/Sheet-Zeit zählt nicht; schnelleres manuelles Schließen bleibt separate bestehende Kategorie | BLOCKED |
| Null / ein Foto | Null Fotos zeigt Kit-Platzhalter; ein echtes ausgewähltes Foto wiederholt sich zyklisch | BLOCKED |
| 10 / 100 Fotos | PhotosPicker bestellt, Fotos lokal restauriert; Reihenfolge per Drag und VoiceOver ändern, entfernen; keine unerwarteten Fotos, entfernte Texturen verschwinden | BLOCKED |
| Bildformate | HEIC/JPEG/PNG mit EXIF 1/6/8; Hochformat, Querformat und sehr große Originale; maximal 256px gespeicherte Kopie, aufrecht/rund mit Ring | BLOCKED |
| iCloud / Zugriff | Noch nicht geladene Auswahl, Offline/Downloadabbruch und erneuter Versuch; nur erfolgreiche Auswahl hinzufügen, vorherige Fotos erhalten; manuelle Auswahl fordert keine PhotoKit-Vollfreigabe | BLOCKED |
| Bibliothek / Favoriten / Ordner | Nur explizit gewählte Quelle; leere/kleine/verschachtelte Alben; keine Ersatzfotos aus anderer Quelle; bestehende Zugriffs- und Tresorfilter | BLOCKED |
| Vier Köpfe | Standard Schlange, Drache, Dino, Monster; Auswahl nach Neustart erhalten; rechts/oben/links/unten anatomisch korrekt, kürzester Drehweg ca.130ms | BLOCKED |
| Mimik | Idle/Blink/Zunge/Blick, Essen ≤180ms und ≤1.08×, Gefahr, Pause/Schlaf, Hurt → Dead; Reduce Motion unterdrückt Zusatzbewegungen | BLOCKED |
| Pfad / Wachstum | Mehrfaches Essen, enge Kurven, legaler auslaufender Schwanz; Abstand und Verbindung ohne diagonale Abkürzung; Fotos bleiben aufrecht | BLOCKED |
| Ränder | Klassische Wand erkennbar, Todesmeldung erst nach sichtbarem Kontakt; Relaxed horizontal/vertikal und an Ecken ohne Querlinie oder fehlende Wrap-Kopie | BLOCKED |
| Steuerung | Nur Wischgesten; schnelle zwei Kurven, kein 180°-Turn; HUD-Taps starten keine Bewegung; keine Richtungsbuttons oder D-Pad-Einstellung | BLOCKED |
| Pause / Fortsetzen | Pause, Fotos-/Einstellungssheet, Spielwahl, Schließen, Hintergrund, Anruf, erneutes Öffnen; keine unbeabsichtigten Ticks; Swipe setzt ausdrücklich fort | BLOCKED |
| Speicherwarnung | Spiel pausiert, komponierte Fototexturen freigegeben; nächster Swipe baut sie einmalig neu auf; Auswahl, Score und Körper bleiben | BLOCKED |
| Rekorde / Einstellungen | Höchste gefressene Anzahl je bestehender Kategorie, Neustart der App, Speicherfehleranzeige; neuer Preferences-Key, alte Keys unverändert | BLOCKED |
| Kleine / große Fenster | Kleine iPhones und große Innenfenster; Safe Areas, HUD, keine elliptischen Fotos; laufende Runde bei Größenwechsel unverändert; neue Runde nutzt neue Maße | BLOCKED |
| Orientierung | Bestehendes iPhone-Hochformat bleibt gesperrt; kein vorgetäuschter Fold-Hardwaretest | BLOCKED |
| Barrierefreiheit | VoiceOver-Schrittmodus, beschriftete HUD-/Galerieaktionen, große Schrift, Deutsch/Englisch/Arabisch, LTR-Spielkoordinaten | BLOCKED |
| Sound / Haptik | Silent Mode, Ton aus, lokale und globale Haptik aus, Hintergrund/Anruf, Musik einer anderen App und Rückkehr zum Feed | BLOCKED |
| 60 / 120Hz | Ziel 60 FPS; 3 / 100 / 300 Segmente und 1 / 100 Fototexturen auf echten 60/120Hz-Geräten mit Instruments/Game Performance messen, Aufnahme und Messwerte ablegen | BLOCKED |
| Restliche App | Feed/iCloud/Überspringen, Analyse, Spielwechsel, Käufe/Ads/Onboarding unverändert durchlaufen | BLOCKED |

Die bestehende Snake beginnt mit drei Körperzellen. Ein einzelnes Foto ist testbar; eine einzelne
Körperzelle wird nicht künstlich eingeführt. Die laufende Runde bleibt wie zuvor im App-Prozess;
über einen Prozessneustart bleiben Galerie, Einstellungen und Rekorde erhalten, nicht die komplette Runde.
