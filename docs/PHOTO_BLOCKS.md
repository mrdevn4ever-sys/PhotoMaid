# Foto Blocks · Implementierung und Abnahme

Stand 18.10.2026, bestehendes Repository und App-Target. Zu Auftragsbeginn gab es keine Blocks-Implementierung.
Neue Core-Regeln und native SwiftUI-Oberfläche sind in den vorhandenen Spielebereich eingebunden.
Snake-Dateien sind gegenüber dem Arbeitsstand zu Beginn dieses Auftrags bytegleich; seine vorherigen,
noch nicht veröffentlichten UX-Änderungen gehören weiterhin zum gemeinsamen Arbeitsstand.

## Regeln und Zustände

Eigenes 9×17-Feld, sechs verbundene Formen mit 2, 3 und 5 Zellen (`pebble`, `shoot`, `arch`, `petal`,
`bough`, `fern`). Gedämpfte Türkis-, Flieder-, Apricot-, Grün-, Blau- und Rosatöne, helle Konturen,
kleine zusätzliche Formmarkierungen und eine gestrichelte Landevorschau. Keine Fotos in Blockzellen,
keine übernommenen Spielgrafiken, Musik, Abhängigkeiten oder fremder Spielcode.

Die deterministische, serialisierbare Engine besitzt `ready`, `playing`, `clearing`, `discovered`,
`gameOver` und eine unabhängige Pause. Ein gespeicherter Zufallszustand mischt jede Form genau einmal
pro Beutel. Rotation normalisiert Koordinaten und prüft kleine seitliche bzw. aufwärts gerichtete
Ausweichschritte. Boden und belegte Zellen verwenden dieselbe Kollisionsprüfung. Festsetzen nach
0,40 s, höchstens acht Verlängerungen durch Bewegungen am Boden; Hard Drop setzt sofort fest.
Eine einzige schwach angebundene `CADisplayLink` läuft mit Ziel 60 Hz. Keine Animations-Completion
ändert die Simulation. Hintergrund, Verlassen und Speicherdruck pausieren; Rückkehr verlangt Fortsetzen.

## Foto-Enthüllung und Levels

Der Fotobereich ist durch eine feste Maske im Fotokoordinatensystem verborgen. Pro entfernter Reihe
wächst die Maske von oben um exakt ein Zehntel. Die Fotomaske kennt weder Board-Zeilen noch deren
Verschiebung. Reihen werden 180 ms ausgeblendet, dann gemeinsam entfernt und der Rest verdichtet.
Mehrfachreihen decken mehrere Abschnitte auf. Bei 8 + 3 Reihen zeigt das alte Foto 100 %; nach dem
Übergang beginnt Level 2 bei 10 %. Kein Fortschritt geht verloren.

Bei vollständigem Foto pausiert die Simulation zwei Sekunden im Entdeckungszustand; Steine,
Raster und Landevorschau sind unsichtbar. Das ganze Foto wird proportional eingepasst, danach
erscheinen das unveränderte verdichtete Spielfeld und die nächste Form mit einem neuen Foto.
Beim Spielen füllt das Foto die Fläche proportional mit mittigem Beschnitt und 55 % Schwarzmaske.
Eine neue SwiftUI-Identität je Level verhindert eine rückwärts animierte Maske über dem neuen Foto.

Fallintervall in Sekunden: `0,16 + 0,72 × 0,90^(Level − 1)`; Exponent numerisch auf 1000 begrenzt.
Level 1: 0,880 s, Level 2: 0,808 s, Level 5: ca. 0,632 s; asymptotische Untergrenze 0,160 s.
Keine feste letzte Spielstufe. Die Runde endet nur, wenn die nächste Form nicht mehr hineinpasst.

## Punkte und lokaler Spielstand

5 Punkte pro gesetzter Form. Reihenbonus `20 × n × (n + 1)`: 40 / 120 / 240 / 400 für 1 / 2 / 3 / 4
gleichzeitige Reihen. Bonusmultiplikator +10 % je weiterem Level, maximal 2×. Hard Drop gibt zusätzlich
einen Punkt pro tatsächlich zurückgelegter Zelle; Soft Drop keine Zusatzpunkte. Anzeige: Score,
Rekord, Level, Reihen, Foto-Fortschritt und nächste Form. Game Over ergänzt die tatsächlich mit
verfügbarem Bild vollständig entdeckten Fotos; neutrale Hintergründe werden nicht als Foto gezählt.

