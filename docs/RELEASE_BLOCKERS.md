# Release-Blocker

Kein Release, kein TestFlight-Upload und keine Fertigmeldung, solange ein Punkt offen ist.

| # | Blocker | Art | Wer |
|---|---|---|---|
| 0 | **App-Target unvollständig**: 19 verlinkte Ansichten fehlen (`docs/PLAN_WEITER.md` §1) – nicht baubar | Implementierung | Claude (Schritte A1–A8) |
| 1 | **Keine macOS/Xcode-Umgebung genutzt**: App-Target nie kompiliert/typgeprüft, keine Simulator- oder Geräteläufe | Verifikation | macOS-CI-Lauf nach Freigabe (E11) oder Mac mit Xcode (iOS-26-SDK) |
| 2 | Liquid-Glass-, AVFoundation- und BackgroundTasks-APIs gegen iOS-26-SDK nicht bestätigt (`glassEffect`, `GlassEffectContainer`, `.glass`, `.glassProminent`, `tabBarMinimizeBehavior`) | Verifikation | Build auf macOS |
| 3 | ~~Bundle-ID, Development Team~~ erledigt: `com.mrdevn4ever.photomaid`, Team `HUN9MS832X`; `PM_BUNDLE_ID`/`PM_TEAM_ID` in GitHub gleich setzen | Konfiguration | Inhaber |
| 4 | StoreKit 2: App-Store-Connect-Produkt (Non-Consumable) anlegen, Produkt-ID als Variable; Preis (E4) | Konfiguration | Inhaber |
| 5 | Werbung/Rewarded (E1) nicht entschieden – derzeit ganz ohne, damit auch kein Pro-Test und kein Video-Bonus | Entscheidung | Inhaber |
| 6 | Dritt-Anbieter-Ordner (File Provider): Offline-Verhalten unbelegt; derzeit nur `isUbiquitousItem` geprüft | Technik/Spike | Entwickler |
| 7 | Mediengrößen für Fotos ohne private API nur über Streaming ermittelbar; aktuell „unbekannt“ angezeigt | Produktentscheidung | Inhaber |
| 8 | Visuelle Abnahme aller 15 Screens (Runtime-PNGs vs. Referenz) | Abnahme | QA auf Simulator/Gerät |
| 9 | Accessibility-/Dynamic-Type-/Dark-/Kontrast-Matrix, VoiceOver-Durchgang | Abnahme | QA |
| 10 | Performance (Instruments), 100 Entscheidungen / 30 Videowechsel / Undo-Serien auf realem iPhone | Abnahme | QA |
| 11 | Reale PhotoKit-Löschung mit QA-Assets, Abbruch, Fehler, iCloud-Konto | Abnahme | QA |
| 12 | Finales App-Icon (aktuell generierter Platzhalter) | Design | Inhaber |
| 13 | Datenschutzerklärung-URL, Privacy Labels, App-Review-Guidelines, DACH-Rechtsprüfung, Altersfreigabe, Marken-/Store-Konflikt „PhotoMaid“ | Recht/Compliance | Inhaber |
| 14 | String Catalog: Format-Spezifizierer interpolierter Texte von Xcode-Extraktion bestätigen lassen | Verifikation | Build auf macOS |
| 15 | Menschliche Code-Review (PR erst auf ausdrückliche Anweisung) | Abnahme | Inhaber |
| 16 | Video-Export auf echten Medien (HDR, Zeitlupe, 4K/60) und Hintergrund-Export (`BGContinuedProcessingTask`) | Abnahme | QA auf Gerät |
