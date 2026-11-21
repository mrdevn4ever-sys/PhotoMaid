# Konzept: „Dein Fotojahr“ – Jahresrückblick im Stil von Spotify Wrapped

Stand 21.11.2026 · **nur Plan, nichts gebaut** · Projektregeln: `CLAUDE.md`, Entscheidungen: `docs/IOS_ENTSCHEIDUNGEN.md`

## 1. Idee in einem Satz
Ein kurzer, bildschirmfüllender Rückblick in Story-Form (antippen = weiter) über das eigene Fotojahr – was du fotografiert hast und was du mit GaleriQ geschafft hast –, komplett auf dem iPhone berechnet und als schöne Karte teilbar.

**Name:** nicht „Wrapped“ (Spotify-Marke). Vorschlag: **„Dein Fotojahr 2026“** · EN „Your Year in Photos“. Alternativ „GaleriQ Rückblick“.

## 2. Warum
- **Für alle sofort nutzbar:** Die Fotostatistik kommt aus den Metadaten der Mediathek, nicht aus der GaleriQ-Nutzung – auch wer die App erst im November installiert hat, bekommt ein volles Jahr.
- **Wachstum:** Teilbare Karten mit kleinem GaleriQ-Schriftzug sind kostenlose Werbung (Instagram-/WhatsApp-Story).
- **App Store:** passt perfekt zu einem **In-App-Event** in App Store Connect („Dein Fotojahr 2026“) – erscheint in Suche und Produktseite.
- **Bindung:** Ende mit sanftem Übergang zum Aufräumen („Mit leichtem Gepäck ins neue Jahr“).

## 3. Ablauf (Story, ca. 10–13 Karten)
Jede Karte erscheint **nur, wenn echte Daten dafür da sind** (sonst wird sie übersprungen). Alle Zahlen gemessen, nichts geschätzt.

| # | Karte | Daten (Quelle) | Bemerkung |
|---|---|---|---|
| 1 | **Intro** „Dein Fotojahr 2026“ – das Tresor-Q im Schriftzug dreht sich, Hinweis „Alles auf deinem iPhone berechnet“ | – | setzt den Ton: privat, persönlich |
| 2 | **Die große Zahl** „2026 hast du 3.412 Fotos und 186 Videos aufgenommen“ (+ Vergleich zum Vorjahr, falls vorhanden) | PhotoKit: Aufnahmedatum, Medientyp | ohne Screenshots/Downloads zählen (eigene Karte) |
| 3 | **Dein fotoreichster Tag** „14. Juli – 213 Fotos“ + 4 Vorschaubilder des Tages | PhotoKit | Bilder nur in der App; beim Teilen optional |
| 4 | **Dein Jahr in Monaten** – animiertes Balkendiagramm, stärkster Monat hervorgehoben | PhotoKit | |
| 5 | **Dein Foto-Typ** (Persona, feste nachvollziehbare Regeln), z. B. „Golden-Hour-Jäger“ (meiste Fotos 17–20 Uhr), „Nachteule“, „Wochenend-Fotograf“, „Frühaufsteher“, „Serienschütze“ (viele Serien) | PhotoKit: Uhrzeit, Wochentag, Serien | humorvoll, nie wertend; Regeln in der App erklärbar |
| 6 | **Was du fotografierst** „Natur 38 % · Tiere 12 % · Essen 9 % …“ | Vorhandene **Vision-Analyse** auf dem Gerät (Kategorien) | nur wenn die Analyse gelaufen ist; ehrlich „von 1.240 analysierten Fotos“; keine neue Pflicht-Analyse |
| 7 | **Bewegte Bilder** „47 Minuten Video – dein längstes: 4:12 am 3. Mai“ · Live Photos | PhotoKit: Dauer, Subtypen | |
| 8 | **Screenshots** „1.028 Screenshots – 640 davon hast du schon aufgeräumt“ | PhotoKit + GaleriQ-Entscheidungen | Augenzwinkern, kein Vorwurf |
| 9 | **Deine Herzen** „112 Favoriten“ + Raster | PhotoKit: Favorit | |
| 10 | **Dein GaleriQ-Jahr** durchgesehen, aktive Tage, längste Serie, fertige Monate, neue Abzeichen | Ledger (`ReviewProgress`, `Achievements`) | Fokus auf **Durchsehen/Behalten**, nicht auf Löschen (s. Entscheidung W3) |
| 11 | **Kreativ & Spiele** Collagen/Filme/PDFs erstellt, Snake-Rekord, Paare-Bestzeit, Blocks-Rekord | „Bearbeitet“-Liste, Spielrekorde | nur wenn benutzt |
| 12 | **Deine Momente 2026** – 9 Vorschläge (Favoriten + Apples Ästhetik-Bewertung auf dem Gerät), austauschbar, „Als Collage speichern“ (Kopie) | Vision `CalculateImageAestheticsScores` (iOS 18+, lokal) | nur Vorschlag – der Nutzer wählt, nichts wird automatisch entschieden |
| 13 | **Outro + Teilen** Zusammenfassungskarte, „Teilen“, sanfter Hinweis „Mit leichtem Gepäck ins neue Jahr → Aufräumen starten“ | – | |

