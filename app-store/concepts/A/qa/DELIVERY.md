# Concept A en-US v1: delivery context

This folder contains the packaged asset layout: ten PNGs under en-US/ plus
root JPEG previews and README.txt. qa/render-manifest-original.json is the
unaltered original renderer report for the flat source render directory
F:/HermesOutput/GaleriQ/concept-a-en-v1/render-r3/; its bare output filenames
are relative to that original directory, not to this packaged layout.
qa/delivery-archive-verification.json binds the actual en-US/ package paths.

The native application capture is commit c6ffd6c4a6279b8fadb2395069f415e84e53370e,
run 43777081132, 1 passed XCTest, 0 failures/0 skips. Later commits in this
branch contain only rendering/design/delivery material; they are not a new
native capture. Original native sources remain at the path in README.txt.
Existing Store assets and other branches are protected. No PR, merge, App
Store Connect upload, submission, release or other locale was performed.

Current acceptance: final-technical.json PASS; final-visual.json
PASS_WITH_OBSERVATIONS. Exact native CTA copy remains BLOCKED: production
says “Remove 2 photos and videos” rather than “Remove 2 photos”.
No product UI/copy or native screenshot was retouched to force conformity.
Owner concept approval and additional Face-ID/security/conversion acceptance
are not implied. Stop for feedback before localization.

Reproduce from the repository root with the genuine original artifact:

    python scripts/store/render_concept_a.py --sources F:/HermesOutput/GaleriQ/concept-a-en-v1/native-run-43777081132-attempt-1 --output F:/HermesOutput/GaleriQ/concept-a-en-v1/reproduced --expected-commit c6ffd6c4a6279b8fadb2395069f415e84e53370e --expected-workflow-run 43777081132 --expected-workflow-url https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/43777081132

Use a new output directory; do not overwrite accepted exports. Run the
independent auditor and repeat final visual review before packaging changed
images.
