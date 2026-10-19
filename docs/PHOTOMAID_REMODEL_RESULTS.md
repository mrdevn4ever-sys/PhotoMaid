# PhotoMaid Remodel — Ergebnisse und Abnahmegrenzen

## Native Nachprüfung vom 19.10.2026

**Der Experimentierstand baut erstmals erfolgreich mit Xcode. Die Gesamtabnahme ist wegen fehlgeschlagener Tests weiterhin offen.** Die nachfolgende ursprüngliche Windows-Abnahme ist ein historischer Bericht; ihre Aussagen „kein Push/Workflow“ und „Swift nicht installiert“ beschreiben den damaligen Stand.

### Revision und unveränderte Grenzen

- Geprüfter App-Quellstand: `417912eae28f675c91336c0e434c1cc8e68dae95`, aufbauend auf dem bereitgestellten `45a0a14e119f3799159d10101ec6998db246dc4b`.
- Ausschliesslich `experiment/photomaid-liquid-glass-remodel` geändert und gepusht. Isoliertes Cloud-Worktree `/workspace/PhotoMaid-remodel`; kein Zugriff auf die Windows-Arbeitskopie auf F:.
- GitHub-main vorher und nach den Quellcodekorrekturen: `ca6f81850a0a4032bbf8093f241f99a7584ab4c6`. Kein Merge oder Force-Push. Das andere Worktree `/workspace/PhotoMaid` bleibt auf `a614cdb6b365104bf60c31528a8eeb85262a6cdb` unverändert.
- Bestehende manuelle CI mit ausdrücklicher Build-/Testfreigabe ausgeführt. Workflows, Signing, `project.yml`, Fastlane, Pakete, App-Einstellungen, Core-Data-Speicher und `VaultCrypto.swift` gegenüber `45a0a14` bytegleich. Keine Compilerprüfung abgeschaltet, keine bestehende Assertion entfernt.
- Kein neuer TestFlight-Lauf oder Upload im Korrekturauftrag. Der frühere unveränderte Uploadversuch auf `45a0a14` war bereits beim Kompilieren gescheitert.

### Korrekturen und vollständiges Dateiinventar dieses Nachtrags

| Datei | Änderung |
|---|---|
| `PhotoMaid/Infrastructure/Archive/ArchiveService.swift` | MainActor-gebundenen Asset-Zugriff korrekt mit `await` ausführen. |
| `PhotoMaid/Features/Archive/ArchiveView.swift` | Fehlenden Formatter durch vorhandenen `SizeText.bytes` ersetzen. |
| `PhotoMaid/Features/Studio/WorkflowsView.swift` | Dieselbe fehlende Formatter-Referenz korrigieren. |
| `PhotoMaid/DesignSystem/ViewerPhotoSurface.swift` | Vom bereits verwendeten Tresor benötigte Fotooberfläche unverändert aus dessen Integrationsbasis `de90f1d` ergänzen. |
| `PhotoMaid/Features/Library/ViewerVideoControls.swift` | Ebenso die fehlenden gemeinsamen Video-Bedienelemente ergänzen. |
| `Sources/PhotoMaidCore/Batch/Workflow.swift` | `TargetSize.search` übernimmt mit `#isolation` den Actor des Aufrufers; veränderlicher Encoder-Zustand bleibt auf diesem Actor. |
| `Tests/PhotoMaidCoreTests/BatchPdfTests.swift` | Regressionstest mit echter Task-Suspension und MainActor-Prüfung für den Encoder-Callback. |
| `PhotoMaid/Infrastructure/Video/VideoSource.swift` | Eng begrenzte Überladungen mit dem vorhandenen `UncheckedBox` für unveränderliche Video-Assets; jeder Vorschauauftrag besitzt seinen eigenen Generator abseits des MainActor. |
| `PhotoMaid/Features/Editor/VideoEditorModel.swift` | Editor-Vorschauaufträge verwenden diese Asset-Übergabe; keine globale Sendable-Konformität für AVFoundation eingeführt. |
| `PhotoMaid/Features/Feed/FeedView.swift` | Zu grossen SwiftUI-Ausdruck in Inhalt, Lebenszyklus und Sheets aufteilen; Reihenfolge der Modifier und vorhandene Aktionen erhalten. |
| `PhotoMaid/Infrastructure/Playback/FeedPlayer.swift` | Ende-Notification vor dem Actor-Wechsel auf eine sendbare Objektidentität reduzieren; verspätete Meldungen bleiben ausgeschlossen. |
| `PhotoMaidTests/VideoSourceTests.swift` | Native Regressionstests für synthetisches H.264-Video/Thumbnails und verspätete Player-Endmeldungen. |
| `docs/PHOTOMAID_REMODEL_RESULTS.md` | Dieser überprüfbare Nachtrag. |
| `docs/IMPLEMENTATION_STATUS.md` | Aktuellen Experiment-Status vom historischen Status unterscheiden. |

