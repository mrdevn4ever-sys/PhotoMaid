# Versteckter Tresor (E16, entschieden und gebaut)

Stand 10.10.2026. Entscheidungen des Inhabers: V1 Eingang „Heute“ 2 Sekunden halten (Einrichten über die
Einstellungen, Eintrag danach ausblendbar), V2 PIN oder Passwort wählbar plus optional Face ID/Touch ID, V3 im
iPhone-Backup (Variante A), V4 optionaler Notfallschlüssel, V5 Free 50 Medien / Pro unbegrenzt, V6 kein Täusch-Code,
V7 nur Wartezeit, V8 alle Teile sichern. Code: `Sources/PhotoMaidCore/Vault/Vault.swift` (Regeln, Tests in
`Tests/PhotoMaidCoreTests/VaultTests.swift`), `PhotoMaid/Infrastructure/Vault/`, `PhotoMaid/Features/Vault/`.
Prüfstatus: Kern-Tests PASS; iOS-Build NOT RUN; Geräteabnahme NOT RUN.

## Wunsch

Ein versteckter, mit Code geschützter Bereich in PhotoMaid. Dort kann man Fotos und Videos ablegen, in Ordner
sortieren und ordnen. Sobald ein Medium im Tresor liegt, ist es aus der Fotos-App verschwunden, taucht in PhotoMaid
weder beim Aufräumen noch in der Mediathek auf und wirkt nach außen, als gäbe es die Datei nicht mehr. Der Eingang
soll so versteckt sein, dass niemand darauf kommt.

## Harte Grenzen (nicht verhandelbar)

| Grenze | Folge für den Tresor |
|---|---|
| Löschen aus der Fotos-App geht nur über `PHAssetChangeRequest.deleteAssets`; iOS fragt **immer** selbst nach (Projektregel und Plattform) | Nach dem Ablegen im Tresor erscheint die iOS-Abfrage „… löschen?“. Lehnt man ab, liegt das Medium in Fotos **und** im Tresor. |
| Gelöschte Medien liegen 30 Tage in „Zuletzt gelöscht“ (auf allen Geräten mit iCloud-Fotos). Apps können diesen Ordner weder leeren noch öffnen | „Als gäbe es die Datei nicht mehr“ gilt erst nach 30 Tagen oder wenn du „Zuletzt gelöscht“ in der Fotos-App selbst leerst. Die App sagt das beim Ablegen klar. |
| App löschen = App-Container weg | Tresor-Inhalt ist dann **unwiederbringlich verloren** (außer im iPhone-Backup, siehe V3). |
| App-Review-Regel 2.3.1: keine versteckten oder undokumentierten Funktionen | Der Tresor muss in der App-Beschreibung stehen, und App Review bekommt in den Prüfnotizen den Weg hinein und einen Test-Code. Ein „getarnter Taschenrechner“ o. Ä. ist riskant und nicht empfohlen. Versteckt heißt also: unauffälliger Eingang für Mitbenutzer des iPhones, nicht vor Apple verborgen. |
| Kein Backend, kein CloudKit, kein Upload (Projektregel) | Kein Sync zwischen Geräten, keine Online-Wiederherstellung. |
| Bildschirmfotos/Bildschirmaufnahme lassen sich mit öffentlicher API nicht verhindern | Nur Abdecken im App-Umschalter und sofortiges Sperren im Hintergrund. |

Alternative ohne PhotoMaid: Die Fotos-App hat das Album „Ausgeblendet“ (mit Face ID geschützt, in Einstellungen ›
Apps › Fotos ganz ausblendbar). Das ist kostenlos und ohne Datenverlust-Risiko, aber nicht „aus Fotos verschwunden“.

## So würde es funktionieren

### Eingang (V1)
- Erste Einrichtung über einen sichtbaren Eintrag „Privater Tresor“ in Einstellungen (dokumentiert, App Review
  findet ihn).
- Danach Schalter „Eingang verstecken“: Der Eintrag verschwindet. Geöffnet wird dann nur noch über eine
  unauffällige Geste, z. B. **langes Drücken (2 s) auf die Versionsnummer** in Einstellungen › Hilfe. Ohne
  eingerichteten Tresor passiert bei der Geste nichts Sichtbares.
- Kein Hinweis auf den Tresor in Mitteilungen, Widgets, Kurzbefehlen, Spotlight, „Zuletzt verwendet“, Statistiken,
  Rundgang oder Diagnose-Protokollen.

### Schutz (V2, V4, V7)
- Eigener Code (6-stellige PIN oder Passwort), dazu optional Face ID (`LocalAuthentication`; braucht den
  Info.plist-Text `NSFaceIDUsageDescription`).
