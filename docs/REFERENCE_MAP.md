# Referenz-Zuordnung: 15 Mockup-Screens → Code

Tafeln liegen in `docs/reference/`. Tafel A = Später/Regeln/Verlauf/Pro/Einstellungen,
Tafel B = Aufräumen/Downloads/Große Dateien/Duplikate/Speicher, Tafel C = Heute/Feed Foto/Feed Video/Datenschutz/Korb.

| # | Screen | Tafel | View | Bewusste Abweichungen von der Vorlage |
|---|---|---|---|---|
| 1 | Heute | C1 | `Features/Today/TodayView.swift` | Keine GB je Kategorie (Mediengrößen ohne Einlesen unbekannt) → Anzahl. Speicherkarte zeigt Gerätewert, klar als „nicht nur Fotos“ beschriftet. „Later 2.9 GB“ entfällt. |
| 2 | Feed Foto | C2 | `Features/ReviewFeed/ReviewFeedView.swift`, `MediaPage.swift` | Vier Richtungshinweise nur als Einstiegshilfe (Overlay), nicht permanent. Kein Ort (GPS nicht angezeigt). Größe unbekannt → Pixelmaße. Kein Herz/Favorit (Behalten ≠ Favorit). |
| 3 | Feed Video | C3 | `MediaPage.swift` (`VideoOverlay`) | Größe nicht angezeigt (unbekannt, bis lokal gemessen). Mute-Control + Timeline in eigener Zone. |
| 4 | Datenschutz/Zugriff | C4 | `Features/Onboarding/PrivacyAccessView.swift` | **Keine Toggles**: echte Systemzustände + kontextuelle Buttons. Text erklärt iCloud-Sync statt „100 % on device“. |
| 5 | Auswahlkorb | C5 | `Features/CleanupBasket/CleanupBasketView.swift` | Kein „1,4 GB ready to be freed“. Getrennte Bestätigung Fotos vs. Dateien, Tageskontingent sichtbar. |
| 6 | Aufräumen-Hub | B1 | `Features/CleanUpHub/CleanUpHubView.swift` | „Similar, blurry“ entfällt (keine KI). Zusätzliche Links: Speicherübersicht, Auswahlkorb. |
| 7 | Downloads/Dateien | B2 | `Features/FileBrowser/FileBrowserView.swift` | Titel „Downloads“ nur bei verbundener Downloads-Quelle, sonst „Dateien“ + „Ordner auswählen“. APK/EXE werden nicht geöffnet/ausgeführt. |
| 8 | Große Dateien | B3 | `Features/Storage/LargeFilesView.swift` | Filter änderbar (Stepper, Standard 100 MB). Unbekannte Größen separat. |
| 9 | Duplikate | B4 | `Features/Duplicates/DuplicatesView.swift` | Gesamt vs. zusätzliche Kopien getrennt; „keine garantierte Ersparnis“. Pro-Badge. |
| 10 | Speicherübersicht | B5 | `LargeFilesView.swift` (`StorageInsightsView`) | A/B/C getrennt; keine Kategorie-GB für Fotos; keine Audio/Documents/Other-Aufschlüsselung fremder Apps. |
| 11 | Später | A1 | `Features/Later/LaterView.swift` | Gruppen: Wieder fällig / Morgen / 7 Tage / ab Datum / ohne Datum (echte Daten). |
| 12 | Regeln & Routinen | A2 | `Features/Rules/RulesView.swift`, `RulesStore.swift` | Regeln erzeugen nur Prüfaufgaben; Hinweis „Hintergrund nicht garantiert“. |
| 13 | Verlauf | A3 | `Features/History/HistoryView.swift` | Keine „x GB freed“-Summen (nicht belegbar). „Bereinigt (bestätigt)“ statt „Cleaned“. |
| 14 | Pro | A4 | `Features/Pro/ProView.swift` | Kein $9.99: Preis nur aus Storeprodukt; ohne Konfiguration „noch nicht verfügbar“. Keine Landschafts-Fotokulisse (Stockmotiv). |
| 15 | Einstellungen | A5 | `Features/Settings/SettingsView.swift` | Deutsch, Version, Hilfe, Datenschutzerklärung-Link (falls konfiguriert). |

Visuelle Abnahme je Screen (Referenz ↔ Runtime-PNG ↔ Abweichung ↔ Entscheidung): **NOT RUN** –
Runtime-Aufnahmen erfordern Simulator/iPhone (siehe `docs/QA_MATRIX.md`).