### Tatsächliche Ergebnisse

| Prüfung | Ergebnis / Beleg |
|---|---|
| Lokale Core-Tests, Swift 6.4 | **PASS: 294 Tests in 34 Suites**, einschliesslich Actor-Regression. |
| Core unter CI / Swift 6.2 | **PASS: 294 Tests in 34 Suites**, sowohl [Lauf 39206790240](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39206790240) als auch [Lauf 39209674569](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39209674569). |
| Native App-Kompilation | **PASS: `** BUILD SUCCEEDED **`** in beiden Läufen auf demselben Commit, macOS 26, Xcode 26.6 (17F113), iPhone 17 / iOS-26.5-Simulator, `CODE_SIGNING_ALLOWED=NO`. Kein Gerätearchiv oder Distributionsbuild. |
| Native Swift-Testing-Suites | **PASS: 16 Tests in 3 Suites** (`RemodelDocumentTests`, `VaultConcealmentTests`, `VideoSourceTests`), einschliesslich beider neuen Video-Tests. |
| Native XCTest-Suites | **10 von 11 Testmethoden PASS; 1 FAIL.** `VaultKeychainTests.testCodeKeychainRoundTripAndReplacement` scheitert mit Security-Status `-34018` (`errSecMissingEntitlement`), auch bei direkter unabhängiger `SecItemAdd`-Probe. Dieser unsignierte Lauf belegt keinen funktionierenden Tresor-Keychain-Zugriff. |
| UI-Gesamtlauf | **FAIL / abgebrochen nach rund 30 Minuten.** Elf UI-Testmethoden waren bereits fehlgeschlagen; weitere nicht abgeschlossen. Vorhandene Tests erwarten unter anderem einen alten Onboarding-Titel bzw. die nicht vorhandene Kennung `onboarding.next`; andere werden durch die anschliessende Tour blockiert. Keine erfolgreiche Navigations-, Feed- oder Tresor-UI-Abnahme. |
| Separater App-/Unit-Lauf ohne UI | **Abgeschlossen: BUILD SUCCEEDED / TEST FAILED**, [39209674569](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39209674569), derselbe Quellstand. Bestätigt 16 bestandene Swift-Testing-Tests sowie 10 bestandene XCTest-Methoden; einziger fehlgeschlagener Test ist erneut der reale Keychain-Test mit `-34018`. Keine UI-Tests in diesem zweiten Lauf. |
| Python-Quellenverträge | **PASS: 26** (`python3 -m unittest discover -s scripts/tests -v`). Der erste Aufruf benötigte zunächst eine lokale, unveränderte main-Referenz für die bestehenden Vergleichsprüfungen; nach Einrichten dieses Mirrors vollständig bestanden. |
| Tresor-Quellenverträge | **PASS: 10** (`python3 scripts/verify_vault_integration.py`). Keine Laufzeit-Sicherheitszertifizierung. |
| Lokalisierung | **PASS:** 1219 verwendete Kennungen, 2293 Einträge, 16 Sprachen. |
| Patch- und Isolationsprüfung | **PASS:** `git diff --check`, geschützte Dateien bytegleich, keine Merge-Commits seit `45a0a14`. |

