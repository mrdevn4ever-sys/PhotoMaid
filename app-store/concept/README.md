# Store-Bilder 1.1 – Concept A („Space to Breathe“)

Zehn Bilder je Sprache und Gerät, gesetzt aus echten nativen Simulator-Aufnahmen von GaleriQ 1.1
(`scripts/store/compose_concept.py`, Überschriften in `headlines.json`). Die App-Aufnahme wird nur verkleinert,
nie vergrößert, verzerrt oder retuschiert; der Schriftzug stammt aus derselben Aufnahme.

- Geräte: iPhone 6,9″ (1320 × 2868), iPhone 6,3″ (1206 × 2622), iPad 13″ (2064 × 2752), PNG ohne Transparenz.
- 45 App-Sprachen decken alle 50 Store-Locales ab (en → en-US/GB/AU/CA, es → es-ES/MX, fr → fr-FR/CA).
- Im Repo: `screenshots/en-US` und `screenshots/de-DE` komplett. Alle 1.350 Bilder mit Prüfsumme, Lauf und Artefakt:
  `screenshots/manifest.json` (die übrigen ~1,5 GB liegen als Actions-Artefakte, nicht im Git).
- Neu setzen ohne Aufnahme: CI `ui_phase=store-recompose` (liest `recompose.tsv`).
- Ersetzt für 1.1 die älteren dunklen Bilder unter `app-store/<sprache>/screenshots*`. Kein Upload zu App Store Connect.
