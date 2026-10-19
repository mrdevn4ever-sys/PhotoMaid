# Silent analysis, PDF editor and four-square Foto Blocks — 19 October 2026

User requests during this change: keep PDF creation, create PDFs from selected files and see the document while editing; use four-square block pieces; prevent the recurring failed photo-analysis cards in the Dynamic Island.

The existing Studio creation card `pdf_title` still opens the existing photo-to-PDF form. The separate document action `remodel_pdf_editor` opens PDF Studio; it did not replace the creation card. The former PDF Studio was a page-action list without a document preview.

## Result and release status

All three requested corrections are implemented on the existing app's main basis. Final native [run 39239130804](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39239130804), source `4b3f02a`, is **SUCCESS**: **502 Core tests, 102 native unit tests, PDF UI 1/1 on iPhone and 1/1 in the wide window**. The final screenshots are inspected. Blocks separately passed on both profiles in run 39231638919; its game/photo source is byte-identical to the final source. Earlier failures and cancellations remain documented below.

Following the explicit instruction “Mach testflight”, these corrections are now in **TestFlight 1.0 (20)** from main, archive source `7634d73`. [Release run 39243456042](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39243456042) passed: 102 repeated native unit tests, eight privacy-checker tests and all three manifests from the signed IPA. Apple finished processing at **11:32:43 UTC** and internal distribution at **11:32:44 UTC** on 19 October 2026. [Upload evidence](testflight/README.md). No external distribution or App Store release. Existing failed analysis cards from an older build may need manual dismissal once.

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
- `scripts/ci/game_visual_tests.sh` — preserve native crash diagnostics before removing UI result bundles, targeted case selection and explicit runtime preference; no workflow or signing changes.
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

## Final verification

| Check | Actual result |
| --- | --- |
| Core, run 39239130804 | 24 XCTest + 478 Swift Testing in 54 suites = **502 PASS**, zero failures |
| Native iOS, same run | 33 XCTest + 69 Swift Testing in 9 suites = **102 PASS**, including 15 PDF and 5 background-lease tests |
| PDF / iPhone 17 / iOS 26.2 | **1/1 PASS**, zero failures/skips, exit 0 |
| PDF / iPad mini A17 Pro wide fallback / iOS 26.2 | **1/1 PASS**, zero failures/skips, exit 0; opens native More and taps the titled Save action |
| Blocks / iPhone 17 / iOS 26.2, run 39231638919 | **1/1 case PASS** |
| Blocks / iPad mini A17 Pro / iOS 26.4.1, same earlier run | **1/1 case PASS**; unchanged game/photo source, whole older workflow is not credited as successful |
| Isolated local Blocks source harness | **29 PASS**, including 20 levels and 10,000 inputs |
| Local strings/source checks | **PASS**, 1742 used keys, 2763 entries, 16 languages; existing translations unchanged |

[Core output](core-result.txt), [native output](native-result.txt), [final phone PDF summary](final-pdf-iphone-summary.json), [final wide PDF summary](final-pdf-wide-summary.json), [Blocks case output](blocks-ui-result.txt), [machine-readable verification](verification.json). Native wide testing is an iPad window check, not real Duo fold/unfold verification.

## Verification history

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
- PASS — earlier complete Core job, run [39229958980](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39229958980), source `39c5af8`: **24 XCTest + 478 Swift Testing tests in 54 suites = 502 tests**, zero failures. Final-source output is linked in the final verification table.
- PASS — combined iOS run [39229241445](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39229241445), source `8d94967`, has completed its native compilation/unit-test phase. The separate iPhone/wide-window UI results are described below. That workflow's Core job failed on the subsequently corrected test-only macro expression; the failure is not hidden. App, Core engine, native tests, UI tests and UI runner are byte-identical between this source and `39c5af8`, as recorded in the source audit.

PASS — earlier complete native run **39229958980**, source `39c5af8`: iOS simulator build plus **33 XCTest + 69 Swift Testing = 102 native tests**, zero failures; includes all 15 PDF and 5 background-lease tests. The final-source extract is linked in the final verification table.

FAIL — fifth iPhone UI attempt: Blocks passed; PDF rotation no longer lost the app/AX connection, but the continuous PDF layout could select a later portrait page after the current page rotated to landscape. The next move then applied to that other page. [Actual summary](attempt-5-iphone-summary.json). The old wide-window continuation was cancelled after collecting the iPhone evidence; no pass is claimed for it.

Correction — page editing now displays one explicit page using PDFKit's native page controller, with horizontal page swipes and the existing thumbnail strip, zoom and search. Rotating cannot implicitly change the page being edited due to another page's visible area. An additional UI assertion checks selection immediately after rotation.