Die vier vorangegangenen Korrekturläufe `39204685273`, `39205226838`, `39205798729` und `39206214802` scheiterten jeweils an weiteren vom Apple-Compiler aufgedeckten Problemen. Sie sind keine bestandenen iOS-Tests. Der ursprünglich allein auf Parsern beruhende Integrationsbericht genügte nicht zum Kompilieren.

### Belege und verbleibende Abnahme

- Vollständiges Xcode-Protokoll, CI-Bericht und das unvollständige Ergebnisbündel des abgebrochenen Laufs: [Artefakt ios-build-report / 12167326408](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39206790240/artifacts/12167326408). Das CI-Berichtsskript meldet beim Abbruch „UNBEKANNT“; die Build-/Testbewertungen oben stammen aus den tatsächlichen Xcode-Markern und einzelnen Testergebnissen.
- Abgeschlossener separater App-/Unit-Lauf: [Artefakt ios-build-report / 12167586842](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39209674569/artifacts/12167586842) mit vollständigem `xcodebuild.log`, `ci-report.md` und `tests.xcresult.zip`. Bericht: `TEST FAILED`, keine Compilerfehler, genau eine fehlgeschlagene Testmethode. `core-test-log` desselben Laufs belegt die 294 Core-Tests.
- 15 echte PNG-Anhänge aus diesem Ergebnisbündel wurden lokal extrahiert und vier davon angesehen. Sie zeigen den ersten Einführungsbildschirm; daraus folgt **keine** visuelle Abnahme der Hauptansichten. Keine nachgebauten Screenshots verwendet.
- Die Keychain-Prüfung bleibt fehlgeschlagen. Weder wird sie übersprungen noch durch einen In-Memory-Ersatz grün gemacht. Signing/Entitlements müssen in einer geeigneten, gesondert geprüften Testumgebung funktionieren, bevor Tresor-Einrichtung und Recovery nativ abgenommen werden können.
- Der UI-Test-Einstieg muss an den tatsächlichen fünfseitigen Einführungsablauf und die anschliessende Tour angepasst werden; Simulator-Medien müssen für Foto-/Video-Tests vorbereitet sein. Das ist noch keine erledigte UI-Integration.
- Im Concealment-Testlauf traten zusätzlich SwiftUI-Warnungen über Veröffentlichungen von Hintergrundthreads auf. Die Assertions bestanden; die Warnungen bleiben ein offener Prüfpunkt.
- Reales iPhone, Face ID, iCloud-Medien, Berechtigungswechsel, Datenschutz-Snapshot-Timing, Instruments und die vollständige Accessibility-/Display-Matrix bleiben ungeprüft. Die bekannten alten Risiken zu Analyse-Caches/OS-Backups und Editor-Löschjournal sind durch diesen Compiler-Nachtrag nicht gelöst.

## Historischer Implementierungsbericht vor der nativen Nachprüfung

**Quellcode-Remodel einschliesslich Tresor implementiert und lokal committed; native iOS-Abnahme BLOCKED / NICHT VERIFIZIERT.** Dieser Bericht ist kein Build-/Sicherheitszertifikat. Keine produktiven Medien oder Tresordaten wurden geöffnet oder migriert.

## Revision und Isolation

