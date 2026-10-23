# Release-Blocker

Historische Ausgangsliste mit verbleibenden Geräte- und Store-Abnahmen. Einige ursprüngliche Punkte
sind inzwischen umgesetzt; maßgeblich ist der [aktuelle Implementierungsstatus](IMPLEMENTATION_STATUS.md).
Interne TestFlight-Builds werden auf ausdrücklichen Auftrag erstellt und ersetzen keine offenen
Geräte- oder App-Store-Abnahmen.

| # | Blocker | Art | Wer |
|---|---|---|---|
| 0 | **App-Target unvollständig**: 19 verlinkte Ansichten fehlen (`docs/PLAN_WEITER.md` §1) – nicht baubar | Implementierung | Claude (Schritte A1–A8) |
| 1 | **Keine macOS/Xcode-Umgebung genutzt**: App-Target nie kompiliert/typgeprüft, keine Simulator- oder Geräteläufe | Verifikation | macOS-CI-Lauf nach Freigabe (E11) oder Mac mit Xcode (iOS-26-SDK) |
| 2 | Liquid-Glass-, AVFoundation- und BackgroundTasks-APIs gegen iOS-26-SDK nicht bestätigt (`glassEffect`, `GlassEffectContainer`, `.glass`, `.glassProminent`, `tabBarMinimizeBehavior`) | Verifikation | Build auf macOS |
| 3 | ~~Bundle-ID, Development Team~~ erledigt: `com.mrdevn4ever.photomaid`, Team `HUN9MS832X`; `PM_BUNDLE_ID`/`PM_TEAM_ID` in GitHub gleich setzen | Konfiguration | Inhaber |
| 4 | StoreKit 2: In App Store Connect Non-Consumable `com.mrdevn4ever.photomaid.pro` anlegen, Vereinbarung „Kostenpflichtige Apps“ aktivieren; Preis (E4). Workflow nutzt diese ID als Standard | Konfiguration | Inhaber |
| 5 | Werbung (E1/E19, entschieden 14.10.2026): echte AdMob-App-ID und Anzeigenblöcke (App-Start, nativ, Belohnung) als Secrets/Variablen `PM_ADMOB_APP_ID`, `PM_ADMOB_APP_OPEN_ID`, `PM_ADMOB_NATIVE_ID`, `PM_ADMOB_REWARDED_ID` – sonst zeigt der Build Googles Test-Anzeigen (keine Einnahmen); App-Store-Datenschutzangaben (Tracking: Geräte-ID, Werbedaten, ungefährer Standort, Diagnose) und Datenschutzerklärung (Werbung von Google, Einwilligung, ATT) anpassen; UMP-Einwilligungsnachricht (DSGVO) in der AdMob-Konsole anlegen | Konfiguration/Recht | Inhaber |
| 6 | Dritt-Anbieter-Ordner (File Provider): Offline-Verhalten unbelegt; derzeit nur `isUbiquitousItem` geprüft | Technik/Spike | Entwickler |
| 7 | Mediengrößen für Fotos ohne private API nur über Streaming ermittelbar; aktuell „unbekannt“ angezeigt | Produktentscheidung | Inhaber |
| 8 | Visuelle Abnahme aller 15 Screens (Runtime-PNGs vs. Referenz) | Abnahme | QA auf Simulator/Gerät |
| 9 | Accessibility-/Dynamic-Type-/Dark-/Kontrast-Matrix, VoiceOver-Durchgang | Abnahme | QA |
| 10 | Performance (Instruments), 100 Entscheidungen / 30 Videowechsel / Undo-Serien auf realem iPhone | Abnahme | QA |
| 11 | Reale PhotoKit-Löschung mit QA-Assets, Abbruch, Fehler, iCloud-Konto | Abnahme | QA |
| 12 | Finales App-Icon (aktuell generierter Platzhalter) | Design | Inhaber |
| 13 | Datenschutzerklärung-URL, Privacy Labels, App-Review-Guidelines, DACH-Rechtsprüfung, Altersfreigabe, Marken-/Store-Konflikt „PhotoMaid“ – seit 23.10.2026 heißt die App sichtbar „Arrumo“ (iOS, Datenschutzseite); offen: Markenrecherche „Arrumo“ (Swissreg, TMview, USPTO; Klassen 9/42), Domain, App-Name und IAP-Anzeigename „Arrumo Pro“ in App Store Connect, AdMob-App „Arrumo“, Store-Bilder mit neuem Schriftzug, Android-Texte | Recht/Compliance | Inhaber |
| 14 | String Catalog: Format-Spezifizierer interpolierter Texte von Xcode-Extraktion bestätigen lassen | Verifikation | Build auf macOS |
| 15 | Menschliche Code-Review (PR erst auf ausdrückliche Anweisung) | Abnahme | Inhaber |
| 16 | Video-Export auf echten Medien (HDR, Zeitlupe, 4K/60) und Hintergrund-Export (`BGContinuedProcessingTask`) | Abnahme | QA auf Gerät |
| 17 | ITMS-91064 für Builds 8–10 gemeldet: alle drei Manifeste der neuen Build-11-IPA bestanden; Apple-Verarbeitung und interne Verteilung bestätigt. ATT-/Werbeverhalten auf echtem Gerät bleibt offen; [Befund](PRIVACY_MANIFEST_AUDIT.md) | Geräteverifikation | Geräteabnahme |
