# Architektur (iOS)

Stand 09.10.2026. Ziel: native iOS-App (iOS 26+, Swift 6 mit strikter Concurrency, SwiftUI + Observation,
Liquid Glass) mit der Produktlogik der Android-App (`photomaid-android`, Funktionsmatrix `docs/IOS_FUNKTIONSMATRIX.md`).

## Schichten

```
PhotoMaid/                         (Repo-Wurzel)
├─ Package.swift                   PhotoMaidCore – plattformneutral, auf Linux getestet (swift test)
├─ Sources/PhotoMaidCore/          Port von photomaid-android/core (gleiche Typen, gleiche Regeln)
│  ├─ Model/                       ItemReference, LocalDay, KnownSize/SizeTally, Ids
│  ├─ Decisions/                   DecisionModel, LedgerState, LedgerPersistence, DecisionLedger (actor)
│  ├─ Feed/                        FeedGestureMachine (einzige Gesten-State-Machine), FeedSession, FeedOrder
│  ├─ Later/ Cleanup/ Capabilities/ Duplicates/ Storage/ Ads/
│  ├─ Library/                     Timeline, AlbumTree (Android FolderTree), Slideshow, Search
│  ├─ Organize/                    Tags, Notes, Basket, Rematch, PhotoSeries
│  ├─ Collections/ Progress/ QuickAccess/ Share/
│  ├─ Edit/                        EditRecipe, EditGeometry, ColorMatrices, Layers, ResizeRules
│  ├─ Studio/                      Collage, VideoPlan, MoviePlan
│  ├─ Batch/                       BatchPlan, Workflow, TargetSize, VideoTarget
│  ├─ Document/                    PdfLayout, PdfEdit (Seitenplan)
│  ├─ Archive/                     Archive (Plan, Journal, Zielart), Backup (photomaid-backup v1)
│  ├─ Analysis/                    Gruppierung ähnlicher Fotos, Schärfe-Schwellen (nur Logik, keine Pixel)
│  └─ Localization/                PluralRules (CLDR-Ganzzahlregeln der 16 Sprachen)
├─ Tests/PhotoMaidCoreTests/       Swift Testing, Port der Android-core-Tests
├─ project.yml                     XcodeGen → PhotoMaid.xcodeproj
├─ PhotoMaid/                      App-Target (nur iOS)
│  ├─ App/                         PhotoMaidApp, AppModel (@Observable, @MainActor), RootView (5 Tabs), AppConfig, Strings
│  ├─ DesignSystem/                Tokens, Glass-Bausteine, Formatting, Haptics
│  ├─ Persistence/                 Core Data (Ledger + Schlüssel/Wert), KeyValueStore
│  ├─ Infrastructure/
│  │  ├─ PhotoLibrary/             PhotoLibraryService, ThumbnailCache, SizeMeter, AlbumService, ResourceHasher
│  │  ├─ Playback/                 FeedPlayer (ein AVPlayer), RemoteCommands
│  │  ├─ Media/                    ImageRenderer (Core Image), VideoComposer/Exporter, MovieExporter,
│  │  │                            CollageRenderer, PdfRenderer, GifWriter, BatchRunner
│  │  ├─ Analysis/                 VisionService (Vision/VisionKit, nur lokal)
│  │  ├─ Files/                    ConnectedSources (Bookmarks), FileIndex
│  │  ├─ Archive/                  ArchiveEngine, BackupService
│  │  ├─ Purchases/                StoreKitGateway (StoreKit 2)
│  │  └─ Notifications/            ReminderScheduler
│  ├─ Features/                    Onboarding, Today, ReviewFeed, Library, Organize, CleanUp, Later,
│  │                               History, Studio, Editor, VideoEditor, PdfStudio, Analysis, Archive,
│  │                               Settings, Pro, Files
│  └─ Resources/                   Localizable.xcstrings (16 Sprachen), InfoPlist.xcstrings, PrivacyInfo, Assets
├─ PhotoMaidTests/                 XCTest: Core Data, Dateisicherheit, Renderer
└─ PhotoMaidUITests/               XCUITest mit QA-Medien (nur Build-Bedingung QA_FIXTURES)
```

## Grundsätze

- **Eine Wahrheit je Zustand.** Entscheidungen, Verlauf, Undo, Journal und Tageskontingent liegen in `LedgerState`
  und werden über `LedgerPersistence.commit(LedgerChange)` in **einer** Core-Data-Transaktion geschrieben.
  Alles Übrige (Einstellungen, Schlagwörter, Notizen, Auswahlkorb, Abläufe, Entwürfe, Größen- und Analyse-Cache)
  liegt als JSON in `CDKeyValue` über `KeyValueStore`.
- **Kern zuerst.** Jede Regel, die sich ohne Apple-SDK formulieren lässt, liegt in `PhotoMaidCore` und ist auf Linux
  getestet. Die App verdrahtet nur.
