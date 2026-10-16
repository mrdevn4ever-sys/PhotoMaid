# iCloud-/Video-Feed: Nachladen und Weitergehen

Stand: 16.10.2026. Nutzerbefund aus TestFlight Build 11: iCloud-Medien laden unzuverlässig;
zwei kurze Videos bleiben mit fehlgeschlagener Vorschau am Anfang des Feeds stehen.
Präzisierung: „Ohne Auswahl weiter“ funktioniert in der Sitzung; nach erneutem Öffnen sind die Videos wieder da.

## Korrektur

- Fehlende Cloud-Kennung im lokalen PhotoKit-Ergebnis beendet den sichtbaren Ladeweg nicht mehr.
  Nach einer fehlenden lokalen Vorschau folgt genau ein netzwerkfähiger Versuch. Ein kleines bereits
  sichtbares Bild bleibt erhalten; scheitert volle Qualität, bleibt Wiederholen erreichbar.
- Verdeckte Nachbarkarten laden nur lokal. Beim Vorrücken startet der Ladeweg für die neue sichtbare
  Karte erneut und darf dann auf iCloud zugreifen. Geänderte Fenstermaße aktualisieren die Auflösung.
- Das sichtbare Video wird unabhängig vom Poster angefordert. Ein echtes erstes Bild des
  `AVPlayerLayer` kann die Karte freigeben, auch wenn PhotoKit kein Poster liefert. Ein bloß erhaltener
  PlayerItem-Verweis genügt nicht als sichtbare Vorschau.
- PhotoKit-Anfragen enden bei Task-Abbruch sofort für den Aufrufer. Nachträglich erhaltene Request-IDs
  werden ebenfalls abgebrochen; verspätete/doppelte Ergebnisse schließen keine Continuation doppelt.
  Ein alter Videoauftrag kann nach Weitergehen oder erneutem Aufrufen desselben Mediums keinen Player ersetzen.
- „Ohne Auswahl weiter“ ist auch während des Ladens erreichbar. Fehler-/Ladeknöpfe konkurrieren nicht
  mit den Tipp-, Zoom- und Wischgesten der Bühne. Die verdeckte Nachbarkarte ist für Accessibility ausgeblendet.
- Weitergehen ist an das ausgelöste Medium gebunden, setzt den visuellen Gestenzustand zurück und
  bewegt genau einen Schritt. Keine automatische Entscheidung, Fotoänderung oder Löschung; ungesehene
  Medien können weiterhin nicht über den Entscheidungspfad als Behalten/Papierkorb gespeichert werden.
- Explizit übersprungene Vorschauen werden als separate Navigationsinformation in Core Data gespeichert.
  Sie fehlen auch nach einem Prozessneustart in neuen Feed-Warteschlangen und der normalen Offen-Zählung.
  Unter „Aufräumen → Übersprungene erneut laden“ stellt der Nutzer sie ausdrücklich wieder her; die Liste
  respektiert aktuelle Sichtbarkeit und ausgeschlossene Alben. Originale und Entscheidungs-Ledger bleiben unverändert.
  Ein fehlgeschlagener Speichervorgang lässt den aktuellen Eintrag stehen und meldet den Fehler.
- Lade-/Fehlerkennungen liegen auf ihren Texten statt auf dem umgebenden Container, damit SwiftUI die
  Kennung des Weiter-Knopfs nicht überschreibt. Verdeckte Karten rendern keine Statusmeldungen.
  Die Videosteuerung nutzt lesbare Farben für helles und dunkles Design; ohne verfügbaren Player ist sie inaktiv.

## Prüfstand

