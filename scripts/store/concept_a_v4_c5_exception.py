#!/usr/bin/env python3
"""Read-only material/recomputation helpers for the ONE authorized C5 exception.

This module does NOT authorize a failed workflow. Renderer and independent auditor
separately enforce the receipt, owner decision and exact failed API step. No call
here runs collect(), writes reports, captures, renders, or grants visual approval.

Parent contract (all hashes are literal SHA-256 of actual bytes):
  captureBinding.workflowException may be absent/null (ordinary green gate), OR
  {"file": "qa/c5-postcapture-workflow-exception.json", "sha256": <receipt hash>}.
The receipt is resolved relative to OUTPUT_ROOT, not the release repository:
  schemaVersion: 1
  kind: "owner-authorized-C5-postcapture-workflow-exception"
  workflowRun: "43949822336", runAttempt: 1
  commit: "90da2494af7dbeffe8c8694ee33f42c4f3ac78f0"
  branch: "hermes/store-concept-a-en", actualWorkflowConclusion: "failure"
  ownerAuthorization: {file: "qa/c5-owner-decision-20261117.json", sha256: OWNER_SHA}
  originalInventory: {file: "qa/c5-original-artifact-immutable-snapshot.json", sha256: INVENTORY_SHA}
  originalProvenanceSHA256: ORIGINAL_SHA
  originalErrors: the exact original three error strings (ORIGINAL_ERRORS)
  exactAttemptReadback: {file: "run-43949822336-readback.json", sha256: READBACK_SHA}
  correctedCollector: {file: "capture_provenance.json", sha256: <actual local report>,
    scope: "C5-retained-native-evidence-and-local-revalidation", fixtureRoot: <actual prepared fixture dir>,
    codeSHA256: current_code_hashes(), auditsSHA256: json_sha256(actual v4_audits),
    sourceHashesSHA256: json_sha256({file: sha256 for actual outputs + branding})}

Do NOT call collect(), run_legacy() or legacy.main() for postcapture validation.
They require the real CI environment, built app and original encoded videos;
reconstructing those inputs would counterfeit native evidence. Instead call
build_postcapture_revalidation_report(DERIVED_ROOT, actual_local_fixture_root).
It returns a deterministic in-memory report; the parent alone may serialize it
into the derived canonical report. Its PASS is LOCAL data validation including
explicitly retained SHA-bound already-PASS native gates, not all gates rerun.
The 35 local JPEGs must equal native bytes and independent derivative pixels.
The local prepared manifest may differ ONLY in both encoded videos' hash/size;
those local MP4s are not the native captured inputs. Native video byte/decode
rechecks and native app/CI metadata recollection remain explicitly NOT RUN.
Preserve the original FAIL report and all 228 raw files. The external receipt
still uses the closed schema above; never rewrite the failed API response,
claim CI is green, or use PASS_WITH_* statuses.

After creating the actual receipt, exercise both read-only full exception gates:
  renderer.verify_workflow_binding(design, DERIVED_ROOT, actual_local_provenance)
  auditor.verify_workflow_binding(design, DERIVED_ROOT, actual_local_provenance)
Set only actual capture pins/hash/report bindings; leave approval flags unchanged.
These functions do not require or grant capture/source/final visual approval.
Every receipt/nested key set above is CLOSED: no additional status/notes/flags.
Normal require_calibrated(), source-review, pixel, final-visual and packaging gates
remain independently closed. Copy the pinned API report bytes into DERIVED_ROOT
as run-43949822336-readback.json; do not reserialize or edit the failed readback.
"""
from __future__ import annotations

