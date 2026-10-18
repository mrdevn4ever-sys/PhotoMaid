# Foto-Snake: klarer Start, natürliche Scores, runde Fotos

18.10.2026 · bestehendes Projekt `PhotoMaid` · Branch `feat/iphone-duo-games`.
Fortsetzung des vorhandenen Arbeitsstands mit den bereits verbesserten Fotos und dem Vogelperspektiven-Kopf.
Keine neue App, kein neues Target, keine Actions, bezahlte Aufrufe oder Uploads. Noch nicht in TestFlight.

## Sichtbare Verbesserungen

- „Foto-Snake“ bleibt der klare Titel. **„Spiel starten“** ist ein großer gefüllter Primärbutton mit
  dunkler Schrift auf hellem Grün; die Fotoaktion ist ebenfalls eine gefüllte Schaltfläche. Mindestens
  52 pt Höhe, ausreichend Innenabstand und sichtbare Druck-/Deaktivierungszustände.
- Ein Tippen im Startmenü startet nach erfolgreichem Laden und der tatsächlichen Spielfeldanpassung.
  Ein zweiter Startschritt entfällt. Im vorbereiteten Spielfeld bleibt ein ausdrücklicher Startknopf
  verfügbar; später heißt er „Runde fortsetzen“ oder „Noch eine Runde“. Direkte Wischgesten bleiben möglich.
- „Fotos auswählen“ / „Fotos ändern“ öffnen die bestehende Galerie bzw. die Fotoeinrichtung. Ohne
  manuelle Auswahl ist Start deaktiviert und die Fotoaktion sichtbar. Mediathek, Favoriten, Alben/Ordner,
  PhotosPicker, Reihenfolge und Entfernen bleiben verfügbar.
- **„Andere Spiele“** bezeichnet den Rückweg zur Spieleauswahl. Der kurze Steuerhinweis lautet
  **„Wische auf dem Spielfeld, um die Richtung zu ändern.“** Zusätzliche Optionen inklusive iCloud
  stehen unter „Spiel anpassen“. iCloud ist weiter standardmäßig an; eine bewusste Abschaltung bleibt erhalten.
- HUD, Spielende und Rekorde verwenden **„Score: X“ / „Rekord: Y“**, ohne „Gefressen“. Ohne Rekord
  steht „Rekord: —“. Auch bei großer Schrift bleiben die Wörter sichtbar; ein zu großes Overlay kann scrollen.
- Starten durch bloßes Öffnen/Ändern von Fotos findet nicht statt. Automatisches Fortsetzen nach
  Hintergrundwechsel, Audio-Unterbrechung oder Speicherwarnung wird durch Zurücksetzen des Startauftrags verhindert.

## Fotos und Kopf

Die Fotogröße bleibt 44–50 pt auf den geprüften üblichen Telefon-Spielflächen. Die Textur verwendet
den vollen Kreisdurchmesser statt einer kleinen Maske mit Außenabstand. Der grüne Rand beträgt
etwa 1,00–1,14 pt. Zentrierter Aspect-Fill, ImageIO-Downsampling, bestehende lokale Speicherung und
der einmalige Bild-/Texturcache bleiben erhalten. Galerie-Vorschaubilder haben ebenfalls nur 1 pt Rand.

Neu manuell importierte Fotos erhalten nach Möglichkeit einen gesichtsgerechten Ausschnitt:
Apples Vision erkennt Gesichtsrechtecke einmal auf der vorhandenen Import-Hintergrundaufgabe.
Eine kleine Gruppe wird gemeinsam zentriert; wenn sie nicht in den Kreis passt, erhält das größte
Gesicht Vorrang. Ohne Erkennung bleibt der Ausschnitt zentriert. Keine Gesichtsdaten werden gespeichert
oder versendet. Bestehende Archivbilder und bereits vorbereitete Zufalls-Vorschaubilder werden nicht
neu geladen oder verändert. Die tatsächliche Vision-Erkennung benötigt noch den nativen iOS-Test.

