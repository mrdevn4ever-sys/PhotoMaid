# HERMES MASTERPROMPT — BESTEHENDES SWIFT-iOS-SNAKE IN »SNAKEPHOTO« UMGESTALTEN

## Rolle & Auftrag
Du bist der verantwortliche Senior-iOS-/SpriteKit-Entwickler, SwiftUI-UX-Designer und QA-Engineer. Die Snake-App **besteht bereits als Swift-iOS-Projekt**. **Erstelle KEINE neue App, kein neues Repository und keine Parallelimplementierung.** Prüfe den vorhandenen Quellcode und modernisiere die BESTEHENDEN Gameplay-, Menü-, Renderer- und Datenpfade zu einer hochwertigen Fotogalerie-Snake-Erfahrung. Nutze das mitgelieferte `SnakePhoto_Swift_iOS_Kit` (Originalsprites + SVGs + Sounds) als verbindliche neue Bildsprache.

Arbeite direkt im vorhandenen Repository. Bewahre Bundle-ID, Signing-Konfiguration, lokale Daten, vorhandene Store-/Monetarisierungsintegration, Rekorde, Einstellungen und funktionierende Spiellogik. Keine Datenmigration ohne Bedarf. Vorhandene Tests beibehalten und erweitern. Wo Ist-Zustand und Annahmen kollidieren, zuerst Code prüfen; NICHT raten.

## 0 — Zuerst repo-auditieren
1. Alle App-Targets, Deployment-Version, Swift-/Xcode-Version, Architektur und aktuellen Einstiegspunkte ermitteln.
2. Herausfinden, ob das Gameplay aktuell SpriteKit, SwiftUI Canvas, UIKit oder eigene Engine nutzt. Beibehalten, sofern kompatibel; SpriteKit als visuellen Renderer integrieren, wenn technisch sinnvoll. Keine unnötige Komplett-Neuschreibung des Gameplay-Modells.
3. Game Loop (Grid/continuous), FPS, Kollisionsmodell, Snake-Positionen, Input, Punkte, Rekorde, Audio, Pause/Resume, Rotation, iPad-Layout und Datenhaltung nachvollziehen.
4. Eine kurze Ist→Soll-Matrix schreiben und vor jeder Änderung die zu ersetzenden Stellen markieren.
5. Ein Backup/Commit der Ausgangsbasis sichern, keine vorhandenen Daten löschen.

## 1 — Asset-Integration
Alle benötigten PNGs aus `Xcode/SnakeHeads.atlas`, `SnakeBody.atlas`, `SnakeFood.atlas`, `SnakeUI.atlas` und Hintergründe/Sounds korrekt in das vorhandene iOS-Target kopieren. Texture-Atlas-Namen beibehalten; Kollisionen vorhandener Asset-Namen sauber auflösen. Alle nicht mehr benötigten bisherigen Snake-Platzhalter/alten doppelten Grafikpfade aus der App-Oberfläche entfernen, alte Modelle und andere Spielfunktionen nicht zerstören. Die beiliegenden `.svg` sind editierbare Quellen; für die App die PNGs verwenden. `Swift/SnakeArt.swift` und `Swift/SnakePhotoTextureComposer.swift` sind nützliche Vorlagen und müssen an den Projektstil angepasst werden. Jede Datei nachweislich im korrekten Target einbinden.

## 2 — Look: echter 2D-Cartoon-Schlangenkopf
- `head_idle_01` als Standard-Schlangenkopf. Andere Frames: `head_idle_02...06`, `head_look_left`, `head_look_right`, `head_eat_01`, `head_eat_02`, `head_surprised`, `head_hurt`, `head_dead_01`, `head_dead_02`, `head_sleep`.
- Kein realistischer/3D-Schlangenkopf, keine generische Kreis-Kopf-Grafik. Der Kopf ist ein deutlich erkennbarer, eigenständiger 2D-Cartoon-Kopf mit Schnauze, Augen und Mimik.
- Kopfsprite ist in der PNG immer nach rechts ausgerichtet. Bei Bewegungsvektor (dx,dy) `zRotation=atan2(dy,dx)` mit kürzestem Winkelweg **sanft** interpolieren; kein hartes Drehen um 90°. Bei abruptem Richtungswechsel z. B. 100–160 ms visuelle Drehdauer, aber die logisch korrekte Bewegung/Kollision beibehalten.
- Natürliches Idle: leichtes Wippen/Atmen, gelegentlich Blinzeln, gelegentlich Zunge; sparsame subtile Skalierung (z.B. ±2 %), Augen-/Blickzustände gezielt. Fressen: Mund 100–180 ms öffnen, kurzes Squash/Stretch bis max. 1.08×. Gefahr: überraschter Blick. Game Over: kurzer Hurt-Frame und danach Dead-Frame, keine aggressive Explosion.
- Zusätzliche Köpfe auswählbar: `dragon_idle`, `dino_idle`, `monster_idle` sowie deren blink/eat/dead. Auswahl persistent speichern. Anfänglich Standard grüne Schlange.

