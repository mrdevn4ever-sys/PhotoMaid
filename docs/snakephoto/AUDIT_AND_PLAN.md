# SnakePhoto-Umbau: Bestandsaufnahme und Änderungsgrenzen

Ausgangsbasis: `4bfba4f` (lokaler Sicherungsbranch `backup/snakephoto-before-20261016-4bfba4f`).
Auftrag: vorhandenes PhotoMaid-Target modernisieren; kein neues Projekt/Repository.
**Aktuelle Nutzerregel: ausschließlich Wischgesten zur Bewegung, keine Richtungstasten, auch nicht optional.**
Diese Präzisierung ersetzt die optionale D-Pad-Forderung des beigefügten Masterprompts.
**Kostenregel dieses Auftrags: keine GitHub Actions, bezahlten Runner/APIs oder TestFlight-Uploads ohne neue ausdrückliche Freigabe.**
Die frühere allgemeine Actions-Freigabe gilt hier nicht.

## Auditumfang

Alle 273 vorhandenen Swift-Dateien (52.872 Zeilen einschließlich Scripts/Tests) sind mit Inhaltshash,
Imports, Typdeklarationen und Persistenz-APIs im `SWIFT_BASELINE_INVENTORY.json` erfasst.
Das ist eine vollständige strukturelle Bestandsanalyse, keine Behauptung einer manuellen Einzelabnahme aller App-Funktionen.
Inhaltlich vollständig gelesen: Snake-/Memory-Spielmodelle, Views, Renderer, Fotolader, Quellenpicker,
Bestwertspeicherung, zugehörige Tests und Root-Lifecycle; AppModel-/Target-/Settings-Anbindungen geprüft.
Der vollständige MASTERPROMPT, README, QA-Checkliste und beide Swift-Vorlagen des Kits wurden gelesen.

- Ein iOS-App-Target `PhotoMaid`, zwei Test-Targets, `PhotoMaidCore` als SwiftPM-Bibliothek.
- iOS 26+, Swift 6/strikte Concurrency, XcodeGen `project.yml`; iPhone-Hochformat bleibt erhalten.
- Kein SpriteKit/GameScene vorhanden. Snake verwendet SwiftUI/Canvas und einen Task-Taktgeber.
- Autorität: `PhotoSnakeGame`: Raster 4–24 × 4–24, zwei gepufferte Kurven, keine 180°-Wende,
  klassische Wände oder Randumlauf, legaler Eintritt in den auslaufenden Schwanz, Wachstum +1/Futter.
- Drei Tempi (0,32 / 0,22 / 0,14 s), VoiceOver-Schrittmodus, thermische Pause,
  app-eigener Spielstand bleibt beim Schließen erhalten; Fensteränderung verformt keine laufende Runde.
- Rekorde: `games.personalRecords.v1` in bestehendem Core-Data-KeyValueStore; unverändert beibehalten.
- Memory: 6/12/18 Zufallspaare, manuell 2–18 Fotos, aktive Spielzeit als Bestwert.
  Befund: scrollbares Brett schaltet automatische Fehlpaar-Aufdeckung aus, während alle geschlossenen
  Karten wegen `hasMismatch` gesperrt sind. Das erklärt ein dauerhaft blockiertes Brett im Quellcode.
- Bestehende Fotoquellen: Mediathek, Favoriten, Album/Ordner mit explizitem PhotoKit-Zugriff;
  diese Quellen bleiben erhalten. Neue manuelle Auswahl nutzt PhotosPicker ohne zusätzliche Vollzugriffsabfrage.
- Keine Änderungen an Bundle-ID, Signing, Käufen, Werbung, Feed-Entscheidungen, Analyse oder Originalfotos.

## Ist → Soll und vorab markierte Änderungsstellen

| Stelle | Ist | Soll |
|---|---|---|
| MemoryGame/Model/View | Fehlpaar kann weitere Karten dauerhaft sperren | sicheres Weiterwählen, automatische Aufdeckung unabhängig von Scroll-Höhe; VoiceOver bleibt bewusst steuerbar |
| `PhotoSnakeBoard.swift` | Kamerakopf, eckige Fotokacheln, Sprünge | bestehende View als SpriteKit-Host, Cartoon-Atlanten, runde Texturen, kontinuierlicher Körperpfad |
| `PhotoSnakeModel.swift` | bestehende Regeln, Quellen, Scores | Regeln/Scores bewahren; lokale Galerie und Darstellungszustand ergänzen |
| `PhotoSnakeView.swift` | alter Einrichtungsbildschirm/Task-Takt | Wald-Menü, PhotosPicker-Galerie, Skins, HUD/Pause/Game Over, ausschließlich Swipes |
| Core/Games | diskrete Snake-Regeln | zusätzliche reine Darstellungsmathematik, Animationstiming, lokale Galerie-Reihenfolge; keine zweite Snake-Engine |
| Resources + `project.yml` | keine Snake-Atlanten | vier Atlanten, vier Hintergründe, sechs Sounds ausdrücklich als App-Ressourcen |
| Persistence/AppModel | bestehende Bestwerte/Settings | additive Schlüssel und lokale verkleinerte Fotokopien, keine destruktive Datenmigration |
| Lokalisierung | 16 Sprachen | neue Kennungen ebenfalls vollständig in 16 Sprachen |
| Tests/Dokumentation | bestehende Suite | Regressionen für Memory, Regeln, Pfad/Rotation, Fotos/Reihenfolge/Persistenz, Animation und Resume |

## Prüfgrenze

Lokaler Swift-/Docker-Test und statische Ressourcen-/Syntaxprüfung sind möglich.
macOS/Xcode, Simulator-/Geräteläufe und gemessene 60 FPS sind ohne freigegebene native Umgebung **BLOCKED**.
Es werden keine alten Simulatorbilder als Nachweis dieses neuen Umbaus verwendet.