import ast
import copy
import hashlib
import inspect
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = Path("F:/HermesOutput/GaleriQ/concept-a-en-v4")
RAW_ROOT = OUTPUT_ROOT / "native-run-43949822336-attempt-1"
DERIVED_ROOT = OUTPUT_ROOT / "revalidated-C5-43949822336-attempt-1/sources"
OWNER_SHA = "dd3f90ce02fed8b611bf3ac7159c06faf63b6ac48ba4cdcf632177836c48a5c5"
INVENTORY_SHA = "88a4a267eb7686cfb7dbf0480da037ce67b0440d06483e0042305be3aa50dde1"
ORIGINAL_SHA = "b916d032f001dc2691c7ec45ac2511827fcec350d24d6c0e4215830af5507d50"
READBACK_SHA = "83d970ee192bf3d5e04bd71308055f38f82ca527db235d5c08da78b2c52f7807"
ORIGINAL_ERRORS = [
    "native_screens: ValueError: Unrelated required native screen states unexpectedly share a file hash",
    "month_progress: ValueError: Proof does not bind an independently inventoried required source",
    "editor_pair: ValueError: Proof does not bind an independently inventoried required source",
]
CODE_PATHS = (
    "scripts/store/collect_concept_a_v4_provenance.py",
    "scripts/store/collect_concept_a_provenance.py",
    "scripts/store/build_concept_a_v4_fixture.py",
    "scripts/store/concept_a_v4_c5_exception.py",
)
LOCAL_GATE_NAMES = frozenset({
    "literal_run_pins", "capture_test", "fixture_manifest", "original_sources",
    "fixture_records", "fixture_files", "captured_fixture_manifest_bytes",
    "native_screens", "actual_library", "sample_media", "month_progress", "editor_pair",
    "exact_attempt_api",
})
# Fields inherited from the real raw/base capture, not newly asserted local data.
NATIVE_HEADER_FIELDS = (
    "fresh_capture", "locale", "app_language", "platform", "base_commit", "commit",
    "workflow_run", "run_attempt", "workflow_url", "branch", "captured_at", "app", "device",
    "capture_summary", "fixture_manifest_sha256", "fixture_visual_source_gate",
    "sample_media_policy", "sample_media_audit", "native_scene_audit", "branding",
)
C5_COMMIT = "90da2494af7dbeffe8c8694ee33f42c4f3ac78f0"
BASE_SHA = "5b3aed84f63ab8e9103609da2b06e7276be3bb8a924d504b91a87b33ae6091f8"
LEGACY_SHA = "85d443c36c18e2018efa12c385a037fe5f2d64265f9ce6ed7be6057775016896"
NATIVE_FIXTURE_SHA = "d9ba50a8299fe7f0ff0abc0066c39fa3f24fabcc68a041d919306fd2a5aa27d4"
INHERITED_GATES = (
    "verify_fixture_files", "_same_manifest_bytes", "validate_fixture_metadata",
    "run_legacy", "collect", "validate_exact_attempt_readback",
)
ORIGINAL_FAILED_GATES = ("native_screens", "month_progress", "editor_pair")
REPORT_KIND = "C5-targeted-postcapture-revalidation"
REVALIDATION_SCOPE = "C5-retained-native-evidence-and-local-revalidation"


def need(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def json_sha256(value):
    """Canonical JSON hash for audit/source maps (not a file-byte hash)."""
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(",", ":"), allow_nan=False).encode("utf-8")).hexdigest()


def current_code_hashes():
    return {name: digest(ROOT / name) for name in CODE_PATHS}


def safe_file(root, name):
    need(type(name) is str and name and "\\" not in name and ":" not in name
         and not any(ord(c) < 32 for c in name), "Unsafe C5 evidence filename")
    relative = PurePosixPath(name)
    need(not relative.is_absolute() and relative.as_posix() == name
         and all(p not in (".", "..") for p in relative.parts), "Noncanonical C5 evidence filename")
    root = Path(root).resolve()
    path = root.joinpath(*relative.parts)
    need(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(root),
         "Missing/out-of-root C5 evidence: " + name)
    return path


def bound_json(root, binding, loader):
    need(type(binding) is dict and set(binding) == {"file", "sha256"}
         and type(binding["sha256"]) is str and re.fullmatch(r"[0-9a-f]{64}", binding["sha256"]),
         "Malformed C5 file/hash binding")
    path = safe_file(root, binding["file"])
    need(digest(path) == binding["sha256"], "C5 bound report bytes changed: " + binding["file"])
    return loader(path)


