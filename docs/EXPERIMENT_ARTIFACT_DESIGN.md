# Experiment-Design „Artefakt“ (Branch `claude/experiment-artifact-design`)

Nutzerauftrag 21.10.2026: das Design-Artefakt (https://claude.ai/artifact/E3HYQMG4knubEuJ2NpBfDT) 1:1 als
experimentelles Design der ganzen App in einem eigenen Branch umsetzen – inklusive wackelnder Foto-Kacheln,
Schrift und Größen. Nicht für `main` bestimmt, solange der Nutzer es nicht ausdrücklich übernimmt.

## Was umgesetzt ist

- **Schriften** (OFL, `PhotoMaid/Resources/Fonts`): Bricolage Grotesque (Titel, Zahlen; 600/700/800, XL-Schnitt für den
  großen Zähler) und Figtree (Text; 400–700) als statische Instanzen. Größen in pt = Artefakt-px bei Standard-Textgröße,
  Dynamic Type skaliert über `relativeTo`.
- **Farben** (`DesignSystem/Tokens.swift`): Grund `#0F0E0D`, Flächen `#1B1917`, Bernstein `#F2B24C`, Behalten `#7CC8FF`,
  Papierkorb `#FF7A50`, Später `#C4B5FD`, Pause-Violett, Erfolg `#8FD9A8`. Nur dunkel (siehe Abweichungen).
- **Symbole** (`PMIcon`): die Linien-Symbole des Artefakts als SVG-Pfade (`SVGPathParser`), nicht SF Symbols.
- **Tableiste** (`PMTabBar`): schwebende Kapsel, Einträge „PhotoMaid“, Fotos, Studio, Verlauf und der runde
  Bernstein-Knopf „Aufräumen“ in der Mitte. Wie im Artefakt nur auf den fünf Startseiten; Unterseiten ohne Tableiste.
- **Startseite**: Begrüßung nach Tageszeit, darunter „PhotoMaid“ (Tresor-Rad im „o“) und Zahnrad; Hero
  „Noch durchzusehen“ mit großer Zahl und drei echten Fotos aus den noch nicht entschiedenen Medien, die leicht wackeln (Swipe-Andeutung, `keyframeAnimator`, aus bei
  „Bewegung reduzieren“). Papierkorb/Später-Kacheln, Pause-Karte, Schnellzugriffe, Pro.
- **Aufräumen, Studio, Verlauf, Fotos, Feed, Papierkorb, Später, Spiele, Einstellungen, Tresor** (Code-Eingabe mit rundem
  Ziffernfeld, Übersicht, Tresor-Papierkorb mit „Alles endgültig löschen“) im Artefakt-Layout.
- Neue Texte: 16 Kennungen `art_*` in allen 16 Sprachen (`scripts/i18n/ios_strings_part18_artifact_design.py`).

## Abweichungen vom Artefakt (bewusst)

- **Begrüßung** nach Tageszeit über „PhotoMaid“ bleibt drin (Nutzer, 21.10.2026): Guten Morgen (5–11 Uhr), Guten Mittag
  (12–13), Guten Nachmittag (14–17), Guten Abend (18–4); kein „Hallo“ mehr.
- **Erscheinungsbild** fehlt in den Einstellungen: das Artefakt-Design gibt es nur dunkel; ein Umschalter ohne Wirkung
  wäre ein toter Knopf.
- **Texte aus echten Kennungen**, wo es sie schon gab (z. B. Mitteilungs-Erklärung in „Später“, Tresor-Hinweis in den
  Einstellungen) – teils länger als die Kurzfassung im Artefakt.
- **Funktionen bleiben erreichbar**, die das Artefakt nicht zeigt: „Code vergessen?“, Sortieren/Auswählen im Tresor,
  Zurückstellung entfernen (Kontextmenü in „Später“), Sprache, Werbe-Einwilligung.
- Formulare tieferer Unterseiten (z. B. Tresor-Einstellungen, Hilfe) übernehmen Schrift und Farben über
  `ArtifactAppearance`, behalten aber ihr Systemlayout.

## Regeln unverändert

Gesten, Entscheidungen, Löschwege, Werbung/Einwilligung, Tageslimit und Tresor-Logik sind nicht angefasst; nur Ansicht.
UI-Tests nutzen die Kennungen `tab.today|library|cleanup|studio|history` und `vault.key.0–9` (Ziffernfeld).

## Prüfstatus

- `swift test` (PhotoMaidCore, Linux): PASS
- `android_strings_to_xcstrings.py --check`: PASS
- Xcode-Build und Unit-Tests: PASS (CI-Läufe 39584295498, 39597390682; TestFlight-Läufe 39586915037, 39591723238, 39598302667)
- UI-Tests (QA-Daten): Lauf 39584295498 FAIL (2 Testhelfer-Probleme, korrigiert); Wiederholung läuft
- TestFlight: interne Builds 1.0 (21), (22) und (23) hochgeladen und von Apple verarbeitet (21.10.2026, nur interne
  Tester); 22 mit Begrüßung nach Tageszeit, festem Kopf, Tableisten-Korrektur und Verlauf (10 neueste, Rest aufklappbar);
  23 mit tieferer Tableiste, plastischem Mittelknopf, kompakten Papierkorb/Später-Kacheln, Rückgängig am richtigen Eintrag
- Geräteabnahme: NOT RUN
