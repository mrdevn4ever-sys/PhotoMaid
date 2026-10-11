# Tresor-Sicherheit: Stand der Isolation (noch ohne Build, NICHT freigegeben)

Stand: 11.10.2026. Branch `claude/vault-isolation-20261011`, Grundlage `24b41a0` (TestFlight Build 4) plus die
Sicherheitsbausteine aus PR #9 (`VaultSecurity.swift`, `VaultSecurityTests.swift`).

## Verbindlicher Auftrag

Was im Tresor liegt, darf in PhotoMaid nirgendwo ausserhalb des Tresors auftauchen: nicht unter Fotos, Bereinigen,
Verlauf, Bearbeitet, Collage, Film, GIF, Suche, Favoriten, Ausgeblendet, Auswahlkorb, Schnellzugriffen,
Dateivorschauen oder einer öffentlichen Sicherung. Gespeicherte Verweise, Vorschauen und abgeleitete Ausgaben sind
einzubeziehen. Ein Titel oder leerer Platzhalter darf die Existenz des privaten Elements ebenfalls nicht verraten.

## Prüfung des Berichts zu PR #9 (Ergebnis)

Der Bericht trifft zu: In Build 3/4 galt „nur im Tresor“ nur, solange iOS das Löschen in der Fotos-App bestätigt.
Echte Lücken waren:

- Abgelehnte iOS-Löschabfrage: Das Original blieb in PhotoMaid überall sichtbar (Fotos, Alben, Bereinigen, Suche …).
- Aus „Zuletzt gelöscht“ zurückgeholte Originale erschienen wieder.
- Spuren: Verlauf, Auswahlkorb, Collage-/Film-Entwürfe, „Bearbeitet“, öffentliche Sicherung, Schlagwort-Zähler,
  Analyse-Cache (inkl. erkanntem Text), Vorschau-Caches.
- Nach dem Sperren konnten verspätete Aufgaben noch öffnen bzw. Klartext-Temp-Dateien anlegen; ein Entsperren, das
  erst nach dem Sperren fertig wurde, öffnete den Tresor wieder.
- Inhaltsverzeichnis: Änderungen galten im Speicher, bevor sie gespeichert waren; Dateien wurden vor dem Speichern
  gelöscht. Schlüsselbund: erst löschen, dann neu anlegen. Einrichten überschrieb vorhandene Tresor-Reste.
- „Zurück in Fotos“ mit vereinfachtem Ergebnis löschte trotzdem das vollständige Tresor-Original.
- Sichtschutz deckte verschachtelte Ansichten (Betrachter, Blätter, Teilen-Fenster) im App-Umschalter nicht ab.

## Umgesetzt (dieser Branch)

1. **Verbergen-Liste** (`VaultConcealment`, `VaultConcealmentSet`): gesalzene SHA-256-Prüfsummen der Original-Kennungen,
   auch bei gesperrtem Tresor lesbar, erst gespeichert, dann gültig; unlesbare Datei wird nie überschrieben.
   Angewendet an allen PhotoKit-Zugängen: `PhotoLibraryService` (Mediathek, Zähler, Alben inkl. Anzahl und
   Titelbild-Datum, neue Medien, Albummitglieder, `assets(ids:)`, `phAsset`), Vorschaubilder (`ThumbnailLoader`
   inkl. verspäteter Ergebnisse), `PreviewPipeline` (Bild, Video, Vorladen), GIF-Wiedergabe. Existenzprüfungen
   (Abgleich, Löschnachprüfung) und der Tresor selbst nutzen getrennte Zugänge (`existingIDs`,
   `phAssetIncludingConcealed`) – ein verborgenes Original gilt nie als „entfernt“.
2. **Sofort verbergen beim Ablegen** – vor der iOS-Löschabfrage, unabhängig von deren Ausgang. Danach
   `AppModel.applyVaultConcealment`: Papierkorb-/Später-Einträge aufheben, aus Auswahlkorb, Collage- und
   Film-Entwürfen nehmen, Analyse-Ergebnisse (inkl. erkanntem Text) verwerfen, Vorschau-Caches leeren, Mediathek und
   Lesemodell neu laden. Lesemodell filtert Papierkorb, Später und Verlauf; öffentliche Sicherung lässt
   Entscheidungen, Schlagwörter, Notizen, Auswahlkorb und Ausgeblendet-Liste der Tresor-Medien weg. Schlagwort-Zähler
   zählen sie nicht mit; „Bearbeitet“ zeigt Ergebnisse im Tresor nicht und sagt nichts über Originale im Tresor.
3. **Dauerhafte Original-Kennung** (`VaultItem.originalID`, nur im verschlüsselten Index). Einträge aus Build 3/4
   werden beim Öffnen übernommen, solange `sourceID` noch bekannt ist – nie geraten. `syncConcealment` gleicht die
   Liste beim Öffnen mit dem Index ab (auch nach beschädigter Liste).
4. **Abgeleitete Kopien** (Bearbeitungen, Collagen, Filme, GIFs, auch über mehrere Stufen): `EditRecord.sources`
   speichert alle Quellen neuer Ergebnisse; beim Ablegen bietet die Rückfrage an, diese Kopien mitzunehmen
   („Mit Kopien ablegen“ / „Ohne Kopien“).
