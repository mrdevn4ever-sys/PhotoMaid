# Implementierungsstatus

Stand: 15.10.2026 · Branch `claude/fixes-analysis-library-vault-20261014` · Build-7-Ausgangsstand, Simulator-Fachprüfung abgeschlossen.

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
