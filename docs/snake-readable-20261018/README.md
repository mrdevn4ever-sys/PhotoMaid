# Foto-Snake: größere Fotos und Vogelperspektive

**Historischer Zwischenstand:** Ein anschließender Nutzerauftrag ersetzt die quadratischen,
überlappungsfreien Fotos durch runde, überlappende Segmente und überarbeitet die Start-UX.
[Aktueller Bericht](../snake-ux-20261018/README.md). Die ursprünglichen Prüfprotokolle unten bleiben erhalten.

Arbeitsstand vom 18.10.2026, bestehendes Projekt `PhotoMaid`, Branch `feat/iphone-duo-games`.
Ausgangspunkt `e9da9dbf1aca9605120a3011281e3ff03154c604`. Kein neues Spiel, Repository oder App-Target.
Keine GitHub Actions, bezahlten Aufrufe oder Uploads für diesen Auftrag. **Nicht in Build 15 enthalten.**

[Vollständige Dateiliste](changed-files.txt) · [Maschinenlesbare Ergebnisse und Quellprüfsummen](RESULTS.json)

## Umsetzung

- Fotokacheln nutzen die ganze Textur statt eines kleinen Kreises im gepolsterten Atlas-Rechteck.
  Abgerundete Quadrate, Radius 33 % der Seitenlänge, über 90 % der quadratischen Bildfläche vor Rahmen.
  Bei 44–50 pt beträgt der grüne Rahmen 1,50–1,71 pt. Die mittlere freie Bildkante bleibt mindestens 41 pt.
- Gemeinsame Geometrie für Raster, Fotos, Kopf, Wachstum und Randübergänge. Der Kopf und jedes Foto
  bewegen sich weiter entlang der bestehenden orthogonalen Historie. Ein grüner Körper mit runden
  Verbindungen folgt auch den dazwischenliegenden Ecken. Die Fotozentren nehmen keine diagonale Abkürzung.
- Das gröbere Raster schafft ausreichend Platz für 44–50-pt-Fotos, auch wenn zwei Nachbarn gleichzeitig
  eine 90°-Kurve passieren. Der genaue Abstand berücksichtigt die abgerundete Kontur. Der neue Schwanz
  wächst erst, sobald Platz zum vorherigen Foto entsteht. Fotokacheln überdecken einander dabei nicht.
- Ein halbes Rasterfeld Sicherheitsraum pro Bildschirmrand hält ganze Fotos und den drehenden Kopf
  sichtbar. Im entspannten Modus überblenden vollständige Kacheln auf beiden Seiten des Übergangs.
  Es gibt keine beschnittene Kopie und keine Strecke quer durch das Spielfeld. Das sichtbare Raster
  richtet sich nach denselben Zellmaßen wie die unveränderte Kollisionslogik.
- Neuer eigener PNG-Atlas: **92 originale flache 2D-Frames**, je vier Blickrichtungen, einschließlich
  Schlange, Drache, Dino und Monster. Schnauze, Nasenlöcher und seitliche Augen sind von oben gezeichnet.
  Nach unten liegt die Schnauze unten; es wird kein frontales Gesicht auf den Kopf gestellt.
  Pupillen folgen der Blickrichtung, Lichtpunkte behalten ihre Bildschirmposition.
- Bestehende Animationszeiten bleiben bestehen: Blinzeln, Zunge, Fressen, Schreck, Schlaf und Game Over.
  Richtungswechsel interpolieren den kürzesten Winkel mit weichem Verlauf über 130 ms und überblenden
  die gerichteten Frames. „Bewegung reduzieren“ und die alternativen Designs bleiben erhalten.
- ImageIO berücksichtigt EXIF, dekodiert für den quadratischen Ausschnitt genügend Pixel und speichert
  höchstens 256 × 256 Pixel lokal. Panorama-Zwischendekodierung ist auf 2048 Pixel begrenzt.
  Zentrierter Aspect-Fill erhält das Seitenverhältnis; kleine Quellen werden nicht künstlich hochgerechnet.
