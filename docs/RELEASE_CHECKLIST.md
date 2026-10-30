# GaleriQ – Release-Checkliste (Stand 30.10.2026)

Drei Teile: was bereits erledigt ist, **Prompts für deinen Agenten** (Browser: AdMob, App Store Connect, GitHub)
und **Handarbeit**, die nur du machen kannst.

## 1. Erledigt (Claude, 30.10.2026)

- **Werbung ohne Tracking-Erlaubnis:** Das Privacy-Manifest meldete AdMobs Host `googleads.g.doubleclick.net`
  als Tracking-Domain. iOS lässt solche Anfragen ohne ATT-Erlaubnis scheitern – keine Werbung, kein Bonus, keine
  Tresor-Ordner für alle, die Tracking ablehnen. Jetzt `NSPrivacyTracking = false` ohne Domain
  (`docs/PRIVACY_MANIFEST_AUDIT.md`). Neuer CI-Schalter `tracking: deny` prüft das.
- **SKAdNetwork:** Googles vollständige Liste (50 Einträge) in `project.yml`.
- **Nie Testwerbung im Store:** Der TestFlight-Workflow bricht ohne alle vier echten AdMob-IDs ab
  (Ausnahme nur mit `allow_test_ads` für rein interne Builds).
- **Store-Texte für 16 Sprachen:** `app-store/metadata/<Sprache>/` (Name, Untertitel, Keywords, Werbetext,
  Beschreibung, URLs), erzeugt und geprüft mit `scripts/store/metadata_texts.py`. Texte für den In-App-Kauf:
  `app-store/metadata/iap-pro.md`. Upload aller Texte per TestFlight-Workflow mit der Aufgabe `store-texts` (Bestätigung `TEXTE`).
- **Websites:** `mrdevn4ever-sys.github.io` (Startseite, Android-Datenschutz) und die Datenschutzseite heißen
  GaleriQ (früher PhotoMaid). `app-ads.txt` liegt auf der Domain-Wurzel.
- **App-Review-Text:** `docs/APP_REVIEW_NOTES.md`.
- **Name GaleriQ** (30.10.2026, „Arrumo“ ist auf Google Play vergeben): App, 16 Sprachen, Websites; Tresor-Rad als „Q“.
- **Werbung bei abgelehntem Tracking geprüft:** CI-Lauf 41138933419 – „Ask App Not to Track“, danach lädt und
  erscheint die Start-Werbung.
- **In App Store Connect eingetragen** (TestFlight-Lauf 41141922451, von App Store Connect zurückgelesen): Name und
  Untertitel, Beschreibung, Keywords, Werbetext, Support-/Marketing-/Datenschutz-URL und Copyright in allen 16 Sprachen;
  App-Prüfungsinformationen mit dem Review-Text angelegt (ohne Kontakt).

## 2. Noch durch Claude

1. Volle CI auf dem GaleriQ-Stand.
2. Store-Screenshots und 2 Clips mit dem Schriftzug „GaleriQ“ neu aufnehmen (`app-store/en`).
3. Screenshot der Kaufseite für die Prüfung des In-App-Kaufs.
4. Sobald die AdMob-Secrets gesetzt sind: Build 30 nach TestFlight (nur interne Tester).

## 3. Prompts für deinen Agenten

### Prompt A – AdMob einrichten und IDs in GitHub hinterlegen

