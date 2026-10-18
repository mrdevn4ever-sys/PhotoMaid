# Foto Blocks · Prüfbelege

[Implementierung, Regeln, Datenschutz und Abnahme](../PHOTO_BLOCKS.md).

Lokale Ergebnisse: **494 Core-Tests PASS** (470 Swift Testing + 24 XCTest), **22 neue Blocks-Tests**;
15 native Swift-Dateien syntaktisch geprüft (13 Produktion + 2 Tests), **kein lokaler iOS-Build**.
Native CI und anschließend ausdrücklich beauftragter interner TestFlight-Upload sind nach
„Du kannst jederzeit minutes brauchen zum testen“ freigegeben und werden ergänzt.

## Geänderte Dateien für diesen Blocks-Auftrag

| Dateien | Aufgabe |
|---|---|
| `Sources/PhotoMaidCore/Games/PhotoBlocksShapes.swift` | eigene Formen, Rotation, gespeicherter Zufall |
| `Sources/PhotoMaidCore/Games/PhotoBlocksGame.swift` | Board, Kollision, Zustände, Levels, Score, bildfreies Archiv |
| `Sources/PhotoMaidCore/Games/PhotoBlocksInput.swift` | Tap, Achsensperre, Drag-Wiederholung, Soft/Hard Drop |
| `Sources/PhotoMaidCore/Games/PhotoBlocksPhotos.swift` | Metadatenreihenfolge und feste Fotoabschnitte |
| `PhotoMaid/Features/Blocks/PhotoBlocksModel.swift` | App-Runde, zentraler Fotozugang, Checkpoints, Berechtigungswechsel |
| `PhotoMaid/Features/Blocks/PhotoBlocksClock.swift` | ein DisplayLink, schwaches Ziel, Pause/Abbau |
| `PhotoMaid/Features/Blocks/PhotoBlocksTouchView.swift` | ein UIKit-Touchpfad für die Engine-Eingaben |
| `PhotoMaid/Features/Blocks/PhotoBlocksBoard.swift` | Foto/Maske getrennt von Canvas-Steinen, nächste Form |
| `PhotoMaid/Features/Blocks/PhotoBlocksView.swift` | Start, HUD, Fotoquelle, Pause, Game Over, Lebenszyklus |
| `PhotoMaid/App/AppModel.swift` | App-eigene Runde, Scope-Updates, Tresor-Invalidierung |
| `PhotoMaid/Persistence/KeyValueStore.swift` | additiver Blocks-Schlüssel; alte Daten bleiben erhalten |
| `PhotoMaid/Features/Games/PhotoGamePhotos.swift` | zentraler Offline-Scope und begrenztes Vorschaufenster |
| `PhotoMaid/Infrastructure/PhotoLibrary/PreviewPipeline.swift` | optionale exakte Auflösung; Standard unverändert |
| `PhotoMaid/DesignSystem/Components.swift` | optionaler Offline-/Tresor-Gate für bestehende Rasterzellen |
| `PhotoMaid/Features/Studio/StudioMediaPicker.swift` | bestehende Auswahl mit optionalem sicheren Offline-Scope |
| `PhotoMaid/Features/Games/PhotoGamesView.swift` | Blocks-Kachel und Navigation |
| `PhotoMaid/Features/Games/PhotoGameRecordsView.swift` | Blocks-Rekord und Speicher-Wiederholung |
| `PhotoMaid/Resources/ios_strings.json`, `Localizable.xcstrings` | 41 Blocks-Kennungen × 16 Sprachen |
| `Tests/PhotoMaidCoreTests/PhotoBlocksGameTests.swift`, `PhotoBlocksInputTests.swift`, `PhotoBlocksPhotosTests.swift` | 22 lokale Engine-/Input-/Foto-Tests |
| `PhotoMaidTests/PhotoBlocksIntegrationTests.swift` | fünf neue native Integrationsfälle |
| `PhotoMaidUITests/PhotoBlocksVisualTests.swift` | echter Start-/Touch-/Pause-/Foto-/Navigationsdurchlauf |
| `scripts/check_photo_blocks.py` | statischer Offline-/Target-/Rekord-/Snake-/Sprachen-Audit |
| `scripts/check_snakephoto_integration.py` | ausschließlich neue Blocks-Textkennungen zusätzlich zulassen |
| `scripts/assets/review_photo_blocks.py` | dokumentierte statische Ansicht aus Core-Zuständen |
| `scripts/ci/game_visual_tests.sh`, `.github/workflows/ci.yml` | gezielte Blocks-UI-Auswahl, bestehender manueller Workflow |
| `CLAUDE.md`, `docs/IMPLEMENTATION_STATUS.md`, `docs/PHOTO_BLOCKS.md`, dieser Ordner | Freigaben, Status, vollständige Dokumentation/Belege |

Bereits vorhandene uncommittete Snake-Änderungen gehören zum vorherigen Auftrag und werden nicht
als Blocks-Arbeit ausgegeben. `snake-baseline.json` beweist ihre Unverändertheit seit Blocks-Auftragsbeginn.

## Lokale Wiederholung

```sh
swift test --build-system native --disable-automatic-resolution
python3 scripts/check_photo_blocks.py
python3 scripts/check_snakephoto_integration.py
python3 scripts/android_strings_to_xcstrings.py --check
python3 -m unittest discover -s scripts/ci -p 'test_check_privacy_manifests.py' -v
python3 scripts/ci/check_privacy_manifests.py PhotoMaid/Resources/PrivacyInfo.xcprivacy
swiftc -O -swift-version 6 Sources/PhotoMaidCore/Games/PhotoBlocks*.swift \
  docs/photo-blocks-20261018/BlocksReviewProbe.swift -o /tmp/BlocksReview
/tmp/BlocksReview > docs/photo-blocks-20261018/engine-states.json
python3 scripts/assets/review_photo_blocks.py
```

Der lokale Lauf verwendete die vorhandene Swift-6.4.1-Toolchain offline in einem kleinen Container
mit read-only Toolchain-Mounts. Keine weiteren Pakete heruntergeladen. `core-tests.log` ist der
vollständige bestandene Lauf, die vorherigen Fehlerlogs bleiben unverändert. `native-syntax.log`
ist bei Erfolg leer; Syntax-Parsing prüft keine Apple-Typen oder Laufzeitdarstellung.

Die statische PNG wurde angesehen: Kontrast, korrektes Ausblenden der Steine bei 100 %, unterschiedliches
Folgefoto, 10-%-Übertrag und Erhalt der verbleibenden Steine nachvollziehbar. Das beweist keine native
SwiftUI-Darstellung oder 60 FPS. Native Screenshots werden erst nach echter Simulatoraufnahme so benannt.
