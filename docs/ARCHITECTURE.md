# Architektur

```
PhotoMaid/                      (Repo-Wurzel)
├─ Package.swift                PhotoMaidCore (Swift Package, plattformneutral, Linux-testbar)
├─ Sources/PhotoMaidCore/
│  ├─ Model/                    ItemReference, LocalDay, Clock, KnownSize/SizeTally
│  ├─ Decisions/                DecisionModel, LedgerState/LedgerPersistence, DecisionLedger (actor)
│  ├─ Feed/                     FeedGestureMachine (einzige Gesten-State-Machine), FeedSession
│  ├─ Later/                    LaterPreset, ReviewQueues, LaterGroup
│  ├─ Cleanup/                  OperationIntent/Outcome, DayUsage, AllowanceSnapshot
│  ├─ Duplicates/               DuplicateFinder (Größe → Teilhash → SHA-256), DuplicateGroup
│  ├─ Rules/                    ReviewRule, RuleEvaluator, ReviewTask
│  ├─ Capabilities/             PurchaseState, RewardLedger, Capabilities.resolve, WorkUnitGrant
│  └─ Storage/                  DeviceCapacity, StorageOverview
├─ Tests/PhotoMaidCoreTests/    Swift Testing (74 Tests)
├─ project.yml                  XcodeGen → PhotoMaid.xcodeproj
├─ PhotoMaid/                   iOS-App-Target
│  ├─ App/                      PhotoMaidApp, AppModel (DI + Lesemodelle), RootView (4 Tabs)
│  ├─ DesignSystem/             Tokens, Components, Formatting
│  ├─ Persistence/              Core-Data-Modell (versioniert) + CoreDataLedgerPersistence
│  ├─ Infrastructure/           PhotoLibrary, LocalFiles, Playback, Purchases, RewardedAds,
│  │                            Notifications, Background
│  ├─ Features/                 Today, ReviewFeed, CleanupBasket, CleanUpHub, FileBrowser,
│  │                            Duplicates, Storage, Later, Rules, History, Settings, Pro, Onboarding
│  └─ Resources/                Localizable.xcstrings, PrivacyInfo.xcprivacy, Assets, PhotoMaid.storekit
├─ PhotoMaidTests/              XCTest: Core-Data-Integration, Dateisicherheit
└─ PhotoMaidUITests/            XCUITest mit QA-Medien
```

## Prinzipien

- **Eine Wahrheit je Zustand.** Entscheidungen, Verlauf, Undo, Journal und Tageskontingent liegen
  gemeinsam in `LedgerState` und werden über `LedgerPersistence.commit(LedgerChange)` atomar in
  Core Data geschrieben. Keine parallele JSON-/SQLite-Quelle.
- **Actor-geschützte Commands.** `DecisionLedger` ist ein `actor`; `commit` ist synchron, damit
  zwischen Berechnung und Speicherung keine Reentrancy möglich ist.
- **Commit erst nach Persistenz.** Der Speicherzustand wird erst nach erfolgreichem Save übernommen.
  Fehler → Zustand unverändert → UI setzt die Aktion zurück.
- **Eine Gesten-State-Machine** (`FeedGestureMachine`) und **eine Feed-Session** (`FeedSession`),
  beide reine Werte ohne UI-Abhängigkeit. SwiftUI verdrahtet nur (`FeedViewModel`).
- **Eine Delete-Orchestrierung** (`AppModel.runCleanup`), aber provider-spezifische Operationen
  (PhotoKit vs. Dateien).
- **Eine Entitlement-Wahrheit** (`PurchaseGateway` → RevenueCat) und **eine Capability-Auflösung**
  (`Capabilities.resolve`).
- **MainActor für UI**, Swift Concurrency für Hintergrundarbeit, keine Hashes/Scans auf dem Main Thread
  (Dateiscan/Hash per `Task.detached`; PhotoKit-Callbacks auf Systemqueues).

## Abhängigkeiten

| Paket | Grund | Pin |
|---|---|---|
| RevenueCat (`purchases-ios-spm`) | vom Auftrag vorgegeben: Apple-IAP-Käufe, Restore, Revocation | exakt 5.91.0 |
| swift-crypto | nur Linux-Tests (CryptoKit-kompatible SHA-256-API); wird auf iOS nicht gelinkt | exakt 4.5.2 |

Rewarded-Werbe-SDK: bewusst **nicht** hinzugefügt, bis der Anbieter entschieden ist.

## Schema

`PhotoMaid.xcdatamodeld` Version 1: `CDItemRecord` (eindeutig `itemKey`), `CDEvent` (eindeutig `id`,
Reihenfolge `sequence`), `CDIntent`, `CDDayUsage`, `CDKeyValue` (Undo-Stack, Einstellungen, Quellen,
Regeln, Rewards, Kauf-Cache). Payloads als JSON-kodierte Domainwerte. Lightweight Migration aktiv.
