# Datenschutz-Datenkarte

| Daten | Ort | Verlässt Gerät? | Backup | Schutz |
|---|---|---|---|---|
| Entscheidungen, Verlauf, Undo, Journal, Kontingent | Core Data, Application Support | Nein | im Geräte-/iCloud-Backup des Nutzers (bewusst: Entscheidungen sollen Wiederherstellung überleben) | `completeUntilFirstUserAuthentication` |
| Ordner-Bookmarks, Regeln, Einstellungen, Reward-Ledger, Kauf-Cache | Core Data (`CDKeyValue`) | Nein | wie oben | wie oben |
| Thumbnails | PhotoKit-Cache (`PHCachingImageManager`), RAM | Nein | – | System |
| SHA-256-Hashes | nur im Speicher während des Scans | Nein | – | – |
| Medien, Dateinamen, Pfade, GPS, Medien-IDs | nur lokal gelesen | **Nein** | – | – |
| Kaufdaten | Apple / RevenueCat (anonyme App-User-ID) | Ja (technisch) | – | RevenueCat-Manifest |
| Werbedaten | Werbeanbieter (offen) | Ja, sobald konfiguriert | – | Release-Blocker |

## Aussagen in der App

- „Analyse und Sortierung erfolgen auf deinem Gerät.“ ✔
- „Mit iCloud-Fotos wirken Löschungen auf allen deinen Geräten.“ ✔ (Korb, Hilfe, Datenschutz)
- Nicht verwendet: „Alle Daten bleiben immer offline“, „100 % privat“.

## Weitere Maßnahmen

- App-Umschalter-Vorschau: Abdeckung, sobald die Szene nicht `active` ist (`RootView`).
- Zugriffsentzug: `refreshAccess()` bei Resume; Quellen melden `accessDenied`/`unavailable`.
- Fehlender Zugriff ist kein Löschbeweis (`ExistenceProbe.unknown`).
- Kein CloudKit-/iCloud-Entitlement (`PhotoMaid.entitlements` leer).
- Keine Analytics-SDKs.
- Required-Reason-APIs deklariert: DiskSpace 85F4.1, FileTimestamp 3B52.1 / C617.1.

## Offene Prüfpunkte vor Release

App Review Guidelines, Privacy Labels (inkl. RevenueCat/Werbung), Datenschutzerklärung-URL
(`PM_PRIVACY_POLICY_URL`), DACH-Rechtsprüfung, Altersfreigabe, Marken-/Store-Konflikt „PhotoMaid“.
Keine rechtliche Freigabe durch diese Arbeit.
