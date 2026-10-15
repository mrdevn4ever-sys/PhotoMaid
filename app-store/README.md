# PhotoMaid – App-Store-Aufnahmen

Dark Mode, ausschließlich Hochkant, alle 16 App-Sprachen. Die Originale sind echte Simulator-Aufnahmen
mit PhotoKit/Core Data und dem Bildsatz unter `media/`; keine synthetischen QA-Fixtures oder erfundenen
Analyseergebnisse. Der Aufnahmeaufbau ist nur im Debug-Simulator verfügbar und fehlt im TestFlight-/Release-Code.
Die 55 Fotos werden nicht in die ausgelieferte App eingebaut und verändern keine persönliche Mediathek.

## Ablage

- `media/`: 45 Präsentationsfotos + 10 schwierigere Motive, einzeln belegte CC0-Lizenz; [Quellen](media/SOURCES.md).
- `locales/<Sprache>/all-pages/`: unveränderte Original-Screenshots aller aufgenommenen Seiten.
- `locales/<Sprache>/app-store-selection/`: zehn vorgeschlagene Screenshots in Präsentationsreihenfolge.
- `locales/<Sprache>/previews/`: drei Vorschauvideos zur Auswahl, einschließlich Poster bei Sekunde 5 und Schnittmanifest.
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
künstlich erzeugte App-Oberflächen. Schnitte entfernen Wartezeiten; das Schnittmanifest nennt die Originalzeiten.

Maßgebliche Apple-Vorgaben, am 15.10.2026 abgerufen:
[Screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/),
[Vorschau-Spezifikation](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/),
[App Previews](https://developer.apple.com/app-store/app-previews/). Vorschauen dauern 15–30 Sekunden;
Apple erlaubt bis zu drei pro Sprache. Diese Assets werden zunächst nur auf dem Arbeitsbranch in Git abgelegt.

## Wiederholen

Der manuelle Workflow `.github/workflows/app-store-assets.yml` nimmt `locales` (`all` oder Kommaliste) und
`capture` (`all`, `screenshots`, `previews`) entgegen. Auf einem frischen Simulator enthält auch `previews`
den Seitenlauf, damit der echte PIN-Tresor mit echten Importen vorbereitet ist. Die Jobs erzeugen getrennte
Asset- und Quellenartefakte. Es gibt weder einen TestFlight-Upload noch einen App-Store-Upload.

Kamera, echtes Face ID, iCloud-Originale und Ansichten, die ein nicht im gewählten Bildsatz enthaltenes Medium
voraussetzen, werden nicht mit Ersatzdaten dargestellt. Der Abschlussbericht benennt solche Lücken ausdrücklich.
