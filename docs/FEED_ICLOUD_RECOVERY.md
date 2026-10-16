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

## Prüfstand

| Prüfung | Status | Beleg |
|---|---|---|
| Core: Weiter ohne Vorschau, veraltete Knöpfe und offener Commit | PASS | gesamte Suite: 425 Swift-Testing- plus 24 XCTest-Fälle; `/workspace/scratch/feed-recovery-core.log` |
| Native PhotoKit-Callback-/Abbruch- und Player-Zuordnungstests | PASS | [CI 38959506351](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38959506351), Quellcommit `85530b12f0d1d92de67100ecfbf71e38a119506c`; native Build-/Unit-Test-Schritte erfolgreich |
| Persistenz übersprungener Medien und Rückkehr über den expliziten Wiederholen-Einstieg | noch nicht gelaufen | neuer Regressionstest mit echtem App-Prozessneustart sowie Core-Data-Integrationstest |
| Fehlerhafte Videos, Video ohne Poster und blockierter Download in echter SwiftUI/PhotoKit-Oberfläche | laufend | derselbe Lauf, iPhone und großes Fenster; tatsächliche Video-Decodierung, gezielte Fehler ausschließlich unter `QA_FIXTURES` im Simulator |
| Persönliche iCloud-Mediathek / betroffene Originalvideos auf dem Gerät | NOT RUN | der Simulator besitzt keinen Zugriff auf die persönliche iCloud-Mediathek |
| Neuer TestFlight-Build | noch nicht hochgeladen | erst nach Abschluss der nativen Prüfung |

Die Simulator-Fälle fälschen weder Fotoeinwilligung noch Entscheidungen. Zwei beschriftete, kurze
QA-Videos werden regulär in die zurückgesetzte PhotoKit-Mediathek importiert. Die Fehler werden nur
an deren Vorschau-/Videoanfragen eingespeist; der Test für ein fehlendes Poster spielt das echte Video ab.
Echte iCloud-Verbindung, Apple-ID-/Netzprobleme und die Integrität der gemeldeten Originale bleiben Geräteprüfungen.
