# Release-Blocker

Kein Release, kein TestFlight-Upload und keine Fertigmeldung, solange ein Punkt offen ist.

| # | Blocker | Art | Wer |
|---|---|---|---|
| 1 | **Keine macOS/Xcode-Umgebung genutzt**: App-Target nie kompiliert/typgeprüft, keine Simulator- oder Geräteläufe | Verifikation | Entwickler mit Mac + Xcode (iOS-27-SDK, stabil) |
| 2 | Liquid-Glass-APIs gegen iOS-27-SDK nicht bestätigt (`glassEffect`, `GlassEffectContainer`, `.glass`, `.glassProminent`, `tabBarMinimizeBehavior`) | Verifikation | Build auf macOS |
| 3 | Bundle-ID (`app.photomaid.ios` = Platzhalter), Development Team leer | Konfiguration | Inhaber |
| 4 | RevenueCat: API-Key, Entitlement-ID, Offering; App-Store-Connect-Produkt (Non-Consumable), Preis (zuletzt 3.99 CHF diskutiert) | Konfiguration | Inhaber |
| 5 | Rewarded-Werbeanbieter nicht entschieden; SDK, Test-Ad-Unit, UMP/Consent, ATT-Bewertung, Privacy-Manifest-Einträge fehlen | Entscheidung | Inhaber |
| 6 | Dritt-Anbieter-Ordner (File Provider): Offline-Verhalten unbelegt; derzeit nur `isUbiquitousItem` geprüft | Technik/Spike | Entwickler |
| 7 | Mediengrößen für Fotos ohne private API nur über Streaming ermittelbar; aktuell „unbekannt“ angezeigt | Produktentscheidung | Inhaber |
| 8 | Visuelle Abnahme aller 15 Screens (Runtime-PNGs vs. Referenz) | Abnahme | QA auf Simulator/Gerät |
| 9 | Accessibility-/Dynamic-Type-/Dark-/Kontrast-Matrix, VoiceOver-Durchgang | Abnahme | QA |
| 10 | Performance (Instruments), 100 Entscheidungen / 30 Videowechsel / Undo-Serien auf realem iPhone | Abnahme | QA |
| 11 | Reale PhotoKit-Löschung mit QA-Assets, Abbruch, Fehler, iCloud-Konto | Abnahme | QA |
| 12 | Finales App-Icon (aktuell generierter Platzhalter) | Design | Inhaber |
| 13 | Datenschutzerklärung-URL, Privacy Labels, App-Review-Guidelines, DACH-Rechtsprüfung, Altersfreigabe, Marken-/Store-Konflikt „PhotoMaid“ | Recht/Compliance | Inhaber |
| 14 | String Catalog: Format-Spezifizierer interpolierter Texte von Xcode-Extraktion bestätigen lassen | Verifikation | Build auf macOS |
| 15 | Zweiter unabhängiger Read-only-Review (Phase 10) | Abnahme | zweite Person/Agent |
