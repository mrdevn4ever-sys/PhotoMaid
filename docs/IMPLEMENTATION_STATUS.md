# Implementierungsstatus

Stand: 16.10.2026 · Arbeitsbranch `feat/iphone-duo-games` · zuletzt hochgeladen und von Apple verarbeitet: Version 1.0, Build 11.
Apple hat laut Nutzer ITMS-91064 für Builds 8–10 gemeldet. Build 11 wurde am 16.10.2026 um 19:23 UTC
erfolgreich verarbeitet und an interne Tester verteilt. [TestFlight-Lauf](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38952167636).

## Spiele, Bestwerte und adaptive Arbeitsflächen (16.10.2026)

Memory-Bestzeiten und Snake-Rekorde bleiben lokal über App-Neustarts erhalten. Hochformat ist
für das normale iPhone deklariert. Breite Fenster erhalten einen Live-Papierkorb links neben dem
Feed, adaptive Dashboards und Raster sowie seitliche Editor-/Collage-Werkzeuge. Snake nutzt das ganze Fenster und ausschließlich Wischgesten; nur Schließen bleibt sichtbar.
F1–F5 des ursprünglichen Spieleaudits sind im Code korrigiert. 447 Core-Tests und 42 native Modelltests,
Übersetzungs- und lokale Privacy-Prüfungen bestehen. Alle sechs aktuellen Snake-UI-Fälle auf iPhone und
großem Fenster bestehen ebenfalls; native Aufnahmen und Rückwege sind geprüft. Memory-Sieg, gespeicherte
Bestzeit, Fotoquellen und adaptive Hauptseiten sind durch die verlinkten nativen Läufe belegt.

**Duo-Grenze:** Der verfügbare Runner hat Xcode 26.6 und keinen Duo-Simulator. Die breite native
Fensterprüfung ersetzt keine Faltabnahme. Apple verlangt SDK 27.1 für vollständige randfüllende
Duo-Unterstützung. [Umsetzung, Belege und genaue Prüfgrenzen](IPHONE_DUO_AND_GAMES.md).
[Historischer Audit-Snapshot](GAMES_FUNCTION_UI_AUDIT.md).

## Privacy-Manifest / ITMS-91064 (16.10.2026, Build 11 verarbeitet)

Zwölf Manifeste aus Projekt und Abhängigkeiten geprüft, einschließlich der offiziellen, per SHA-256
verifizierten GoogleMobileAds-13.9.0- und UserMessagingPlatform-3.1.0-ZIPs. Keine der SDK-Dateien enthält
Tracking-Domains bei `false`. Der eigene App-Eintrag `true` plus leere Domainliste ist jedoch laut Apple
TN3181 ebenfalls ungültig. Lokal durch den bekannten AdMob-Host ergänzt; Tracking bleibt deklariert.
Alle drei Manifeste der exportierten Build-11-IPA wurden vor dem Upload erfolgreich geprüft;
[unveränderter Bericht mit Manifest-Hashes](privacy-manifests-build11.json).

**PASS:** korrigierte Tracking-Deklaration, ursprüngliche zwölf Datei-Prüfungen, acht Regressionstests,
42 native Modelltests, alle drei Manifeste der neuen IPA, Upload und Apple-Verarbeitung von Build 11.
**NOT RUN:** ursprüngliche Build-8–10-IPAs und ATT-/Werbeabnahme auf einem echten Gerät.
[Vollständiger Befund mit Grenzen und Quellen](PRIVACY_MANIFEST_AUDIT.md).

## Foto-Snake und gemeinsame Spielauswahl (16.10.2026)

Die freiwillige Pause im Feed und bei Analysen bietet jetzt Memory und Foto-Snake. Ein Kamerakopf
sammelt Bilder und verlängert seinen Fotostreifen. Klassische feste Ränder oder entspannter
Randumlauf und drei Tempi. Im Spiel nur Wischgesten und Schließen; VoiceOver verwendet benannte Aktionen im Schrittmodus.
Vorbereitete, erneut geöffnete und neu gestartete Runden warten auf einen Swipe zum Fortsetzen.
App-Wechsel, Schließen und hohe Gerätetemperatur pausieren Snake.

Fotos stammen wahlweise zufällig aus Mediathek, Favoriten oder Album/Fotoordner (bis zu zwölf nutzbare
Vorschauen, mindestens eine), alternativ aus einer manuellen Auswahl von ein bis achtzehn Bildern.
Memory und Snake nutzen dieselbe Ladeimplementierung mit getrennten Bildspeichern und Spielständen.
Es gibt keine Fotoänderungen, Spiel-Uploads oder neuen Analyseaufträge.

**PASS:** zehn Snake-Regel-/Rastertests und sieben native Snake-/Fotolader-Tests; Bestandteil der oben
genannten Gesamtprüfung. Die Änderungen liegen im Arbeitsbranch und sind seit Version 1.0, Build 11
in TestFlight enthalten. [Bedienung, Grenzen und aktueller Prüfstatus](PHOTO_SNAKE.md).

## Foto-Memory mit eigenen Bildern (16.10.2026)

Auf Nutzerauftrag ist eine freiwillige Wischpause im Feed und bei laufender Analyse ergänzt.
Zufallsrunden mit 6, 12 oder 18 Paaren aus der Mediathek, Favoriten oder gewählten Alben/Fotoordnern
(einschließlich Unteralben), alternativ zwei bis achtzehn selbst gewählte Fotos oder sechs Symbolpaare,
ohne Zeitlimit. Neue Zufallsrunden wählen erneut aus derselben Quelle. Spielstand und
Feed-Position bleiben beim Schließen erhalten, solange dieselbe App-Instanz läuft. Kleine
Vorschauen bleiben im RAM; Tresorfotos sind ausgeschlossen, iCloud-Laden für das Spiel ist optional.
Analysefortschritt und Rückkehr zu den Ergebnissen sind im Spiel erreichbar.

**PASS:** sieben Memory-/Zufallsauswahl-Tests und sieben native Modelltests; Bestandteil der oben
genannten Gesamtprüfung. [Bedienung, Grenzen und aktueller Prüfstatus](PHOTO_MEMORY.md).

## 20 deutsche Werbevideos (15.10.2026, abgeschlossen)

Auf neuen Auftrag sind **20 verschiedene deutsche Hochkant-Werbevideos** erstellt: jeweils
18 Sekunden, 1080 × 1920, 30 fps, H.264/yuv420p und AAC-Stereo/48 kHz. Jede Variante hat einen
eigenen Einstieg, drei Inhaltsszenen und eine Schlusskarte mit „PhotoMaid entdecken“.
Fünf dunkle Farbwelten, fünf eigene Instrumentalbetten, deutsche Texte im Bild, ohne Sprecher.

[Alle 20 Videos mit Dateinamen und Schwerpunkten](../marketing/de/README.md) ·
[Interaktive lokale Galerie](../marketing/de/index.html) ·
[Konzepte und Texte](../marketing/de/concepts.json) · [Audit](../marketing/de/audit.json).
Die Galerie bietet Themenfilter, eine Merkliste für die geöffnete Sitzung und direkte Downloads.

| Punkt | Status | Dateien / Nachweis |
|---|---|---|
| 20 unterschiedliche Konzepte und fertige Filme | PASS | `marketing/de/videos/01-einfach-anfangen.mp4` bis `20-alles-in-einer-app.mp4`; vollständige Namen im Index |
| Format, Dauer, Bild-/Tonspur, vollständige Dekodierung | PASS | alle 20 Filme, je 540 Frames / 18 s; `marketing/de/audit.json` |
| Deutsche Texte und Übereinstimmung mit App-Funktion | PASS | 80 tatsächlich angesehene Bildstichproben, `marketing/de/review/` |
| 20 tatsächlich aus dem fertigen Film entnommene Poster | PASS | `marketing/de/posters/`, fünf gesonderte Prüfbögen |
| Tonmessung / Übersteuerung | PASS | −17,0 bis −17,1 LUFS, maximal −4,4 dBTP; fünf verlustfreie eigene FLAC-Master |
| Untertitel und Quellen | PASS | 20 optionale SRT-Dateien; Herkunft und SHA-256 in `marketing/de/manifests/` |
| Galerie / Browser-Wiedergabe / Merkliste / Mobilansicht | PASS | Chromium über lokalen HTTP-Server; Desktop/Mobil angesehen, Filter zählen 9/7/3/1, `marketing/de/gallery-check.json` |

Verwendet werden die geprüften deutschen Originalaufnahmen und der bestehende CC0-Fotobildsatz.
Screenshots erhalten eine leichte proportionale Kamerafahrt; bewegte Szenen stammen aus den echten
Feed-, Editor- und Tresor-Aufnahmen. Werbetexte und Grafiken stehen außerhalb des App-Bildes.
Es werden keine zusätzlichen Treffer, Medienzahlen, Speicherersparnisse oder Kaufpreise erfunden.
Eine leere Ähnlichkeitsansicht wurde als Werbevariante verworfen und durch frei belegbare Gesten ersetzt.
Der Export setzt quadratische Pixel ausdrücklich; die erste Serie wurde hierfür ohne erneute Kodierung
normalisiert. Die vollständigen Filme wurden dekodiert und stichprobenweise angesehen, nicht jeweils
in Echtzeit. Ton technisch geprüft, keine subjektive Hörabnahme.

Die Umsetzung liegt in `scripts/marketing/`; Marketingtexte sind deutsch und gehören nicht zum
App-Sprachkatalog. Dieser Nachtrag ändert kein App-Verhalten und erfordert keinen neuen TestFlight-Build.

## App-Store-Bildsatz und lokalisierte Dark-Mode-Aufnahmen (15.10.2026, abgeschlossen)

Auf ausdrücklichen Wunsch sind echte App-Store-Vorschauvideos erstellt (keine App-Clip-Erweiterung):
zuerst Seiten-Screenshots für alle 16 App-Sprachen, anschließend drei verschiedene Vorschauen je Sprache
(Aufräumen, Studio, Tresor). Alle Dateien sind geprüft und nach Sprache und Seite im Arbeitsbranch abgelegt.
Es gibt keinen weiteren TestFlight- oder App-Store-Upload in diesem Auftrag.

[Abschlussbericht mit Status-/Dateitabelle, endgültigen Läufen und Commitliste](../app-store/DELIVERY.md).

**Bildsatz PASS:** 45 Präsentationsfotos und 10 schwierigere Motive, alle echte Hochkant-JPEGs,
55 verschiedene SHA-256-Werte, jeweils einzeln geprüfte CC0-1.0-Lizenz.
Dateien, Urheber, Quellen, Lizenzbelege und Maße stehen in
[`app-store/media/SOURCES.md`](../app-store/media/SOURCES.md) und `manifest.json`.
Keine künstliche Verschlechterung, kein Hochskalieren. Der Bildsatz ist nicht Teil des App-Bundles.

Die Simulator-Aufnahme verwendet ausschließlich diese 55 importierten Bilder und echte PhotoKit-/Core-Data-
Daten, tatsächliche lokale Analysen sowie den normalen PIN-Tresor mit echten verschlüsselten Importen.
Die sechs vorinstallierten Simulatorfotos werden nur im ausgeschalteten, eigens angelegten
Wegwerf-Simulator vor dem Import entfernt. Der tatsächliche PhotoKit-Bestand wird auf exakt 55 passende
Originaldateinamen geprüft. Keine `-qa-fixtures`, erfundenen Treffer, Käufe oder Medienzahlen.
Systemlöschungen werden ausschließlich abgelehnt. Aufnahmehilfe und Werbeunterdrückung sind auf
`QA_FIXTURES && targetEnvironment(simulator)` plus `-store-capture` begrenzt; Release bleibt unberührt.

