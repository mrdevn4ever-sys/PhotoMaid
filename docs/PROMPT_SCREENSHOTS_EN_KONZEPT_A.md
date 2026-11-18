# Prompt: Konzept A – neue englische Screenshots, verbessern bis perfekt

Alles unterhalb der Linie in Hermes einfügen und das ZIP „GaleriQ-Konzept-A-neue-Reihenfolge-en-US.zip“ als Referenz mitgeben.

---

Auftrag: Erzeuge das **englische App-Store-Screenshot-Set von GaleriQ nach Konzept A („Space to Breathe“) neu** – mit **frisch aufgenommenen echten App-Screens** über GitHub Actions – arbeite alle Verbesserungen unten ein und schick mir am Ende ein **ZIP**. **Nur Englisch (en-US).** Danach warte auf mein Feedback; wir wiederholen das, bis ich „perfekt“ sage. Erst dann geht es an andere Sprachen – nicht vorher. Antworte auf Deutsch.

## Freigaben und Grenzen
- **GitHub-Actions-Minuten sind ausdrücklich freigegeben** (macOS-Runner für Simulator-Aufnahmen), so oft wie nötig.
- Repo `mrdevn4ever-sys/photomaid`, Basis: Branch `claude/galeriq-localization-1-0-1-bgpw9u` (aktueller App-Stand 1.0.1). Arbeite auf einem **eigenen neuen Branch**, z. B. `hermes/store-concept-a-en`. Kein Merge, kein PR, keine Änderungen an anderen Branches.
- Vorhandene Werkzeuge nutzen: `.github/workflows/app-store-assets.yml`, `simulator-screenshot.yml`, `app-store-refresh.yml`, Skripte in `scripts/store/` (u. a. `capture.sh`, `create_capture_simulator.py`, `assemble_assets.py`, `audit_assets.py`). Bei Bedarf anpassen oder einen eigenen `workflow_dispatch`-Workflow ergänzen (nur manuell auslösbar).
- **Nichts nach App Store Connect hochladen, nichts einreichen**, bestehende Store-Screenshots in `app-store/` nicht ersetzen. Neue Dateien z. B. unter `app-store/concepts/A/en-US/`.
- Keine Secrets/Keys in Repo oder Chat. Interne Namen („PhotoMaid“) nie sichtbar; sichtbarer Name nur „GaleriQ“. Projektregeln in `CLAUDE.md` beachten.
- Keine erfundenen Zahlen oder Auszeichnungen („Nr. 1“, „X GB frei“, Sterne). Keine Funktionen versprechen, die es nicht gibt; die App löscht nie selbst. Keine fremden Marken/Logos, keine echten Personenfotos.

## Technische Anforderungen
- 10 PNGs, **1206 × 2622 px**, RGB, **ohne Alpha**, sRGB.
- App-Screens **echt** aus dem iOS-Simulator (iPhone mit Dynamic Island, englische App-Sprache, Statusleiste 9:41, voller Akku), keine nachgebaute UI.
- Testbibliothek im Simulator mit **neutralen, lizenzfreien Beispielmotiven**, die nach Aufräumen aussehen: doppelte Fotos, Serien fast gleicher Aufnahmen, verwackelte/unscharfe Bilder, Bildschirmfotos (ohne private Daten), große Videos – plus einige schöne Motive für Collage/Editor/Tresor. Keine Personen.

## Reihenfolge und Inhalte (neu)
1. **Swipe** – „Swipe the clutter. Keep the memories.“ Karte **mitten im Wischen** (schräg), drei große Pfeile in den echten Aktionsfarben: ↑ Keep, ← Trash, → Later. Motiv: typisches Durcheinander (z. B. Bildschirmfoto oder verwackeltes Bild), nicht nur Landschaft.
2. **Duplikate & große Dateien** – „Find duplicates. Spot large files.“ Echtes Ergebnis zeigen: zwei identische Fotos nebeneinander mit gemessener Größe bzw. Liste großer Dateien – keine Kachel nur mit Symbolen.
3. **Sicherheit** – „Nothing deletes without you.“ Echten **Papierkorb** zeigen („Remove 2 photos“) und groß den **iOS-Bestätigungsdialog** – nicht die Bibliotheksliste.
4. **Tresor** – „Private photos. Locked away.“ Untertitel: „Encrypted vault, protected by your own code and Face ID.“ (nicht „passcode“). Tresor-UI mit Fotos, gerne Sperrbildschirm mit Zahlenrad.
5. **Später** – „Unsure? Choose later.“ mit der Pille „Again in 2 days · Change“.
6. **Monate** – „One month. A fresh start.“ Ausschnitt so wählen, dass keine große leere Fläche bleibt.
7. **Analyse** – „Blurry or similar? Take a closer look.“ Echte Ergebnisse: Serie im Vergleich oder Raster unscharfer Bilder. Keine verwaiste Zeile („Find. Review. Decide.“ weg oder in den Untertitel).
8. **Collage** – „Make a collage. Keep the moment.“
9. **Editor** – „A new look. Your own photo.“
10. **Spiele** – „A small break. Your photos play.“ Darunter gut lesbar (nicht winzig): „Free with ads. GaleriQ Pro: one purchase, no subscription.“

## Gestaltung (Konzept A beibehalten, aber verbessert)
- Heller Hintergrund wie Konzept A, aber **ohne harten Übergang Hellblau/Weiß** mitten durchs Gerät: eine durchgehende Fläche oder weicher Verlauf.
- **Entfernen:** Seitennummern „01 / 10“ und den wiederholten Slogan „SPACE TO BREATHE“.
- Oben das **echte GaleriQ-Logo** (Schriftzug, das „Q“ als Tresor-Zahlenrad – aus den App-Assets, nicht als Lupe nachgebaut).
- **Einheitlich:** auf jedem Bild das ganze iPhone (gleicher Rahmen, gleiche Größe, gleiche Position); die entscheidende Stelle zusätzlich als vergrößerten Ausschnitt mit Schatten über das Gerät legen, wenn sie sonst zu klein ist.
- Überschrift max. 2 Zeilen, Untertitel max. 2 Zeilen; Schrift so wählen, dass das Layout später auch für lange Sprachen und RTL funktioniert (automatisches Verkleinern als Regel festhalten).
- Ränder/Abstände auf allen 10 Bildern identisch; Text nie näher als ~70 px an den Rand.

## Prüfung vor dem Versand
- Automatische Prüfung: Format, Alpha, Größe, Farbraum (`scripts/store/audit_assets.py` o. ä.).
- Sichtprüfung jedes Bildes in voller Größe **und** verkleinert wie im Suchergebnis (die ersten 3 Bilder nebeneinander): ist die Aussage ohne Zoomen klar?
- Keine abgeschnittenen Texte, keine Platzhalter, keine internen Namen, keine Debug-Elemente.

## Lieferung
- ZIP `GaleriQ-Konzept-A-en-US-v<N>.zip` mit: `en-US/01-…png` bis `10-…png`, `00-overview.jpg` (alle 10 nebeneinander), `00-search-preview.jpg` (erste 3 wie im Suchergebnis), `README.txt` (was geändert wurde, Branch, Workflow-Run-IDs).
- Kurze Nachricht an mich: was umgesetzt wurde, was offen ist, Prüfstatus PASS / FAIL / NOT RUN / BLOCKED.
- Dann **warten auf mein Feedback** und die nächste Version (v2, v3 …) liefern, bis ich „perfekt“ sage.