- Repository: `mrdevn4ever-sys/PhotoMaid`, `https://github.com/mrdevn4ever-sys/PhotoMaid`.
- Arbeitskopie `F:/PhotoMaid-remodel`, eigener Git-Store auf F:, Experimentier-Branch `experiment/photomaid-liquid-glass-remodel`.
- Ausgangs-main: `ca6f81850a0a4032bbf8093f241f99a7584ab4c6`. Main, vorhandene Windows-Checkouts und Produktion bleiben unverändert. Kein Push, PR, Merge, Workflowlauf oder TestFlight.
- Lokale Meilensteine: `fb24a51` Design/Navigation; `c54399a` Feed; `0c65547` Quellenverträge; `a9b4388` Erreichbarkeit/Dokumente/Archiv; Implementierungsabschluss `17b15879c8d4d294e089a803c524eb11e49e13a1` Tresor/Isolation/Reviewkorrekturen. Nachfolgender Dokumentationscommit ergänzt diesen Bericht; endgültiges HEAD über git rev-parse HEAD feststellen.

## Installierte und eingesetzte Skills

Claude Code 2.1.187; unterstützte persönliche Skill-Ordner, über Windows-Junctions auf F: abgelegt, vorhandene Skills nicht überschrieben. Keine UI-Laufzeitabhängigkeit.

- `swiftui-expert-skill`, AvdLee/SwiftUI-Agent-Skill `204dba7c67256a8b707ee3fbc5759a824191974f`, vollständiger Skill sowie Layout-/Navigation-/Accessibility-/Animationsreferenzen.
- `swiftui-liquid-glass`, Dimillian/Skills `05ba982bfeb0d77d3c97d4542b0ee15034d05f84`, vollständiger Skill und Liquid-Glass-Referenz.
- `swift-testing-pro`, twostraws/Swift-Testing-Agent-Skill `2d6bba14a3c8bf3694f218b92fffe617c41ae43e`, vollständiger Skill und core-rules/writing-better-tests. Der verschachtelte Upstream-Skill-Ordner enthält keine Referenzen; installiert ist deshalb der vollständige Elternordner `swift-testing-pro`.

Die drei Namen wurden in einer neuen Claude-Code-Sitzung sowohl in `system.init.skills` als auch `slash_commands` nachgewiesen. Externer Beleg: `F:/PhotoMaid-remodel-evidence/skill-discovery.json`. `plugin details ...@skills-dir` erkennt keine einfachen Legacy-Skill-Verzeichnisse; das ist kein Plugin-Installationsnachweis. Verwendet wurde der unterstützte Skill-Mechanismus und tatsächliche Sitzungsdiscovery, nicht eine erfundene Marketplace-Konfiguration. Keine API-Key-Anmeldung verwendet.

## Implementiert im Quellcode

- Gemeinsame native, deckende blau-neutrale Flächen mit eigenen Light/Dark/High-Contrast-Werten; kein violetter Verlauf. Text-/Akzentkontraste sowie weisse Beschriftung auf blauen CTA-Flächen rechnerisch geprüft.
- Neue wiederverwendbare `FeatureHeader`, `FeatureActionTile`, `FeaturePressStyle`; Systemtypografie und SF Symbols. Kleine Touchrückmeldung respektiert Reduce Motion, keine dauernden Animationen.
- Studio trennt Erstellen, Werkzeuge, Dokumente, Gespeichert und Entwürfe. Adaptive Raster werden bei Accessibility-Schrift einspaltig. Vorher unerreichbare Convert/GPS/Stitch/GIF/Batch-Tools, PDF Studio und unterstützter VisionKit-Scanner haben echte Einstiege.
- Aufräumen bekommt direkte Papierkorb-/Später-Ziele; die Kacheln öffnen nur Ansichten, löschen/entscheiden nicht. Fünf Tabs und getrennte NavigationStacks bleiben, Tableiste minimiert nicht beim Scrollen.
- Native Glass-Controls bleiben auf funktionales Chrome begrenzt. Opaque Fallbacks bei Reduce Transparency und erhöhtem Kontrast. Keine externe UI-Bibliothek hinzugefügt.
- Feed schützt gegen wiederholtes Laden/Sessionreset, verspätete Preview-/Videoladevorgänge, überlappende Undo/Decision-Aktionen und falsche Serien-Erfolgsmeldungen; Pinch-Suspension sowie VoiceOver/Switch-Control-Startzustand korrigiert. Physische Gestenbedeutungen und zentraler Commit-Pfad bleiben erhalten.
- Thumbnails setzen wiederverwendete Zellen zurück, berücksichtigen Grösse/Display-Skalierung und ignorieren abgebrochene Ergebnisse; NSCache bekommt zusätzlich ein Kostenbudget. Das ist keine gemessene Gesamt-App-Speichergrenze.
- Schutz für inaktiven Root und Vollbild-Medien, ohne Editorzustand durch Entfernen der View zu zerstören. Fensterweiter PrivacyCover über Sheets und Vollbildansichten ergänzt; Snapshot-Timing und Face ID sind weiterhin nicht auf Hardware geprüft.
- PDF-Ausgaben dauerhaft statt tmp-only, eindeutige Dateinamen und Grössenprüfung; native Tests für Schreiben/Wiederöffnen/Kollision/leere Ausgabe hinzugefügt, **noch nicht ausgeführt**. PDF-Import hält Security Scope während des Einlesens; Seitenauswahl nutzt stabile IDs statt veränderlicher Positionen. Kein Anspruch auf implementierte Unterschrift/OCR-PDF-Funktion.
- Archivindex nach übersprungenen IDs korrigiert; zuvor wirkungsloser CSV-Prüflisten-Schalter wird ausgewertet. CSV nutzt vorhandene Formel-Injection-Absicherung; unbekannte Metadaten bleiben leer. Kein Anspruch auf vollständig bewiesenes Multi-Ressourcen-Archiv.

