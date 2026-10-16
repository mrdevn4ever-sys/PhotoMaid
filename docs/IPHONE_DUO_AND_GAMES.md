# PhotoMaid: iPhone Duo, Spiele und Bestwerte

Stand: 16.10.2026. Referenz: Apples [Duo-Vorbereitung](https://developer.apple.com/iphone-duo/prepare/) und [Adapt your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/).

## Verhalten

- Normales iPhone und Duo-Außendisplay: unterstützte Ausrichtung ausschließlich Hochformat, in `project.yml` und `Info.plist` identisch. Das Innendisplay behandelt Ausrichtung und Fenstergrößen systemseitig anders; seine Orientierung wird nicht durch eine künstliche Drehung des Inhalts erzwungen.
- Layoutwahl nach tatsächlich verfügbarer Fenstergröße und Dynamic Type. Keine Modellnamen, `UIScreen.main`-Abmessungen oder Annahmen über einen mittigen Falz. SwiftUI berücksichtigt die jeweiligen sicheren Ränder. Schwelle für die geteilte Arbeitsfläche: mindestens 620 × 400 Punkte; große Bedienungshilfenschrift behält eine vertikale, scrollbar erreichbare Anordnung.
- Aufgeklappter Aufräumfeed: Papierkorb links, Wischfläche rechts. Der Papierkorb zeigt echte, in PhotoMaid sichtbare Kandidaten und „Zurücklegen“. Endgültiges Entfernen bleibt im vorhandenen Papierkorb mit Auswahl, Limitprüfung und Systembestätigung. Die Feed-State-Machine und die Wischbelegung bleiben dieselben. Eine Größenänderung bricht eine laufende Geste ohne Entscheidung ab.
- Navigation: native `sidebarAdaptable`-Tableiste. Die fünf Ziele und ihre Navigation bleiben im `AppModel` erhalten.
- Heute und Aufräumen: Inhaltsgruppen wechseln zwischen einer und zwei Spalten, ohne ihre Identität zu wechseln. Fotos/Favoriten/Alben/Suche und alle anderen Verbraucher von `MediaGrid` erhalten mehr Spalten bei größerer Fensterbreite. Studio-Werkzeuge, Medienauswahl und Tresorraster passen ihre Spaltenzahl an.
- Fotoeditor: Vorschau und Werkzeuge nebeneinander auf breiten Fenstern, untereinander auf schmalen. Collage: große Bühne mit seitlich dauerhaft sichtbaren Werkzeugen im breiten Fenster; einklappbare Werkzeuge auf dem Außendisplay. Einstellungen, Verlauf, Papierkorb, Video- und Archivformulare begrenzen lange Zeilen. Onboarding begrenzt die Lesebreite. Betrachter, Video und Diashow verwenden weiterhin ihre proportional eingepasste, fensterbezogene Bühne.

## Spiele

- Memory: eigene Auswahl von 2–18 Bildern oder zufällig 6/12/18 Paare aus Mediathek, Favoriten oder Album/Ordner einschließlich Unteralben. Motive funktionieren ohne Fotozugriff. Fotoauswahl und Vorschauladen verändern keine Originale oder Feed-Entscheidungen. iCloud-Vorschauladen ist ausdrücklich wählbar.
- Das Raster wählt Spalten und Kartenhöhe gemeinsam anhand der verfügbaren Fläche; jede Karte bleibt mindestens 44 Punkte groß. Muss der Inhalt bei großer Schrift oder kleinem Fenster scrollen, bleiben Fehlpaare bis zum manuellen Umdrehen sichtbar. Gleiches gilt mit VoiceOver. Vorbereitete Fotos werden bei Ausblenden, Berechtigungsverlust und Tresoränderungen verworfen.
- Snake: Kamera als Kopf, eingesammelte Fotos als Filmstreifen. Klassisch mit Wänden oder entspannt mit umlaufendem Rand, drei Tempi, optionale Einzelschritte. Pfeile bleiben auch in RTL räumlich richtig. VoiceOver beschreibt Kamera, Foto, nächste Richtung und ein unmittelbar folgendes Hindernis. Der Spieltakt lädt keine Bilder und führt keine Analyse aus.
- Auf breiten Fenstern stehen Snake-Steuerung und Spielfeld nebeneinander. Das Feld wird nicht unter 256 Punkte Höhe verkleinert; bei Bedarf ist die Steuerung scrollbar erreichbar. Hintergrund, Spielwechsel, Vorbereitung und thermische Grenzen pausieren das Spiel.
- Memory startet die monotone Uhr beim ersten gültigen Aufdecken und stoppt bei Sieg. Hintergrund, Fotoauswahl, Vorbereitung und geschlossene Spielansicht zählen nicht. Nur gewonnene Runden erzeugen einen Zeitrekord. Snake speichert jedes neue Maximum gefressener Bilder sofort; Schließen verliert keinen bereits erzielten Rekord.
- Bestwerte liegen im bestehenden lokalen Core-Data-Key/Value-Store, ohne Foto-IDs oder Bilddaten. Memory wird nach Paarzahl, Fotos/Motiven und manuellem Umdrehen getrennt. Snake wird nach Modus, Tempo, Einzelschritten und Spielfeldgröße getrennt. Speicherung fehlgeschlagen: Rekord bleibt während der Sitzung sichtbar, mit Wiederholen-Aktion.
- Der Spiele-Dialog besitzt einen gemeinsamen Analysekontext über Spielwechsel hinweg. Das Ende der Analyse unterbricht kein Spiel. Die Bildschirm-Wachanforderung gehört der laufenden Analyse; Spiele, Diashow und Export geben jeweils nur ihre eigene Anforderung frei.

## Prüfung und tatsächliche Grenzen

- PASS: Core-Rekord-/Uhrtests (9); adaptive Rastertests (2), inklusive 280 Punkte Breite, 36 Karten und Bedienungshilfenschrift; bestehende 15 Spiellogiktests.
- PASS: alle bestehenden Übersetzungen unverändert, 90 neue Kennungen jeweils in allen 16 Sprachen; Katalogprüfung erfolgreich.
- PASS: lokale Swift-Syntaxprüfung und Privacy-Manifest-Prüfung einschließlich 8 Python-Tests. Dies ersetzt keinen Apple-Compiler oder Store-Upload.
- Native Build-, Integrations- und Screenshot-Ergebnisse werden nach den Actions-Läufen unten ergänzt.
- BLOCKED – echte Duo-Simulatorabnahme: Der verfügbare `macos-26`-Runner bietet Xcode 26.6 (17F113), iOS-Runtimes 26.2/26.4/26.5 und keinen Duo-Gerätetyp. Beleg: [Umgebungsprüfung 38920972484](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38920972484). Für vollständige, randfüllende Duo-Unterstützung verlangt Apple einen Build mit dem iOS-27.1-SDK. Ein mit SDK 26 erzeugter Build ersetzt diese Voraussetzung nicht.
- Der visuelle Workflow wählt einen Duo-Simulator, sobald vorhanden, andernfalls ausdrücklich einen iPad-mini-Simulator als breite Fensterprüfung. Nur dieser QA-Build erweitert `TARGETED_DEVICE_FAMILY` auf `1,2`; das Produkt bleibt iPhone. Diese Aufnahmen belegen Layouts auf einem großen Fenster, nicht Falten/Entfalten, Duo-Statusleisten, die echte innere Safe Area oder die Animation des Displays.
- Nach Verfügbarkeit von Xcode 27.1: mit dem neuen SDK neu bauen; echte äußere/innere Duo-Ansicht, beide inneren Ausrichtungen, Split View in beiden Positionen, Größenwechsel während Wischgeste/Memory/Fotoauswahl/Editor und Hintergrund-Tresorschutz prüfen. Keine erfundenen Duo-Screenshots als Abnahme ausgeben.

## Reproduzieren

```sh
gh workflow run ci.yml --ref feat/iphone-duo-games -f ui_tests=true -f qa_case=games -f ui_phase=fixtures
```

`PhotoGameVisualTests` nutzt echte SwiftUI-, PhotoKit- und Persistenzpfade auf zurückgesetzten Simulatoren mit beschrifteten synthetischen QA-Bildern. Gewonnene Memory-Runde, Rekord nach Neustart, Snake-Fotoaufnahme und Pause, unveränderte Feedposition, Hochformat, breite Arbeitsfläche und die Hauptseiten werden mit Screenshots und Accessibility-Bäumen dokumentiert. Zusätzlich gibt es große arabische Schrift sowie Favoriten-/Ordnerquellen. Kamera-, Kauf- und echte Falthardwareabnahmen sind damit nicht behauptet.
