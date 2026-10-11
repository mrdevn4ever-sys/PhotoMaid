# Tresor-Sicherheit: unvollständiger Entwicklungsstand, NICHT freigeben

Stand: 11.10.2026. Ausgangspunkt: `24b41a0731f65ff04a7889a80dbeab626dfcb7a9` (TestFlight Build 4).

## Verbindlicher Auftrag

Was im Tresor liegt, darf in PhotoMaid nirgendwo ausserhalb des Tresors auftauchen: nicht unter Fotos, Bereinigen, Verlauf, Bearbeitet, Collage, Film, GIF, Suche, Favoriten, Ausgeblendet, Auswahlkorb, Schnellzugriffen, Dateivorschauen oder einer öffentlichen Sicherung. Gespeicherte Verweise, Vorschauen und abgeleitete Ausgaben sind einzubeziehen. Ein Titel oder leerer Platzhalter darf die Existenz des privaten Elements ebenfalls nicht verraten.

## Tatsächlicher Abschluss dieses Arbeitsversuchs

**Die vollständige Reparatur ist NICHT umgesetzt. Die App verwendet weiterhin den Ausgangsstand der Tresor-Implementierung.**

Ein umfassender Tool-Schreibzugriff auf `VaultStore.swift` wurde von einer Sicherheitsprüfung abgewiesen. Daraufhin wurden die voneinander abhängigen, teilweise bereits geschriebenen Änderungen an AppModel, PhotoLibraryService, OrganizeStore, KeyValueStore und VaultCrypto sowie die neuen iOS-Isolationsklassen in einem korrektiven Commit zurückgenommen. Die Rücknahme behält die Branch-Historie bei; kein Force-Push. Weder main noch Release-Branch wurden geändert.

Übrig bleiben ausschliesslich:

- `Sources/PhotoMaidCore/Vault/VaultSecurity.swift`: unabhängige Hilfsfunktionen für Sichtbarkeitsregeln, Abhängigkeiten abgeleiteter Ausgaben, Sitzungsgültigkeit, Value-Type-Transaktionen und sichere Pfadkomponenten.
- `Tests/PhotoMaidCoreTests/VaultSecurityTests.swift`: zugehörige isolierte Regressionstests.
- Dieses Statusdokument.

Diese Hilfsfunktionen sind NICHT in die iOS-App integriert. Ein erfolgreicher Helper-Test beweist weder wirksame Tresor-Isolation noch die Sicherheit des vorhandenen Builds. Insbesondere widerruft der Session-Helper nur Gültigkeitsnachweise; er löscht keine Schlüsselkopien automatisch. Die Transaktionshilfe setzt Value-Semantik voraus und ist kein transaktionaler Dateisystem- oder Keychain-Ersatz.

## Tatsächlich ausgeführte lokale Prüfung

Am 11.10.2026 mit Swift 6.2.1 auf x86_64-Linux: isoliertes SwiftPM-Testpaket, bestehend nur aus dem neuen Helper und den neuen Tests. Der Helper-Blob stimmt exakt mit `45fb328ab4990571187112f5bce112ef76565388` überein.

- Debug: 13 Tests in 1 Suite bestanden.
- Release: 13 Tests in 1 Suite bestanden.
- Enthalten: Fail-closed-Status, gemischte Collage-Abhängigkeiten, zyklische Beziehungen, alte Sitzung nach Sperren/Neuanmeldung, unterdrückte Schreibaktion bei ungültiger Sitzung, fehlgeschlagene Value-Type-Transaktion, sichere Pfadkomponenten.
- NICHT ausgeführt: vollständiges PhotoMaidCore-Paket, Xcode/iOS-Build, Simulator, iPhone, CryptoKit-Manipulationstests, Face ID/Keychain, Photos-Integration oder Ansichtentests.

Keine GitHub Actions gestartet oder wiederholt. Kein weiterer TestFlight-Upload.

## Noch notwendige Integrationsarbeit

1. Eine zentrale, dauerhaft gespeicherte und beim gesperrten Tresor nutzbare Eigentumsprüfung an sämtlichen Medienzugängen. Öffentliche Abfragen und authentifizierte Tresoraktionen müssen getrennte Befugnisse besitzen.
2. Altbestände migrieren: Im bisherigen Format wird `sourceID` nach dem Entfernen des Originals auf nil gesetzt. Die Identität darf deshalb nicht aus einem fehlenden Feld als öffentlich abgeleitet werden. Unklare Zuordnungen dürfen weder offen erscheinen noch zum stillen Löschen fremder Medien führen.
3. Sämtliche bearbeiteten Ausgaben und vollständigen Eingangslisten von Collagen/Filmen/GIFs nachvollziehbar speichern. Bisherige Metadaten reichen nicht für eine pauschale Zusicherung aus, jede alte abgeleitete Kopie eindeutig erkennen zu können.
4. Öffentliche Listen, Verlauf, Kennzahlen, gespeicherte Auswahlzustände und Vorschaubilder beim Eigentumswechsel invalidieren. Auch Rückgaben bereits laufender Bild-/Video-Anfragen müssen geprüft werden.
5. Entsperren, Entschlüsseln und temporäre Dateien an eine widerrufbare Sitzung binden. Eine verspätete Aufgabe darf nach Sperren nicht öffnen, anzeigen oder Klartext neu anlegen.
6. Index-/Datei-/Keychain-Änderungen mit überprüfbarer Fehlerbehandlung; kein Löschen der letzten gültigen Zugangsdaten oder Medien bei gescheitertem Persistieren. Keine automatische Neueinrichtung über einen beschädigten Tresor.
7. Erneute Authentifizierung für sensible Einstellungen; Sichtschutz auch auf verschachtelten Vollbildansichten; Prüfung aktiver Bildschirmaufzeichnung. Keine unbelegbare Screenshot-Schutzgarantie.
8. Wiederherstellen ohne unbemerkten Verlust von Originalen, RAW-/Live-Photo- oder Bearbeitungsressourcen; bei einem vereinfachten Ergebnis das vollständige Tresororiginal behalten.

## Abnahme vor einer Sicherheitsfreigabe

- Ein Foto in allen öffentlichen Bereichen und Caches vorbereiten, dann in den Tresor verschieben und jede Oberfläche erneut prüfen, auch nach Sperren/Neustart/offline.
- Gleicher Test mit bearbeiteter Kopie, gemischter Collage, mehreren Bearbeitungsschritten, Video, GIF und alten Tresoreinträgen ohne sourceID.
- Während PIN-/Face-ID-Prüfung, Entschlüsselung, Teilen und Import sperren: keine verspätete Freigabe oder Klartextreste.
- Speicher voll, Index beschädigt, Prozessabbruch und Keychain-Schreibfehler simulieren: keine falschen Erfolgsmeldungen und keine stille Datenvernichtung.
- Apple-Original nicht löschen bzw. Systemdialog abbrechen: innerhalb PhotoMaid trotzdem privat; der Nutzer erhält einen ehrlichen Hinweis, dass ausserhalb PhotoMaid noch ein Original vorhanden sein kann.

Die App darf nicht versprechen, bereits extern geteilte Dateien zurückzuholen oder Apples Systembestätigung/Zuletzt-gelöscht-Verhalten zu umgehen. Der streng verlangte Ausschluss betrifft alle von PhotoMaid kontrollierten Oberflächen und Zugriffe.