## Tresor und unabhängiger Review

- Bestehendes Subsystem gezielt aus `claude/fixes-analysis-library-vault-20261014` / `de90f1d67c2dbe753f5da6c012ae6feb9172b277` übernommen: verschlüsselte Medien, Dateien, Notizen, Aufnahmen, Papierkorb, Recovery, biometrisches Öffnen, verschlüsseltes Backup/Restore. Kein Vollmerge; Werbung, neue Free-/Pro-Regeln, Workflows und Store-Assets sind ausgeschlossen.
- VaultCrypto.swift bleibt als versionierter Quellinhalt bytegleich; SHA-256 `4e326b01de50649c8b1189e09021e2b055202479bde21d3cb33c92cf5057022a`. Kein Kryptografieformat geändert, keine produktiven Daten migriert.
- Fail-closed Verbergen-Liste: korrupt/unlesbar/unbekannt oder fehlend bei bestehendem Index ist nicht leer. Isolation muss gespeichert sein, bevor Import/Index-Publikation Erfolg melden; bei Fehlschlag keine Original-Löschabfrage. Authentifiziertes Reparieren und Session-Leases aus dem bestehenden Subsystem erhalten.
- Öffentliche PhotoKit-Zugänge, Previews, Dateien, Metadaten, Verlauf, Backup, Analyse und Duplikatergebnisse sind gefiltert; verspätete Ledger-Projektionen werden vor Veröffentlichung nochmals gegen die Sichtbarkeitsrevision geprüft. Neue optionale EditRecord.sources dokumentiert transitive Ableitungen rückwärtskompatibel. GIF/Stitch/Batch/Collage/Film geben tatsächliche Quellen weiter; Studio-Entwürfe werden nach Visibility-Änderungen erneut gefiltert. Archivlisten verwenden guarded Metadaten und eine Visibility-Fence beim Schreiben.
- Today/Settings öffnen den echten VaultRootView, Hintergrund sperrt und widerruft die Sitzung. Fensterweiter Schutz liegt über verschachtelten Sheets. Vault-Phasenwechsel beachten Reduce Motion.
- 20/Tag, StoreKit, Core-Data-Schema, Entitlements, Pakete und Workflows unverändert; project.yml erlaubt ausschliesslich Face-ID-/Mikrofon-Zwecktexte für die vorhandenen Tresorfunktionen.
- Unabhängiger Review `F:/PhotoMaid-remodel-evidence/review-initial-remodel.md` fand drei konkrete Probleme. Behoben: PrivacyCover über allen Präsentationen; explizit dunkler Medien-Fallback statt weiss-auf-weiss bei erhöhtem Kontrast; Magnification und konkurrierenden Drag gemeinsam bis Gestenende suspendieren. Quellentests ergänzt, Geräteabnahme NOT RUN.
- Grenzen: PhotoMaid-Isolation ist keine Löschung bereits extern geteilter Dateien, iCloud-/Fotos-/Zuletzt-gelöscht-Kopien oder aller alten unzuordenbaren Ableitungen. Bestehende öffentliche Core-Data-/OS-Backups wurden nicht kryptografisch migriert. Kein manipulationssicherer Container oder Schutz gegen beliebige Bildschirmaufnahmen behauptet.