- Der Texturcache erzeugt jede Fototextur einmal pro Foto/Bildinstanz. Er entfernt abgewählte Bilder
  und erkennt ein neu geladenes Bild mit derselben ID. Bis zu 100 Texturen werden zwischen allen
  Körper-Sprites geteilt, auch bei 300 Segmenten. Körper- und Randkopie-Sprites werden wiederverwendet.
  Die normalen Frames erzeugen keine Fototexturen. Das Bewegungsmodell liefert seine Stichpunkte
  einmal pro Frame für Körper und Verbindungen. Zielvorgabe des SKView bleibt 60 FPS.

## Maße aus dem tatsächlich kompilierten Core

Die Angaben beziehen sich auf die verfügbare **Spielfläche nach HUD und sicheren Rändern**, nicht
auf die gesamte physische Bildschirmauflösung. Quelle: [layout-samples.json](layout-samples.json).

| Spielfläche in pt | Raster | Rasterabstand | Fotoseite | Rahmen |
|---|---|---|---|---|
| 367 × 560 | 4 × 6 | 73,40 pt | 44,04 pt | 1,50 pt |
| 394 × 760 | 4 × 9 | 76,00 pt | 45,60 pt | 1,55 pt |
| 432 × 850 | 4 × 10 | 77,27 pt | 46,36 pt | 1,58 pt |
| 736 × 1024 | 8 × 12 | 78,77 pt | 47,26 pt | 1,61 pt |

Der Core-Test deckt zusätzlich 367 × 700 bis 936 × 1240 pt ab und prüft 44–50 pt sowie Rahmen ≤ 2 pt.
Das Raster hat bewusst weniger Zellen als zuvor. Die Regeln „eine Zelle pro Schritt“, Wachstum,
Wand-/Selbstkollision und der bestehende Richtungspuffer bleiben gleich. Frühere Rekorde bleiben
in ihren vorhandenen Rasterkategorien gespeichert; neue Raster besitzen wie bisher eigene Kategorien.

Eine laufende Runde behält beim Größenwechsel ihr logisches Raster und ihren Spielstand. Beim
Verkleinern passen sich die Fotos proportional an und können unter 44 pt sinken. Auch sehr schmale
Zoom-/Sonderfenster unter 367 pt können kleinere Fotos erfordern. Eine neue Runde verwendet das
aktuell passende Raster. Alte bereits gespeicherte kleine Vorschaubilder bleiben lesbar und erhalten
keine erfundenen zusätzlichen Bilddetails; für neue Importe gilt die verbesserte Dekodierung.

## Tatsächlich durchgeführte Prüfungen

| Prüfung | Ergebnis | Beleg / Umfang |
|---|---|---|
| Komplette lokale Core-Suite | **PASS, 469 Tests** | 445 Swift-Testing-Tests in 51 Suites + 24 XCTest, 0 Fehler; [Originalprotokoll](core-tests.log) |
| Snake-Tests innerhalb der Suite | **PASS, 29 Tests** | Regeln, Richtungspuffer, Punkte, Wachstum, Kollision, Galerie, Speicherung, Animation und Darstellung |
| Neue Geometrieprüfungen | **PASS, 8 Tests** | 1001 Kurvenpositionen, 1001 Wachstumsschritte, 2002 Randpositionen, alle Kopf-Drehwinkel einschließlich Fresspuls |
| Lange / fast volle Schlangen | **PASS** | 39/40, 49/50, 125/126 und 303/576 Zellen; echte Spielhistorie über 8 weitere Schritte und 7 Zwischenstände, alle Fotopaare geprüft |
| Swift-Syntax der nativen Änderungen | **PASS, 7 Dateien** | `swiftc -frontend -parse`; [leeres Erfolgsprotokoll](native-syntax.log), [Exitcodes](local-exits.json); keine SDK-Typprüfung |
| Ressourcen und Bestandsschutz | **PASS** | 77 ursprüngliche Ressourcen bytegleich, 92 neue 256px-RGBA-Frames, Alpha-Ränder und Blickrichtungen geprüft; [Protokoll](resource-audit.log) |
| Quellen der neuen Grafiken | **PASS** | SVG- und PNG-Prüfsummen gegen Generator geprüft; [Manifest](head-art.json), [Protokoll](art-audit.log) |
| Regeln, Fotodaten und Rekorde | **PASS, statisch** | `PhotoSnakeGame` unverändert zum Original; natives Spielmodell, Galeriearchiv und Rekordspeicherung bytegleich zum Ausgangsstand |
| Lokalisierungen und Steuerung | **PASS, statisch** | Alle 2702 Einträge unverändert, keine Richtungstasten hinzugefügt; vorhandene Wischsteuerung beibehalten |
| Statische Gestaltung | **PASS, angesehen** | Drei Telefonflächen, großes Fenster und alle 92 Kopf-Frames; siehe Bilder unten |
| Neuer iOS-Build / XcodeGen | **NOT RUN** | Kein Apple-SDK / Xcode in dieser Linux-Umgebung |
| UIKit-/SpriteKit-Integrationstests | **NOT RUN** | Native Tests für EXIF, Panorama, Cache, Foto-Reihenfolge, Fortsetzung und Atlas-Laden ergänzt bzw. angepasst; benötigen iOS-Testhost |
| Native Animation / Gerät / 60 FPS | **NOT RUN** | Kein Simulator- oder Geräteprofiling; Core-Geometrie und statische Vorschauen ersetzen diesen Nachweis nicht |

