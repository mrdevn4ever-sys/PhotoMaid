# Foto-Snake (16.10.2026)

> **Aktuell: SnakePhoto-Umbau.** Cartoon-Köpfe, SpriteKit, bis zu 100 lokal gespeicherte
> PhotosPicker-Fotos, Galerie-Reihenfolge sowie Schließen/Pause/Einstellungen im sicheren HUD.
> Bewegung ausschließlich per Wischgesten. [Aktueller Stand und native Prüfergebnisse](snakephoto/TESTFLIGHT_VERIFICATION.md).
> Der folgende ursprüngliche Bericht beschreibt die Vorgängerversion aus Build 11–12.

Die freiwillige Pause im Feed und bei Analysen bietet [Memory](PHOTO_MEMORY.md) und Foto-Snake.
Die Umsetzung liegt auf `feat/iphone-duo-games` und ist in TestFlight Version 1.0, Build 11 enthalten.
Apple-Verarbeitung und interne Verteilung sind [bestätigt](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38952167636).

## Spielfläche und Bedienung

- Das Feld füllt das gesamte Fenster, auf schmalem und großem Display. Keine Navigationsleiste,
  Richtungstasten, Start-/Pause-, Weiter- oder Einrichten-Tasten während des Spiels. Nur Schließen
  bleibt als sichtbarer Button; Punkte und Bestwert liegen als kompakte Anzeige über dem Feld.
- Der erste Swipe startet und bestimmt die erste Richtung, einschließlich links. Weitere Swipes
  lenken; direktes Umkehren in den Körper bleibt gesperrt. Zwei Richtungswechsel können gepuffert werden.
- Nach Verlassen oder App-Wechsel bleibt die Runde pausiert. Ein Swipe setzt fort. Nach Spielende
  startet ein Swipe eine neue Runde. Das Spiel holt während einer Pause keine Schritte nach.
- Fotoquelle, Modus und Tempo werden vor dem Spielen gewählt. Beim erneuten Öffnen kann dort
  dieselbe Runde fortgesetzt oder eine andere vorbereitet werden.
- Der Kamerakopf sammelt Bilder und verlängert seinen Fotostreifen. Jedes Bild zählt genau einen Punkt.
  Der persönliche Rekord wird bei jedem neuen Maximum sofort lokal gespeichert.
- Klassisch endet beim Randkontakt, entspannt läuft gegenüber weiter. Eine Selbstkollision beendet
  beide Modi. Drei Tempi: 320, 220 oder 140 ms je Schritt.
- Die Rastergröße ergibt sich vor einer Runde aus dem tatsächlichen Fenster. Während einer aktiven
  Runde bleiben Körper, Futter, Punkte und logisches Raster beim Größenwechsel erhalten; die Darstellung
  füllt die neue Fläche. Die nächste Runde nutzt die neue Rastergröße. Bilder werden proportional beschnitten.
- VoiceOver bietet benannte Richtungs-, Pause- und Neustartaktionen ohne sichtbare Steuerknöpfe.
  Richtungen bleiben auch in RTL physisch gleich. Mit VoiceOver wird schrittweise gespielt.
- Hohe Gerätetemperatur pausiert. Das eigentliche Spiel lädt weder Fotos noch Analyseergebnisse nach.

## Eigene Fotos

Zufällig aus Mediathek, Favoriten oder Album/Fotoordner einschließlich Unteralben, alternativ ein bis
achtzehn manuell gewählte Fotos oder Symbole ohne Fotozugriff. Bis zu zwölf nutzbare Bilder werden
für eine Zufallsrunde vorbereitet; eine Quelle mit nur einem Bild funktioniert ebenfalls.

Vorschauen mit 512 × 512 bleiben im RAM. Memory und Snake halten getrennte Bildspeicher.
iCloud-Laden für die Vorbereitung ist ausdrücklich wählbar und anfangs aus. Ausgeblendete Bilder,
verborgene Alben und Tresorfotos sind ausgeschlossen. Zugriffsentzug oder nachträgliches Verbergen
verwirft eine betroffene Runde. Abgebrochene/verspätete Vorbereitung ersetzt keine neuere Runde.

Der verdeckte Feed bleibt an derselben Position. Die Analyse läuft weiter und wird durch einen
Spielwechsel nicht beendet. Das Spiel verändert weder Originale noch Fotoentscheidungen oder Löschzahlen.
Der gemeinsame Spielekontext behält die Rückkehr zu Analyseergebnissen außerhalb der Vollbildrunde.

## Prüfung

Die gesamte Core-Suite besteht nach der Swipe-Umstellung (423 Swift-Testing- und 24 XCTest-Fälle).
Zusätzliche native Tests prüfen Erststart, Neustart nach Spielende und Größenwechsel ohne Spielverlust.
Die aktuelle native Swipe-/Vollbildabnahme besteht: drei UI-Fälle auf iPhone und drei auf einem großen
Fenster, einschließlich Fotoaufnahme, Rekord, Schließen, Wiederöffnen und Hintergrundpause.
Die echten Aufnahmen wurden angesehen; alte Aufnahmen mit Richtungstasten sind abgelöst.
Aktuelle Ergebnisse und die ausdrücklich offene echte Duo-Abnahme stehen in
[IPHONE_DUO_AND_GAMES.md](IPHONE_DUO_AND_GAMES.md).
