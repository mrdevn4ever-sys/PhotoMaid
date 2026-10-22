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
- **Suche im Tab „Fotos“ entfernt** (Nutzer, 21.10.2026: „falls du kein easy fix hast entfern die suche“): Sie las
  beim Öffnen alle Dateinamen einzeln (bei großen Mediatheken minutenlang Ladekreis), und Personennamen stellt iOS
  Apps nicht bereit – „Ellie“ wäre auch repariert nie gefunden worden. Ordner-Suche und Schlagwörter bleiben.
- **Keine Hitzewarnung in der ganzen App** (Nutzer, 21.10.2026): `AnalysisRunner.thermalLevel()` deckelt jede erhöhte
  iOS-Wärmestufe auf „erhöht“ – Foto-Analyse, Größen messen und Duplikatsuche drosseln nur (halbe Parallelität mit
  Pause), warten und halten nie an; die Texte „Wartet, bis das iPhone abgekühlt ist“ / „sehr heiß“ erscheinen nirgends
  mehr (alte gespeicherte Zustände zeigen „läuft“ bzw. „angehalten“).
- **Snake ohne Wärme-Sperre** (Nutzer, 21.10.2026: „Das iPhone ist nicht überhitzt“): Snake hielt bei der iOS-Wärmestufe
  „ernst“ an („Wartet, bis das iPhone abgekühlt ist“), die schon unter normaler Last gemeldet wird. Entfernt; das
  leichte Spiel läuft weiter, echte Überhitzung regelt iOS selbst.
- **Analyse „Warte auf WLAN“ trotz WLAN** (Nutzer, 21.10.2026): „Nur WLAN“ verlangte zusätzlich ein nicht „teures“ und
  nicht eingeschränktes Netz – Persönlicher Hotspot, Datensparmodus oder VPN galten als „kein WLAN“. Jetzt: WLAN oder
  Kabel genügt, Mobilfunk nie (`AnalysisNetwork.permitsCloud`). Neu: Wird WLAN verfügbar, setzt eine wartende
  Analyse von selbst fort (`.analysisNetworkReady`), wie die Oberfläche es verspricht.
- **Rundgang auf der Startseite** (Nutzer, 21.10.2026): „Ansehen ändert nichts“ aus dem Fotos-Schritt entfernt
  (alle 16 Sprachen). Neu: Schritt „Zeit für eine Pause?“ an der Karte „Kurze Pause“ (Paare, Foto-Snake, Foto Blocks
  mit eigenen Fotos) und als letzter Schritt „Dein privater Tresor“ am Schriftzug („PhotoMaid“ 2 Sekunden halten,
  Einrichten und Optionen in den Einstellungen). Der Tresor-Schritt entfällt bei „Eingang verstecken“, damit ein
  neu gestarteter Rundgang den Tresor nicht verrät.
- **Fächer im Hero bewegt sich nur sichtbar** (Watchdog-Bericht Build 21, 0x8BADF00D „Failed to terminate gracefully“,
  Hauptthread mitten in einem Zeichendurchlauf): Der Feed liegt als Ebene über den Tabs, die Startseite bleibt darunter
  bestehen – drei wiederholte `keyframeAnimator` zeichneten dort jedes Bild neu (auch in der Ruhephase, auch unter dem
  Feed). Jetzt einzelne Animationen mit Pausen ohne Zeichnen, und still, sobald Feed, Vollbild, Spiele, Tresor,
  ein anderer Tab, eine Unterseite oder der Hintergrund aktiv ist. Der Bericht stammt aus Build 21 (MetricKit liefert
  verzögert); das Löschen von 19 Medien im mitgeschickten Protokoll gehört zu einem anderen Start von Build 24.
- **Entscheidungstasten im Feed passen in die Breite** (gefunden im Real-Library-UI-Test 30, 22.10.2026): Mit „Tasten
  anzeigen: Immer“ oder VoiceOver waren fünf Tasten (4 × 64 + 80 pt, 22 pt Abstand) breiter als ein iPhone; die Zeile
  schob den ganzen Feed seitlich hinaus (⋯, Rückgängig, Papierkorb-Zähler bei x = 400–444 auf 402 pt). Jetzt die
  größte Stufe, die passt (64/80 → 56/68 → 48/56 → 44/48 pt), mindestens 44 pt Tippfläche. Betraf alle Builds 21–24.