Lokale Swift-Version: [Swift 6.4.1, Linux](swift-version.txt). Ausführung aus dem bereits vorhandenen
Docker-Cache mit `--pull never --network none`, ohne externe Abhängigkeiten nachzuladen:

```sh
swift test --build-system native --disable-automatic-resolution
swiftc -frontend -parse PhotoMaid/Features/Snake/PhotoSnakeBoard.swift \
  PhotoMaid/Features/Snake/SnakeArt.swift PhotoMaid/Features/Snake/PhotoSnakeView.swift \
  PhotoMaid/Features/Snake/SnakePhotoLibrary.swift PhotoMaid/Features/Games/PhotoGamesView.swift \
  PhotoMaidTests/PhotoSnakeModelTests.swift PhotoMaidTests/SnakePhotoIntegrationTests.swift
python3 scripts/check_snakephoto_integration.py
python3 scripts/assets/make_snake_topdown.py --check
git diff --check
```

Der erste breite lokale Wiederholungslauf scheiterte vor Testbeginn an Speicherplatz. Ausschließlich
eigene unreferenzierte temporäre Docker-Kopien dieses fehlgeschlagenen Starts wurden entfernt.
Der anschließend vollständig ausgeführte Testlauf ist oben als PASS belegt. Ein erster statischer
Design-Probeweg enthielt einen fehlerhaften Testpfad für ungerade Zeilenzahlen; der Probeweg wurde
korrigiert und neu kompiliert. Die finale Vorschau verwendet gültige laufende Runden.

## Angesehene Entwurfsvorschauen

**Diese Bilder sind statisch erzeugte Designprüfungen, keine iOS-Screenshots oder Store-Assets.**
Sie verwenden die tatsächlichen Koordinaten aus dem kompilierten Core-Probeprogramm, die neuen
Atlas-PNGs und vorhandene [CC0-Testfotos mit Quellen](../../app-store/media/SOURCES.md).
Sie zeigen die Spielfläche ohne das unverändert vorhandene native HUD.

- [Drei Telefon-Spielflächen](static-phone-design.png)
- [Großes Fenster, keine Duo-Abnahme](static-wide-design.png)
- Alle Animationen und Richtungen: [Schlange](head-review-snake.png), [Drache](head-review-dragon.png),
  [Dino](head-review-dino.png), [Monster](head-review-monster.png)

Erneut erzeugen: `SnakeLayoutProbe.swift` zusammen mit den vier darin verwendeten Core-Dateien
kompilieren und dessen Ausgabe in `layout-samples.json` schreiben; danach
`python3 scripts/assets/review_snake_readable.py`. Für Kopf-Neugenerierung ist lokal Inkscape nötig.
Die originale Kit-Grafik bleibt vollständig erhalten und wird nicht bearbeitet.

## Geänderte Dateien

