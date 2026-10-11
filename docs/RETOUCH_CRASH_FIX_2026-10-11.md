# RetouchPanel crash — 11 October 2026

Incident: `127E94C9-8CFF-4388-9907-B73E79DDB9AD`, PhotoMaid 1.0 (4).
Failure: Swift array bounds trap in the retained Binding getter at EditorPanels.swift:245.
Base: `7a4a41e1d1d6e48c093a91646be41cd0f6d78d0e` (vault isolation/security fixes retained).

## Change

- LocalAdjustment has an immutable UUID, preserved by value copies, Codable, undo and redo.
  Legacy records without an ID receive one during decoding. No IDs are generated in view getters.
- RetouchSelection resolves the identity on EVERY read/write and requires the original context
  revision. Missing, deselected, duplicated and obsolete targets cannot mutate the recipe.
  Missing getters have finite display fallbacks and never change selection or create replacements.
- Both adjustment and radial-size bindings use this policy. The size setter uses current geometry,
  preserves aspect ratio and rejects invalid numeric inputs. Controls have separate stable identities.
- Deletion, brush and linear gestures no longer retain integer array offsets.
  Overlay identity and selection are ID-based as well.
- Undo/redo, reset, geometry-only save, selection, parameter, mode, tool and lifecycle transitions
  settle a pending undo group and invalidate old callbacks. A restored ID does not revive old events.
- A physical stage gesture retains its context until it ends or is cancelled. Late events after
  undo/reset cannot silently create another brush/linear region. Cancellation clears transient state.
- Original media, export algorithms, pricing, navigation, translations and vault logic are unchanged.

## Verification

| Check | Result |
|---|---|
| Original reconstructed source bytes vs Git blob SHAs (EditorModel, EditorPanels, PhotoEditorView, EditRecipe) | PASS before editing |
| Focused Swift 6 retouch core suite, Debug | PASS — 24 tests, 0 failures |
| Same focused suite, optimized Release | PASS — 24 tests, 0 failures |
| Stress case within the suite | PASS — 1,000 invalidation/restore/insert cycles |
| Swift syntax parsing of changed/new Swift files | PASS — syntax only, not Apple SDK type-checking |
| Actual SwiftUI retained-Binding/model regression tests | NOT RUN — 11 tests added to PhotoMaidTests; requires Xcode |
| Full PhotoMaidCore repository suite | NOT RUN |
| iOS compile, simulator and physical-device verification | NOT RUN |
| GitHub Actions / TestFlight upload | NOT RUN |

The focused harness compiles the actual Adjustments.swift, LocalAdjustment.swift and
RetouchSelection.swift repository files with the unchanged RetouchSelectionTests.swift file.
It does not substitute fake production types or claim to run the full application.
Execution environment used here: Swift 6.2.1, x86_64 Linux, Swift 6 language mode.

Reproduce without network dependencies:

```sh
python3 scripts/test_retouch_core.py
python3 scripts/test_retouch_core.py --configuration release
```

The Xcode project already includes the PhotoMaidTests directory automatically. With Xcode available:

```sh
xcodegen generate
xcodebuild -scheme PhotoMaid -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PhotoMaidTests/RetouchBindingTests test
```

Do not label the device crash verified until this test target and the manual cases below pass.
A new TestFlight build was not requested as part of this code fix.

## Required device checks before release

1. Retouch > radial: create the only region, move exposure/size, delete, undo, redo, reset.
2. Repeat with multiple regions; verify no remaining region changes unexpectedly.
3. While dragging a slider/brush/linear region, undo/reset or switch parameter/mode/tool.
   No crash, recreated region, wrong target or duplicate undo step is allowed.
4. Cancel a stage gesture with zoom, background/resume the app, then begin a new gesture.
   The first new gesture must work; cancelled gestures must not resume.
5. Remove pro tools through geometry-only save, dismiss/reopen the editor, and save a copy.
   Confirm original media and the separate vault protections remain unchanged.