def verify_immutable_inventory(snapshot, sources):
    """Read every raw/derived input; only derived canonical provenance may differ."""
    sources = Path(sources).resolve()
    need(sources == DERIVED_ROOT.resolve() and sources != RAW_ROOT.resolve()
         and not sources.is_relative_to(ROOT), "C5 requires its exact separate DERIVED source root")
    need(snapshot.get("raw_root") == RAW_ROOT.as_posix()
         and type(snapshot.get("file_count")) is int and snapshot["file_count"] == 228
         and type(snapshot.get("total_bytes")) is int and snapshot["total_bytes"] == 363037134,
         "Wrong original C5 inventory root/count/bytes")
    rows = snapshot.get("files")
    need(type(rows) is dict and len(rows) == 228, "Complete original 228-file C5 inventory required")
    actual = {p.relative_to(RAW_ROOT).as_posix() for p in RAW_ROOT.rglob("*") if p.is_file()}
    need(actual == set(rows), "Immutable original C5 file membership changed")
    size = 0
    for name, row in rows.items():
        need(type(row) is dict and set(row) == {"sha256", "bytes"}
             and type(row["bytes"]) is int and row["bytes"] >= 0
             and type(row["sha256"]) is str and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]),
             "Malformed original C5 inventory entry")
        raw = safe_file(RAW_ROOT, name)
        need(raw.stat().st_size == row["bytes"] and digest(raw) == row["sha256"],
             "Immutable original C5 bytes changed: " + name)
        if name != "capture_provenance.json":
            derived = safe_file(sources, name)
            need(derived.stat().st_size == row["bytes"] and digest(derived) == row["sha256"],
                 "Derived C5 capture input differs from immutable original: " + name)
        size += row["bytes"]
    need(size == snapshot["total_bytes"] and rows["capture_provenance.json"]["sha256"] == ORIGINAL_SHA,
         "C5 original inventory aggregate/provenance mismatch")
    return {"original_files_verified": len(rows), "unchanged_derived_inputs_verified": len(rows) - 1,
            "original_provenance_sha256": ORIGINAL_SHA}


def _equal_json(left, right):
    """JSON equality without bool/int or int/float coercion."""
    return json_sha256(left) == json_sha256(right)


def _function_asts(text):
    return {node.name: ast.dump(node, include_attributes=False) for node in ast.parse(text).body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}


def _verify_inherited_gate_source(current, captured):
    """Compare unchanged ordinary gates, never execute the CI-only functions."""
    current, captured = _function_asts(current), _function_asts(captured)
    for name in INHERITED_GATES:
        need(name in current and name in captured and current[name] == captured[name],
             "Inherited ordinary collector gate changed since native capture: " + name)
    return {name: hashlib.sha256(current[name].encode("utf-8")).hexdigest() for name in INHERITED_GATES}


def verify_inherited_gate_code():
    import collect_concept_a_v4_provenance as collector

    path = ROOT / "scripts/store/collect_concept_a_v4_provenance.py"
    need(Path(collector.__file__).resolve() == path.resolve(), "Wrong imported native collector module")
    captured = subprocess.run(["git", "-C", str(ROOT), "show", C5_COMMIT + ":scripts/store/collect_concept_a_v4_provenance.py"],
                              check=True, capture_output=True, timeout=30).stdout.decode("utf-8")
    current = path.read_text(encoding="utf-8")
    ast_hashes = _verify_inherited_gate_source(current, captured)
    nodes = _function_asts(current)
    for name in INHERITED_GATES:
        function = getattr(collector, name)
        need(Path(inspect.getsourcefile(function) or "").resolve() == path.resolve()
             and _function_asts(inspect.getsource(function)).get(name) == nodes[name],
             "Loaded inherited collector function differs from its source: " + name)
    legacy = ROOT / "scripts/store/collect_concept_a_provenance.py"
    need(Path(collector.legacy.__file__).resolve() == legacy.resolve() and digest(legacy) == LEGACY_SHA,
         "Legacy native collector bytes changed since actual CI PASS")
    return {"capture_commit": C5_COMMIT, "inherited_function_ast_sha256": ast_hashes,
            "legacy_collector_sha256": LEGACY_SHA}


def _json_differences(native, local, pointer=""):
    """Exact, typed JSON-pointer differences, including added/missing keys."""
    if type(native) is not type(local):
        return [{"path": pointer, "native": native, "local": local}]
    if type(native) is dict and set(native) == set(local):
        return [row for key in sorted(native) for row in
                _json_differences(native[key], local[key], pointer + "/" + key.replace("~", "~0").replace("/", "~1"))]
    if type(native) is list and len(native) == len(local):
        return [row for index, (a, b) in enumerate(zip(native, local)) for row in
                _json_differences(a, b, pointer + "/" + str(index))]
    return [] if _equal_json(native, local) else [{"path": pointer, "native": native, "local": local}]


