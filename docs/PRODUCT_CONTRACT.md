# PhotoMaid – Produktvertrag (iOS)

Verbindliche Kurzfassung des Auftrags. Bei Widerspruch gilt: (1) Sicherheit und tatsächlich
verfügbare öffentliche Apple-APIs, (2) dieser Vertrag, (3) Mockup-Tafeln, (4) alte Android-Unterlagen.

## Produkt

Lokaler Ordnungs- und Aufräumassistent für Fotos, Videos, Screenshots und ausdrücklich
freigegebene Ordner. Kein Server, kein Konto, kein CloudKit, kein Upload, keine KI/ML/Vision,
keine privaten APIs, keine automatische Löschung.

## Entscheidungs-Feed (FEST)

| Finger | Aktion | Persistiert | Danach |
|---|---|---|---|
| hoch | Behalten | `kept` | nächstes Medium |
| links | Papierkorb | `markedForCleanup` (PhotoMaid-Papierkorb, nichts gelöscht) | nächstes Medium |
| rechts (gerade/schräg unten) | Später | `later` + Standardtermin (Vorgabe 2 Tage, einstellbar 1/2/3/7) | nächstes Medium + Pille „In 2 Tagen wieder · Ändern“ |
| schräg rechts oben | Später, Datum wählen | `later` + Termin aus Drehrad (Tage/Wochen/Monate) oder Kalender | nächstes Medium + Drehrad-Sheet; Abbrechen = Standardtermin |
| runter | Vorheriges | nichts | vorheriges Medium |

- Nichts tun = keine Entscheidung. Passive Navigation, Scrolloffset, onAppear/onDisappear,
  Rotation, Hintergrund, Videoende, programmatisches Springen erzeugen nie Entscheidungen.
- Eine Geste = höchstens ein Schritt. Jeder Commit: Item-ID, erwartete Revision, Command-ID, Aktion.
- Korrektur früherer Items: atomarer Ersatz + Verlaufseintrag `correction`. Gleiche Entscheidung
  erneut: `unchanged`, keine Zähler.
- Nicht geladene Vorschau (z. B. nur iCloud) kann nicht entschieden werden; „Ohne Entscheidung überspringen“.
- „Behalten“ setzt keinen Apple-Favoriten.

## Später 2.0

- Swipe rechts setzt sofort den Standardtermin (Pille mit „Ändern“, blendet nach ~2,4 s aus);
  schräg rechts oben öffnet das Drehrad. Ein Später hat damit immer einen Termin.
  Die Pille gehört zum zurückgestellten Item; eine neue Entscheidung schließt sie.
- Termin = lokaler Kalendertag (`LocalDay`, gregorianisch), Audit = UTC-Instant. Kalenderarithmetik.
- Pro Item max. ein aktiver Termin. Vor Fälligkeit aus normalen Queues ausgeschlossen, ab Fälligkeit
  nur im Wieder-fällig-Bereich. Fällig + erneut rechts ohne Datum: nur Session-Skip, Termin bleibt.
- Behalten/Vormerken löst Termin im selben Commit auf. Zurückstellung entfernen löscht nichts.

## Undo

Gemeinsame Command-Historie (max. 200). Undo stellt exakt den vorherigen Zustand her, überschreibt
keine neuere Entscheidung (Revisionsprüfung), Terminwahl gehört zur Später-Aktion (`amends`).
Undo vor Systemlöschung ≠ Wiederherstellung nach Systemlöschung (kein In-App-Restore).

## Bereinigung

Entdecken → Entscheiden → Auswahl prüfen → Bestätigen → Provider-Operation → Abgleichen → Verlauf.
Fotos/Videos: `PHAssetChangeRequest.deleteAssets` (System-Bestätigung, „Zuletzt gelöscht“).
Dateien: nur „Endgültig löschen“ mit eigener Bestätigung (kein universeller iOS-Papierkorb).
Gemischter Korb wird nach Provider getrennt bestätigt. Operation-Journal vor jeder Systemoperation.

## Free / Pro / Rewarded

- Free: alles ansehen/sortieren/Später/Undo/Verlauf; 15 bestätigte Bereinigungen je lokalem Tag.
- Pro (Non-Consumable, RevenueCat + Apple-IAP): unbegrenzt, exakte Duplikate, erweiterte
  Datei-/Speicherwerkzeuge, dauerhafte Routinen, keine Werbung. Preis nur aus dem Store.
- Rewarded (freiwillig): 30 reale Minuten Pro-Werkzeuge, max. 1× pro lokalem Tag, nur nach
  SDK-Reward-Callback, Tageslimit bleibt 15, Routinen nur einmaliger Testscan.

## Nordstern

HOCH BEHALTEN. LINKS PAPIERKORB. RECHTS SPÄTER (SCHRÄG HOCH: DATUM WÄHLEN). RUNTER ZURÜCK.