```
Du arbeitest in meinem Google-AdMob-Konto und in meinem GitHub-Repo mrdevn4ever-sys/PhotoMaid.
Ziel: Werbung für meine iPhone-App „GaleriQ“ (Bundle-ID com.mrdevn4ever.photomaid) einrichten.
Gib keine Zahlungs-, Steuer- oder Bankdaten ein, ändere keine Kontoeinstellungen, lösche nichts,
aktiviere keine Vermittlung (Mediation). Frag mich, wenn etwas unklar ist.

1. AdMob › Apps › App hinzufügen: Plattform iOS, „Ist die App in einem App-Store?“ → Nein (noch nicht
   veröffentlicht), App-Name „GaleriQ“. Notiere die App-ID (Format ca-app-pub-XXXXXXXXXXXXXXXX~NNNNNNNNNN).
2. In dieser App drei Anzeigenblöcke anlegen und je die ID notieren (Format ca-app-pub-…/NNNNNNNNNN):
   - Format „App-Start“ (App open), Name „GaleriQ – App-Start“
   - Format „Nativ erweitert“ (Native advanced), Name „GaleriQ – Feed-Karte“, Standardeinstellungen
   - Format „Mit Prämie“ (Rewarded), Name „GaleriQ – Belohnung“, Prämie: Menge 1, Artikel „Bonus“,
     serverseitige Bestätigung aus
3. Datenschutz & Mitteilungen:
   - „Europäische Vorschriften“ (DSGVO): Mitteilung für die App GaleriQ erstellen, Sprachen: alle verfügbaren,
     Schaltflächen „Einwilligen“, „Nicht einwilligen“ und „Optionen verwalten“ aktivieren, Datenschutz-URL
     https://mrdevn4ever-sys.github.io/photomaid-website/ , VERÖFFENTLICHEN.
   - „IDFA-Erläuterung“ (iOS): Mitteilung für GaleriQ erstellen und veröffentlichen.
   - „US-Bundesstaaten-Vorschriften“: Mitteilung für GaleriQ erstellen und veröffentlichen.
4. Einstellungen › Kontoinformationen: Publisher-ID ablesen. Prüfe, ob sie „pub-1549279515168572“ ist
   (so steht es in https://mrdevn4ever-sys.github.io/app-ads.txt). Wenn nicht: mir die richtige ID melden.
5. GitHub › mrdevn4ever-sys/PhotoMaid › Settings › Secrets and variables › Actions › Repository secrets:
   vier Secrets anlegen (bestehende gleichnamige überschreiben):
   - PM_ADMOB_APP_ID      = App-ID aus Schritt 1
   - PM_ADMOB_APP_OPEN_ID = ID „GaleriQ – App-Start“
   - PM_ADMOB_NATIVE_ID   = ID „GaleriQ – Feed-Karte“
   - PM_ADMOB_REWARDED_ID = ID „GaleriQ – Belohnung“
   Keine der IDs darf mit ca-app-pub-3940256099942544 beginnen (das sind Googles Test-IDs).
6. Melde mir: die vier IDs, ob die drei Mitteilungen veröffentlicht sind und die Publisher-ID.
```

### Prompt B – App Store Connect vorbereiten (ohne Einreichung)

```
Du arbeitest in App Store Connect für meine App mit der Bundle-ID com.mrdevn4ever.photomaid
(neuer Name „GaleriQ“, früher PhotoMaid). NICHT zur Prüfung einreichen, NICHT veröffentlichen, keine Builds
löschen, Bundle-ID und SKU nicht ändern, keine Verträge, Bank- oder Steuerdaten bearbeiten.
Texte und Dateien liegen im privaten Repo mrdevn4ever-sys/PhotoMaid, Branch claude/experiment-artifact-design.

1. App-Informationen:
   - Name und Untertitel sind in allen 16 Sprachen schon eingetragen (z. B. „GaleriQ: Fotos aufräumen“) – nur prüfen.
   - Kategorie: Primär „Foto & Video“, sekundär „Dienstprogramme“.
   - Inhaltsrechte: „Nein, enthält keine Inhalte Dritter, zeigt oder greift nicht darauf zu“.
   - Altersfreigabe: Fragebogen wahrheitsgemäß – keine Gewalt, keine sexuellen Inhalte, kein Glücksspiel,
     kein freier Webzugang, keine Nutzerinhalte/Chats; die App enthält Werbung (Google). Erwartet: 4+.
2. Preise und Verfügbarkeit: Preis kostenlos. Verfügbarkeit: alle Länder AUSSER China (Festland).
3. App-Datenschutz:
   - Datenschutz-URL: https://mrdevn4ever-sys.github.io/photomaid-website/
   - Datenerhebung „Ja“. Nur die Gratis-Version mit Google AdMob erhebt Daten. Eintragen:
     | Datentyp | Zwecke | Mit Nutzer verknüpft | Tracking |
     |---|---|---|---|
     | Kennungen › Geräte-ID | Drittanbieter-Werbung, Analysen | Ja | Ja |
     | Nutzungsdaten › Werbedaten | Drittanbieter-Werbung, Analysen | Ja | Ja |
     | Nutzungsdaten › Produktinteraktion | Drittanbieter-Werbung, Analysen | Ja | Ja |
     | Standort › Grober Standort | Drittanbieter-Werbung, Analysen | Ja | Ja |
     | Diagnose › Leistungsdaten | Drittanbieter-Werbung, Analysen | Ja | Ja |
     | Diagnose › Absturzdaten | Analysen | Nein | Nein |
     Alles andere (Fotos, Kontakte, Kontodaten, Käufe usw.) „wird nicht erhoben“.
     Die Fotos verlassen das Gerät nie; Käufe laufen nur über Apple.
4. Version 1.0 (App Store):
   - Beschreibung, Keywords, Werbetext, URLs, Copyright und die Prüfungsnotizen sind schon eingetragen – nichts
     davon ändern.
   - App-Prüfungsinformationen: Anmeldung erforderlich → Nein. Kontakt (Vorname, Nachname, Telefon mit +41…,
     E-Mail): mich fragen und eintragen.
   - Freigabe der Version: „Diese Version manuell freigeben“.
5. In-App-Käufe › Neu: Typ „Nicht-verbrauchbar“, Referenzname „GaleriQ Pro“, Produkt-ID exakt
   com.mrdevn4ever.photomaid.pro (ist sie schon vorhanden: nur prüfen und ergänzen).
   - Preis: [MEIN PREIS – frag mich], Verfügbarkeit wie die App, Familienfreigabe: [frag mich].
   - Lokalisierungen: Anzeigename „GaleriQ Pro“ und Beschreibung je Sprache aus
     app-store/metadata/iap-pro.md.
   - Prüfungs-Screenshot: später (ich liefere ihn); Prüfungsnotiz: „Unlocks GaleriQ Pro: no ads, unlimited
     deleting, new vault folders without rewarded videos. Settings > GaleriQ Pro.“
   - NICHT separat einreichen; der Kauf wird später mit Version 1.0 eingereicht.
6. Melde mir: was eingetragen ist, was fehlt und jede Fehlermeldung wörtlich.
```

