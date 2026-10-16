# Foto-Memory (16.10.2026)

Freiwillige kurze Wischpause: Im Feed öffnet das Tassen-Symbol die Auswahl zwischen Memory und
[Foto-Snake](PHOTO_SNAKE.md). Bei laufender
Bildanalyse steht „Kurze Pause“ in der Statuskarte. Kein zusätzlicher Tab und kein automatischer Start.

Die Befunde aus dem [ursprünglichen Audit](GAMES_FUNCTION_UI_AUDIT.md) sind im Code korrigiert.
Aktuell: [adaptive Raster, dauerhafte Bestzeiten und nativer Prüfstatus](IPHONE_DUO_AND_GAMES.md).

## Spielen

- Bildquelle wählen: gesamte sichtbare Mediathek, Favoriten, ein Album oder ein Fotoordner der Fotos-App.
  Ein Fotoordner umfasst auch seine Unteralben. Verborgene Alben und Tresorfotos sind ausgeschlossen.
- Zufallsrunden bieten 6, 12 oder 18 Paare (12, 24 oder 36 Karten), Vorgabe 12 Paare. Die Auswahl ist zufällig
  und enthält jedes Foto genau einmal als Paar. „Noch eine Runde“ zieht erneut aus derselben Quelle.
- „Eigene Fotos wählen“ bleibt als manuelle Alternative erhalten: zwei bis achtzehn Fotos ergeben
  vier bis sechsunddreißig Karten. Videos sind bei allen Quellen ausgeschlossen.
- Alternativ sofort mit sechs Symbolpaaren spielen (ausdrücklich so beschriftet).
  Keine neuen Bilddateien oder Abhängigkeiten.
- Immer zwei Karten aufdecken; gefundene Paare bleiben sichtbar. Bei einem Fehlpaar werden
  weitere Tipps blockiert, bis die Karten wieder verdeckt sind. Keine Zeitbegrenzung und keine Strafpunkte.
- Mit VoiceOver bleiben Fehlpaare bis „Karten umdrehen“ offen. Verdeckte Karten verraten ihre
  Identität nicht in der Accessibility-Beschriftung. Das Raster berücksichtigt große Schrift.
- Schließen und erneutes Öffnen behält innerhalb derselben App-Instanz die Karten, aufgedeckten
  Bilder, Paare und Züge. Bei manuellen Runden mischt „Noch eine Runde“ dieselben Bilder neu. Beim Beenden des Prozesses
  wird das Spiel verworfen; Foto-Vorschauen und Kennungen werden dafür nicht auf Platte gespeichert.

## Fotos und Analyse

- Höchstens achtzehn Vorschauen mit Zielgröße 320 × 320, nacheinander über die vorhandene Preview-Pipeline.
  Keine Originalbearbeitung, keine neuen Analyseaufträge, keine Spiel-Uploads.
- Memory und Snake verwenden dieselbe Ladeimplementierung, haben aber getrennte Vorschauen und Spielstände.
  Ein Wechsel des Spiels ersetzt die Bilder der anderen Runde nicht.
- iCloud-Downloads für die Spielvorbereitung sind zunächst aus und werden nur durch den ausdrücklichen
  Schalter „Ausgewählte iCloud-Fotos laden“ erlaubt. Der normale Fotoauswahl-Bildlader bleibt unverändert.
- Unzugängliche, entfernte oder im Tresor verborgene Fotos werden geprüft; eine betroffene Runde wird
  zusammen mit ihren Bildvorschauen verworfen. Die Prüfung erfolgt auch bei geänderter Tresor-Sichtbarkeit,
  Berechtigung und Mediathek. Eine beschädigte Verbergen-Liste erlaubt keine eigenen Spielbilder.
- Eine misslungene Auswahl ersetzt keine bisherige Runde. Abgebrochene oder verspätete Ladevorgänge
  können eine inzwischen gestartete neue Runde nicht überschreiben.
- Zufallsrunden überspringen nicht verfügbare Vorschauen innerhalb derselben Quelle. Höchstens die dreifache
  Paarzahl an Kandidaten wird angefragt (maximal 54); der Lauf endet, sobald genügend Vorschauen bereit sind.
  Reicht das nicht, wird die gewählte Paarzahl nicht still verkleinert und keine andere Quelle verwendet:
  ein Hinweis bietet weniger Paare, eine andere Quelle oder die Freigabe von iCloud-Downloads an.
- Der Feed bleibt während der Spielpause bestehen, seine Gesten und Medienwiedergabe pausieren.
  Der Feed-Aktivitätszähler wird ausgeglichen freigegeben, damit die Analyse während des Spiels
  nicht weiter wegen des verdeckten Feeds gedrosselt wird. Rückkehr lädt die Feed-Sitzung nicht neu.
- Der echte Analysefortschritt ist im Spiel sichtbar. Nach Abschluss kann die Runde weitergespielt oder
  über „Ergebnisse ansehen“ zur passenden Analyse zurückgekehrt werden. Das Spiel hält die Analyse nicht an.
- Das Spiel nimmt keine Fotoentscheidungen vor und zählt keine Entfernungen, Werbeaktionen oder Boni.

## Prüfstatus

| Prüfung | Status | Nachweis |
|---|---|---|
| PhotoMaidCore, gesamte Suite | PASS | Lokal im Swift-6.4-Docker-Container: 409 Tests, 46 Suites einschließlich Snake |
| Memory-Regeln und Zufallsauswahl | PASS | Sieben Tests: Deckvalidierung, schnelle Mehrfachtipps/Fehlpaare, Unterbrechung, gemischte Decks, große Runden, Quellfilter, begrenzte Stichproben |
| Swift-Syntax aller App- und App-Testdateien | PASS | Lokales `swiftc -frontend -parse` (keine SDK-Typprüfung) |
| Lokalisierung | PASS | 39 neue Kennungen in allen 16 Sprachen; bestehende Texte und Berechtigungsangaben erhalten |
| Native Model-Regressionen | NOT RUN | Sieben Fälle in `PhotoMaidTests/PhotoMemoryModelTests.swift`: fehlgeschlagene Auswahl, verspätete Ergebnisse, Zugriffsentzug, erneute Runde, übersprungene Vorschauen, zu kleine Quelle, große Zufallsrunde |
| iOS-Build, Simulator und Gerätebedienung | NOT RUN | Linux-Umgebung ohne Xcode; keine GitHub Actions aufgerufen |
| GitHub Actions / CI / TestFlight | NOT RUN | Auf Wunsch ausdrücklich keine Actions-Minuten verbraucht |

Vor einer später ausdrücklich beauftragten iOS-Abnahme: eigene lokale und iCloud-Fotos, Abbruch während
des Ladens, verweigerter/eingeschränkter Fotozugriff, Tresor-Verschiebung, VoiceOver, große Schrift,
Dark Mode, große Runden im Hoch-/Querformat, leere Favoriten, verschachtelte Fotoordner,
Rückkehr zum selben Feed-Foto und Analyseabschluss während einer Runde prüfen.
