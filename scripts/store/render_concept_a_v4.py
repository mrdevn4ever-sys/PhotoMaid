#!/usr/bin/env python3
"""Separate Concept A V4 en-US renderer; native capture is deliberately NOT run.

Accepted engine primitives remain unmodified. This module owns its V4 contract;
no legacy constants are patched, no historical capture can satisfy the V4 gate,
and --check-layout is STRUCTURAL ONLY, never source/export/visual acceptance.
Calibrate v4-design.json only AFTER reviewing the new exact-attempt sources.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import math
from pathlib import Path
import re
import sys

from PIL import Image, ImageChops, ImageDraw

import render_concept_a as engine

VERSION = "concept-a-v4/1"
ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DESIGN = ROOT / "app-store/concepts/A/v4-design.json"
OUTPUT_ROOT = Path("F:/HermesOutput/GaleriQ/concept-a-en-v4")
BASELINE = "61800c00f0cc572cd7221d95355f04d7f1cc505e"
LEGACY_BASELINE = "583eb804a81401aa2010996875b35d05afc61539"
HISTORICAL_COMMITS = {"8ffdc943d8a3cc57ad8212320a0fea586609c6da"}
HISTORICAL_RUNS = {"43865738891"}
SIZE = (1206, 2622)
WORDMARK = "branding/native-wordmark.png"
MEDIA_POLICY = "approved-stock-photos-and-videos-no-app-screenshots"
SCENE_POLICY = "v4-mixed-approved-originals-real-month-progress-published-editor-pair"
CAPTURE_TEST = "AppStoreCaptureTests/test08ConceptAV4StoreScreenshots"
COPY = (
    ("Swipe the clutter. Keep the memories.", "Keep, trash or decide later.", "swipe"),
    ("Find duplicates. Free up space.", "Find extra copies and large files.", "large-files"),
    ("Similar shots. Keep your favorites.", "Review a series before you decide.", "analysis"),
    ("You decide what gets deleted.", "Review your choices before deleting.", "delete-confirm"),
    ("Private photos. Locked away.", "Encrypted vault, protected by your own code and Face ID.", "vault"),
    ("Not sure yet? Decide later.", "Come back when you are ready.", "later-swipe"),
    ("Clean up by month. See your progress.", "Pick a month and see your progress.", "v4-months"),
    ("Make a collage. With your photos.", "Choose photos, a layout and a style.", "collage"),
    ("Try a new look. Keep the original.", "Preview a look and save a separate copy.", "v4-editor-after"),
    ("Take a break. Play a little.", "Match pairs with your own photos.", "games"),
)
OLD_TO_NEW = {1: 1, 2: 2, 7: 3, 3: 4, 4: 5, 5: 6, 6: 7, 8: 8, 9: 9, 10: 10}
LEGACY_SCREENS = {f"screenshots/concept-a-{name}.png" for name in (
    "swipe", "duplicates", "large-files", "trash", "delete-confirm", "vault", "later",
    "later-swipe", "months", "analysis", "collage", "editor", "games", "games-menu")}
NEW_SCREENS = {f"screenshots/concept-a-v4-{name}.png" for name in (
    "months", "editor-before", "editor-after", "editor-undo", "editor-redo", "editor-copy-default")}
CAPTURES = LEGACY_SCREENS | NEW_SCREENS
INSETS = {2: ("duplicate-results", "duplicates", {"duplicate-pair", "selection-labels"}),
          3: ("series-decision", "analysis", {"series", "keep5-trash1"}),
          4: ("system-dialog", "delete-confirm", {"system-dialog"})}
REVIEW = {"stockOnlyEveryMediaTile", "sharpRecognizableFirstPhoto", "opaqueSystemDialogNoUnderlyingHome",
          "noLoadingSpinner", "heldRightwardLater", "filledNativePairsBoard", "nativeKeep5Trash1",
          "completeDuplicatePair", "actualMonthProgress", "editorPublishedOriginalWarmUndoRedo",
          "editorCopyDefault", "editorComparisonTruthful", "allTenFromSameNewAttempt"}
SOURCE_GATE = {"provenanceFile": "capture_provenance.json", "appLanguage": "en", "nativeSize": [1206, 2622],
               "minimumInsetTop": 200, "wordmarkSource": WORDMARK, "wordmarkComponent": "VaultDialWordmark",
               "wordmarkForeground": "lightForeground", "requireVisualQA": True,
               "requireProtectedNativeRects": True, "normalizeNativeICCToSRGB": True,
               "requiredCaptureTest": CAPTURE_TEST,
               "sourceManifest": "app-store/concepts/A/v4-source-media/manifest.json",
               "fixtureAllowlist": "app-store/concepts/A/qa/v4-fixture-source-allowlist.json"}
DEVICE = {"screenBox": [131, 844, 1075, 2896], "screenRadius": 115, "frameWidth": 9,
          "frameColor": "#242322", "shadowBlur": 20, "shadowOffset": [0, 12], "shadowAlpha": 38,
          "viewportClip": "bottom-only", "v2ReferenceScreenBox": [201, 760, 1005, 2508]}
FLAT = {"radius": 0, "shadowBlur": 0, "shadowOffset": [0, 0], "shadowAlpha": 0}
INSET_STYLE = {"radius": 24, "shadowBlur": 2, "shadowOffset": [0, 2], "shadowAlpha": 32}
COMPOSITE_KIND = "creative-composite-photo-comparison"
COMPOSITE_SOURCES = ("screenshots/concept-a-v4-editor-before.png", "screenshots/concept-a-v4-editor-after.png")
GateError = engine.GateError
need, keys, rect, wh = engine.need, engine.keys, engine.rect, engine.wh
inside, overlaps, expanded = engine.inside, engine.overlaps, engine.expanded
sha = engine.digest


def read_json(path: Path) -> dict:
    value = json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=engine.unique_object,
                       parse_constant=lambda token: (_ for _ in ()).throw(GateError("Nonfinite JSON: " + token)))
    need(type(value) is dict, "Expected JSON object: " + str(path))
    return value


def optional_sha(value, label):
    need(value is None or (type(value) is str and re.fullmatch(r"[0-9a-f]{64}", value)), label + ": malformed literal SHA-256")


# Deliberately literal, single-attempt exception pins; not an allow-failed switch.
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


def validate_c5_owner_authorization(value, sources):
    """The fixed owner's actual decision, not a new boolean approval invented here."""
    keys(value, {"schema", "status", "recorded_utc", "user_response", "quoted_offer", "run", "attempt", "capture_commit",
                 "failed_workflow_exception_authorized", "additional_native_run_authorized", "workflow_conclusion_preserved",
                 "source_approval", "raw_artifact_manifest", "derived_sources", "restrictions"}, label="C5 owner decision")
    need(type(value["schema"]) is int and value["schema"] == 1 and value["status"] == "OWNER_AUTHORIZED_TARGETED_C5_REVALIDATION_NOT_SOURCE_ACCEPTANCE"
         and value["user_response"] == "Weiter" and type(value["quoted_offer"]) is str and "„C5 verwenden“" in value["quoted_offer"]
         and type(value["recorded_utc"]) is str and bool(value["recorded_utc"]), "Actual explicit C5 owner decision required")
    need(value["run"] == C5_RUN and type(value["attempt"]) is int and value["attempt"] == 1 and value["capture_commit"] == C5_COMMIT
         and value["failed_workflow_exception_authorized"] is True and value["additional_native_run_authorized"] is False
         and value["workflow_conclusion_preserved"] == "failure" and value["source_approval"] is False,
         "C5 owner scope/run/attempt differs or improperly grants capture/source approval")
    derived = OUTPUT_ROOT / "revalidated-C5-43949822336-attempt-1/sources"
    need(value["raw_artifact_manifest"] == "qa/c5-original-artifact-immutable-snapshot.json" and value["derived_sources"] == derived.as_posix()
         and Path(sources).resolve() == derived.resolve() and value["restrictions"] == ["No native capture/dispatch/rerun", "No PR/merge/ASC/localization",
         "Preserve v1/v2/v3/final archives", "Do not edit raw C5 evidence", "Independent real revalidation and source/final VQA required"],
         "C5 owner restrictions or exact DERIVED source root changed")


