# TestFlight 1.0 (20) — main

The user explicitly requested “Mach testflight”. The existing manual workflow was dispatched once, with native tests enabled and `confirm_upload=UPLOAD`. No signing, secrets, workflow definitions or app code were changed for this upload.

- Archive source: `7634d7304e462a475620db909f7b1b48b4d3ff66`, branch `main`.
- App/test/script content is unchanged from the verified native source `4b3f02a2f6791d2ec8905ae219f540c0793782f0`; intervening changes were documentation and evidence only.
- [Release run 39243456042](https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/39243456042): **SUCCESS**.
- Repeated native tests: **33 XCTest + 69 Swift Testing = 102 PASS**, zero failures.
- Signing preflight: **PASS**. Release archive, signed IPA export and upload: **PASS**.
- Privacy checker: **8 tests PASS**; all **3 manifests of the actual signed IPA PASS**. This checks the declared tracking/domain rules, not every privacy-policy or runtime behavior requirement.
- Upload accepted by App Store Connect: **2026-10-19 11:30:09 UTC**.
- Apple processing finished for **1.0 (20)**: **2026-10-19 11:32:43 UTC**.
- Changelog set and internal distribution confirmed by Fastlane: **2026-10-19 11:32:44 UTC**.
- No external distribution or App Store submission. Installation on the user's iPhone is not independently observed.

The build includes silent bounded background analysis with checkpoint/resume, PDF creation from files and visible PDF editing, and four-square Foto Blocks with legacy-session preservation. Existing OS-owned failed analysis cards from an older version may need manual dismissal once. Physical-device and real iCloud-provider limits from the parent report still apply.

Evidence: [release metadata](release.json), [upload/Apple processing log excerpt](upload-evidence.txt), [native test excerpt](native-result.txt), [signed IPA privacy report](privacy-manifests.json). Original GitHub artifact: `testflight-report`, ID `12183196416`. The original artifact also contains full unit-test and archive logs and Fastlane's XML result. Later repository changes for this release record are documentation only.
