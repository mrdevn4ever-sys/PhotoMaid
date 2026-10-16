# Funktions- und UI-Audit: Memory und Snake

16.10.2026 · historischer Audit-Snapshot auf `feat/photo-memory-break`.

**Nachtrag:** F1–F5 wurden anschließend im Code korrigiert. Aktuelle Umsetzung, Bestwerte,
adaptive Arbeitsflächen sowie native Testbelege und Duo-SDK-Grenzen:
[IPHONE_DUO_AND_GAMES.md](IPHONE_DUO_AND_GAMES.md). Die folgenden Befunde und NOT-RUN-Angaben
beschreiben den Stand vor diesen Korrekturen.

**Ergebnis: Die Spielregeln bestehen die lokalen Prüfungen, die Einbindung und das Layout haben
fünf konkrete Befunde. Zwei davon sollten vor einer Auslieferung zuerst behoben werden.**
Dies ist ein Code-, Zustandsfluss- und Layout-Audit. Es wurden keine nativen Ansichten gerendert
und keine Simulator-/Gerätebedienung durchgeführt. Insbesondere sind die folgenden Layoutmaße
aus dem Code berechnet, keine Messungen eines Screenshots. Der Spielcode wurde für dieses Audit
nicht geändert; Bericht und wiederholbarer Invariantenlauf wurden ergänzt.

## Befunde nach Priorität

### F1 · P1 · Nachträglich ausgeblendete Fotos bleiben in beiden Spielen sichtbar

**Auslöser:** Eine Fotorunde vorbereiten, das Spiel schließen, eines ihrer Fotos oder sein Album
über „In PhotoMaid ausblenden“ ausblenden, dieselbe Runde wieder öffnen.

Die Erstauswahl nutzt `app.visibleMedia` und respektiert die Ausblendung. Die spätere
Validierung prüft jedoch ausschließlich PhotoKit-Zugriff, Existenz, Medientyp und Tresor.
`settings.hiddenMedia`, `settings.hiddenAlbums` bzw. die aktuelle sichtbare Menge kommen darin
nicht vor. Deshalb verwirft auch die Validierung nach `mediaRevision` die Runde nicht.
Die bereits geladenen Vorschauen bleiben abrufbar. Das widerspricht der bestehenden Bedeutung
„Medien und Alben, die PhotoMaid nirgends zeigt“.

