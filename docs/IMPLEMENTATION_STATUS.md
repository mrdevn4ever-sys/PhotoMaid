# Implementierungsstatus

Stand: 14.10.2026 · Branch `claude/fixes-analysis-library-vault-20261014` · Build-7-Ausgangsstand, Simulator-Prüfung läuft.

## Simulator-Prüfung über GitHub Actions (14.10.2026, Build-7-Stand)

Freigabe des Inhabers: nur `ci.yml` und Simulator-Prüfungen auf
`claude/fixes-analysis-library-vault-20261014`. Keine Änderungen an E1–E19, kein TestFlight/Release/Merge.

- Ausgangslauf: [38633721469](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38633721469),
  Commit `269eaa6`, `ui_tests=true`: Build PASS; 22 iOS-Unit-Tests PASS (11 XCTest + 11 Swift Testing),
  8 UI-Tests FAIL. Belege heruntergeladen; alle 2 unterschiedlichen PNGs angesehen (3 Anhänge: `03_home`,
  `13_studio`, `14_history` – zeigen noch die Einführung). Die Videos zeigen zusätzlich: der blinde
  `app.tap()` nach dem Fotozugriff öffnet teilweise schon den Feed; dadurch sind die erwarteten Tabs verdeckt.
  Neuer Aufbau wartet auf die Tabs und tippt nur bei tatsächlich ausstehender Berechtigung.
- Prüfaufbau ergänzt: getrennte, zurückgesetzte Simulator-Durchläufe mit QA-Daten und ohne `-qa-fixtures`.
  Der zweite importiert 150 Bilder (130 öffentliche Fotos, 5 exakte Kopien, 10 unscharfe Ableitungen,
  5 Simulator-Screenshots) plus 3 Videos über PhotoKit; Herkunft und SHA-256 stehen im Artefakt-Manifest.
  Fotozugriff wird vorab per `simctl privacy` erlaubt. Werbung ausschließlich mit Googles Test-IDs,
  Käufe ausschließlich mit `PhotoMaid.storekit`; Tresor per PIN. Keine Systemlöschung wird bestätigt.
- UI-Prüfpunkte speichern PNGs und Accessibility-Bäume als XCTAttachments; `.xcresult`, Logs und Testübersichten
  werden im Artefakt `simulator-ui-evidence` aufbewahrt. Veraltete Einführung/Selektoren korrigiert,
  stabile Kennungen an vorhandenen Bedienelementen ergänzt.
- Lokal: Swift **6.4.1**, Linux: **381/381 PASS**; Mediengenerator: **153 Importe, exakt 5 zusätzliche Kopien PASS**;
  Strings `--check`: **PASS**, 1563 Kennungen / 2548 Einträge / 16 Sprachen.
- Erweiterter Lauf [38635318023](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38635318023):
  Kern PASS, iOS-Build FAIL: zu großer SwiftUI-Ausdruck der Feed-Bühne; synchroner UI-Test-Abbau verletzt
  MainActor-Isolation. Korrektur: Bühnen-Layer und einzelne Medienseite separat typprüfen; Abbau asynchron.
  Keine Gesten-/Ledger-/Produktregel geändert. Danach erneut 381 Kern-Tests PASS.
- Wiederholung [38636571661](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38636571661) läuft mit
  Export der Ausgangsbelege: **Build PASS, 22 iOS-Unit-Tests PASS**, keine Compilerfehler. UI wurde wegen
  eines Workflow-Fehlers übersprungen: Xcode meldet `TEST EXECUTE SUCCEEDED` statt `TEST SUCCEEDED`.
  Erfolgserkennung/Bericht korrigiert; getrennte Fehlermarker werden ebenfalls geprüft. Endgültige UI-/visuelle
  Ergebnisse weiterhin **NOT RUN**. Ein grüner Build allein gilt nicht
  als Geräteabnahme. Die abschließende Tabelle und Fehlerkorrekturen folgen hier nach den Simulator-Läufen.

- Weitere Belege: Lauf `38638077269` (abgebrochen), alle **31 unterschiedlichen PNGs** geprüft;
  Lauf `38642182043`, QA: **2/8 PASS, 6/8 FAIL**, alle **25 unterschiedlichen PNGs** geprüft.
  Rich-Photos-Systemblatt trotz `simctl privacy`; explizite sichere Freigabe ergänzt.
  UMP zeigt „Our app wants to stay free for you“ / „Continue“; zuvor fälschlich als Anzeige erkannt.
  Einwilligung und sichtbare Anzeigen werden nun getrennt erkannt (versteckter SDK-Preloader zählt nicht).
  Veraltete Einstellungen-/Studio-Texte und Pro-Selektor korrigiert. Pro-Einstellungenzeile zeigt jetzt
  „PhotoMaid Pro“ neben dem Kaufstatus (bestehende Texte aller 16 Sprachen).
  App-eigene Entfernungsbestätigung wird im QA-Fotolauf durch Beenden/Neustart sicher verworfen;
  niemals die echte Löschung ausgelöst. Ergebnis der nächsten Wiederholung steht noch aus.

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