- **Foto Blocks wackelt nicht mehr** (Nutzer, 22.10.2026: „Es wackelt weil unten ein Text auftaucht“ → „Der Text soll
  nie kommen“): Unter dem Spielfeld erschien kurz „Bilder werden vorbereitet …“ bzw. ein Speicher-Hinweis und schob
  das Brett hoch. Der Text ist ganz entfernt; ein Speicherproblem zeigt nur ein Warnsymbol (erneut speichern) in der
  Spielleiste oben.
- **Einheitliches Spiele-Design** (Nutzer, 22.10.2026: „Können wir das Design vereinheitlichen“, `GameChrome.swift`):
  Paare, Foto-Snake und Foto Blocks haben dieselbe Kopfzeile (Schließen · Spielname · Andere Spiele), dieselbe
  Startseite (Symbolkachel, ein Satz, Rekord, Karte „Fotos“, Bernstein-Knopf „Spiel starten“), dieselben Pause- und
  Ende-Fenster und dieselben Beschriftungen (Nochmal, Fortsetzen, Fotos ändern). Nur das Spielfeld selbst behält
  sein Aussehen. Bernstein-Akzent für das ganze Spiele-Fenster – Paare aus dem Feed war vorher blau.
- **Spielfotos laden parallel** (Nutzer, 22.10.2026: „Können wir laden verschnellern?“): Paare und Snake luden ihre
  Fotos strikt nacheinander; jetzt bis zu sechs gleichzeitig (gleiche PhotoKit-Vorschau, gleiche Reihenfolge, jede
  Kennung vorher gegen Tresor/Ausgeblendet/Zugriff geprüft, Abbrechen wie bisher).
- **Laufende Spielszenen** (Nutzer, 22.10.2026: „Vielleicht mehr game-mäßig, damit klar ist, um was es geht? Zu
  statisch“, `GameShowcase.swift`): Statt einer Symbolkachel zeigt jede Startseite oben eine kleine Szene in Schleife –
  Paare (Finger tippt, Karten drehen sich, ein Fehlversuch, dann alle Paare mit Haken), Foto-Snake (Schlange aus runden
  Fotos frisst Obst und wächst, Finger wischt vor jeder Kurve), Foto Blocks (Stein fällt in die Lücke, volle Reihen
  verschwinden, Foto wird Streifen für Streifen frei, nächster Stein links). „Kurze Pause“ zeigt dieselben Szenen
  klein auf den Spielkarten. Rekord als Bernstein-Plakette. Nur Ansicht: gezeichnete Beispielbilder statt
  Mediathek-Fotos, keine Eingabe, kein Spielstand; zeichnet nur bei aktiver App, bei „Bewegung reduzieren“ ein fester
  Moment; Richtungen nie gespiegelt. Läuft nach dem Erscheinen eine Weile (Karten 4 s, Startseite 1 min) und ruht dann
  auf dem letzten Bild; die große Snake-Wiese liegt als feste Ebene dahinter statt in jedem Bild neu gezeichnet.
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
  Medaille); „Heute“ mit Serien-Chip, Tagesziel-Balken im Hero und Wochenrückblick „Deine letzte Woche“ (immer da, kein X; Nutzer 21.10.2026: nur in Einstellungen › Erfolge abschaltbar); Verlauf mit
  Wochenbalken und Erfolge-Chip; Feed-Pillen bei jedem 100. Medium der Sitzung und beim Tagesziel;
  Sitzungs-Zusammenfassung mit Level, Serie und Ziel.
- **Einstellungen**: Erfolge anzeigen (Standard an), Tagesziel Aus/25/50/100 (Standard 50).
- Snake-Rekord jetzt über alle Feldgrößen (`PhotoGameRecords.snakeOverallBest`); gespeicherte Einzelwerte bleiben.
- Gamification löst nie eine Entscheidung aus und belohnt kein Löschen. Texte: 105 Kennungen in 16 Sprachen
  (`scripts/i18n/ios_strings_part19_gamification.py`).