**Beleg:** [PhotoGamePhotos.swift:129](../PhotoMaid/Features/Games/PhotoGamePhotos.swift#L129),
[Bildabruf:123](../PhotoMaid/Features/Games/PhotoGamePhotos.swift#L123),
[RootView.swift:118](../PhotoMaid/App/RootView.swift#L118),
[Ausblenden:748](../PhotoMaid/App/AppModel.swift#L748),
[HiddenView:160](../PhotoMaid/Features/Library/LibraryPages.swift#L160).
Der Datenpfad ist statisch belegt; die beschriebene Bedienfolge wurde nicht auf einem Gerät ausgeführt.

**Korrektur:** Eine gemeinsame aktuelle Sichtbarkeitsprüfung auch auf vorhandene Spielbilder
und vor dem Übernehmen neuer Vorschauen anwenden. Betroffene Bilder und Runde verwerfen.
Regressionen für ein einzelnes ausgeblendetes Foto, ein ausgeblendetes Album und spätere Wiederfreigabe ergänzen.

### F2 · P1 · Snake ist im Querformat zu klein; Steuerung konkurriert mit Scrollen

Die Spielfeldhöhe lautet `max(150, min(420, verfügbareHöhe - 290))`. Bis zu einer verfügbaren Höhe
von 440 pt wird deshalb immer ein nur 150 pt hohes Feld gerendert. Bei 12 × 16 Feldern ergeben sich
9,375 pt je Zelle und **7,375 pt je Fotokachel**. Das sichtbare Spielfeld ist dann nur 112,5 pt breit,
auch wenn die Ansicht viel breiter ist. Für das Kamerasymbol verbleibt nach 4 pt Innenabstand je Seite
rechnerisch kein Platz mehr.

Der komplette Spielbereich einschließlich Richtungstasten liegt zugleich in einem vertikalen
`ScrollView`. Das Tastenfeld allein hat mindestens 104 pt Höhe, zusätzlich zu Spielfeld, Punkten,
Hinweisen, Aktionsknöpfen und Seitenabständen. Bei etwa 300 pt verfügbarer Höhe passen diese
Elemente nicht gleichzeitig in den sichtbaren Bereich. Nach „Starten / weiter“ läuft die Uhr auch
während des erforderlichen Scrollens. Große Schrift verschärft das Problem.

**Beleg:** [PhotoSnakeView.swift:42](../PhotoMaid/Features/Snake/PhotoSnakeView.swift#L42),
[Steuerung:174](../PhotoMaid/Features/Snake/PhotoSnakeView.swift#L174),
[PhotoSnakeBoard.swift:14](../PhotoMaid/Features/Snake/PhotoSnakeBoard.swift#L14),
[Kamera-Innenabstand:60](../PhotoMaid/Features/Snake/PhotoSnakeBoard.swift#L60).
Geometrie statisch berechnet; konkrete native Darstellung und Gestenerkennung bleiben zu prüfen.

**Korrektur:** Einen eigenen kompakten bzw. horizontalen Spielaufbau mit gleichzeitig sichtbarer
Steuerung vorsehen. Spielfeldgröße und Rasterdarstellung aus dem tatsächlich verfügbaren Platz
ableiten. Analysefortschritt während des Spiels kompakt halten. Einen laufenden Echtzeitmodus
nicht in einen Bereich setzen, der für seine Bedienung gescrollt werden muss.

### F3 · P2 · Memory-Standardrunde kann während einer Analyse nicht vollständig sichtbar sein

Die Spaltenzahl hängt an Paarzahl und Size Class, nicht an der verfügbaren Höhe.
Bei 375 pt Ansichtsbreite, 16 pt Seitenrand und 8 pt Rasterabstand ergeben sich:

| Paare | Raster | Kartenbreite | Reine Rasterhöhe |
|---:|---|---:|---:|
| 6 | 3 Spalten, 4 Zeilen | 109 pt | 460 pt |
| 12 (Vorgabe) | 4 Spalten, 6 Zeilen | 79,75 pt | 518,5 pt |
| 18 | 6 Spalten, 6 Zeilen | 50,5 pt | 343 pt |

Zur Standardrunde kommen Analysekarte, Paar-/Zuganzeige, Aktionsknöpfe und Abstände hinzu.
Bei einem etwa 600 pt hohen Inhaltsbereich und beispielsweise 80 pt Analysekarte reicht der
Platz nicht für alle Karten gleichzeitig. Ein Fehlpaar wird dennoch nach 1,2 Sekunden verdeckt,
auch wenn sich eine der Karten inzwischen außerhalb des Ausschnitts befindet. Bei großer
Bedienungsschrift kommen nur zwei Spalten zum Einsatz; Scrollen ist dann erst recht vorgesehen.
Der bestehende VoiceOver-Sonderfall verhindert das automatische Verdecken nur mit aktivem VoiceOver.

**Beleg:** [PhotoMemoryView.swift:186](../PhotoMaid/Features/Memory/PhotoMemoryView.swift#L186),
[Raster:166](../PhotoMaid/Features/Memory/PhotoMemoryView.swift#L166),
[Fehlpaar-Timer:77](../PhotoMaid/Features/Memory/PhotoMemoryView.swift#L77).
Die Beispielhöhe der Analysekarte ist eine Modellannahme; der Rasterwert folgt direkt aus dem Code.

**Korrektur:** Die Rasterwahl auch an der Höhe ausrichten und die Analysekarte kompakt halten.
Wenn das Brett scrollen muss, Fehlpaare bis zum ausdrücklichen Umdrehen offen lassen oder eine
geeignete, einstellbare Betrachtungsdauer anbieten. Runden weiterhin mit 6/12/18 Paaren ermöglichen.

### F4 · P2 · Spielwechsel verliert nach Analyseabschluss den Rücksprung zu den Ergebnissen

**Auslöser:** Während Analyse A Memory öffnen, A fertig laufen lassen, „Spiele“ wählen,
anschließend Snake öffnen. Keine weitere Analyse läuft.

`watched` liegt als `@State` im jeweils neu erzeugten `PhotoGameAnalysisStatus`. Die Spielauswahl
ersetzt beim Wechsel den kompletten Unterbaum. Die neue Statusansicht übernimmt beim Erscheinen
nur `analysis.runKind`; nach dem Abschluss ist dieser Wert `nil`. Der Fertig-Hinweis samt
„Ergebnisse ansehen“ verschwindet, obwohl `stageByKind[A]` noch `.finished` enthält.
Die Analyseergebnisse selbst werden dadurch nicht gelöscht.

**Beleg:** [PhotoGameAnalysisStatus.swift:8](../PhotoMaid/Features/Games/PhotoGameAnalysisStatus.swift#L8),
[Initialisierung:34](../PhotoMaid/Features/Games/PhotoGameAnalysisStatus.swift#L34),
[Unterbaum-Wechsel:12](../PhotoMaid/Features/Games/PhotoGamesView.swift#L12),
[Analyseabschluss:366](../PhotoMaid/Infrastructure/Analysis/AnalysisController.swift#L366).
Statische Zustandsverfolgung; kein nativer Navigationstest vorhanden.

**Korrektur:** Den beobachteten Analysekontext in der gemeinsamen Pausenansicht halten und an die
Statuskomponenten weitergeben. Abschluss vor dem Spielwechsel sowie während einer wartenden zweiten
Analyse als Navigationstest abdecken.

### F5 · P2 · Wachhaltung während der Analyse hängt vom gewählten Spiel ab

Memory setzt bei laufender Analyse `isIdleTimerDisabled = true` und beim Verlassen pauschal
`false`. Weder Spielauswahl noch Snake übernehmen diese Verantwortung. Nach Memory → Spiele → Snake
ist die automatische Bildschirmsperre deshalb wieder aktiv, auch wenn dieselbe Analyse noch läuft.
Bei einer längeren Denk-/Lesepause kann das Gerät sperren; ohne aktiviertes Weiterlaufen im Hintergrund
wird damit die Analyse unterbrochen. Fortlaufende Eingaben beim Echtzeitspiel verhindern zwar die
normale Inaktivitätssperre, lösen den Zustandsfehler aber nicht.

**Beleg:** [PhotoMemoryView.swift:87](../PhotoMaid/Features/Memory/PhotoMemoryView.swift#L87),
[Freigabe:90](../PhotoMaid/Features/Memory/PhotoMemoryView.swift#L90),
[PhotoGamesView.swift:11](../PhotoMaid/Features/Games/PhotoGamesView.swift#L11),
[bisherige Analyse-Wachhaltung:57](../PhotoMaid/Features/Analysis/SmartReviewView.swift#L57).
Setzen und Zurücksetzen sind im Code belegt; die tatsächliche Systemsperre wurde nicht abgewartet.

**Korrektur:** Wachhaltung für die ganze Spielpause zentral verwalten, solange die relevante Analyse
läuft. Den Lebenszyklus auch mit Export/Slideshow abstimmen, statt globale Zustände aus einzelnen
Unteransichten pauschal zurückzusetzen.

## UI-Design und zusätzliche Prüfungen

Die im Code verwendete Markensprache passt: warme Hell-/Dunkel-Farben, Systemschrift mit Dynamic Type,
native Navigation, vorhandene SurfaceCards und Liquid-Glass-Knöpfe. Die freiwillige Pause benötigt
keinen weiteren Tab. Fotos werden proportional beschnitten. Snake bietet 48 pt hohe Richtungstasten
und physisch unveränderte Richtungen in RTL; Memory verbirgt die Identität verdeckter Karten vor VoiceOver
und berücksichtigt Reduce Motion. Der Symbolmodus funktioniert konzeptionell ohne Fotofreigabe.

Die Konfiguration ist derzeit recht formularartig. Für eine kurze Pause sollten Spielfeld und eine
klare Hauptaktion dominieren; Bildquelle und Optionen können kompakter angeordnet werden.
Zusätzliche Punkte für einen Design-Durchgang:

- **Zustände benennen:** „Bilder ändern“ öffnet bei Snake auch Modus und Tempo. „Starten / weiter“
  unterscheidet Erststart und Fortsetzen nicht. Bei einem fertigen Memory bezeichnet die Spielauswahl
  den Zustand weiterhin als „Runde fortsetzen“. Beschriftungen an den tatsächlichen Zustand anpassen.
- **Änderungen an Optionen erklären:** Tempo/Modus wirken erst beim Vorbereiten einer neuen Runde;
  „Runde fortsetzen“ im Konfigurationsbild übernimmt diese Änderungen nicht. Das muss erkennbar sein.
- **VoiceOver bei Snake vertiefen:** Das Brett nennt Kamera- und Fotoposition, aber weder aktuelle Richtung
  noch Körper-/Gefahrenpositionen. Schrittmodus ist vorhanden; Spielbarkeit, Fokusführung und Ansagen
  nach Kollision/Abschluss sind ohne Geräteprüfung nicht als vollständig barrierefrei abgenommen.
- **Schmale Ansichten prüfen:** Bei 320 pt logischer Breite und sechs Memory-Spalten bleiben nur
  41,33 pt Breite pro Karte. `minHeight: 44` sichert die Breite nicht ab. Dies ist eine berechnete
  Grenzkonstellation, kein Nachweis auf einem konkreten unterstützten Gerät.
- **Hauptthread messen:** `PhotoGamePhotos.allowed` fragt PhotoKit synchron ab; Memory ruft dies bei
  jedem Aufdecken für alle Rundenelemente auf. Auch Kandidatenfilter und Stichprobe laufen auf dem
  MainActor. Eine sichtbare Verzögerung ist nicht gemessen; unter paralleler Analyse/iCloud-Last profilen
  und gegebenenfalls die Prüfung revisionsbezogen bzw. außerhalb des UI-Threads vorbereiten.

## Was die lokale Prüfung trägt

| Bereich | Status | Nachweis / Grenze |
|---|---|---|
| Memory-Regeln und Quellenauswahl | PASS | sieben gezielt erneut ausgeführte Core-Tests |
| Snake-Regeln | PASS | acht gezielt erneut ausgeführte Core-Tests; Randmodi, Wachstum, Selbstkollision, voller Rasterabschluss |
| Zusätzliche Regel-Invarianten | PASS | 4.000 Snake-Runden, 546.182 Schritte; 340 Memory-Decks mit 85.000 Zufallstipps, danach alle abgeschlossen |
| App-/App-Test-Syntax | PASS | alle Swift-Dateien per `swiftc -frontend -parse`; keine SDK-Typprüfung |
| Sprachkatalog | PASS | 1.641 benutzte Kennungen, 2.629 Einträge, 16 Sprachen |
| Native Foto-/Modelltests | NOT RUN | sieben Memory- und fünf Snake-/Fotoladerfälle benötigen Apple-SDK; keine Abdeckung von F1/F4/F5 |
| Native UI-/Gerätetests für die Spiele | NOT RUN | keine vorhandenen Spiel-UI-Tests; kein Xcode in dieser Umgebung |
| Sichtprüfung, Dark Mode, Kontrast, VoiceOver, Dynamic Type | NOT RUN | Codepfade und Maße geprüft, keine gerenderten nativen Screens oder Bedienung |
| GitHub Actions / Push / TestFlight | NOT RUN | keine Actions-Minuten verbraucht und kein Upload |

Die Invarianten prüfen die echten Core-Quelldateien; sie simulieren kein UIKit oder PhotoKit.
Der wiederholbare Zusatzlauf liegt unter [scripts/qa/photo_games/main.swift](../scripts/qa/photo_games/main.swift).
[Prüfstand, Dateihashes und Layoutberechnungen](game-audit-20261016.json) halten den geprüften Stand fest.
Die bestehende komplette Core-Suite mit 409 Tests wurde für dieses Audit nicht noch einmal vollständig
wiederholt; hier wurden gezielt die 15 Spieltests erneut ausgeführt.

```sh
swift test --parallel --filter 'PhotoMemoryGameTests|PhotoSnakeGameTests'
swiftc -swift-version 6 -O Sources/PhotoMaidCore/Games/PhotoMemoryGame.swift Sources/PhotoMaidCore/Games/PhotoSnakeGame.swift scripts/qa/photo_games/main.swift -o /tmp/photomaid-game-audit
/tmp/photomaid-game-audit
```

Reihenfolge für die Behebung: F1 (Sichtbarkeit), F2/F3 (spielbare Größe ohne Zeitdruck beim Scrollen),
F4/F5 (durchgehende Analysepause), anschließend Beschriftungen und native Accessibility-/Designabnahme.