Aufnahme-Workflows: `.github/workflows/app-store-assets.yml`, auf diesem Branch über den vorhandenen
`ci.yml` mit `store_locales` und `ui_phase=store-screenshots` bzw. `store-previews` aufgerufen.
Native Screenshotgröße 1320 × 2868; Vorschauen 886 × 1920, H.264, 30 fps, 15–30 s, AAC-Stereo mit Stille.
Die Original-PNGs werden unverändert archiviert; die Videos schneiden ausschließlich echte Aufnahmen.
Sprachindex und Wiederholung: [`app-store/README.md`](../app-store/README.md).

**Screenshot-Phase abgeschlossen: PASS.** Alle 16 App-Sprachen sind im
[Sprachindex](../app-store/INDEX.md) abgelegt: **1.969 unveränderte native Seitenaufnahmen**,
**160 unveränderte Store-Vorschläge** und **176 beschriftete Prüfbögen**.
Jedes endgültige Bild wurde angesehen, jedem Original ist im Prüfmanifest sein SHA-256 zugeordnet.
Jede Sprachserie besteht aus 2/2 nativen UI-Tests, ohne Fehler oder Skip; die tatsächliche
PhotoKit-Inventarliste enthält genau die 55 Quelldateien. Der vollständige Screenshot-Audit besteht.
Portugiesisch enthält 124 statt 123 Bilder: zusätzlich den echten Pausenzustand vor der erfolgreichen
UI-Fortsetzung der Textanalyse bis 55/55.

| Sprachen | Endgültiger Screenshot-Lauf | Status / Dateien je Sprache |
|---|---|---|
| Deutsch, Englisch, Italienisch, Russisch, Ukrainisch, Chinesisch (vereinfacht) | `38735332484` · `defb941` | PASS · je 123 Originale + zehn Store-Vorschläge |
| Japanisch | `38742616639` · `bb4706f` | PASS · 123 + zehn |
| Arabisch, Französisch | `38744237961` · `59b6e81` | PASS · je 123 + zehn |
| Polnisch, Niederländisch, Rumänisch, Türkisch | `38748687136` · `819609e` | PASS · je 123 + zehn |
| Portugiesisch (Portugal) | `38748687136` · `819609e` | PASS · 124 + zehn |
| Spanisch | `38750057086` · `819609e` | PASS · 123 + zehn |
| Koreanisch | `38757333460` · `d8744fb` | PASS · 123 + zehn |

Die Bildprüfung bestätigt korrekt abgebildete App-Zustände, keine erfundenen Analyseergebnisse:
Französisch zeigt bei ähnlichen Fotos ehrlich 53/55 und zwei nicht analysierte Medien;
Niederländisch zeigt denselben Zustand bei der Textanalyse. Das steht zusätzlich in den jeweiligen
Prüfmanifesten. Diese Aufnahmen sind kein Nachweis, dass in diesen beiden Scans alle 55 analysiert wurden.
Die arabischen Gestenpfeile bleiben physisch links = Papierkorb, rechts = Später.
Leere Video-/Screenshot-Filter und Datei-/PDF-Eingänge entsprechen dem ausdrücklich reinen Foto-Bildsatz.

**Vorschau-Phase abgeschlossen: PASS.** Erst nach Abschluss und Push aller Screenshot-Serien wurde
`38764957492` auf `02e689f` für Deutsch, Englisch und Arabisch mit `store-previews` gestartet.
`38765595100` auf `364f9bf` nahm die übrigen 13 Sprachen auf; beide verwendeten denselben App-/Test-Code.
Drei Varianten je Sprache: Aufräumen, Studio, Tresor. Die UI-Tests prüfen tatsächliche Wischschritte,
veränderte Belichtung, gewählten Monochromfilter, Zeichnen und echten Tresorzoom; jeder Videoschritt
hat zusätzlich einen nativen Screenshot. Videoexport, vollständige Dekodierung, Sichtprüfung und
Ablage der insgesamt 48 Vorschauen sind abgeschlossen.

**48/48 Vorschauen PASS:** Alle 16 Sprachen sind vollständig exportiert,
vollständig dekodiert und mit je acht tatsächlich angesehenen Videobildern plus drei Postern geprüft.
Zusätzlich wurden alle 400 nativen Schritt-/Einrichtungs-Screenshots dieser 16 Sprachen angesehen.
Die Dateien liegen unter `app-store/locales/<Sprache>/previews/`; Ausgangsdaten, Tempo und Posterzeitcodes
stehen im jeweiligen Manifest. Der Gesamtaudit besteht einschließlich übereinstimmender Spurdauern.
Die Sichtprüfung umfasst Bildstichproben und Poster; die vollständigen Filme wurden technisch dekodiert,
aber nicht jeweils in Echtzeit angesehen. Die endgültigen Serien belegen insgesamt 96 bestandene native
UI-Testausführungen: 32 für die Seitenaufnahmen und 64 für Einrichtung/Vorschauen, ohne Fehler oder Skip.

| Sprachen | Native Vorschauaufnahme | Endgültiger Export | Stand |
|---|---|---|---|
| Deutsch, Englisch, Arabisch | `38764957492` · `02e689f` · je 4/4 native Tests | `38769640439` · `955333d` | PASS · je drei Videos und Poster |
| Japanisch | `38765595100` · `364f9bf` · 4/4 native Tests | `38769716633` · `955333d` | PASS · drei Videos und Poster |
| Spanisch | `38765595100` · `364f9bf` · 4/4 native Tests | `38770044249` · `955333d` | PASS · drei Videos und Poster |
| Französisch | `38765595100` · `364f9bf` · 4/4 native Tests | `38770563352` · `955333d` | PASS · drei Videos und Poster |
| Italienisch, Niederländisch | `38765595100` · `364f9bf` · je 4/4 native Tests | `38770999865` · `f146cd9` | PASS · je drei Videos und Poster |
| Koreanisch | `38765595100` · `364f9bf` · 4/4 native Tests | `38771629526` · `f146cd9` | PASS · drei Videos und Poster |
| Polnisch, Portugiesisch (Portugal) | `38765595100` · `364f9bf` · je 4/4 native Tests | `38772655624` · `1836474` | PASS · je drei Videos und Poster |
| Rumänisch, Türkisch | `38765595100` · `364f9bf` · je 4/4 native Tests | `38774573992` · `1e0daee` | PASS · je drei Videos und Poster |
| Ukrainisch, Chinesisch (vereinfacht) | `38765595100` · `364f9bf` · je 4/4 native Tests | `38775272307` · `1e0daee` | PASS · je drei Videos und Poster |
| Russisch | Wiederholung `38774007322` · `6ee08f3` · 4/4 native Tests | im selben Lauf | PASS · drei Videos und Poster |

Die ersten drei Sprachen bestanden jeweils 4/4 native Tests; der anschließende Export scheiterte jedoch
an variablen Simulator-Bildraten. Ein Studio-Clip wurde trotz gekürzter Wandzeitsegmente 36,8 s lang.
Die Originalaufnahmen und Schritt-Screenshots sind erhalten. Der korrigierte Export verwendet die ganze
tatsächliche Aufnahme mit normalisierter Bildrate, beschleunigt längere Abläufe auf 24 s und hält das
echte Schlussbild drei Sekunden. Der lokale englische Gegenversuch ergibt dreimal exakt 27 s.
`app-store-export.yml` kann vorhandene Quellen auf Linux erneut prüfen/exportieren, ohne bestandene
Simulator-Tests zu wiederholen; Aufnahme- und Exportcommit/-lauf werden getrennt ausgewiesen.
Der erste Linux-Gegenversuch `38768987654` war im Workflow grün, wurde aber durch die lokale
Bildstichprobe verworfen: Die Tresor-Bildspur endete trotz 27 s Container-/Tonspur schon nach 25,5–26,2 s.
Der Schlussbild-Halt wird deshalb bis zur expliziten Zieldauer fortgeführt; Export und Audit verlangen
zusätzlich übereinstimmende Bild-/Ton-/Containerdauer. Die verworfenen Originale bleiben als Beleg erhalten.

Russisch in `38765595100` bestand nur die Einrichtung (1/4); die drei Aufnahme-Tests meldeten einen
Recorder-Fehler. Der erhaltene Recorder-Log zeigt dennoch eine gestartete Aufnahme, und es entstand
ein zurückgelassener Recorder-Prozess. Die genaue alte Fehlerantwort wurde nicht archiviert.
Die Aufnahmehilfe wartet jetzt bis zu 45 statt zehn Sekunden auf Bereitschaft und beendet einen
fehlgeschlagenen Start zuverlässig. XCTest wartet auf die Antwort einschließlich Bereinigung bis 90 s,
zeigt deren Fehlertext und archiviert die Steuerantworten. Der frische russische Simulatorlauf
`38774007322` auf `6ee08f3` ist vollständig erfolgreich: 4/4 native Tests, sechs erfolgreiche
Recorder-Antworten und drei erfolgreiche Exporte. Das belegt die funktionierende Wiederholung;
die genaue alte Fehlerursache bleibt mangels archivierter Antwort unbewiesen. Die fehlgeschlagene
Serie wird nicht als bestanden gewertet; ihre zehn Einrichtungs-Screenshots wurden angesehen und
separat aufbewahrt.

Die Probeläufe fanden und korrigierten Fehler in der Aufnahmehilfe: sechs vorinstallierte Fremdfotos,
verzögerte System-Fotoabfrage, fehlendes `@Sendable` in einer PhotoKit-Änderung, ausgeblendete
Diashow-Leisten, Kaltstart-Navigationsabstände, außerhalb der Scrollansicht liegende Editorwerkzeuge,
umgekehrte Positionszählung auf Japanisch/Koreanisch, nicht vollständig geschlossene Systemabfragen,
Systembanner und noch ladende Metadaten. `d8744fb` löst wechselnde SwiftUI-Menütypen über die aktuelle
Beschriftung und Position auf, nachdem Koreanisch an einer veralteten XCTest-Button-Identität scheiterte.
Systemlöschungen wurden stets abgelehnt. Fehlgeschlagene Serien bleiben außerhalb der endgültigen Ablage.

Nachweislich verworfene Zwischenstände: Spanisch/Niederländisch/Türkisch/Portugiesisch im ersten Gesamtlauf
wegen blockierender Systemabfrage; Japanisch/Koreanisch wegen Test-Positionsauswertung; Polnisch wegen
XCTest-App-Startfehler. Französisch und die erste spanische Wiederholung bestanden nativ, hatten jedoch
Systembanner in einzelnen Bildern. Rumänisch hatte noch ungeladene Metadaten. Arabisch pausierte tatsächlich
bei der Textanalyse. `38730546597` und `38731542233` scheiterten an der Editor-Testabfrage;
`38732351800` wurde vor UI-Aufnahmen abgebrochen, um denselben Fehler nicht zu vervielfachen.
Die jeweiligen Wiederholungen in der Tabelle ersetzen diese Serien vollständig; keine Mischung aus Läufen.