5. **Sitzung** (`VaultSessionFence`): Sperren widerruft; Vorschaubilder, Fotos, Videos, Teilen, Ablegen, Zurücklegen
   und Index-Änderungen prüfen die Sitzung. Verspätete Klartext-Temp-Dateien werden verworfen. Ein Entsperren, das
   nach einer Sperre fertig wird, öffnet nicht (`UnlockResult.cancelled`, kein Fehlversuch).
6. **Speichern zuerst** (`VaultTransaction`): Index-Änderungen gelten erst nach dem verschlüsselten Speichern; Dateien
   werden erst danach entfernt. Schlüsselbund wird in einem Schritt ersetzt (`SecItemUpdate`, sonst `SecItemAdd`).
   Einrichten legt Reste eines früheren Tresors beiseite (`.pmv-<Zeit>`), statt sie zu löschen; die Verbergen-Liste
   bleibt gültig. Temp-Dateinamen nur als sichere Pfadkomponenten (`VaultPathRules`).
7. **Zurücklegen**: Liegt das Original noch in der Fotos-App (abgelehnt oder aus „Zuletzt gelöscht“ zurück), macht
   „Zurück in Fotos verschieben“ es nur wieder sichtbar (keine Doppelung). Ein nur vereinfacht zurückgelegtes Medium
   bleibt vollständig im Tresor; die App sagt das. Gelöscht wird nur, was vollständig zurückliegt.
8. **Sichtschutz über allem**: eigenes Fenster über allen Ebenen (Betrachter, Blätter, Teilen-Fenster), bei offenem
   Tresor schon beim Wechsel in den App-Umschalter, sonst beim Wechsel in den Hintergrund.

## Bewusst NICHT umgesetzt / Grenzen

- Erneute Code-Abfrage für sensible Tresor-Einstellungen: nicht umgesetzt (Tresor ist ohnehin nur offen benutzbar und
  sperrt beim Verlassen).
- Erkennung laufender Bildschirmaufnahme und Screenshot-Schutz: nicht umgesetzt; keine Garantie.
- Einträge aus Build 3/4, deren Original iOS bereits gelöscht hatte (`sourceID` war `nil`), haben keine bekannte
  Kennung. Holt man ein solches Original aus „Zuletzt gelöscht“ zurück, kann PhotoMaid es nicht zuordnen (es wird
  nicht geraten).
- Collagen, Filme und GIFs aus Build 3/4 haben keine gespeicherten Quellen und werden nicht als Kopie angeboten.
- Auf einem neuen iPhone (Wiederherstellung aus dem Backup) vergibt iOS neue Kennungen: Originale, die dort noch in
  der Fotos-App liegen, kann PhotoMaid nicht mehr zuordnen.
- Ausserhalb von PhotoMaid (Fotos-App, „Zuletzt gelöscht“, iCloud-Fotos, bereits geteilte Dateien, Größen-Cache mit
  reinen Byte-Zahlen) gilt die Isolation nicht; die App sagt das bei abgelehnter Löschabfrage.
- System-Auswahl für „begrenzten Zugriff“ (iOS-Oberfläche) zeigt alle Fotos – nicht steuerbar.

## Tatsächlich ausgeführte Prüfung (Linux-Container)

- `swift build && swift test` (PhotoMaidCore, Swift 6.4): 276 Tests; **2 FAIL**, beide schon vor diesen Änderungen auf
  Build-4-Stand rot (`restoredFromRecentlyDeletedIsPendingAgain`, `removedItemThatIsBackCanBeDecidedAgain`, aus Commit
  `9ea3a0e` „entfernte Medien nie erneut einreihen“, widerspricht Android K5) – Produktentscheidung offen.
  Neue Tresor-Tests (Verbergen-Liste, Original-Kennung, Übernahme alter Einträge, Kopien über mehrere Stufen,
  Gespeichert ohne Quellen): PASS.
- `swiftc -parse` aller geänderten App-Dateien: PASS (nur Syntax).
- `python3 scripts/android_strings_to_xcstrings.py --check`: PASS (16 Sprachen).
- NOT RUN: Xcode/iOS-Build, Simulator, iPhone, Face ID/Schlüsselbund, PhotoKit-Integration, Ansichtentests.
  Keine GitHub Actions gestartet, kein TestFlight-Upload.

## Abnahme vor einer Sicherheitsfreigabe (auf dem iPhone)

- Ein Foto in allen öffentlichen Bereichen und Caches vorbereiten (Papierkorb, Später, Auswahlkorb, Schlagwort, Notiz,
  Collage-Entwurf, Analyse), dann ablegen und die iOS-Abfrage **ablehnen**: in PhotoMaid nirgends mehr, in der
  Fotos-App noch vorhanden; Hinweis im Tresor. Danach „Dort löschen“ und aus „Zuletzt gelöscht“ zurückholen: bleibt
  verborgen. Auch nach Sperren, Neustart, offline.
- Gleicher Test mit bearbeiteter Kopie, gemischter Collage, mehreren Bearbeitungsschritten, Video, GIF.
- Während PIN-/Face-ID-Prüfung, Entschlüsselung, Teilen und Ablegen die App verlassen: keine verspätete Freigabe,
  keine Klartextreste in `tmp/pmv-tmp`.
- App-Umschalter mit offenem Betrachter und offenem Teilen-Fenster im Tresor: abgedeckt.
- „Zurück in Fotos verschieben“ bei abgelehntem Löschen: Original wieder sichtbar, keine Doppelung.