Bedienung wie Instagram-Stories: tippen rechts/links, gedrückt halten = Pause, runter = schließen. Kurze Animationen (zählende Zahlen, wachsende Balken), Haptik. **Keine Musik** (Lizenzen), Bewegung reduziert, wenn „Bewegung reduzieren“ an ist. VoiceOver liest jede Karte als Satz vor.

## 4. Teilen
- Pro Karte und als Zusammenfassung: **9:16 (Story)** und **1:1 (Beitrag)**, als neues Bild erzeugt (SwiftUI-Renderer, kein Screenshot), über das System-Teilen-Menü.
- **Standard: nur Zahlen und Grafiken, keine eigenen Fotos.** Fotos auf der Karte nur nach ausdrücklicher Auswahl im Teilen-Dialog; Ortsdaten sind nie enthalten.
- Kleiner GaleriQ-Schriftzug (Tresor-Q) unten auf jeder Karte – keine URL/QR-Pflicht, optional „Im App Store“-Hinweis.
- Kein eigener Upload, kein Server, keine Links mit Kennungen.

## 5. Einstiege
- **Heute-Tab:** große Karte „Dein Fotojahr 2026 ist da“ im Aktionszeitraum.
- **Erfolge-Bereich:** dauerhaft „Rückblicke“ (auch frühere Jahre, soweit Mediathekdaten vorhanden).
- **Optional Mitteilung** (nur wenn Mitteilungen erlaubt, einmalig) – siehe Entscheidung W6.
- Einstellungen: Schalter „Jahresrückblick zeigen“ (wie „Erfolge zeigen“).

## 6. Regeln aus `CLAUDE.md` – wie sie eingehalten werden
| Regel | Umsetzung |
|---|---|
| Kein Backend, kein Upload, kein Konto | alles lokal; Teilen nur über das System-Menü auf Wunsch |
| Bildanalyse nur Apple-Frameworks auf dem Gerät (E7), kein LLM | Kategorien aus vorhandener Vision-Analyse, Ästhetik-Score von Vision; Persona aus festen Regeln |
| Ergebnisse sind Vorschläge, nie Entscheidung | „Momente“ sind austauschbare Vorschläge; der Rückblick löst nie eine Entscheidung aus |
| Keine erfundenen Zahlen | jede Zahl gemessen; fehlt eine Grundlage → Karte entfällt; Analyseanteile mit Basis („von N analysierten“) |
| Tresor, ausgeblendete und ausgenommene Medien | werden **vollständig ausgeschlossen** (wie bei den Spielen); Tresor wird nirgends erwähnt |
| Originale nie verändern | „Als Collage speichern“ immer als neue Kopie |
| Werbung nur Free, nie Entscheidung (E19) | Vorschlag: **keine Werbung im Rückblick** (W5) |
| Texte nur über `Localizable.xcstrings`, alle 45 Sprachen, RTL | neue Kennungen sofort in allen Sprachen inkl. Plural; RTL gespiegelt, Diagramme/Zeitachsen bleiben links→rechts |
| Keine privaten APIs | nur PhotoKit-Metadaten; **keine** „Personen“-Alben (nicht öffentlich), **keine** Ortsnamen per Online-Geocoding (W4) |

