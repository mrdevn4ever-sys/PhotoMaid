# Offene und getroffene Entscheidungen (iOS)

Stand 09.10.2026. Der Masterprompt verlangt, bei kostenpflichtigen Diensten, irreversiblen Änderungen und neuen
Produktregeln anzuhalten. Deshalb steht hier jede Stelle, an der Android-Quellcode, Masterprompt und alte
iOS-Unterlagen sich widersprechen.

- **Angewendet** = folgt eindeutig aus einer Vorgabe des Nutzers (Masterprompt oder Android-Produktentscheidung).
- **Vorläufig** = umkehrbarer Standard, damit weitergebaut werden kann. Er steht an genau einer Stelle im Code
  (`Capabilities`, `AppConfig`), damit eine andere Entscheidung nur dort etwas ändert.
- **Offen** = du entscheidest. Bis dahin ist nichts davon aktiv.

| # | Thema | Widerspruch | Stand | Was gilt bis zur Entscheidung |
|---|---|---|---|---|
| E1 | Werbung, Rewarded, Pro-Test, Video-Bonus | Android: AdMob-Werbekarte alle 7 Entscheidungen, Rewarded für den 30-Minuten-Pro-Test und „+20 für heute“. Masterprompt iOS: „Keine Tracker“. Jedes Werbe-SDK überträgt Gerätedaten an Dritte (iOS: ATT, Privacy Manifest, Datenschutz-Labels „Tracking“) | **Offen** | Kein Werbe-SDK. Keine Werbekarte, keine Anzeige in der Zusammenfassung, kein Pro-Test, kein Video-Bonus. Der Kern enthält die Logik (`RewardLedger`, `FeedAdPolicy`), die App bietet sie nicht an (keine toten Knöpfe) |
| E2 | Diagonale Geste „schräg rechts oben = Datum wählen“ | Alte iOS-Regel: Diagonale. Android-Produktentscheidung 2026-09-29: Diagonale entfällt, eigener Termin über „Ändern“ in der Pille | **Angewendet** (Android-Entscheidung des Nutzers) | rechts bis 45° nach oben oder unten = Später mit Standardtermin + Pille „In 2 Tagen wieder · Ändern“; Schwellen wie Android (72 pt, 380 pt/s ab 20 pt, lockRatio 1,3) |
| E3 | Käufe | Alte iOS-Architektur: RevenueCat. Masterprompt: „Premium als einmaliger Lifetime-Kauf über StoreKit 2“, „keine unnötigen Drittanbieter-Abhängigkeiten“ | **Angewendet** | StoreKit 2 direkt, RevenueCat-Paket entfernt. Produkt-ID über Build-Einstellung `PM_PRO_PRODUCT_ID`; ohne ID: „Käufe sind in dieser Version noch nicht verfügbar“ |
| E4 | Tageslimit und Preis | Android-Quellcode: 20 endgültige Entfernungen pro lokalem Tag (Produktentscheidung 2026-10-04), Bonus +20. Alte iOS-Unterlagen: 15. Preis: iOS-Unterlagen „zuletzt 3.99 CHF diskutiert“, Android-Bericht „2.99–3.99“ | Limit **angewendet** (20, Masterprompt: „zunächst aus dem Quellcode übernehmen“); Preis **offen** | 20 pro Tag. Der Preis wird nur in App Store Connect festgelegt und in der App ausschließlich als `Product.displayPrice` gezeigt |
| E5 | Ordner und Alben | Android: „Ordner“ = Speicherort (In Ordner verschieben, Ordnerbaum, Ausgenommene Ordner); „Album“ = PhotoMaid-eigene Zusammenstellung ohne Datei-Änderung. iOS-Fotos kennen keine Speicherorte; Alben der Fotos-App sind genau „bewusste Zusammenstellung mit Mehrfachzuordnung“ | **Vorläufig** | Ordnerbaum → Alben und Ordner der Fotos-App (`PHCollectionList`); „In Ordner verschieben“ → „Zu Album hinzufügen“ (Systembestätigung entfällt, Änderung ist in der Fotos-App sichtbar und wird mit iCloud-Fotos synchronisiert – so beschriftet); Ausgenommene Ordner → Ausgenommene Alben. Keine zweite, PhotoMaid-eigene Alben-Liste. Schlagwörter, Notizen, Auswahlkorb bleiben PhotoMaid-eigen |
| E6 | Mindest-iOS | Alte iOS-Regel: iOS 27. Masterprompt: „iOS 26 als primäres Designziel“ | **Angewendet** | Deployment Target iOS 26.0; Liquid-Glass-APIs gibt es seit iOS 26 |
| E7 | Bildanalyse | Android und alte iOS-Regel: „keine KI/ML/Vision“. Masterprompt iOS §5: Vision/VisionKit/Core ML ausdrücklich verlangt, nur lokal | **Angewendet** (nur iOS) | Nur Apple-Frameworks auf dem Gerät. Ergebnisse sind Vorschläge oder Filter, nie eine Entscheidung oder Löschung. Texte sagen „auf diesem iPhone analysiert“ statt „keine Bilderkennung“. Analyse-Ergebnisse bleiben lokal (Core Data), werden nie gesichert/geteilt |
| E8 | Zusatzmodelle LaMa (Objekt entfernen), MobileSAM (Segmentierung) | Masterprompt: vor Integration Lizenz, kommerzielle Nutzung, Größe, Tempo, Core ML, Geräte prüfen | **Offen** | Prüfung in `docs/IOS_MODELLPRUEFUNG.md`; nicht integriert. Freistellen läuft mit Vision ohne Zusatzmodell |
| E9 | „An PhotoMaid senden“ (Share Extension) | Braucht eine App Group (in deinem Apple-Developer-Konto zu registrieren) und ein zweites Provisioning Profile | **Offen** (Konfiguration) | Erweiterung nicht im Build, damit Signierung und TestFlight ohne App Group funktionieren. Code-Pfad „Übernommen“ in der App vorhanden, Einstieg nur über „Öffnen in…“ (Dokumenttypen) |
| E10 | Freie/Pro-Aufteilung der iOS-eigenen Funktionen | Für Scannen, Texterkennung, PDF-Seiten bearbeiten/zusammenführen/Unterschrift, Freistellen, ähnliche/unscharfe Fotos, Stapelbearbeitung gibt es keine Android-Regel | **Vorläufig** (an einer Stelle: `Capabilities`) | wie die nächste Android-Regel: Scannen, Texterkennung, PDF-Seiten bearbeiten frei (PDF aus Fotos wie Android: Free bis 10 Fotos, 1–2 je Seite); Unterschrift/Annotationen frei; Freistellen, ähnliche/unscharfe Fotos, Stapelbearbeitung = Pro (wie Serien/Regler) |
| E11 | Kostenpflichtige Dienste | Apple Developer Program (99 USD/Jahr) ist für TestFlight Pflicht; GitHub-Actions-macOS-Minuten sind über dem Freikontingent kostenpflichtig (macOS zählt zehnfach) | **Offen** (du entscheidest) | Alle Workflows nur manuell (`workflow_dispatch`). Kein Lauf ohne deine ausdrückliche Anweisung |
| E12 | Bundle-ID, Team-ID, App-Store-Connect-App | Platzhalter `app.photomaid.ios`, Team leer | **Offen** (Konfiguration) | Werte kommen aus GitHub-Secrets/Variablen, nie aus dem Repo (`docs/CI_TESTFLIGHT.md`) |
| E13 | Rückfallsprache | Alte iOS-Regel „Deutsch zuerst“; Android: Englisch als Rückfall für nicht unterstützte Sprachen, Deutsch Leitsprache | **Angewendet** (wie Android) | `CFBundleDevelopmentRegion = en`, Texte in 16 Sprachen aus den Android-Übersetzungen, Tests laufen auf Deutsch |
| E14 | „Endgültig löschen“ und Android-Papierkorb-Ansicht | iOS hat keine öffentliche API dafür | **Plattformgrenze** | nicht angeboten; Hinweis „liegt 30 Tage in ‚Zuletzt gelöscht‘ der Fotos-App“ |
| E15 | Bearbeiten am Original | Android: nur Kopie oder Kopie + Original in den Papierkorb. iOS kann nicht destruktiv am Original speichern (`PHContentEditingOutput`, in der Fotos-App rücksetzbar, Systembestätigung) | **Vorläufig** | Vorauswahl bleibt „Als Kopie speichern“; „Original bearbeiten (rücksetzbar)“ nur auf ausdrückliche Wahl |

## Was du entscheiden musst (Kurzfassung)

1. **E1** Werbung/Rewarded auf iOS: ganz ohne (Standard jetzt), oder ein Anbieter (welcher) trotz „keine Tracker“.
2. **E4** Preis in App Store Connect.
3. **E5** Alben der Fotos-App statt eigener PhotoMaid-Alben – passt das?
4. **E8** LaMa/MobileSAM überhaupt einbauen (Größe, Lizenzlage der Trainingsdaten)?
5. **E9/E12** Apple-Developer-Konto, Bundle-ID, App Group anlegen; Secrets in GitHub hinterlegen.
6. **E10** Aufteilung Free/Pro der neuen iOS-Funktionen.
7. **E11** Wann ein macOS-CI-Lauf gestartet werden darf.
