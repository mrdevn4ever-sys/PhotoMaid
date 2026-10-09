# Bauen, testen und TestFlight – nur mit Windows

Kein Mac nötig. Code wird auf Windows bearbeitet (Claude Code/Codex), gebaut wird auf GitHub-macOS-Runnern.
**Kein Workflow startet von selbst** (`workflow_dispatch`): Ein Push oder Pull Request verbraucht keine
Actions-Minuten. macOS-Minuten zählen bei GitHub zehnfach und sind über dem Freikontingent kostenpflichtig
(Entscheidung E11).

## Workflows

| Datei | Was | Wann |
|---|---|---|
| `.github/workflows/ci.yml` | Kern-Tests (Linux) + iOS-Build + Unit-Tests auf dem Simulator; optional UI-Tests/Screenshots | manuell: Actions › CI › „Run workflow“ |
| `.github/workflows/testflight.yml` | Unit-Tests, Archiv, Signierung, Upload zu TestFlight | manuell: Actions › TestFlight › „Run workflow“ |

Beide erzeugen einen **CI-Bericht** (`ci-report.md`, auch in der Job-Zusammenfassung): Compilerfehler mit
`Datei:Zeile`, fehlgeschlagene Tests, Concurrency-Warnungen. Der nächste Korrekturdurchlauf liest ihn so:

```sh
gh api repos/mrdevn4ever-sys/photomaid/actions/runs?per_page=1          # letzter Lauf
gh api repos/mrdevn4ever-sys/photomaid/actions/runs/<RUN_ID>/artifacts  # Artefakt „ios-build-report“
```

## Einmalige Einrichtung (alles im Browser)

1. **Apple Developer Program** (kostenpflichtig, 99 USD/Jahr) – Pflicht für TestFlight.
2. **App-ID** anlegen: developer.apple.com › Certificates, Identifiers & Profiles › Identifiers ›
   „App IDs“, Bundle-ID z. B. `ch.deinname.photomaid` (endgültig, später nicht änderbar).
   Capability „In-App Purchase“ ist Standard.
3. **App in App Store Connect** anlegen (Meine Apps › „+“), dieselbe Bundle-ID, Primärsprache Deutsch.
4. **In-App-Kauf**: App › Monetarisierung › In-App-Käufe › „Nicht verbrauchbar“, Produkt-ID z. B.
   `photomaid.pro.lifetime`, Preis wählen (E4), Beschreibung in den Sprachen.
5. **API-Schlüssel**: App Store Connect › Benutzer und Zugriff › Integrationen › App Store Connect API ›
   Teamschlüssel „+“, Rolle **App-Manager** (für automatische Signierung: **Admin**). Die `.p8`-Datei kann nur
   einmal geladen werden. Notiere Key-ID und Issuer-ID.
6. **GitHub** › Repository › Settings › Environments › „New environment“ `testflight`
   (optional „Required reviewers“ = du, dann startet ein Upload nur nach deiner Freigabe).
   Darin **Secrets**:

   | Secret | Inhalt | Windows-Befehl |
   |---|---|---|
   | `ASC_KEY_ID` | Key-ID des API-Schlüssels | – |
   | `ASC_ISSUER_ID` | Issuer-ID | – |
   | `ASC_KEY_P8_BASE64` | `.p8`-Datei Base64 | PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8"))` |
   | `PM_TEAM_ID` | Team-ID (10 Zeichen, Membership-Seite) | – |

   und **Variablen** (nicht geheim): `PM_BUNDLE_ID`, `PM_PRO_PRODUCT_ID`, `PM_PRIVACY_POLICY_URL`.

7. Nur falls die automatische Signierung nicht geht (Variante B): Distributionszertifikat und App-Store-Profil.
   Auf Windows ohne Mac:
   ```powershell
   # OpenSSL ist bei Git für Windows dabei: "C:\Program Files\Git\usr\bin\openssl.exe"
   openssl genrsa -out dist.key 2048
   openssl req -new -key dist.key -out dist.csr -subj "/emailAddress=du@example.com/CN=PhotoMaid Dist/C=CH"
   # dist.csr im Developer-Portal unter Certificates › „Apple Distribution“ hochladen, dist.cer laden
   openssl x509 -inform DER -in distribution.cer -out dist.pem
   openssl pkcs12 -export -inkey dist.key -in dist.pem -out dist.p12 -legacy
   ```
   Profil: Profiles › „App Store Connect“ › App-ID › Zertifikat wählen › `.mobileprovision` laden.
   Secrets: `DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD`, `PROVISIONING_PROFILE_BASE64` (Base64 wie oben).
   `dist.key` und `dist.p12` danach sicher verwahren, **nie** ins Repository.

## Ablauf pro Testbuild

1. Änderungen pushen (verbraucht nichts).
2. Actions › **CI** › Run workflow → grün? Sonst `ci-report.md` an Claude Code geben.
3. Actions › **TestFlight** › Run workflow (Text „Was testen?“ eingeben).
   Buildnummer = letzte TestFlight-Nummer + 1 (automatisch).
4. Nach 5–30 Minuten Verarbeitung bei Apple: TestFlight-App auf dem iPhone › PhotoMaid › Installieren
   (interne Tester: App Store Connect › TestFlight › Interne Gruppe, dich selbst hinzufügen).
5. Auf dem iPhone prüfen (Prüfliste `docs/QA_MATRIX.md`). Probleme:
   - Absturz: TestFlight sammelt Absturzberichte (App Store Connect › TestFlight › Abstürze).
   - In der App: Einstellungen › Hilfe › **Diagnose teilen** (lokales Protokoll dieser App + MetricKit-Berichte,
     ohne Medien, Dateinamen oder IDs) – Datei an Claude Code geben.

## Was die Workflows nie tun

- keinen Lauf selbst starten, nichts zusammenführen, nichts extern verteilen (`distribute_external: false`);
- Schlüssel ins Log schreiben (Secrets werden maskiert, temporäre Dateien am Ende gelöscht);
- Zertifikate, Profile oder `.p8` dauerhaft speichern (temporärer Schlüsselbund, im letzten Schritt entfernt).