Der vorhandene Core-Data-`KeyValueStore` speichert atomar unter dem neuen Schlüssel `games.blocks.v1`.
Das Archiv enthält Zahlen, Formen, Board, Beutel, Zeitreste sowie Fotoquellen-Typ und Zufalls-Seed. Keine Bilder,
Klartext-Foto-IDs oder Dateipfade. Alte Snake-/Paare-Rekordformate und Schlüssel bleiben unverändert.
Beschädigte/unplausible Snapshots werden vor Array-Zugriffen verworfen. Speichern bei gesetzten
Formen, Phasenwechsel und Pause; Fehler bleiben sichtbar und wiederholbar. Wiederherstellung immer
pausiert, Fotos werden ausschließlich aus dem aktuell erlaubten Bestand neu aufgelöst.
Quelle und Seed bleiben erhalten; eigene Auswahl muss nach Prozessneustart erneut gewählt werden,
statt unbemerkt auf die gesamte Mediathek auszuweichen.

## Eingaben und Oberfläche

Startansicht: Foto Blocks, „Entferne Reihen und entdecke deine Fotos.“, gefüllter Primärbutton
„Spiel starten“, eigener Foto-Button und drei kurze Gestenhinweise. Die Fotokonfiguration bietet
Zufall, Neueste, Favoriten und eigene Auswahl. Fehlende Fotos verhindern keinen Spielstart.
Pause: Fortsetzen, Neustart, Fotos ändern, Beenden; Game Over: Nochmal, Fotos ändern, Andere Spiele.
Die Spielfläche passt proportional in die verfügbare Safe Area; die Pause bleibt außerhalb des Boards.

Ein Touch-Recognizer trennt alle Eingaben. Unter 10 pt und bis 280 ms: genau eine Rotation.
Achsenentscheidung ab 12 pt und 1,15-fachem Richtungsübergewicht. Seitliches Ziehen wiederholt pro
`max(18 pt, 0,65 × Zellbreite)` und verarbeitet auch dünn verteilte Touch-Samples. Ab 18 pt nach unten
Soft Drop mit maximal 45 ms Fallintervall. Hard Drop erst bei mindestens 56 pt, mindestens 650 pt/s
und höchstens 550 ms Gestendauer. Bewegung darf nie zugleich Tap-Rotation auslösen. Fingerabbruch,
Pause und Festsetzen beenden Soft Drop. Ein sichtbarer Pauseknopf ersetzt die optionale Zwei-Finger-Geste.
Keine Bewegungstasten. Haptik bei Rotation, Hard Drop, Reihen und Fotoabschluss.

## Datenschutz und Tresor

`PhotoGamePhotos.offlineCandidates` ist die gemeinsame verbindliche Quelle für Hintergründe UND
den vorhandenen `StudioMediaPicker`: aktuelle Leseberechtigung, intakte Verbergen-Liste, nur Bilder,
`cleanupMedia` ohne ausgeblendete/ausgenommene Alben und ausstehende Löschungen, zusätzlicher Tresorfilter.
Kein System-PhotosPicker: Er könnte nicht gelöschte Tresor-Originale in seiner eigenen Auswahl zeigen.
Der bestehende App-Picker erhält einen opt-in Offline-Modus; andere Werkzeuge behalten ihr Verhalten.

Die gemeinsame `PreviewPipeline` lädt ausschließlich mit `allowNetwork: false`, exakter Größenanforderung
und maximal 1280 Pixel langer Kante. Aktuelles und nächstes Foto werden asynchron vorbereitet und wiederverwendet;
höchstens zwei Hintergrundbilder bleiben im RAM. Der bestehende, auf 48 MiB begrenzte Thumbnail-Lader
erhält für den Picker ebenfalls keine Netzwerkfreigabe. Kein neuer PhotoKit-Manager, keine Disk-Bildcaches,
keine Originaldateien, Analyse, Bild-Uploads, externe KI, Spiel-Tracking- oder Benachrichtigungsaufrufe.
Die bestehende Werbung der übrigen App und ihr Privacy-Manifest wurden nicht verändert.

Vor dem Laden, nach jedem asynchronen Ergebnis und vor Anzeige werden Zugriff und Tresor erneut geprüft.
Generationstoken verwerfen verspätete Ergebnisse. Sichtbarkeits-/Berechtigungsänderung invalidiert
Hintergrund, vorbereitete Bilder und Auswahl-Vorschauen; Auswahl-IDs werden erneut gefiltert. Der
AppModel-Tresorpfad invalidiert Blocks ausdrücklich. Picker-Zellen geben Bilder beim Verlassen frei,
der Picker leert seine Thumbnail-Puffer und zeigt im Hintergrund keine Medien. Bei fehlendem,
nicht lokal verfügbarem oder nicht mehr erlaubtem Foto erscheint ein neutraler Verlauf.
Ein stabiler, deduplizierter Metadatenzyklus wiederholt erst nach Erschöpfung des jeweiligen Pools;
Neueste sortiert Datum/ID, Zufall verwendet einen reproduzierbaren Seed. Keine Foto-IDs im Archiv.

