# GaleriQ – App-Store-Einträge (Englisch)

Stand **31.10.2026**, Experiment-Design (`claude/experiment-artifact-design`, Commit `8a41b29`), Name **GaleriQ**
(Schriftzug mit Tresor-Rad als „Q“), aufgenommen mit dem Workflow `app-store-refresh.yml` (CI-Lauf 41149551351,
`store_locales=en`, `store_devices=iphone-large`, 5/5 Aufnahmetests PASS). Ältere Aufnahmen bleiben in der Git-Historie.

## Inhalt

- [`en/screenshots/`](en/screenshots): zehn Screenshots in Präsentationsreihenfolge – Start, **Behalten** (Wisch
  nach oben, Pille „Keep“), **Papierkorb** (Wisch nach links, Pille „Trash“), Fotos, Aufräumen, Foto-Snake, Paare,
  Collage, Editor (Filter), Tresor. Behalten/Papierkorb sind echte Simulator-Screenshots mitten in der gehaltenen Geste.
  Native PNGs des iPhone 17 Pro Max (6,9″, **1320 × 2868**), Dark Mode, ohne Beschnitt, Verzerrung oder Hochskalierung.
- [`en/previews/`](en/previews): zwei App-Vorschauen mit Poster
  - `01-review.mp4` – Aufräumen per Wischen: langsam gezogen und kurz gehalten, Behalten, Papierkorb und Später je
    einmal klar sichtbar, dann Zurück
  - `02-photo-games.mp4` – Paare und Foto-Snake
  Je 27 s, **886 × 1920**, 30 fps, H.264, AAC-Stereo (Stille) – innerhalb von Apples Vorgabe 15–30 s.
- [`en/provenance.json`](en/provenance.json): Commit, Lauf, Gerät, Testergebnis (5/5 Aufnahmetests PASS) und
  SHA-256 jeder Datei. [`en/previews/manifest.json`](en/previews/manifest.json): Schnittangaben der Clips.

App Store Connect: Produktseite **en-US**, iPhone 6,9″-Bildschirm (kleinere iPhones skaliert Apple daraus).
Die Bilder und Clips lädt der Inhaber bzw. sein Agent hoch (`docs/RELEASE_CHECKLIST.md`, Prompt C); die Store-Texte
kommen aus `metadata/` über den TestFlight-Workflow (`task: store-texts`).

## Quellen

Echte Simulator-Aufnahmen mit PhotoKit/Core Data und den 55 Fotos unter [`media/`](media) (einzeln belegte
CC0-Lizenzen, [Quellen](media/SOURCES.md)). Keine synthetischen QA-Daten, keine erfundenen Zahlen. Der
Aufnahmeaufbau ist nur im Debug-Simulator verfügbar und fehlt im TestFlight-/Release-Code.

## Wiederholen

`ci.yml` mit `store_locales=en`, `ui_phase=store-refresh`, `store_devices=iphone-large`; das Artefakt
`store-current-en-iphone-large-assets` enthält `app-store-selection/` (Screenshots) und `previews/`
(drei Clips: Aufräumen, Fotospiele, Studio – abgelegt sind die ersten beiden). Weitere Sprachen über
`store_locales=<Codes>`; `localizations.json` ordnet die App-Sprachen den App-Store-Lokalisierungen zu.
