# TestFlight · PhotoMaid 1.0 (17)

**PASS: Release archiviert, signiert, hochgeladen, von Apple verarbeitet und intern verteilt.**

- [Lauf 39200627021](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39200627021),
  App `com.mrdevn4ever.photomaid`, Apple-App-ID `6821165617`.
- Exakter App-Quellstand: `575313d9f1f9a6f2a806bc87b19060f0379bcd3a`.
- Version **1.0, Build 17**, Release, Xcode 26.6 / iPhoneOS-SDK 26.5, vorhandenes manuelles Signing.
- `ARCHIVE SUCCEEDED`; signierte IPA um **04:46:12 UTC** geprüft.
- Upload bestätigt am **19.10.2026, 04:47:52 UTC**.
- Apple-Verarbeitung und interne Verteilung bestätigt um **04:50:26 UTC**.
- Keine externe Tester-Verteilung und keine App-Store-Veröffentlichung.

Der [native CI-Lauf](../native/run.json) hat denselben Quellstand erfolgreich gebaut und getestet:
**499 Core-Tests, 82 native Unit-Tests sowie je 3/3 UI-Tests auf iPhone und großem Simulatorfenster**.
Die [483 App-/Test-/Release-Dateien](../final-app-source.json) sind identisch mit dem CI-Stand.
Deshalb `run_tests=false` im Upload-Job; der signierte Release-Build wurde tatsächlich neu erstellt.

## Signierte IPA: Privacy-Prüfung

Alle drei tatsächlichen Manifeste bestehen, ohne Privacy-Fehler oder -Warnung:

| Manifest | Tracking | Tracking-Domains |
|---|---|---|
| `PhotoMaid.app/PrivacyInfo.xcprivacy` | `true` | `googleads.g.doubleclick.net` |
| `GoogleMobileAds.framework/PrivacyInfo.xcprivacy` | nicht gesetzt | keine |
| `UserMessagingPlatform.framework/PrivacyInfo.xcprivacy` | nicht gesetzt | keine |

Die ITMS-91064-Regel ist am exportierten App-Paket geprüft. Die anschließende erfolgreiche
Apple-Verarbeitung ist separat bestätigt. Die bestehende App-Werbekonfiguration blieb unverändert.
Fotos werden über Apples Photos-Framework aus der eigenen Mediathek geladen; keine neuen Bild-Uploads.

## Belege

- [Upload, Verarbeitung und interne Verteilung](upload-confirmation.log): ausgewählte unveränderte
  Workflowlog-Zeilen, nur ANSI-Farbcodes entfernt.
- [Manifestpfade, Prüfsummen und Ergebnisse](build/privacy-manifests.json).
- [Release-Archivlog](gym.log), [Workflow-Ergebnis](run.json), [fastlane-Bericht](fastlane/report.xml).
- [Automatischer Kurzbericht](ci-report.md): `UNBEKANNT` bedeutet, dass der bestehende Parser den
  Archivmarker nicht erkennt. Das Original enthält `ARCHIVE SUCCEEDED`; null Compilerfehler,
  eine bestehende Video-API-Deprecation. Weitere Loghinweise betreffen Atlas-Aufteilung und
  übersprungene AppIntents-Metadaten; keine Buildfehler.

Reales iCloud-Konto/Netzverhalten, Geräte-FPS und physische Faltgeräte sind nicht abgenommen.
Ausgeführte Tests und native Aufnahmen: [Abschlussbericht](../README.md).
