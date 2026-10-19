# TestFlight · PhotoMaid 1.0 (16)

**PASS: gebaut, manuell signiert, hochgeladen, von Apple verarbeitet und intern verteilt.**

- Lauf: [39179559217](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39179559217).
- App: `com.mrdevn4ever.photomaid`, Apple-App-ID `6821165617`.
- Exakter App-Quellstand: `a17daf70456757869caec5508808f56ebc367c1e`.
- Konfiguration: Release, Xcode 26.6, iPhoneOS-SDK 26.5, vorhandenes manuelles Signing.
- Archiv: `ARCHIVE SUCCEEDED`; signierter IPA-Export am **19.10.2026, 00:15:04 UTC**.
- Upload bestätigt: **00:16:18 UTC**.
- Apple-Verarbeitung bestätigt: **00:18:22 UTC**; anschließend interne Verteilung und gesetzter Testhinweis.
- Keine externe Verteilung und keine App-Store-Veröffentlichung.

Die 483 in `../final-app-source.json` aufgeführten App-, Test- und Release-Konfigurationsdateien
entsprechen unverändert dem bestandenen nativen CI-Stand. Dort: **498 Core-Tests, 76 native
Unit-Tests und Blocks je Simulator 1/1 UI PASS**. Deshalb keine zweite Unit-Ausführung im
TestFlight-Workflow (`run_tests=false`); die signierte Release-Konfiguration wird tatsächlich neu gebaut.

## Tatsächliche IPA-Privacy-Prüfung

Alle drei Manifeste der exportierten IPA bestehen, ohne Fehler oder Privacy-Warnung:

| Manifest im App-Paket | Tracking | Tracking-Domains |
|---|---|---|
| `PhotoMaid.app/PrivacyInfo.xcprivacy` | `true` | `googleads.g.doubleclick.net` |
| `Frameworks/GoogleMobileAds.framework/PrivacyInfo.xcprivacy` | nicht gesetzt | keine |
| `Frameworks/UserMessagingPlatform.framework/PrivacyInfo.xcprivacy` | nicht gesetzt | keine |

Damit ist auch die von ITMS-91064 betroffene Beziehung zwischen Tracking-Domains und Flag geprüft.
Der Validator prüft die wirkliche signierte IPA vor dem Upload; nicht nur das Quellmanifest.
Die nachfolgende erfolgreiche Apple-Verarbeitung ist separat belegt.

## Originalbelege

- [Apple-Upload, Verarbeitung und interne Verteilung](upload-confirmation.log): unveränderte ausgewählte Zeilen aus dem GitHub-Workflowlog, ohne ANSI-Farbcodes.
- [Manifestpfade, Prüfsummen und Ergebnisse](build/privacy-manifests.json).
- [Vollständiges Release-Archivlog](gym.log), [Workflow-Ergebnis](run.json), [fastlane-Schritte](fastlane/report.xml).
- [Automatischer Kurzbericht](ci-report.md): dessen Status `UNBEKANNT` entsteht, weil der vorhandene
  Parser Test-/Build-Marker auswertet und den Archivmarker nicht erkennt. Das Original-Archivlog
  enthält `ARCHIVE SUCCEEDED`; Upload, Verarbeitung und interne Verteilung sind zusätzlich bestätigt.
  Null Compilerfehler; eine gezählte bestehende `AVMutableVideoComposition`-Deprecation-Warnung.

Echte iCloud-only-Fotos, Tresor-/Berechtigungswechsel auf einem realen Gerät, Geräte-FPS,
Instruments-Leaks, physisches Falten und die rechtliche Namens-/Gestaltungsprüfung bleiben offen.