- Zufälliger 256-Bit-Hauptschlüssel. Er liegt nur im Schlüsselbund, verschlüsselt mit einem aus dem Code abgeleiteten
  Schlüssel (PBKDF2-SHA256 über CommonCrypto, hohe Iterationszahl). Für Face ID eine zweite Kopie im Schlüsselbund
  mit `SecAccessControl(.biometryCurrentSet)`.
- Jede Datei wird mit AES-GCM (CryptoKit) verschlüsselt und zusätzlich mit Dateischutz `.complete` gespeichert.
  Vorschaubilder ebenfalls verschlüsselt, nur im Tresor-Ordner.
- Sperrt sofort beim Wechsel in den Hintergrund; im App-Umschalter abgedeckt.
- Fehlversuche: wachsende Wartezeit (1 min, 5 min, 15 min …), keine Selbstlöschung (V7).
- **Code vergessen und Face ID nicht verfügbar = Inhalt verloren.** Keine Hintertür (V4).

### Ablegen (aus Mediathek, Feed-Aktionsleiste ⋯ oder Auswahl)
1. Originale vollständig laden (`PHAssetResourceManager`, auch aus iCloud; Live Photos mit Video-Teil, RAW+JPEG,
   bearbeitete Fassung und Original nach V8).
2. Verschlüsselt in den Tresor schreiben und per SHA-256 gegen die Quelle prüfen (wie beim Auslagern). Aufnahmedatum,
   Ort, Dateiname, Favorit und Albumnamen in der verschlüsselten Tresor-Datenbank merken.
3. Erst wenn **alle** Kopien geprüft sind: iOS-Löschabfrage für genau diese Medien. Vorher Hinweis: „Danach liegen
   sie 30 Tage in ‚Zuletzt gelöscht‘. Leere diesen Ordner in der Fotos-App, wenn sie dort auch verschwinden sollen.“
4. Entscheidungen, Später-Termine und Papierkorb-Einträge von PhotoMaid zu diesen Medien werden entfernt; dadurch
   tauchen sie nirgends mehr auf.
5. Lehnt man die iOS-Abfrage ab: Medien bleiben auch in Fotos; die App sagt das und bietet „Erneut fragen“ an.

### Im Tresor
- Raster mit Ordnern, Sortieren nach Aufnahmedatum, Ablagedatum, Name, Größe (gemessen, unbekannt ≠ 0).
- Verschieben zwischen Ordnern, umbenennen, Mehrfachauswahl.
- Ansicht für Fotos und Videos (Videos werden in eine geschützte Temp-Datei entschlüsselt, beim Sperren gelöscht).
- „Zurück in die Fotos-App“: als neues Medium mit gemerktem Datum/Ort speichern, danach optional aus dem Tresor
  entfernen.
- Teilen (über das Teilen-Menü; vorher Hinweis, dass die Datei dann den Tresor verlässt).
- Endgültig löschen im Tresor nur mit eigener Bestätigung (es gibt kein „Zuletzt gelöscht“ dafür).

### Daten und Backup (V3)
- Ablage unter `Application Support/` in einem neutral benannten Ordner, nicht in „Dateien“ sichtbar
  (`UIFileSharingEnabled` bleibt aus).
- Variante A (empfohlen): Tresor-Dateien sind im iPhone-Backup enthalten (verschlüsselt); der Schlüssel liegt im
  Schlüsselbund ohne „nur dieses Gerät“, damit ein verschlüsseltes iCloud-/Mac-Backup auf ein neues iPhone
  übertragen werden kann. Der Code bleibt nötig.
- Variante B: nur dieses Gerät (`ThisDeviceOnly`, vom Backup ausgeschlossen). Maximal privat, aber bei
  Gerätewechsel oder Defekt ist alles weg.

### Sonstiges
- Exportkonformität: `ITSAppUsesNonExemptEncryption` steht derzeit auf `false`. Mit eigener AES-Verschlüsselung
  (Standardverfahren über Apple CryptoKit, nur lokal) ist die Frage in App Store Connect neu zu beantworten; das
  fällt voraussichtlich unter eine Ausnahme, muss aber vor dem Release geprüft werden.
- Speicherplatz: Tresor-Inhalt belegt Platz in PhotoMaid (Einstellungen › Allgemein › iPhone-Speicher zeigt
  PhotoMaid größer). Die App zeigt den gemessenen Tresor-Platz an.
- Texte in allen 16 Sprachen; VoiceOver vollständig; Gestenpfeile nicht betroffen.

## Bauplan (nach deinen Entscheidungen)

