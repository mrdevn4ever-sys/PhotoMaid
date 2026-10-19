# Foto Blocks · Implementierung und Abnahme

Stand 19.10.2026, bestehendes Repository und App-Target. Zu Auftragsbeginn gab es keine Blocks-Implementierung.
Neue Core-Regeln und native SwiftUI-Oberfläche sind in den vorhandenen Spielebereich eingebunden.
Snake-Dateien sind gegenüber dem Arbeitsstand zu Beginn dieses Auftrags bytegleich. Seine damals
noch nicht veröffentlichten UX-Änderungen werden mit Build 16 ebenfalls ausgeliefert.

**Ausgeliefert: TestFlight 1.0 (16), von Apple verarbeitet und intern verteilt am 19.10.2026.**
Foto Blocks lädt iCloud-Fotos standardmäßig. Die finale Abnahme und Prüfgrenzen stehen unten.

## Regeln und Zustände

Eigenes 9×17-Feld, sechs verbundene Formen mit 2, 3 und 5 Zellen (`pebble`, `shoot`, `arch`, `petal`,
`bough`, `fern`). Gedämpfte Türkis-, Flieder-, Apricot-, Grün-, Blau- und Rosatöne, helle Konturen,
kleine zusätzliche Formmarkierungen und eine gestrichelte Landevorschau. Keine Fotos in Blockzellen,
keine übernommenen Spielgrafiken, Musik, Abhängigkeiten oder fremder Spielcode.

Die deterministische, serialisierbare Engine besitzt `ready`, `playing`, `clearing`, `discovered`,
`gameOver` und eine unabhängige Pause. Ein gespeicherter Zufallszustand mischt jede Form genau einmal
pro Beutel. Rotation normalisiert Koordinaten und prüft kleine seitliche bzw. aufwärts gerichtete
Ausweichschritte (am Boden bis zu zwei Zeilen für die lange Form). Boden und belegte Zellen verwenden dieselbe Kollisionsprüfung. Festsetzen nach
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

## Ausgelieferter TestFlight-Build

**PhotoMaid 1.0 (Build 16)** wurde am 19.10.2026 aus `a17daf7` tatsächlich als Release archiviert,
signiert und hochgeladen. Apple bestätigt Verarbeitung und interne Verteilung um **00:18:22 UTC**.
Alle drei Privacy-Manifeste der exportierten IPA bestehen. Derselbe App-Quellstand besteht die
finale native CI; nach dieser Prüfung wurden keine App-Dateien mehr geändert.
[TestFlight-Bericht mit originalen Build-/Privacy-/Apple-Belegen](photo-blocks-20261018/testflight/README.md).

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
und höchstens 550 ms Gestendauer. Der letzte schnelle Bewegungssample bleibt beim ortsgleichen
Touch-Ende erhalten; nach längerem Stillhalten verfällt er. Ein Soft-Drop-Wechsel erhält den
prozentualen Schwerkraftfortschritt, statt alte Normalfall-Zeit in viele schnelle Zeilen umzudeuten. Bewegung darf nie zugleich Tap-Rotation auslösen. Fingerabbruch,
Pause und Festsetzen beenden Soft Drop. Ein sichtbarer Pauseknopf ersetzt die optionale Zwei-Finger-Geste.
Keine Bewegungstasten. Haptik bei Rotation, Hard Drop, Reihen und Fotoabschluss.

## Datenschutz und Tresor

Die nachgereichte Anforderung „Icloud ist ein muss auch bei blocks“ ersetzt die ursprüngliche
Offline-Vorgabe: **iCloud-Fotos werden standardmäßig über Apples Fotos-Framework geladen**, auch
für die Fotoauswahl. Es gibt keine externe Fotoübertragung oder eigene Cloud-Anbindung.