Der Simulator-Testbuild wird einmal je Lauf kompiliert und mit erhaltenen Berechtigungen und
Framework-Verknüpfungen an die Aufnahmerunner übertragen; deren Xcode-Versionen müssen übereinstimmen.
Checkout der Runner schließt das wachsende fertige Bildarchiv aus, behält jedoch Quellcode und Testfotos.
Linux Swift 6.4.1: **394 Tests / 44 Suites PASS**. Textgenerator `--check`: **PASS**, 1572 verwendete
Kennungen, 2559 Einträge, 16 Sprachen. Neue App-Texte wurden nicht eingeführt.

Keine ausstehenden Aufnahmen oder Exporte dieses Assets-Auftrags. Format-, Dateinamen-,
Prüfsummen- und Platzhalterprüfung bestehen für alle 16 Sprachen. Eine vollständige sprachliche
Redaktion der bestehenden Übersetzungen ist damit nicht belegt; chinesische Texte enthalten
teilweise traditionelle Zeichen, lange native Steuerelementtitel werden teils gekürzt.
Dokumentenscanner/Kamera ist wegen fehlender Kamerafunktion im Simulator **NOT RUN**, mit nativem
Crashbericht aus dem verworfenen Scannerpilot belegt. Echtes Face ID, iCloud, 30.000 Fotos und Wärme
bleiben **NOT RUN** ohne physisches iPhone. Videoeditor/Wiedergabe mit echten Videodateien sind
mit diesem Foto-Bildsatz **NOT RUN**; eine echte Filmzusammenstellung aus fünf Fotos ist aufgenommen.
Wiederherstellungsschlüssel werden nicht veröffentlicht. E1–E19 unverändert.

## TestFlight-Build 9 mit Tresor-, Duplikat- und Zoom-Korrekturen (15.10.2026)

Auf erneute ausdrückliche Anweisung des Inhabers wurde `testflight.yml` mit Unit-Tests und
`confirm_upload=UPLOAD` auf Commit `cbf4610` gestartet.
[Lauf `38713405082`](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38713405082)
ist vollständig **PASS**: Signing-Preflight, 24 iOS-Unit-Tests (13 XCTest + 11 Swift Testing,
0 Fehler, kein Skip), Release-Archiv, Export, Upload und Schlüsselbereinigung.

**Version 1.0, Build 9** wurde um **09:39:58 UTC** hochgeladen. Apple-Verarbeitung,
Testhinweise und Verteilung an interne Tester sind um **09:42:03 UTC** bestätigt.
Enthalten sind alle drei nachfolgend dokumentierten Nachträge: Tresorinhalte per Wischen/Auswahl
in den Papierkorb verschieben, gemeinsamer Foto-/Video-Betrachter mit ausblendbaren Leisten,
Zeichnen bei Zoom einschließlich Rückgängig-Vorschau, vollständige Duplikatressourcen mit
ausdrücklich wählbaren iCloud-Originalen sowie die Korrektur der Anzeigeninitialisierung.

Das Artefakt `testflight-report` wurde heruntergeladen und geprüft: `unit-tests.log`, `gym.log`,
`fastlane/report.xml` und `ci-report.md`. Der generische Bericht erkennt den Archivabschluss
nicht (`UNBEKANNT`, 0 Compilerfehler, 1 Warnung); Archiv, Upload und abgeschlossene Verarbeitung
sind durch die erfolgreichen Fastlane-Schritte und das Workflow-Protokoll belegt.
Die vorherigen Simulatorbelege stehen in den jeweiligen Nachträgen; dieser Upload-Lauf führt
keine UI-Tests erneut aus. Reales iCloud, 30.000 Fotos, Wärme, Kamera und echtes Face ID bleiben
**NOT RUN** auf einem physischen iPhone. Keine echte Systemlöschung bestätigt, keine externe
Verteilung, keine Änderung an E1–E19, kein Merge und kein Push auf `main`.

## Tresor-Betrachter und Zeichnen bei Zoom (15.10.2026, nach Build 8)

**Abgeschlossen: Alle 14 QA-Testfälle sind nach gezielter Wiederholung bestanden.**
Letzter Code-Stand `89f3552`: [CI `38708113112`](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38708113112)
vollständig PASS (394 Linux-Tests, 24 native iOS-Unit-Tests, 3 Medien-UI-Tests, kein Skip).
Die übrigen UI-Fälle sind auf `4feaf77` belegt; die Berichte kombinieren diese Fachnachweise.
Die fehlgeschlagenen Zwischenläufe bleiben als solche dokumentiert.

Auf Nutzermeldung angeglichen: Fotos im Tresor verwenden dieselbe Zoom-/Doppeltipp-Bühne wie die normale
Fotoansicht. Kopf- und Aktionsleiste sowie die gemeinsame Video-Steuerung haben eigenen Platz oberhalb/
unterhalb des Mediums. Ein Tipp auf Foto/Video blendet die Leisten aus und wieder ein; VoiceOver erhält
dieselbe Aktion. Wischen blättert, nach unten schließt ohne Zoom. Entschlüsselung und geschützte Video-
Tempdateien bleiben ausschließlich beim Tresor; Sperren verwirft Vorschau/Player und schließt die Ansicht.

Im Fotoeditor schaltete der bisherige Code die Werkzeug-Geste bei Zoom ausdrücklich ab. Jetzt sitzt
sie innerhalb der Bildtransformation: Zeichnen, Retusche und Ebenenbewegungen erhalten bildlokale
Koordinaten. Ein Finger bearbeitet, zwei Finger zoomen/verschieben ausschließlich die Ansicht.
Auch Text/Sticker im Videoeditor lassen sich bei Zoom bewegen; abgebrochene Gesten schließen ihre
Rückgängig-Gruppe. Zoom verändert weder Rezept noch Export. Vergrößerte Vorschauen werden auf die
Bühne begrenzt und überdecken keine Werkzeuge.

Ein zweiter Fehler wurde in den Simulatorbildern sichtbar: Ein noch laufender Vorschauauftrag konnte
einen bereits rückgängig gemachten Strich verspätet anzeigen. Jede neue Vorschauanfrage entwertet
jetzt ältere Ergebnisse sofort. Der Editor zeigt die laufende Verarbeitung an; die Kopfknöpfe behalten
dabei ihre Position. Wechsel zwischen Werkzeugen mit gleichem Vorschaurezept rendern nicht erneut.

Neue Screenshot-Regressionen: `testZoomedPhotoMarkupAndUndo` (tatsächlicher Zoom, keine Änderung durch
Pinch, Zeichnen bei Zoom, genau ein Rückgängig-Schritt, Wiederholen, Gesamtbild; zusätzlich tatsächliche
rote Bildpunkte nach Zeichnen, Rückgängig und Wiederholen) und
`test12ViewerControlsPhotoZoomAndVideo` (Leisten außerhalb der Medien, Ein-/Ausblenden, Doppeltipp,
Abspielen/Pause, unveränderte Medienzahl). Sie gehören zum vorhandenen QA-Durchlauf.

| Prüfung dieses Nachtrags | Status | Beleg |
|---|---|---|
| Linux-Kern, Swift 6.4.1 | PASS | 394 Tests in 44 Suites; `/workspace/viewer-zoom-core-test.log` |
| Texte / Generator / `--check` | PASS | 4 neue Bedienhinweise/-aktionen in allen 16 Sprachen; 1572 verwendete Kennungen / 2559 Einträge |
| Swift-6-Syntax / Patchprüfung | PASS | Geänderte iOS-Dateien und UI-Tests mit `swiftc -frontend -parse`; keine iOS-Typprüfung |
| iOS-Build / Unit-Tests | PASS | `89f3552`, `38708113112`: Build, 13 XCTest + 11 Swift-Testing-Tests; 394 Linux-Tests in CI grün |
| Zeichnen bei Zoom / Vorschau / Rückgängig | PASS | [`38702261222`](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38702261222), `4feaf77`: 1 UI-Test, 0 FAIL / 0 SKIP; echte Strichpixel und Rückzoom 100 %, alle 17 unterschiedlichen PNGs angesehen |
| Tresor-Betrachter Foto/Video | PASS | Erneut `38708113112`, `test11` / `test12`; `vault_delete_viewer_next_item`, `vault_delete_photo_controls_hidden`, `vault_delete_photo_double_tap_zoom`, `vault_delete_video_controls_hidden`, `vault_delete_video_paused`, `vault_delete_viewer_media_preserved` |
| Tresor-Notizen / Dateien: Wischen, Auswahl, Abbrechen, Wiederherstellen | PASS | `38702264616` und `38702267912`, `test20` / `test30`; `vault_delete_notes_bulk_cancelled`, `vault_delete_notes_restored`, `vault_delete_files_bulk_cancelled`, `vault_delete_files_restored`; ungewählter Eintrag bleibt erhalten |
| Alle 14 QA-Testfälle nach Wiederholungen | PASS | `38702267912`: 13 PASS / 1 FAIL / 0 SKIP; der einzige Fehler anschließend in `38708113112` behoben und bestanden. Keine Behauptung eines grünen Gesamtlaufs auf dem Zwischenstand |
| Medien-Wischen / Auswahl | PASS | `89f3552`, `38708113112`, `test10`: Foto und Video wischen, Abbrechen erhält Inhalt, vier Medien auswählen/abbrechen/verschieben/wiederherstellen; `vault_delete_media_swipe_confirmation`, `vault_delete_media_bulk_cancelled`, `vault_delete_media_bulk_confirmed`, `vault_delete_photos_and_videos_restored` |

Nachprüfung auf `802b0b3`: iOS-Build und 24 Unit-Tests bestanden. Der erste QA-Lauf
[`38691761679`](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38691761679) ergab 7 PASS / 7 FAIL:
Die Duplikatsuche beendete den Lauf nicht; die neue Editor-Prüfung fragte einen noch außerhalb des
Bildschirms liegenden Werkzeugknopf ab. Im Tresor-Test war die Import-Beschriftung falsch, und der
Dateiauswahldialog wurde noch nicht zuverlässig auf „Durchsuchen“ umgestellt. Nach „Abbrechen“
verschwand eine Notizzeile bereits durch die native destruktive Wischrolle, vor einer Speicheränderung.

`34390b6` verlegt blockierende PhotoKit-Leser vom kooperativen Swift-Ausführungspool in eine eigene
Dispatch-Queue. Abbrechen bleibt über eine threadsichere Markierung wirksam. Der tatsächliche
PhotoKit-Fachtest mit 159 Medien besteht danach in Lauf `38697133324`: sichtbarer Fortschritt,
Abschluss, fünf Kopien, große Dateien und Speicherübersicht. Zwölf unterschiedliche PNGs angesehen.
Eine zusätzliche PhotoKit-Unit-Testvariante wurde wegen fehlender Freigabe im Unit-Host übersprungen
und wieder entfernt; sie gilt ausdrücklich nicht als Nachweis. Der echte UI-Fachtest ist der Nachweis.

Notiz-/Datei-Wischaktionen warten ohne vorzeitige Zeilenentfernung auf die Bestätigung. Ihre gesamte
Zeilenfläche ist jetzt antippbar; zuvor änderte ein Tipp auf den freien Bereich die Auswahl nicht.
Testelemente behalten ihre Kennung statt einer veränderlichen Listenposition. Der System-Dateidialog
wird über seine Dateizellen bedient. Die Systemlöschung wird auch bei der Beschriftung „Don’t Allow“
ausschließlich abgebrochen. Längere QA-Videos ermöglichen die Prüfung von Abspielen und Pause vor
Videoende. Dies verändert keine Produktionsmedien.

