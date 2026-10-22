# PhotoMaid – App-Store-Einträge (Englisch)

Stand **22.10.2026**, Experiment-Design (`claude/experiment-artifact-design`, Commit `64f1715`),
aufgenommen mit dem Workflow `app-store-refresh.yml` (CI-Lauf 39797435049, `store_locales=en`,
`store_devices=iphone-large`). Alle älteren Aufnahmen (16 Sprachen, `locales/` vom 15.10. und `current/` vom
18.10.2026) wurden auf Wunsch entfernt; sie bleiben in der Git-Historie.

## Inhalt

- [`en/screenshots/`](en/screenshots): zehn Screenshots in Präsentationsreihenfolge – Start, Feed, Fotos,
  Aufräumen, Foto-Snake, Paare, Collage, Editor (Filter), Film, Tresor.
  Native PNGs des iPhone 17 Pro Max (6,9″, **1320 × 2868**), Dark Mode, ohne Beschnitt, Verzerrung oder Hochskalierung.
- [`en/previews/`](en/previews): zwei App-Vorschauen mit Poster
  - `01-review.mp4` – Aufräumen per Wischen (Behalten, Papierkorb, Später, Zurück)
  - `02-photo-games.mp4` – Paare und Foto-Snake
  Je 27 s, **886 × 1920**, 30 fps, H.264, AAC-Stereo (Stille) – innerhalb von Apples Vorgabe 15–30 s.
- [`en/provenance.json`](en/provenance.json): Commit, Lauf, Gerät, Testergebnis (5/5 Aufnahmetests PASS) und
  SHA-256 jeder Datei. [`en/previews/manifest.json`](en/previews/manifest.json): Schnittangaben der Clips.

App Store Connect: Produktseite **en-US**, iPhone 6,9″-Bildschirm (kleinere iPhones skaliert Apple daraus).
Nichts davon wurde zu App Store Connect hochgeladen.

## Quellen

Echte Simulator-Aufnahmen mit PhotoKit/Core Data und den 55 Fotos unter [`media/`](media) (einzeln belegte
CC0-Lizenzen, [Quellen](media/SOURCES.md)). Keine synthetischen QA-Daten, keine erfundenen Zahlen. Der
Aufnahmeaufbau ist nur im Debug-Simulator verfügbar und fehlt im TestFlight-/Release-Code.

## Wiederholen

`ci.yml` mit `store_locales=en`, `ui_phase=store-refresh`, `store_devices=iphone-large`; das Artefakt
`store-current-en-iphone-large-assets` enthält `app-store-selection/` (Screenshots) und `previews/`
(drei Clips: Aufräumen, Fotospiele, Studio – abgelegt sind die ersten beiden). Weitere Sprachen über
`store_locales=<Codes>`; `localizations.json` ordnet die App-Sprachen den App-Store-Lokalisierungen zu.