| Datei / Verzeichnis | Änderung |
|---|---|
| `Sources/PhotoMaidCore/Games/PhotoSnakeLayout.swift` (neu) | Gemeinsame Maße, Kurvenabstand, Wachstum, ganze Randkopien, Aspect-Fill |
| `Sources/PhotoMaidCore/Games/PhotoSnakeViewport.swift` | Größeres Raster mit Sicherheitsrand für erkennbare Fotos |
| `Sources/PhotoMaidCore/Games/PhotoSnakeMotion.swift` | Bereits berechnete Punkte für die Verbindung wiederverwenden; Regeln und Bewegungsweg gleich |
| `Sources/PhotoMaidCore/Games/PhotoSnakeStyle.swift` | Bestehende Animation auf neue gerichtete Frames abbilden |
| `PhotoMaid/Features/Snake/PhotoSnakeBoard.swift` | Große Kacheln, verbundenes Raster, Sprite-Pools, neue Kopf-Interpolation und ganze Randüberblendungen |
| `PhotoMaid/Features/Snake/SnakeArt.swift` | Neuer Atlas, quadratische Texturkomposition, dünner Rahmen und Bildidentitäts-Cache |
| `PhotoMaid/Features/Snake/SnakePhotoLibrary.swift` | EXIF-gerechte, scharfe quadratische lokale Vorschaubilder |
| `PhotoMaid/Features/Snake/PhotoSnakeView.swift` | Neuer Kopf im bestehenden Startmenü und in der Designauswahl |
| `PhotoMaid/Features/Games/PhotoGamesView.swift` | Neue Snake-Vorschau in der bestehenden Spieleauswahl |
| `PhotoMaid/Resources/SnakePhoto/SnakeTopDown.atlas/` (neu) | 92 neue PNG-Dateien; vollständige Dateiliste und SHA-256 in `head-art.json` |
| `project.yml` | Neuen Atlas dem bestehenden iOS-Target als Ressource zuordnen |
| `Tests/PhotoMaidCoreTests/PhotoSnakeReadableLayoutTests.swift` (neu) | Acht Geometrie-/Asset-Mapping-Prüfungen einschließlich langer Schlangen |
| `Tests/PhotoMaidCoreTests/PhotoSnakeGameTests.swift` | Erwartete Viewport-Größen dem neuen Raster anpassen |
| `PhotoMaidTests/PhotoSnakeModelTests.swift` | Native Viewport-Erwartungen anpassen; Erhalt laufender Runde weiter prüfen |
| `PhotoMaidTests/SnakePhotoIntegrationTests.swift` | Atlasrichtungen, EXIF, volle Fotofläche, Panorama und Cache-Ersetzung |
| `scripts/check_snakephoto_integration.py` | Neuer Atlas sowie Erhalt von Regeln, Daten und aktuellen Übersetzungen prüfen |
| `scripts/assets/make_snake_topdown.py` (neu) | Reproduzierbare eigene SVG-/PNG-Grafiken und Prüfsummen |
| `scripts/assets/SnakeLayoutProbe.swift` (neu) | Tatsächliche Core-Koordinaten für die statische Designkontrolle |
| `scripts/assets/review_snake_readable.py` (neu) | Reproduzierbare, ausdrücklich statische Kontaktbögen |
| `CLAUDE.md`, `docs/PHOTO_SNAKE.md`, `docs/IMPLEMENTATION_STATUS.md` | Aktuellen Stand und auftragsbezogene CI-/Upload-Sperre dokumentieren |
| `docs/snake-readable-20261018/` (neu) | Dieser Bericht, Messwerte, Grafiken, Prüfsummen und unveränderte finale Testprotokolle |

Fotoauswahl, PhotosPicker, Quellen Mediathek/Favoriten/Ordner, iCloud-Vorgabe, Reihenfolge/Entfernen,
lokales Archiv, Swipe-Belegung, Richtungspuffer, Pause/Fortsetzung, Punkte, Rekordformat, Einstellungen,
Sounds und Futterdesigns werden weiterverwendet. Die Paare- und Feed-Funktionen wurden nicht verändert.