`PhotoGamePhotos.gameCandidates` ist die gemeinsame verbindliche Quelle für Hintergründe UND
den vorhandenen `StudioMediaPicker`: aktuelle Leseberechtigung, intakte Verbergen-Liste, nur Bilder,
`cleanupMedia` ohne ausgeblendete/ausgenommene Alben und ausstehende Löschungen, zusätzlicher Tresorfilter.
Die Quelle ist zusätzlich gesperrt, solange neu gewählte Albumfilter noch nicht zum geladenen Snapshot passen.
Der Snapshot vermerkt die tatsächlich abgefragten Albumfilter; normale Bibliotheksaktualisierungen
mit unveränderten Filtern machen dadurch kein Hintergrundflackern. Kein System-PhotosPicker: Er könnte nicht gelöschte Tresor-Originale in seiner eigenen Auswahl zeigen.
Der bestehende App-Picker erhält einen opt-in sicheren Spiele-Modus; andere Werkzeuge behalten ihr Verhalten.

Die gemeinsame `PreviewPipeline` lädt mit `allowNetwork: true`, exakter Größenanforderung
und maximal 1280 Pixel langer Kante. Aktuelles und nächstes Foto werden asynchron vorbereitet und wiederverwendet;
höchstens zwei Hintergrundbilder bleiben im RAM. Unveränderte Sichtbarkeit und wiederholte Vorbereitung
derselben Bilder brechen laufende Downloads nicht ab. Der bestehende, auf 48 MiB begrenzte Thumbnail-Lader
liefert lokal zuerst und lädt fehlende Picker-Vorschauen aus iCloud; die Spielzugriffsprüfung gilt vor
dem Cachezugriff und nach asynchronen Ergebnissen. Kein neuer PhotoKit-Manager, keine eigenen Disk-Bildcaches,
keine Originaldateien, Analyse, Bild-Uploads, externe KI, Spiel-Tracking- oder Benachrichtigungsaufrufe.
Die bestehende Werbung der übrigen App und ihr Privacy-Manifest wurden nicht verändert.

Vor dem Laden, nach jedem asynchronen Ergebnis und vor Anzeige werden Zugriff und Tresor erneut geprüft.
Generationstoken verwerfen verspätete Ergebnisse. Sichtbarkeits-/Berechtigungsänderung invalidiert
Hintergrund, vorbereitete Bilder und Auswahl-Vorschauen; Auswahl-IDs werden erneut gefiltert. Der
AppModel-Tresorpfad invalidiert Blocks ausdrücklich. Picker-Zellen geben Bilder beim Verlassen frei,
der Picker leert seine Thumbnail-Puffer und zeigt im Hintergrund keine Medien. Bei fehlendem,
nicht herunterladbarem oder nicht mehr erlaubtem Foto erscheint ein neutraler Verlauf. Während
des asynchronen Ladens bleibt das Spiel bedienbar; beim Fortsetzen oder der nächsten Vorbereitung
können fehlgeschlagene Bilder erneut angefordert werden.
Ein stabiler, deduplizierter Metadatenzyklus wiederholt erst nach Erschöpfung des jeweiligen Pools;
Neueste sortiert Datum/ID, Zufall verwendet einen reproduzierbaren Seed. Keine Foto-IDs im Archiv.

## Tatsächlich ausgeführte Prüfungen

**PASS, lokal:** Swift 6.4.1 unter Linux, offline aus vorhandenem Toolchain-Cache: 498 Core-Tests
(474 Swift Testing + 24 XCTest), davon 26 neue Blocks-Tests. Unter anderem Fallen, Boden/Steine,
Grenzen/Rotation, Mehrfachreihen und Verdichtung, 1/3/10 Abschnitte, 8+3-Übertrag, Board-Erhalt,
2-s-Entdeckungsphase, Pause, fortsetzbare Serialisierung, Beutel, Eingabeschwellen und Fotoreihenfolge.
Je 20 fortlaufende simulierte Levelwechsel auf 6×12, 9×17 und 14×28, mit realem Zustandsübertrag;
gezielte legale Board-Fixtures pro Abschluss. Separat 10.000 tatsächliche Engine-Eingaben mit
Pausen/Neustarts und Invariantenprüfung, ohne Board-Fixtures. Der Foto-Scope-Test simuliert erlaubte
IDs und nachträglichen Entzug; er ist ausdrücklich keine PhotoKit-/Tresor-Geräteabnahme.