Im Medienraster konkurrierte die SwiftUI-Wischgeste am Button mit dessen Antippen und der Scrollansicht:
Die Bestätigung erschien nicht, stattdessen wurde der Betrachter angestoßen. `89f3552` bindet eine native
linke Wischgeste ein; sie kooperiert mit dem Scrollen und ist im Auswahlmodus deaktiviert. Die
Bestätigung und der Speicherweg bleiben gemeinsam. Die drei Medienfälle bestehen danach vollständig.
Alle 68 unterschiedlichen PNGs aus `38708113112` wurden angesehen; der Abgleich mit den originalen
`.xcresult`-Payloads zeigt keine fehlenden Bilder. Logs und Ergebnisbündel sind heruntergeladen.

Die Startprüfung `38692373177`, ihre Wiederholung `38694627007` und der Startteil von `38697133324`
meldeten `app-open-load-window-expired`. Ursache: `ready` wurde vor dem asynchronen Abschluss der
Google-SDK-Initialisierung gesetzt; das viersekündige Anzeigen-Ladefenster begann zu früh. `04eef69`
wartet auf den echten SDK-Abschluss. Lauf [`38698567816`](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38698567816)
ist vollständig PASS: Start 1–3 ohne Anzeige, Start 4 mit Google-Testanzeige, sicher geschlossen;
13 unterschiedliche PNGs angesehen. Keine Verlängerung des Fensters und keine Änderung an E19.

Alle 79 unterschiedlichen PNGs des ersten QA-Laufs wurden angesehen. Original-`.xcresult` vollständig
als drei Teile gesichert; Sammellauf `38695361479`. Weitere geprüfte Bilder: `38692373177` (15),
`38694627007` (12), `38697126087` (16 Editor), `38697133324` Start (11),
`38697129861` (81 Tresor; Original-`.xcresult` in zwei
Teilen über Sammellauf `38701049892`). Im späteren Tresorlauf `38702264616` wurden alle 110
unterschiedlichen PNGs angesehen und mit den Original-Payloads im `.xcresult` abgeglichen.
Der gesamte spätere QA-Lauf `38702267912` enthält 144 unterschiedliche PNGs; alle angesehen.
Original-`.xcresult` vollständig als zwei Teile über Sammler `38708643537` gesichert.
Fehlgeschlagene Zwischenläufe bleiben FAIL. `38697129861`
besteht bereits das Weiterblättern nach Löschen; seine übrigen Befunde führten zu den Korrekturen oben.

Screenshot-Namen der Regressionen: `editor_05_zoomed_no_edit`, `editor_06_stroke_at_zoom`,
`editor_07_zoomed_stroke_undone`, `editor_08_zoomed_stroke_redone`,
`editor_09_full_image_stroke_alignment`, `vault_delete_photo_controls_hidden`,
`vault_delete_photo_double_tap_zoom`, `vault_delete_video_controls_hidden`,
`vault_delete_viewer_media_preserved`. Editorlauf und abschließende Medien-Wiederholung sind
vollständig PASS. Alle 14 unterschiedlichen QA-Fälle sind damit fachlich belegt; Notizen und Dateien
wurden im vorausgehenden Gesamtlauf bestanden.
Build 8 enthält diesen Nachtrag noch nicht; seit Build 9 ist er in TestFlight enthalten (siehe oben).
E1–E19 unverändert.

Commits der drei Nachträge nach Build 8 (auf dem genannten Branch gepusht):

| Commit | Änderung |
|---|---|
| `ff6add0` | Tresorinhalte per Wischen und sichtbarer Auswahl löschen |
| `fedf05d` | Tresor-Regression und blockierte iOS-Prüfung dokumentieren |
| `a52b8c4` | Duplikatsuche für vollständige Medien und iCloud öffnen |
| `7be7448` | Unvollständige Dateiquellen und Duplikat-Prüfstatus festhalten |
| `10351ad` | Tresoransicht angleichen und Zeichnen bei Zoom erlauben |
| `802b0b3` | Zwei-Finger-Geste über die UIKit-Schnittstelle anbinden |
| `34390b6` | Duplikat-Leser entkoppeln und Tresor-Abbruch erhalten |
| `3a7342f` | Fotozugriff vor der PhotoKit-Regression erlauben |
| `04eef69` | Werbe-SDK vor dem Anzeigen-Ladefenster initialisieren |
| `65db7cb` | PhotoKit-Zugriff nach Installation und vollständigen Rückzoom prüfen |
| `4feaf77` | Vorschau nach Rückgängig und volle Tresor-Zeilen korrigieren |
| `89f3552` | Medien-Wischgeste im Tresor mit dem Raster abstimmen |

Die zusätzliche PhotoKit-Unit-Testvariante aus den Zwischenständen ist im endgültigen Stand wieder
entfernt; sie war wegen der Unit-Host-Berechtigung nicht aussagekräftig. Keine Prüfung wird durch Skip
grün gerechnet. Die Laufberichte und Bilder dokumentieren sowohl Fehlschläge als auch Wiederholungen.


## Duplikate: alle Ressourcen und ausdrücklich gewählte iCloud-Originale (15.10.2026, nach Build 8)

Auf die Nutzermeldung mit sehr vielen ungeprüften Medien: Der bisherige Scanner schloss Live Photos,
bearbeitete Aufnahmen und RAW+JPEG pauschal aus. PhotoKit-Anfragen erlaubten ausschließlich lokale
Bytes; gespeicherte „nur iCloud“-/Fehlerstände wurden 12/24 Stunden lang nicht erneut versucht.

Commit `a52b8c4` ersetzt diese Einschränkungen:

- Alle zulässigen Medien werden aufgenommen, auch wenn Pixelmaße/Dauer kein zweites Foto teilen:
  eine identische Datei kann in einem verbundenen Ordner liegen.
- Mehrteilige Medien werden über sämtliche Ressourcen verglichen, mit Rolle, Länge und SHA-256.
  Reihenfolge und Dateinamen sind unerheblich; ein abweichendes Live-Video, RAW/JPEG oder eine Bearbeitung
  verhindert eine falsche Duplikatgruppe. Einzelressourcen bleiben mit gewöhnlichen Dateien vergleichbar.
- **„iCloud-Originale einbeziehen“** ist ausdrücklich aktivierbar und standardmäßig aus. Erst wenn lokale
  Bytes fehlen, dürfen Originale bei nicht kostenpflichtiger/beschränkter WLAN-Verbindung geladen werden.
  Bei WLAN-Verlust wird die Anforderung abgebrochen. Es entstehen keine Klartext-Tempdateien und kein Upload.
- Unbekannte Größen und beide Prüfsummen werden zusammen gestreamt. Gemessene Inhalte bleiben gecacht;
  unlesbare/iCloud-Einträge werden bei „Erneut suchen“ sofort wieder versucht. Verbundene Ordner werden
  frisch ohne die frühere 20.000-Dateien-Grenze inventarisiert; unbekannte Dateigrößen werden tatsächlich gemessen.
  Auch teilweise nicht lesbare Ordner oder eine abgebrochene Inventur gelten nicht als vollständig geprüft.
- Einzelne Lesefehler und unvollständige/geänderte Streams stoppen den Rest nicht und gelten niemals als
  bestätigte Kopien. Der Puffer ist begrenzt; Warten bleibt abbrechbar und hat eine Stillstandsfrist.
  Fortschritt wird während der Arbeit aktualisiert und für die Oberfläche gedrosselt.
- Bei ungeprüften Inhalten oder nicht lesbaren Quellen zeigt die App **„Suche noch unvollständig“**;
  vorhandene Gruppen bleiben sichtbar. Es gibt keine abschließende grüne Entwarnung für ein Teilergebnis.
  Inzwischen in den Tresor gelegte Inhalte werden vor der Veröffentlichung erneut ausgefiltert.

Die Suche umfasst den erlaubten Bereich: freigegebene, nicht ausgenommene Medien und verbundene Ordner.
Fehlende iOS-Berechtigungen, nicht erreichbare iCloud-Originale und beschädigte Ressourcen können weiterhin
eine vollständige Prüfung verhindern; diese Lücken bleiben sichtbar. Kein automatisches Löschen.

| Prüfung dieses Nachtrags | Status | Beleg |
|---|---|---|
| Linux-Kern, Swift 6.4.1 | PASS | 394 Tests in 44 Suites; 13 neue Regressionen für vollständige Ressourcen, unvollständige Streams, Fehler, Abbruch, Fortschritt und unbekannte Dateigrößen |
| Texte / Generator / `--check` | PASS | 7 neue Texte in allen 16 Sprachen; 1568 verwendete Kennungen / 2555 Einträge |
| Swift-6-Syntax / Patchprüfung | PASS | Geänderte iOS-Dateien und Screenshot-Tests mit `swiftc -frontend -parse`; keine iOS-Typprüfung |
| iOS-Build / Unit-Tests | PASS | Nach Freigabe der öffentlichen Runner auf `4feaf77`: Build und 24 native Unit-Tests bestanden |
| PhotoKit, Duplikate / große Dateien / Speicher | PASS | Fachtest 50 in `38697133324`, 159 Medien / 5 Kopien, Exitcode 0; 12 unterschiedliche PNGs geprüft. Gesamtworkflow wegen des separaten Starttests FAIL; dessen spätere Korrektur ist oben belegt |
| Echte iCloud-Mediathek / 30.000 Originale | NOT RUN | Echtes iPhone mit iCloud und entsprechender Mediathek nötig |

Screenshot-Regression ergänzt um `09a_duplicates_all_resources_and_cloud_option` und den echten Abschluss
der Suche. Die ursprüngliche Blockade `38689505928` durch GitHub-Abrechnung wurde durch die wieder öffentliche
Repository-Sichtbarkeit aufgehoben; nachträglicher echter PhotoKit-Nachweis siehe Tabelle. Build 8 enthält
auch diesen Nachtrag noch nicht; seit Build 9 ist er in TestFlight enthalten (siehe oben). E1–E19 unverändert.

## Tresor: Löschen per Wischen und Auswahl (15.10.2026, nach Build 8)

Auf Nutzermeldung ergänzt: **Auswählen** ist auf Medien, Notizen und Dateien direkt oben sichtbar.
Notizen erhalten einen Mehrfach-Auswahlmodus; vorhandene Datei-/Medienauswahl ist leichter erreichbar.
Fotos und Videos im Raster fragen nach einem Wischen nach links nach dem Verschieben in den
Tresor-Papierkorb. Notizen und Dateien bieten native Wischaktionen. Wischen, Kontextmenü und
Auswahl verwenden dieselbe Bestätigung mit festgehaltenen IDs. Abbrechen erhält die Auswahl.
Verschlüsselung, Wiederherstellung, Anhangsschutz und endgültiges Löschen im Tresor-Papierkorb
verwenden die vorhandenen Speicherfunktionen; externe Originale werden dabei nicht gelöscht.
Im Medienbetrachter wird nach dem Löschen das nächste vorhandene Medium statt einer leeren Seite gezeigt.

`VaultDeletionTests` prüft Foto-/Video-Import, beide Löschwege, Abbrechen, ungewählte Inhalte,
Wiederherstellung und das Weiterblättern nach dem Löschen. Notizen werden über den Editor erzeugt,
Dateien über den System-Dateiauswahldialog importiert. Eine Systemlöschung von Fotos wird ausschließlich
abgebrochen. Jeder Schritt speichert einen Screenshot. Gezielt startbar mit
`ci.yml`: `ui_tests=true`, `ui_phase=fixtures`, `qa_case=vault`.

