# Silent analysis, PDF editor and four-square Foto Blocks — 19 October 2026

User requests during this change: keep PDF creation, create PDFs from selected files and see the document while editing; use four-square block pieces; prevent the recurring failed photo-analysis cards in the Dynamic Island.

The existing Studio creation card `pdf_title` still opens the existing photo-to-PDF form. The separate document action `remodel_pdf_editor` opens PDF Studio; it did not replace the creation card. The former PDF Studio was a page-action list without a document preview.

## Result and release status

The source implements all three requested corrections. Current-source native compilation/unit-test phase and the two targeted iPhone UI cases passed. Full Core: **502 tests PASS**. The preceding complete green native run reports **102 tests PASS**, including 15 PDF and 5 analysis lease tests; current native test sources are unchanged. The supplementary wide-window run did not finish and remains **NOT VERIFIED**.

No TestFlight upload or App Store release was started for these corrections. The latest previously distributed build remains **1.0 (19)** and does not contain them. Existing failed analysis cards from an older build may need manual dismissal once.

## Implementation

- **PDF erstellen:** retains the photo picker, layout, margins, paper sizes and contact sheets. A separate **PDF aus Dateien erstellen** action opens the system multi-file picker.
- **PDF bearbeiten:** full PDFKit page preview, zoom, page swipes, selectable page thumbnails, clockwise rotation, move earlier/later, page deletion, multi-page selection, text search/highlighting, add more files, save and share a new copy. The last page cannot be removed.
- Selected PDFs and image files can be combined into one PDF. Images are orientation-correct, proportionally fitted on A4 and decoded with a bounded 2480-pixel thumbnail. Office documents and arbitrary file formats are not advertised as supported.
- Provider files are read asynchronously under balanced security-scoped access using `NSFileCoordinator`, including materialization by an iCloud Drive provider. No provider URLs survive the import; the editor owns PDF bytes. Imports are atomic: one bad file does not replace or partially append the current pages.
- Page identity survives reordering. Preview and export apply the same `PdfPageRef` plan to copies of source pages. Changes invalidate the share action for the older saved copy, while previously saved files remain intact.
- Cached thumbnails are reused after reordering. Import limits: 100 MiB per file, 256 MiB of input per selection, 500 total source pages per editor session.
- Feed, Snake, Paare, vault encryption, original media, signing and workflow definitions are unchanged. Blocks and analysis changes are described below.
- All 14 new labels (12 PDF, 2 analysis) have explicit translations for all 16 supported languages; previous catalog values are unchanged.

## Failed analysis system cards

The old analysis controller created `BGContinuedProcessingTaskRequest` jobs. These have an OS-owned visible Live Activity. Ordinary stops and expiry paths completed them unsuccessfully, leaving the reported “Fotos werden analysiert / Vorgang fehlgeschlagen” cards.

Analysis now uses a single ordinary `UIApplication.beginBackgroundTask` lease, which creates no analysis Live Activity. The existing background preference remains saved. Analysis continues only for the background time iOS grants; on expiry it checkpoints and resumes when the app is reopened. Foreground work, saved results, queued analyses, iCloud options and vault filtering remain in place. Returning to the app while cancellation is still finishing also resumes correctly.

The lease balances begin/end, ignores stale expiration callbacks and ends once. Migration cancels only pending requests matching this app's old `.analysis.<UUID>` identifiers. Export jobs are unchanged.

The five native lease tests inject begin/end/expiration callbacks. They verify lifecycle behavior; they do not measure physical-device background duration or inspect a real iPhone's system-card presentation.

Already completed cards owned by an older installed build cannot be programmatically dismissed retroactively. An existing card may need to be closed manually once. The source change prevents new analysis cards; on-device OS presentation is not independently verified here.

Apple documentation: [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask), [long-running tasks](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados/).

## Foto Blocks: four-square pieces

New draws use seven connected shapes, each made from exactly four equal square cells. Board size remains PhotoMaid's 9×17. Photo reveal, ten-row levels, carry-over, scoring, speed curve, gestures, iCloud photo source and vault restrictions remain unchanged. The four-cell line has additional bounded wall/floor rotation offsets; every candidate still uses the existing collision check.

Legacy enum raw values and their exact old footprints remain decodable. A saved active piece and its already-visible next piece finish unchanged. Remaining legacy bag entries are replaced only for future draws. Existing placed cells, progress and records are preserved.

