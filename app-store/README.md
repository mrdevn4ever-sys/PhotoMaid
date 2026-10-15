# PhotoMaid – App-Store-Aufnahmen

Dark Mode, ausschließlich Hochkant, alle 16 App-Sprachen. Die Originale sind echte Simulator-Aufnahmen
mit PhotoKit/Core Data und dem Bildsatz unter `media/`; keine synthetischen QA-Fixtures oder erfundenen
Analyseergebnisse. Der Aufnahmeaufbau ist nur im Debug-Simulator verfügbar und fehlt im TestFlight-/Release-Code.
Die 55 Fotos werden nicht in die ausgelieferte App eingebaut und verändern keine persönliche Mediathek.

**Abgeschlossen:** 1.969 native Seitenaufnahmen und 160 Store-Vorschläge in allen 16 Sprachen,
48 Vorschauvideos mit Postern. [Sprachindex](INDEX.md) · [Abschlussbericht, Grenzen und Commits](DELIVERY.md).

## Ablage

- `media/`: 45 Präsentationsfotos + 10 schwierigere Motive, einzeln belegte CC0-Lizenz; [Quellen](media/SOURCES.md).
- `locales/<Sprache>/all-pages/`: unveränderte Original-Screenshots aller aufgenommenen Seiten.
- `locales/<Sprache>/app-store-selection/`: zehn vorgeschlagene Screenshots in Präsentationsreihenfolge.
- `locales/<Sprache>/previews/`: drei Vorschauvideos zur Auswahl mit Postern und Schnittmanifest (Posterzeit im Manifest).
- `locales/<Sprache>/provenance.json`: Commit, Workflow, Gerät, tatsächliche Testergebnisse.

Die Sprachordner verwenden die App-Kennungen `ar`, `de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `nl`, `pl`,
`pt-PT`, `ro`, `ru`, `tr`, `uk`, `zh-Hans`. App Store Connect ordnet diese der jeweils passenden
Produktseiten-Lokalisierung zu (z. B. `en-US`, `zh-Hans`). Arabisch bleibt RTL; physische Wischrichtungen
werden nicht gespiegelt. Nicht jede Support-/Leer-/Einrichtungsseite eignet sich für die Store-Auswahl;
das vollständige Seitenarchiv bleibt daneben erhalten.

## Formate und Quellen

Screenshots: native PNGs des iPhone 17 Pro Max (1320 × 2868), ohne Beschnitt, Verzerrung oder Hochskalierung.
Videos: drei unterschiedliche echte Bildschirmaufnahmen je Sprache (Aufräumen, Studio, Tresor), auf 886 × 1920
verkleinert, 30 fps, H.264, Zielrate 10 Mbit/s, AAC-Stereo mit Stille. Keine Musik, externen Filmszenen oder
künstlich erzeugte App-Oberflächen. Die vollständigen Aufnahmen bleiben erhalten; längere Demonstrationen
werden auf 24 Sekunden beschleunigt, danach steht das echte Schlussbild drei Sekunden. Das Manifest nennt
Originaldauer, Tempo, Original-SHA-256 und native Schrittmarken. Variable Simulator-Bildraten werden vor dem
Export normalisiert; Wandzeitmarken dienen nicht als ungenaue Schnittpunkte.

Maßgebliche Apple-Vorgaben, am 15.10.2026 abgerufen:
[Screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/),
[Vorschau-Spezifikation](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/),
[App Previews](https://developer.apple.com/app-store/app-previews/). Vorschauen dauern 15–30 Sekunden;
Apple erlaubt bis zu drei pro Sprache. Diese Assets werden zunächst nur auf dem Arbeitsbranch in Git abgelegt.

## Wiederholen

Der manuelle Workflow `.github/workflows/app-store-assets.yml` nimmt `locales` (`all` oder Kommaliste) und
`capture` (`all`, `screenshots`, `previews`) entgegen. Auf dem Arbeitsbranch wird er über `ci.yml` aufgerufen:
`store_locales=all` und `ui_phase=store-screenshots` bzw. `store-previews`.
Auf einem frischen Simulator enthält `previews` einen eigenen Einrichtungslauf für Fotozugriff und
den echten PIN-Tresor mit echten Importen. Die Jobs erzeugen getrennte
Asset- und Quellenartefakte. Es gibt weder einen TestFlight-Upload noch einen App-Store-Upload.

Ein Exportfehler erfordert keine Wiederholung bestandener Simulator-Tests:
`.github/workflows/app-store-export.yml` lädt mit `source_run` und `locales` vorhandene Quellen,
prüft erneut exakt 55 Quelldateien und 4/4 native Tests und exportiert auf Linux.
`preview-provenance.json` unterscheidet ursprünglichen Aufnahmecommit/-lauf und Exportcommit/-lauf.
Auf diesem Branch über `ci.yml`: `ui_phase=store-export`, `baseline_run=<Aufnahmelauf-ID>` und
`store_locales=<Sprachliste>`; der zusätzliche Workflow ist vor dem Merge nicht direkt dispatchbar.

Nach der Ablage erzeugt `python3 scripts/store/make_review.py app-store/locales/<Sprache>`
Prüfbögen mit zunächst `PENDING`. Erst nach tatsächlicher Sichtprüfung wird ihr Status auf `PASS`
gesetzt. Nach Hinzufügen der Vorschauen behält `--previews-only` bereits geprüfte Screenshot-Einträge
bei und kontrolliert ihre Prüfsummen erneut. `scripts/store/audit_assets.py --screenshots-only`
prüft die erste Phase; ohne diesen Schalter verlangt die Prüfung auch alle Videos und Poster.

Kamera, echtes Face ID, iCloud-Originale und Ansichten, die ein nicht im gewählten Bildsatz enthaltenes Medium
voraussetzen, werden nicht mit Ersatzdaten dargestellt. Der Abschlussbericht benennt solche Lücken ausdrücklich.