**PASS, lokal:** Syntax-Parsing der 13 betroffenen nativen Produktionsdateien und zwei Apple-Testdateien;
kein Apple-SDK-Typcheck. 41 neue UI-Kennungen in 16 Sprachen, bestehender Katalog unverändert.
Snake-SHA-Baseline, unveränderte alte Rekordformate, Ressourcen-/Target-/Fotoquellenprüfung,
Quell-Privacy-Manifest und acht Tests des vorhandenen Privacy-Validators.
Ein erster Test-Compilefehler bei mutierenden `#expect`-Ausdrücken sowie drei falsche Fixture-Annahmen
sind korrigiert; ursprüngliche Fehlerlogs bleiben im Belegordner. Ein falscher anfänglicher
Privacy-Checker-Aufruf verlangte ein IPA-Hauptmanifest beim Prüfen einer Quelldatei; korrekt wiederholt PASS.

**PASS, native macOS-CI:** [Lauf 39175702951](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39175702951),
Quellstand `ace6169ee517ba23978196f881338214fd68e98b`: echter iOS-Simulator-Build, **73 native Unit-Tests**
(60 Swift Testing + 13 XCTest), sowie **iPhone 2/2 und großes Fenster 2/2 UI-Tests**, ohne Fehler oder Skip.
Die Core-Suite besteht dort ebenfalls alle 498 Tests. Xcode 26.6, iPhone 17 mit iOS 26.2;
das große Fenster ist ein iPad mini A17 Pro mit iOS 26.4.1, kein Faltgerät.

Sieben neue native Integrationsfälle prüfen Zwei-Bild-Fenster/Reuse, späte verbotene Ergebnisse,
eingeschränkten Zugriff/Fallback/Entzug, KeyValueStore-Fortsetzung neben alten Rekorden,
Speicherfehler mit Wiederholung, Zwei-Zeilen-Bodenausgleich und den wirklichen AppModel-Scope bei
noch nicht abgefragten Albumausschlüssen. Der UI-Test prüft echten Tap, Links-/Rechts-Wischen,
klassifizierten Hard Drop, Pause, Hintergrund/Fortsetzen, Fotoquelle und Rückkehr. Der bestehende
Snake-/Paare-Setup-Test besteht auf beiden Geräten ebenfalls. Alle **26 nativen PNG-Aufnahmen**
(einschließlich zwei Berechtigungsansichten) sind unverändert mit SHA-256 im Belegordner archiviert
und visuell geprüft; Start, Spiel, kompakte Pause, Fotoauswahl sowie die bestehenden Spiele.
Die vollständige Foto-Enthüllung/Levelserie wurde per Core-Test und ausgeführter Swift-Probe geprüft,
nicht per 20 manuell gespielten nativen Levels.

**Finale iCloud-Wiederholung PASS:** [Lauf 39178252940](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39178252940),
Quellstand `a17daf70456757869caec5508808f56ebc367c1e`: echter iOS-Build, **76 native Unit-Tests**
(63 Swift Testing + 13 XCTest), erneut alle 498 Core-Tests und **Blocks auf beiden Simulatoren 1/1 PASS**,
ohne Fehler oder Skip. Zehn neue native Integrationsfälle insgesamt; die drei zusätzlichen Fälle
prüfen iCloud-Freigabe/Weitergabe an den Lader, Wiederverwendung ohne erneuten Download, Fehler mit
anschließendem Retry sowie unveränderte Sichtbarkeit während eines laufenden Downloads. Der zuvor
vorhandene Entzugstest gilt auch für den nun netzwerkfähigen Lader. Sichtbarkeits-Notifications
werden ausdrücklich auf dem Main-RunLoop zugestellt. Alle zehn aktuellen Blocks-PNGs sind tatsächlich
angesehen und mit Prüfsummen archiviert; Start, Spiel, Pause, Fotoquelle und Berechtigungsdialog.