| Prüfung dieses Nachtrags | Status | Beleg |
|---|---|---|
| Linux-Kern, Swift 6.4.1 | PASS | Anfangs 381 Tests in 43 Suites; aktueller Abschluss `38708113112`: 394 Tests in 44 Suites, keine Fehler |
| Swift-6-Syntax der geänderten Ansichten und UI-Tests | PASS | `swiftc -frontend -parse -swift-version 6`; keine iOS-Typprüfung |
| Sprachen / Generator / Workflow-YAML / Shell-Syntax | PASS | 16 Sprachen, 1563 benutzte Kennungen / 2548 Einträge; vorhandene Texte wiederverwendet |
| iOS-Build / Unit-Tests | PASS | `89f3552`: Build und 24 native Unit-Tests bestanden; Repository wieder öffentlich |
| Alle fünf Tresor-UI-Testfälle nach Wiederholungen | PASS | `38702267912`: Notizen, Dateien und beide Betrachterfälle bestanden. `38708113112` auf `89f3552`: Medien-Wischen/Auswahl und beide Betrachterfälle 3 PASS / 0 FAIL / 0 SKIP; alle 68 PNGs geprüft |

Implementierung: `ff6add0`, anschließend Ergänzung der Betrachter-Regression und dieses Prüfstatus.
Build 8 enthält diesen nachträglichen Fix noch nicht; seit Build 9 ist er in TestFlight enthalten (siehe oben).
Die nachfolgenden PASS-Belege betreffen den davor geprüften Build-8-Stand.

## TestFlight-Build 8 auf ausdrückliche Anweisung (15.10.2026)

Nach Abschluss der Simulatorprüfung hat der Inhaber den TestFlight-Build ausdrücklich beauftragt.
[TestFlight-Lauf `38682125439`](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38682125439)
auf Commit `613810f` ist vollständig **PASS**: Signing-Preflight, 24 iOS-Unit-Tests
(13 XCTest + 11 Swift Testing, keine Fehler), Release-Archiv, Export, Upload und Schlüsselbereinigung.
**Version 1.0, Build 8** wurde um 04:47 UTC hochgeladen; Apple-Verarbeitung und Testhinweise
sind um 04:50 UTC bestätigt. Keine externe Verteilung, kein Merge und kein Push auf `main`.

Commit `613810f` gleicht die vorgeschalteten Simulator-Tests an die bereits geprüfte lokale
Ad-hoc-Signierung an; damit funktioniert auch der echte Keychain-Rundlauf. App-Code und
Distributionssignierung bleiben auf dem simulatorgeprüften Stand. Das Artefakt `testflight-report`
enthält `gym.log`, `unit-tests.log` und den Fastlane-Bericht. Der generische CI-Bericht bezeichnet
den Archivlauf als `UNBEKANNT` (0 Fehler, 2 Warnungen); tatsächlicher Archivabschluss,
Upload und Apple-Verarbeitung sind durch die erfolgreichen Workflow-/Fastlane-Schritte belegt.
Die unten genannten offenen Geräteprüfungen bleiben für diesen internen Testbuild bestehen.

## Simulator-Prüfung über GitHub Actions (14.–15.10.2026, Build-7-Stand)

Freigabe des Inhabers: `ci.yml` auf `claude/fixes-analysis-library-vault-20261014`.
Keine Änderung an E1–E19; kein TestFlight, Release, Merge oder Push auf `main`.
**Alle im Simulator prüfbaren Punkte sind durch erfolgreiche Prüfungen belegt. Reale Geräteprüfungen bleiben offen.**

Prüfaufbau: getrennt zurückgesetzte iPhone-17-Simulatoren (iOS 26.5 und 26.2, macOS 26.6.2).
QA startet mit `-qa-fixtures`, ohne Werbung. PhotoKit startet ohne QA-Argumente und importiert mit
`simctl addmedia` 130 öffentliche Fotos, 5 exakte Kopien, 10 unscharfe Ableitungen, 5 Screenshot-PNGs und
3 Videos. Vollständiger Lauf und Fotos-Filtertest ergänzen ein natives iOS-Bildschirmfoto über das Simulator-Menü.
Herkunft, Autor, Dateigröße und SHA-256 stehen im Manifest; 153 Importe und genau 5 zusätzliche identische
Dateien auch für `38667553754` nachgeprüft. Fotozugriff vorab mit `simctl privacy`;
zusätzliche native Dialoge werden ausdrücklich über erlaubte Beschriftungen/Interruption-Monitor behandelt.
Keine Systemlöschung wird bestätigt. Google ausschließlich mit öffentlichen Test-IDs, Kauf ausschließlich
mit `PhotoMaid.storekit`, Tresor mit PIN. Jeder Prüfschritt erhält ein PNG; zusätzliche Accessibility-Bäume
entfallen nur bei zeitkritischen Gesten. Die echte 1,5-s-Sperre wird zusätzlich anhand der App-Zeitstempel geprüft.

### Belegte Ergebnisse und Wiederholungen

| Prüfbereich | Status | Lauf und Screenshot-Namen |
|---|---|---|
| Linux-Kern, Swift 6.4.1 | PASS | 381 Tests; auch auf `90e61d9` in `38672118816`, `38672122249` und `38672555604` |
| Sprachkatalog | PASS | Generator + `--check`, 1563 verwendete Kennungen / 2548 Einträge / 16 Sprachen |
| iOS-Build / Unit-Tests | PASS | 24 Tests (13 XCTest + 11 Swift Testing), zuletzt auch im grünen QA-Lauf `38672555604` auf `90e61d9`; echte Keychain-Prüfung und Beobachtungsregression der Duplikatsuche eingeschlossen |
| QA-Oberflächen | PASS | Abschließende Regression `38672555604` auf `90e61d9`: 8 PASS, 0 FAIL, 0 SKIP; alle 35 unterschiedlichen PNGs geprüft. `03_home`, `04_review_photo`, `06_later_pill`, `15_pro`, `18_dark_home`. Frühere Wiederholungen ebenfalls 8 PASS |
| Einführung / Freigaben / Kaltstarts | PASS | `38667553754` (Code `6a4de43`, gesamter Startlauf grün): Einführung, Fotos, ATT, Heute; Starts 1–3 ohne, Start 4 mit Google-Testanzeige; alle 13 unterschiedlichen PNGs geprüft. Auch `38669225732` besteht den Starttest auf iOS 26.5; `real_cold_start_1` bis `_4`, `real_test_ad_closed` |
| Feed-Richtungen / Rückgängig | PASS | `38672122249` auf `90e61d9`: gesamter Fachtest 20 mit Exitcode 0; alle 121 unterschiedlichen PNGs geprüft. Wiederholung `38672118816` auf iOS 26.5 ebenfalls PASS mit Exitcode 0; alle 120 PNGs geprüft. `real_up_keep`, `real_right_later`, `real_down_previous`, `real_undo`, `real_history_no_ad_decision`. Pille „In 2 Tagen wieder · Ändern“ sichtbar. Abschließend 104 Rohereignisse, einschließlich eigenem Termin und Undo; Später/Termin werden in der sichtbaren Liste zusammengefasst (103 Zeilen) |
| 50/100 Wische / Werbekarte / Verlauf | PASS | Ebenfalls `38672122249`: 100 korrekte Fortschritte, Verlauf exakt 50/100, Runter nach 0,565 s während der Sperre; seitlich nach 0,582 s blockiert, nach 1,573 s freigegeben. Automatischer Log-Prüfer PASS, Fachtest-Exitcode 0; Wiederholung `38672118816` ebenfalls PASS, Freigabe nach 1,601 s. `real_ad_down_immediate`, `real_ad_early_swipe_blocked`, `real_ad_after_1_5s_dismissed_no_decision`, `real_history_exactly_100_no_ad` |
| Wischhilfe / eigene Belegung | PASS | `38659670047`, Fachtest 30: Hilfe bei 3 s sichtbar, bei 7 s weg; tatsächliche Log-Laufzeiten 6,658 s / 6,501 s; `real_hints_still_after_3s`, `real_right_adds_to_album`, `real_buttons_always` |
| Papierkorb / Bonus 200 | PASS | `38664902732`, Fachtest 98: 154 ausgewählte Medien, Limit-Blatt mit Video/Pro, Google-Testvideo → 200; eigene Bestätigung außerhalb sicher geschlossen, keine Systemlöschung. Alle 19 unterschiedlichen PNGs geprüft. `real_trash_count_sizes`, `real_limit_100`, `real_bonus_test_video`, `real_delete_confirmation_cancelled_outside`, `real_limit_200_no_deletion` |
| Pro-Texte | PASS | `15_pro` aus der aktuellen QA-Regression und `real_pro_free_benefits` aus dem echten StoreKit-Lauf: Zahl 100, alle drei E19-Vorteile, Kostenlos-Hinweis, keine Platzhalter |
| StoreKit-Kauf / Pro ohne Werbung | PASS | `38661843821`, Fachtest 90 auf iOS 26.2: echter Kauf aus `PhotoMaid.storekit`, „Pro ist aktiv“, Transaktion vorhanden; Kaltstart und 50 Feed-Entscheidungen ohne Werbung, Pro-Ordner ohne Video. `real_pro_active`, `real_pro_cold_start_without_ad`, `real_pro_rapid_50`, `real_vault_folder_created_Pro-Test`. Alle 71 unterschiedlichen PNGs geprüft |
| Tresor PIN / Schließen / Ordner | PASS | `38661843821`, Fachtest 80: PIN, korrigierter E19-Einführungstext, Gratis-Ordner nach Google-Testvideo, ✕ links auf allen drei Reitern ohne Abfrage beim Schließen; alle 25 unterschiedlichen PNGs geprüft. `real_vault_folder_created_Gratis-Test`, `real_vault_closed_no_prompt_Medien` / `_Notizen` / `_Dateien` |
| Analyse-Warteschlange / Fortschritt / Raster / Durchwischen | PASS | `38655279492`, `test10AnalysisQueueProgressAndGrid`; `real_similar_queued`, `real_similar_prioritized`, `real_blurry_full_grid`, `real_blurry_swipe_feed` |
| Große Dateien / Duplikate / Speicher | PASS | `38665396878`: beobachtbare Suche mit sichtbarem Fortschritt, genau 5 Kopien, große Dateien vollständig gemessen, Speicherzahlen und Balken; alle 15 PNGs geprüft. `real_duplicates_progress`, `real_duplicates_five_selected_copies`, `real_large_finished_below_threshold`, `real_storage_loaded_numbers_and_progress` |
| Fotos-Filter / Sortierung / Ansicht | PASS | `38662832942`, Fachtest 60: alle fünf Filter, echtes natives Screenshot-Asset sichtbar, „Zuletzt hinzugefügt“, quadratisch/Seitenverhältnis; alle 19 PNGs geprüft. `real_library_Screenshots`, `real_view_Quadratisch`, `real_view_Seitenverhältnis` |
| Studio ohne Pro | PASS | Auch `38655279492`: Collage, Werkzeuge/Größe ändern und geladener Fotoeditor ohne Pro-Sperre oder Krone; `real_collage_editor`, `real_tools_free`, `real_studio_photo_editor_free` |
| Englisch / Arabisch / RTL | PASS | `38655279492`, Fachtest 95: 18 PNGs geprüft; `real_en_today`, `real_en_feed_arrows`, `real_en_pro_text`, entsprechend `ar`; keine Platzhalter, physische Pfeilrichtungen unverändert |
| iCloud / 30 000 Fotos / Wärme / Kamera / echtes Face ID | NOT RUN | Benötigt echtes iPhone / entsprechende Mediathek; kein Simulator-Nachweis |