def validate_c5_readback(readback, provenance):
    """Independent failed-workflow facts; this ALONE is not owner/source acceptance."""
    import collect_concept_a_v4_provenance as collector
    pins = collector.validate_run_pins(provenance)
    need(pins == {"workflow_run": C5_RUN, "run_attempt": "1", "commit": C5_COMMIT,
                  "branch": "hermes/store-concept-a-en", "repository": "mrdevn4ever-sys/PhotoMaid"}, "C5 exception cannot authorize another run/attempt/SHA")
    actual, jobs, latest = readback.get("attempt_readback"), readback.get("attempt_jobs_readback"), readback.get("run")
    need(type(actual) is dict and type(jobs) is dict and type(latest) is dict, "Complete actual C5 API readbacks required")
    need(all(type(actual.get(k)) is int and actual[k] == n for k, n in (("id", 43949822336), ("run_attempt", 1), ("workflow_id", 389136991)))
         and type(readback.get("run_attempt")) is int and readback["run_attempt"] == 1
         and actual.get("head_sha") == C5_COMMIT and actual.get("head_branch") == "hermes/store-concept-a-en"
         and actual.get("event") == "workflow_dispatch" and actual.get("status") == "completed" and actual.get("conclusion") == "failure",
         "C5 exact attempt must remain completed/failure on the literal capture pins")
    api = "https://api.github.com/repos/mrdevn4ever-sys/PhotoMaid/actions/runs/" + C5_RUN
    web = "https://github.com/mrdevn4ever-sys/PhotoMaid/actions/runs/" + C5_RUN
    need(actual.get("url") == api and actual.get("html_url") == web and actual.get("jobs_url") == api + "/attempts/1/jobs"
         and actual.get("workflow_url") == "https://api.github.com/repos/mrdevn4ever-sys/PhotoMaid/actions/workflows/389136991"
         and ("request_url" not in readback or readback["request_url"] == api + "/attempts/1"), "C5 exact API resource differs")
    rows = jobs.get("jobs")
    need(type(jobs.get("total_count")) is int and jobs["total_count"] == 1 and type(rows) is list and len(rows) == 1, "Exactly the one complete C5 job required")
    job = rows[0]
    need(type(job) is dict and all(type(job.get(k)) is int and job[k] == n for k, n in (("id", 133589042502), ("run_id", 43949822336), ("run_attempt", 1)))
         and job.get("head_sha") == C5_COMMIT and job.get("head_branch") == "hermes/store-concept-a-en" and job.get("status") == "completed"
         and job.get("conclusion") == "failure" and job.get("run_url") == api, "C5 job is pending or from another attempt")
    steps = job.get("steps")
    need(type(steps) is list and len(steps) == 13 and all(type(s) is dict and type(s.get("number")) is int for s in steps)
         and [s["number"] for s in steps] == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 22, 23], "Complete literal C5 step list required")
    by_number = {s["number"]: s for s in steps}
    for step in steps:
        need(step.get("status") == "completed" and step.get("conclusion") == ("failure" if step["number"] == 9 else "success"),
             "Only C5's postcapture binding step may have failed; no skipped/pending/other failure")
        need(all(type(step.get(k)) is str and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z", step[k]) for k in ("started_at", "completed_at"))
             and step["started_at"] <= step["completed_at"], "Actual completed native step timestamps required")
    need(by_number[5].get("name") == "Build current app and capture test without Apple credentials"
         and by_number[8].get("name") == "Capture real swipes, finished results, trash confirmation, vault and creative tools"
         and by_number[9].get("name") == C5_FAILED_STEP
         and by_number[5]["completed_at"] <= by_number[8]["started_at"]
         and by_number[8]["completed_at"] <= by_number[9]["started_at"], "Failure must be strictly AFTER the genuine successful build/capture")
    need(all(type(latest.get(k)) is int and latest[k] == n for k, n in (("databaseId", 43949822336), ("runAttempt", 1)))
         and latest.get("headSha") == C5_COMMIT and latest.get("headBranch") == "hermes/store-concept-a-en" and latest.get("event") == "workflow_dispatch"
         and latest.get("status") == "completed" and latest.get("conclusion") == "failure" and latest.get("url") == web and latest.get("jobs") == rows,
         "Latest wrapper must not substitute a successful rerun for C5")
    artifacts = readback.get("artifacts", {})
    need(type(artifacts.get("total_count")) is int and artifacts["total_count"] == 1 and type(artifacts.get("artifacts")) is list and len(artifacts["artifacts"]) == 1,
         "Actual single C5 artifact API record required")
    artifact = artifacts["artifacts"][0]
    need(type(artifact.get("id")) is int and artifact["id"] == 14268939904
         and artifact.get("name") == "galeriq-concept-a-v4-en-US-native-43949822336-attempt-1"
         and artifact.get("digest") == "sha256:f4a09af54d15ce0c4f6529f8aaad1e05f330acdd8d675ad867e7154d1c63d855"
         and artifact.get("workflow_run", {}).get("id") == 43949822336 and artifact["workflow_run"].get("head_sha") == C5_COMMIT
         and artifact["workflow_run"].get("head_branch") == "hermes/store-concept-a-en", "C5 artifact identity does not match the preserved native run")
    counters = readback.get("actual_native_capture_test", {})
    need(set(counters) == {"passed", "failed", "skipped", "total"} and all(type(counters[k]) is int and counters[k] == n for k, n in (("passed", 1), ("failed", 0), ("skipped", 0), ("total", 1)))
         and readback.get("workflow_conclusion") == "failure", "Actual C5 native test must be 1 PASS / 0 FAIL / 0 SKIP")
    return {**pins, "actual_api_run_attempt": 1, "complete_jobs": 1, "actual_workflow_conclusion": "failure", "workflow_success": False,
            "failed_postcapture_step": {"number": 9, "name": C5_FAILED_STEP}}


def validate_c5_receipt(value, binding, provenance_sha256):
    keys(value, {"schemaVersion", "kind", "workflowRun", "runAttempt", "commit", "branch", "actualWorkflowConclusion", "ownerAuthorization",
                 "originalInventory", "originalProvenanceSHA256", "originalErrors", "exactAttemptReadback", "correctedCollector"}, label="C5 exception receipt")
    need(type(value["schemaVersion"]) is int and value["schemaVersion"] == 1 and value["kind"] == C5_KIND and value["workflowRun"] == C5_RUN
         and type(value["runAttempt"]) is int and value["runAttempt"] == 1 and value["commit"] == C5_COMMIT and value["branch"] == "hermes/store-concept-a-en"
         and value["actualWorkflowConclusion"] == "failure" and binding["commit"] == C5_COMMIT and binding["workflowRun"] == C5_RUN
         and engine.canonical_run_attempt(binding["runAttempt"], "C5 binding attempt") == 1, "C5 receipt is not the exact authorized failed attempt")
    need(value["ownerAuthorization"] == {"file": "qa/c5-owner-decision-20261117.json", "sha256": C5_OWNER_SHA}
         and value["originalInventory"] == {"file": "qa/c5-original-artifact-immutable-snapshot.json", "sha256": C5_INVENTORY_SHA}
         and value["originalProvenanceSHA256"] == C5_ORIGINAL_SHA and value["originalErrors"] == C5_ERRORS,
         "Actual owner/original FAIL provenance and immutable inventory bindings required")
    need(value["exactAttemptReadback"] == binding["exactAttemptReadback"] == {"file": "run-43949822336-readback.json", "sha256": C5_READBACK_SHA},
         "Only the original literal failed C5 API readback is admissible")
    local = value["correctedCollector"]
    keys(local, {"file", "sha256", "scope", "fixtureRoot", "codeSHA256", "auditsSHA256", "sourceHashesSHA256"}, label="C5 local collector receipt")
    need(local["file"] == "capture_provenance.json" and local["sha256"] == provenance_sha256 == binding["provenanceSHA256"]
         and local["sha256"] != C5_ORIGINAL_SHA and local["scope"] == "C5-retained-native-evidence-and-local-revalidation", "Actual corrected local collector report must be separately hash-bound")
    for token in (local["sha256"], local["auditsSHA256"], local["sourceHashesSHA256"]):
        optional_sha(token, "C5 local binding")
        need(token is not None, "Incomplete C5 revalidation hashes")
    need(type(local["fixtureRoot"]) is str and Path(local["fixtureRoot"]).is_absolute()
         and Path(local["fixtureRoot"]).resolve().as_posix() == local["fixtureRoot"] and type(local["codeSHA256"]) is dict,
         "Literal actual prepared fixture root and collector code hashes required")
    keys(local["codeSHA256"], {"scripts/store/collect_concept_a_v4_provenance.py", "scripts/store/collect_concept_a_provenance.py",
         "scripts/store/build_concept_a_v4_fixture.py", "scripts/store/concept_a_v4_c5_exception.py"}, label="C5 collector code hashes")
    for token in local["codeSHA256"].values():
        optional_sha(token, "C5 collector code hash")
        need(token is not None, "Missing C5 collector code hash")


def verify_workflow_binding(design, sources, provenance):
    """Read-only complete workflow gate, callable before (not instead of) source VQA."""
    import collect_concept_a_v4_provenance as collector
    import concept_a_v4_c5_exception as materials
    validate_design(design)
    binding = design["captureBinding"]
    readback = materials.bound_json(sources, binding["exactAttemptReadback"], read_json)
    exception = binding.get("workflowException")
    if exception is None:
        # Unchanged ordinary path: the collector MUST still reject any failed run.
        return collector.validate_exact_attempt_readback(readback, provenance)
    need(Path(sources).resolve() == (OUTPUT_ROOT / "revalidated-C5-43949822336-attempt-1/sources").resolve(), "C5 requires its exact DERIVED source root")
    receipt = materials.bound_json(OUTPUT_ROOT, exception, read_json)
    provenance_sha = sha(materials.safe_file(sources, "capture_provenance.json").read_bytes())
    need(read_json(materials.safe_file(sources, "capture_provenance.json")) == provenance, "Passed local report differs from actual corrected report bytes")
    validate_c5_receipt(receipt, binding, provenance_sha)
    owner = materials.bound_json(OUTPUT_ROOT, receipt["ownerAuthorization"], read_json)
    validate_c5_owner_authorization(owner, sources)
    snapshot = materials.bound_json(OUTPUT_ROOT, receipt["originalInventory"], read_json)
    need(type(snapshot.get("schema")) is int and snapshot["schema"] == 1 and snapshot.get("status") == "PASS_IMMUTABLE_RAW_C5_ARTIFACT_SNAPSHOT" and snapshot.get("run") == C5_RUN
         and type(snapshot.get("attempt")) is int and snapshot["attempt"] == 1 and snapshot.get("commit") == C5_COMMIT, "Actual immutable C5 snapshot pins differ")
    inventory = materials.verify_immutable_inventory(snapshot, sources)
    original = materials.bound_json(materials.RAW_ROOT, {"file": "capture_provenance.json", "sha256": C5_ORIGINAL_SHA}, read_json)
    need(original.get("status") == "FAIL" and original.get("errors") == C5_ERRORS and provenance.get("status") == "PASS" and provenance.get("errors") == [],
         "Preserve original FAIL; require a genuine corrected LOCAL collector PASS")
    facts = validate_c5_readback(readback, provenance)
    local = materials.recompute_local_data(sources, receipt["correctedCollector"]["fixtureRoot"], provenance, original)
    need(all(receipt["correctedCollector"][k] == local[k] for k in ("codeSHA256", "auditsSHA256", "sourceHashesSHA256")),
         "C5 corrected collector code/all-gates/same-source hash revalidation differs")
    return {**facts, "status": "OWNER_AUTHORIZED_EXCEPTION", "readback_sha256": C5_READBACK_SHA,
            "owner_exception": {"kind": C5_KIND, "receipt": exception, "authorization": receipt["ownerAuthorization"],
                "original_inventory": receipt["originalInventory"], "original_errors": C5_ERRORS, **inventory,
                "corrected_provenance_sha256": provenance_sha, "local_data_status": local["localDataStatus"],
                "workflow_conclusion": "failure", "source_or_final_visual_approval_granted": False}}


def capture_policy(design):
    return "single-C5-owner-authorized-postcapture-exception" if design["captureBinding"].get("workflowException") is not None else "single-new-green-v4-stock-only-run"


def phone_geometry(design):
    need(design["layout"]["device"] == DEVICE, "V4 must retain the exact accepted common phone/frame geometry")
    return engine.phone_geometry(design)


def validate_design(design):
    """Strict closed design schema, including every pending calibration field."""
    keys(design, {"schemaVersion", "moduleVersion", "concept", "direction", "locale", "canvas", "background", "colors",
                  "tokenReferences", "fonts", "layout", "sourceGate", "slots", "previews", "localizationRule",
                  "creativeRevision", "layoutRevision", "nativeRevision", "nativeScenePolicy", "sampleMediaPolicy",
                  "captureBaselineCommit", "captureBinding", "finalSourceVisualQA", "slotMapping", "outputRoot"}, label="V4 design")
    need(type(design["schemaVersion"]) is int and design["schemaVersion"] == 2 and design["moduleVersion"] == VERSION,
         "Explicit separate V4 schema/module version required")
    need(all(type(design[k]) is int and design[k] == 4 for k in ("creativeRevision", "layoutRevision", "nativeRevision")), "V4 revisions required")
    need((design["concept"], design["direction"], design["locale"]) == ("A", "Space to Breathe", "en-US"), "Only accepted Concept A/en-US")
    need(design["captureBaselineCommit"] == BASELINE and design["outputRoot"] == OUTPUT_ROOT.as_posix(), "V4 baseline/output scope differs")
    need(design["nativeScenePolicy"] == SCENE_POLICY and design["sampleMediaPolicy"] == MEDIA_POLICY, "V4 native/stock-only policy changed")
    need(design["slotMapping"] == [{"old": old, "new": new} for old, new in OLD_TO_NEW.items()], "Explicit old-to-new mapping drift")
    need(design["canvas"] == {"width": 1206, "height": 2622, "safeMargin": 70}, "Exact Store canvas required")
    need(design["background"] == {"top": "#E0EFF9", "bottom": "#EAF4FB", "interpolation": "smoothstep"}, "Accepted ice-blue changed")
    need(design["colors"] == {"ink": "#1C1916", "subtitle": "#1C1916", "keep": "#1B6FA8", "trash": "#C4441A", "later": "#6347D0"}, "Accepted ink/gesture palette changed")
    need(design["tokenReferences"] == {"file": "PhotoMaid/DesignSystem/Tokens.swift", "sky_tint": "AppColors.tileKeep.light = #E0EFF9",
         "keep": "AppColors.keep.light = #1B6FA8", "trash": "AppColors.cleanup.light = #C4441A", "later": "AppColors.later.light = #6347D0"}, "Token references drift")
    need(design["sourceGate"] == SOURCE_GATE, "Source gate must not be weakened or redirected")
    binding = design["captureBinding"]
    keys(binding, {"approved", "commit", "workflowRun", "runAttempt", "provenanceSHA256", "exactAttemptReadback"},
         optional={"workflowException"}, label="captureBinding")
    exception = binding.get("workflowException")
    if exception is not None:
        keys(exception, {"file", "sha256"}, label="workflowException")
        need(exception["file"] == "qa/c5-postcapture-workflow-exception.json", "Only the explicit C5 owner exception report may be bound")
        optional_sha(exception["sha256"], "workflowException.sha256")
        need(exception["sha256"] is not None, "C5 exception report hash cannot be pending")
    need(type(binding["approved"]) is bool, "Explicit capture approval boolean required")
    need(binding["commit"] is None or (type(binding["commit"]) is str and re.fullmatch(r"[0-9a-f]{40}", binding["commit"])), "Malformed literal capture commit")
    need(binding["workflowRun"] is None or (type(binding["workflowRun"]) is str and re.fullmatch(r"[1-9][0-9]*", binding["workflowRun"])), "Malformed literal capture run")
    if binding["runAttempt"] is not None:
        engine.canonical_run_attempt(binding["runAttempt"], "captureBinding.runAttempt")
    optional_sha(binding["provenanceSHA256"], "captureBinding.provenanceSHA256")
    readback = binding["exactAttemptReadback"]
    keys(readback, {"file", "sha256"}, label="exactAttemptReadback")
    need(readback["file"] is None or (type(readback["file"]) is str and re.fullmatch(r"[A-Za-z0-9_.-]+\.json", readback["file"])), "Readback must be an explicit root JSON filename")
    optional_sha(readback["sha256"], "exactAttemptReadback.sha256")
    review = design["finalSourceVisualQA"]
    keys(review, {"approved", "provenanceSHA256", "commit", "workflowRun", "runAttempt", "reviewer", "notes", "nativeWordmarkComponent",
                  "nativeWordmarkForeground", "nativeStatusBar", "requirements", "sourceReview"}, label="finalSourceVisualQA")
    need(type(review["approved"]) is bool and set(review["requirements"]) == REVIEW and all(type(v) is bool for v in review["requirements"].values()), "Explicit V4 source-review requirement set required")
    optional_sha(review["provenanceSHA256"], "source visual provenance")
    need(review["nativeWordmarkComponent"] == "VaultDialWordmark" and review["nativeWordmarkForeground"] == "lightForeground" and
         review["nativeStatusBar"] == {"time": "9:41", "fullBattery": True, "dynamicIsland": True, "appearance": "dark"}, "Canonical branding/status contract drift")
    keys(review["sourceReview"], {"file", "sha256"}, label="sourceReview")
    optional_sha(review["sourceReview"]["sha256"], "sourceReview.sha256")
    need(review["sourceReview"]["file"] is None or (type(review["sourceReview"]["file"]) is str and re.fullmatch(r"[A-Za-z0-9_.-]+\.json", review["sourceReview"]["file"])), "Source review must be explicit root JSON")
    layout = design["layout"]
    keys(layout, {"alignment", "wordmarkBox", "headlineBox", "subtitleBox", "device", "insetStyle", "seriesInsetStyle", "dialogInsetStyle", "gestures"}, label="layout")
    need(layout["alignment"] == "left" and layout["wordmarkBox"] == [70, 78, 406, 200] and
         layout["headlineBox"] == [70, 248, 1136, 532] and layout["subtitleBox"] == [70, 560, 1136, 708], "Accepted header geometry changed")
    phone_geometry(design)
    need(layout["insetStyle"] == INSET_STYLE and layout["seriesInsetStyle"] == layout["dialogInsetStyle"] == FLAT, "Native inset/frame styles drift")
    gestures = [
        {"action": "Keep", "direction": "up", "color": "keep", "arrowBox": [70, 734, 124, 788], "labelBox": [144, 724, 370, 808]},
        {"action": "Trash", "direction": "left", "color": "trash", "arrowBox": [454, 734, 508, 788], "labelBox": [528, 724, 754, 808]},
        {"action": "Later", "direction": "right", "color": "later", "arrowBox": [838, 734, 892, 788], "labelBox": [912, 724, 1136, 808]}]
    need(layout["gestures"] == gestures, "Physical gesture semantics/geometry must not be mirrored or repurposed")
    keys(design["fonts"], {"headline", "subtitle", "gesture"}, label="fonts")
    for kind, filename, preferred, floor, lines, gap in (("headline", "PMDisplay-Bold.ttf", 112, 84, 2, 12),
            ("subtitle", "PMText-Medium.ttf", 52, 46, 2, 8), ("gesture", "PMText-Bold.ttf", 72, 60, 1, 0)):
        need(design["fonts"][kind] == {"path": "PhotoMaid/Resources/Fonts/" + filename, "preferredSize": preferred,
             "minimumSize": floor, "step": 1, "maxLines": lines, "lineGap": gap}, "Accepted bundled font/fit contract changed: " + kind)
    need(type(design["slots"]) is list and len(design["slots"]) == 10, "Exactly ten V4 slots required")
    files = set()
    for index, (slot, expected) in enumerate(zip(design["slots"], COPY), 1):
        required = {"id", "file", "headline", "subtitle", "primary", "primarySourceSHA256", "primaryProtectedRects", "gestures", "insets", "evidence"}
        keys(slot, required | ({"editorComparison"} if index == 9 else set()), label=f"slot {index}")
        need(type(slot["id"]) is int and slot["id"] == index and (slot["headline"], slot["subtitle"]) == expected[:2], "V4 exact copy/sequence drift")
        need(slot["primary"] == f"screenshots/concept-a-{expected[2]}.png", "Wrong exact V4 native primary")
        need(type(slot["file"]) is str and re.fullmatch(fr"{index:02d}-[a-z0-9-]+\.png", slot["file"]) and slot["file"] not in files, "Unsafe/duplicate numbered filename")
        files.add(slot["file"])
        need(slot["gestures"] is (index == 1) and type(slot["evidence"]) is str and slot["evidence"].strip(), "Explicit truthful slot semantics required")
        optional_sha(slot["primarySourceSHA256"], "primary hash")
        regions = slot["primaryProtectedRects"]
        need(regions is None or (type(regions) is list and bool(regions)), "Protected rects must be pending or nonempty")
        if regions is not None:
            for region in regions:
                rect(region, "primary protected rect")
        need(type(slot["insets"]) is list, "Explicit inset array required")
        if index not in INSETS:
            need(slot["insets"] == [], "No extra focus, including Later")
        else:
            name, source, evidence = INSETS[index]
            need(len(slot["insets"]) == 1, "Exactly one genuine native detail required")
            inset = slot["insets"][0]
            fields = {"id", "source", "crop", "cropSourceSHA256", "cropEvidenceRects", "targetBox", "enabled", "required", "evidence", "verticalAnchor"}
            keys(inset, fields | ({"nativeRectEvidence"} if index == 4 else set()), label="inset")
            need(inset["id"] == name and inset["source"] == f"screenshots/concept-a-{source}.png" and inset["enabled"] is True and inset["required"] is True, "Wrong native inset binding")
            need(set(inset["cropEvidenceRects"]) == evidence and inset["verticalAnchor"] == ("center" if index == 2 else "bottom"), "Required complete native inset evidence/anchor differs")
            optional_sha(inset["cropSourceSHA256"], "crop source hash")
            if inset["crop"] is not None:
                rect(inset["crop"], "inset crop")
            for region in inset["cropEvidenceRects"].values():
                if region is not None:
                    rect(region, "inset evidence")
            rect(inset["targetBox"], "planned inset output box")
            if index == 4:
                binding = inset["nativeRectEvidence"]
                keys(binding, {"file", "sha256", "jsonPointer", "format", "coordinateScale"}, label="nativeRectEvidence")
                need({k: v for k, v in binding.items() if k != "sha256"} == {"file": "concept-a-delete-confirm-frame.json", "jsonPointer": "/nativeRect", "format": "xyxy", "coordinateScale": 1}, "Only actual native dialog receipt accepted")
                optional_sha(binding["sha256"], "native dialog proof hash")
        if index == 9:
            validate_comparison(slot["editorComparison"])
    keys(design["previews"], {"overview", "search"}, label="previews")
    for kind, ids, width, margin, gap, filename in (("overview", list(range(1, 11)), 241, 20, 20, "00-overview.jpg"),
            ("search", [1, 2, 3], 112, 16, 11, "00-search-preview.jpg")):
        need(design["previews"][kind] == {"file": filename, "slotIds": ids, "columns": len(ids), "tileWidth": width, "gap": gap, "margin": margin}, "Single-row preview contract drift")
    keys(design["localizationRule"], {"renderNow", "futureOnly"}, label="localizationRule")
    need(design["localizationRule"]["renderNow"] == ["en-US"] and type(design["localizationRule"]["futureOnly"]) is str, "Localization not authorized")


def validate_comparison(value):
    keys(value, {"kind", "approved", "sourceBefore", "sourceAfter", "sourceBeforeSHA256", "sourceAfterSHA256", "proof",
                 "photoCrop", "targetBox", "disclosure", "labels", "nativeSideBySideClaim", "layout"}, label="editorComparison")
    need(value["kind"] == COMPOSITE_KIND and type(value["approved"]) is bool and value["nativeSideBySideClaim"] is False,
         "Editor comparison must be an explicitly disclosed marketing composite, never native split-view UI")
    need((value["sourceBefore"], value["sourceAfter"]) == COMPOSITE_SOURCES and
         value["disclosure"] == "Photo comparison" and value["labels"] == ["Original", "Warm"], "Actual Original/Warm bindings/labels required")
    for field in ("sourceBeforeSHA256", "sourceAfterSHA256"):
        optional_sha(value[field], field)
    keys(value["proof"], {"file", "sha256"}, label="editor proof")
    need(value["proof"]["file"] == "editor-pair-proof.json", "Actual native editor-pair receipt required")
    optional_sha(value["proof"]["sha256"], "editor proof hash")
    for field in ("photoCrop", "targetBox"):
        if value[field] is not None:
            rect(value[field], "editor comparison " + field)
    need(value["layout"] == {"padding": 16, "gap": 20, "disclosureHeight": 54, "labelHeight": 54,
                            "fontSize": 46, "photoRadius": 0, "shadowAlpha": 0, "background": "#E0EFF9", "ink": "#1C1916"}, "Marketing comparison must remain flat, labeled, and visually separate from native controls")


def require_calibrated(design, commit, run, attempt):
    """Fail before opening any native input or creating any output directory."""
    validate_design(design)
    need(type(commit) is str and re.fullmatch(r"[0-9a-f]{40}", commit), "Literal full new capture commit required")
    need(type(run) is str and re.fullmatch(r"[1-9][0-9]*", run), "Literal positive new run required")
    attempt = engine.canonical_run_attempt(attempt, "expected attempt")
    if design["captureBinding"].get("workflowException") is not None:
        need(commit == C5_COMMIT and run == C5_RUN and attempt == 1, "C5 exception cannot authorize another run/attempt/SHA")
    need(commit not in HISTORICAL_COMMITS and run not in HISTORICAL_RUNS and commit != BASELINE, "Historical C14/baseline cannot be new V4 capture evidence")
    binding, review = design["captureBinding"], design["finalSourceVisualQA"]
    need(binding["approved"] is True, "V4 captureBinding is UNAPPROVED; await the real new native run/attempt")
    need(binding["commit"] == commit and binding["workflowRun"] == run and
         engine.canonical_run_attempt(binding["runAttempt"], "binding attempt") == attempt, "New V4 capture pins disagree")
    need(binding["provenanceSHA256"] and binding["exactAttemptReadback"]["file"] and binding["exactAttemptReadback"]["sha256"], "Exact new provenance/API readback binding is unset")
    need(review["approved"] is True and review["commit"] == commit and review["workflowRun"] == run and
         engine.canonical_run_attempt(review["runAttempt"], "review attempt") == attempt and
         review["provenanceSHA256"] == binding["provenanceSHA256"] and
         all(type(review[k]) is str and review[k].strip() for k in ("reviewer", "notes")) and
         all(review["requirements"].values()) and review["sourceReview"]["file"] and review["sourceReview"]["sha256"], "Source VQA is unapproved/incomplete or not bound to the exact new capture")
    for slot in design["slots"]:
        need(slot["primarySourceSHA256"] and slot["primaryProtectedRects"], "New primary hashes/protected rects are uncalibrated")
        for inset in slot["insets"]:
            need(inset["crop"] and inset["cropSourceSHA256"] and all(inset["cropEvidenceRects"].values()), "New native inset crops/evidence are uncalibrated")
            if "nativeRectEvidence" in inset:
                need(inset["nativeRectEvidence"]["sha256"], "New system dialog receipt hash is unset")
    comparison = design["slots"][8]["editorComparison"]
    need(comparison["approved"] is True and all(comparison[k] for k in ("photoCrop", "targetBox", "sourceBeforeSHA256", "sourceAfterSHA256")) and
         comparison["proof"]["sha256"], "Actual two-source editor comparison is unapproved/uncalibrated")
    return attempt


def validate_provenance(value, commit, run, attempt):
    need(type(value.get("schema_version")) is int and value["schema_version"] == 2 and value.get("creative_revision") == 4,
         "Separate V4 collector schema/revision required, not relabeled C14")
    need(value.get("status") == "PASS" and value.get("errors") == [] and value.get("native_scene_policy") == SCENE_POLICY and
         value.get("v4_native_scene_policy") == SCENE_POLICY, "V4 native proof collector must pass")
    # Explicit read-only compatibility projection: ONLY schema version is mapped
    # for the accepted header/PNG validator. The complete V4 object is retained.
    base = copy.deepcopy(value)
    base["schema_version"] = 1
    rows = engine.validate_provenance(base, commit, run, attempt)
    need(value.get("branch") == "hermes/store-concept-a-en" and commit not in HISTORICAL_COMMITS and run not in HISTORICAL_RUNS,
         "All sources must come from ONE new native run on the isolated branch")
    need(CAPTURES | {WORDMARK} <= rows.keys(), "All old 14 sources plus actual new month/editor sources required")
    audits = value.get("v4_audits")
    required = {"literal_run_pins", "capture_test", "fixture_manifest", "original_sources", "fixture_records", "fixture_files",
                "captured_fixture_manifest_bytes", "native_screens", "actual_library", "sample_media", "month_progress", "editor_pair", "exact_attempt_api"}
    need(type(audits) is dict and required <= audits.keys(), "Incomplete V4 collector audit set")
    for name in required - {"fixture_manifest", "actual_library", "exact_attempt_api"}:
        need(type(audits[name]) is dict and audits[name].get("status") == "PASS", "Actual V4 collector subgate failed: " + name)
    need(audits["capture_test"].get("test") == CAPTURE_TEST, "Historical/native summary-only PASS cannot replace test08")
    need(value.get("base_c14_provenance", {}).get("status") == "PASS" and
         value.get("base_c14_native_scene_policy") == "sharp-stock-hero-opaque-confirmation-filled-photo-game", "Original scene gates must still pass")
    return rows


class SourceGate(engine.SourceGate):
    """Reuse immutable native PNG/ICC loader; V4 pins and proofs are not legacy globals."""
    def __init__(self, root, commit, run, expected_attempt):
        need(Path(root).is_dir(), "Exact new native source root missing; no fallback")
        self.root = Path(root).resolve()
        need(not self.root.is_relative_to(ROOT), "New source artifact must remain outside the release worktree")
        path = engine.safe_asset(self.root, "capture_provenance.json")
        self.provenance = read_json(path)
        self.provenance_sha256 = sha(path.read_bytes())
        self.expected_attempt = engine.canonical_run_attempt(expected_attempt, "expected attempt")
        self.rows = validate_provenance(self.provenance, commit, run, self.expected_attempt)
        self.loaded = {}


def verify_new_evidence(design, gate):
    """Read-only re-evaluation of actual proofs; never reruns/rewrites the collector."""
    import collect_concept_a_v4_provenance as collector
    import collect_concept_a_provenance as original
    import build_concept_a_v4_fixture as builder
    need(collector.V4_SCENE_POLICY == SCENE_POLICY and set(collector.legacy.REQUIRED) == {Path(p).stem.removeprefix("concept-a-") for p in LEGACY_SCREENS}, "Collector required-source contract drift")
    need(gate.provenance_sha256 == design["captureBinding"]["provenanceSHA256"], "Actual new provenance bytes differ from approval")
    fixture = read_json(engine.safe_asset(gate.root, "fixture-manifest.json"))
    library = read_json(engine.safe_asset(gate.root, "concept-a-library.json"))
    need(sha(engine.safe_asset(gate.root, "fixture-manifest.json").read_bytes()) == gate.provenance["fixture_manifest_sha256"], "Fixture manifest bytes drift")
    actual_stock = engine.verify_sample_media_policy(gate)
    # Canonical public evidence shape is independently reconstructed by the
    # auditor (not the collector's richer internal status/error dictionary).
    stock = {"policy": MEDIA_POLICY, "actual_library_sha256": sha(engine.safe_asset(gate.root, "concept-a-library.json").read_bytes()),
             **{k: actual_stock[k] for k in ("actual_asset_count", "actual_photo_count", "actual_video_count", "actual_screenshot_subtype_count")}}
    registry_path = engine.safe_asset(ROOT, SOURCE_GATE["sourceManifest"])
    allowlist_path = engine.safe_asset(ROOT, SOURCE_GATE["fixtureAllowlist"])
    registry, allowlist = read_json(registry_path), read_json(allowlist_path)
    builder.validate_registry(registry, allowlist)
    collector.validate_fixture_metadata(fixture, registry, allowlist, sha(registry_path.read_bytes()), sha(allowlist_path.read_bytes()))
    need(fixture["visual_source_gate"] == gate.provenance["fixture_visual_source_gate"], "Captured fixture visual allowlist gate differs")
    scenes = original.audit_v3_scenes(gate.root, fixture)
    need(scenes.get("status") == "PASS" and scenes == gate.provenance["native_scene_audit"], "Retained sharp-hero/opaque-dialog/filled-board evidence changed")
    screens = collector.validate_native_screens(gate.root)
    need(all(gate.rows[path] == row for path, row in screens.items()), "Actual V4 native source inventory differs from collector")
    month = collector.audit_month_progress(gate.root, screens, library)
    editor = collector.audit_editor_pair(gate.root, screens, library)
    need(month == gate.provenance["v4_audits"]["month_progress"] and editor == gate.provenance["v4_audits"]["editor_pair"], "Actual new month/editor proof differs from collector")
    test = collector.validate_capture_summary(read_json(engine.safe_asset(gate.root, "summary.json")),
                                              read_json(engine.safe_asset(gate.root, "tests.json")), CAPTURE_TEST)
    need(test == gate.provenance["v4_audits"]["capture_test"], "Actual XCTest node tree disagrees")
    base_receipt = gate.provenance["base_c14_provenance"]
    base_path = engine.safe_asset(gate.root, base_receipt["file"])
    need(sha(base_path.read_bytes()) == base_receipt["sha256"], "Preserved base collector proof bytes drift")
    base = read_json(base_path)
    need(base.get("status") == "PASS" and all(base.get(k) == gate.provenance[k] for k in ("commit", "workflow_run", "run_attempt", "branch", "fixture_manifest_sha256")), "Original base evidence is not from the same new attempt")
    api = verify_workflow_binding(design, gate.root, gate.provenance)
    source_review = design["finalSourceVisualQA"]["sourceReview"]
    path = engine.safe_asset(gate.root, source_review["file"])
    need(sha(path.read_bytes()) == source_review["sha256"], "Actual source visual review report bytes drift")
    review = read_json(path)
    need(review.get("approved") is True and review.get("provenanceSHA256") == gate.provenance_sha256 and
         review.get("commit") == gate.provenance["commit"] and review.get("workflowRun") == gate.provenance["workflow_run"] and
         engine.canonical_run_attempt(review.get("runAttempt"), "source review attempt") == gate.expected_attempt and
         review.get("requirements") == design["finalSourceVisualQA"]["requirements"], "Saved source VQA is not bound to actual new attempt")
    return {"stockLibrary": stock, "legacySceneAudit": scenes, "monthProgress": month, "editorPair": editor,
            "exactAttemptAPI": api, "sourceManifestSHA256": sha(registry_path.read_bytes()), "fixtureAllowlistSHA256": sha(allowlist_path.read_bytes())}


def comparison_geometry(value):
    """Equal true native photo crops, no split slider/buttons or invented adjustment."""
    crop, box = rect(value["photoCrop"], "actual comparison photo crop"), rect(value["targetBox"], "marketing comparison box")
    spec = value["layout"]
    p, gap = spec["padding"], spec["gap"]
    content_top = box[1] + p + spec["disclosureHeight"] + spec["labelHeight"]
    width = (wh(box)[0] - 2 * p - gap) // 2
    need(width > 0 and box[3] - p > content_top, "Comparison has no room for actual photo pixels")
    cells = [[box[0] + p + n * (width + gap), content_top, box[0] + p + n * (width + gap) + width, box[3] - p] for n in range(2)]
    photos = [engine.contained_geometry(wh(crop), cell) for cell in cells]
    need(wh(photos[0][0]) == wh(photos[1][0]), "Comparison photo sizes must be identical")
    labels = [[cell[0], content_top - spec["labelHeight"], cell[2], content_top] for cell in cells]
    disclosure = [box[0] + p, box[1] + p, box[2] - p, box[1] + p + spec["disclosureHeight"]]
    return {"box": list(box), "crop": list(crop), "photoTargets": [list(row[0]) for row in photos],
            "nativeScale": photos[0][1], "labelBoxes": labels, "disclosureBox": disclosure}


def prepare_sources(design, gate, fonts):
    require_calibrated(design, gate.provenance["commit"], gate.provenance["workflow_run"], gate.expected_attempt)
    evidence = verify_new_evidence(design, gate)
    for relative in sorted(CAPTURES | {WORDMARK}):
        gate.load(relative)
    wordmark = gate.load(WORDMARK)
    crop = wordmark.image.getchannel("A").getbbox()
    need(crop is not None, "Empty native Q wordmark")
    target, scale = engine.contained_geometry(wh(crop), design["layout"]["wordmarkBox"])
    x, y = design["layout"]["wordmarkBox"][:2]
    branding = {"source": WORDMARK, "crop": list(crop), "target": [x, y, x + wh(target)[0], y + wh(target)[1]], "nativeScale": scale}
    screen = design["layout"]["device"]["screenBox"]
    geometry = phone_geometry(design)
    sx, sy = wh(screen)[0] / SIZE[0], wh(screen)[1] / SIZE[1]
    prepared = []
    for slot in design["slots"]:
        need(slot["primarySourceSHA256"] == gate.load(slot["primary"]).sha256, "New primary source hash mismatch")
        protected = [[0, 0, 1206, 200]] + slot["primaryProtectedRects"]
        mapped = [[screen[0] + math.floor(r[0] * sx), screen[1] + math.floor(r[1] * sy),
                   screen[0] + math.ceil(r[2] * sx), screen[1] + math.ceil(r[3] * sy)] for r in protected]
        need(all(inside(r, geometry["visibleGeometry"]) for r in mapped), "Bottom clip hides decisive native controls; recapture, never drop their protection")
        insets = []
        for inset in slot["insets"]:
            source = gate.load(inset["source"])
            crop = rect(inset["crop"], "new reviewed inset crop")
            need(crop[1] >= 200 and inset["cropSourceSHA256"] == source.sha256, "Inset source hash/status-area violation")
            need(all(inside(rect(r, "inset evidence rect"), crop) for r in inset["cropEvidenceRects"].values()), "Whole native inset evidence must be continuous and contained")
            native_rect = None
            if slot["id"] == 4:
                native_rect = engine.read_native_rect_evidence(gate.root, inset["nativeRectEvidence"])
                need(native_rect["sha256"] == evidence["legacySceneAudit"]["source_bindings"][native_rect["file"]] and
                     native_rect["nativePixelRect"] == evidence["legacySceneAudit"]["actual_dialog_native_rect"] == inset["cropEvidenceRects"]["system-dialog"] and
                     list(crop) == native_rect["nativePixelRect"], "Dialog focus must use exactly the actual complete native panel, no stale gutters")
            target, scale = engine.inset_geometry(crop, inset)
            need(scale > max(sx, sy), "Detail must actually enlarge relative to the uniform phone, never upscale native pixels")
            if inset["id"] in ("series-decision", "system-dialog"):
                need((target[0], target[2]) == (screen[0], screen[2]), "Full-width native focus must close both inner-screen edges")
            style = engine.inset_style(design, inset["id"])
            effect = target if style["shadowAlpha"] == 0 else expanded(target, style["shadowBlur"] * 3 + 2, style["shadowOffset"])
            effect = [min(target[0], effect[0]), min(target[1], effect[1]), max(target[2], effect[2]), max(target[3], effect[3])]
            visible = [effect[0], effect[1], effect[2], min(effect[3], SIZE[1])]
            need(inside(effect, screen) and inside(target, geometry["visibleGeometry"]) and inside(visible, geometry["visibleGeometry"]) and
                 effect[1] >= screen[1] + DEVICE["screenRadius"] and not any(overlaps(effect, r) for r in mapped), "Inset/shadow covers protected controls/frame")
            insets.append({"id": inset["id"], "source": inset["source"], "crop": list(crop), "target": list(target), "nativeScale": scale,
                           "magnificationRelativeToPhone": scale / sx, "cropEvidenceRects": inset["cropEvidenceRects"], "nativeRectEvidence": native_rect,
                           "requestedBox": inset["targetBox"], "verticalAnchor": inset["verticalAnchor"], "effectBox": effect,
                           "visibleEffectBox": visible, "shadowViewportClip": "bottom-only" if effect[3] > SIZE[1] else "none"})
        result = {"primary": slot["primary"], "protectedSourceRects": protected, "protectedOutputRects": mapped, "insets": insets, "creativeComposite": None}
        if slot["id"] == 9:
            value = slot["editorComparison"]
            need(value["sourceBeforeSHA256"] == gate.load(COMPOSITE_SOURCES[0]).sha256 and value["sourceAfterSHA256"] == gate.load(COMPOSITE_SOURCES[1]).sha256,
                 "Comparison must bind both actual same-asset native screenshots")
            proof_path = engine.safe_asset(gate.root, value["proof"]["file"])
            need(sha(proof_path.read_bytes()) == value["proof"]["sha256"] == evidence["editorPair"]["proof_sha256"], "Actual same-asset/Adjust/Undo/Redo/copy-default proof differs")
            proof = read_json(proof_path)
            native = proof["checkpoints"]["after"]["photoNativeFrame"]
            observed = [native["x"], native["y"], native["x"] + native["width"], native["y"] + native["height"]]
            need(all(type(n) in (int, float) and math.isfinite(n) and int(n) == n for n in observed),
                 "Observed native photo frame must be integral, never silently rounded")
            photo_rect = rect([int(n) for n in observed], "observed native photo frame")
            need(inside(value["photoCrop"], photo_rect), "Creative cutouts must be photo-only pixels inside the observed matched editor stage")
            composite = comparison_geometry(value)
            mapped_photo = [screen[0] + math.ceil(photo_rect[0] * sx), screen[1] + math.ceil(photo_rect[1] * sy),
                            screen[0] + math.floor(photo_rect[2] * sx), screen[1] + math.floor(photo_rect[3] * sy)]
            need(inside(composite["box"], mapped_photo) and inside(composite["box"], geometry["visibleGeometry"]) and
                 not any(overlaps(composite["box"], r) for r in mapped), "Marketing panel must stay inside actual photo, away from frame/status/decisive controls")
            label_spec = {"preferredSize": 46, "minimumSize": 46, "step": 1, "maxLines": 1, "lineGap": 0}
            text_plans = [engine.fit_text(value["disclosure"], composite["disclosureBox"], label_spec, fonts["subtitle"]["path"])]
            text_plans += [engine.fit_text(label, box, label_spec, fonts["subtitle"]["path"]) for label, box in zip(value["labels"], composite["labelBoxes"])]
            result["creativeComposite"] = {**composite, "kind": COMPOSITE_KIND, "disclosure": value["disclosure"], "labels": value["labels"],
                "sourceBindings": [{"file": source, "sha256": gate.load(source).sha256} for source in COMPOSITE_SOURCES],
                "proof": value["proof"], "nativeSideBySideClaim": False, "observedPhotoRect": list(photo_rect),
                "textPlans": [engine.public_text_plan(plan) for plan in text_plans]}
        prepared.append(result)
    return branding, prepared, evidence


def composite_occlusion(prepared):
    mask = Image.new("L", SIZE)
    if prepared and prepared.get("creativeComposite"):
        mask.paste(255, prepared["creativeComposite"]["box"])
    return mask


def verify_native_pixels(canvas, layers, prepared=None):
    """Accepted exact pixel comparator plus explicitly separate marketing occlusion."""
    proofs = []
    for i, layer in enumerate(layers):
        box = layer.description["targetGeometry"]
        eligible = layer.mask.point(lambda v: 255 if (v > 0 if layer.wordmark else v == 255) else 0)
        full_count = eligible.histogram()[255]
        eligible = ImageChops.multiply(eligible, engine.viewport_mask(box))
        viewport_count = eligible.histogram()[255]
        if layer.description["id"] == "full-phone":
            eligible = ImageChops.subtract(eligible, composite_occlusion(prepared).crop(box))
        for above in layers[i + 1:]:
            eligible = ImageChops.subtract(eligible, above.occlusion.crop(box).point(lambda v: 255 if v else 0))
        pixels = eligible.histogram()[255]
        same_dialog = any(above.description["id"] == "system-dialog" and above.description["originalSource"] == layer.description["originalSource"] for above in layers[i + 1:])
        minimum = (0.25 if same_dialog else 0.5) if layer.description["id"] == "full-phone" else 1
        need(pixels > 100 and pixels >= viewport_count * minimum, "Native evidence excessively occluded")
        actual = canvas.crop(box).convert("RGB")
        difference = Image.composite(ImageChops.difference(actual, layer.expected), Image.new("RGB", layer.expected.size), eligible)
        need(difference.getbbox() is None, "Native interior pixels changed: " + layer.description["id"])
        reference = Image.composite(layer.expected, Image.new("RGB", layer.expected.size), eligible)
        output = Image.composite(actual, Image.new("RGB", layer.expected.size), eligible)
        proofs.append({**layer.description, "pixelQA": {"status": "PASS", "comparedPixels": pixels,
            "opaqueInteriorPixels": viewport_count, "fullTargetOpaqueInteriorPixels": full_count,
            "offCanvasOpaqueInteriorPixels": full_count - viewport_count, "occludedByLaterInsetOrShadowPixels": viewport_count - pixels,
            "minimumVisibleViewportFraction": minimum, "maxChannelDifference": 0,
            "maskedKnownResampleSHA256": sha(reference.tobytes()), "maskedOutputSHA256": sha(output.tobytes()),
            "method": "Exact visible native equality; only actual alpha, bottom viewport and declared native/marketing occlusion excluded"}})
    return proofs


def render_one(design, slot, text, prepared, branding, gate, fonts):
    canvas = engine.background(design)
    device = design["layout"]["device"]
    screen = device["screenBox"]
    frame = expanded(screen, device["frameWidth"])
    mask = engine.rounded_mask(wh(frame), device["screenRadius"] + device["frameWidth"])
    engine.shadow(canvas, frame, mask, device)
    canvas.paste(device["frameColor"], frame, mask)
    layers = [engine.native_layer(canvas, gate.load(WORDMARK), branding["crop"], branding["target"], branding["nativeScale"], 0, None, "native-wordmark")]
    for kind in ("headline", "subtitle"):
        engine.draw_text(canvas, text[kind], design["colors"]["ink" if kind == "headline" else "subtitle"])
    for gesture in text["gestures"]:
        engine.draw_arrow(canvas, gesture["arrowBox"], gesture["direction"], design["colors"][gesture["color"]])
        engine.draw_text(canvas, gesture["textPlan"], design["colors"][gesture["color"]])
    layers.append(engine.native_layer(canvas, gate.load(slot["primary"]), [0, 0, *SIZE], screen, wh(screen)[0] / 1206, device["screenRadius"], None, "full-phone"))
    for inset in prepared["insets"]:
        style = engine.inset_style(design, inset["id"])
        layers.append(engine.native_layer(canvas, gate.load(inset["source"]), inset["crop"], inset["target"], inset["nativeScale"], style["radius"], style, inset["id"]))
    composite = prepared["creativeComposite"]
    if composite:
        value = slot["editorComparison"]
        # Marketing background and labels are separately audited, not native UI.
        canvas.paste(value["layout"]["background"], composite["box"])
        for plan in composite["textPlans"]:
            engine.draw_text(canvas, {**plan, "fontPath": fonts["subtitle"]["path"]}, value["layout"]["ink"])
        for source, target, name in zip(COMPOSITE_SOURCES, composite["photoTargets"], ("editor-original-photo", "editor-warm-photo")):
            layers.append(engine.native_layer(canvas, gate.load(source), composite["crop"], target, composite["nativeScale"], 0, None, name))
    verify_native_pixels(canvas, layers, prepared)
    engine.verify_frame_pixels(canvas, design)
    return canvas, layers


def render_all(design, design_path, gate, fonts, texts, branding, prepared, evidence, output):
    require_calibrated(design, gate.provenance["commit"], gate.provenance["workflow_run"], gate.expected_attempt)
    output = Path(output).resolve()
    need(output.is_relative_to(OUTPUT_ROOT.resolve()) and output != OUTPUT_ROOT.resolve(), "Use a fresh child directory under the separate V4 output root")
    need(not output.exists() and not output.is_relative_to(ROOT) and not output.is_relative_to(gate.root) and not gate.root.is_relative_to(output), "Refuse overwrite, source overlap or protected repo writes")
    images, layer_sets = [], []
    for slot, text, plan in zip(design["slots"], texts, prepared):
        image, layers = render_one(design, slot, text, plan, branding, gate, fonts)
        images.append(image)
        layer_sets.append(layers)
    previews = {kind: engine.preview_image(design, images, kind) for kind in ("overview", "search")}
    icc = engine.srgb_profile()
    output.mkdir(parents=True, exist_ok=False)
    records = []
    for slot, image, layers, text, plan in zip(design["slots"], images, layer_sets, texts, prepared):
        record, reopened = engine.write_exclusive_image(output / slot["file"], image, "PNG", icc)
        record.update({"slot": slot["id"], "headline": engine.public_text_plan(text["headline"]), "subtitle": engine.public_text_plan(text["subtitle"]),
            "gestures": [{**g, "textPlan": engine.public_text_plan(g["textPlan"])} for g in text["gestures"]],
            "nativeLayers": verify_native_pixels(reopened, layers, plan), "protectedEvidence": plan,
            "creativeComposite": plan["creativeComposite"], "framePixelQA": engine.verify_frame_pixels(reopened, design),
            "layoutQA": {"status": "PASS", "safeMargin": 70, "headlineMaxLines": 2, "subtitleMaxLines": 2,
                "phoneGeometry": phone_geometry(design), "originalNativeCrop": [0, 0, *SIZE], "phoneProportionalWithinHalfPixel": True,
                "nativeUpscaling": False, "secondDynamicIsland": False, "protectedPrimaryEvidenceUnobscured": True, "allTextBBoxesInsideContainers": True}})
        records.append(record)
    preview_records = []
    for kind, (image, geometry) in previews.items():
        record, _ = engine.write_exclusive_image(output / design["previews"][kind]["file"], image, "JPEG", icc)
        preview_records.append({**record, **geometry, "kind": kind})
    manifest = {"schemaVersion": 2, "moduleVersion": VERSION, "creativeRevision": 4, "layoutRevision": 4, "nativeRevision": 4,
        "runAttempt": gate.expected_attempt, "sampleMediaPolicy": MEDIA_POLICY, "capturePolicy": capture_policy(design),
        "nativeScenePolicy": SCENE_POLICY, "concept": "A", "locale": "en-US", "size": list(SIZE),
        "renderer": {"path": "scripts/store/render_concept_a_v4.py", "sha256": sha(Path(__file__).read_bytes()),
            "baseEnginePath": "scripts/store/render_concept_a.py", "baseEngineSHA256": sha(Path(engine.__file__).read_bytes()),
            "pillowVersion": Image.__version__, "pythonVersion": sys.version.split()[0]},
        "design": {"path": str(Path(design_path).resolve()), "logicalPath": "app-store/concepts/A/v4-design.json", "sha256": sha(Path(design_path).read_bytes())},
        "captureBaselineCommit": BASELINE, "slotMapping": design["slotMapping"],
        "sourceGate": {"status": "PASS", "passedTest": True, "sourceRoot": str(gate.root), "provenanceSHA256": gate.provenance_sha256,
            "provenance": gate.provenance, "expectedRunAttempt": gate.expected_attempt, "evidence": evidence,
            "actualWorkflowConclusion": evidence["exactAttemptAPI"].get("actual_workflow_conclusion", "success"),
            "ownerException": evidence["exactAttemptAPI"].get("owner_exception"),
            "note": "Offline LOCAL data/native observation gate, not workflow success, cryptographic CI attestation or final visual acceptance; any owner exception retains the actual failed workflow"},
        "originalSources": [{"path": s.path, "sha256": s.sha256, "size": list(s.image.size), "mode": s.original_mode,
            "ICC": s.icc, "colorManagement": s.color_management, "provenance": s.provenance} for s in sorted(gate.loaded.values(), key=lambda s: s.path)],
        "sourceVisualQA": design["finalSourceVisualQA"], "fonts": {kind: {k: v for k, v in data.items() if k != "path"} for kind, data in fonts.items()},
        "ICC": {"embedded": True, "colorSpace": "sRGB", "sha256": sha(icc), "description": engine.profile_info(icc)["description"], "reusedFromPriorExport": None},
        "outputs": records, "previews": preview_records,
        "layoutQA": {"status": "PASS", "pngCount": 10, "identicalFullTargetAndVisiblePhoneGeometry": True, "phoneGeometry": phone_geometry(design),
            "requiredInsetSlots": [2, 3, 4], "subtitleCount": 10, "screenBox": DEVICE["screenBox"], "frameBox": list(expanded(DEVICE["screenBox"], 9)),
            "backgroundColors": design["background"], "overviewSlots": list(range(1, 11)), "overviewRows": 1, "searchSlots": [1, 2, 3],
            "editorComparisonSlot": 9, "nativePixelComparison": "PASS", "finalHumanVisualQA": "NOT RUN"},
        "localizationRule": design["localizationRule"]}
    with (output / "render-manifest.json").open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")
    need({p.name for p in output.iterdir()} == {s["file"] for s in design["slots"]} | {"00-overview.jpg", "00-search-preview.jpg", "render-manifest.json"}, "Unexpected V4 output members")
    return {"status": "PASS", "creativeRevision": 4, "output": str(output), "pngCount": 10, "previewCount": 2,
            "actualWorkflowConclusion": evidence["exactAttemptAPI"].get("actual_workflow_conclusion", "success"),
            "ownerException": evidence["exactAttemptAPI"].get("owner_exception"), "humanFinalVisualAcceptance": "NOT RUN"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--design", type=Path, default=DEFAULT_DESIGN)
    parser.add_argument("--check-layout", action="store_true", help="STRUCTURAL ONLY: actual bundled font fit/locked layout, no native render")
    parser.add_argument("--sources", type=Path)
    parser.add_argument("--expected-commit")
    parser.add_argument("--expected-workflow-run")
    parser.add_argument("--expected-run-attempt")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        design = read_json(args.design)
        validate_design(design)
        fonts = engine.font_files(design)
        texts = engine.layout_plan(design, fonts)
        if args.check_layout:
            need(not any((args.sources, args.expected_commit, args.expected_workflow_run, args.expected_run_attempt, args.output)), "Structural layout mode cannot accept render arguments")
            print(json.dumps({"status": "PASS", "scope": "STRUCTURAL ONLY", "moduleVersion": VERSION, "slots": len(texts),
                "copyFit": [{"slot": t["slot"], "headlineFontSize": t["headline"]["fontSize"], "subtitleFontSize": t["subtitle"]["fontSize"],
                             "headlineLines": t["headline"]["lines"], "subtitleLines": t["subtitle"]["lines"]} for t in texts],
                "phoneGeometry": phone_geometry(design), "nativeCapture": "NOT RUN", "sourceVisualQA": "UNAPPROVED" if not design["finalSourceVisualQA"]["approved"] else "requires actual source gate",
                "render": "NOT RUN", "technicalExportAcceptance": "NOT RUN", "finalVisualAcceptance": "NOT RUN"}))
            return 0
        need(all((args.sources, args.expected_commit, args.expected_workflow_run, args.expected_run_attempt, args.output)), "Full render requires explicit new source/commit/run/attempt/output pins")
        require_calibrated(design, args.expected_commit, args.expected_workflow_run, args.expected_run_attempt)
        gate = SourceGate(args.sources, args.expected_commit, args.expected_workflow_run, args.expected_run_attempt)
        branding, prepared, evidence = prepare_sources(design, gate, fonts)
        print(json.dumps(render_all(design, args.design, gate, fonts, texts, branding, prepared, evidence, args.output)))
        return 0
    except (ValueError, OSError, KeyError, TypeError, ImportError) as error:
        print(json.dumps({"status": "FAIL", "moduleVersion": VERSION, "error": f"{type(error).__name__}: {error}", "nativeCapture": "NOT RUN", "finalVisualAcceptance": "NOT RUN"}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