Diese Cloud-Tests verwenden kontrollierte Loader-/Berechtigungs-Seams. Die Simulatoren sind nicht
bei einer privaten iCloud-Fotomediathek angemeldet. Ein echter iCloud-only-Download unter realen
Netzbedingungen und echte Tresor-/Berechtigungswechsel auf einem Gerät bleiben deshalb offen.
Der freigegebene TestFlight-Lauf hat exakt denselben App-Quellstand als signierten
Release erneut gebaut; native Unit-Tests wurden dort nicht nochmals dupliziert. Die Quellprüfsummen stehen
in `final-app-source.json`.

Der native CI-Kurzbericht zählt null Compilerfehler und acht bestehende Compilerwarnungen.
Die normalisierte Warnmeldungsliste entspricht dem vorherigen Stand; keine neue Warnmeldung durch
die iCloud-Erweiterung. Die tatsächlichen Originalprotokolle bleiben erhalten.

Der erste iCloud-Build `39177621042` brach beim Typprüfen ab: Ein AppModel-Aufruf verwendete noch
den bisherigen Namen `restrictOfflineWindow`. Es wurden dort keine nativen Unit- oder UI-Tests
erfolgreich ausgeführt; nur die separate Core-Suite bestand. Der Aufruf ist in `a17daf7` korrigiert,
und der statische Audit durchsucht nun sämtliche nativen Swift- und Testdateien nach alten APIs.
Die tatsächlichen Fehlerbelege stehen unter `native-r4`.

**Noch nicht verifiziert:** reale iPhone-FPS/Temperatur/Akkulast, Instruments-Leaks, echte iCloud-only
Bibliothek, physisches Falten, VoiceOver und sämtliche 16 Sprachen auf echten Displays. Ein breites
Simulatorfenster ersetzt keine Falt-Hardware-Abnahme. Ein grüner Build ersetzt keine Rechtsprüfung.

## Eingaberegressionen und fehlgeschlagener Zwischenlauf

Der zweite native Lauf `39173827613` scheiterte in beiden Blocks-UI-Fällen an der Forderung
„Score nach Hard Drop > 5“. Dieser Bonus ist bei einem bereits am Boden liegenden Stein nicht
garantiert; der anschließende Test prüft stattdessen die tatsächlich klassifizierte Hard-Drop-Aktion.
Der bestehende Snake-/Paare-Test bestand jeweils. Dieser Zwischenlauf wird nicht als erfolgreich gewertet.

Die Untersuchung fand zusätzlich zwei echte Fehler: Ein ortsgleiches Touch-Ende überschrieb die
zuletzt gemessene Wischgeschwindigkeit mit null; beim Aktivieren von Soft Drop konnte angesammelte
Normalfallzeit in mehrere schnelle Zeilenschritte umgedeutet werden. Beides ist in der Engine korrigiert
und durch automatisierte Regressionstests abgesichert. Die tatsächliche Swift-Probe gegen alten und
neuen Quellstand dokumentiert **13 unbeabsichtigte Zeilenschritte vorher, null danach** sowie
`stationaryReleaseRecognizedHardDrop: false → true`.
[Vorher](photo-blocks-20261018/input-regression-before.json),
[nachher](photo-blocks-20261018/input-regression-after.json),
[ausgeführte Probe](photo-blocks-20261018/BlocksInputRegressionProbe.swift).
Der UI-Test nutzt nur im Simulator mit QA-Kompilierungsflag eine zusätzliche Accessibility-Diagnose
der wirklichen Input-Aktionen; keine Testeingaben umgehen den normalen Touchpfad. Diese Diagnose
und Touch-Koordinaten-Ausgaben werden nicht in den Release-Build kompiliert.

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