Der Rasterabstand beträgt **87,5 % des Fotodurchmessers**, also **12,5 % Überlappung auf geraden
Strecken und an vollständigen Rasterpositionen**. Die Fotozentren folgen weiter dem bestehenden
korrekten orthogonalen Bewegungsweg. An engen 90°-Kurven steigt die Überdeckung vorübergehend
bis etwa **38,2 % des Durchmessers**. Sie wird durch feste Schichtung kontrolliert: Das Segment näher
am Kopf liegt über seinem Nachfolger; Randkopien behalten dieselbe Tiefe. Die Mittelpunkte etablierter
Fotos bleiben sichtbar. Ein neuer Schwanz erscheint hinter seinem Vorgänger, ohne plötzlich auf ihm zu liegen.
Damit werden für eine rein optische Anforderung keine neuen Spielregeln oder Bewegungswege eingeführt.

Ein separater Sicherheitsrand hält Kreise und den drehenden Kopf innerhalb der Spielfläche. Der
vorhandene Kopf aus echter Vogelperspektive mit vier Richtungen, 92 Frames und weicher Drehung
bleibt unverändert. Es wird keine Seitenansicht umgedreht. Die logischen Regeln, Richtungspuffer,
Tempi, Punkte, Rekorddaten und Foto-Reihenfolge wurden nicht geändert. Das Raster passt nun zum
Abstand der runden Segmente; laufende Runden behalten beim Größenwechsel ihr bestehendes Raster.

| Verfügbare Spielfläche | Raster | Fotodurchmesser | Rahmen |
|---|---|---|---|
| 320 × 480 pt | 6 × 10 | 44,95 pt | 1,02 pt |
| 367 × 560 pt | 7 × 12 | 45,33 pt | 1,03 pt |
| 394 × 760 pt | 8 × 17 | 44,29 pt | 1,01 pt |
| 432 × 800 pt | 9 × 18 | 44,19 pt | 1,00 pt |
| 736 × 1024 pt | 16 × 24 | 44,76 pt | 1,02 pt |

Werte aus dem tatsächlich kompilierten Core: [layout-samples.json](layout-samples.json). Weitere
größere Flächen sind in den Tests abgedeckt. Eine nachträglich verkleinerte laufende Runde kann
weiterhin kleinere Fotos erfordern. Alte Rekorde bleiben in ihren bisherigen Rasterkategorien erhalten.

## Durchgeführte Prüfungen

| Prüfung | Ergebnis |
|---|---|
| Komplette lokale Core-Suite | **PASS: 472 Tests**, 448 Swift Testing + 24 XCTest, 0 Fehler; [Originalprotokoll](core-tests.log) |
| Snake innerhalb dieser Suite | **PASS: 32 Tests**, einschließlich Wachstum, Kollision, Puffer, Fotoarchiv und Bewegungsdarstellung |
| Neue/angepasste Geometrie und Cropping | **PASS: 11 Tests**; 1001 Kurvenzustände, Wachstum, 2002 Randpositionen, alle Kopf-Drehwinkel, Gesichtsausschnitte |
| Lange / fast volle Schlangen | **PASS**: echte Historie mit 39, 49, 125 und 303 Segmenten; Sichtbarkeit und feste Schichtung geprüft |
| Native Swift-Syntax | **PASS**, 8 Dateien; Syntaxprüfung, keine Apple-SDK-Typprüfung; [Protokoll](native-syntax.log) |
| Ressourcen und Bestandsschutz | **PASS**: Original-Assets und 92 Kopf-Frames unverändert, Spielregeln, Modell, Archiv und Rekordspeicherung unverändert; [Audit](resource-audit.log) |
| Lokalisierung | **PASS**: drei Einträge geändert, drei ergänzt, jeweils 16 Sprachen; alle übrigen Katalogeinträge unverändert; [Prüfung](localization.log) |
| Statische visuelle Kontrolle | **PASS, angesehen**: UX-Layoutstudie und fünf Spielflächen, siehe unten |
| iOS-Build / Simulator / native UI-Tests / tatsächliche FPS | **NOT RUN**: hier kein Apple-SDK; keine CI gestartet |

Die Core-Suite lief mit [Swift 6.4.1 unter Linux](swift-version.txt), offline aus der vorhandenen
lokalen Toolchain. Die nativen Testfälle für Start-/Foto-Buttons, Resume, Score und iCloud wurden
angepasst, aber **nicht ausgeführt**. Die Syntaxprüfung beweist weder einen iOS-Build noch
korrekte SwiftUI-Darstellung auf einem Gerät. Die Vorgabe von 60 FPS bleibt ein ungeprüftes Geräteziel.

Lokale Befehle: `swift test --build-system native --disable-automatic-resolution`,
`swiftc -frontend -parse …`, `python3 scripts/android_strings_to_xcstrings.py --check`,
`python3 scripts/check_snakephoto_integration.py`, `git diff --check`.