## Tatsächlich ausgeführte Prüfungen

**PASS, lokal:** Swift 6.4.1 unter Linux, offline aus vorhandenem Toolchain-Cache: 494 Core-Tests
(470 Swift Testing + 24 XCTest), davon 22 neue Blocks-Tests. Unter anderem Fallen, Boden/Steine,
Grenzen/Rotation, Mehrfachreihen und Verdichtung, 1/3/10 Abschnitte, 8+3-Übertrag, Board-Erhalt,
2-s-Entdeckungsphase, Pause, fortsetzbare Serialisierung, Beutel, Eingabeschwellen und Fotoreihenfolge.
Je 20 fortlaufende simulierte Levelwechsel auf 6×12, 9×17 und 14×28, mit realem Zustandsübertrag;
gezielte legale Board-Fixtures pro Abschluss. Separat 10.000 tatsächliche Engine-Eingaben mit
Pausen/Neustarts und Invariantenprüfung, ohne Board-Fixtures. Der Foto-Scope-Test simuliert erlaubte
IDs und nachträglichen Entzug; er ist ausdrücklich keine PhotoKit-/Tresor-Geräteabnahme.

**PASS, lokal:** Syntax-Parsing der 13 betroffenen nativen Produktionsdateien und zwei Apple-Testdateien;
kein Apple-SDK-Typcheck. 40 neue UI-Kennungen in 16 Sprachen, bestehender Katalog unverändert.
Snake-SHA-Baseline, unveränderte alte Rekordformate, Ressourcen-/Target-/Offline-Quellenprüfung,
Quell-Privacy-Manifest und acht Tests des vorhandenen Privacy-Validators.
Ein erster Test-Compilefehler bei mutierenden `#expect`-Ausdrücken sowie drei falsche Fixture-Annahmen
sind korrigiert; ursprüngliche Fehlerlogs bleiben im Belegordner. Ein falscher anfänglicher
Privacy-Checker-Aufruf verlangte ein IPA-Hauptmanifest beim Prüfen einer Quelldatei; korrekt wiederholt PASS.

**Native CI: ausstehend.** Mit der nachgereichten Freigabe für Testminuten werden iOS-Build,
native Unit-Tests und echte Simulatoransichten ausgeführt. Fünf neue native Integrationstests prüfen
Zwei-Bild-Fenster/Reuse, späte verbotene Ergebnisse, eingeschränkten Zugriff/Fallback/Entzug,
KeyValueStore-Fortsetzung neben alten Rekorden und Speicherfehler mit Wiederholung. Der neue UI-Test
prüft Start, Gesten, Pause/Hintergrund, Fotoquelle und Rückkehr; der bestehende Spiele-Setup-Test
sichert Snake/Paare zusätzlich. Abschließende CI- und TestFlight-Belege werden hier ergänzt.

**Noch nicht verifiziert:** reale iPhone-FPS/Temperatur/Akkulast, Instruments-Leaks, echte iCloud-only
Bibliothek, physisches Falten, VoiceOver und sämtliche 16 Sprachen auf echten Displays. Ein breites
Simulatorfenster ersetzt keine Falt-Hardware-Abnahme. Ein grüner Build ersetzt keine Rechtsprüfung.

## Belege, Dateien und rechtliche Restpunkte

[Belegordner, vollständige Dateiliste und Wiederholungsbefehle](photo-blocks-20261018/README.md).
[Statische Engine-Ansicht](photo-blocks-20261018/static-engine-review.png) aus tatsächlich ausgeführter
Swift-Engine; ausdrücklich keine iOS-Screenshots. Zwei bestehende CC0-Testfotos mit Herkunft/Hashes
in `static-review-provenance.json`; sie werden nicht in die App eingebaut.

Die Mischung der Formen, 9×17-Proportionen, Farben, Dekoration, Foto-Enthüllung und Oberfläche ist
eigenständig implementiert. Daraus folgt keine rechtliche Freigabe. Für „Foto Blocks“ fehlen eine
Marken-/Namensrecherche und eine fachliche Prüfung der konkreten Gesamtgestaltung in Zielmärkten;
verbleibende Marken-, Urheber- und wettbewerbsrechtliche Risiken können technische Tests nicht ausschließen.
Keine fremden Spielassets oder geschützten Produktnamen im sichtbaren Blocks-Produkt/Marketing.
