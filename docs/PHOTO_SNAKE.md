# Foto-Snake (16.10.2026)

Die freiwillige „Kurze Pause“ im Feed und bei laufender Bildanalyse öffnet eine Spielauswahl mit
[Foto-Memory](PHOTO_MEMORY.md) und Foto-Snake. Kein zusätzlicher Tab und kein automatischer Spielstart.
Die Umsetzung liegt auf `feat/iphone-duo-games` und ist noch nicht in TestFlight.

Die Befunde aus dem [ursprünglichen Audit](GAMES_FUNCTION_UI_AUDIT.md) sind im Code korrigiert.
Aktuell: [breite Spielfläche, dauerhafte Rekorde und nativer Prüfstatus](IPHONE_DUO_AND_GAMES.md).

## Spielen

- Der Kamerakopf bewegt sich auf einem Raster mit 12 × 16 Feldern. Eingesammelte Fotos verlängern
  den Fotostreifen um jeweils ein Feld und erhöhen den Spielpunktestand um eins.
- „Entspannt“ führt an einem Rand auf der gegenüberliegenden Seite weiter. „Klassisch“ beendet
  die Runde beim Randkontakt. Eine Kollision mit dem eigenen Körper beendet beide Modi.
- Drei Tempi: langsam (320 ms), normal (220 ms), schnell (140 ms pro Schritt).
- Wischgesten oder Richtungstasten steuern dieselben Regeln. Höchstens zwei Richtungswechsel
  werden vorgemerkt; direktes Umkehren in den eigenen Körper ist gesperrt.
- Der optionale Schrittmodus bewegt sich nur durch eine gültige Richtungseingabe oder „Vorwärts“.
  VoiceOver aktiviert ihn automatisch; Kamera- und Zielfoto-Positionen sind am Spielfeld lesbar.
  Physische Richtungen bleiben in rechtsläufigen und linksläufigen Sprachen gleich.
- Vorbereitete und neu gestartete Runden sind pausiert. Start und Fortsetzen erfolgen ausdrücklich.
  Beim Schließen, Spielwechsel, Wechsel aus der App und bei hoher Gerätetemperatur wird pausiert.
  Verstrichene Zeit wird beim Fortsetzen nicht durch zusätzliche Schritte nachgeholt.
- Der Spielstand bleibt beim Schließen innerhalb derselben App-Instanz erhalten. „Noch eine Runde“
  startet mit denselben Vorschauen neu; über die Fotoauswahl lässt sich neu aus derselben Quelle ziehen.
  Beim Beenden des Prozesses werden Spiel und Vorschauen verworfen.
- Der Punktestand gehört ausschließlich zum Spiel. Er trifft keine Fotoentscheidungen und verändert
  keine Löschzahlen, Freikontingente, Werbung oder Belohnungen.

## Fotos und laufende Analyse

- Zufällig aus der sichtbaren Mediathek, Favoriten oder einem gewählten Album/Fotoordner der Fotos-App.
  Ordner umfassen ihre Unteralben. Bis zu zwölf nutzbare Fotos werden vorbereitet; eine kleine Quelle
  funktioniert bereits mit einem Foto. Die Bilder wiederholen sich im wachsenden Streifen.
- Alternativ ein bis achtzehn Fotos manuell wählen oder ohne Fotozugriff mit Symbolen spielen.
  Videos, verborgene Alben und Tresorfotos sind ausgeschlossen. Es gibt keinen Rückgriff auf eine
  andere Quelle, wenn die gewählte Quelle keine nutzbaren Bilder enthält.
- Nur Vorschauen mit Zielgröße 512 × 512, nacheinander über die vorhandene Preview-Pipeline.
  iCloud-Downloads für die Spielvorbereitung sind zunächst aus und nur per ausdrücklichem Schalter erlaubt.
  Zufallsauswahl prüft höchstens die dreifache gewünschte Zahl von Kandidaten und überspringt unzugängliche
  Bilder. Während des eigentlichen Spiels werden keine weiteren Fotos geladen.
- Der gemeinsame Fotolader hält für Memory und Snake getrennte Vorschauen im RAM. Bilder und Kennungen
  werden für die Spiele nicht auf Platte gespeichert. Es gibt keine neuen Analyseaufträge, Änderungen
  an Originalen, Entscheidungen oder Uploads durch das Spiel.
- Fehlgeschlagene Fotoauswahl bewahrt die vorige Runde. Abgebrochene oder verspätete Ladeaufträge
  können keine neuere Runde überschreiben. Bei entzogenem Fotozugriff, entfernten oder in den Tresor
  verschobenen Spielbildern werden die betroffene Runde und ihre Vorschauen verworfen.
- Der verdeckte Feed pausiert Gesten und Wiedergabe; seine Sitzung und Position bleiben erhalten.
  Der echte Analysefortschritt bleibt erreichbar. Ein Analyseabschluss unterbricht die Runde nicht;
  „Ergebnisse ansehen“ führt freiwillig zur passenden Analyse zurück.

## Prüfstatus

Die acht Snake-Regeltests sowie fünf native Snake-/Fotolader-Tests bestehen. Geprüft sind
Start/Pause, Schrittmodus, Echtzeitmodell/Neustart, VoiceOver-Umschaltung, kleine Fotoquellen
und die Unabhängigkeit einer vorhandenen Memory-Runde.
Aktuelle Gesamtergebnisse, Screenshot-Belege und verbleibende Geräteprüfungen stehen zentral in
[IPHONE_DUO_AND_GAMES.md](IPHONE_DUO_AND_GAMES.md). GitHub Actions sind seit der ausdrücklichen
Freigabe am 16.10.2026 im Einsatz; ein neuer TestFlight-Upload wurde nicht durchgeführt.