## Vorschau

[Startmenü, Start-Overlay und runde Schlange](static-ux-study.png) · Spielflächen:
[320 pt](static-board-320.png), [367 pt](static-board-367.png), [394 pt](static-board-394.png),
[432 pt](static-board-432.png), [großes Fenster](static-board-736.png).

**Das sind statische Layoutstudien, keine iOS-Screenshots oder Store-Assets.** Die Darstellung von
HUD/Buttons ist stilisiert; Fotozentren stammen aus tatsächlichen Core-Runden. Bilder sind vorhandene
[CC0-Testfotos](../../app-store/media/SOURCES.md), keine persönlichen Nutzerbilder. Ein großes Fenster
ist keine Faltgeräte-Abnahme. `SnakeUXLayoutProbe.swift` und `review_snake_ux.py` erzeugen die Studien erneut.

## Geänderte Dateien dieses Folgeauftrags

Der vorangegangene Arbeitsstand wurde erhalten. [Vollständige Dateiliste](changed-files.txt) und
[Prüfergebnisse/Quellprüfsummen](RESULTS.json) unterscheiden diese Änderungen von den vorherigen.

| Datei | Verbesserung |
|---|---|
| `PhotoMaid/Features/Snake/PhotoSnakeView.swift` | Startablauf, gefüllte Buttons, Overlay, verständliche Navigation, HUD und große Schrift |
| `PhotoMaid/Features/Snake/PhotoSnakeBoard.swift` | Stabile Überlappungsreihenfolge, sauberer Schwanzaufbau, Randreserve |
| `PhotoMaid/Features/Snake/SnakeArt.swift` | Volle runde Fototexturen, dünner Rahmen, vorhandener Cache |
| `PhotoMaid/Features/Snake/SnakePhotoLibrary.swift` | Lokale Gesichtszentrierung beim manuellen Import |
| `PhotoMaid/Features/Snake/SnakeGalleryView.swift` | Dünnerer Rand der Galerie-Vorschauen |
| `Sources/PhotoMaidCore/Games/PhotoSnakeLayout.swift` | Kreisabstand, Schichtung, Randreserve, Gesichtsausschnitt-Geometrie |
| `Sources/PhotoMaidCore/Games/PhotoSnakeViewport.swift` | Raster zur bestehenden Fotogröße und neuen Überlappung |
| `PhotoMaid/Resources/ios_strings.json` | Sechs gezielte Snake-Texte in 16 Sprachen |
| `PhotoMaid/Resources/Localizable.xcstrings` | Passende native Katalogeinträge |
| `Tests/PhotoMaidCoreTests/PhotoSnakeReadableLayoutTests.swift` | Kurven, Überlappung, Sichtbarkeit, Gesichtsausschnitte |
| `Tests/PhotoMaidCoreTests/PhotoSnakeGameTests.swift` | Neue Rastermaße prüfen, Regeln unverändert weiter testen |
| `PhotoMaidTests/PhotoSnakeModelTests.swift` | Rastermaße anpassen; vorhandene Start-/Fortsetzungsprüfungen erhalten |
| `PhotoMaidTests/SnakePhotoIntegrationTests.swift` | Volle Kreisfläche und Rand statt der vorherigen Quadratmaske |
| `PhotoMaidUITests/PhotoGameVisualTests.swift` | Eindeutige Buttons, Direktstart, Pause/Resume und verlegte iCloud-Option |
| `scripts/check_snakephoto_integration.py` | Gezielte Textänderungen zulassen, restlichen Bestand weiter schützen |
| `scripts/assets/SnakeUXLayoutProbe.swift` (neu) | Tatsächliche Core-Runden für die statische Kontrolle |
| `scripts/assets/review_snake_ux.py` (neu) | Reproduzierbare, klar gekennzeichnete Layoutstudien |
| `CLAUDE.md`, `docs/IMPLEMENTATION_STATUS.md`, `docs/PHOTO_SNAKE.md` | Aktuellen UX-Auftrag und lokalen Prüfstatus festhalten |
| `docs/snake-readable-20261018/README.md` | Vorherigen Quadrat-Entwurf als historischen Zwischenstand kennzeichnen |
| `docs/snake-ux-20261018/` (neu) | Bericht, Messwerte, Dateiliste, Prüfsummen und Originalprotokolle |