| Prüfung | Status | Beleg |
|---|---|---|
| Core: Weiter ohne Vorschau, veraltete Knöpfe und offener Commit | PASS | gesamte Suite: 425 Swift-Testing- plus 24 XCTest-Fälle; finaler CI-Lauf unten |
| Native PhotoKit-Callback-/Abbruch- und Player-Zuordnungstests | PASS | insgesamt 38 Swift-Testing- plus 13 XCTest-Fälle; `/workspace/scratch/feed-recovery-native/xcodebuild.log` |
| Persistenz übersprungener Medien und Rückkehr über den expliziten Wiederholen-Einstieg | PASS | [CI 38962426871](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38962426871), Quellcommit `137c471334d385f5e53ec8e1f271885e8095114b`; echter App-Prozessneustart sowie Core-Data-Integrationstest |
| Fehlerhafte Videos, Video ohne Poster und blockierter Download in echter SwiftUI/PhotoKit-Oberfläche | PASS | je 3/3 UI-Fälle auf iPhone 17 (iOS 26.2) und iPad mini A17 Pro (iOS 26.4.1) als großes Ersatzfenster; beide Ergebnis-JSONs ohne Fehler, beide Exit-Codes 0 |
| Persönliche iCloud-Mediathek / betroffene Originalvideos auf dem Gerät | NOT RUN | der Simulator besitzt keinen Zugriff auf die persönliche iCloud-Mediathek |
| Neuer TestFlight-Build | PASS | Version 1.0, Build 12; [TestFlight 38965702294](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38965702294), derselbe Quellcommit; Upload 21:04:06 UTC, Apple-Verarbeitung 21:06:10 UTC, interne Verteilung 21:06:11 UTC bestätigt |
| Privacy-Manifeste der tatsächlich exportierten Build-12-IPA | PASS | alle 3 Dateien ohne Fehler/Warnungen; [unveränderter Bericht mit SHA-256](privacy-manifests-build12.json) |

Die Simulator-Fälle fälschen weder Fotoeinwilligung noch Entscheidungen. Zwei beschriftete, kurze
QA-Videos werden regulär in die zurückgesetzte PhotoKit-Mediathek importiert. Die Fehler werden nur
an deren Vorschau-/Videoanfragen eingespeist; der Test für ein fehlendes Poster spielt das echte Video ab.
Echte iCloud-Verbindung, Apple-ID-/Netzprobleme und die Integrität der gemeldeten Originale bleiben Geräteprüfungen.

Der erste native UI-Lauf bestätigte die Videowiedergabe ohne Poster, zeigte aber zwei fehlgeschlagene
Recovery-Tests: SwiftUI hatte Status-/Buttonkennungen überlagert. Die UI-Hierarchie belegte außerdem doppelte
Statusmeldungen verdeckter Karten. Beides wurde im Quellcode korrigiert; der abschließende Lauf bestätigt diese Korrekturen.
20 unveränderte native PNGs mit SHA-256-Prüfsummen: `/workspace/scratch/feed-recovery-review/index.html`.
Die breite Prüfung ist keine Faltabnahme auf einem Duo-Gerät.
Der TestFlight-Lauf wiederholt die bereits bestandenen nativen Tests nicht (`run_tests=false`), baut jedoch
ein frisches signiertes Release-Archiv, prüft dessen exportierte Manifeste und wartet auf Apples Verarbeitung.

## Geräteprüfung mit der betroffenen Mediathek

1. Mit Netzverbindung einen nur in iCloud verfügbaren Eintrag öffnen: lokale Vorschau darf sofort erscheinen,
   die sichtbare Karte lädt automatisch nach. Zwischen benachbarten Fotos und Videos wechseln.
2. Während eines Downloads weitergehen; die folgende Karte muss bedienbar bleiben. Ein verspätetes Video
   darf den Player der inzwischen sichtbaren Karte nicht ersetzen.
3. Die beiden gemeldeten Videos jeweils mit „Ohne Auswahl weiter“ überspringen. Feed schließen und wieder
   öffnen, danach App beenden und neu starten: beide bleiben aus dem normalen Feed entfernt; Papierkorb unverändert.
   Frühere, nur flüchtige Übersprünge aus Build 11 lassen sich nicht nachträglich rekonstruieren: einmal im neuen Build überspringen.
4. Unter „Aufräumen → Übersprungene erneut laden“ ausdrücklich wieder öffnen. Lässt sich ein Original
   weiterhin nicht anzeigen, erneut überspringen; falls möglich zusätzlich seine Abspielbarkeit in Apple Fotos prüfen.
5. Offline eine Cloud-Datei öffnen: Wiederholen und Weitergehen bleiben erreichbar. Nach Rückkehr der
   Verbindung denselben Eintrag ausdrücklich erneut laden. Der Test setzt keine automatische Original-Reparatur voraus.