### Korrekturen und Belege

- Feed-Bühne in kleinere SwiftUI-Builder zerlegt: Xcode-Typprüfung schlug mit dem großen Ausdruck fehl.
  Keine Änderung an Gesten oder Ledger. Sichtbar ziffernweise umgebrochene Serien-/Papierkorb-Zähler bleiben
  jetzt einzeilig; bei Platzmangel separate Zählerzeile. Einstellungen zeigen den vorhandenen Titel „PhotoMaid Pro“.
- Googles Entwickler-Validator meldete „No implementation issues found“, überlagerte aber die native Testkarte.
  Offizieller Schalter `GADNativeAdValidatorEnabled=false`; Testanzeigen und Werberegeln bleiben aktiv.
- Stabile Accessibility-Kennungen, aktuelle Einführungs-/Buttontexte, sichere Dialogsteuerung und atomare
  Snapshot-/Prädikatabfragen ersetzen veraltete/instabile Testselektoren. Fehlende Testmedien führen zu FAIL,
  nicht zu einem verdeckenden Skip. Eigene Entfernungsbestätigungen werden sicher verworfen.
- Duplikat-Suche: `isRunning` las nur eine mit `@ObservationIgnored` ausgeblendete Task. SwiftUI abonnierte damit den Start nicht; die Suchseite konnte bis zum Ergebnis ohne Fortschrittsanzeige bleiben. Laufzustand jetzt aus der beobachtbaren Phase, Regression über `withObservationTracking`, UI-Prüfung vor dem Größen-Cache.
- Veralteter Tresor-Einführungstext „Gratis: bis zu 50 Medien“ durch die bestehende E19-Ordnerregel in allen 16 Sprachen ersetzt; Schutz und Modell unverändert.
- Simulator lokal ad hoc signiert (`CODE_SIGN_IDENTITY=-`), ohne Zertifikat/Profil. Test-Bundles erzeugen ihre
  Info.plist. Keychain-Schutz unverändert; Diagnose protokolliert nur Fehlerdomäne/-code, keine Tresorinhalte.
- Workflow erkennt auch `TEST EXECUTE SUCCEEDED`, prüft sämtliche Fehler-/Exitmarker und liefert QA, Start und
  jeden Fachtest als eigenes frühes Artefakt. Bis zu 120 Minuten; getrennte Wiederholung mit `ui_phase`.
  Große Alt-Artefakte lassen sich mit `collect_run` verlustfrei in herunterladbare Teile aufteilen.
- Visuell geprüft: Ausgang `38633721469` (2 unterschiedliche PNGs + Video-Endbilder), `38638077269` (31),
  `38642182043` (25), `38646080655` (33), `38646580594` (191), `38649479126` (6),
  `38650310717` (35 QA + 12 Start, darunter identische Heute-Bilder), `38655279492` Start (14) und Analyse (16). Original-`.xcresult`, Logs und PNGs
  heruntergeladen; Zuordnung über Screenshot-Namen und SHA-256. Artefakt-Sammler-Erfolg gilt nie als App-PASS.
- Abschließender Stand: Code `90e61d9`; [QA 38672555604](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38672555604)
  vollständig grün, [Feed 38672122249](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38672122249)
  und [Feed 38672118816](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38672118816)
  jeweils als vollständiger Fachtest einschließlich Timing grün. Ihre Gesamtworkflows bleiben wegen der
  separat fehlgeschlagenen Startanzeigen-Tests rot (`app-open-load-window-expired`); erfolgreiche Startbelege stehen in der Tabelle.
  Die Tabelle kombiniert gezielte Fachbelege und ist keine Behauptung eines komplett grünen Gesamtdurchlaufs.


### Grenzen und offene Geräteprüfungen

- Die Tabelle führt Fachbelege aus dem vollständigen Ausgangslauf und den gezielten Wiederholungen zusammen.
  Im Ausgangslauf traten Fehler auf. Bei späteren Workflows kann ein Fachtest PASS sein und die separate
  strenge Startprüfung desselben Workflows wegen Googles Ladezeit fehlschlagen; ihr Gesamtstatus bleibt FAIL.
- App-Start-Anzeige: Start 4 wurde tatsächlich mit Google-Testanzeige belegt. Wiederholungen melden teilweise
  `app-open-load-window-expired`: Googles Testanzeige war innerhalb der vorgeschriebenen 4 s nicht geladen.
  Das Fenster und die übrigen E19-Regeln wurden dafür nicht verlängert. Diese externe Abhängigkeit bleibt
  ein Grund für nicht deterministische CI-Startprüfungen.
- Native Testanzeigen können ebenfalls am SDK-Netzwerk scheitern: `38666633929` und `38669048955` melden
  `native-load-failed com.google.admob:2`, im ersten Lauf mit `NSURLErrorDomain -1005`. Diese Läufe bleiben
  FAIL. Der spätere echte Nachweis beider Karten und ihrer Zeitgrenze steht gesondert in der Tabelle.
