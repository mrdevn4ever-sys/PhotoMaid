# Privacy-Manifest-Prüfung, 16.10.2026

Der Nutzer hat Apple-Meldungen **ITMS-91064 für Builds 8, 9 und 10** bestätigt. Ein erfolgreicher
Transport zu App Store Connect und ein grüner Upload-Workflow widerlegen diese Meldungen nicht.
Die frühere Einschätzung, `NSPrivacyTracking = true` mit leerer Domainliste sei unproblematisch,
war falsch: [Apple TN3181](https://developer.apple.com/documentation/technotes/tn3181-debugging-invalid-privacy-manifest)
nennt genau diese Kombination ausdrücklich als ungültig.

## Tatsächlich untersucht

Alle `.xcprivacy`-Dateien im Projekt und in den vorhandenen Swift-Package-Checkouts, außerdem
die offiziellen binären SDK-ZIPs für die **exakten in Build 10 aufgelösten Versionen**. Die
SHA-256-Werte beider ZIPs stimmen mit den Checksummen ihrer offiziellen `Package.swift` überein.
Es wurden keine SDK-Dateien verändert.

| Herkunft | Dateien | Tracking / Domains | Befund |
|---|---:|---|---|
| App: `PhotoMaid/Resources/PrivacyInfo.xcprivacy` vor Korrektur | 1 | `true` / `[]` | **FAIL:** laut TN3181 ungültig |
| GoogleMobileAds 13.9.0, Gerät und Simulator | 2 | beide Schlüssel fehlen | **PASS:** keine widersprüchlichen Tracking-Domains |
| UserMessagingPlatform 3.1.0, Gerät und Simulator | 2 | beide Schlüssel fehlen | **PASS:** keine widersprüchlichen Tracking-Domains |
| swift-crypto 4.5.2, sieben Quell-/Hilfstargets | 7 | `false` / `[]` | **WARN:** leeren Domains-Schlüssel besser entfernen; diese Abhängigkeit wird laut `Package.swift` nur unter Linux gelinkt |
| swift-asn1 1.7.3 und PhotoMaidCore-Quellen | 0 | kein Manifest | keine weiteren Fundstellen; keine zusätzliche iOS-Tracking-Abhängigkeit |

Die SDK-Hypothese „Domains gesetzt, aber Tracking false“ hat sich in **keiner der zwölf gefundenen
Dateien** bestätigt. Stattdessen gibt es einen belegten ungültigen Eintrag im eigenen App-Manifest.
Die maschinenlesbare [Dateiliste mit Manifest-Hashes und SDK-Checksummen](privacy-manifests-20261016.json)
enthält die einzelnen Fundstellen und den Vorher-/Nachher-Befund.

## Bezug zu Build 10 und Grenzen

Der [bestehende Lauf 38808372020](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38808372020)
verwendet Commit `de90f1d67c2dbe753f5da6c012ae6feb9172b277`. Sein `gym.log` löst GoogleMobileAds 13.9.0,
UserMessagingPlatform 3.1.0, swift-crypto 4.5.2 und swift-asn1 1.7.3 auf. Der protokollierte
`CpResource`-Schritt kopiert `PhotoMaid/Resources/PrivacyInfo.xcprivacy` direkt nach
`PhotoMaid.app/PrivacyInfo.xcprivacy`. Der Stand dieses Commits enthält `true` und die leere Liste.

Das vorhandene Artefakt `testflight-report` enthält nur `gym.log`, `unit-tests.log`, `ci-report.md`
und `fastlane/report.xml`, **keine IPA und kein xcarchive**. Deshalb wurde die damals hochgeladene
IPA nicht direkt untersucht. Ein zusätzlicher Fehler im fertigen Bundle ist damit nicht ausgeschlossen;
auch die Quelldateien von Build 8 und 9 sind hier nicht unabhängig rekonstruiert worden.
Der Apple-Verarbeitungsstatus der alten Builds wurde nicht separat abgefragt. Der neue Build 11
wurde nach der Korrektur bis zum erfolgreichen Abschluss der Apple-Verarbeitung verfolgt (unten).

## Lokale Korrektur und Schutz vor erneutem Upload desselben Fehlers

- `NSPrivacyTracking` bleibt wahr, passend zur bestehenden AdMob-/ATT-Integration. Die App deklariert
  jetzt den bekannten AdMob-Host `googleads.g.doubleclick.net` statt einer leeren Liste.
  [Googles SDK-Team nennt diesen Host für AdMob](https://groups.google.com/g/google-admob-ads-sdk/c/FCH97KHK6Eg).
  Er kommt auch als Hostname im per Prüfsumme verifizierten Geräte-SDK 13.9.0 vor.
- Keine erfundenen Tracking-Domains, kein Umschalten auf „kein Tracking“ und kein Patchen signierter SDKs.
  Die Liste beansprucht ohne Laufzeitmessung keine Vollständigkeit für dynamische Anzeigeninhalte.
- `scripts/ci/check_privacy_manifests.py` prüft Quelldateien, Verzeichnisse, SDK-ZIPs und IPAs rein lesend:
  Boolean-Typ, Domainliste, Hostnamen, widersprüchliche Kombinationen und doppelte Plist-Schlüssel.
  Fehler liefern Exitcode 1; `false` mit leerer Liste liefert einen gesonderten Hinweis.
- Der weiterhin ausschließlich manuell startbare TestFlight-Workflow prüft zunächst die Quelle.
  Fastlane prüft **vor `upload_to_testflight` die tatsächlich exportierte IPA**, einschließlich aller
  eingebetteten Framework- und Ressourcen-Manifeste und des vorhandenen App-Manifests.
  Der Bericht `build/privacy-manifests.json` wird im vorhandenen TestFlight-Berichtsartefakt aufbewahrt.
- Domaindeklarationen wirken sich laut Apple auch auf Netzsperren bei verweigerter ATT aus.
  Anzeigenladen mit erlaubter und verweigerter ATT sowie zusätzliche tatsächlich kontaktierte Hosts
  müssen vor einer Geräteabnahme geprüft werden. Es wurden hier keine Anzeigenanfragen erzeugt.

## Neuer TestFlight-Build 11

Auf ausdrücklichen Auftrag wurde Version 1.0, Build 11 aus Commit
`3e91e3a0dd22b4944edf94bca3055285241af8cf` erstellt. Der [Lauf 38952167636](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38952167636)
bestand am 16.10.2026 vollständig: 42 native Tests, Release-Archiv, Signierung und Prüfung der drei
Manifeste der tatsächlich exportierten IPA. Der [unveränderte Bericht](privacy-manifests-build11.json)
enthält Pfade, SHA-256-Werte und Tracking-Deklarationen; keine Fehler oder Hinweise.

Upload um 19:20:43 UTC, erfolgreiche Apple-Verarbeitung um 19:23:17 UTC und anschließende
Verteilung an interne Tester sind im Fastlane-Protokoll bestätigt. Die Lane wartet jetzt ausdrücklich
auf die Verarbeitung statt nur auf den Transfer. Dies ersetzt keine ATT-/Werbeabnahme auf dem Gerät
und keine App-Review-Freigabe. Die alten IPAs bleiben mangels Archiv ununtersucht.

## Prüfstatus

| Prüfung | Status | Ergebnis |
|---|---|---|
| Ursprüngliches Build-10-App-Manifest | FAIL, reproduziert | Prüfer erkennt `true` plus leere Liste |
| Korrigierte App, beide offiziellen SDK-ZIPs, Swift-Checkouts | PASS mit sieben Hinweisen | zwölf Dateien, kein Tracking-Konsistenzfehler nach Korrektur |
| Acht Prüfer-Regressionen | PASS | unter anderem eingebettetes fehlerhaftes Framework trotz korrektem App-Manifest, XML/Binär-Plist, fehlendes App-Manifest |
| Ruby/Fastlane-Ausführung | PASS | lokale Syntaxprüfung und vollständige Beta-Lane auf macOS einschließlich Apple-Verarbeitung |
| Ursprüngliche Build-8–10-IPAs / xcarchives | NOT RUN | Originale nicht archiviert |
| Neue exportierte Build-11-IPA | PASS | drei Manifeste geprüft, keine Fehler oder Hinweise; Manifest-Hashes im Bericht |
| ATT-/Werbeverhalten auf echtem Gerät | NOT RUN | keine Geräteabnahme |
| Neuer TestFlight-Upload und Apple-Verarbeitung | PASS | Version 1.0, Build 11 erfolgreich verarbeitet und an interne Tester verteilt |

Lokale Wiederholung:

```sh
python3 -m unittest discover -s scripts/ci -p 'test_check_privacy_manifests.py' -v
python3 scripts/ci/check_privacy_manifests.py PhotoMaid/Resources/PrivacyInfo.xcprivacy
python3 scripts/ci/check_privacy_manifests.py build/PhotoMaid.ipa --require-app-manifest --json-output build/privacy-manifests.json
```

Die letzte Zeile setzt eine tatsächlich vorhandene exportierte IPA voraus. Diese Prüfung ersetzt
keine Apple-Validierung und keine vollständige Prüfung sämtlicher Privacy-Manifest-Kategorien.