### Prompt C – Store-Bilder hochladen (erst wenn Claude sie neu aufgenommen hat)

```
App Store Connect › GaleriQ › Version 1.0 › Englisch (USA) › iPhone 6,9-Zoll-Display:
1. Alle vorhandenen Screenshots und App-Vorschauen entfernen (nur in dieser Version, nur Bilder/Videos).
2. Screenshots aus app-store/en/screenshots (Repo mrdevn4ever-sys/PhotoMaid, Branch
   claude/experiment-artifact-design) in der Reihenfolge der Dateinamen 01 … 10 hochladen.
3. App-Vorschauen: 01-review.mp4 und 02-photo-games.mp4 aus app-store/en/previews, Posterbild je
   01-review-poster.png bzw. 02-photo-games-poster.png.
4. Nicht einreichen. Melde mir Fehlermeldungen wörtlich.
```

## 4. Handarbeit (nur du)

- [x] **H1 GitHub-Abrechnung reparieren** (erledigt 30.10.2026).
- [ ] **H2 Name absichern:** „GaleriQ“ direkt im App Store und in Google Play suchen, Markenrecherche (Swissreg,
      TMview, WIPO Global Brand Database; Klassen 9 und 42) und galeriq.app kaufen (am 30.10.2026 frei, .com vergeben).
- [ ] **H3 App Store Connect, Verträge:** Vertrag „Kostenpflichtige Apps“ mit Bankkonto und Steuerformular
      (W-8BEN) – ohne ihn lädt der In-App-Kauf nicht. EU-Händlerstatus (DSA) angeben: Adresse, Telefon und E-Mail
      werden im EU-App-Store öffentlich angezeigt.
- [ ] **H4 Entscheidungen für Prompt B:** Preis von GaleriQ Pro, Familienfreigabe ja/nein, Kontakt für die Prüfung.
- [ ] **H5 AdMob-Konto:** Zahlungs- und Steuerdaten, Identitätsprüfung.
- [ ] **H6 Gerätetest Build 30:** Testkauf (Sandbox) und „Käufe wiederherstellen“; Werbung mit Tracking
      „Erlauben“ **und** „App bitten, nicht zu tracken“; Tresor; Löschen. Eigene Werbung nie antippen.
- [ ] **H7 Einreichen:** Version 1.0: Build 30 wählen, In-App-Kauf „GaleriQ Pro“ anhängen, „Zur Prüfung
      einreichen“. Nach der Freigabe selbst veröffentlichen.
- [ ] **H8 Nach dem Livegang:** In AdMob die App mit dem App-Store-Eintrag verknüpfen (App-Einstellungen ›
      App-Store-Details); app-ads.txt wird dann geprüft.