- Lokales StoreKit unter iOS 26.5 scheitert beim CLI-Start an `SKInternalErrorDomain Code=3` (von Apple DTS
  bestätigtes Runtime-Problem, [Bericht](https://developer.apple.com/forums/thread/826971)). Der echte lokale
  Kauf ist mit der bereits installierten Runtime 26.2 bestanden. Deshalb ist 26.2 nun CI-Vorgabe; neuestes
  stabiles Xcode/SDK und die bewusst wählbare neueste Runtime bleiben erhalten.
- iCloud-Originale, eine Mediathek mit 30 000 Fotos, Wärmeverhalten, Kamera und echtes Face ID bleiben
  **NOT RUN**: dafür sind ein echtes iPhone und die entsprechende Mediathek erforderlich.
- Keine echte Löschung und kein TestFlight-Upload durchgeführt. Der Inhaber startet TestFlight selbst.

### Commits dieses Prüfauftrags

Auf dem freigegebenen Branch, nach dem vorhandenen Inhaber-Commit `e8e627e`, zusätzlich zum abschließenden
Dokumentationscommit:

```text
89ca58f Simulatorprüfung mit echter Mediathek ergänzen
31631cc CI-Belege je Commit erhalten
a88d9c9 Ältere Simulatorbelege exportierbar machen
72e20fe Feed-Bühne für Swift-Typprüfung aufteilen
afd3585 CI-Erfolg erkennen und Werbetakt vollständig prüfen
b526e85 UI-Belege früher liefern und Startanzeigen abfangen
58cc1f6 Große Simulatorbelege prüfbar aufteilen
07ead15 Einwilligung sicher bedienen und Pro-Eintrag benennen
70da755 Simulator-Durchläufe gezielt wiederholbar machen
c06cf3b PhotoKit-Startbelege vor den Fachtests bereitstellen
edc58cd Frühe Teilbelege einzeln auswertbar machen
ff65409 Startprüfung isolieren und Ladeende ausdrücklich prüfen
05f5937 Systemdialoge nur nach ihrer Anforderung abfragen
9e6d257 Fachtests einzeln mit sofortigen Belegen ausführen
c28b383 QA-Feed und Duplikatsuche korrekt ansteuern
72dbac0 Leere Werbeabfragen sparen und Startdiagnose behalten
32c8d56 Simulatorzugriff und Dialoge absichern, Zähler lesbar halten
95151f6 Parallele UI-Phasen getrennt laufen lassen
a0531e5 Test-Bundles mit generierter Info-Plist signieren
24c8081 Audit-Verlauf korrekt prüfen und Fachtests gezielt wiederholen
2182b3e Native Screenshot-Aufnahme im Simulator untersuchen
2cd26b8 Screenshot-Diagnose über registrierten CI-Workflow aufrufen
dc8c501 Wisch- und Hilfezeiten ohne langsame Vorabfragen messen
a7a589a Duplikatauswahl sichtbar prüfen und Screenshot-Gerät festlegen
2b33c2c Tresorhinweis an E19 anpassen und Anzeigenzustände belegen
9c60ca3 StoreKit-Prüfung auf funktionierende iOS-Runtime umstellen
f58724e Native Bildschirmfotos und volle Papierkorbauswahl prüfen
081b53d Gesperrte Werbekarte vor der Screenshot-Pause schließen
90b2f4e Laufende Duplikatsuche für SwiftUI beobachtbar machen
56b7455 Entfernungsdialog im Test sicher außerhalb schließen
922807b Simulator-Aufnahme isolieren und Einwilligung robust bedienen
9f04ca6 Wischzeiten präzise und Später-Journal vollständig prüfen
6a4de43 Einwilligung einmal bedienen und StoreKit-Runtime vorgeben
90e61d9 Später-Prüfung auf sichtbare Bestätigung synchronisieren
```

## Neues Pro-Modell E19 + Werbung (14.10.2026, gleicher Branch)

Nutzerentscheidung (14.10.2026; Rückfragen: Tresor nur Ordner, Feed-Werbekarte wie Android, iOS-Tracking-Abfrage ja):

- **Pro-Bildschirm:** „Tageslimit von %1$lld“ – die Zahl wurde nicht eingesetzt. Jetzt mit Zahl; Inhalt neu: ohne Werbung,
  ohne Tageslimit (100), Tresor-Ordner ohne Werbung; Hinweis „alles andere ist für alle kostenlos“. „Pro ist aktiv“ nur
  noch bei gekauftem Pro (`isLifetimePro`), nicht mehr über `hasProToolsAccess`.
- **Kern (`Capabilities`, `AdRules`, `FeedAdPolicy`):** alle Werkzeuge frei; Free 100 Entfernungen/Tag, +100 einmal
  täglich nach Belohnungs-Callback (`LimitBonus`, `LimitBonusOffer`); Werbekarte nach jeder 50. Entscheidung (ohne
  Schonfrist/Tagesgrenze/Mindestabstand); App-Start-Werbung ab dem 4. Kaltstart (`AppOpenAdPolicy`); Tresor-Ordner
  (`VaultFolderAccess`: Pro frei, sonst Video; ohne eingerichtete Werbung nichts gesperrt). Kein Pro-Test mehr.
- **App:** Google Mobile Ads 13.9.0 + UMP 3.1.0 (SPM, feste Versionen), `AdsService`: UMP-Einwilligung → ATT-Abfrage →
  SDK-Start (nach der Einführung, nur Free); App-Start-Werbung (höchstens 4 s Ladezeit, nur in den ersten 15 s, nie über
  Tresor/Feed/Vollbild); Belohnungsvideo (vorab geladen) für „+100 heute“ (Papierkorb: Limit-Blatt und Kopfzeile) und
  Tresor-Ordner (verdientes Video verfällt nicht bei Abbruch; Tresor-Sitzung läuft während des Videos weiter); native
  Werbekarte im Feed (`FeedAdCard`, Googles `NativeAdView`, Medien eingepasst; nie Entscheidung; 1,5 s, dann wegwischen
  oder „Weiter“; „runter“/Rückgängig sofort; „Ohne Werbung mit Pro“). Einstellungen/Datenschutz: „Werbe-Einwilligung
  ändern“ (wenn von Google verlangt), Hinweis zur Werbung. QA-Testdaten: keine Werbung.
- **Konfiguration:** `GADApplicationIdentifier`, `PMAdMob*`-Schlüssel, `SKAdNetworkItems`, `NSUserTrackingUsageDescription`
  (16 Sprachen); Standard = Googles öffentliche Test-IDs, CI/fastlane übernehmen `PM_ADMOB_*` aus Secrets/Variablen.
  Privacy Manifest: `NSPrivacyTracking = true` (Google bringt ein eigenes Manifest mit).
- 12 neue Texte + 1 Info.plist-Text in 16 Sprachen; `privacy_ads` ohne „AdMob“ (Prüfskript).

| Prüfung | Ergebnis |
|---|---|
| `swift test` (Linux) | PASS: 381 Tests (Capabilities/Werbung/Tresor-Ordner/Bonus neu bzw. angepasst) |
| Typprüfung `AdsService`, `VaultFolderGate`, `NativeAdLayout` gegen Platzhalter mit den Swift-Namen aus den Headern von GMA 13.9.0/UMP 3.1.0 | PASS (Platzhalter, nicht das echte SDK) |
| `android_strings_to_xcstrings.py --check` | PASS: 1563 benutzte Kennungen, 2548 Einträge, 16 Sprachen |
| Xcode-Build mit echtem SDK, SwiftUI-Teile (`FeedAdCard`, Tresor, Papierkorb, Pro) | NOT RUN (nur über GitHub Actions auf Anweisung) |
| Gerät: Einwilligung/ATT, App-Start-Werbung ab 4. Start, Karte nach 50 Wischen, +100, Tresor-Ordner | NOT RUN |
| Echte AdMob-IDs, App-Store-Datenschutzangaben, Datenschutzerklärung | BLOCKED (Inhaber, `docs/RELEASE_BLOCKERS.md` #5) |

## Fixes nach Build 6 (14.10.2026, gleicher Branch)

Auf Nutzermeldung (Bildschirmaufnahmen Build 6: „Analyse blockt weiterhin“, „Gestenhilfe verschwindet sofort“):

- **Ursache Analyse:** Jede Meldung von Fotos (bei 30k Medien laufend: iCloud-Abgleich, eigene Analyse von Fotos,
  geladene Vorschauen) erhöhte `changeToken` → die App las alle Medien neu → `AnalysisController` setzte die Analyse
  zurück (anhalten, Ergebnisse leeren, alle Arten neu abgleichen, neu vorbereiten). Ergebnis in der Aufnahme: ~1 Foto je
  Zyklus („10'570 → 10'571 → 10'572“), „Fotos und Videos werden geladen …“, leere Trefferliste, grauer Start-Knopf.
- **Mediathek-Änderungen:** `LibraryChangeTracker` wertet `PHChange.changeDetails` gegen die Abfrage aller Medien aus
  (`LibraryChangeSummary`, Kern): nur bei neuen/entfernten Medien (oder ohne Einzelheiten, oder Album-Änderung bei
  ausgeblendeten/ausgenommenen Alben) wird neu gelesen – im Hintergrund, ohne laufendes Neuladen abzubrechen; sonst
  werden nur die geänderten Medien neu beschrieben (`patchAssets`). Meldungen werden zusammengefasst (`ChangeCoalescer`:
  0,8 s Ruhe, spätestens 3 s). Neues `AppModel.mediaRevision` nur bei Bestandsänderungen.
- **Analyse:** reagiert nur noch auf `mediaRevision`, Zugriff und „Analyse an/aus“ – Umfang wird angepasst, der Lauf
  läuft weiter. Ein gelöschtes/geändertes Foto hält den Lauf nicht mehr an (übersprungen, nächstes Mal neu).
  Öffnen einer anderen Analyse hält die laufende nicht mehr an: Warteschlange (`AnalysisPlan`, Kern) mit „Danach
  analysieren“, „Jetzt zuerst“ (die bisherige wartet danach vorne weiter) und „Nicht mehr warten“; fertig → nächste.
  Vorbereiten liest nur noch die eigene Analyse einmal (statt 6× alle), Anzeige über `states()` ohne JSON.
  „Nur in iCloud“ wird zwischen Analysen geteilt (`AnalysisAvailability`): Ähnliche/Motive nutzen jetzt 512 px wie
  „Unscharf“ (Vision rechnet intern kleiner; liegt bei „Speicher optimieren“ öfter lokal) und überspringen bekannte
  iCloud-Fotos sofort; bisherige Ergebnisse dieser zwei Analysen werden einmal neu berechnet (neues Verfahren).
  iCloud-Schalter auch während des Laufs. Zähler-Meldungen höchstens alle 0,25 s. Gruppen ähnlicher Aufnahmen werden
  nur noch zurückgesetzt, wenn ein entferntes Foto zu einer Gruppe gehörte. Unterbrochene Analyse läuft nach dem
  App-Start weiter, ohne die Ansicht zu öffnen; nach Speicherwarnung nach 15 s. 6 Texte, 16 Sprachen.
- **Gestenhilfe:** Der Zeitgeber nutzte `try? await Task.sleep` – jeder Abbruch der Aufgabe blendete sofort aus. Jetzt
  blendet nur die abgelaufene Zeit (6 s), Antippen oder ein echter Wisch (> 24 pt) aus, beides frühestens nach 1 s.
- **Tresor:** ✕ zum Schließen auch auf „Notizen“ und „Dateien“ (gemeinsames `VaultCloseToolbarItem`, sperrt sofort).
- **Feed stockt bei schnellem Wischen (iCloud):** (1) Jeder Wisch wartete auf das komplette neue Lesemodell
  (`publishRead`: Projektion + Warteschlange über alle Medien, danach Neuzeichnen aller beobachtenden Ansichten); bis
  dahin galt `isCommitting` und der nächste Wisch sprang zurück – bei „Später“ sogar zweimal. Jetzt: gespeichert wird
  sofort, das Lesemodell nach 0,6 s Ruhe einmal für alle schnellen Wische (`schedulePublishRead`, spätestens 2,5 s;
  beim Schließen des Feeds sofort). (2) Aus iCloud geladene Bilder wurden beim Zeichnen auf dem Hauptthread dekodiert
  (während der Animation) → jetzt `byPreparingForDisplay()` vorab. (3) PhotoKit-Abfragen der Vorschau und das
  Vorhalten der Nachbarn liefen auf dem Hauptthread → jetzt im Hintergrund (seriell). (4) iCloud-Fortschritt nur in
  5-%-Schritten. (5) Solange der Feed offen ist, treten Analyse, Größen-Messen und Duplikat-Suche zurück
  (`ForegroundActivity`: halbe Parallelität + Pause, wie bei warmem iPhone).

| Prüfung | Ergebnis |
|---|---|
| `swift build` / `swift test` (Linux, Swift 6.4) | PASS: 378 Tests (10 neu: Warteschlange, iCloud-Wissen, Änderungsauswertung, Zusammenfassen) |
| Typprüfung gegen Platzhalter (Swift 6 strikt): `AnalysisController`, `AnalysisRunner`, `AnalysisDatabase`, `LibraryChangeTracker` + Änderungsweg `PhotoLibraryService`/`AppModel` (Auszug) | PASS (nur Linux-Platzhalter, kein Apple-SDK) |
| `swiftc -parse` geänderter App-Dateien | PASS |
| `android_strings_to_xcstrings.py --check` | PASS: 1549 benutzte Kennungen, 2536 Einträge, 16 Sprachen |
| App-Target bauen (`xcodebuild`), SwiftUI-Dateien typgeprüft | NOT RUN: kein macOS/Xcode (nur über GitHub Actions auf Anweisung) |
| Typprüfung gegen Platzhalter: `PreviewPipeline`, `ForegroundActivity`, aufgeschobenes `publishRead` | PASS (nur Linux-Platzhalter) |
| Gerät: Analyse-Tempo bei 30k Medien/iCloud, Häufigkeit der Fotos-Meldungen, Gestenhilfe 6 s, flüssiges Wischen mit iCloud-Fotos, ✕ im Tresor | NOT RUN |

## Fixes nach Build 5 (14.10.2026, Branch `claude/fixes-analysis-library-vault-20261014`)

Auf Nutzermeldung (Screenshots Build 5) – alles ohne neue Netzwerk-, Konto- oder Löschwege:

- **Tresor:** Schließen löste Face ID aus. Ursache: `lock()` setzte erst „gesperrt“, die Vollbild-Ebene zeigte während
  des Ausblendens kurz den Sperrbildschirm, dessen `.task` Face ID startete (Bestätigen entsperrte unsichtbar). Jetzt:
  beim Schließen nur Abdeckung, Face ID startet nur bei sichtbarem Tresor und aktiver App, Entsperren bei geschlossenem
  Tresor wird abgelehnt. Regel „sperrt sofort beim Verlassen“ unverändert.
- **Analyse-Ergebnisse:** Raster war unsichtbar nach Monaten gruppiert (Reihen mit 1/2/3 Bildern) → ein durchgehendes
  Raster (`AnalysisResultPage`), Reihenfolge der Analyse. Nur noch offene Fotos (Schalter „Auch entschiedene zeigen“).
  „Durchwischen (n)“ öffnet alle Treffer im normalen Feed (Gesten, Ledger); Tipp auf ein Foto startet dort.
  Ähnliche Aufnahmen als Gruppen mit „Vergleichen“ (`SeriesCompareView`, nie „bestes Foto“). Gilt für alle vier Analysen.
- **Analyse-Ablauf:** Wärme drosselt statt abzubrechen (`ThrottledWork`/`WorkThrottle`: warm → warten und von selbst
  weiter, nur kritisch → anhalten); Fortsetzen nach Rückkehr in die App, nach dem Abkühlen und nach App-Neustart, außer
  der Nutzer hat selbst angehalten (`AnalysisAutoResume`). iCloud bis 3 Fotos gleichzeitig (WLAN). „iCloud einbeziehen“
  bleibt gespeichert. Neue Option „Weiterlaufen, wenn ich die App verlasse“ (Standard aus, Nutzerwunsch 14.10.2026):
  `BGContinuedProcessingTask` mit iOS-Fortschritt; endet die Aufgabe, geht es beim nächsten Öffnen weiter. Bildschirm
  bleibt an, solange die Analyse sichtbar läuft.
- **Große Dateien:** „Größe unbekannt (31'951)“ zählte noch nicht Gemessenes mit. Jetzt getrennt: gemessen / wird noch
  gemessen / nur in iCloud / nicht lesbar (`SizeInventory`, `MeasureState`). Größen in SQLite (`SizeIndexDatabase`)
  statt eines JSON-Blocks, der bei jeder Messung komplett neu geschrieben wurde; „nur in iCloud“ wird gespeichert und
  erst nach 12 h erneut geprüft. App-weiter Mess-Auftrag (`SizeMeasuring`): Videos zuerst (Dateigröße ohne Lesen),
  bis 4 parallel, PhotoKit-Abfragen in Paketen, läuft weiter beim Verlassen der Seite. Abschnitt „Videos nur in iCloud –
  längste zuerst“ (keine Größe, nichts geschätzt). iOS nennt die Größe von iCloud-Originalen ohne Download nicht
  öffentlich; private API bleibt verboten.
- **Duplikate:** hing bei „0 / 1“, weil vorher ALLE Größen gemessen wurden (ohne Fortschritt). Jetzt: Vorfilter
  (gleiche Art + Pixelmaße + Dauer, `DuplicatePrefilter`), nur vergleichbare Assets messen, Fortschritt je Phase,
  Prüfsummen gespeichert (`DuplicateHashCache`) – zweiter Lauf liest kaum noch; Suchlauf läuft weiter beim Verlassen.
- **Fotos-Tab:** Filter wie in der Fotos-App (Alle · Favoriten · Bearbeitet · Fotos · Videos · Bildschirmfotos, Medienarten:
  Selfies, Live Photos, Porträts, Panoramen, Zeitlupe, Zeitraffer, Kinomodus, RAW) und Ansicht quadratisch/Seitenverhältnis
  (`LibraryFilter`, gespeichert). Aktiver Filter als Chip mit Anzahl und ✕; gilt für Betrachter, Auswahl, Diashow.
- 33 neue Texte in 16 Sprachen (`ios_strings.json`), `ana2_stage_thermal` angepasst.
- Nachtrag C: `AppModel.sizes` (Papierkorb, Sammlungen) misst über `SizeMeasuring.measureParallel` (gespeicherte Werte
  sofort, Rest parallel in Paketen, Wärme-Drosselung). „Speicher“ nutzt den app-weiten Mess-Auftrag (läuft beim
  Verlassen weiter, zeigt „mind.“, solange noch gemessen wird); ein zweiter Auftrag bricht den ersten nicht mehr ab.
- E17 (Nutzerentscheidung 14.10.2026): beim Löschen steht immer eine Zahl. `SizeEstimator` (Kern) kalibriert sich aus
  den gemessenen Medien dieser Mediathek (Median Bytes/Pixel bzw. Bytes/(Pixel·s), Dateien: Median je Typ; zu wenige
  Messungen → Richtwerte HEIC/HEVC). Papierkorb: Größe je Eintrag, „Auswahl: …“, Bestätigungsdialog, „Gespart“ und
  Gesamtsumme mit „ca.“, sobald ein Teil geschätzt ist (`SizeValue`, `SizeSum`, `CleanupSavings.display`,
  `savedTotalApproximate`). „Große Dateien“: Medien nur in iCloud/nicht lesbar mit „ca.“ und iCloud-Symbol in der Liste.
  „Dateien“: ohne lesbare Größe „ca.“; Dateigröße zusätzlich über `totalFileSize`. 7 Texte (davon 1 geändert).
- E18 (Nutzerentscheidung 14.10.2026): Einstellungen › Wischen & Tasten (`FeedControlsView`, Kern `FeedControls`).
  Jede Richtung frei belegbar (auch „In Album „…“ legen“ = hinzufügen + Behalten, ein Schritt, Rückgängig nimmt beides
  zurück), Tasten frei wählbar/sortierbar/platzierbar, anzeigen nur mit Bedienungshilfen oder immer. Feed: Geste →
  Belegung (`perform(action:direction:)`), Medium fliegt in die gewischte Richtung, Richtungs-Pille, Gestenhilfe,
  Tasten und Färbung zeigen die eigene Belegung; Album-Aktionen auch als VoiceOver-Aktionen. 24 Texte.
- Nachtrag B: Medienart „Bildschirmaufnahmen“ (`videoScreenRecording`) und Sortierung „Zuletzt hinzugefügt“
  (`LibraryOrder`, Reihenfolge des Systemalbums „Aufnahmen“/`smartAlbumUserLibrary`; ohne Datumsüberschriften). 2 Texte.

| Prüfung | Ergebnis |
|---|---|
| `swift build` / `swift test` (Linux, Swift 6.4) | PASS: 361 Tests (28 neu: Ergebnisse/Drosselung, Inventur/Vorfilter/Prüfsummen, Filter/Reihenfolge, Schätzung/„ca.“-Summen) |
| Typprüfung neuer Infrastruktur gegen Platzhalter (Swift 6 strikt: `MediaSizer`, `SizeMeasuring`, `SizeIndexDatabase`, `DuplicateScanner`, `AnalysisRunner`, `AnalysisController`, `AnalysisDatabase`) | PASS (nur Linux-Platzhalter für Photos/UIKit/BackgroundTasks, kein Apple-SDK) |
| `SizeIndexDatabase` mit echtem SQLite (Linux) | PASS |
| `swiftc -parse` aller 123 App-Dateien | PASS |
| `android_strings_to_xcstrings.py --check` | PASS: 1520 benutzte Kennungen, 2506 Einträge, 16 Sprachen |
| App-Target bauen (`xcodebuild`), SwiftUI-Dateien typgeprüft | NOT RUN: kein macOS/Xcode; kein GitHub-Actions-Lauf ohne Freigabe |
| Gerät: Geschwindigkeit bei 30k Medien, Wärme, Face ID beim Schließen, PhotoKit-Fehlercode „nur in iCloud“, Reihenfolge „Zuletzt hinzugefügt“, Plausibilität der „ca.“-Schätzung gegenüber der Fotos-App | NOT RUN |

## Build 5 (11.10.2026, Branch `claude/build5-all-20261011`)

Enthält alles: Release-Stand `24b41a0` (Build 4) + Tresor-Isolation + Retusche-Absturz-Fix + K5 + Tresor-Notizen/Dateien/
Papierkorb (`claude/vault-workspace-20261011`) + schrittweise iCloud-Analyse (PR #10, `2f9d4ec`) + Integration:

- Analyse an die Oberfläche angebunden (`SmartReviewView` auf `AnalysisController`: Fortschritt, Anhalten/Fortsetzen,
  Fehlgeschlagene erneut, iCloud nur auf Wunsch und nur im WLAN, Textsuche, Motiv-Filter, Seiten). 34 Texte, 16 Sprachen.
- Kompilierlücken aus PR #10 geschlossen: fehlender Hintergrunddienst (`AnalysisBackground`) entfernt – keine
  Hintergrundanalyse, beim Verlassen der App wird angehalten; `hits(…, offset:)` ergänzt.
- Verbergen-Liste: PR #10 machte die ganze App „fail-closed“ (bei vorhandenem Tresor ohne Liste wären alle Fotos
  verschwunden; die nötige Abdeckungsbestätigung wurde nie aufgerufen). Zurück auf die sichere Fassung; für die Analyse
  ergänzt: Speichern nur unter derselben Sperre wie das Verbergen (`withAnalysisAccess`), keine Analyse bei
  beschädigter Liste, beim Verbergen werden Analyse-Daten (Text, Merkmale, Gruppen) gelöscht, Änderungsmeldung.
- Prüfung: `swift test` 333 PASS (davon 20 Analyse-Kern), Strings `--check` OK, `swiftc -parse` OK.
  iOS-Build/Gerät: siehe TestFlight-Lauf.

## Umgebung

Windows-Arbeitsumgebung ohne Swift, SwiftC, Xcode, Simulator oder iPhone. Die iOS-App ist geschrieben, aber in
dieser Umgebung weder geparst noch typgeprüft oder ausgeführt. Frühere Linux-Ergebnisse gelten nur für den damaligen
Commit und werden für den aktuellen Stand nicht als erneuter PASS ausgegeben.

## Prüfstatus

| Prüfung | Ergebnis |
|---|---|
| `swift build` / `swift test` (aktueller Commit) | BLOCKED: `swift` ist lokal nicht installiert |
| `swiftc -parse` aller 96 Swift-Dateien | BLOCKED: `swiftc` ist lokal nicht installiert |
| `scripts/i18n/build_ios_strings.py` | PASS: 97 iOS-Texte + 4 InfoPlist-Texte |
| `scripts/android_strings_to_xcstrings.py --check` | PASS: 1008 benutzte Kennungen, 2092 Einträge, 16 Sprachen |
| App-Target bauen (`xcodebuild`) | NOT RUN: kein macOS/Xcode; kein GitHub-Actions-Lauf autorisiert |
| XCTest / XCUITest | NOT RUN |
| Simulator, Gerät, VoiceOver, Performance | NOT RUN |

## Fertig geschrieben (App)

Fundament (Texte, AppModel, 5 Tabs, Design-System, StoreKit 2, Diagnose) · Feed (Gesten, Aktionsleiste,
Favoritenschutz, Später-Pille, Zusammenfassung, Limit-Blatt) · Heute · Aufräumen · Papierkorb · Später · Verlauf ·
Monate · Serien · Duplikate · Große Dateien · Speicher · Dateien · Tab Fotos (Zeitachse, Betrachter, Alben,
Favoriten, Suche, Auswahl, Schlagwörter/Notizen, Auswahlkorb, Diashow) · Foto-Editor · Video-Editor ·
Export-Koordinator · Studio/Collage · Film/Diashow · Werkzeuge/Stapel/GIF · Abläufe · PDF aus Fotos · PDF-Studio ·
VisionKit-Scan · lokale Smart-Review-Analyse · verifiziertes Archiv · JSON-Sicherung/Wiederherstellung · Einstellungen ·
StoreKit-Pro-Seite · Datenschutz/Hilfe · ausgeschlossene Alben · Sammlungen · „Öffnen in“ · Onboarding.

## Noch nicht als produktionsreif verifiziert

Der Code für A1–A9 ist vorhanden und alle zuvor fehlenden View-Typen existieren. Ohne Apple-Compiler ist die
Produktionsreife jedoch **nicht belegt**. Insbesondere PDF-Annotation/Unterschrift/OCR-Textebene, echte HDR-/4K-Medien,
security-scoped File-Provider, StoreKit-Sandbox, Vision-Ergebnisse, Hintergrundexport und alle Geräte-/Accessibility-
Matrizen benötigen einen macOS-Build und reale Gerätetests. Bis dahin ist der App-Gesamtstatus `NOT RUN`, nicht PASS.

## Nachtrag 10.10.2026 (nach TestFlight-Build 2, für Build 3)

| Bereich | Stand | Prüfstatus |
|---|---|---|
| iCloud-Vorschau wie Fotos-App (lokal sofort, volle Qualität nachladen, „!“ unten rechts) | gebaut | NOT RUN (Gerät) |
| Einführung mit Bildern/Übungskarten, Rundgang auf echte Stellen | gebaut | NOT RUN |
| Pro: ehrlicher Zustand statt „Preis wird geladen“; TestFlight-Produkt-ID `com.mrdevn4ever.photomaid.pro` | gebaut | BLOCKED (IAP in App Store Connect anlegen) |
| Tab-Leiste fest, App-Sprache (iOS-Einstellungen), Entwürfe löschen, „Gespeichert“ vollständig | gebaut | NOT RUN |
| Rasterauswahl trifft die getippte Zelle, Teilen mehrerer Medien, neue Schnellzugriffe (Zufällig u. a.) | gebaut | Kern PASS, App NOT RUN |
| Collage neu (Layout-Vorschauen, Zuschnitt je Feld, Frei/Streifen, Text/Sticker, Speicherort) | gebaut | Kern PASS, App NOT RUN |
| Video zusammenfügen, Verkleinern/Werkzeuge, Auslagern verständlich | gebaut | NOT RUN |
| Privater Tresor (E16) | gebaut | Kern PASS (11 Tests), App NOT RUN, Geräteabnahme NOT RUN |
| Neues App-Icon | eingebaut | NOT RUN |
