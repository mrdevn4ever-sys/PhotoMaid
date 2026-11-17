#!/usr/bin/env python3
"""Independent, read-only Concept A V4 export auditor. No renderer imports.

Known accepted audit primitives are reused without patching their globals. V4
sequence, copy, source gate, editor composite and pixel masks are independently
stated here. A structural test PASS is NEVER native, visual or delivery approval.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import re

from PIL import Image, ImageChops, ImageCms, ImageDraw, ImageFilter, ImageFont

import audit_concept_a as reference

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DESIGN = ROOT / "app-store/concepts/A/v4-design.json"
OUTPUT_ROOT = Path("F:/HermesOutput/GaleriQ/concept-a-en-v4")
VERSION = "concept-a-v4/1"
SIZE = (1206, 2622)
BASELINE = "61800c00f0cc572cd7221d95355f04d7f1cc505e"
MEDIA_POLICY = "approved-stock-photos-and-videos-no-app-screenshots"
SCENE_POLICY = "v4-mixed-approved-originals-real-month-progress-published-editor-pair"
CAPTURE_TEST = "AppStoreCaptureTests/test08ConceptAV4StoreScreenshots"
COPY = ["Swipe the clutter. Keep the memories.", "Find duplicates. Free up space.",
        "Similar shots. Keep your favorites.", "You decide what gets deleted.", "Private photos. Locked away.",
        "Not sure yet? Decide later.", "Clean up by month. See your progress.", "Make a collage. With your photos.",
        "Try a new look. Keep the original.", "Take a break. Play a little."]
SUBTITLES = ["Keep, trash or decide later.", "Find extra copies and large files.", "Review a series before you decide.",
             "Review your choices before deleting.", "Encrypted vault, protected by your own code and Face ID.",
             "Come back when you are ready.", "Pick a month and see your progress.", "Choose photos, a layout and a style.",
             "Preview a look and save a separate copy.", "Match pairs with your own photos."]
PRIMARIES = ("swipe", "large-files", "analysis", "delete-confirm", "vault", "later-swipe", "v4-months", "collage", "v4-editor-after", "games")
INSETS = {2: ("duplicate-results", "duplicates", {"duplicate-pair", "selection-labels"}),
          3: ("series-decision", "analysis", {"series", "keep5-trash1"}),
          4: ("system-dialog", "delete-confirm", {"system-dialog"})}
LEGACY_SCREENS = {f"screenshots/concept-a-{name}.png" for name in (
    "swipe", "duplicates", "large-files", "trash", "delete-confirm", "vault", "later", "later-swipe", "months", "analysis", "collage", "editor", "games", "games-menu")}
NEW_SCREENS = {f"screenshots/concept-a-v4-{name}.png" for name in (
    "months", "editor-before", "editor-after", "editor-undo", "editor-redo", "editor-copy-default")}
WORDMARK = "branding/native-wordmark.png"
REVIEW = {"stockOnlyEveryMediaTile", "sharpRecognizableFirstPhoto", "opaqueSystemDialogNoUnderlyingHome", "noLoadingSpinner",
          "heldRightwardLater", "filledNativePairsBoard", "nativeKeep5Trash1", "completeDuplicatePair", "actualMonthProgress",
          "editorPublishedOriginalWarmUndoRedo", "editorCopyDefault", "editorComparisonTruthful", "allTenFromSameNewAttempt"}
COMPOSITE_KIND = "creative-composite-photo-comparison"
COMPOSITE_SOURCES = ("screenshots/concept-a-v4-editor-before.png", "screenshots/concept-a-v4-editor-after.png")
FLAT = {"radius": 0, "shadowBlur": 0, "shadowOffset": [0, 0], "shadowAlpha": 0}
need, digest = reference.need, reference.digest
within, intersects, dimensions = reference.within, reference.intersects, reference.dimensions
raw_sha, rounded, full_mask = reference.raw_sha, reference.rounded, reference.full_mask


def load(path):
    def unique(pairs):
        out = {}
        for key, value in pairs:
            need(key not in out, "Duplicate JSON key: " + key)
            out[key] = value
        return out
    value = json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=unique,
                       parse_constant=lambda token: (_ for _ in ()).throw(ValueError("Nonfinite JSON: " + token)))
    need(type(value) is dict, "Expected JSON object")
    return value


def keys(value, expected, label):
    need(type(value) is dict and set(value) == set(expected), "Missing/unknown " + label + " fields")


def integer_rect(value, label, bounds=(1206, 2622)):
    need(type(value) is list and len(value) == 4 and all(type(n) is int for n in value) and within(value, [0, 0, *bounds]), "Invalid integer " + label)
    return value


def source_path(root, name):
    need(type(name) is str and name and "\\" not in name and ":" not in name and not any(ord(c) < 32 for c in name), "Unsafe native path")
    rel = PurePosixPath(name)
    need(not rel.is_absolute() and rel.as_posix() == name and ".." not in rel.parts, "Noncanonical native path")
    return reference.source_path(Path(root), name)


def optional_sha(value):
    need(value is None or (type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value)), "Malformed literal SHA-256")


# Independent policy pins; the auditor never imports the V4 renderer.
C5_RUN = "43949822336"
C5_COMMIT = "90da2494af7dbeffe8c8694ee33f42c4f3ac78f0"
C5_READBACK_SHA = "83d970ee192bf3d5e04bd71308055f38f82ca527db235d5c08da78b2c52f7807"
C5_OWNER_SHA = "dd3f90ce02fed8b611bf3ac7159c06faf63b6ac48ba4cdcf632177836c48a5c5"
C5_INVENTORY_SHA = "88a4a267eb7686cfb7dbf0480da037ce67b0440d06483e0042305be3aa50dde1"
C5_ORIGINAL_SHA = "b916d032f001dc2691c7ec45ac2511827fcec350d24d6c0e4215830af5507d50"
C5_KIND = "owner-authorized-C5-postcapture-workflow-exception"
C5_ERRORS = [
    "native_screens: ValueError: Unrelated required native screen states unexpectedly share a file hash",
    "month_progress: ValueError: Proof does not bind an independently inventoried required source",
    "editor_pair: ValueError: Proof does not bind an independently inventoried required source",
]
C5_FAILED_STEP = "Bind actual sources, test result and native logo to this exact run and SHA"


def validate_c5_owner_authorization(owner, sources):
    keys(owner, {"schema", "status", "recorded_utc", "user_response", "quoted_offer", "run", "attempt", "capture_commit",
                 "failed_workflow_exception_authorized", "additional_native_run_authorized", "workflow_conclusion_preserved", "source_approval",
                 "raw_artifact_manifest", "derived_sources", "restrictions"}, "C5 owner decision")
    need(type(owner["schema"]) is int and owner["schema"] == 1 and owner["status"] == "OWNER_AUTHORIZED_TARGETED_C5_REVALIDATION_NOT_SOURCE_ACCEPTANCE"
         and owner["user_response"] == "Weiter" and type(owner["quoted_offer"]) is str and "„C5 verwenden“" in owner["quoted_offer"]
         and type(owner["recorded_utc"]) is str and bool(owner["recorded_utc"]), "Actual explicit C5 owner decision required")
    need(owner["run"] == C5_RUN and type(owner["attempt"]) is int and owner["attempt"] == 1 and owner["capture_commit"] == C5_COMMIT
         and owner["failed_workflow_exception_authorized"] is True and owner["additional_native_run_authorized"] is False
         and owner["source_approval"] is False and owner["workflow_conclusion_preserved"] == "failure", "C5 owner decision has another scope or grants unearned approval")
    path = OUTPUT_ROOT / "revalidated-C5-43949822336-attempt-1/sources"
    need(owner["derived_sources"] == path.as_posix() and Path(sources).resolve() == path.resolve()
         and owner["raw_artifact_manifest"] == "qa/c5-original-artifact-immutable-snapshot.json"
         and owner["restrictions"] == ["No native capture/dispatch/rerun", "No PR/merge/ASC/localization", "Preserve v1/v2/v3/final archives",
                                       "Do not edit raw C5 evidence", "Independent real revalidation and source/final VQA required"], "Owner permits only the exact DERIVED C5 root with all original restrictions")


def validate_c5_readback(readback, provenance):
    """Reconstruct actual C5 API facts independently; never infer green from XCTest."""
    need(provenance.get("workflow_run") == C5_RUN and provenance.get("run_attempt") == "1" and provenance.get("commit") == C5_COMMIT
         and provenance.get("branch") == "hermes/store-concept-a-en" and provenance.get("fresh_capture") is True
         and provenance.get("locale") == "en-US" and provenance.get("app_language") == "en"
         and provenance.get("workflow_url") in ("https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/43949822336",
                                                "https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/43949822336/attempts/1"), "C5 exception cannot bind another native run/attempt/SHA")
    a, listing, wrapper = readback.get("attempt_readback"), readback.get("attempt_jobs_readback"), readback.get("run")
    need(all(type(x) is dict for x in (a, listing, wrapper)), "Complete exact C5 attempt, jobs and wrapper responses required")
    for key, expected in {"id": 43949822336, "workflow_id": 389136991, "run_attempt": 1}.items():
        need(type(a.get(key)) is int and a[key] == expected, "Literal C5 API integer pin differs: " + key)
    need(type(readback.get("run_attempt")) is int and readback["run_attempt"] == 1 and a.get("head_sha") == C5_COMMIT
         and a.get("head_branch") == "hermes/store-concept-a-en" and a.get("event") == "workflow_dispatch"
         and (a.get("status"), a.get("conclusion")) == ("completed", "failure"), "C5 actual workflow must remain completed/failure")
    web = "https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/43949822336"
    api = "https://api.github.com/repos/mrdevn4ever-sys/PhotoMaid/actions/runs/43949822336"
    need(a.get("url") == api and a.get("html_url") == web and a.get("jobs_url") == api + "/attempts/1/jobs"
         and a.get("workflow_url") == "https://api.github.com/repos/mrdevn4ever-sys/PhotoMaid/actions/workflows/389136991"
         and ("request_url" not in readback or readback["request_url"] == api + "/attempts/1"), "Wrong C5 exact-attempt API endpoint")
    jobs = listing.get("jobs")
    need(type(listing.get("total_count")) is int and listing["total_count"] == 1 and type(jobs) is list and len(jobs) == 1, "Partial, duplicate or extra C5 jobs rejected")
    job = jobs[0]
    need(type(job) is dict, "Actual C5 job must be an object")
    for key, expected in {"id": 133589042502, "run_id": 43949822336, "run_attempt": 1}.items():
        need(type(job.get(key)) is int and job[key] == expected, "C5 job literal integer differs: " + key)
    need(job.get("head_sha") == C5_COMMIT and job.get("head_branch") == "hermes/store-concept-a-en" and job.get("run_url") == api
         and (job.get("status"), job.get("conclusion")) == ("completed", "failure"), "C5 job must be this completed failed attempt")
    steps = job.get("steps")
    need(type(steps) is list and len(steps) == 13 and all(type(x) is dict and type(x.get("number")) is int for x in steps)
         and [x["number"] for x in steps] == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 22, 23], "Actual full C5 job step sequence required")
    for step in steps:
        need(step.get("status") == "completed" and step.get("conclusion") == ("failure" if step["number"] == 9 else "success"),
             "Only the one postcapture binding step may fail; no skipped/pending capture or other failure")
        for key in ("started_at", "completed_at"):
            need(type(step.get(key)) is str and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", step[key]), "Missing actual native step timestamp")
        need(step["started_at"] <= step["completed_at"], "Reversed native step timestamps")
    build, capture, failed = steps[4], steps[7], steps[8]
    need(build.get("name") == "Build current app and capture test without Apple credentials"
         and capture.get("name") == "Capture real swipes, finished results, trash confirmation, vault and creative tools" and failed.get("name") == C5_FAILED_STEP
         and build["completed_at"] <= capture["started_at"] and capture["completed_at"] <= failed["started_at"], "Failed step is not strictly after genuine successful build/capture")
    need(type(wrapper.get("databaseId")) is int and wrapper["databaseId"] == 43949822336 and type(wrapper.get("runAttempt")) is int and wrapper["runAttempt"] == 1
         and wrapper.get("headSha") == C5_COMMIT and wrapper.get("headBranch") == "hermes/store-concept-a-en" and wrapper.get("event") == "workflow_dispatch"
         and (wrapper.get("status"), wrapper.get("conclusion")) == ("completed", "failure") and wrapper.get("url") == web and wrapper.get("jobs") == jobs,
         "Latest-run wrapper disagrees or substitutes a rerun")
    artifact_listing = readback.get("artifacts", {})
    need(type(artifact_listing.get("total_count")) is int and artifact_listing["total_count"] == 1
         and type(artifact_listing.get("artifacts")) is list and len(artifact_listing["artifacts"]) == 1, "Actual one C5 artifact required")
    artifact = artifact_listing["artifacts"][0]
    need(type(artifact) is dict and type(artifact.get("id")) is int and artifact["id"] == 14268939904
         and artifact.get("name") == "galeriq-concept-a-v4-en-US-native-43949822336-attempt-1"
         and artifact.get("digest") == "sha256:f4a09af54d15ce0c4f6529f8aaad1e05f330acdd8d675ad867e7154d1c63d855"
         and artifact.get("workflow_run", {}).get("id") == 43949822336 and artifact["workflow_run"].get("head_sha") == C5_COMMIT
         and artifact["workflow_run"].get("head_branch") == "hermes/store-concept-a-en", "Wrong actual artifact run/SHA/name/digest")
    counts = readback.get("actual_native_capture_test")
    need(type(counts) is dict and set(counts) == {"passed", "failed", "skipped", "total"}
         and all(type(counts[k]) is int and counts[k] == n for k, n in {"passed": 1, "failed": 0, "skipped": 0, "total": 1}.items())
         and readback.get("workflow_conclusion") == "failure", "Actual C5 native capture must be 1 PASS / 0 FAIL / 0 SKIP")
    return {"workflow_run": C5_RUN, "run_attempt": "1", "commit": C5_COMMIT, "branch": "hermes/store-concept-a-en", "repository": "mrdevn4ever-sys/PhotoMaid",
            "actual_api_run_attempt": 1, "complete_jobs": 1, "actual_workflow_conclusion": "failure", "workflow_success": False,
            "failed_postcapture_step": {"number": 9, "name": C5_FAILED_STEP}}


def validate_c5_receipt(receipt, binding, provenance_sha256):
    keys(receipt, {"schemaVersion", "kind", "workflowRun", "runAttempt", "commit", "branch", "actualWorkflowConclusion", "ownerAuthorization",
                   "originalInventory", "originalProvenanceSHA256", "originalErrors", "exactAttemptReadback", "correctedCollector"}, "C5 exception receipt")
    need(type(receipt["schemaVersion"]) is int and receipt["schemaVersion"] == 1 and receipt["kind"] == C5_KIND and receipt["workflowRun"] == C5_RUN
         and type(receipt["runAttempt"]) is int and receipt["runAttempt"] == 1 and receipt["commit"] == C5_COMMIT and receipt["branch"] == "hermes/store-concept-a-en"
         and receipt["actualWorkflowConclusion"] == "failure" and binding["commit"] == C5_COMMIT and binding["workflowRun"] == C5_RUN
         and reference.canonical_run_attempt(binding["runAttempt"], "C5 binding attempt") == 1, "C5 exception receipt cannot authorize another failed run/attempt")
    need(receipt["ownerAuthorization"] == {"file": "qa/c5-owner-decision-20261117.json", "sha256": C5_OWNER_SHA}
         and receipt["originalInventory"] == {"file": "qa/c5-original-artifact-immutable-snapshot.json", "sha256": C5_INVENTORY_SHA}
         and receipt["originalProvenanceSHA256"] == C5_ORIGINAL_SHA and receipt["originalErrors"] == C5_ERRORS, "C5 owner/original FAIL/inventory hash binding changed")
    need(receipt["exactAttemptReadback"] == binding["exactAttemptReadback"] == {"file": "run-43949822336-readback.json", "sha256": C5_READBACK_SHA}, "Only the genuine pinned failed C5 API bytes may be used")
    local = receipt["correctedCollector"]
    keys(local, {"file", "sha256", "scope", "fixtureRoot", "codeSHA256", "auditsSHA256", "sourceHashesSHA256"}, "C5 local collector receipt")
    need(local["file"] == "capture_provenance.json" and local["sha256"] == provenance_sha256 == binding["provenanceSHA256"]
         and local["sha256"] != C5_ORIGINAL_SHA and local["scope"] == "C5-retained-native-evidence-and-local-revalidation", "Require separately bound actual corrected LOCAL report")
    for key in ("sha256", "auditsSHA256", "sourceHashesSHA256"):
        optional_sha(local[key])
        need(local[key] is not None, "Missing corrected local revalidation hash")
    need(type(local["fixtureRoot"]) is str and Path(local["fixtureRoot"]).is_absolute()
         and Path(local["fixtureRoot"]).resolve().as_posix() == local["fixtureRoot"] and type(local["codeSHA256"]) is dict, "Actual canonical prepared fixture root/code bindings required")
    keys(local["codeSHA256"], {"scripts/store/collect_concept_a_v4_provenance.py", "scripts/store/collect_concept_a_provenance.py",
         "scripts/store/build_concept_a_v4_fixture.py", "scripts/store/concept_a_v4_c5_exception.py"}, "C5 collector code hashes")
    for token in local["codeSHA256"].values():
        optional_sha(token)
        need(token is not None, "Missing C5 collector code hash")


def verify_workflow_binding(design, sources, provenance):
    """Independent read-only workflow gate; source/final VQA is still separate."""
    import collect_concept_a_v4_provenance as collector
    import concept_a_v4_c5_exception as materials
    validate_design(design)
    binding = design["captureBinding"]
    saved_api = materials.bound_json(sources, binding["exactAttemptReadback"], load)
    exception_binding = binding.get("workflowException")
    if exception_binding is None:
        return collector.validate_exact_attempt_readback(saved_api, provenance)
    expected_root = OUTPUT_ROOT / "revalidated-C5-43949822336-attempt-1/sources"
    need(Path(sources).resolve() == expected_root.resolve(), "C5 requires its exact DERIVED source root")
    receipt = materials.bound_json(OUTPUT_ROOT, exception_binding, load)
    actual_path = source_path(sources, "capture_provenance.json")
    need(load(actual_path) == provenance, "Corrected provenance argument is not the actual saved local report")
    actual_sha = digest(actual_path)
    validate_c5_receipt(receipt, binding, actual_sha)
    validate_c5_owner_authorization(materials.bound_json(OUTPUT_ROOT, receipt["ownerAuthorization"], load), sources)
    snapshot = materials.bound_json(OUTPUT_ROOT, receipt["originalInventory"], load)
    need(type(snapshot.get("schema")) is int and snapshot["schema"] == 1 and snapshot.get("status") == "PASS_IMMUTABLE_RAW_C5_ARTIFACT_SNAPSHOT"
         and snapshot.get("run") == C5_RUN and type(snapshot.get("attempt")) is int and snapshot["attempt"] == 1 and snapshot.get("commit") == C5_COMMIT, "Actual C5 inventory receipt pins differ")
    immutable = materials.verify_immutable_inventory(snapshot, sources)
    original = materials.bound_json(OUTPUT_ROOT / "native-run-43949822336-attempt-1", {"file": "capture_provenance.json", "sha256": C5_ORIGINAL_SHA}, load)
    need(original.get("status") == "FAIL" and original.get("errors") == C5_ERRORS and provenance.get("status") == "PASS" and provenance.get("errors") == [], "Original must remain FAIL; actual corrected LOCAL collector must PASS")
    actual_api = validate_c5_readback(saved_api, provenance)
    local = materials.recompute_local_data(sources, receipt["correctedCollector"]["fixtureRoot"], provenance, original)
    for key in ("codeSHA256", "auditsSHA256", "sourceHashesSHA256"):
        need(receipt["correctedCollector"][key] == local[key], "Actual corrected collector code/gates/source hashes differ: " + key)
    return {**actual_api, "status": "OWNER_AUTHORIZED_EXCEPTION", "readback_sha256": C5_READBACK_SHA,
            "owner_exception": {"kind": C5_KIND, "receipt": exception_binding, "authorization": receipt["ownerAuthorization"],
                "original_inventory": receipt["originalInventory"], "original_errors": C5_ERRORS, **immutable,
                "corrected_provenance_sha256": actual_sha, "local_data_status": local["localDataStatus"],
                "workflow_conclusion": "failure", "source_or_final_visual_approval_granted": False}}


def capture_policy(design):
    return "single-C5-owner-authorized-postcapture-exception" if design["captureBinding"].get("workflowException") is not None else "single-new-green-v4-stock-only-run"


def phone_geometry(design):
    need(all(type(design.get(k)) is int and design[k] == 4 for k in ("creativeRevision", "layoutRevision", "nativeRevision")), "Only explicit V4 geometry may pass")
    d = design["layout"]["device"]
    need(d == {"screenBox": [131, 844, 1075, 2896], "screenRadius": 115, "frameWidth": 9, "frameColor": "#242322",
        "shadowBlur": 20, "shadowOffset": [0, 12], "shadowAlpha": 38, "viewportClip": "bottom-only", "v2ReferenceScreenBox": [201, 760, 1005, 2508]}, "Exact accepted common phone/frame geometry changed")
    box = d["screenBox"]
    need(all(type(n) is int for n in box), "Integer full target geometry required")
    w, h = dimensions(box)
    frame = [box[0] - 9, box[1] - 9, box[2] + 9, box[3] + 9]
    scale = w / 1206
    need(abs(h - 2622 * scale) <= .5 and scale <= 1 and frame[0] >= 70 and frame[2] <= 1136 and frame[1] >= 70 and box[3] > 2622, "Only proportional bottom-only clipping allowed")
    return {"fullTargetGeometry": box, **reference.clip_geometry(box, [0, 0, *SIZE]), "fullFrameGeometry": frame,
            "visibleFrameGeometry": reference.clip_geometry(frame, [0, 0, *dimensions(frame)])["visibleGeometry"], "nativeScale": scale,
            "sizeRelativeToV2XY": [w / 804, h / 1748], "resampleRoundingXY": [0, h - 2622 * scale], "clipping": "bottom-only", "completePhoneVisible": False}


def validate_design(design):
    """Independently close all design-key sets before interpreting coordinates."""
    keys(design, {"schemaVersion", "moduleVersion", "concept", "direction", "locale", "canvas", "background", "colors", "tokenReferences",
                  "fonts", "layout", "sourceGate", "slots", "previews", "localizationRule", "creativeRevision", "layoutRevision", "nativeRevision",
                  "nativeScenePolicy", "sampleMediaPolicy", "captureBaselineCommit", "captureBinding", "finalSourceVisualQA", "slotMapping", "outputRoot"}, "V4 design")
    need(type(design["schemaVersion"]) is int and design["schemaVersion"] == 2 and design["moduleVersion"] == VERSION and
         (design["concept"], design["direction"], design["locale"]) == ("A", "Space to Breathe", "en-US"), "Explicit independent V4/en-US contract required")
    need(design["canvas"] == {"width": 1206, "height": 2622, "safeMargin": 70} and design["background"] == {"top": "#E0EFF9", "bottom": "#EAF4FB", "interpolation": "smoothstep"}, "Accepted canvas/background drift")
    need(design["colors"] == {"ink": "#1C1916", "subtitle": "#1C1916", "keep": "#1B6FA8", "trash": "#C4441A", "later": "#6347D0"}, "Accepted ink/gesture palette drift")
    need(design["captureBaselineCommit"] == BASELINE and design["outputRoot"] == OUTPUT_ROOT.as_posix() and
         design["sampleMediaPolicy"] == MEDIA_POLICY and design["nativeScenePolicy"] == SCENE_POLICY, "V4 source baseline/policy/scope drift")
    need(design["slotMapping"] == [{"old": old, "new": new} for old, new in ((1, 1), (2, 2), (7, 3), (3, 4), (4, 5), (5, 6), (6, 7), (8, 8), (9, 9), (10, 10))], "V4 old/new mapping differs")
    need(design["tokenReferences"] == {"file": "PhotoMaid/DesignSystem/Tokens.swift", "sky_tint": "AppColors.tileKeep.light = #E0EFF9", "keep": "AppColors.keep.light = #1B6FA8", "trash": "AppColors.cleanup.light = #C4441A", "later": "AppColors.later.light = #6347D0"}, "Token references drift")
    need(design["sourceGate"] == {"provenanceFile": "capture_provenance.json", "appLanguage": "en", "nativeSize": [1206, 2622], "minimumInsetTop": 200,
        "wordmarkSource": WORDMARK, "wordmarkComponent": "VaultDialWordmark", "wordmarkForeground": "lightForeground", "requireVisualQA": True,
        "requireProtectedNativeRects": True, "normalizeNativeICCToSRGB": True, "requiredCaptureTest": CAPTURE_TEST,
        "sourceManifest": "app-store/concepts/A/v4-source-media/manifest.json", "fixtureAllowlist": "app-store/concepts/A/qa/v4-fixture-source-allowlist.json"}, "V4 gate may not be weakened/redirected")
    layout = design["layout"]
    keys(layout, {"alignment", "wordmarkBox", "headlineBox", "subtitleBox", "device", "insetStyle", "seriesInsetStyle", "dialogInsetStyle", "gestures"}, "layout")
    need(layout["alignment"] == "left" and layout["wordmarkBox"] == [70, 78, 406, 200] and layout["headlineBox"] == [70, 248, 1136, 532] and layout["subtitleBox"] == [70, 560, 1136, 708], "Accepted header boxes drift")
    phone_geometry(design)
    need(layout["seriesInsetStyle"] == layout["dialogInsetStyle"] == FLAT and layout["insetStyle"] == {"radius": 24, "shadowBlur": 2, "shadowOffset": [0, 2], "shadowAlpha": 32}, "Native detail styles changed")
    need(layout["gestures"] == [
        {"action": "Keep", "direction": "up", "color": "keep", "arrowBox": [70, 734, 124, 788], "labelBox": [144, 724, 370, 808]},
        {"action": "Trash", "direction": "left", "color": "trash", "arrowBox": [454, 734, 508, 788], "labelBox": [528, 724, 754, 808]},
        {"action": "Later", "direction": "right", "color": "later", "arrowBox": [838, 734, 892, 788], "labelBox": [912, 724, 1136, 808]}], "Actual gesture semantics/geometry changed")
    keys(design["fonts"], {"headline", "subtitle", "gesture"}, "fonts")
    for kind, file, size, floor, lines, gap in (("headline", "PMDisplay-Bold.ttf", 112, 84, 2, 12), ("subtitle", "PMText-Medium.ttf", 52, 46, 2, 8), ("gesture", "PMText-Bold.ttf", 72, 60, 1, 0)):
        need(design["fonts"][kind] == {"path": "PhotoMaid/Resources/Fonts/" + file, "preferredSize": size, "minimumSize": floor, "step": 1, "maxLines": lines, "lineGap": gap}, "App font/fit policy changed")
    binding, review = design["captureBinding"], design["finalSourceVisualQA"]
    keys(binding, {"approved", "commit", "workflowRun", "runAttempt", "provenanceSHA256", "exactAttemptReadback"}
         | ({"workflowException"} if "workflowException" in binding else set()), "capture binding")
    exception = binding.get("workflowException")
    if exception is not None:
        keys(exception, {"file", "sha256"}, "workflow exception")
        need(exception["file"] == "qa/c5-postcapture-workflow-exception.json", "Only the fixed C5 exception report is admissible")
        optional_sha(exception["sha256"])
        need(exception["sha256"] is not None, "C5 exception report needs its actual hash")
    need(type(binding["approved"]) is bool, "Explicit approval boolean required")
    optional_sha(binding["provenanceSHA256"])
    need(binding["commit"] is None or (type(binding["commit"]) is str and re.fullmatch(r"[0-9a-f]{40}", binding["commit"])), "Malformed new native commit")
    need(binding["workflowRun"] is None or (type(binding["workflowRun"]) is str and re.fullmatch(r"[1-9][0-9]*", binding["workflowRun"])), "Malformed new native run")
    if binding["runAttempt"] is not None:
        reference.canonical_run_attempt(binding["runAttempt"], "capture binding attempt")
    for pair in (binding["exactAttemptReadback"], review.get("sourceReview")):
        keys(pair, {"file", "sha256"}, "root proof binding")
        need(pair["file"] is None or (type(pair["file"]) is str and re.fullmatch(r"[A-Za-z0-9_.-]+\.json", pair["file"])), "Root proof filename must be explicit canonical JSON")
        optional_sha(pair["sha256"])
    keys(review, {"approved", "provenanceSHA256", "commit", "workflowRun", "runAttempt", "reviewer", "notes", "nativeWordmarkComponent", "nativeWordmarkForeground", "nativeStatusBar", "requirements", "sourceReview"}, "source VQA")
    need(type(review["approved"]) is bool and type(review["requirements"]) is dict and set(review["requirements"]) == REVIEW and all(type(v) is bool for v in review["requirements"].values()), "Explicit complete V4 source review set required")
    optional_sha(review["provenanceSHA256"])
    need(review["nativeWordmarkComponent"] == "VaultDialWordmark" and review["nativeWordmarkForeground"] == "lightForeground" and review["nativeStatusBar"] == {"time": "9:41", "fullBattery": True, "dynamicIsland": True, "appearance": "dark"}, "Canonical wordmark/status gate differs")
    need(type(design["slots"]) is list and len(design["slots"]) == 10, "Exactly ten slots required")
    files = set()
    for index, slot in enumerate(design["slots"], 1):
        keys(slot, {"id", "file", "headline", "subtitle", "primary", "primarySourceSHA256", "primaryProtectedRects", "gestures", "insets", "evidence"} | ({"editorComparison"} if index == 9 else set()), "slot")
        need(type(slot["id"]) is int and slot["id"] == index and slot["headline"] == COPY[index - 1] and slot["subtitle"] == SUBTITLES[index - 1], "Exact V4 sequence/copy differs")
        need(slot["primary"] == f"screenshots/concept-a-{PRIMARIES[index - 1]}.png" and slot["gestures"] is (index == 1), "Wrong V4 native primary/gesture slot")
        need(type(slot["file"]) is str and re.fullmatch(fr"{index:02d}-[a-z0-9-]+\.png", slot["file"]) and slot["file"] not in files, "Unsafe/duplicate output filename")
        files.add(slot["file"])
        optional_sha(slot["primarySourceSHA256"])
        regions = slot["primaryProtectedRects"]
        need(regions is None or (type(regions) is list and bool(regions)), "Missing/empty protected rect list")
        if regions is not None:
            for region in regions:
                integer_rect(region, "protected native rect")
        need(type(slot["insets"]) is list, "Explicit inset list required")
        if index not in INSETS:
            need(slot["insets"] == [], "Extra native inset, including Later")
        else:
            name, source, evidence = INSETS[index]
            need(len(slot["insets"]) == 1, "One continuous native inset required")
            inset = slot["insets"][0]
            keys(inset, {"id", "source", "crop", "cropSourceSHA256", "cropEvidenceRects", "targetBox", "enabled", "required", "evidence", "verticalAnchor"} | ({"nativeRectEvidence"} if index == 4 else set()), "inset")
            need(inset["id"] == name and inset["source"] == f"screenshots/concept-a-{source}.png" and inset["enabled"] is True and inset["required"] is True and
                 set(inset["cropEvidenceRects"]) == evidence and inset["verticalAnchor"] == ("center" if index == 2 else "bottom"), "Wrong V4 inset schema/source/evidence")
            optional_sha(inset["cropSourceSHA256"])
            integer_rect(inset["targetBox"], "inset output")
            if inset["crop"] is not None:
                integer_rect(inset["crop"], "inset crop")
            for region in inset["cropEvidenceRects"].values():
                if region is not None:
                    integer_rect(region, "inset evidence")
            if index == 4:
                binding = inset["nativeRectEvidence"]
                keys(binding, {"file", "sha256", "jsonPointer", "format", "coordinateScale"}, "native dialog binding")
                need({k: v for k, v in binding.items() if k != "sha256"} == {"file": "concept-a-delete-confirm-frame.json", "jsonPointer": "/nativeRect", "format": "xyxy", "coordinateScale": 1}, "Actual dialog receipt required")
                optional_sha(binding["sha256"])
        if index == 9:
            validate_comparison(slot["editorComparison"])
    keys(design["previews"], {"overview", "search"}, "previews")
    for kind, ids, width, margin, gap, file in (("overview", list(range(1, 11)), 241, 20, 20, "00-overview.jpg"), ("search", [1, 2, 3], 112, 16, 11, "00-search-preview.jpg")):
        need(design["previews"][kind] == {"file": file, "slotIds": ids, "columns": len(ids), "tileWidth": width, "gap": gap, "margin": margin}, "Exact independent preview contract differs")
        reference.preview_geometry(design, kind)
    keys(design["localizationRule"], {"renderNow", "futureOnly"}, "localizationRule")
    need(design["localizationRule"]["renderNow"] == ["en-US"], "Localization not authorized")


def validate_comparison(value):
    keys(value, {"kind", "approved", "sourceBefore", "sourceAfter", "sourceBeforeSHA256", "sourceAfterSHA256", "proof", "photoCrop", "targetBox", "disclosure", "labels", "nativeSideBySideClaim", "layout"}, "editor composite")
    need(value["kind"] == COMPOSITE_KIND and type(value["approved"]) is bool and value["nativeSideBySideClaim"] is False and
         (value["sourceBefore"], value["sourceAfter"]) == COMPOSITE_SOURCES and value["disclosure"] == "Photo comparison" and value["labels"] == ["Original", "Warm"], "Untruthful/synthetic native editor comparison")
    for name in ("sourceBeforeSHA256", "sourceAfterSHA256"):
        optional_sha(value[name])
    keys(value["proof"], {"file", "sha256"}, "editor pair proof")
    need(value["proof"]["file"] == "editor-pair-proof.json", "Actual native pair proof required")
    optional_sha(value["proof"]["sha256"])
    for name in ("photoCrop", "targetBox"):
        if value[name] is not None:
            integer_rect(value[name], name)
    need(value["layout"] == {"padding": 16, "gap": 20, "disclosureHeight": 54, "labelHeight": 54, "fontSize": 46, "photoRadius": 0, "shadowAlpha": 0, "background": "#E0EFF9", "ink": "#1C1916"}, "Disclosed flat marketing comparison style differs")


def require_calibrated(design, commit, run, attempt):
    validate_design(design)
    need(type(commit) is str and re.fullmatch(r"[0-9a-f]{40}", commit) and type(run) is str and re.fullmatch(r"[1-9][0-9]*", run), "Literal full new capture commit/run required")
    attempt = reference.canonical_run_attempt(attempt, "expected attempt")
    if design["captureBinding"].get("workflowException") is not None:
        need(commit == C5_COMMIT and run == C5_RUN and attempt == 1, "C5 exception cannot authorize another run/attempt/SHA")
    need(commit not in {BASELINE, "8ffdc943d8a3cc57ad8212320a0fea586609c6da"} and run != "43865738891", "Historical/baseline capture cannot satisfy new V4")
    binding, review = design["captureBinding"], design["finalSourceVisualQA"]
    need(binding["approved"] is True, "V4 captureBinding is UNAPPROVED; await actual new native evidence")
    need(binding["commit"] == commit and binding["workflowRun"] == run and reference.canonical_run_attempt(binding["runAttempt"], "binding attempt") == attempt and
         binding["provenanceSHA256"] and binding["exactAttemptReadback"]["file"] and binding["exactAttemptReadback"]["sha256"], "V4 independent capture pins/readback absent or different")
    need(review["approved"] is True and review["commit"] == commit and review["workflowRun"] == run and
         reference.canonical_run_attempt(review["runAttempt"], "source visual attempt") == attempt and review["provenanceSHA256"] == binding["provenanceSHA256"] and
         all(type(review[k]) is str and review[k].strip() for k in ("reviewer", "notes")) and all(review["requirements"].values()) and
         review["sourceReview"]["file"] and review["sourceReview"]["sha256"], "Actual exact-attempt source VQA approval missing/stale")
    for slot in design["slots"]:
        need(slot["primarySourceSHA256"] and slot["primaryProtectedRects"], "New primary hashes/protected rects remain unset")
        for inset in slot["insets"]:
            need(inset["crop"] and inset["cropSourceSHA256"] and all(inset["cropEvidenceRects"].values()), "New native inset calibration is unset")
            if "nativeRectEvidence" in inset:
                need(inset["nativeRectEvidence"]["sha256"], "Native dialog receipt hash unset")
    composite = design["slots"][8]["editorComparison"]
    need(composite["approved"] is True and composite["proof"]["sha256"] and all(composite[k] for k in ("photoCrop", "targetBox", "sourceBeforeSHA256", "sourceAfterSHA256")), "Actual editor-pair comparison not calibrated/approved")
    return attempt


def verify_sources(sources, provenance, design, commit, run, attempt):
    """Read-only shared native observation decoder, independent exported-pixel path."""
    import collect_concept_a_v4_provenance as collector
    import collect_concept_a_provenance as original
    import build_concept_a_v4_fixture as builder
    need(collector.V4_SCENE_POLICY == SCENE_POLICY and provenance.get("schema_version") == 2 and provenance.get("creative_revision") == 4 and
         provenance.get("native_scene_policy") == provenance.get("v4_native_scene_policy") == SCENE_POLICY and provenance.get("errors") == [], "Native V4 collector contract incomplete")
    reference.validate_run_binding(provenance, commit, run, attempt)
    collector.validate_run_pins(provenance)
    need(provenance.get("status") == "PASS" and provenance.get("fresh_capture") is True and provenance.get("base_commit") == "583eb804a81401aa2010996875b35d05afc61539" and
         provenance.get("branch") == "hermes/store-concept-a-en" and provenance.get("device", {}).get("name") == "iPhone 17 Pro", "Exact fresh native header/baseline/device required")
    fixture = load(source_path(sources, "fixture-manifest.json"))
    need(digest(source_path(sources, "fixture-manifest.json")) == provenance["fixture_manifest_sha256"], "Actual fixture bytes drift")
    library = load(source_path(sources, "concept-a-library.json"))
    stock = reference.verify_stock_library(sources, provenance, fixture)
    registry_path = ROOT / "app-store/concepts/A/v4-source-media/manifest.json"
    allowlist_path = ROOT / "app-store/concepts/A/qa/v4-fixture-source-allowlist.json"
    registry, allowlist = load(registry_path), load(allowlist_path)
    builder.validate_registry(registry, allowlist)
    collector.validate_fixture_metadata(fixture, registry, allowlist, digest(registry_path), digest(allowlist_path))
    need(fixture["visual_source_gate"] == provenance["fixture_visual_source_gate"], "Unknown/rejected fixture original included")
    scene = original.audit_v3_scenes(sources, fixture)
    need(scene.get("status") == "PASS" and scene == provenance["native_scene_audit"] and provenance.get("base_c14_native_scene_policy") == original.V3_SCENE_POLICY, "Original 14-source scene gates lost/stale")
    screens = collector.validate_native_screens(sources)
    native = {}
    for row in provenance["outputs"]:
        need(type(row) is dict and row["file"] not in native, "Duplicate actual native provenance source")
        native[row["file"]] = row
    need(LEGACY_SCREENS | NEW_SCREENS <= native.keys() and all(native[path] == row for path, row in screens.items()), "Missing/mismatched required actual sources")
    branding = provenance["branding"]
    need(branding["file"] == WORDMARK and WORDMARK not in native and re.fullmatch(r"[0-9a-f]{64}", branding["sha256"]), "Canonical native branding missing")
    native[WORDMARK] = branding
    audits = provenance.get("v4_audits", {})
    for name in ("literal_run_pins", "capture_test", "original_sources", "fixture_records", "fixture_files", "captured_fixture_manifest_bytes", "native_screens", "sample_media", "month_progress", "editor_pair"):
        need(type(audits.get(name)) is dict and audits[name].get("status") == "PASS", "V4 collector subgate failed: " + name)
    test = collector.validate_capture_summary(load(source_path(sources, "summary.json")), load(source_path(sources, "tests.json")), CAPTURE_TEST)
    need(test == audits["capture_test"], "Actual passed test08 tree differs")
    month = collector.audit_month_progress(sources, screens, library)
    editor = collector.audit_editor_pair(sources, screens, library)
    need(month == audits["month_progress"] and editor == audits["editor_pair"], "Actual month/editor evidence differs from collector report")
    preserved = provenance["base_c14_provenance"]
    need(preserved.get("status") == "PASS" and digest(source_path(sources, preserved["file"])) == preserved["sha256"], "Original base native collector bytes drift")
    base = load(source_path(sources, preserved["file"]))
    need(base.get("status") == "PASS" and all(base.get(key) == provenance[key] for key in ("commit", "workflow_run", "run_attempt", "branch", "fixture_manifest_sha256")), "Original base native report belongs to another attempt")
    api = verify_workflow_binding(design, sources, provenance)
    review_binding = design["finalSourceVisualQA"]["sourceReview"]
    need(digest(source_path(sources, review_binding["file"])) == review_binding["sha256"], "Actual source VQA report bytes drift")
    review = load(source_path(sources, review_binding["file"]))
    need(review.get("approved") is True and review.get("provenanceSHA256") == digest(sources / "capture_provenance.json") and review.get("commit") == commit and
         review.get("workflowRun") == run and reference.canonical_run_attempt(review.get("runAttempt"), "saved source VQA attempt") == attempt and
         review.get("requirements") == design["finalSourceVisualQA"]["requirements"], "Actual source VQA is not approved for these literal source pins")
    return native, {"stockLibrary": stock, "legacySceneAudit": scene, "monthProgress": month, "editorPair": editor, "exactAttemptAPI": api,
                    "sourceManifestSHA256": digest(registry_path), "fixtureAllowlistSHA256": digest(allowlist_path)}


def focus_style(design, name):
    if name in ("editor-original-photo", "editor-warm-photo"):
        return FLAT
    return reference.focus_style(design, name)


def layer_occlusion(layer, design):
    box = layer["targetGeometry"]
    radius = design["layout"]["device"]["screenRadius"] if layer["id"] == "full-phone" else focus_style(design, layer["id"])["radius"]
    mask = rounded(dimensions(box), radius)
    # Only the documented native inset may have a shadow; never broad masks.
    coverage = full_mask(mask, box)
    if layer["id"] not in ("full-phone", "editor-original-photo", "editor-warm-photo"):
        return reference.layer_occlusion(layer, design)
    return coverage


def verify_pixels(final, sources, layer, later_layers, design, composite=None):
    """Reconstruct ICC/crop/resample/alpha from ORIGINAL files, not renderer buffers."""
    path = source_path(sources, layer["originalSource"])
    need(digest(path) == layer["sourceSHA256"], "Actual native layer source SHA drift")
    with Image.open(path) as image:
        image.load()
        need(image.format == "PNG" and image.mode in ("RGB", "RGBA") and image.getexif().get(274, 1) == 1 and getattr(image, "n_frames", 1) == 1, "Invalid original native PNG")
        need(layer["sourceSize"] == list(image.size) and layer["sourceMode"] == image.mode, "Native source size/mode metadata drift")
        alpha = image.getchannel("A") if image.mode == "RGBA" else None
        rgb = image.convert("RGB")
        raw_icc = image.info.get("icc_profile")
        if raw_icc:
            profile = ImageCms.ImageCmsProfile(io.BytesIO(raw_icc))
            need(profile.profile.xcolor_space.strip() == "RGB", "Native RGB ICC required")
            rgb = ImageCms.profileToProfile(rgb, profile, ImageCms.createProfile("sRGB"), outputMode="RGB", renderingIntent=ImageCms.Intent.RELATIVE_COLORIMETRIC, flags=0)
        normalized = rgb.copy()
        if alpha is not None:
            normalized.putalpha(alpha)
        need(layer["colorManagement"]["normalizedPixelSHA256"] == raw_sha(normalized.tobytes()), "ICC-normalized original pixel/alpha hash drift")
        box, crop = layer["targetGeometry"], layer["crop"]
        need(type(box) is list and len(box) == 4 and all(type(n) is int for n in box), "Integer native target required")
        integer_rect(crop, "source crop", image.size)
        size, native_size, scale = dimensions(box), dimensions(crop), layer["nativeScale"]
        need(type(scale) in (int, float) and math.isfinite(scale) and 0 < scale <= 1 and
             all(actual <= original and abs(actual - original * scale) <= .5 + 1e-9 for actual, original in zip(size, native_size)), "Unknown native proportional resample/upscale")
        need(layer["effectiveNativeScaleXY"] == [size[0] / native_size[0], size[1] / native_size[1]] and layer["rotationDegrees"] == 0, "Native aspect/rotation metadata drift")
        geometry = reference.clip_geometry(box, crop)
        need(all(layer[k] == v for k, v in geometry.items()), "False full/visible viewport metadata")
        viewport = Image.new("L", size)
        viewport.paste(255, geometry["visibleLocalRect"])
        if layer["id"] == "native-wordmark":
            need(alpha is not None and alpha.getextrema()[0] == 0 and crop == list(alpha.getbbox()), "Canonical wordmark transparency/whole ink lost")
            tile = normalized.crop(crop)
            if tile.size != size:
                tile = tile.resize(size, Image.Resampling.LANCZOS)
            mask = tile.getchannel("A")
            expected = reference.marketing_background(design).crop(box)
            expected.paste(tile.convert("RGB"), (0, 0), mask)
            eligible = mask.point(lambda n: 255 if n > 0 else 0)
        else:
            need(image.size == SIZE and (alpha is None or alpha.getextrema() == (255, 255)), "Opaque 1206x2622 native screen required")
            expected = rgb.crop(crop)
            if expected.size != size:
                expected = expected.resize(size, Image.Resampling.LANCZOS)
            radius = design["layout"]["device"]["screenRadius"] if layer["id"] == "full-phone" else focus_style(design, layer["id"])["radius"]
            mask = rounded(size, radius)
            eligible = mask.point(lambda n: 255 if n == 255 else 0)
        need(layer["maskSHA256"] == raw_sha(mask.tobytes()) and layer["viewportMaskSHA256"] == raw_sha(viewport.tobytes()) and
             layer["visibleMaskSHA256"] == raw_sha(ImageChops.multiply(mask, viewport).tobytes()), "False native/viewport mask metadata")
        full_count = eligible.histogram()[255]
        eligible = ImageChops.multiply(eligible, viewport)
        viewport_count = eligible.histogram()[255]
        if layer["id"] == "full-phone" and composite:
            blocker = Image.new("L", SIZE)
            blocker.paste(255, composite["box"])
            eligible = ImageChops.subtract(eligible, blocker.crop(box))
        for above in later_layers:
            eligible = ImageChops.subtract(eligible, layer_occlusion(above, design).crop(box).point(lambda n: 255 if n else 0))
        count = eligible.histogram()[255]
        same_dialog = any(above["id"] == "system-dialog" and above["originalSource"] == layer["originalSource"] for above in later_layers)
        minimum = (.25 if same_dialog else .5) if layer["id"] == "full-phone" else 1
        need(count > 100 and count >= viewport_count * minimum, "Native evidence excessively occluded")
        actual = final.crop(box).convert("RGB")
        diff = Image.composite(ImageChops.difference(actual, expected), Image.new("RGB", size), eligible)
        need(diff.getbbox() is None, "Independent original native pixel mismatch: " + layer["id"])
        actual_masked = Image.composite(actual, Image.new("RGB", size), eligible)
        expected_masked = Image.composite(expected, Image.new("RGB", size), eligible)
        proof = layer["pixelQA"]
        need(proof["status"] == "PASS" and proof["comparedPixels"] == count and proof["opaqueInteriorPixels"] == viewport_count and proof["fullTargetOpaqueInteriorPixels"] == full_count and
             proof["offCanvasOpaqueInteriorPixels"] == full_count - viewport_count and proof["occludedByLaterInsetOrShadowPixels"] == viewport_count - count and
             proof["minimumVisibleViewportFraction"] == minimum and proof["maxChannelDifference"] == 0 and
             proof["maskedKnownResampleSHA256"] == raw_sha(expected_masked.tobytes()) == proof["maskedOutputSHA256"] == raw_sha(actual_masked.tobytes()), "Renderer's pixel proof is not the actual independent comparison")
        return count


def verify_frame(final, design, proof):
    geometry = phone_geometry(design)
    d = design["layout"]["device"]
    box, frame = geometry["fullTargetGeometry"], geometry["fullFrameGeometry"]
    outer = full_mask(rounded(dimensions(frame), d["screenRadius"] + d["frameWidth"]), frame)
    inner = full_mask(rounded(dimensions(box), d["screenRadius"]), box)
    mask = ImageChops.multiply(outer.point(lambda n: 255 if n == 255 else 0), inner.point(lambda n: 255 if n == 0 else 0))
    count = mask.histogram()[255]
    diff = Image.composite(ImageChops.difference(final, Image.new("RGB", SIZE, d["frameColor"])), Image.new("RGB", SIZE), mask)
    need(count > 1000 and diff.getbbox() is None, "Visible hardware frame pixels obscured/changed")
    need(proof == {"status": "PASS", "comparedPixels": count, "maxChannelDifference": 0, "visibleFrameMaskSHA256": raw_sha(mask.tobytes()),
        "topLeftRightVisible": True, "bottomIntentionallyClipped": True, "geometry": geometry}, "Frame/clip proof differs")
    return count


def verify_insets(row, slot, design, sources, native, scene):
    index, layers = slot["id"], row["nativeLayers"]
    ids = ["native-wordmark", "full-phone"] + ([INSETS[index][0]] if index in INSETS else []) + (["editor-original-photo", "editor-warm-photo"] if index == 9 else [])
    need([layer["id"] for layer in layers] == ids, "Missing/extra/reordered V4 native layer")
    primary = layers[1]
    need(primary["originalSource"] == slot["primary"] == f"screenshots/concept-a-{PRIMARIES[index - 1]}.png" and
         primary["sourceSHA256"] == slot["primarySourceSHA256"] == native[slot["primary"]]["sha256"] and primary["crop"] == [0, 0, *SIZE] and
         primary["targetGeometry"] == design["layout"]["device"]["screenBox"], "Native primary/full coordinates changed")
    wordmark = layers[0]
    need(wordmark["originalSource"] == WORDMARK, "Canonical native wordmark missing")
    with Image.open(source_path(sources, WORDMARK)) as image:
        crop = image.getchannel("A").getbbox()
    w, h = dimensions(crop)
    container = design["layout"]["wordmarkBox"]
    scale = min(1, dimensions(container)[0] / w, dimensions(container)[1] / h)
    need(wordmark["crop"] == list(crop) and wordmark["targetGeometry"] == [container[0], container[1], container[0] + math.floor(w * scale + .5), container[1] + math.floor(h * scale + .5)] and wordmark["nativeScale"] == scale, "Wordmark native ink/alignment changed")
    protected = [[0, 0, 1206, 200]] + slot["primaryProtectedRects"]
    box = primary["targetGeometry"]
    sx, sy = dimensions(box)[0] / 1206, dimensions(box)[1] / 2622
    mapped = [[box[0] + math.floor(r[0] * sx), box[1] + math.floor(r[1] * sy), box[0] + math.ceil(r[2] * sx), box[1] + math.ceil(r[3] * sy)] for r in protected]
    prepared = row["protectedEvidence"]
    keys(prepared, {"primary", "protectedSourceRects", "protectedOutputRects", "insets", "creativeComposite"}, "prepared source plan")
    need(prepared["primary"] == slot["primary"] and prepared["protectedSourceRects"] == protected and prepared["protectedOutputRects"] == mapped and
         all(within(r, phone_geometry(design)["visibleGeometry"]) for r in mapped), "False/hidden decisive protected source evidence")
    if index not in INSETS:
        need(slot["insets"] == prepared["insets"] == [], "Unexpected duplicated native UI focus")
        return mapped
    name, source, evidence_keys = INSETS[index]
    inset, layer = slot["insets"][0], layers[2]
    need(layer["originalSource"] == inset["source"] == f"screenshots/concept-a-{source}.png" and
         layer["sourceSHA256"] == inset["cropSourceSHA256"] == native[inset["source"]]["sha256"] and layer["crop"] == inset["crop"], "Unbound native inset source")
    crop = inset["crop"]
    need(within(crop, [0, 200, *SIZE]) and set(inset["cropEvidenceRects"]) == evidence_keys and all(within(r, crop) for r in inset["cropEvidenceRects"].values()), "Continuous whole native inset evidence missing")
    requested = inset["targetBox"]
    cw, ch = dimensions(crop)
    scale = min(1.0, dimensions(requested)[0] / cw, dimensions(requested)[1] / ch)
    w, h = math.floor(cw * scale + .5), math.floor(ch * scale + .5)
    x, y = requested[0] + (dimensions(requested)[0] - w) // 2, requested[1] + (dimensions(requested)[1] - h) // 2
    if inset["verticalAnchor"] == "bottom":
        y = requested[3] - h
    target = [x, y, x + w, y + h]
    need(layer["targetGeometry"] == target and layer["nativeScale"] == scale > max(sx, sy), "Inset must use known proportional contain, no native upscale")
    if name in ("series-decision", "system-dialog"):
        need((target[0], target[2]) == (box[0], box[2]), "Exposed stale native gutters beside full-width focus")
    style = focus_style(design, name)
    radius, dx, dy = style["shadowBlur"] * 3 + 2, *style["shadowOffset"]
    effect = target if style["shadowAlpha"] == 0 else [min(x, x - radius + dx), min(y, y - radius + dy), max(x + w, x + w + radius + dx), max(y + h, y + h + radius + dy)]
    visible = [effect[0], effect[1], effect[2], min(effect[3], 2622)]
    need(within(target, phone_geometry(design)["visibleGeometry"]) and within(effect, box) and within(visible, phone_geometry(design)["visibleGeometry"]) and effect[1] >= box[1] + 115 and not any(intersects(effect, r) for r in mapped), "Native inset/shadow covers frame or decisive evidence")
    frame_binding = None
    if index == 4:
        actual = reference.actual_dialog_rect(sources, inset["nativeRectEvidence"])
        need(inset["nativeRectEvidence"]["sha256"] == scene["source_bindings"]["concept-a-delete-confirm-frame.json"] and
             actual == crop == inset["cropEvidenceRects"]["system-dialog"] == scene["actual_dialog_native_rect"], "Native dialog focus must be exactly the real complete panel, no old outside slivers")
        frame_binding = {**inset["nativeRectEvidence"], "nativePixelRect": actual}
    need(prepared["insets"] == [{"id": name, "source": inset["source"], "crop": crop, "target": target, "nativeScale": scale,
        "magnificationRelativeToPhone": scale / sx, "cropEvidenceRects": inset["cropEvidenceRects"], "nativeRectEvidence": frame_binding,
        "requestedBox": requested, "verticalAnchor": inset["verticalAnchor"], "effectBox": list(effect), "visibleEffectBox": visible,
        "shadowViewportClip": "bottom-only" if effect[3] > 2622 else "none"}], "False prepared native inset geometry")
    return mapped


def comparison_geometry(value):
    """Independent integer reconstruction of two equal contained photo-only crops."""
    box, crop, spec = value["targetBox"], value["photoCrop"], value["layout"]
    p, gap = spec["padding"], spec["gap"]
    y = box[1] + p + spec["disclosureHeight"] + spec["labelHeight"]
    width = (box[2] - box[0] - 2 * p - gap) // 2
    need(width > 0 and box[3] - p > y, "Comparison lacks native photo area")
    photos, labels, scales = [], [], []
    for n in range(2):
        left = box[0] + p + n * (width + gap)
        scale = min(1.0, width / dimensions(crop)[0], (box[3] - p - y) / dimensions(crop)[1])
        w, h = [max(1, math.floor(length * scale + .5)) for length in dimensions(crop)]
        px, py = left + (width - w) // 2, y + (box[3] - p - y - h) // 2
        photos.append([px, py, px + w, py + h])
        labels.append([left, y - spec["labelHeight"], left + width, y])
        scales.append(scale)
    need(scales[0] == scales[1] and dimensions(photos[0]) == dimensions(photos[1]), "Photo comparisons must be equal-scale")
    return {"box": box, "crop": crop, "photoTargets": photos, "nativeScale": scales[0], "labelBoxes": labels,
            "disclosureBox": [box[0] + p, box[1] + p, box[2] - p, box[1] + p + spec["disclosureHeight"]]}


def verify_comparison(final, row, slot, design, sources, native, editor, mapped, fonts):
    if slot["id"] != 9:
        need(row["creativeComposite"] is None and row["protectedEvidence"]["creativeComposite"] is None, "Unexpected marketing panel on another feature")
        return None
    value, actual = slot["editorComparison"], row["creativeComposite"]
    need(type(actual) is dict and actual == row["protectedEvidence"]["creativeComposite"], "Missing explicit creative-composite receipt")
    keys(actual, {"box", "crop", "photoTargets", "nativeScale", "labelBoxes", "disclosureBox", "kind", "disclosure", "labels", "sourceBindings", "proof", "nativeSideBySideClaim", "observedPhotoRect", "textPlans"}, "creative composite receipt")
    geometry = comparison_geometry(value)
    need(all(actual[k] == v for k, v in geometry.items()) and actual["kind"] == COMPOSITE_KIND and actual["nativeSideBySideClaim"] is False and
         actual["disclosure"] == "Photo comparison" and actual["labels"] == ["Original", "Warm"], "False or misleading marketing comparison geometry/disclosure")
    need(actual["proof"] == value["proof"] and digest(source_path(sources, value["proof"]["file"])) == value["proof"]["sha256"] == editor["proof_sha256"], "Actual same-asset published Warm/Undo/Redo/copy-default receipt mismatch")
    need(actual["sourceBindings"] == [{"file": source, "sha256": native[source]["sha256"]} for source in COMPOSITE_SOURCES] and
         value["sourceBeforeSHA256"] == native[COMPOSITE_SOURCES[0]]["sha256"] and value["sourceAfterSHA256"] == native[COMPOSITE_SOURCES[1]]["sha256"], "Two real native photo source bindings required")
    proof = load(source_path(sources, value["proof"]["file"]))
    frame = proof["checkpoints"]["after"]["photoNativeFrame"]
    coords = [frame["x"], frame["y"], frame["x"] + frame["width"], frame["y"] + frame["height"]]
    need(all(type(n) in (int, float) and math.isfinite(n) and int(n) == n for n in coords), "Observed photo-only native rectangle must be integral")
    photo = [int(n) for n in coords]
    need(actual["observedPhotoRect"] == photo and within(value["photoCrop"], photo), "Crop includes synthetic UI or exceeds true native photo")
    screen = design["layout"]["device"]["screenBox"]
    sx, sy = dimensions(screen)[0] / 1206, dimensions(screen)[1] / 2622
    mapped_photo = [screen[0] + math.ceil(photo[0] * sx), screen[1] + math.ceil(photo[1] * sy), screen[0] + math.floor(photo[2] * sx), screen[1] + math.floor(photo[3] * sy)]
    need(within(actual["box"], mapped_photo) and within(actual["box"], phone_geometry(design)["visibleGeometry"]) and not any(intersects(actual["box"], r) for r in mapped), "Comparison panel crosses native controls/status/frame")
    for layer, source, target in zip(row["nativeLayers"][2:], COMPOSITE_SOURCES, geometry["photoTargets"]):
        need(layer["originalSource"] == source and layer["sourceSHA256"] == native[source]["sha256"] and layer["crop"] == value["photoCrop"] and
             layer["targetGeometry"] == target and layer["nativeScale"] == geometry["nativeScale"], "False native comparison crop/known scale")
    # Reconstruct every marketing panel pixel; only the two real photo rectangles
    # are excluded here and are verified independently by verify_pixels().
    expected = Image.new("RGB", SIZE, value["layout"]["background"])
    draw = ImageDraw.Draw(expected)
    font_path = source_path(ROOT, design["fonts"]["subtitle"]["path"])
    need(digest(font_path) == fonts["subtitle"]["sha256"], "Marketing panel app-font hash drift")
    plans = actual["textPlans"]
    boxes = [geometry["disclosureBox"], *geometry["labelBoxes"]]
    need(type(plans) is list and len(plans) == 3, "Disclosure and both photo labels required")
    for text, box, plan in zip(["Photo comparison", "Original", "Warm"], boxes, plans):
        need(plan["text"] == text and plan["lines"] == [text] and plan["fontSize"] == 46 and plan["container"] == box and len(plan["origins"]) == 1, "Comparison labels rewritten/hidden/too small")
        font = ImageFont.truetype(str(font_path), 46)
        b = font.getbbox(text)
        origin = [box[0] - b[0], box[1] - b[1]]
        glyph = [origin[0] + b[0], origin[1] + b[1], origin[0] + b[2], origin[1] + b[3]]
        need(list(plan["origins"][0]) == origin and plan["lineBBoxes"] == [glyph] and within(glyph, box), "Comparison actual glyphs must fit exact marketing containers")
        draw.text(origin, text, font=font, fill=value["layout"]["ink"])
    mask = Image.new("L", SIZE)
    mask.paste(255, actual["box"])
    for target in geometry["photoTargets"]:
        mask.paste(0, target)
    difference = Image.composite(ImageChops.difference(final, expected), Image.new("RGB", SIZE), mask)
    need(difference.getbbox() is None, "Actual comparison disclosure/background pixels differ; synthetic controls/slider not allowed")
    return actual


def verify_gestures(final, row, design, fonts):
    """Independently reconstruct marketing arrows too; they must never enter UI."""
    expected = reference.marketing_background(design)
    # The unchanged hardware shadow is painted before marketing labels by the
    # accepted engine and can reach the lowest pixels of this marketing band.
    # Reconstruct it from actual fixed geometry; never waive those pixels.
    device = design["layout"]["device"]
    frame = phone_geometry(design)["fullFrameGeometry"]
    ring = rounded(dimensions(frame), device["screenRadius"] + device["frameWidth"])
    field = Image.new("L", SIZE)
    field.paste(ring, (frame[0] + device["shadowOffset"][0], frame[1] + device["shadowOffset"][1]))
    field = field.filter(ImageFilter.GaussianBlur(device["shadowBlur"]))
    expected.paste((20, 29, 36), (0, 0), field.point(lambda n: round(n * device["shadowAlpha"] / 255)))
    gestures = row["gestures"]
    need(len(gestures) == (3 if row["slot"] == 1 else 0), "Wrong marketing gesture count")
    for value, spec in zip(gestures, design["layout"]["gestures"]):
        need({k: v for k, v in value.items() if k != "textPlan"} == spec, "Marketing gesture semantic drift")
        plan, box = value["textPlan"], spec["arrowBox"]
        need(plan["text"] == spec["action"] and plan["container"] == spec["labelBox"] and plan["lines"] == [spec["action"]] and 60 <= plan["fontSize"] <= 72, "Gesture label copy/size drift")
        path = source_path(ROOT, design["fonts"]["gesture"]["path"])
        need(digest(path) == fonts["gesture"]["sha256"], "Gesture font bytes drift")
        font = ImageFont.truetype(str(path), plan["fontSize"])
        draw = ImageDraw.Draw(expected)
        for line, origin, bbox in zip(plan["lines"], plan["origins"], plan["lineBBoxes"]):
            b = font.getbbox(line)
            need(bbox == [origin[0] + b[0], origin[1] + b[1], origin[0] + b[2], origin[1] + b[3]] and within(bbox, spec["labelBox"]), "False gesture label ink geometry")
            draw.text(origin, line, font=font, fill=design["colors"][spec["color"]])
        w, h = dimensions(box)
        tile = Image.new("RGBA", (w * 4, h * 4))
        points = [(0.04, 0.36), (0.57, 0.36), (0.57, 0.08), (0.96, 0.50), (0.57, 0.92), (0.57, 0.64), (0.04, 0.64)]
        if spec["direction"] == "left":
            points = [(1 - x, y) for x, y in points]
        elif spec["direction"] == "up":
            points = [(y, 1 - x) for x, y in points]
        ImageDraw.Draw(tile).polygon([(round(x * (tile.width - 1)), round(y * (tile.height - 1))) for x, y in points], fill=design["colors"][spec["color"]])
        tile = tile.resize((w, h), Image.Resampling.LANCZOS)
        expected.paste(tile.convert("RGB"), box[:2], tile.getchannel("A"))
        for region in (box, spec["labelBox"]):
            need(ImageChops.difference(final.crop(region), expected.crop(region)).getbbox() is None, "Actual gesture arrow/label pixels mismatch")


def audit(render, sources, expected_commit, expected_run, expected_attempt, design_path=DEFAULT_DESIGN):
    design_path = Path(design_path).resolve()
    design = load(design_path)
    attempt = require_calibrated(design, expected_commit, expected_run, expected_attempt)
    render, sources = Path(render).resolve(), Path(sources).resolve()
    need(render.is_relative_to(OUTPUT_ROOT.resolve()) and render != OUTPUT_ROOT.resolve() and not render.is_relative_to(ROOT) and
         not sources.is_relative_to(ROOT) and not render.is_relative_to(sources) and not sources.is_relative_to(render), "Protected/wrong V4 output/source scope")
    manifest = load(render / "render-manifest.json")
    keys(manifest, {"schemaVersion", "moduleVersion", "creativeRevision", "layoutRevision", "nativeRevision", "runAttempt", "sampleMediaPolicy", "capturePolicy", "nativeScenePolicy", "concept", "locale", "size", "renderer", "design", "captureBaselineCommit", "slotMapping", "sourceGate", "originalSources", "sourceVisualQA", "fonts", "ICC", "outputs", "previews", "layoutQA", "localizationRule"}, "render manifest")
    need(manifest["schemaVersion"] == 2 and manifest["moduleVersion"] == VERSION and all(type(manifest[k]) is int and manifest[k] == 4 for k in ("creativeRevision", "layoutRevision", "nativeRevision")) and
         manifest["capturePolicy"] == capture_policy(design) and manifest["sampleMediaPolicy"] == MEDIA_POLICY and manifest["nativeScenePolicy"] == SCENE_POLICY and
         (manifest["concept"], manifest["locale"], manifest["size"]) == ("A", "en-US", [1206, 2622]), "Old/mixed native creative contract cannot pass V4")
    need(manifest["captureBaselineCommit"] == BASELINE and manifest["slotMapping"] == design["slotMapping"] and manifest["localizationRule"] == design["localizationRule"], "V4 capture baseline/sequence drift")
    need(Path(manifest["design"]["path"]).resolve() == design_path and manifest["design"]["logicalPath"] == "app-store/concepts/A/v4-design.json" and digest(design_path) == manifest["design"]["sha256"], "Actual independent V4 design byte binding drift")
    provenance = load(source_path(sources, "capture_provenance.json"))
    need(digest(sources / "capture_provenance.json") == design["captureBinding"]["provenanceSHA256"] == manifest["sourceGate"]["provenanceSHA256"] and
         manifest["sourceGate"]["provenance"] == provenance and Path(manifest["sourceGate"]["sourceRoot"]).resolve() == sources, "Exact source root/provenance binding differs")
    reference.verify_manifest_attempt(manifest, attempt)
    need(manifest["sourceVisualQA"] == design["finalSourceVisualQA"], "Source visual approval differs")
    native, evidence = verify_sources(sources, provenance, design, expected_commit, expected_run, attempt)
    need(manifest["sourceGate"]["evidence"] == evidence and manifest["sourceGate"]["status"] == "PASS" and manifest["sourceGate"]["passedTest"] is True, "Saved source proof set differs from actual read-only re-evaluation")
    need(manifest["sourceGate"].get("actualWorkflowConclusion") == evidence["exactAttemptAPI"].get("actual_workflow_conclusion", "success")
         and manifest["sourceGate"].get("ownerException") == evidence["exactAttemptAPI"].get("owner_exception"),
         "Render manifest conceals the failed workflow or its exact owner exception")
    need(manifest["renderer"]["path"] == "scripts/store/render_concept_a_v4.py" and manifest["renderer"]["sha256"] == digest(ROOT / "scripts/store/render_concept_a_v4.py") and
         manifest["renderer"]["baseEnginePath"] == "scripts/store/render_concept_a.py" and manifest["renderer"]["baseEngineSHA256"] == digest(ROOT / "scripts/store/render_concept_a.py"), "Renderer/accepted engine byte binding drift")
    original_sources = manifest["originalSources"]
    paths = [r["path"] for r in original_sources]
    need(len(paths) == len(set(paths)) and set(paths) == LEGACY_SCREENS | NEW_SCREENS | {WORDMARK}, "All and only required same-run original sources must be inventoried")
    for record in original_sources:
        need(record["sha256"] == native[record["path"]]["sha256"] == digest(source_path(sources, record["path"])) and record["provenance"] == native[record["path"]], "Unbound/mutated original source")
    rows = manifest["outputs"]
    need(type(rows) is list and len(rows) == 10 and [r["slot"] for r in rows] == list(range(1, 11)), "Ten ordered actual numbered outputs required")
    files = [row["file"] for row in rows]
    need(files == [slot["file"] for slot in design["slots"]] and {p.name for p in render.glob("*.png")} == set(files), "Wrong/missing/extra numbered PNG output set")
    checked = []
    for row, slot in zip(rows, design["slots"]):
        keys(row, {"file", "sha256", "width", "height", "mode", "alpha", "format", "ICC", "slot", "headline", "subtitle", "gestures", "nativeLayers", "protectedEvidence", "creativeComposite", "framePixelQA", "layoutQA"}, "output record")
        path = source_path(render, row["file"])
        need(digest(path) == row["sha256"], "Actual output file hash drift")
        meta = reference.profile(path)
        raw = path.read_bytes()
        need(meta["size"] == [1206, 2622] and meta["format"] == "PNG" and raw[:8] == b"\x89PNG\r\n\x1a\n" and raw[24:26] == b"\x08\x02", "True 8-bit RGB/no-alpha/sRGB PNG required")
        need(row["width"] == 1206 and row["height"] == 2622 and row["mode"] == "RGB" and row["alpha"] is False and row["format"] == "PNG" and
             row["ICC"] == {"colorSpace": "sRGB", "embedded": True, "sha256": meta["icc_sha256"]} and manifest["ICC"]["sha256"] == meta["icc_sha256"], "False encoded output/ICC metadata")
        need(row["headline"]["text"] == COPY[slot["id"] - 1] and row["subtitle"]["text"] == SUBTITLES[slot["id"] - 1], "Exact V4 copy drift")
        mapped = verify_insets(row, slot, design, sources, native, evidence["legacySceneAudit"])
        with Image.open(path) as image:
            image.load()
            final = image.copy()
        reference.verify_marketing_text(final, row, design, manifest["fonts"])
        verify_gestures(final, row, design, manifest["fonts"])
        composite = verify_comparison(final, row, slot, design, sources, native, evidence["editorPair"], mapped, manifest["fonts"])
        layers, pixels = row["nativeLayers"], 0
        for index, layer in enumerate(layers):
            keys(layer, {"id", "originalSource", "sourceSHA256", "sourceSize", "sourceMode", "sourceICC", "crop", "targetGeometry", "nativeScale", "effectiveNativeScaleXY", "resample", "rotationDegrees", "colorManagement", "colorOperations", "mask", "maskSHA256", "visibleGeometry", "visibleLocalRect", "visibleSourceBounds", "viewportClipPixels", "viewportMaskSHA256", "visibleMaskSHA256", "pixelQA"}, "native layer")
            need(layer["originalSource"] in native and layer["sourceSHA256"] == native[layer["originalSource"]]["sha256"], "Layer not bound to same new native capture")
            pixels += verify_pixels(final, sources, layer, layers[index + 1:], design, composite)
        frame_pixels = verify_frame(final, design, row["framePixelQA"])
        layout = row["layoutQA"]
        need(layout == {"status": "PASS", "safeMargin": 70, "headlineMaxLines": 2, "subtitleMaxLines": 2, "phoneGeometry": phone_geometry(design), "originalNativeCrop": [0, 0, *SIZE],
             "phoneProportionalWithinHalfPixel": True, "nativeUpscaling": False, "secondDynamicIsland": False, "protectedPrimaryEvidenceUnobscured": True, "allTextBBoxesInsideContainers": True}, "False per-output geometry/control gate")
        checked.append({"slot": slot["id"], "file": row["file"], "sha256": row["sha256"], **meta, "native_layers_verified": len(layers),
                        "independently_compared_native_pixels": pixels, "visible_hardware_frame_pixels_verified": frame_pixels, "creative_composite": composite["kind"] if composite else None})
    need(len({r["sha256"] for r in checked}) == 10, "Duplicate final image")
    layout = manifest["layoutQA"]
    need(layout == {"status": "PASS", "pngCount": 10, "identicalFullTargetAndVisiblePhoneGeometry": True, "phoneGeometry": phone_geometry(design),
        "requiredInsetSlots": [2, 3, 4], "subtitleCount": 10, "screenBox": [131, 844, 1075, 2896], "frameBox": [122, 835, 1084, 2905],
        "backgroundColors": design["background"], "overviewSlots": list(range(1, 11)), "overviewRows": 1, "searchSlots": [1, 2, 3], "editorComparisonSlot": 9,
        "nativePixelComparison": "PASS", "finalHumanVisualQA": "NOT RUN"}, "False all-ten V4 layout contract")
    previews = reference.verify_previews(render, manifest["previews"], rows, design)
    need({p.name for p in render.iterdir()} == set(files) | {"00-overview.jpg", "00-search-preview.jpg", "render-manifest.json"}, "Unexpected delivery-tree files")
    return {"schema_version": 2, "module_version": VERSION, "creative_revision": 4, "technical_export_status": "PASS", "workflow_run": expected_run,
        "run_attempt": attempt, "commit": expected_commit, "locale": "en-US", "png_count": 10, "images": checked, "preview_count": 2, "previews": previews,
        "uniform_phone_box": [131, 844, 1075, 2896], "phone_geometry": phone_geometry(design), "required_inset_slots": [2, 3, 4], "editor_comparison_slot": 9,
        "source_evidence": evidence, "actual_workflow_conclusion": evidence["exactAttemptAPI"].get("actual_workflow_conclusion", "success"),
        "owner_exception": evidence["exactAttemptAPI"].get("owner_exception"),
        "render_manifest_sha256": digest(render / "render-manifest.json"), "design_sha256": digest(design_path),
        "provenance_sha256": digest(sources / "capture_provenance.json"), "auditor_sha256": digest(Path(__file__)),
        "native_pixels": "PASS, independently reconstructed from ICC-normalized originals; only actual alpha/viewport/disclosed composite occlusion excluded",
        "human_final_visual_acceptance": "NOT RUN", "native_capture_by_this_auditor": "NOT RUN", "security_runtime_conversion_or_store_upload_acceptance": "NOT RUN"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--render", required=True, type=Path)
    parser.add_argument("--sources", required=True, type=Path)
    parser.add_argument("--design", default=DEFAULT_DESIGN, type=Path)
    parser.add_argument("--expected-commit", required=True)
    parser.add_argument("--expected-workflow-run", required=True)
    parser.add_argument("--expected-run-attempt", required=True)
    parser.add_argument("--report", type=Path, help="New report outside repo/render/source trees; omit to print only")
    args = parser.parse_args(argv)
    try:
        if args.report:
            report = args.report.resolve()
            need(not report.exists() and not report.is_relative_to(ROOT) and not report.is_relative_to(args.render.resolve()) and not report.is_relative_to(args.sources.resolve()), "Never overwrite or write reports into protected/source/render trees")
        result = audit(args.render, args.sources, args.expected_commit, args.expected_workflow_run, args.expected_run_attempt, args.design)
    except Exception as error:
        result = {"technical_export_status": "FAIL", "module_version": VERSION, "creative_revision": 4, "error": f"{type(error).__name__}: {error}",
                  "human_final_visual_acceptance": "NOT RUN", "native_capture_by_this_auditor": "NOT RUN"}
    if args.report:
        # Validate write scope again even when the audit itself failed.
        report = args.report.resolve()
        if report.exists() or report.is_relative_to(ROOT) or report.is_relative_to(args.render.resolve()) or report.is_relative_to(args.sources.resolve()):
            print(json.dumps({"technical_export_status": "FAIL", "error": "Unsafe/existing report destination; nothing written"}))
            return 1
        report.parent.mkdir(parents=True, exist_ok=True)
        with report.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(result, stream, indent=2, ensure_ascii=False, allow_nan=False)
            stream.write("\n")
    print(json.dumps({k: v for k, v in result.items() if k != "images"}, ensure_ascii=False))
    return 0 if result["technical_export_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
