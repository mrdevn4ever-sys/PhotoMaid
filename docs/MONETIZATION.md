# Monetarisierung

## Modell

| Stufe | Inhalt |
|---|---|
| Free | unbegrenzt ansehen/sortieren, Feed, Später, Undo, Verlauf, Quellen, Basis-Dateiansicht, Sicherheit; **15 bestätigte Bereinigungen pro lokalem Kalendertag** (Fotos + Videos + Dateien gemeinsam; ein logisches Asset/eine Datei = 1) |
| Pro (Non-Consumable) | unbegrenzte Bereinigungen, exakte Duplikate, erweiterte Datei-/Speicherwerkzeuge, dauerhafte Routinen, keine Werbung |
| Rewarded-Vorschau | freiwillig, 30 reale Minuten Pro-Werkzeuge, max. 1 Freischaltung pro lokalem Tag, Tageslimit bleibt 15, Routinen nur einmaliger Testscan |

Nicht gezählt: Swipes, Behalten, Vormerken, Analyse, Termine.

## Umsetzung

- `Capabilities.resolve(purchase:rewards:now:)` – einzige Auflösung (PhotoMaidCore, getestet).
- `PurchaseGateway` – `RevenueCatPurchaseGateway` (Kauf, Restore, Pending/Ask-to-Buy, Abbruch, Fehler,
  Revocation über `customerInfoStream`, Offline-Cache) oder `UnconfiguredPurchaseGateway`.
- Konfiguration über Build-Settings → Info.plist: `PM_REVENUECAT_API_KEY`, `PM_PRO_ENTITLEMENT_ID`.
  Ohne Werte: „Käufe sind in dieser Version noch nicht verfügbar“ (kein erfundener Preis).
- Preis: ausschließlich `storeProduct.localizedPriceString`. Mockup-$9.99 ist Platzhalter;
  zuletzt diskutiert 3.99 CHF – nur im lokalen StoreKit-Test (`PhotoMaid.storekit`, Produkt
  `test.photomaid.pro.lifetime`, klar als TEST markiert).
- Rewarded: `RewardedAdGateway`; `EntitlementCenter.watchRewardedAd` schaltet nur bei
  `.rewarded(rewardID:)` frei (idempotent). Keine Ad-Requests bei Pro oder unbekanntem Kaufstatus.
  Keine Banner/Interstitials/App-Open-Ads.
- Ablauf der Vorschau: begonnene Arbeitseinheit (`WorkUnitGrant`) läuft zu Ende; Entscheidungen bleiben.

## Nicht übernommen

- Android-Käufe werden nicht automatisch als iOS-Pro gewertet.
- Dreitages-Trial: nicht aktiviert (nur bei ausdrücklicher Freigabe und App-Store-konform).
- Keine Belohnung für Tracking-Einwilligung; fehlende ATT-Freigabe sperrt nichts.

## Status

Käufe: BLOCKED (keine RevenueCat-/App-Store-Connect-Konfiguration). Rewarded: BLOCKED (Anbieter offen).