## Bild- und Videobearbeitung im Tresor (Nutzerwunsch 21.10.2026)

- Im Tresor-Betrachter „Bearbeiten“ (Stift) für Fotos, Live Photos (als Standbild) und Videos: derselbe Foto- bzw.
  Video-Editor wie außerhalb, aber mit Quelle aus dem Tresor (`VaultStore.editPhotoSource`/`editVideoSource`).
- Speichern nur „Als Kopie im Tresor“ (Vorauswahl) oder „Kopie speichern, Original in den Tresor-Papierkorb“; kein
  „Original bearbeiten“, kein „Nur teilen“, kein Ton-Export. Standbilder aus Videos ebenfalls in den Tresor.
- Ergebnis: neues verschlüsseltes Medium im selben Ordner (`VaultEdit`, `VaultSnapshot.addEdited`, ein
  Schreibvorgang; Ersetzen legt das Original im selben Schritt in den Tresor-Papierkorb), mit verschlüsseltem
  Vorschaubild und ohne Kennung in der Fotos-App. Nie in der Fotos-App, nie in „Bearbeitet“, nie im Verlauf/Ledger,
  keine Toasts außerhalb, keine Caches auf der Platte; Klartext (Video-Quelle, Export) nur in der Temp-Ablage der
  Sitzung, sofort danach gelöscht, spätestens beim Sperren. Sperren schließt den Editor; ein Export zählt als
  Bedienung (keine Inaktivitätssperre mittendrin).
- Sicherheitsprüfung (Code-Review 21.10.2026, alle Wege der Tresor-Bearbeitung) – behoben:
  - Sperren bricht einen laufenden Tresor-Export sofort ab (`ExportCoordinator.cancelVaultWork`); Tresor-Exporte laufen
    nie im Hintergrund weiter, halten den Bildschirm nicht wach und zeigen keinen „App kurz wechseln“-Hinweis.
  - Export schreibt nur in den schon angelegten geschützten Ordner der Sitzung (nach dem Sperren nie neu angelegt), ohne
    zweiten Schreibdurchgang für Netz-Optimierung.
  - Editor schon geschlossen, während das Video noch entschlüsselt wird: die Datei wird sofort gelöscht.
  - „Ersetzen“ + Tresor-Papierkorb leeren: das Fotos-Original bleibt verborgen (`VaultItem.concealsOriginalID`).
  - Inaktivitätssperre prüft der Tresor selbst und Berührungen in Betrachter/Editor verlängern die Sitzung.
  - Bearbeitungen sind an die Sitzung beim Öffnen gebunden (nach Sperren + Öffnen nie in die neue Sitzung).
  - Texteingaben im Tresor-Editor ohne Autokorrektur-Lernen; Sperren setzt Zähler und letztes Ergebnis zurück;
    Videos im Betrachter werden beim Weiterblättern gelöscht; Zusammenfügen nimmt die gemessene Videolänge.
  - Bestätigt unverändert: kein Weg in Fotos-App, Ledger/Verlauf, „Bearbeitet“, Erfolge, Toasts, Zwischenablage,
    Spotlight; Diagnose nur Ereignisname + Fehlercode.
- Tempo (langsamer/schneller), Schnitt, Farbe, Text, Ton und Format: Werkzeuge des Video-Editors, im Tresor über
  „Bearbeiten“. **Videos zusammenfügen** (Nutzer, 21.10.2026): im Raster mindestens zwei Videos auswählen →
  „Video zusammenfügen“ (`VaultMovieView`): Reihenfolge, Schwarzblende, Format, Qualität; derselbe Film-Export wie im
  Studio (`VideoExportJob.renderMovie`), Ergebnis nur im Tresor (Ordner des ersten Clips, ohne Standort), Quellen
  bleiben. Keine Musik aus „Dateien“ im Tresor (bewusst schlank gehalten).