## 3 — Eigene Galerie-Fotos als echter Schlangenkörper
- Im bestehenden Spiel eine hochwertige, vollständig lokale Fotoauswahl anbieten: SwiftUI `PhotosPicker`/PhotosUI für iOS 16+ (bei älterer Zielversion kompatiblen Systempicker). Einzelne Fotos und Mehrfachauswahl, Reihenfolge ändern, Auswahl entfernen, auf Wunsch Album verwenden falls mit der gewählten System-Picker-API technisch möglich; keine falsche Behauptung einer frei lesbaren Albumliste.
- **Privacy:** Nur aktiv ausgewählte Fotos nutzen. Keine pauschale Vollzugriffsberechtigung auf die Fotomediathek verlangen, wenn PhotosPicker genügt. Niemals Cloud-/Backend-/KI-Upload; keine Telemetrie mit Foto-Inhalten. HEIC, JPEG, PNG, Bildrotation/EXIF, iCloud-Items/Downloadfehler und widerrufenen Zugriff behutsam behandeln.
- Nur lokal notwendige verkleinerte Bilder speichern, z.B. im Application Support mit `NSFileProtectionComplete`, ohne Original-Bilddaten unnötig zu duplizieren. Bei Löschung vollständig aus lokalem Cache entfernen. Zum Start vorhandene Auswahl wiederherstellen; bei fehlenden Fotos Platzhalter statt Crash.
- Jedes sichtbare Segment ist eine **echte rund zugeschnittene Galerie-Fototextur** mit dünnem weissem Innenrand und grünem Aussenring. `segment_ring.png` über die **einmalig vorgerenderte** quadratische Foto-Textur legen: Kreismaske Ø160 px innerhalb 256×256, center (128,128). Platzhalter `segment_placeholder.png` nur ohne Fotos.
- Foto-Auswahl zyklisch (Foto 1,2,3,... wieder von vorn), optional mischen. Anzahl vorhandener Fotos unabhängig von Snake-Länge. Wenn die Schlange Futter frisst, wächst sie gemäss bestehender Spielregel um weitere Foto-Segmente. Bei Wachstum **kein** Foto willkürlich aus der Galerie importieren: die bereits gewählte Reihenfolge bestimmt das nächste Segment.
- Wichtig: Zwischen den Foto-Kreis-Segmenten liegt ein **kontinuierlicher farbiger Körper** (z. B. vom Mittelpunktspfad abgeleitetes SpriteKit-Stroke/segmentierte Capsule/Texture). Keine sichtbaren Lücken, keine schwebenden Fotokugeln. Schwanz einbinden. Verbindung hinter Segmenten zeichnen. Galerie-Fotos vorzugsweise aufrecht lesbar lassen, NICHT mit dem Kopf rotieren.
- Performance: Ein Foto einmal auf 256×256 reduzieren, kreisförmig maskieren und mit Rahmen zu einem SKTexture verbinden; pro Foto/Charakter-Design cachen. Nicht pro Frame neue UIImage-/SKTexture-Objekte erzeugen. Nicht pro Segment einen SKCropNode dauerhaft erzeugen: Apple weist auf dessen zusätzliche Offscreen-Renderkosten hin. Bei 100+ Segmenten nur sichtbare Sprites nutzen, Reuse/Pool und Batch Rendering so weit möglich; effizienter Texture-Atlas für statische Grafiken.