## Tatsächlich ausgeführte Prüfungen

- **PASS:** 26 Python-Quellenverträge nach kompletter Integration (python -m unittest discover -s scripts/tests -v) sowie 10 Vault-Quellenverträge (python scripts/verify_vault_integration.py). Kein Swift-Runtime-Nachweis; insbesondere keine ausgeführten Swift-Sicherheitstests.
- **PASS:** Lokalisierungsvalidator nach Integration: 1219 Kennungen, 2293 logische Einträge, 16 Sprachen. Die drei Remodel-Labels wurden zusätzlich im tatsächlichen Laufzeitkatalog ergänzt und geprüft; der logische Validator allein beweist das nicht.
- **PASS auf Parser-Delta-Ebene:** scripts/check_swift_syntax_delta.py prüfte 186 Swift-Dateien: keine neuen/vermehrten Befunde, dieselben Befunde in fünf Baseline-Dateien. Tree-sitter 0.26.0/swift0.7.4 ist **kein Swift-Compiler**, kein Typ-/SDK-/Strict-Concurrency-Nachweis. git diff --check und Secret-/Workflow-Scopeprüfung bestanden. Parsechecks: 15 Python-Skripte, 7 JSON/Katalog/StoreKit-Dateien, 3 Plist/Entitlement/Privacy-Dateien, 3 YAML-Dateien.
- **FAIL → behoben:** erster Python-Durchlauf verglich Windows-CRLF gegen Git-LF; Vergleich normalisiert jetzt nur Zeilenenden. Später fand der tatsächliche Katalogtest zwei fehlende Remodel-Labels trotz grünem logischem Validator; alle drei Labels wurden im Laufzeitkatalog ergänzt. Danach 26 Prüfungen PASS. Keine bestehende Swift-Assertion abgeschwächt.
- **NOT RUN / BLOCKED:** Swift build/test (swift nicht installiert, tatsächlicher Aufruf exit127), XcodeGen, Xcode-Build, Swift Testing, XCTest, XCUITest, Simulator, Device, Instruments und native Screenshots. Windows, kein Xcode/macOS/iPhone-Runner; WSL nicht installiert, Docker fehlt. Keine CI-Minuten als Ersatz verwendet.

## Noch offen / bewusst nicht als erledigt behauptet

- Tresor-Quellintegration ist abgeschlossen und auf Quellenebene geprüft; native Verschlüsselungs-/Biometrie-/Recovery-/Migrations-/Disk-Failure-Abnahme bleibt NOT RUN. Kein Sicherheitszertifikat und kein Nachweis sicheren Speicher-Nullens oder Screenshot-Verhinderns.
- API-/Typprüfung aller neuen SwiftUI-Aufrufe sowie Bilder/Video/Undo/konkurrierende Gesten auf iPhones unterschiedlicher Grösse.
- Fotozugriff vollständig/begrenzt/verweigert und während Operationen entzogen; iCloud, File Provider, App-Neustart und Migrations-/Datenerhaltungsfälle.
- StoreKit Pending/Restore/Revocation, Premium-Status, Free-Limit und destruktive Systembestätigung. Bestehende Regeln werden nicht still geändert.
- Weitergehende Auditpunkte zu Analyse-Cache/OS-Backup, Editor-Löschjournal/Allowance und Restore-Teilerfolgen verlangen eigene, verifizierte Lösungen; keine riskante Änderung der Geschäfts- oder Migrationsregeln nur für ein visuelles Remodel.
- Accessibility/Dynamic Type/RTL/Reduce Motion/Transparenz auf Hardware; Kontrastberechnung ersetzt keine visuelle Abnahme.
- Keine Produktionsreife, keine Security-Zertifizierung und keine Garantie gegen Screenshots/Screen Recording behauptet.

