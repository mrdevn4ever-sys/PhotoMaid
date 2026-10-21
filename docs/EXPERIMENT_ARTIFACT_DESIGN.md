# Experiment-Design „Artefakt“ (Branch `claude/experiment-artifact-design`)

Nutzerauftrag 21.10.2026: das Design-Artefakt (https://claude.ai/artifact/E3HYQMG4knubEuJ2NpBfDT) 1:1 als
experimentelles Design der ganzen App in einem eigenen Branch umsetzen – inklusive wackelnder Foto-Kacheln,
Schrift und Größen. Nicht für `main` bestimmt, solange der Nutzer es nicht ausdrücklich übernimmt.

## Was umgesetzt ist

- **Schriften** (OFL, `PhotoMaid/Resources/Fonts`): Bricolage Grotesque (Titel, Zahlen; 600/700/800, XL-Schnitt für den
  großen Zähler) und Figtree (Text; 400–700) als statische Instanzen. Größen in pt = Artefakt-px bei Standard-Textgröße,
  Dynamic Type skaliert über `relativeTo`.
- **Farben** (`DesignSystem/Tokens.swift`): Grund `#0F0E0D`, Flächen `#1B1917`, Bernstein `#F2B24C`, Behalten `#7CC8FF`,
  Papierkorb `#FF7A50`, Später `#C4B5FD`, Pause-Violett, Erfolg `#8FD9A8`; heller Modus siehe Abweichungen.
- **Symbole** (`PMIcon`): die Linien-Symbole des Artefakts als SVG-Pfade (`SVGPathParser`), nicht SF Symbols.
- **Tableiste** (`PMTabBar`): schwebende Kapsel, Einträge „PhotoMaid“, Fotos, Studio, Verlauf und der runde
  Bernstein-Knopf „Aufräumen“ in der Mitte. Wie im Artefakt nur auf den fünf Startseiten; Unterseiten ohne Tableiste.
- **Startseite**: Begrüßung nach Tageszeit, darunter „PhotoMaid“ (Tresor-Rad im „o“) und Zahnrad; Hero
  „Noch durchzusehen“ mit großer Zahl und drei echten Fotos aus den noch nicht entschiedenen Medien, die leicht wackeln (Swipe-Andeutung, `keyframeAnimator`, aus bei
  „Bewegung reduzieren“). Papierkorb/Später-Kacheln, Pause-Karte, Schnellzugriffe, Pro.
- **Zahlenschloss-Rad** (Nutzerwunsch 21.10.2026, `DesignSystem/CombinationDial.swift`): das „o“ in „PhotoMaid“ ist ein
  Tresor-Zahlenrad (Chromrand, schwarze Skala mit Teilstrichen, Chromknopf, Bernstein-Marke). Beim 2-Sekunden-Halten
  dreht es links über eine volle Umdrehung, rechts, links und klickt (Haptik); groß mit Zahlen 0–90 statt der
  Schloss-Kachel auf dem Tresor-Sperrbildschirm, dort je eingegebenem Zeichen abwechselnd links/rechts um feste Winkel
  (nie zur getippten Ziffer, damit niemand die PIN am Rad ablesen kann). „Bewegung reduzieren“: keine Drehung.
- **Aufräumen, Studio, Verlauf, Fotos, Feed, Papierkorb, Später, Spiele, Einstellungen, Tresor** (Code-Eingabe mit rundem
  Ziffernfeld, Übersicht, Tresor-Papierkorb mit „Alles endgültig löschen“) im Artefakt-Layout.
- Neue Texte: 16 Kennungen `art_*` in allen 16 Sprachen (`scripts/i18n/ios_strings_part18_artifact_design.py`).

## Abweichungen vom Artefakt (bewusst)

- **Begrüßung** nach Tageszeit über „PhotoMaid“ bleibt drin (Nutzer, 21.10.2026): Guten Morgen (5–11 Uhr), Guten Mittag
  (12–13), Guten Nachmittag (14–17), Guten Abend (18–4); kein „Hallo“ mehr.
- **Erscheinungsbild** (Nutzer, 21.10.2026): Einstellungen › Erscheinungsbild „Wie auf dem Gerät · Hell · Dunkel“,
  Standard dunkel (eigene Einstellung `designAppearance`). Der helle Modus ist eine eigene warme Ableitung der
  Artefakt-Farben (`AppColors.dyn(dunkel, hell)`), das Artefakt selbst zeigt nur dunkel. Editor und Medienbühnen bleiben
  dunkel.
- **Texte aus echten Kennungen**, wo es sie schon gab (z. B. Mitteilungs-Erklärung in „Später“, Tresor-Hinweis in den
  Einstellungen) – teils länger als die Kurzfassung im Artefakt.
- **Funktionen bleiben erreichbar**, die das Artefakt nicht zeigt: „Code vergessen?“, Sortieren/Auswählen im Tresor,
  Zurückstellung entfernen (Kontextmenü in „Später“), Sprache, Werbe-Einwilligung.
- Formulare tieferer Unterseiten (z. B. Tresor-Einstellungen, Hilfe) übernehmen Schrift und Farben über
  `ArtifactAppearance`, behalten aber ihr Systemlayout.

## Gamification (Nutzerentscheidung 21.10.2026)

Plan: https://claude.ai/artifact/QEkF2h19hvzCfdDr6gWLaQ. Entscheidungen: Bestwerte mit **einem Rekord je Spiel außer
Paare** (Paare je Kategorie), keine Feldgrößen bei Snake und Blocks; **Tagesziel an** (Standard 50); **ein Pausentag je
Woche**; alles andere aus dem Plan umsetzen.

- **Kern** (`Sources/PhotoMaidCore/Progress/`): `ReviewProgress` zählt je lokalem Tag verschiedene durchgesehene Medien
  (Behalten, Papierkorb, Später gleich; Rückgängig am selben Tag wird abgezogen), Serie mit einem verziehenen Tag je
  ISO-Woche, längste Serie, Meilenstein-Zeitpunkte. `ReviewLevel` (feste Schwellen 50 … 100 000), `Achievements` (24
  Abzeichen, nur aus echten Daten, keines für gelöschte Mengen oder Speicher), `GameMedal` (nur eigene Werte).
- **App**: Fortschritt im Lesemodell (`LedgerReadModel.progress`), `AchievementCenter` speichert erreichte Abzeichen und
  Bestwert-Zeitpunkte lokal (`progress.achievements.v1`, `games.recordStamps.v1`); beim ersten vollständigen Laden still
  übernommen, danach eine Pille (im Feed ohne Sprung).
- **Seiten**: „Erfolge“ (Level, Serie mit Wochenpunkten, Tagesziel, Wochenbalken, Abzeichen, fertige Monate); Bestwerte
  neu (Zuletzt geknackt, Filter, Paare je Kategorie mit Medaille und Datum, Snake/Blocks je ein Rekord mit nächster
  Medaille); „Heute“ mit Serien-Chip, Tagesziel-Balken im Hero und Wochenrückblick (Mo–Mi, wegtippbar); Verlauf mit
  Wochenbalken und Erfolge-Chip; Feed-Pillen bei jedem 100. Medium der Sitzung und beim Tagesziel;
  Sitzungs-Zusammenfassung mit Level, Serie und Ziel.
- **Einstellungen**: Erfolge anzeigen (Standard an), Tagesziel Aus/25/50/100 (Standard 50).
- Snake-Rekord jetzt über alle Feldgrößen (`PhotoGameRecords.snakeOverallBest`); gespeicherte Einzelwerte bleiben.
- Gamification löst nie eine Entscheidung aus und belohnt kein Löschen. Texte: 105 Kennungen in 16 Sprachen
  (`scripts/i18n/ios_strings_part19_gamification.py`).

## Regeln unverändert

Gesten, Entscheidungen, Löschwege, Werbung/Einwilligung, Tageslimit und Tresor-Logik sind nicht angefasst; nur Ansicht.
UI-Tests nutzen die Kennungen `tab.today|library|cleanup|studio|history` und `vault.key.0–9` (Ziffernfeld).

## Prüfstatus

- `swift test` (PhotoMaidCore, Linux): PASS (490 Tests inkl. `ReviewProgressTests`)
- `android_strings_to_xcstrings.py --check`: PASS
- Xcode-Build und Unit-Tests: PASS (CI-Läufe 39584295498, 39597390682; TestFlight-Läufe 39586915037, 39591723238, 39598302667)
- UI-Tests (QA-Daten): Lauf 39584295498 FAIL (2 Testhelfer-Probleme, korrigiert); Lauf 39599499410 PASS
- Heller Modus: Xcode-Build PASS (CI-Lauf 39602173887); UI-Tests darauf NOT RUN
- Gamification: Xcode-Build und Unit-Tests PASS (CI-Lauf 39628291349)
- Zahlenschloss-Rad: erster Build FAIL (Swift-6-Isolation der Farbhilfe, CI 39630003836 / TestFlight 39630131770, nichts hochgeladen); nach Korrektur 3bfb264 Xcode-Build und Unit-Tests PASS (CI-Lauf 39634182275), UI-Tests darauf noch offen
- TestFlight: interne Builds 1.0 (21), (22) und (23) hochgeladen und von Apple verarbeitet (21.10.2026, nur interne
  Tester); 22 mit Begrüßung nach Tageszeit, festem Kopf, Tableisten-Korrektur und Verlauf (10 neueste, Rest aufklappbar);
  23 mit tieferer Tableiste, plastischem Mittelknopf, kompakten Papierkorb/Später-Kacheln, Rückgängig am richtigen Eintrag
- TestFlight: Build 1.0 (24) mit Gamification und Zahlenschloss-Rad hochgeladen und von Apple verarbeitet (Lauf 39634177758, 21.10.2026, nur interne Tester)
- Geräteabnahme: NOT RUN