- **Eine Gesten-State-Machine** (`FeedGestureMachine`), eine Feed-Session (`FeedSession`), ein Feed-Weg
  (`FeedViewModel.perform` – Geste, VoiceOver-Aktion und Taste rufen dieselbe Funktion).
- **Eine Capability-Auflösung** (`Capabilities.resolve`), eine Kauf-Wahrheit (`StoreKitGateway`).
  Keine View deutet den Kaufstatus selbst.
- **Concurrency.** `AppModel` und alle ViewModels `@MainActor @Observable`. Schwere Arbeit (Hash, Größen messen,
  Core Image, Export, Vision) in `actor`s oder `Task.detached` mit `Sendable`-Werten; Fortschritt über
  `AsyncStream`; jeder lange Vorgang abbrechbar (`Task.checkCancellation`).
- **Vorschau = Export.** Foto-Editor: ein Core-Image-Graph (`ImageRenderer.render(recipe:source:)`) für Bildschirm und
  Datei. Video: eine `AVVideoComposition` für `AVPlayerItem` und `AVAssetExportSession`. Collage/PDF: ein Renderer.
- **Nie verzerren.** Bilder `.scaledToFit()`/`.scaledToFill()` + `.clipped()`, Video `resizeAspect`, Größe nur proportional.
- **Medien von iCloud (wie die Fotos-App, Nutzerentscheidung 2026-10-10).** Feed und Betrachter zeigen sofort die
  schnelle, ggf. unscharfe Fassung (`deliveryMode = .opportunistic`) und laden die volle Qualität automatisch aus iCloud
  (`isNetworkAccessAllowed = true`, Fortschritt als kleine Anzeige); Videos werden gestreamt; die nächsten Medien werden
  vorgeladen. „Aus iCloud laden“ gibt es nur noch als Rückfall, wenn nichts ankommt (z. B. ohne Netz). Größen werden
  weiterhin nur lokal gemessen (unbekannt bleibt unbekannt, kein Download nur zum Messen).

## Navigation

`TabView` mit fünf `Tab`s wie Android: **Heute · Fotos · Aufräumen · Studio · Verlauf**, Tab-Leiste in Liquid Glass,
`tabBarMinimizeBehavior(.onScrollDown)`. Je Tab ein `NavigationStack` mit typisierten Routen (`AppRoute`).
Feed, Betrachter und Editoren als `fullScreenCover` (Tab-Leiste aus). Einstellungen und Pro als Sheet.

## Liquid Glass

Nur öffentliche iOS-26-APIs, keine nachgebauten Glas-Effekte:

| Baustein | API | Einsatz |
|---|---|---|
| Tab-Leiste, Navigationsleisten, Toolbars, Sheets | Systemstandard (iOS 26 rendert sie in Glas) | überall |
| Schwebende Kapseln (Feed-Kopf, Richtungs-Pille, Später-Pille, Editor ✕/✓) | `.glassEffect(.regular, in: .capsule)` in `GlassEffectContainer` | über Fotos |
| Schaltflächen | `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` | Hauptaktionen über Medien |
| Interaktive Kapseln | `.glassEffect(.regular.interactive())` | Werkzeugleisten im Editor |
| Übergänge | `.glassEffectID(_:in:)` | Kopfzeile ↔ Auswahl-Leiste |

Listen, Raster und Fotos selbst bleiben ohne Glas (Masterprompt: „Fotos und Videos im Mittelpunkt“).
Reduce Transparency/Increase Contrast übernimmt das System. Touch-Ziele ≥ 44 pt (`Tokens.touch = 48`).

## Abhängigkeiten

| Paket | Grund | Pin |
|---|---|---|
| swift-crypto | nur Linux-Tests (CryptoKit-kompatibles SHA-256); auf iOS nicht gelinkt | exakt 4.5.2 |

Keine weiteren. RevenueCat entfällt (StoreKit 2, Entscheidung E3). Kein Werbe-SDK (E1).

## Lokalisierung

`scripts/android_strings_to_xcstrings.py` erzeugt `Localizable.xcstrings` aus den 16 Android-`strings.xml`
(gleiche Kennungen, `%1$s` → `%1$@`, `%d` → `%lld`, `plurals` → Einträge `kennung#one|few|many|…`) und ergänzt
iOS-eigene Texte aus `PhotoMaid/Resources/ios_strings.json`. Mengen wählt `PluralRules` (Kern, getestet).
In Swift nur über `L("kennung")`, `L("kennung", args…)` und `LP("kennung", anzahl, args…)`.

## Persistenz-Schema

`PhotoMaid.xcdatamodeld` Version 1 (unverändert): `CDItemRecord`, `CDEvent`, `CDIntent`, `CDDayUsage`, `CDKeyValue`.
Neue Daten nur als neue Schlüssel in `CDKeyValue`, damit keine Migration nötig ist.