## Geänderte Dateien gegenüber der auditierten main-Basis

- `PhotoMaid/App/AppModel.swift`
- `PhotoMaid/App/RootView.swift`
- `PhotoMaid/DesignSystem/Components.swift`
- `PhotoMaid/DesignSystem/FeatureChrome.swift`
- `PhotoMaid/DesignSystem/Glass.swift`
- `PhotoMaid/DesignSystem/Tokens.swift`
- `PhotoMaid/Features/Analysis/SmartReviewView.swift`
- `PhotoMaid/Features/Archive/ArchiveView.swift`
- `PhotoMaid/Features/Cleanup/CleanUpHubView.swift`
- `PhotoMaid/Features/Cleanup/DuplicatesView.swift`
- `PhotoMaid/Features/Common/MediaShare.swift`
- `PhotoMaid/Features/Documents/DocumentScannerHost.swift`
- `PhotoMaid/Features/Documents/PdfStudioView.swift`
- `PhotoMaid/Features/Editor/EditSaver.swift`
- `PhotoMaid/Features/Editor/EditsView.swift`
- `PhotoMaid/Features/Feed/FeedMediaPage.swift`
- `PhotoMaid/Features/Feed/FeedView.swift`
- `PhotoMaid/Features/Feed/FeedViewModel.swift`
- `PhotoMaid/Features/Files/FilesView.swift`
- `PhotoMaid/Features/Files/ReceivedView.swift`
- `PhotoMaid/Features/Organize/OrganizeStore.swift`
- `PhotoMaid/Features/Settings/SettingsView.swift`
- `PhotoMaid/Features/Studio/CollageView.swift`
- `PhotoMaid/Features/Studio/MovieView.swift`
- `PhotoMaid/Features/Studio/StudioView.swift`
- `PhotoMaid/Features/Studio/ToolsView.swift`
- `PhotoMaid/Features/Today/TodayView.swift`
- `PhotoMaid/Features/Vault/VaultCapture.swift`
- `PhotoMaid/Features/Vault/VaultDeletionControls.swift`
- `PhotoMaid/Features/Vault/VaultDocumentPreview.swift`
- `PhotoMaid/Features/Vault/VaultHomeView.swift`
- `PhotoMaid/Features/Vault/VaultLockView.swift`
- `PhotoMaid/Features/Vault/VaultRootView.swift`
- `PhotoMaid/Features/Vault/VaultSettingsView.swift`
- `PhotoMaid/Features/Vault/VaultSetupView.swift`
- `PhotoMaid/Features/Vault/VaultViewer.swift`
- `PhotoMaid/Features/Vault/VaultWorkspaceHomeView.swift`
- `PhotoMaid/Features/Vault/VaultWorkspaceToolsView.swift`
- `PhotoMaid/Infrastructure/Archive/ArchiveService.swift`
- `PhotoMaid/Infrastructure/Documents/PdfServices.swift`
- `PhotoMaid/Infrastructure/Editing/BatchProcessor.swift`
- `PhotoMaid/Infrastructure/LocalFiles/ConnectedSources.swift`
- `PhotoMaid/Infrastructure/LocalFiles/FileIndex.swift`
- `PhotoMaid/Infrastructure/PhotoLibrary/MediaSizer.swift`
- `PhotoMaid/Infrastructure/PhotoLibrary/PhotoLibraryService.swift`
- `PhotoMaid/Infrastructure/PhotoLibrary/PreviewPipeline.swift`
- `PhotoMaid/Infrastructure/Playback/FeedPlayer.swift`
- `PhotoMaid/Infrastructure/Vault/VaultBackup.swift`
- `PhotoMaid/Infrastructure/Vault/VaultConcealment.swift`
- `PhotoMaid/Infrastructure/Vault/VaultCrypto.swift`
- `PhotoMaid/Infrastructure/Vault/VaultNoteJournalIO.swift`
- `PhotoMaid/Infrastructure/Vault/VaultStore.swift`
- `PhotoMaid/Infrastructure/Vault/VaultWorkspaceIO.swift`
- `PhotoMaid/Resources/InfoPlist.xcstrings`
- `PhotoMaid/Resources/Localizable.xcstrings`
- `PhotoMaid/Resources/ios_strings.json`
- `PhotoMaidTests/RemodelDocumentTests.swift`
- `PhotoMaidTests/VaultConcealmentTests.swift`
- `PhotoMaidTests/VaultKeychainTests.swift`
- `PhotoMaidUITests/VaultDeletionTests.swift`
- `PhotoMaidUITests/VaultUITestSupport.swift`
- `Sources/PhotoMaidCore/Edit/EditRecipe.swift`
- `Sources/PhotoMaidCore/Vault/Vault.swift`
- `Sources/PhotoMaidCore/Vault/VaultAccessSession.swift`
- `Sources/PhotoMaidCore/Vault/VaultAudioFormat.swift`
- `Sources/PhotoMaidCore/Vault/VaultNoteJournal.swift`
- `Sources/PhotoMaidCore/Vault/VaultSecurity.swift`
- `Sources/PhotoMaidCore/Vault/VaultSnapshot.swift`
- `Sources/PhotoMaidCore/Vault/VaultWorkspace.swift`
- `Tests/PhotoMaidCoreTests/FeedSessionTests.swift`
- `Tests/PhotoMaidCoreTests/GestureMachineTests.swift`
- `Tests/PhotoMaidCoreTests/VaultIntegrationCompatibilityTests.swift`
- `Tests/PhotoMaidCoreTests/VaultSecurityTests.swift`
- `Tests/PhotoMaidCoreTests/VaultTests.swift`
- `Tests/PhotoMaidCoreTests/VaultWorkspaceTests.swift`
- `docs/PHOTOMAID_REMODEL_AUDIT.md`
- `docs/PHOTOMAID_REMODEL_PLAN.md`
- `docs/PHOTOMAID_REMODEL_RESULTS.md`
- `project.yml`
- `scripts/android_strings_to_xcstrings.py`
- `scripts/check_swift_syntax_delta.py`
- `scripts/i18n/ios_strings_remodel.py`
- `scripts/tests/test_remodel_contract.py`
- `scripts/verify_vault_integration.py`

## Verbleibende Abnahme auf einem ausdrücklich freigegebenen Mac

1. `swift build && swift test` (Core).
2. `python3 scripts/android_strings_to_xcstrings.py --check`; `xcodegen generate`.
3. Unsigned Simulator-Build/Test: `xcodebuild -scheme PhotoMaid -destination 'platform=iOS Simulator,name=<tatsächlich verfügbarer Simulator>' CODE_SIGNING_ALLOWED=NO build test`.
4. Native Light/Dark/Accessibility-Screenshots auf kleinem und grossem iPhone; Navigation aller Ziele, Gesten und Undo samt Multi-Touch testen.
5. Tresor auf iPhone mit Face ID/Keychain, verweigerter Original-Löschung, gesperrten/abgebrochenen Aufgaben, korrupten Concealment-Daten, Restore/Backup und App-Umschalter inklusive Sheets prüfen. Nur synthetische isolierte Testmedien verwenden; keine produktiven Datenoperationen ohne Freigabe.