def _validate_prepared_manifest(native, local):
    differences = _json_differences(native, local)
    expected = {f"/records/{index}/{key}" for index in (35, 36) for key in ("bytes", "sha256")}
    need({row["path"] for row in differences} == expected and len(differences) == 4,
         "Local prepared manifest must differ ONLY in the two encoded MP4 hash/size fields")
    for index, name in ((35, "CA_40_large_01.mp4"), (36, "CA_40_large_02.mp4")):
        row = local["records"][index]
        need(row["file"] == name and row["media_type"] == "video" and type(row["bytes"]) is int
             and row["bytes"] > 110_000_000 and type(row["sha256"]) is str
             and re.fullmatch(r"[0-9a-f]{64}", row["sha256"]), "Malformed available local encoded-video measurement")
    return differences


def _jpeg_pixels(image):
    """Reproduce derivative JPEG pixels in memory; never change fixture files."""
    from PIL import Image, ImageFile
    import build_concept_a_v4_fixture as builder

    with builder.JPEG_SAVE_LOCK:
        previous = ImageFile.MAXBLOCK
        try:
            ImageFile.MAXBLOCK = max(previous, image.width * image.height * 4)
            buffer = io.BytesIO()
            image.save(buffer, "JPEG", quality=94, subsampling=0, optimize=True)
        finally:
            ImageFile.MAXBLOCK = previous
    buffer.seek(0)
    with Image.open(buffer) as decoded:
        decoded.load()
        return decoded.convert("RGB")