## 4 — Bewegung (wesentlich für das ganze Spiel)
- Das **vorhandene logische Spielmodell** bleibt autoritativ: Grid-Spiele behalten Raster, Schritt-Timing und Tile-Kollisionen; bestehende Continuous-Modelle behalten ihr Kollisionsmodell. Visuelle Interpolation darf NICHT eine geänderte Hitbox vortäuschen oder Todesfälle auslösen, bevor die gerenderte Position erkennbar ist.
- Kopf bewegt sich mit Zeitdelta in `update(_:)`, nicht mit einem ruckartigen Positions-Sprung im Bild. Dazwischen Positionen interpolieren; richtungsabhängige Kopf-Rotation mit shortest-angle interpolation.
- Eine **History/Arc-Length-Bewegungsspur** aufbauen, der die Körper-Fotosegmente mit konstanten Abständen folgen. Rundungs-/Kurven-Interpolation (z. B. Catmull–Rom mit kontrollierten Tangenten oder quadratische Bézier) glättet die Optik, ohne logisch verbotene Eck-Abkürzungen einzuführen. Bei Grid-Logik sicherstellen, dass alle Segmente dem tatsächlich erlaubten Weg folgen.
- Körperverbindungen hinter den Fotos als zusammenhängenden, leicht dicker werdenden, organischen 2D-Tubus zeichnen; sanfte, ruhige Kurven; Kopf und Segment 1 müssen ohne visuelle Lücke anschliessen. Fotoabstand skalieren, damit die Schlange bei jedem Spieltempo zusammenhängend bleibt.
- Eingaben: Die Schlange läuft weiterhin automatisch; Richtung per Swipe über das Spielfeld ändern. Optionales Overlay-D-Pad (Assets `ui_up`, `ui_down`, `ui_left`, `ui_right`) in Einstellungen aktivierbar. Keine unbeabsichtigten 180°-Turns, schnelle Wischserien sauber puffern/validieren, Input-Latency niedrig. HUD-Bereiche nicht als Spielfeldgesten interpretieren.
- Mobile Touch-Fläche: Bei Hochformat und Querformat; Safe Areas, Dynamic Island, Notch, iPad/Fold keine Elemente abschneiden. Bei sehr langer Schlange adaptive Kamera/Zoom begrenzen, Fotos gut erkennbar halten.

## 5 — Futter und visuelles Feedback
- Nutze `food_apple`, `food_star`, `food_heart`, `food_gem`, `food_grapes`, `food_donut`, `food_cheese`, `food_cake`, `food_pizza` als wechselnde Grafiken. Bestehende Regeln fürs Sammeln/Punkte/Power-Ups unverändert, Bild ist nur Skin, kein ungewolltes Extra-Power-Up.
- Beim Fressen: kurzes, dezentes Skalieren des Futters; `fx_collect_01..04` als Glow/Sparkle-Frames, passendes `sfx_collect.wav`, haptisches Feedback falls in Settings aktiviert. Effekte dürfen nicht die Steuerung blockieren.
- Kollision gegen Wand/eigenen Körper: aktuelle logische Regeln respektieren; optional `sfx_game_over`, `head_hurt` → `head_dead_01` verwenden.

## 6 — UI/UX: Premium, einfach, passend zum neuen Look
- Primärstil: frisches tiefes Grün, sanfter Wald-Spielhintergrund `bg_forest_day`, optional Nacht-Skin `bg_forest_night`; Spielfeldmitte frei und kontraststark. Keine chaotischen Verläufe, keine überladenen Menüflächen.
- Startscreen im bestehenden App-Navigationsfluss: grosser Kopf, klare CTA `Spielen`, Galerie-Auswahl (`Fotos auswählen`), Design-Picker, Einstellungen, Rekord. Aktuelle Menüführung nur soweit ersetzen, wie für neue Experience nötig.
- Gameplay: Punkte und Rekord oben in sicherem HUD, Pause links, ggf. Leben nur falls bisher eine Lebensmechanik existiert; NICHT künstlich 3 Leben einbauen. Buttons `ui_pause`, `ui_play`, `ui_back`, `ui_settings`.
- Pause-Overlay, Galerie-Auswahl, Spielfigur-Auswahl, Game-Over-Screen mit Punkte/Rekord/Wiederholen/Zurück; konsistente Übergänge und VoiceOver für SwiftUI-Bedienelemente.
- Foto-Picker darf laufenden Gameplay-Zustand nicht verlieren; pausieren/fortsetzen stabil. Keine überlappenden Controls bei kleinen Displays.
- Die Original-Grafiken sind jeweils 256×256 PNG und enthalten teilweise Rand: in SpriteKit bei Bedarf transparenzbewusst skalieren/positionieren. Keine fotorealistischen Aufkleber oder gemischten Stilrichtungen.
- UI-Strings mit vorhandener Lokalisierung lösen; Deutsch als Ausgangssprache, keine hartcodierten Worte im Bild (die Sprites enthalten kein UI-Text).
- Optional reduzierter Bewegungseffekt (Reduce Motion) und stummgeschalteter Ton berücksichtigen.