The product remains **Foto Blocks**, with its own palette, photo reveal, interface and board proportions. No external game code, art, logos or sounds were imported. This is not legal clearance: the combination of familiar shapes and presentation can still create copyright/trade-dress risk. [Tetris Holding v. Xio, US District Court opinion](https://law.justia.com/cases/federal/district-courts/new-jersey/njdce/3:2009cv06115/235418/61/) distinguishes abstract rules from protected expression and found liability for a much closer overall imitation. Commercial name/mark and jurisdiction-specific review remain open.

## File inventory

Production:

- `PhotoMaid/Features/Documents/PdfFromPhotosView.swift` — keep photo creation and offer file creation.
- `PhotoMaid/Features/Documents/PdfStudioView.swift` — live preview and page-editing controls.
- `PhotoMaid/Features/Documents/PdfEditorModel.swift` — atomic imports, stable page identities, page plan, preview, thumbnail cache and save state.
- `PhotoMaid/Features/Documents/PdfDocumentPreview.swift` — PDFKit/SwiftUI bridge, synchronized page selection and search highlighting.
- `PhotoMaid/Infrastructure/Documents/PdfServices.swift` — coordinated scoped reads, image-to-PDF conversion, shared preview/export composition.
- `PhotoMaid/Features/Studio/StudioView.swift` — explicit description of the separate page editor.
- `PhotoMaid/Resources/ios_strings.json`, `PhotoMaid/Resources/Localizable.xcstrings`, `scripts/i18n/ios_strings_part_pdf_editor.py` — 16-language labels.

Tests:

- `PhotoMaidTests/PdfEditorTests.swift` — fifteen native behavioral tests.
- `PhotoMaidUITests/PhotoGameVisualTests.swift` — targeted PDF creation/editing UI test and screenshot checkpoints.
- `scripts/ci/game_visual_tests.sh` — preserve native crash diagnostics before removing UI result bundles; no workflow or signing changes.
- `PhotoMaid/App/PdfEditorFixtures.swift` — synthetic files, compiled only with `QA_FIXTURES` on a simulator and loaded only with the explicit `-pdf-editor-fixtures` argument. They pass through the production importer.

Analysis and Blocks additions:

- `PhotoMaid/Infrastructure/Analysis/AnalysisBackgroundTime.swift` — single silent background lease and narrow legacy request matcher.
- `PhotoMaid/Infrastructure/Analysis/AnalysisController.swift` — remove visible continued-processing analysis jobs; checkpoint/resume and migration.
- `PhotoMaid/Features/Analysis/SmartReviewView.swift` — honest background-time label and explanation.
- `PhotoMaidTests/AnalysisBackgroundTimeTests.swift` — five tests for balance, expiry, denied time, stale callbacks and migration scope.
- `Sources/PhotoMaidCore/Games/PhotoBlocksShapes.swift` — seven four-square playable forms; preserve old raw values and footprints.
- `Sources/PhotoMaidCore/Games/PhotoBlocksGame.swift` — modern shape bag and bounded four-cell-line rotation offsets.
- `PhotoMaid/Features/Blocks/PhotoBlocksBoard.swift` — exhaustive own-palette rendering for the added forms.
- `Tests/PhotoMaidCoreTests/PhotoBlocksGameTests.swift` — geometry, rotation, four-row reveal and legacy-session migration regressions.
- `scripts/i18n/ios_strings_part_analysis_background.py` — two analysis labels in 16 languages.

Exact changed source inventory, untouched path checks, unchanged existing translations and Git tree identities: [source-audit.json](source-audit.json).

## Verification

- PASS — local Swift frontend syntax parsing of eight changed/new Swift files. This is not an Apple SDK build.
- PASS — final localization validator: 1742 used identifiers, 2763 catalog entries, all 16 languages.
- PASS — existing translation values unchanged and production change scope audited.
- PASS — first native app compilation and unit-test phase.
- PASS — first core run: 24 XCTest tests plus 475 Swift Testing tests in 54 suites (499 total), zero failures.
- FAIL — first iPhone UI attempt lost the app/AX connection immediately after rotating a page. File creation, system picker and initial three-page preview had succeeded. The enclosing continue-on-error step initially appeared successful, but `iphone.exit` was 65 and the xcresult summary reported one failed test; those artifacts are authoritative.
- Correction — create a fresh PDFKit view for each document snapshot and release its page tree with its own text/AX subviews. Bound the horizontal thumbnail strip to 100 pt, giving the PDF more than half the initial phone screen. Compact labelled page actions remain directly available.
- FAIL — second iPhone attempt reproduced the same lost app/AX connection after rotation; a fresh view alone was insufficient. The larger preview passed its initial layout assertion. Full summaries for both failed attempts are retained beside this report.
- Additional correction — serialize and reopen each composed preview so it has independent native CGPDF backing. Two additional native tests verify backing isolation and repeated rendering/rotation while an older PDF remains visible. UI checks also verify that the visible selected page follows reordering and that deletion removes the correct page.
- The intermediate third run was cancelled before completion to include a viewport-scaling correction and its native zoom regression test. No result is claimed for that run.
- FAIL — fourth run compiled the app, passed 14/15 PDF tests and failed a test's incorrect expectation that changing height alone increases PDFKit's width-based fit. The test now changes both width and height; production scaling code did not need another change. UI tests did not run behind that failed unit-test gate.
- PASS — isolated local Blocks harness: 29 tests in 3 suites using exact copies of the current four engine files and three test files; includes every new form at both walls/floor, four-row reveal, old saved games, 20 level transitions, 10,000 inputs, pause/restart and photo exclusion tests. No external dependencies or new app/repository. The first harness compilation caught a mutating-call Swift Testing macro expression in a new test; changing it to test the returned Boolean fixed compilation. A separate attempt to run the entire package locally was blocked by the container's missing C++ standard-library headers; that attempt is not a test pass.
- PASS — final full Core job, run [39229958980](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39229958980), source `39c5af8`: **24 XCTest + 478 Swift Testing tests in 54 suites = 502 tests**, zero failures. [Relevant native runner output](core-result.txt).
- PASS — combined iOS run [39229241445](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39229241445), source `8d94967`, has completed its native compilation/unit-test phase. Detailed counts and the separate iPhone/wide-window UI artifacts are pending below. That workflow's Core job failed on the subsequently corrected test-only macro expression; the failure is not hidden. App, Core engine, native tests, UI tests and UI runner are byte-identical between this source and `39c5af8`, as recorded in the source audit.

PASS — final full native run **39229958980**, source `39c5af8`: iOS simulator build plus **33 XCTest + 69 Swift Testing = 102 native tests**, zero failures; includes all 15 PDF and 5 background-lease tests. [Native result extract](native-result.txt).

FAIL — fifth iPhone UI attempt: Blocks passed; PDF rotation no longer lost the app/AX connection, but the continuous PDF layout could select a later portrait page after the current page rotated to landscape. The next move then applied to that other page. [Actual summary](attempt-5-iphone-summary.json). The old wide-window continuation was cancelled after collecting the iPhone evidence; no pass is claimed for it.

Correction — page editing now displays one explicit page using PDFKit's native page controller, with horizontal page swipes and the existing thumbnail strip, zoom and search. Rotating cannot implicitly change the page being edited due to another page's visible area. An additional UI assertion checks selection immediately after rotation.

Current-source run [39231638919](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39231638919), source `25648d4`: native compilation/unit-test phase and both iPhone UI cases passed. The additional wide-window phase supplied no final result for more than 15 minutes and cancellation was requested. This is **not a successful complete two-device workflow**; the cause of the incomplete wide run is unverified.

Current-source results already confirmed:

- Full Core runner: 24 XCTest + 478 Swift Testing tests = **502 PASS**, zero failures.
- Current-source native app compilation and unit-test phase: **PASS**. The detailed 102-test extract above belongs to the preceding complete green run 39229958980; the native test sources are unchanged. The later source change configures the PDFKit bridge for one selected page and strengthens its UI assertion.
- **iPhone 17 / iOS 26.2: 2/2 UI tests PASS**, zero failures, zero skips; `iphone.exit = 0`. PDF editing 63.518 s, Blocks 68.672 s. [Actual summary](iphone-summary.json).
- **Wide-window UI: NOT VERIFIED**. The run did not finish and was cancelled; no pass or root cause is claimed. iPhone evidence was downloaded and checked before cancellation.

## Native screenshots

Original, unmodified iPhone captures from run 39231638919/source 25648d4:

- [PDF creation: photos or files](screenshots/pdf-create-iphone.png)
- [Large PDF page preview](screenshots/pdf-preview-iphone.png)
- [Rotation keeps the current page selected](screenshots/pdf-rotated-iphone.png)
- [Moved page remains visible](screenshots/pdf-reordered-iphone.png)
- [Saved copy and live preview](screenshots/pdf-saved-iphone.png)
- [Foto Blocks with four-cell pieces](screenshots/blocks-playing-iphone.png)

Each capture above has been visually inspected. They show simulator QA documents/photos, not private user media. [Artifact identities and SHA-256 hashes](screenshot-sources.json); [original iPhone attachment manifest](iphone-attachment-manifest.json). The briefly visible saved-copy toast is the existing app toast, not a permanent editor overlay.

Not verified: the final wide-window UI, physical-device analysis-card presentation/background duration, real iCloud Drive download/provider behavior, protected external provider documents, very large PDFs, device memory/FPS profiling, and visual localization outside German. Simulator file tests cover local coordinated reads, missing files, invalid files and import limits. No new TestFlight upload or App Store release is part of this PDF correction.
