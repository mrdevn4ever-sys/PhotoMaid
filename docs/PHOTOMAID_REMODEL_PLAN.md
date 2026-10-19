# PhotoMaid Experimental Remodel — Roadmap

## Verbindliche Basis

- Isolierter Klon des echten Repositorys `https://github.com/mrdevn4ever-sys/PhotoMaid`, main-Snapshot `ca6f81850a0a4032bbf8093f241f99a7584ab4c6`.
- Nur `experiment/photomaid-liquid-glass-remodel`; kein Push, PR, Merge, CI, Signing oder TestFlight. Die drei vorhandenen Windows-Checkouts bleiben unverändert.
- `CLAUDE.md` und E1–E15 gelten. iOS26+, Swift6/Observation, 16 Sprachen, feste Gesten, keine automatischen Löschungen/Uploads/Abos.
- Main enthält keinen verschlüsselten Tresor. Separater Vault-Branch wird nur gelesen; kein kryptografischer Eingriff und keine implizite Feature-Migration.

## Gestaltungsrichtung

Native Medien-App mit ruhigen, deckenden Inhaltsflächen und zurückhaltendem Systemblau für Aktionen. Helle Hintergründe werden neutral-kühl, Dark Mode erhält eigenständig abgestimmte dunkle Flächen und erhöhte Kontrastwerte. Fotos und Videos bleiben das Zentrum; Glas ist funktionale Navigation bzw. Medien-Chrome, nicht Dekoration hinter Text. Systemtypografie, konsistente 8/16/24-Abstände und adaptive statt fix gekappte Textzeilen sollen auf kleinen iPhones und bei grossen Schriftgrössen funktionieren. Vorhandene Symbolik und Warnfarben bleiben semantisch getrennt.

## Priorisierte Arbeitspakete

1. **P0 — Belege und Grenzen:** drei Upstream-Skills mit Revisionen installieren, Discovery verifizieren, Quellen-/Funktionsaudit, vorhandene Workflows nur lesen, Werkzeugbestand erfassen. Ausgangschecks vor UI-Änderungen ausführen.
2. **P1 — Gemeinsames Design:** Farb-/Typo-/Spacing-Tokens aktualisieren, adaptive wiederverwendbare Navigation und Karten, ausreichende Touchflächen, Glas-/Transparenz-Fallbacks und Reduce Motion. Keine neue UI-Abhängigkeit.
3. **P1 — Navigation:** fünf existierende Tabs und deren getrennte Stacks erhalten; Swipe bleibt Vollbildebene. Aufräumen bekommt direkte sichere Einstiege in Papierkorb und Später; Studio klare Werkzeuggruppen statt konkurrierender Kacheln. Alle bestehenden Route-Fälle behalten.
4. **P1 — Feed:** Implementierung/Medienplayer lesen, Gestenkonflikte, Undo, Laden, Video und fehlende Zustandsrücksetzung gezielt verbessern. Fixierte Bewegungsrichtungen und einziger Commit-Pfad bleiben unverändert. Neue Swift-Testing-Regressionen.
5. **P1 — Privatsphäre/Asynchronität:** Hintergrundschutz auch auf Vollbild-Medien; keine veralteten Thumbnail-Updates nach Wiederverwendung. Keine Persistenzschema-/StoreKit-Regeländerung.
6. **P2 — Prüfen:** ausführbare Windows-Quellen-/Katalog-/Projekt-/Erhaltungschecks sowie Syntaxparser; unabhängiger Review der Änderungen. Native Swift-/iOS-/Simulator-/Instruments-Abnahme explizit NOT RUN, sofern Werkzeuge fehlen. Kein Screenshot als angeblicher nativer Beweis aus HTML.
7. **Abschluss:** kleine lokale Commits, exakte Datei-/Testliste, verbleibende Risiken und macOS-Abnahmeschritte in RESULTS. Kein Produktionsreifeversprechen.

## Akzeptanzkriterien

- Keine vorhandene Route, Gesture-Aktion oder Capability absichtlich entfernt.
- Kein Änderungen an Modellversionen, Kryptografie, Signing, Workflows, Abhängigkeiten oder Löschregeln.
- Neue Anzeigen verwenden vorhandene lokalisierte Texte oder vollständige 16-Sprachen-Ergänzung; keine Fake-Werte/Buttons.
- Static PASS ist nur Quellenbeleg, kein iOS-Runtime-PASS. Jede Testart wird separat als PASS/FAIL/NOT RUN/BLOCKED angegeben.