def _expected_image_pixels(row, registry_root):
    """Independent input-photo recipe/crop check, not screenshot modification."""
    from PIL import Image, ImageEnhance, ImageFilter, ImageOps

    with Image.open(safe_file(registry_root, row["source"])) as source:
        source.load()
        if row["category"] in ("pretty", "exact-duplicate"):
            need(row["sha256"] == row["source_sha256"], row["file"] + ": unchanged original bytes required")
            return source.convert("RGB")
        image = ImageOps.exif_transpose(source).convert("RGB")
    name = row["file"]
    if name == "CA_01_clutter_blur.jpg":
        image = image.filter(ImageFilter.GaussianBlur(26))
    elif name == "CA_02_clutter_shake.jpg":
        image = image.filter(ImageFilter.GaussianBlur(18))
    elif name == "CA_03_clutter_dark.jpg":
        image = ImageEnhance.Brightness(image).enhance(0.25)
    elif name.startswith("CA_20_series_"):
        index = int(name.removeprefix("CA_20_series_").removesuffix(".jpg")) - 1
        inset = index * 5
        image = ImageEnhance.Brightness(image.crop((inset, inset, image.width - inset, image.height - inset))).enhance(0.98 + index * 0.008)
    elif name.startswith("CA_30_pretty_"):
        number = int(name.removeprefix("CA_30_pretty_").removesuffix(".jpg"))
        if 1 <= number <= 4:
            unit = min(image.width // 4, image.height // 5)
            w, h = 4 * unit, 5 * unit
            x, y = (image.width - w) // 2, (image.height - h) // 2
            crop = [x, y, x + w, y + h]
            need(crop == row.get("source_crop"), name + ": independent original-photo crop mismatch")
            image = image.crop(crop)
        else:
            need(15 <= number <= 24, name + ": unsupported derivative recipe")
            offset = number - 15
            inset = 48 + offset * 7
            image = ImageEnhance.Brightness(image.crop((inset, inset, image.width - inset, image.height - inset))).enhance(1.04 + offset * 0.005)
    else:
        raise ValueError("Unsupported native fixture image recipe: " + name)
    return _jpeg_pixels(image)


def _verify_available_images(fixture_root, rows, registry_root):
    from PIL import Image, ImageOps

    result = {}
    for name, row in rows.items():
        if row["media_type"] != "image":
            continue
        path = safe_file(fixture_root, name)
        sha = digest(path)
        need(path.resolve().parent == fixture_root and path.stat().st_size == row["bytes"] and sha == row["sha256"],
             name + ": available JPEG differs from exact native fixture bytes")
        with Image.open(path) as image, Image.open(registry_root / row["source"]) as original:
            image.load()
            oriented = ImageOps.exif_transpose(original)
            need(image.format == "JPEG" and list(image.size) == row["size"]
                 and image.width <= oriented.width and image.height <= oriented.height,
                 name + ": native JPEG dimensions/format/upscaling mismatch")
            rgb = image.convert("RGB")
        expected = _expected_image_pixels(row, registry_root)
        pixels = rgb.tobytes()
        need(rgb.size == expected.size and pixels == expected.tobytes(),
             name + ": independent original-photo recipe/crop pixel mismatch")
        result[name] = {"sha256": sha, "bytes": path.stat().st_size, "size": list(rgb.size),
                        "decoded_rgb_sha256": hashlib.sha256(pixels).hexdigest(),
                        "original_photo_recipe_pixels_equal": True, "source_crop": row.get("source_crop")}
    need(len(result) == 35, "Exactly 35 actual JPEG byte/decode/recipe checks required")
    return {"status": "PASS", "actual_files": len(result), "native_bytes_exact": True,
            "independent_original_photo_pixels_exact": True, "files": result}


def _verify_local_prepared_files(fixture_root, native, local):
    need(fixture_root.is_dir() and not fixture_root.is_relative_to(ROOT)
         and not fixture_root.is_relative_to(RAW_ROOT.resolve()) and not fixture_root.is_relative_to(DERIVED_ROOT.resolve()),
         "Actual available fixture must be separate from source/repository/raw roots")
    need({p.name for p in fixture_root.iterdir()} == {r["file"] for r in native["records"]} | {"fixture-manifest.json"},
         "Available fixture must contain exactly 37 files plus its prepared manifest")
    differences = _validate_prepared_manifest(native, local)
    video_files = {}
    for row in local["records"]:
        if row["media_type"] != "video":
            continue
        path = safe_file(fixture_root, row["file"])
        sha = digest(path)
        need(path.resolve().parent == fixture_root and path.stat().st_size == row["bytes"] and sha == row["sha256"],
             "Available local MP4 hash/size disagrees with its LOCAL manifest: " + row["file"])
        video_files[row["file"]] = {"sha256": sha, "bytes": path.stat().st_size}
    return differences, {"status": "PASS", "scope": "local prepared file hash/size only; NOT captured native MP4s",
                          "native_capture_byte_identity": False, "full_decode_recheck": "NOT RUN", "files": video_files}


def _load_pinned_original(sources):
    import build_concept_a_v4_fixture as builder

    bound_json(OUTPUT_ROOT, {"file": "qa/c5-owner-decision-20261117.json", "sha256": OWNER_SHA}, builder.load_json)
    snapshot = bound_json(OUTPUT_ROOT, {"file": "qa/c5-original-artifact-immutable-snapshot.json", "sha256": INVENTORY_SHA}, builder.load_json)
    inventory = verify_immutable_inventory(snapshot, sources)
    original = bound_json(RAW_ROOT, {"file": "capture_provenance.json", "sha256": ORIGINAL_SHA}, builder.load_json)
    need(original.get("status") == "FAIL" and original.get("errors") == ORIGINAL_ERRORS
         and original.get("commit") == C5_COMMIT and original.get("workflow_run") == "43949822336"
         and original.get("run_attempt") == "1" and type(original.get("run_attempt")) is str,
         "Only the exact original C5 FAIL with the three expected errors may be revalidated")
    need(set(original["v4_audits"]) == LOCAL_GATE_NAMES, "Incomplete original C5 gate inventory")
    for name, error in zip(ORIGINAL_FAILED_GATES, ORIGINAL_ERRORS):
        need(original["v4_audits"][name] == {"status": "FAIL", "errors": [error]}, "Original C5 failed gate scope changed")
    return original, inventory


def _verify_native_base(sources, original, collector):
    import build_concept_a_v4_fixture as builder

    receipt = original["base_c14_provenance"]
    need(receipt == {"status": "PASS", "exit_code": 0, "file": "capture_provenance.base-c14-" + BASE_SHA + ".json",
                     "sha256": BASE_SHA, "collector_sha256": LEGACY_SHA, "previous_canonical": None}
         and type(receipt["exit_code"]) is int, "Exact original already-PASS native base receipt required")
    base = bound_json(sources, {"file": receipt["file"], "sha256": BASE_SHA}, builder.load_json)
    need(base.get("status") == "PASS" and base.get("errors") == [] and type(base.get("schema_version")) is int
         and base["schema_version"] == 1 and all(_equal_json(base.get(k), original.get(k)) for k in NATIVE_HEADER_FIELDS)
         and base["native_scene_policy"] == original["base_c14_native_scene_policy"] == collector.legacy.V3_SCENE_POLICY,
         "Immutable native base metadata/headers are not the original already-PASS evidence")
    need(_equal_json(builder.load_json(safe_file(sources, "device.json")), base["device"])
         and _equal_json(builder.load_json(safe_file(sources, "summary.json")), base["capture_summary"]),
         "Actual native device/summary metadata differs from preserved base PASS")
    actual_outputs = [collector.legacy.image_record(path, sources) for path in sorted((sources / "screenshots").glob("*.png"))
                      if path.name != "concept-a-logo.png"]
    need(_equal_json(actual_outputs, base["outputs"]) and _equal_json(base["outputs"], original["outputs"]),
         "Actual native PNG byte/header inventory differs from preserved base PASS")
    branding = collector.legacy.image_record(safe_file(sources, base["branding"]["file"]), sources)
    need(_equal_json(branding, base["branding"]), "Actual native wordmark metadata/bytes differ from base PASS")
    for name in ("native_visual_acceptance", "store_export_acceptance", "real_device_or_security_acceptance"):
        need(base.get(name) == original.get(name) == "NOT RUN", "Retained base must not grant visual/export/security approval")
    return base


def _revalidate_materials(sources, fixture_root):
    """Re-read actual local data and hash-bound native PASS gates without writes."""
    import collect_concept_a_v4_provenance as collector
    import build_concept_a_v4_fixture as builder

    sources, fixture_root = Path(sources).resolve(), Path(fixture_root).resolve()
    need(sources == DERIVED_ROOT.resolve() and sources != RAW_ROOT.resolve(), "Never revalidate in raw C5 root")
    code = verify_inherited_gate_code()
    original, inventory = _load_pinned_original(sources)
    base = _verify_native_base(sources, original, collector)
    registry_root = ROOT / "app-store/concepts/A/v4-source-media"
    allowlist = ROOT / "app-store/concepts/A/qa/v4-fixture-source-allowlist.json"
    fixture = builder.load_json(safe_file(sources, "fixture-manifest.json"))
    native_manifest_sha = digest(sources / "fixture-manifest.json")
    need(native_manifest_sha == original["fixture_manifest_sha256"] == NATIVE_FIXTURE_SHA
         and _equal_json(fixture, original["v4_audits"]["fixture_manifest"])
         and _equal_json(fixture["visual_source_gate"], base["fixture_visual_source_gate"]),
         "Original native fixture manifest/visual gate bytes changed")
    roles, registry_sha, allowlist_sha = builder.load_sources(registry_root, allowlist)
    records = collector.validate_fixture_metadata(fixture, builder.load_json(registry_root / "manifest.json"),
                                                  builder.load_json(allowlist), registry_sha, allowlist_sha)
    local_path = safe_file(fixture_root, "fixture-manifest.json")
    local_manifest_sha = digest(local_path)
    local_fixture = builder.load_json(local_path)
    differences, local_videos = _verify_local_prepared_files(fixture_root, fixture, local_fixture)
    collector.validate_fixture_metadata(local_fixture, builder.load_json(registry_root / "manifest.json"),
                                        builder.load_json(allowlist), registry_sha, allowlist_sha)
    images = _verify_available_images(fixture_root, records, registry_root)
    originals = {row["file"]: {"sha256": digest(safe_file(registry_root, row["file"])),
                               "bytes": (registry_root / row["file"]).stat().st_size,
                               "size": [row["width"], row["height"]], "license": row["license"]}
                 for row in roles.values()}
    need(len(originals) == 15 and all(originals[row["file"]]["sha256"] == row["sha256"] for row in roles.values()),
         "Actual licensed originals changed during local image validation")
    native_fixture_files = original["v4_audits"]["fixture_files"]
    native_manifest_check = original["v4_audits"]["captured_fixture_manifest_bytes"]
    need(_equal_json(native_fixture_files, {"status": "PASS", "actual_files": 37, "images": 35, "videos": 2,
                                          "independent_video_full_decode": "PASS"})
         and native_manifest_check == {"status": "PASS", "sha256": NATIVE_FIXTURE_SHA},
         "Only exact already-PASS native fixture-byte/full-decode/manifest gates may be retained")
    screens = collector.validate_native_screens(sources)
    library = builder.load_json(safe_file(sources, "concept-a-library.json"))
    sample = collector.legacy.audit_sample_media(library, fixture)
    need(sample["status"] == "PASS", "Actual native PhotoKit sample media audit failed")
    collector.library_by_id(library)
    need(_equal_json({**sample, "actual_library_sha256": digest(sources / "concept-a-library.json")}, base["sample_media_audit"]),
         "Native initial PhotoKit inventory differs from preserved base evidence")
    audits = {
        "literal_run_pins": {"status": "PASS", **collector.validate_run_pins(original)},
        "capture_test": collector.validate_capture_summary(builder.load_json(safe_file(sources, "summary.json")),
                            builder.load_json(safe_file(sources, "tests.json")), collector.DEFAULT_CAPTURE_TEST),
        "fixture_manifest": fixture,
        "original_sources": {"status": "PASS", "verified_originals": len(roles),
                             "source_manifest_sha256": registry_sha, "allowlist_sha256": allowlist_sha},
        "fixture_records": {"status": "PASS", "actual_records": len(records), "filename_set_exact": True, "all_source_fields_bound": True},
        # These results are retained, NOT fabricated local video/manifest PASS.
        # Their exact original source and local NOT RUN scope are mandatory below.
        "fixture_files": copy.deepcopy(native_fixture_files),
        "captured_fixture_manifest_bytes": copy.deepcopy(native_manifest_check),
        "native_screens": {"status": "PASS", "required_count": len(screens), "outputs": list(screens.values())},
        "actual_library": library,
        "sample_media": sample,
        "month_progress": collector.audit_month_progress(sources, screens, library),
        "editor_pair": collector.audit_editor_pair(sources, screens, library),
        "exact_attempt_api": {"status": "NOT RUN", "reason": "Exact-attempt API completion/jobs readback is a separate post-run gate; no API success is inferred"},
    }
    need(set(audits) == LOCAL_GATE_NAMES, "Incomplete local/retained gate set")
    for name in LOCAL_GATE_NAMES - set(ORIGINAL_FAILED_GATES):
        need(_equal_json(audits[name], original["v4_audits"][name]), "Previously passed native gate changed: " + name)
    scene = collector.legacy.audit_v3_scenes(sources, fixture)
    need(scene.get("status") == "PASS" and _equal_json(scene, original["native_scene_audit"]), "Actual retained native scene audit failed")
    need(digest(local_path) == local_manifest_sha, "Local prepared manifest changed during revalidation")
    raw_report_binding = {"file": RAW_ROOT.relative_to(OUTPUT_ROOT).as_posix() + "/capture_provenance.json", "sha256": ORIGINAL_SHA}
    base_binding = {"file": RAW_ROOT.relative_to(OUTPUT_ROOT).as_posix() + "/" + original["base_c14_provenance"]["file"], "sha256": BASE_SHA}
    evidence = {
        "schema_version": 1, "kind": "C5-only-immutable-PASS-native-gate-retention",
        "scope": REVALIDATION_SCOPE, "fresh_native_collection": False,
        "scope_definition": "Available-data checks plus SHA-bound retained native PASS gates; not a rerun of all native gates",
        "recomputed_local_gates": sorted(LOCAL_GATE_NAMES - {"fixture_files", "captured_fixture_manifest_bytes", "exact_attempt_api"}),
        "native_timestamps_retained": {k: original[k] for k in ("captured_at", "collected_at")},
        "actual_workflow_conclusion": "failure", "workflow_success": False,
        "original_provenance_sha256": ORIGINAL_SHA, "original_provenance": raw_report_binding,
        "original_errors": copy.deepcopy(ORIGINAL_ERRORS), "immutable_inventory": inventory,
        "owner_authorization_sha256": OWNER_SHA, "inherited_gate_code": code,
        "native_header_fields_preserved": list(NATIVE_HEADER_FIELDS),
        "native_header_sha256": json_sha256({k: original[k] for k in NATIVE_HEADER_FIELDS}),
        "fixture_root": fixture_root.as_posix(), "captured_fixture_manifest_sha256": native_manifest_sha,
        "local_prepared_fixture_manifest_sha256": local_manifest_sha,
        "local_prepared_manifest_differences": differences,
        "retained_native_gates": {
            "base_c14_provenance": {"source": base_binding, "result": copy.deepcopy(original["base_c14_provenance"]), "local_rerun": "NOT RUN"},
            "fixture_files": {"source": raw_report_binding, "result": copy.deepcopy(native_fixture_files), "local_rerun": "NOT RUN"},
            "captured_fixture_manifest_bytes": {"source": raw_report_binding, "result": copy.deepcopy(native_manifest_check), "local_rerun": "NOT RUN"},
        },
        "local_35_image_bytechecks": images,
        "local_15_original_checks": {"status": "PASS", "actual_originals": len(originals), "full_decode": "PASS", "files": originals},
        "local_prepared_video_file_checks": local_videos,
        "local_videos_match_native_capture": False,
        "native_encoded_video_byte_recheck": "NOT RUN", "native_encoded_video_full_decode_recheck": "NOT RUN",
        "native_app_plist_recheck": "NOT RUN", "native_ci_metadata_recollection": "NOT RUN",
        "source_or_final_visual_approval_granted": False,
    }
    report = {**copy.deepcopy(original), "report_kind": REPORT_KIND, "status": "PASS", "errors": [], "v4_audits": audits,
              "outputs": list(screens.values()), "exact_api_run_acceptance": "NOT RUN", "postcapture_revalidation": evidence}
    hashes = {name: row["sha256"] for name, row in screens.items()}
    branding = original["branding"]
    need(branding["file"] not in hashes and digest(safe_file(sources, branding["file"])) == branding["sha256"],
         "Actual native branding byte hash mismatch")
    hashes[branding["file"]] = branding["sha256"]
    return report, {"auditsSHA256": json_sha256(audits), "sourceHashesSHA256": json_sha256(hashes),
                    "codeSHA256": current_code_hashes(), "localDataStatus": "PASS", "apiGreenStatus": "NOT RUN"}


def build_postcapture_revalidation_report(sources, fixture_root):
    """Return an actual C5-only local/retained report IN MEMORY; never write it.

    sources must be DERIVED_ROOT. fixture_root is the actual available prepared
    local fixture (35 native-identical JPEGs and 2 non-native local MP4s). Native
    header/app metadata and already-PASS video/manifest gates remain bound to
    their original immutable native reports. No CI metadata, plist, native video
    bytes, counters, captures or successful workflow are manufactured.
    """
    return _revalidate_materials(sources, fixture_root)[0]


def recompute_local_data(sources, fixture_root, provenance, original):
    """Independently re-read/recompute actual data AND exact retention evidence.

    The closed existing receipt schema remains compatible. Its scope includes
    the explicitly disclosed SHA-bound retained native PASS evidence, not an
    assertion that missing native video bytes/CI-only metadata were rerun here.
    """
    import build_concept_a_v4_fixture as builder

    need(type(provenance) is dict and provenance.get("status") == "PASS" and provenance.get("errors") == []
         and type(provenance.get("schema_version")) is int and provenance["schema_version"] == 2
         and type(provenance.get("creative_revision")) is int and provenance["creative_revision"] == 4,
         "Actual corrected LOCAL collector must PASS before the C5 exception")
    pinned_original = bound_json(RAW_ROOT, {"file": "capture_provenance.json", "sha256": ORIGINAL_SHA}, builder.load_json)
    need(type(original) is dict and _equal_json(original, pinned_original), "Supplied original differs from exact immutable native C5 report")
    need(all(k in provenance and _equal_json(provenance[k], pinned_original[k]) for k in NATIVE_HEADER_FIELDS),
         "Corrected local report changed immutable native header/branding evidence")
    need(provenance.get("report_kind") == REPORT_KIND and type(provenance.get("postcapture_revalidation")) is dict
         and provenance["postcapture_revalidation"].get("scope") == REVALIDATION_SCOPE,
         "Explicit targeted C5 postcapture retained-native-proof mode/scope is required; no silent legacy fallback")
    expected, result = _revalidate_materials(sources, fixture_root)
    need(_equal_json(provenance, expected),
         "Corrected local report/gates/retention evidence differs from actual read-only recomputation")
    return result