## 7. Technik (grob)
- **PhotoMaidCore** (plattformneutral, Linux-Tests): neues Modul `YearInReview` – reine Funktion: Eingaben (Asset-Metadaten: Datum, Typ, Subtypen, Dauer, Favorit, Serie; GaleriQ-Ereignisse; Spielrekorde; Studio-Ergebnisse; Analysekategorien) → Liste der Karten mit Werten. Persona-Regeln, Schwellen, Vorjahresvergleich, Zeitzonen/Sommerzeit, Schaltjahr.
- **App:** `Features/YearInReview/` (Story-Ansicht, Karten, Teilen-Renderer), Daten über die vorhandenen PhotoKit-/Ledger-Dienste; Berechnung im Hintergrund mit Fortschritt, Ergebnis pro Jahr zwischengespeichert, bei Änderungen der Mediathek neu.
- **Leistung:** 100.000 Medien nur Metadaten → wenige Sekunden; Vorschaubilder klein über `PHImageManager` (iCloud erlaubt, wie bei den Spielen).
- **Tests:** Core-Unit-Tests (leere/eingeschränkte Mediathek, nur iCloud, Tresor-Ausschluss, Jahresgrenzen, Sommerzeit), UI-Test mit Testmediathek, Store-Aufnahme für Screenshots/Event-Bild.
- **Eingeschränkter Fotozugriff:** Rückblick nur über die freigegebenen Fotos, mit Hinweis.

## 8. Zeitplan (Vorschlag)
Heute ist der 21.11. Damit es **dieses Jahr** zählt:
1. Entscheidungen W1–W8 (unten) – 1 Tag
2. Core-Modul + Tests – 2–3 Tage
3. Story-UI, Teilen, 45 Sprachen, Barrierefreiheit – 4–5 Tage
4. CI, interner TestFlight, Gerätetest – 2 Tage
5. App-Review + In-App-Event anlegen → **im Store ca. 10.–12.12.**, Event bis 31.01.

Wenn das zu knapp ist: Rückblick ganzjährig ab 1.1. für „2026“ – verliert aber den Dezember-Effekt.

## 9. Offene Entscheidungen (bitte festlegen)
| | Frage | Vorschlag |
|---|---|---|
| W1 | Name | „Dein Fotojahr 2026“ / „Your Year in Photos“ |
| W2 | Zeitraum | 1.1.–31.12.; im Dezember „Stand heute“, ab 1.1. endgültig; frei verfügbar 1.12.–31.1., danach im Erfolge-Bereich |
| W3 | Löschzahlen/gesparter Speicher zeigen? | **Nein** – passt zur Abzeichen-Regel „bewusst nichts für gelöschte Mengen oder Speicher“; Fokus auf Durchsehen und Behalten |
| W4 | Orte („Du warst an 23 Orten“) | Weglassen oder nur Anzahl grober Orts-Cluster **ohne Namen** (Online-Geocoding würde Koordinaten senden) |
| W5 | Werbung | keine Werbung im Rückblick, auch in Free |
| W6 | Mitteilung zum Start | eine einmalige Mitteilung, nur wenn Mitteilungen bereits erlaubt |
| W7 | Free/Pro | komplett frei für alle (passt zu E19) |
| W8 | Fotos auf Teilen-Karten | standardmäßig aus, nur nach ausdrücklicher Auswahl |

## 10. Nicht Teil des Plans
Keine Server-Statistik, keine Bestenlisten/Vergleiche mit anderen Nutzern, keine Personen-Erkennung, keine Musik, keine automatischen Löschvorschläge im Rückblick, kein Upload.