| Phase | Inhalt | Prüfung |
|---|---|---|
| 1 | `PhotoMaidCore`: Tresor-Index (Ordner, Einträge, Sortierung), Sperr-/Fehlversuch-Logik, Dateinamen, Migrationsformat | Linux-Tests |
| 2 | App: Schlüssel/Code/Face ID, verschlüsselte Ablage, Ablegen mit Prüfsumme und iOS-Löschabfrage, Ansicht, Zurück in Fotos, Sperren im Hintergrund | Simulator-Tests, TestFlight |
| 3 | Ordner, Sortieren, Mehrfachauswahl, versteckter Eingang, App-Beschreibung und Prüfnotizen für App Review | TestFlight, Geräteabnahme |

Geschätzter Umfang: groß (etwa so viel wie das PDF-Studio). Erst nach Freigabe von V1–V8.

## Was du entscheiden musst

| # | Frage | Empfehlung |
|---|---|---|
| V1 | Eingang: (a) langes Drücken auf die Versionsnummer, (b) Code ins Suchfeld der Mediathek tippen, (c) nur sichtbarer Eintrag | (c) zum Einrichten, danach (a) mit „Eingang verstecken“ |
| V2 | Code: 6-stellige PIN oder freies Passwort? Face ID zusätzlich? | PIN oder Passwort wählbar, Face ID optional |
| V3 | Backup: Variante A (im iPhone-Backup, verschlüsselt) oder B (nur dieses Gerät) | A |
| V4 | Code vergessen: kein Weg zurück, oder Wiederherstellungsschlüssel zum Aufschreiben? | Wiederherstellungsschlüssel anbieten (freiwillig) |
| V5 | Free/Pro: Tresor gratis mit Grenze (z. B. 50 Medien) oder nur Pro? | Gratis bis 50 Medien, Pro unbegrenzt |
| V6 | Täusch-Code, der einen leeren Tresor zeigt? | nicht in der ersten Version |
| V7 | Viele Fehlversuche: nur Wartezeit oder Tresor löschen? | nur Wartezeit |
| V8 | Was sichern: nur die aktuelle Fassung oder alle Teile (Original + Bearbeitung, Live-Photo-Video, RAW)? | alle Teile |

## Umsetzung (Stand Build 3)

- Ablage: `Application Support/.pmv/` – `state.json` (unverschlüsselte Einstellungen inkl. mit dem Notfallschlüssel
  verpacktem Hauptschlüssel), `index.bin` (AES-GCM-verschlüsseltes Inhaltsverzeichnis), `o/` (Dateien, AES-GCM in
  1-MiB-Blöcken, Schlüssel je Datei per HKDF), `t/` (verschlüsselte Vorschaubilder). Dateischutz `.complete`.
- Hauptschlüssel: 256 Bit zufällig; mit dem Code per PBKDF2-SHA256 (600 000 Runden) verpackt im Schlüsselbund
  (`WhenUnlocked`, wandert mit verschlüsselten Backups); Face ID: Kopie mit `biometryCurrentSet`, nur dieses Gerät.
- Ablegen: Auswahl im Tresor → Rückfrage → alle Teile laden (auch iCloud), verschlüsselt schreiben, Prüfsumme gegen
  den gelesenen Strom → erst dann iOS-Löschabfrage. Abgelehnt: Hinweis „liegen noch zusätzlich in der Fotos-App“
  mit „Dort löschen“. Papierkorb- und Später-Einträge werden aufgehoben.
- Zurücklegen: zuerst mit allen Teilen (Original + Bearbeitung + Anpassungsdaten), sonst aktuelle Fassung mit
  Live-Photo-Video und RAW; Datum, Ort und Favorit wie vorher.
- Sperren: beim Wechsel in den Hintergrund und beim Schließen; Schlüssel, Inhaltsverzeichnis, Vorschaubilder und
  entschlüsselte Temp-Dateien werden verworfen. Im App-Umschalter abgedeckt.
- Nicht protokolliert (keine Diagnose-Einträge), keine Mitteilungen, kein Spotlight, keine Kurzbefehle.

## Vor dem App-Store-Release (nicht für TestFlight intern nötig)

1. App-Beschreibung: „Privater Tresor mit Code für Fotos und Videos“ erwähnen (Regel 2.3.1).
2. Prüfnotizen für App Review: „Einstellungen › Privater Tresor einrichten. Danach kann der Eintrag ausgeblendet
   werden; geöffnet wird dann durch 2 Sekunden langes Drücken auf ‚Heute‘ oben auf der Startseite.“ Test-PIN angeben.
3. Exportkonformität: Standard-AES über Apple CryptoKit nur auf dem Gerät. `ITSAppUsesNonExemptEncryption` steht auf
   `false`; vor dem Release in App Store Connect bestätigen, dass die Ausnahme greift (sonst Wert anpassen).