Earlier app-source run [39231638919](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39231638919), source `25648d4`: native compilation/unit-test phase and both iPhone UI cases passed. The additional wide-window phase supplied no result for over 15 minutes, so cancellation was requested. The late artifacts then became available: Blocks passed; the PDF test failed when it tried to tap a Save button that iOS had moved into the native “More” toolbar menu. Rotation, page selection, reordering and deletion had already passed. The UI test was then changed to open the native menu; the following run showed that opening it alone was insufficient. This is **not a successful complete two-device workflow**. [Actual wide result](attempt-7-wide-summary.json).

Results from the earlier app-source run:

- Full Core runner: 24 XCTest + 478 Swift Testing tests = **502 PASS**, zero failures.
- Earlier app-source native compilation and **33 XCTest + 69 Swift Testing = 102 native tests PASS** in run 39231638919/source 25648d4, zero failures. The final source log was preserved after cancellation. The final-source native extract is linked in the final table.
- **iPhone 17 / iOS 26.2: 2/2 UI tests PASS**, zero failures, zero skips; `iphone.exit = 0`. PDF editing 63.518 s, Blocks 68.672 s. [Actual summary](iphone-summary.json).
- **Wide-window UI (iPad mini A17 Pro / iOS 26.4.1): 1 PASS (Blocks), 1 FAIL (PDF save entry not opened)**. The next test opened the native overflow but still could not reach Save; this required an actual toolbar correction, described below.

Targeted retest: [39236285582](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39236285582), source `cd9b8a6`. Only the PDF UI test and the QA device selector changed; the complete production app tree remains byte-identical to source 25648d4. The selector now prefers the same warmed iOS runtime as the phone for the generic wide fallback, instead of an arbitrary cold runtime. It still gives an actual Duo profile precedence if available. No workflow definition, signing, app logic or release configuration changed.

### Later targeted findings and final correction

Run 39236285582/source cd9b8a6 failed both PDF attempts: [iPhone result](attempt-8-iphone-summary.json) stopped before the preview because the synthetic startup files were not loaded; [wide result](attempt-8-wide-summary.json) reached editing and opened the native More control, but Save remained unreachable. It was therefore premature to attribute the wide failure solely to the test.

Corrections in the existing view:

- The simulator-only fixture path now directly awaits the existing production importer in one owning startup task, instead of changing a sibling task's ID during initial view construction. Cancellation makes that fixture startup retryable on the next appearance. Normal file-picker imports are unchanged.
- Actions, Add and Save now have real localized `Label` titles and separate native `ToolbarItem`s. Save uses `.confirmationAction`, giving it primary priority in the adaptive toolbar. Image-only custom groups could leave the native More entry unusable. No document/page logic, storage or app navigation was changed.
- The intermediate run 39238157614/source d7dab84 was cancelled as superseded by the toolbar correction. No UI pass is claimed for it.

Final native verification: **SUCCESS**, run [39239130804](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39239130804), source `4b3f02a`. Both exported UI summaries report Passed with exit 0, zero failures and zero skips. The wide log confirms that native More exposes the titled “Als PDF speichern” action and the test saves successfully.

## Native screenshots

Original, unmodified PDF captures are from final run 39239130804/source 4b3f02a. Blocks captures are from run 39231638919/source 25648d4; the Blocks sources are unchanged:

- [PDF creation: photos or files](screenshots/pdf-create-iphone.png)
- [Large PDF page preview](screenshots/pdf-preview-iphone.png)
- [Rotation keeps the current page selected](screenshots/pdf-rotated-iphone.png)
- [Moved page remains visible](screenshots/pdf-reordered-iphone.png)
- [Saved copy and live preview](screenshots/pdf-saved-iphone.png)
- [Foto Blocks with four-cell pieces](screenshots/blocks-playing-iphone.png)
- [Wide PDF preview](screenshots/pdf-preview-wide.png)
- [Wide rotated page](screenshots/pdf-rotated-wide.png)
- [Wide saved PDF and live preview](screenshots/pdf-saved-wide.png)
- [Wide Foto Blocks](screenshots/blocks-playing-wide.png)

Each capture above has been visually inspected. They show simulator QA documents/photos, not private user media. [Artifact identities and SHA-256 hashes](screenshot-sources.json); [final phone PDF manifest](final-pdf-iphone-manifest.json), [final wide PDF manifest](final-pdf-wide-manifest.json). The briefly visible saved-copy toast is the existing app toast, not a permanent editor overlay.

Not verified: physical-device analysis-card presentation/background duration, real iCloud Drive download/provider behavior, protected external provider documents, very large PDFs, device memory/FPS profiling, and visual localization outside German. Simulator file tests cover local coordinated reads, missing files, invalid files and import limits. The subsequent expressly authorized internal TestFlight upload is documented above; no App Store release was performed.

Complete inventory, including documentation and evidence files: [changed-files.txt](changed-files.txt).