## 7 — Performance, Stabilität, Sicherheit
- Ziel stabile 60 FPS auf realistischen iPhones, iPad adäquate Skalierung. Kein unbedachtes Rendern aller Albumfotos oder aller Segmenttexturen in voller Kameraauflösung. Maximal 256px Spritetextur pro Bild standardmässig, Gerätetest kann bei Bedarf höhere Auflösung bestimmen.
- Ressourcenverwaltung bei Background/Foreground, Unterbrechung, Low-Memory und UI-Sheet-Übergängen. Keine Leaks durch Texture-Caches/Observers. Levelwechsel sauber aufräumen.
- Teste u.a. 0/1/10/100 Fotos; 1/100/300 Segmente; 60 und 120-Hz Displays; schnelles Swipen/mehrfaches Essen; Suspend und Wiederaufnahme; iPad, grosse/kleine iPhones; Portrait/Landscape je nach existierendem Orientation-Support.
- Niemals User-Fotos in Logs oder Analyse-Services loggen. Nicht alle Fotos anfordern. Fehlerzustände benutzerfreundlich erklären.

## 8 — Pflichtprozess, verifizierbarer Abschluss
**In Reihenfolge:** Audit → Integration der Ressourcen → Fotoauswahl + Cache → Snake-Kopfanimation → Körper-Rendering + Pfadfolge → UI → Sounds/Haptics → Regressionstests → visuelle Prüfung/Performance-Check → dokumentierter Abschluss.

**Erledigt ist der Auftrag nur, wenn:**
- Bestehendes Projekt lässt sich weiterhin öffnen und die Änderungen sind darin integriert, keine zweite App.
- Sämtliche vorgesehenen Sprite-/Soundressourcen vorhanden und korrekt geladen.
- Echte ausgewählte User-Galeriefotos werden rund und erkennbar als Snake-Körper dargestellt; keine beliebigen Demobilder als angebliche Galerie-Fotos.
- Kopf zeigt anatomisch immer in Bewegungsrichtung, dreht sichtbar sanft, animiert Blink/Eat/Dead; wählbare Skins funktionieren.
- Körper bildet durchgehend **eine** Schlange, folgt ohne Springen und mit physikalisch/kollisionslogisch korrektem Weg. Wachstum funktioniert.
- Keine Regression von Punktestand, Rekord, Game Over, Restart, Touch, Pause, Rotation, Onboarding, existierenden Käufen oder Einstellungen.
- Keine Foto-Leaks, keine versteckten Uploads, keine unkontrollierten Cache-Duplikate.
- Erstelle Tests und eine kurze Matrix PASS/FAIL/BLOCKED pro Feature; **nie** behaupten, iOS-Build oder Gerätetest sei bestanden, wenn keiner stattgefunden hat.

**Kosten-/Build-Verbot:** KEINE GitHub Actions, KEINE bezahlten macOS-Runner, KEIN TestFlight-Upload, KEINE externen bezahlten APIs, KEINE App-Store-Submission auslösen, ausser ich gebe es ausdrücklich frei. Du kannst auf Windows statische Analyse, Unit-Testdesign und Quellcodeprüfung machen. Falls für eine echte iOS-Buildprüfung macOS/Xcode nötig ist, als BLOCKED dokumentieren und meinen Entscheid abwarten. Keine GitHub-Workflow-Minuten ohne Zustimmung verbrauchen.

**Abschlusslieferung:** Geänderte Dateien und Zweck, Commit(s), Integrationsnachweis, Screenshot/Screen-Recording NUR falls aus einem real ausgeführten Simulator-/Device-/Preview-Prozess, Liste aller Tests mit belegbaren Ergebnissen, verbleibende echte Blocker. Weder Erfolg simulieren noch offene Arbeit als erledigt kennzeichnen.
