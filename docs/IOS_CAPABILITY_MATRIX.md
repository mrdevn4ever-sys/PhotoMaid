# iOS-Fähigkeitsmatrix

Status: **SDK-verifiziert** = gegen lokal kompilierbare iOS-27-SDK-Signaturen geprüft.
In dieser Umgebung (Linux, kein Xcode) ist **keine** Zeile SDK-verifiziert. Alles unten beruht auf
öffentlicher Apple-Dokumentation (Stand iOS 26 SDK) und muss auf macOS mit Xcode/iOS-27-SDK
bestätigt werden (Phase-0-Spikes, siehe unten).

## Toolchain-Preflight (Phase 0)

| Prüfung | Ergebnis |
|---|---|
| `xcodebuild -version` | BLOCKED – Linux-Container (Ubuntu 24.04), kein Xcode |
| `xcodebuild -showsdks` | BLOCKED |
| `xcrun simctl list devices available` | BLOCKED |
| macOS-Version | BLOCKED – kein macOS |
| Swift-Compiler | Swift 6.4 (swift-6.4-RELEASE, Linux x86_64), Swift-6-Sprachmodus aktiv |
| XcodeGen | 2.46.0 aus Quellcode gebaut (Linux), `project.yml` → `PhotoMaid.xcodeproj` erzeugt |
| Physisches iPhone | BLOCKED |

## Funktionen und APIs

| Bereich | Öffentliche API | Entscheidung | Status |
|---|---|---|---|
| Fotozugriff | `PHPhotoLibrary.authorizationStatus/requestAuthorization(for: .readWrite)` | 5 Zustände inkl. `limited`; Anfrage nur per Button | NOT RUN |
| Limited verwalten | `presentLimitedLibraryPicker(from:)` | angeboten bei `limited` | NOT RUN |
| Änderungen | `PHPhotoLibraryChangeObserver` | `changeToken` → Screens laden neu | NOT RUN |
| Vorschau | `PHCachingImageManager.requestImage`, `isNetworkAccessAllowed = false`, `.highQualityFormat` | kein iCloud-Download; `PHImageResultIsInCloudKey` → „nicht lokal“ | NOT RUN |
| Video | `requestPlayerItem(forVideo:)`, `AVPlayer`, `AVPlayerLayer` (`resizeAspect`) | ein Player; `.ambient`+`mixWithOthers` solange stumm | NOT RUN |
| Löschen Fotos | `PHPhotoLibrary.performChanges` + `PHAssetChangeRequest.deleteAssets` | System-Bestätigung, Gesamtergebnis; `userCancelled` → abgebrochen | NOT RUN |
| Löschbarkeit | `PHAsset.canPerform(.delete)` | nicht löschbare/geteilte Assets ausgeschlossen | NOT RUN |
| Mediengröße | **keine** öffentliche Metadaten-API; `value(forKey:"fileSize")` verboten | Fotos: unbekannt; Videos: `AVURLAsset.url` → `.fileSizeKey` (lokal); Hash-Streaming zählt Bytes | NOT RUN (Spike nötig) |
| Duplikate Fotos | `PHAssetResourceManager.requestData` (`isNetworkAccessAllowed = false`) | nur Assets mit genau 1 Foto/Video-Ressource vergleichbar | NOT RUN |
| Ordnerzugriff | `fileImporter([.folder])`, security-scoped URL, `bookmarkData()` | Bookmarks in Core Data, stale → erneuert | NOT RUN (Spike nötig) |
| Cloud-Ordner | `URLResourceValues.isUbiquitousItem` | iCloud Drive abgelehnt; Dritt-Provider: **offen** (siehe Release-Blocker) | NOT RUN |
| Dateikoordination | `NSFileCoordinator` (lesen / `.forDeleting`) | für Scan und Löschen | NOT RUN |
| Datei-Papierkorb | `FileManager.trashItem` | **nicht angeboten**: auf iOS nicht universell; nur „Endgültig löschen“ | Entscheidung |
| Vorschau Dateien | QuickLook `.quickLookPreview` | keine WebView, kein Entpacken, kein Ausführen | NOT RUN |
| Gerätespeicher | `volumeTotalCapacity`, `volumeAvailableCapacityForImportantUsage` | nur Anzeige (Reason 85F4.1) | NOT RUN |
| Liquid Glass | `glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)` | nur Navigation/schwebende Controls; Listen ruhig | NOT RUN |
| Tabs | `TabView` + `Tab(_:systemImage:value:)`, `tabBarMinimizeBehavior` | 4 Tabs | NOT RUN |
| Hintergrund | `BGTaskScheduler` | bewusst **nicht** verwendet (kein sinnvoller Hintergrundlauf ohne AppModel); Prüfung bei Start/Resume | Entscheidung |
| Mitteilungen | `UNUserNotificationCenter`, `UNCalendarNotificationTrigger` | opt-in, max. 8 ausstehend, keine Dateinamen | NOT RUN |
| Käufe | RevenueCat 5.91.0 (`purchases-ios-spm`) | einzige Entitlement-Wahrheit | BLOCKED (keine Konfiguration) |
| Rewarded | Anbieter offen | Protokoll + „nicht konfiguriert“ | BLOCKED |
| Hash | CryptoKit `SHA256` (Linux-Tests: swift-crypto) | Streaming | PASS (Linux, Testvektor) |

## Phase-0-Spikes (auf macOS/iPhone auszuführen)

1. PhotoKit: Zugriff in allen Zuständen, Löschung eines QA-Assets, Abbruch der Systemabfrage, Fehlercode.
2. Ordnerzugriff: Bookmark über App-Neustart, stale Bookmark nach Umbenennen, Entzug, Read-only-Ordner,
   „Auf meinem iPhone“ vs. iCloud Drive vs. Dritt-Provider (`isUbiquitousItem`, Offline-Verhalten).
3. Videogröße via `AVURLAsset.url` für lokale und optimierte (iCloud) Videos.
4. Liquid-Glass-Modifier gegen iOS-27-SDK kompilieren; Reduce Transparency / Increase Contrast prüfen.