- Tests: `VaultEditTests` (Linux), UI-Tests `test13EditPhotoInsideVaultStaysInVault`, `test14MergeVideosInsideVault`.

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
- Nacht 21./22.10.2026 (Rundgang, Hero-Fächer, Feed-Tasten, Testanpassungen):
  - `swift test` (Linux): PASS (495 Tests); `android_strings_to_xcstrings.py --check`: PASS
  - QA-UI-Tests mit Rundgang (Spiele- und Tresor-Schritt, kein „Ansehen ändert nichts“): PASS (7d4cea2, Lauf
    39675285627; 0ee501d mit Feed-Tasten-Fix, Lauf 39690942458)
  - Real-Library-UI-Tests: 9 von 11 PASS auf 0ee501d (Lauf 39690938843); FAIL test00 (Werbe-/Einwilligungsablauf beim
    Kaltstart) und test98 (Papierkorb-Limit) – beide schon vor dieser Nacht rot. **Korrektur:** Der Lauf vom 21.10.
    17:39 UTC (f307dd3) war nicht „bis auf einen Schritt grün“: Sieben Real-Library-Tests waren rot, die Schritte
    zeigten wegen `continue-on-error` trotzdem grün. Davon waren sechs Testanpassungen an das Design, einer ein echter
    Fehler (Feed-Tasten, behoben, gezielter Lauf 39690653443 PASS).
  - Spiele-UI-Tests (891b12a, Lauf 39687137413): FAIL test40 (Snake bei XXXL auf Arabisch, iPhone – identisch auf
    `main`, Lauf 39675303256, vorbestehend seit dabbdd7), test60 (Snake bewegt sich nicht innerhalb 8 s, beide
    Geräte) und test35 (PDF, großes Fenster) – Snake-/PDF-Code in Lauf 222 und 224 identisch, in Lauf 222 PASS; alle
    übrigen PASS (test30 Studio/Feed-Zähler und test05 jetzt PASS)
- TestFlight: Build 1.0 (25) mit Tresor-Bearbeitung, Rundgang Spiele/Tresor, ohne Hitzewarnung, Analyse-WLAN-Fix,
  Wochenrückblick fest, ohne Fotos-Suche, Hero-Fächer nur sichtbar und Feed-Tasten-Fix (ff6c674) hochgeladen und von
  Apple verarbeitet (Lauf 39698316933, Unit-Tests davor PASS, 22.10.2026, nur interne Tester). Ein erster Versuch
  (Lauf 39690300592) wurde vor dem Upload abgebrochen, um den Feed-Tasten-Fix einzuschließen.
- Spiele-UI-Tests mit parallelem Laden (e62beb8, Lauf 39731198318): iPhone und großes Fenster PASS bis auf test40
  (Snake bei XXXL auf Arabisch, iPhone – vorbestehend, siehe oben); test60 und test35 diesmal PASS
- TestFlight: Build 1.0 (26) mit einheitlichem Spiele-Design, parallelem Foto-Laden, Blocks ohne Wackeln/Hinweistext
  und Bernstein-Akzent (52d8460) hochgeladen und von Apple verarbeitet (Lauf 39733444754, Unit-Tests davor PASS,
  22.10.2026, nur interne Tester). Ein erster Versuch (Lauf 39733054664) wurde vor dem Upload abgebrochen, um den
  Akzent-Fix einzuschließen. Die laufenden Spielszenen (f789db1) sind noch nicht in diesem Build.
- Laufende Spielszenen: Blocks-Tests + test05 auf iPhone und großem Fenster PASS (f789db1, Lauf 39735195960);
  nach der Blocks-Überarbeitung (951e19d, Lauf 39739125820) Blocks PASS auf beiden, test05 iPhone FAIL / großes
  Fenster PASS (Snake bewegt sich nicht innerhalb 8 s); 0454597 (Lauf 39742166262) iPhone beide PASS, großes Fenster
  beide FAIL (Blocks-Wisch nach links nicht erkannt, Snake bewegt sich nicht). Ursache für die Häufung: Die
  dauerhaft laufenden Szenen ließen die App für XCUITest nie zur Ruhe kommen – Wartezeiten auf „idle“ von 23 s (ohne
  Szene) auf 32–59 s, Testdauer bis fast dreifach, am längsten beim Öffnen von „Kurze Pause“ (drei Szenen, große Wiese
  in jedem Bild). Behoben durch Ruhephase und feste Wiesen-Ebene (siehe oben); Nachweis im nächsten Lauf
- Geräteabnahme: NOT RUN
