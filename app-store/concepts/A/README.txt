GaleriQ – Konzept A „Space to Breathe“ – en-US – v1

Inhalt
10 verlustfreie PNGs, 1206 × 2622 Pixel, 8-Bit-RGB, kein Alpha, eingebettetes sRGB.
00-overview.jpg: alle zehn Motive in einer horizontalen Reihe.
00-search-preview.jpg: erste drei Motive in 390px Suchskalierung.

Quelle und Reproduzierbarkeit
Repo: https://github.com/mrdevn4ever-sys/photomaid
Eigener Branch: hermes/store-concept-a-en
Basisbranch: claude/galeriq-localization-1-0-1-bgpw9u
Basis-Commit: 583eb804a81401aa2010996875b35d05afc61539
Tatsächlich aufgenommener App-Commit: c6ffd6c4a6279b8fadb2395069f415e84e53370e
App: GaleriQ 1.0.1; echter iPhone-17-Pro-Simulator; App-Sprache en.
Aufnahme-Workflow-Run: 43777081132
Workflow-URL: https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/43777081132
Quellenartefakt-ID: 14186903983
Originalquellen lokal archiviert: F:\HermesOutput\GaleriQ\concept-a-en-v1\native-run-43777081132-attempt-1
Provenienzdatei SHA256: 86d228e9451dbc6f018e94c2bc9894fd6203aa7e3dd256e0c4eda4b99b4ac217
Render-Design SHA256: 71ca17cc901dd8224c9cb5fc4dff398ee83b08fcea37a854c77ffe9465e1bc2d
Renderer: scripts/store/render_concept_a.py
Renderer SHA256: d0c2f37e2b2940a861e7d949be5b7032ba3f9768fe0b0df86e6bbb1705550905
Renderumgebung: Python 3.11.15, Pillow 12.3.0.
Verworfene Aufnahme-Runs: 43770703076, 43772843048 (fehlgeschlagen; keine Finalquellen).

Änderungen gegenüber der Referenz
- Neue Reihenfolge: Swipe, Duplikate/große Dateien, Löschsicherheit, Tresor,
  Später, Monate, Serienvergleich, Collage, Editor, Spiele.
- Frische echte App-Aufnahmen, reale Duplikate und gemessene große Videodateien.
- Einheitliches vollständiges iPhone, gleiche Größe und Position, weicher Eisblau-Verlauf.
- Keine Seitennummern und kein wiederholter „SPACE TO BREATHE“-Slogan.
- Originale native GaleriQ-Wordmark mit echtem Tresor-Q, nicht nachgezeichnet.
- Fokusdetails aus echten Originalaufnahmen, keine nachgebaute oder retuschierte UI.
- Sämtliche Fokusdetails samt Schatten innerhalb des Displays; alle Rahmenabschnitte frei.
- Bild03 zeigt die ganze echte Systembestätigung in der unveränderten nativen Ansicht.
- Exakte englische Headlines und geforderte Tresor-/Geschäftsmodell-Untertexte.
- Neutrale, lizenzierte CC0-Fotofixtures; erklärte Fotoderivate wurden vor dem Import
  erstellt, niemals als Retusche der App-Oberfläche oder als Scan-Ergebnis-Injektion.

Schriftregel für spätere freigegebene Sprachen
Höchstens zwei Zeilen pro Headline/Untertitel. Umbruch an Wortgrenzen, anschließend
schrittweise um 1px verkleinern. Mindestgrößen: Headline 84px; Untertitel 46px.
Wenn es dann nicht passt: harter Abbruch statt Abschneiden, Stauchen oder Umschreiben.
RTL benötigt eine gesonderte Shaping-/Spiegelungs-/Quellenprüfung und ist nicht abgenommen.

Prüfstatus
PASS: nativer Build und genau ein bestandener Aufnahme-XCTest ohne Skips.
PASS: zehn PNGs, Maße/RGB/kein Alpha/sRGB, Originalquellen- und Ausgabedatei-Hashes.
PASS: unabhängiger Pixelvergleich gegen echte farbverwaltete Original-Captures;
      dokumentierte proportionale Verkleinerung, kein Upscaling der nativen UI.
PASS: echte Rahmenpixel aller zehn Bilder unverdeckt und identisch geprüft.
PASS_WITH_OBSERVATIONS: jedes Finalbild einzeln sowie Übersicht und erste-drei-Suchansicht.
BLOCKED: exakter nativer Wortlaut „Remove 2 photos“; tatsächlich „Remove 2 photos and videos“.
NOT RUN: zusätzliche reale Geräte-/Sicherheits-/Conversion-Abnahme.
Nicht ausgeführt: App Store Connect, Einreichung, Release, PR oder Merge.
Bestehende Store-Medien und andere Branches wurden nicht ersetzt.

Beobachtungen / unveränderte Original-UI
- Bild03: Native CTA unverändert „Remove 2 photos and videos“ statt „Remove 2 photos“. Exakter Brief-Wortlaut: BLOCKED durch unveränderte Produktionscopy; keine UI-Retusche oder Katalogänderung. Die echte Systemfrage nennt ausdrücklich „2 photos“.
- Die Later-Pille besteht nativ aus „Again in 2 days“ und einem separaten „Change“-Button; ein künstlicher Mittelpunkt oder kombinierter Text wurde nicht erzeugt.
- Monate: sechs vollständige Zeilen; die nächste Mai-Zeile beginnt nativ angeschnitten. Editor-Filter und Serienreihe bleiben echte horizontale Scrollbereiche; im Analyse-Fokus werden drei echte Thumbnails vergrößert, nicht alle sechs als sichtbar ausgegeben.
- Der native Duplikatheader „2.3 MB total“ bezeichnet extra-copy bytes, nicht die Summe beider Dateien und keine garantierte Speicherfreigabe. Die echten Größen-/Speicherplatzvorbehalte bleiben sichtbar.
- Spielebild zeigt die drei echten nativen Spielkarten/Standbild-Vorschauen, keine Abnahme laufenden Gameplays.
- 112px-Suchskalierung: Headlines und Feature-Reihenfolge lesbar. Feine MB-Zahlen, OS-Dialogtexte und Zusatzzeilen sind dort nicht zuverlässig lesbar; die vollständigen Inhalte wurden separat in den großen Bildern geprüft.
- Bildmotive stammen ausschließlich aus der hashgebundenen Auswahl von16 einzeln geprüften CC0-Originalen; keine pauschale Freigabe aller55 Originalfotos.
- Face ID und eigener Tresor-Code sind durch den gepinnten App-Quellstand belegt; diese Bildproduktion ist keine zusätzliche Face-ID-, Kryptografie-, reale-Geräte- oder Conversion-Abnahme.

Nur en-US. Andere Sprachen erst nach ausdrücklicher Nutzerfreigabe „perfekt“.
