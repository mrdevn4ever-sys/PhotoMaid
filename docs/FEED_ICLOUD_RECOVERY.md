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

## Sofortige Video-Entscheidung anhand der Vorschau (17.10.2026)

Neuer Nutzerbefund nach Build 13: Bei jedem Video musste vor dem nächsten Swipe kurz auf das Laden
gewartet werden, obwohl bereits ein erkennbares Standbild sichtbar war.

Ursache: `refreshWindow()` entzog dem aktuellen Video die Vorschaufreigabe, solange der gemeinsame
Player noch nicht dieses Medium hielt. Das betraf auch bereits vorgeladene Poster; ein Größenwechsel
beim Einblenden der Videosteuerung konnte die Freigabe nochmals zurücksetzen.

Korrektur auf dem bestehenden Branch, Quellstand `440f7e5`:

- Ohne vorbereitetes Bild wird bei Videos zuerst ein kleines lokales 600px-Poster angefordert,
  ohne Netz; erst danach folgt die Display-Qualität. Die unabhängige Player-Anfrage bleibt parallel.
- Tatsächliche vorbereitete Poster werden im selben begrenzten Fenster wie der Feed gehalten
  (vorheriges, aktuelles, zwei nächste Medien; höchstens vier), nach Verlassen freigegeben und sofort
  an die Karte übergeben. Kein Warten auf erneutes Dekodieren beim Kartenwechsel.
- Poster und reine Player-Frames werden getrennt gemeldet. Ein vorhandenes Bild hält Gesten und
  Entscheidungsfreigabe beim Laden, Fensterwechsel oder Wiedergabefehler offen. Veraltete Player-Frames
  geben ein ungesehenes Video weiterhin nicht frei. Ohne Bild oder sichtbaren Frame bleibt nur das
  ausdrückliche Weitergeben ohne Entscheidung möglich.
- Der bestehende Commit-Pfad, IDs, Revisionen, Favoritenschutz, Swipe-Belegung und Animation bleiben
  erhalten. Keine Originale oder gespeicherten Entscheidungen werden geändert.
- Vier native Modelltests prüfen direkte Videofolgen ohne Player, Größenwechsel, genaue Entscheidungen,
  verworfene Frames und die Begrenzung/Freigabe des Caches. Der neue UI-Fall verwendet echte lokale
  PhotoKit-Testvideos, deren Player-Anfrage im ausschließlich für QA kompilierten Testzweig 120 Sekunden
  wartet. Behalten/Papierkorb/Später müssen anhand der tatsächlichen Standbilder vorher funktionieren,
  auch nach Rückkehr zum Video.

Prüfung: [CI 38985804949](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/38985804949),
`qa_case=games`, `games_case=feed` (vier Video-/Vorschau-UI-Fälle auf iPhone und großem Ersatzfenster).
Lokalisierungsprüfung und Shell-Syntaxprüfung PASS. Core: **461 PASS**. Nativer iOS-Build und **62 Unit-/Integrationstests PASS** (49 Swift Testing + 13 XCTest),
einschließlich aller vier neuen Poster-/Cache-/Entscheidungsfälle. iPhone 17 / iOS 26.2: **4/4 UI-Tests PASS, 0 Fehler, 0 übersprungen, Exitcode 0**.
Der neue Test85 dauerte 22,126s und entschied trotz noch ausstehender Player-Anfragen; beide
unveränderten Screenshots tatsächlich angesehen. Originale und Zusammenfassung: [QA-Belege](feed-video-swipe-qa/).
Großes Ersatzfenster (iPad mini A17 Pro / iOS 26.4.1): ebenfalls **4/4 PASS, 0 Fehler,
0 übersprungen, Exitcode 0**. Der gesamte CI-Lauf ist **success**. Xcode 26.6 (17F113);
kein realer Fold-/Unfold-Test. Das große Posterbild wurde ebenfalls visuell geprüft.
[Maschinenlesbare Ergebnisse und Quellstand](feed-video-swipe-qa/RESULTS.json),
[native Testergebnisse](feed-video-swipe-qa/native-result.log).
Nicht gemessen: Latenz/FPS auf einem echten Gerät; persönliche iCloud-Mediathek nicht getestet.
Die 120s-Verzögerung betrifft ausschließlich den QA-Player; Originalbilder und System-PhotosPicker
werden dadurch in Release-/TestFlight-Builds nicht verändert.
Dieser neue Fix ist noch nicht in TestFlight Build 13 enthalten; kein weiterer Upload wurde gestartet.

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
