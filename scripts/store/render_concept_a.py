#!/usr/bin/env python3
"""Concept A / en-US only. Native evidence in, unretouched Pillow composites out.

No discovery, legacy fallback, simulated UI, downloads, automatic deletion or overwrite.
Run --help, --print-provenance-schema, --check-layout or --self-test without captures.
Only a full, independently pinned SourceGate PASS can reach the render/export path.
"""
from __future__ import annotations

import argparse
import copy
import functools
import hashlib
import io
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from PIL import Image, ImageChops, ImageCms, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DESIGN = ROOT / "app-store/concepts/A/design.json"
SIZE = (1206, 2622)
RESAMPLE = Image.Resampling.LANCZOS
COPY = (
    ("Swipe the clutter. Keep the memories.", "Keep, trash or decide later.", "swipe"),
    ("Spot large files. Find duplicates.", "Find extra copies and space-hungry files.", "large-files"),
    ("Nothing deletes without you.", "Review first. You make the final call.", "delete-confirm"),
    ("Private photos. Locked away.", "Encrypted vault, protected by your own code and Face ID.", "vault"),
    ("Unsure? Choose later.", "Swipe right. Come back to it later.", "later"),
    ("One month. A fresh start.", "Sort your library, one month at a time.", "months"),
    ("Blurry or similar? Take a closer look.", "Compare your shots. Choose what stays.", "analysis"),
    ("Make a collage. Keep the moment.", "Bring your favorite moments together.", "collage"),
    ("A new look. Your own photo.", "Add a new look to a photo you love.", "editor"),
    ("A small break. Your photos play.", "Free with ads. GaleriQ Pro: one purchase, no subscription.", "games"),
)
WORDMARK = "branding/native-wordmark.png"
CAPTURES = {f"screenshots/concept-a-{s}.png" for s in
            ("swipe", "duplicates", "large-files", "trash", "delete-confirm", "vault",
             "vault-locked", "later", "later-swipe", "months", "analysis", "collage", "editor", "games")}
SHA = re.compile(r"[0-9a-f]{64}\Z")
COMMIT = re.compile(r"[0-9a-f]{40}\Z")
RUN = re.compile(r"[1-9][0-9]*\Z")
BASE_COMMIT = "583eb804a81401aa2010996875b35d05afc61539"
RUN_URL = re.compile(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/([1-9][0-9]*)(?:/attempts/([1-9][0-9]*))?\Z")
V2_SCREEN = (201, 760, 1005, 2508)  # Actual v2 export, not an assumed device size.
INSETS = {2: ("duplicate-results", "duplicates", {"duplicate-pair", "selection-labels"}),
          3: ("system-dialog", "delete-confirm", {"system-dialog"}),
          7: ("series-decision", "analysis", {"series", "keep5-trash1"})}
V3_REVIEW = {"stockOnlyEveryMediaTile", "sharpRecognizableFirstPhoto", "opaqueSystemDialogNoUnderlyingHome",
             "noLoadingSpinner", "heldRightwardLater", "filledNativePairsBoard", "nativeKeep5Trash1", "completeDuplicatePair"}
V3_SCENE_POLICY = "sharp-stock-hero-opaque-confirmation-filled-photo-game"


class GateError(ValueError):
    """An explicit, non-recoverable source/layout/export gate failure."""


def need(condition: Any, message: str) -> None:
    if not condition:
        raise GateError(message)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs: list[tuple[str, Any]]) -> dict:
    out: dict = {}
    for key, value in pairs:
        need(key not in out, f"Duplicate JSON key: {key}")
        out[key] = value
    return out


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise GateError(f"Cannot read JSON {path}: {exc}") from exc
    need(isinstance(value, dict), f"Expected a JSON object: {path}")
    return value


def keys(value: Any, required: set[str], optional: set[str] | None = None, label: str = "object") -> None:
    need(isinstance(value, dict), f"{label}: expected object")
    need(required <= value.keys(), f"{label}: missing {sorted(required - value.keys())}")
    extra = value.keys() - required - (optional or set())
    need(not extra, f"{label}: unknown fields {sorted(extra)}")


def integer(value: Any, label: str, minimum: int = 0) -> int:
    need(type(value) is int and value >= minimum, f"{label}: integer >= {minimum} required")
    return value


def canonical_run_attempt(value: Any, label: str) -> int:
    # GITHUB_RUN_ATTEMPT is a string; API readbacks use integers. No coercive repair.
    need((type(value) is int and value > 0) or
         (type(value) is str and RUN.fullmatch(value) is not None),
         f"{label}: canonical positive run attempt required (integer or numeric string)")
    return int(value)


def rect(value: Any, label: str, bounds: tuple[int, int] = SIZE) -> tuple[int, int, int, int]:
    need(isinstance(value, (list, tuple)) and len(value) == 4, f"{label}: explicit [left,top,right,bottom] required")
    need(all(type(x) is int for x in value), f"{label}: only integer source/output pixels are allowed")
    x0, y0, x1, y1 = value
    need(0 <= x0 < x1 <= bounds[0] and 0 <= y0 < y1 <= bounds[1], f"{label}: outside {bounds}: {value}")
    return x0, y0, x1, y1


def wh(box: tuple | list) -> tuple[int, int]:
    return box[2] - box[0], box[3] - box[1]


def overlaps(a: tuple | list, b: tuple | list) -> bool:
    return max(a[0], b[0]) < min(a[2], b[2]) and max(a[1], b[1]) < min(a[3], b[3])


def inside(a: tuple | list, b: tuple | list) -> bool:
    return b[0] <= a[0] < a[2] <= b[2] and b[1] <= a[1] < a[3] <= b[3]


def expanded(box: tuple | list, pixels: int, offset: tuple | list = (0, 0)) -> tuple[int, int, int, int]:
    return (box[0] - pixels + offset[0], box[1] - pixels + offset[1],
            box[2] + pixels + offset[0], box[3] + pixels + offset[1])


def contained_geometry(source_size: tuple[int, int], target: tuple | list) -> tuple[tuple[int, int, int, int], float]:
    """Contain, never fit/stretch/upscale. Nearest integer sizes cost <= 0.5 px/axis."""
    scale = min(1.0, wh(target)[0] / source_size[0], wh(target)[1] / source_size[1])
    w, h = (max(1, int(math.floor(n * scale + 0.5))) for n in source_size)
    need(w <= source_size[0] and h <= source_size[1], "Native upscaling is forbidden")
    need(w <= wh(target)[0] and h <= wh(target)[1], "Contain rounding exceeded target")
    x, y = target[0] + (wh(target)[0] - w) // 2, target[1] + (wh(target)[1] - h) // 2
    return (x, y, x + w, y + h), scale


def viewport_geometry(box: tuple | list, crop: tuple | list) -> dict:
    """Full resample target is never confused with its canvas intersection."""
    visible = (max(0, box[0]), max(0, box[1]), min(SIZE[0], box[2]), min(SIZE[1], box[3]))
    need(visible[0] < visible[2] and visible[1] < visible[3], "Native layer misses the viewport")
    local = (visible[0] - box[0], visible[1] - box[1], visible[2] - box[0], visible[3] - box[1])
    return {"visibleGeometry": list(visible), "visibleLocalRect": list(local),
            "visibleSourceBounds": [crop[0] + local[0] * wh(crop)[0] / wh(box)[0],
                                    crop[1] + local[1] * wh(crop)[1] / wh(box)[1],
                                    crop[0] + local[2] * wh(crop)[0] / wh(box)[0],
                                    crop[1] + local[3] * wh(crop)[1] / wh(box)[1]],
            "viewportClipPixels": {"left": local[0], "top": local[1],
                                   "right": wh(box)[0] - local[2], "bottom": wh(box)[1] - local[3]}}


def inset_geometry(crop: tuple | list, inset: dict) -> tuple[tuple[int, int, int, int], float]:
    target, scale = contained_geometry(wh(crop), inset["targetBox"])
    if inset["verticalAnchor"] == "bottom":
        target = (target[0], inset["targetBox"][3] - wh(target)[1], target[2], inset["targetBox"][3])
    return target, scale


def viewport_mask(box: tuple | list) -> Image.Image:
    geometry = viewport_geometry(box, (0, 0, *wh(box)))
    mask = Image.new("L", wh(box), 0)
    local = geometry["visibleLocalRect"]
    mask.paste(255, local)
    return mask


def phone_geometry(design: dict) -> dict:
    device = design["layout"]["device"]
    screen = device["screenBox"]
    need(isinstance(screen, list) and len(screen) == 4 and all(type(n) is int for n in screen), "Explicit full target screen box required")
    w, h = wh(screen)
    scale = w / SIZE[0]
    need(0 < scale <= 1 and abs(h - SIZE[1] * scale) <= 0.5, "Phone must use known proportional resampling, <=0.5 px rounding, no upscale")
    frame = expanded(screen, integer(device["frameWidth"], "frameWidth", 1))
    need(70 <= frame[0] < frame[2] <= SIZE[0] - 70 and 70 <= frame[1] < SIZE[1] < screen[3],
         "v3 requires visible top/left/right frame, with intentional bottom-only screen clipping")
    ratios = [w / wh(V2_SCREEN)[0], h / wh(V2_SCREEN)[1]]
    need(all(1.15 <= ratio <= 1.20 for ratio in ratios), "v3 phone must be 15-20% larger than the actual v2 export")
    need(device.get("viewportClip") == "bottom-only" and device.get("v2ReferenceScreenBox") == list(V2_SCREEN), "Explicit v3 clipping and actual v2 reference required")
    return {"fullTargetGeometry": list(screen), **viewport_geometry(screen, (0, 0, *SIZE)),
            "fullFrameGeometry": list(frame), "visibleFrameGeometry": viewport_geometry(frame, (0, 0, *wh(frame)))["visibleGeometry"],
            "nativeScale": scale, "sizeRelativeToV2XY": ratios,
            "resampleRoundingXY": [0, h - SIZE[1] * scale], "clipping": "bottom-only", "completePhoneVisible": False}


def safe_asset(root: Path, relative: str) -> Path:
    need(isinstance(relative, str) and "\\" not in relative, "Asset paths must use canonical relative forward slashes")
    rel = PurePosixPath(relative)
    need(not rel.is_absolute() and ".." not in rel.parts and str(rel) == relative, f"Unsafe path: {relative}")
    path = root.joinpath(*rel.parts)
    need(path.is_file() and not path.is_symlink(), f"Missing/non-regular native source: {path}")
    need(path.resolve().is_relative_to(root.resolve()), f"Source escapes artifact root: {path}")
    return path


def provenance_schema() -> dict:
    """Parent-owned wire format. Extra actual CI/device metadata is retained, not rejected."""
    screenshot = {"type": "object", "required": ["file", "sha256", "width", "height", "mode", "opaque"],
                  "properties": {"file": {"type": "string"}, "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
                                 "width": {"const": 1206}, "height": {"const": 2622},
                                 "mode": {"enum": ["RGB", "RGBA"]}, "opaque": {"const": True}}}
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "title": "Parent Concept A capture_provenance.json v1",
            "type": "object", "required": ["schema_version", "status", "fresh_capture", "locale", "app_language", "base_commit", "commit",
                                              "workflow_run", "run_attempt", "workflow_url", "capture_summary", "device", "outputs", "branding"],
            "properties": {"schema_version": {"const": 1}, "status": {"const": "PASS"}, "fresh_capture": {"const": True},
                           "locale": {"const": "en-US"}, "app_language": {"const": "en"}, "base_commit": {"const": BASE_COMMIT},
                           "commit": {"type": "string", "pattern": "^[0-9a-f]{40}$"},
                           "workflow_run": {"type": "string", "pattern": "^[1-9][0-9]*$"},
                           "run_attempt": {"anyOf": [{"type": "integer", "minimum": 1},
                                                       {"type": "string", "pattern": "^[1-9][0-9]*$", "not": {"pattern": "[^0-9]"}}]},
                           "workflow_url": {"type": "string", "pattern": "^" + RUN_URL.pattern.replace("\\Z", "$")},
                           "capture_summary": {"type": "object", "required": ["result", "passedTests", "failedTests", "skippedTests"],
                                               "properties": {"result": {"const": "Passed"}, "passedTests": {"const": 1},
                                                              "failedTests": {"const": 0}, "skippedTests": {"const": 0}}},
                           "device": {"type": "object", "required": ["name"], "properties": {"name": {"const": "iPhone 17 Pro"}}},
                           "outputs": {"type": "array", "minItems": 12, "items": screenshot},
                           "branding": {"type": "object", "required": ["file", "sha256"], "properties": {
                               "file": {"const": WORDMARK}, "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"}}}},
            "$comment": "Runtime also enforces independent --expected-commit/--expected-workflow-run/--expected-run-attempt pins, URL/run/attempt consistency, every canonical required source, image/hash/metadata agreement and SHA-bound parent visual/crop QA in design.json. New capture commit is independent from base_commit; it is NOT forced to equal the base."}


def validate_provenance(value: dict, expected_commit: str, expected_run: str, expected_attempt: int | str,
                        expected_workflow_url: str | None = None) -> dict[str, dict]:
    need(bool(COMMIT.fullmatch(expected_commit)), "--expected-commit must be the literal full lowercase 40-hex CI commit")
    need(bool(RUN.fullmatch(expected_run)), "--expected-workflow-run must be the literal positive numeric run ID string")
    attempt = canonical_run_attempt(expected_attempt, "--expected-run-attempt")
    required = {"schema_version", "status", "fresh_capture", "locale", "app_language", "base_commit", "commit",
                "workflow_run", "run_attempt", "workflow_url", "capture_summary", "device", "outputs", "branding"}
    need(isinstance(value, dict) and required <= value.keys(), f"Parent capture provenance requires {sorted(required)}")
    need(type(value["schema_version"]) is int and value["schema_version"] == 1, "Unsupported parent provenance version")
    need(value["status"] == "PASS" and value["fresh_capture"] is True, "Fresh native capture PASS required")
    for name, expected in (("commit", expected_commit), ("workflow_run", expected_run), ("base_commit", BASE_COMMIT),
                           ("locale", "en-US"), ("app_language", "en")):
        need(value[name] == expected, f"SourceGate {name} mismatch: expected {expected!r}, found {value[name]!r}")
    need(canonical_run_attempt(value["run_attempt"], "provenance.run_attempt") == attempt,
         "SourceGate run_attempt differs from independent --expected-run-attempt")
    url = value["workflow_url"]
    match = RUN_URL.fullmatch(url) if isinstance(url, str) else None
    need(match is not None and match.group(1) == expected_run, "workflow_url must be the exact GitHub capture run URL")
    need(match.group(2) is None or match.group(2) == str(attempt), "workflow_url attempt differs from independent --expected-run-attempt")
    if expected_workflow_url is not None:
        need(url == expected_workflow_url, "Independent --expected-workflow-url mismatch")
    summary = value["capture_summary"]
    need(isinstance(summary, dict) and {"result", "passedTests", "failedTests", "skippedTests"} <= summary.keys(), "capture_summary missing native test results")
    need(summary["result"] == "Passed" and integer(summary["passedTests"], "capture_summary.passedTests", 1) == 1 and
         integer(summary["failedTests"], "capture_summary.failedTests") == 0 and
         integer(summary["skippedTests"], "capture_summary.skippedTests") == 0, "One passed, zero failed, zero skipped native capture test required")
    need(isinstance(value["device"], dict) and value["device"].get("name") == "iPhone 17 Pro", "Expected actual iPhone 17 Pro device metadata")
    for name, expected in (("appearance", "dark"), ("width", 1206), ("height", 2622)):
        if name in value["device"]:
            need(value["device"][name] == expected, f"Wrong device.{name}")
    need(isinstance(value["outputs"], list), "Parent outputs must be an array")
    rows: dict[str, dict] = {}
    for row in value["outputs"]:
        need(isinstance(row, dict) and {"file", "sha256", "width", "height", "mode", "opaque"} <= row.keys(), "Incomplete parent output record")
        path = row["file"]
        need(isinstance(path, str) and path not in rows, f"Duplicate/invalid output file: {path!r}")
        need(isinstance(row["sha256"], str) and bool(SHA.fullmatch(row["sha256"])), f"Invalid native SHA-256: {path}")
        need(integer(row["width"], "output.width", 1) == 1206 and integer(row["height"], "output.height", 1) == 2622 and
             row["mode"] in ("RGB", "RGBA") and row["opaque"] is True, f"Wrong native capture geometry/mode/opacity: {path}")
        # Extra real captures from the same CI artifact are preserved in provenance but NEVER used as fallback.
        rows[path] = row
    branding = value["branding"]
    need(isinstance(branding, dict) and branding.get("file") == WORDMARK and isinstance(branding.get("sha256"), str) and
         bool(SHA.fullmatch(branding["sha256"])), "Exact native branding file and SHA-256 required")
    need(WORDMARK not in rows, "Branding must be declared once, in branding")
    rows[WORDMARK] = branding
    required_sources = (CAPTURES - {"screenshots/concept-a-vault-locked.png"}) | {WORDMARK}
    need(required_sources <= rows.keys(), f"Missing canonical native outputs: {sorted(required_sources - rows.keys())}")
    return rows


def profile_info(raw: bytes | None, png_srgb_intent: int | None = None) -> dict:
    if not raw:
        return {"embedded": False, "sha256": None, "description": None,
                "png_sRGB_rendering_intent": png_srgb_intent,
                "interpretation": "Native PNG declares sRGB; no ICC conversion needed" if png_srgb_intent is not None else
                                  "Untagged native RGB interpreted as sRGB; parent must confirm in visualQA notes"}
    try:
        profile = ImageCms.ImageCmsProfile(io.BytesIO(raw))
        description = ImageCms.getProfileDescription(profile).strip()
        need(profile.profile.xcolor_space.strip() == "RGB", f"Native RGB ICC required: {description}")
    except GateError:
        raise
    except Exception as exc:
        raise GateError(f"Invalid ICC profile: {exc}") from exc
    return {"embedded": True, "sha256": digest(raw), "description": description}


def normalize_native(image: Image.Image, raw_icc: bytes | None) -> tuple[Image.Image, dict]:
    """Define the audited transform stage BEFORE crops/resampling; preserve native alpha."""
    info = profile_info(raw_icc, image.info.get("srgb"))
    alpha = image.getchannel("A") if image.mode == "RGBA" else None
    rgb = image.convert("RGB")
    if raw_icc:
        try:
            rgb = ImageCms.profileToProfile(rgb, ImageCms.ImageCmsProfile(io.BytesIO(raw_icc)),
                                           ImageCms.ImageCmsProfile(io.BytesIO(srgb_profile())),
                                           renderingIntent=ImageCms.Intent.RELATIVE_COLORIMETRIC, outputMode="RGB", flags=0)
        except Exception as exc:
            raise GateError(f"Native ICC to sRGB normalization failed: {exc}") from exc
    if alpha is not None:
        rgb.putalpha(alpha)
    return rgb, {"stage": "native ICC -> RGB sRGB (alpha preserved) -> original crop -> proportional LANCZOS -> outer mask",
                 "operation": "Pillow ImageCms.profileToProfile" if raw_icc else
                              ("Native PNG sRGB declaration preserved, no color conversion" if image.info.get("srgb") is not None else
                               "Untagged RGB interpreted as sRGB, no color conversion"),
                 "inputICC": info, "outputICC_SHA256": digest(srgb_profile()), "renderingIntent": "RELATIVE_COLORIMETRIC", "flags": 0,
                 "normalizedMode": rgb.mode, "normalizedPixelSHA256": digest(rgb.tobytes()),
                 "nativeAlphaPreserved": alpha is not None, "pixelProofReference": "This exact normalized pixel buffer before crop/resampling"}


@dataclass
class NativeSource:
    path: str
    sha256: str
    image: Image.Image
    original_mode: str
    icc: dict
    provenance: dict
    color_management: dict | None = None


class SourceGate:
    def __init__(self, root: Path, commit: str, run: str, expected_attempt: int | str, workflow_url: str | None = None):
        need(root.is_dir(), f"Native artifact directory is missing: {root}; no substitute sources are allowed")
        self.root = root.resolve()
        provenance_path = safe_asset(self.root, "capture_provenance.json")
        provenance_raw = provenance_path.read_bytes()
        self.provenance = json.loads(provenance_raw.decode("utf-8"), object_pairs_hook=unique_object)
        self.provenance_sha256 = digest(provenance_raw)
        self.rows = validate_provenance(self.provenance, commit, run, expected_attempt, workflow_url)
        self.expected_attempt = canonical_run_attempt(expected_attempt, "--expected-run-attempt")
        self.loaded: dict[str, NativeSource] = {}

    def load(self, relative: str) -> NativeSource:
        if relative in self.loaded:
            return self.loaded[relative]
        need(relative in self.rows, f"No exact provenance entry: {relative}")
        row = self.rows[relative]
        raw = safe_asset(self.root, relative).read_bytes()
        need(digest(raw) == row["sha256"], f"Source SHA-256 mismatch: {relative}")
        try:
            with Image.open(io.BytesIO(raw)) as probe:
                need(probe.format == "PNG" and getattr(probe, "n_frames", 1) == 1, f"Single native PNG required: {relative}")
                probe.verify()
            with Image.open(io.BytesIO(raw)) as native:
                native.load()
                need(native.getexif().get(274, 1) == 1, f"EXIF rotation is not permitted: {relative}")
                info = profile_info(native.info.get("icc_profile"), native.info.get("srgb"))
                original_mode = native.mode
                for field, actual in (("width", native.width), ("height", native.height), ("mode", original_mode)):
                    if field in row:
                        need(row[field] == actual, f"Parent record disagrees with actual {field}: {relative}")
                if relative == WORDMARK:
                    need(native.mode == "RGBA", "Native wordmark must be a transparent RGBA PNG")
                    extrema = native.getchannel("A").getextrema()
                    need(extrema[0] == 0 and extrema[1] > 0, "Native wordmark requires actual transparent background and visible pixels")
                    image, color_management = normalize_native(native, native.info.get("icc_profile"))
                else:
                    need(native.size == SIZE and native.mode in ("RGB", "RGBA"), f"Native screenshot must be RGB/opaque RGBA {SIZE}: {relative}")
                    if native.mode == "RGBA":
                        need(native.getchannel("A").getextrema() == (255, 255), f"Transparent screenshot rejected: {relative}")
                    normalized, color_management = normalize_native(native, native.info.get("icc_profile"))
                    image = normalized.convert("RGB")
                    need(any(lo != hi for lo, hi in image.getextrema()), f"Uniform/blank capture rejected: {relative}")
        except (OSError, SyntaxError) as exc:
            raise GateError(f"Cannot decode native PNG {relative}: {exc}") from exc
        result = NativeSource(relative, row["sha256"], image, original_mode, info, row, color_management)
        self.loaded[relative] = result
        return result


def normalized_copy(text: str | None) -> str | None:
    return text.replace("\n", " ") if isinstance(text, str) else text


def validate_design(design: dict) -> None:
    need(design.get("schemaVersion") == 1 and design.get("locale") == "en-US", "Only concept A v1 en-US is implemented")
    native_revision = design.get("nativeRevision")
    need(type(native_revision) is int and native_revision == 3 and design.get("creativeRevision") == design.get("layoutRevision") == 3, "This renderer requires the explicit v3 creative/layout/native contract")
    need(design.get("sampleMediaPolicy") == "approved-stock-photos-and-videos-no-app-screenshots", "Screenshot-free actual stock library is mandatory")
    need(design.get("nativeScenePolicy") == V3_SCENE_POLICY, "v3 requires actual sharp stock hero, opaque iOS dialog and filled Photo Pairs board")
    need(design.get("concept") == "A" and design["canvas"] == {"width": 1206, "height": 2622, "safeMargin": 70}, "Fixed canvas / shared 70 px margins required")
    need(design["layout"]["alignment"] == "left", "Left-aligned Concept A, not a centered hero")
    need(design["background"] == {"top": "#E0EFF9", "bottom": "#EAF4FB", "interpolation": "smoothstep"}, "Continuous ice-blue background contract changed")
    for name, color in {"ink": "#1C1916", "subtitle": "#1C1916", "keep": "#1B6FA8", "trash": "#C4441A", "later": "#6347D0"}.items():
        need(design["colors"].get(name) == color, f"App light foreground token changed: {name}")
    need(design["sourceGate"] == {"provenanceFile": "capture_provenance.json", "appLanguage": "en", "nativeSize": [1206, 2622],
         "minimumInsetTop": 200, "wordmarkSource": WORDMARK, "wordmarkComponent": "VaultDialWordmark", "wordmarkForeground": "lightForeground",
         "requireVisualQA": True, "requireProtectedNativeRects": True, "normalizeNativeICCToSRGB": True}, "SourceGate may not be weakened in design.json")
    slots = design["slots"]
    need(isinstance(slots, list) and len(slots) == 10, "Exactly ten slots are required")
    filenames: set[str] = set()
    # Latest owner brief explicitly authorizes exactly these three native details.
    for i, (slot, expected) in enumerate(zip(slots, COPY), 1):
        need(type(slot["id"]) is int and slot["id"] == i and normalized_copy(slot["headline"]) == expected[0] and
             normalized_copy(slot["subtitle"]) == expected[1], f"Exact sentence-case copy / order changed at slot {i}")
        expected_primary = ("screenshots/concept-a-later-swipe.png" if i == 5 and native_revision == 3
                            else f"screenshots/concept-a-{expected[2]}.png")
        need(slot["primary"] == expected_primary, f"Wrong native primary at slot {i}")
        need(bool(re.fullmatch(fr"{i:02d}-[a-z0-9-]+\.png", slot["file"])) and slot["file"] not in filenames, f"Invalid/duplicate output filename at slot {i}")
        filenames.add(slot["file"])
        need(slot["gestures"] is (i == 1), "Only slot 1 has the three marketing gesture arrows")
        insets = slot["insets"]
        need(isinstance(insets, list) and len(insets) <= 1, "One focal inset at most per phone")
        if i in INSETS:
            name, source, evidence = INSETS[i]
            need(len(insets) == 1 and insets[0]["id"] == name and insets[0]["source"] == f"screenshots/concept-a-{source}.png" and
                 insets[0]["enabled"] is True and insets[0]["required"] is True, f"Required truthful native inset missing in slot {i}")
            need(isinstance(insets[0].get("cropEvidenceRects"), dict) and set(insets[0]["cropEvidenceRects"]) == evidence,
                 f"Complete parent-bound native evidence fields required at slot {i}")
            need(insets[0].get("verticalAnchor") == ("bottom" if i in (3, 7) else "center"), "Exact inset anchoring required to avoid duplicate lower controls")
        else:
            need(not insets, f"Unexpected secondary focus in slot {i}")
    for kind, filename in (("headline", "PMDisplay-Bold.ttf"), ("subtitle", "PMText-Medium.ttf"), ("gesture", "PMText-Bold.ttf")):
        spec = design["fonts"][kind]
        need(spec["path"] == f"PhotoMaid/Resources/Fonts/{filename}", f"Bundled app font required: {kind}")
        for key in ("preferredSize", "minimumSize", "step", "maxLines", "lineGap"):
            integer(spec[key], f"font {kind}.{key}", 0 if key == "lineGap" else 1)
        need(spec["minimumSize"] <= spec["preferredSize"] and spec["step"] == 1, "Font shrink must proceed in 1 px steps to its floor")
        need(spec["minimumSize"] >= (84 if kind == "headline" else 46), f"Font floor too small: {kind}")
        need(spec["maxLines"] == (1 if kind == "gesture" else 2), "Headline/subtitle line limit cannot change")
    gestures = design["layout"]["gestures"]
    need([(g["action"], g["direction"], g["color"]) for g in gestures] ==
         [("Keep", "up", "keep"), ("Trash", "left", "trash"), ("Later", "right", "later")], "Gesture directions/semantics must not be mirrored")
    for kind, ids, columns, filename in (("overview", list(range(1, 11)), 10, "00-overview.jpg"),
                                        ("search", [1, 2, 3], 3, "00-search-preview.jpg")):
        preview = design["previews"][kind]
        need(preview["slotIds"] == ids and preview["columns"] == columns and preview["file"] == filename, "Preview count/order/single-row contract changed")
        for field in ("tileWidth", "gap", "margin"):
            integer(preview[field], f"preview {kind}.{field}", 1)
        need(preview["tileWidth"] <= 1206, "Preview upscaling forbidden")
        if kind == "search":
            need(2 * preview["margin"] + columns * preview["tileWidth"] + (columns - 1) * preview["gap"] == 390,
                 "Search preview must be exactly 390 pixels wide")


def font_files(design: dict) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for kind, spec in design["fonts"].items():
        path = safe_asset(ROOT, spec["path"])
        font = ImageFont.truetype(str(path), spec["preferredSize"])
        family, style = font.getname()
        need(family == ("PMDisplay" if kind == "headline" else "PMText"), f"Wrong app font family: {path}")
        result[kind] = {"path": str(path), "relativePath": spec["path"], "sha256": digest(path.read_bytes()), "family": family, "style": style}
    return result


def fit_text(text: str, box: tuple | list, spec: dict, font_path: str) -> dict:
    """Try every allowed line break at each size. Never truncate, condense or rewrite."""
    need(isinstance(text, str) and bool(text) and text == text.strip(), "Nonempty exact text required")
    need("\r" not in text and "\t" not in text and "  " not in text, "Only explicit newline/word-boundary wrapping is allowed")
    if "\n" in text:
        candidates = [text.split("\n")]
    else:
        words = text.split(" ")
        candidates = [[text]] + [[" ".join(words[:i]), " ".join(words[i:])] for i in range(1, len(words))]
    for size in range(spec["preferredSize"], spec["minimumSize"] - 1, -spec["step"]):
        font = ImageFont.truetype(font_path, size)
        advance = sum(font.getmetrics()) + spec["lineGap"]
        possible = []
        for lines in candidates:
            if len(lines) > spec["maxLines"] or not all(lines):
                continue
            raw = [font.getbbox(line) for line in lines]
            widths = [b[2] - b[0] for b in raw]
            tops = [b[1] + i * advance for i, b in enumerate(raw)]
            bottoms = [b[3] + i * advance for i, b in enumerate(raw)]
            height = max(bottoms) - min(tops)
            if max(widths) > wh(box)[0] or height > wh(box)[1]:
                continue
            # Prefer a sentence boundary and balanced lines, but never change the copy.
            sentence_bonus = 70 if len(lines) == 2 and lines[0][-1:] in ".?!" else 0
            score = (len(lines), max(widths) + (max(widths) - min(widths)) * 0.25 - sentence_bonus)
            origins = [(box[0] - b[0], box[1] - min(tops) + i * advance) for i, b in enumerate(raw)]
            bboxes = [[origin[0] + b[0], origin[1] + b[1], origin[0] + b[2], origin[1] + b[3]] for origin, b in zip(origins, raw)]
            possible.append((score, {"text": text, "lines": lines, "fontSize": size, "minimumSize": spec["minimumSize"],
                                     "preferredSize": spec["preferredSize"], "lineAdvance": advance, "origins": origins,
                                     "lineBBoxes": bboxes, "textBBox": [min(b[0] for b in bboxes), min(b[1] for b in bboxes),
                                                                                max(b[2] for b in bboxes), max(b[3] for b in bboxes)],
                                     "container": list(box), "fontPath": font_path, "shrinkSteps": spec["preferredSize"] - size}))
        if possible:
            return min(possible, key=lambda item: item[0])[1]
    raise GateError(f"Text cannot fit in <= {spec['maxLines']} lines at floor {spec['minimumSize']} px: {text!r}")


def inset_style(design: dict, layer_id: str) -> dict:
    if layer_id in ("series-decision", "system-dialog"):
        style_key = "seriesInsetStyle" if layer_id == "series-decision" else "dialogInsetStyle"
        style = design["layout"].get(style_key)
        need(style == {"radius": 0, "shadowBlur": 0, "shadowOffset": [0, 0], "shadowAlpha": 0},
             "Full-width series focus must be flat and shadow-free; no exposed underlying UI gutter")
        return style
    return design["layout"]["insetStyle"]


def layout_plan(design: dict, fonts: dict) -> list[dict]:
    layout = design["layout"]
    safe = (70, 70, SIZE[0] - 70, SIZE[1] - 70)
    header_boxes = [rect(layout[k], k) for k in ("wordmarkBox", "headlineBox", "subtitleBox")]
    for box in header_boxes:
        need(inside(box, safe), f"Header outside common safe margins: {box}")
    for i, box in enumerate(header_boxes):
        need(all(not overlaps(box, other) for other in header_boxes[i + 1:]), "Header containers overlap")
    device = layout["device"]
    geometry = phone_geometry(design)
    screen, frame = geometry["fullTargetGeometry"], geometry["fullFrameGeometry"]
    need(all(not overlaps(frame, box) for box in header_boxes), "Phone frame/header collision")
    for style in (device, layout["insetStyle"], inset_style(design, "series-decision")):
        integer(style["shadowBlur"], "shadowBlur")
        need(type(style["shadowAlpha"]) is int and 0 <= style["shadowAlpha"] <= 96, "Quiet bounded shadow alpha required")
        need(isinstance(style["shadowOffset"], list) and len(style["shadowOffset"]) == 2 and
             all(type(n) is int for n in style["shadowOffset"]), "Integer shadow offset required")
    need(1 <= integer(device["screenRadius"], "screenRadius", 1) <= min(wh(screen)) // 2, "Invalid screen radius")
    integer(layout["insetStyle"]["radius"], "inset radius", 1)
    result = []
    for slot in design["slots"]:
        item = {"slot": slot["id"], "headline": fit_text(slot["headline"], layout["headlineBox"], design["fonts"]["headline"], fonts["headline"]["path"]), "subtitle": None, "gestures": []}
        if slot["subtitle"]:
            item["subtitle"] = fit_text(slot["subtitle"], layout["subtitleBox"], design["fonts"]["subtitle"], fonts["subtitle"]["path"])
        for plan in (item["headline"], item["subtitle"]):
            if plan:
                need(all(inside(b, plan["container"]) for b in plan["lineBBoxes"]), "Actual text ink escapes its container")
        if slot["gestures"]:
            for gesture in layout["gestures"]:
                arrow = rect(gesture["arrowBox"], "gesture arrow")
                label = rect(gesture["labelBox"], "gesture label")
                need(inside(arrow, safe) and inside(label, safe) and not overlaps(arrow, label), "Gesture outside safe area / overlaps label")
                need(all(not overlaps(b, frame) and all(not overlaps(b, h) for h in header_boxes) for b in (arrow, label)), "Gesture obscures native phone or marketing copy")
                item["gestures"].append({**gesture, "textPlan": fit_text(gesture["action"], label, design["fonts"]["gesture"], fonts["gesture"]["path"])})
        for inset in slot["insets"]:
            if inset["enabled"]:
                target = rect(inset["targetBox"], f"slot {slot['id']} inset target")
                need(inside(target, (70, 70, SIZE[0] - 70, SIZE[1])) and inside(target, geometry["visibleGeometry"]), "Whole inset must remain entirely inside the visible screen; only its shadow may clip at the bottom")
                need(all(not overlaps(target, box) for box in header_boxes), "Inset covers marketing text or native wordmark")
        result.append(item)
    return result


def verify_sample_media_policy(gate: SourceGate) -> dict:
    """Independently read actual native PhotoKit evidence for the no-screen rule."""
    from collect_concept_a_provenance import MEDIA_POLICY, audit_sample_media
    need(gate.provenance.get("sample_media_policy") == MEDIA_POLICY, "Current artwork requires a screenshot-free actual sample library")
    recorded = gate.provenance.get("sample_media_audit", {})
    need(recorded.get("status") == "PASS" and recorded.get("fixture_filename_set_exact") is True,
         "Native no-screenshot library audit must pass")
    library_raw = safe_asset(gate.root, "concept-a-library.json").read_bytes()
    fixture_raw = safe_asset(gate.root, "fixture-manifest.json").read_bytes()
    need(digest(library_raw) == recorded.get("actual_library_sha256"), "Actual PhotoKit inventory hash changed")
    need(digest(fixture_raw) == gate.provenance.get("fixture_manifest_sha256"), "Actual fixture manifest hash changed")
    actual = audit_sample_media(json.loads(library_raw, object_pairs_hook=unique_object),
                                json.loads(fixture_raw, object_pairs_hook=unique_object))
    need(actual["status"] == "PASS", f"App screenshot or non-approved media in actual capture library: {actual['errors']}")
    need((actual["actual_asset_count"], actual["actual_photo_count"], actual["actual_video_count"]) == (37, 35, 2),
         "Exactly 35 approved stock photos and two real videos required")
    need(not (gate.root / "stills/concept-a-native-library.fixture.json").exists(), "Old app-screenshot fixture is never a final source")
    need(all(actual[key] == recorded.get(key) for key in ("actual_asset_count", "actual_photo_count", "actual_video_count",
                                                        "actual_screenshot_subtype_count", "fixture_filename_set_exact")),
         "Native library audit differs from its actual resources")
    return actual


def verify_native_scene_policy(gate: SourceGate) -> dict:
    """Recompute the parent collector's actual scene/hash evidence, fail closed."""
    need(gate.provenance.get("native_scene_policy") == V3_SCENE_POLICY and
         gate.provenance.get("native_scene_audit", {}).get("status") == "PASS", "Actual v3 native scene policy/audit must PASS; old green C6 is not final")
    try:
        from collect_concept_a_provenance import V3_SCENE_POLICY as policy, audit_v3_scenes
    except ImportError as exc:
        raise GateError("Parent collector's audit_v3_scenes is required before final rendering") from exc
    need(policy == V3_SCENE_POLICY, "Collector scene-policy constant differs")
    fixture = read_json(safe_asset(gate.root, "fixture-manifest.json"))
    actual = audit_v3_scenes(gate.root, fixture)
    need(actual.get("status") == "PASS" and actual == gate.provenance["native_scene_audit"],
         "Actual v3 hero/dialog-stability/game scene evidence or hashes differ from provenance")
    return actual


def prepare_sources(design: dict, gate: SourceGate) -> tuple[dict, list[dict]]:
    """Load ALL current required files before considering any layout/render output."""
    for relative in sorted((CAPTURES - {"screenshots/concept-a-vault-locked.png"}) | {WORDMARK}):
        gate.load(relative)
    verify_sample_media_policy(gate)
    verify_native_scene_policy(gate)
    review = design.get("finalSourceVisualQA", {})
    need(review.get("approved") is True and review.get("provenanceSHA256") == gate.provenance_sha256 and
         review.get("commit") == gate.provenance["commit"] and review.get("workflowRun") == gate.provenance["workflow_run"] and
         canonical_run_attempt(review.get("runAttempt"), "source visual QA runAttempt") == gate.expected_attempt and
         all(isinstance(review.get(k), str) and review[k].strip() for k in ("reviewer", "notes")),
         "Parent must approve finalSourceVisualQA in design.json, bound to ONE new fresh provenance SHA, commit, workflowRun and runAttempt")
    need(set(review.get("requirements", {})) == V3_REVIEW and all(value is True for value in review["requirements"].values()),
         "Every v3 source-visual requirement must be actually reviewed, not inherited from v2")
    need(review.get("nativeWordmarkComponent") == "VaultDialWordmark" and review.get("nativeWordmarkForeground") == "lightForeground" and
         review.get("nativeStatusBar") == {"time": "9:41", "fullBattery": True, "dynamicIsland": True, "appearance": "dark"},
         "Parent visual QA must confirm original native wordmark and native status-bar appearance")

    wordmark = gate.load(WORDMARK)
    wordmark_crop = wordmark.image.getchannel("A").getbbox()
    need(wordmark_crop is not None, "Empty native wordmark")
    wordmark_box, scale = contained_geometry(wh(wordmark_crop), design["layout"]["wordmarkBox"])
    # Top-left alignment applies to actual native wordmark ink, not its transparent padding.
    x, y = design["layout"]["wordmarkBox"][:2]
    wordmark_box = (x, y, x + wh(wordmark_box)[0], y + wh(wordmark_box)[1])
    branding = {"source": WORDMARK, "crop": list(wordmark_crop), "target": list(wordmark_box), "nativeScale": scale}
    screen = tuple(design["layout"]["device"]["screenBox"])
    geometry = phone_geometry(design)
    scale = geometry["nativeScale"]
    scale_x, scale_y = wh(screen)[0] / SIZE[0], wh(screen)[1] / SIZE[1]
    prepared = []
    for slot in design["slots"]:
        native = gate.load(slot["primary"])
        need(slot.get("primarySourceSHA256") == native.sha256, f"Parent must bind primaryProtectedRects to actual primarySourceSHA256 at slot {slot['id']}")
        regions = slot.get("primaryProtectedRects")
        need(isinstance(regions, list) and bool(regions), f"Parent source-vision QA must supply primaryProtectedRects at slot {slot['id']}")
        regions = [rect(r, f"slot {slot['id']} protected native evidence") for r in regions]
        protected = [(0, 0, 1206, 200)] + regions
        mapped = [(screen[0] + math.floor(r[0] * scale_x), screen[1] + math.floor(r[1] * scale_y),
                   screen[0] + math.ceil(r[2] * scale_x), screen[1] + math.ceil(r[3] * scale_y)) for r in protected]
        need(all(inside(r, geometry["visibleGeometry"]) for r in mapped),
             f"Bottom viewport clip hides parent-protected primary evidence at slot {slot['id']}; recapture/review, never silently drop protection")
        insets = []
        for inset in slot["insets"]:
            if not inset["enabled"]:
                continue
            source = gate.load(inset["source"])
            crop = rect(inset["crop"], f"Parent approved crop for {inset['id']}", source.image.size)
            need(crop[1] >= design["sourceGate"]["minimumInsetTop"], "Inset includes status bar / risks a second Dynamic Island")
            need(inset.get("cropSourceSHA256") == source.sha256, f"Crop must bind exact current source SHA-256: {inset['id']}")
            evidence = {name: list(rect(value, f"{inset['id']} / {name}")) for name, value in inset["cropEvidenceRects"].items()}
            need(all(inside(value, crop) for value in evidence.values()), f"Inset omits required whole native evidence: {inset['id']}")
            native_rect = None
            if slot["id"] == 3:
                native_rect = read_native_rect_evidence(gate.root, inset["nativeRectEvidence"])
                need(native_rect["file"] == "concept-a-delete-confirm-frame.json" and native_rect["jsonPointer"] == "/nativeRect"
                     and native_rect["format"] == "xyxy" and native_rect["coordinateScale"] == 1
                     and native_rect["sha256"] == gate.provenance["native_scene_audit"]["source_bindings"][native_rect["file"]]
                     and native_rect["nativePixelRect"] == gate.provenance["native_scene_audit"]["actual_dialog_native_rect"],
                     "Dialog crop must bind the exact actual v3 scene-audited native frame JSON")
                need(evidence["system-dialog"] == native_rect["nativePixelRect"] and inside(evidence["system-dialog"], crop),
                     "Inset must contain the entire actual JSON-bound native system-dialog frame")
            target, native_scale = inset_geometry(crop, inset)
            need(native_scale > max(scale_x, scale_y), f"Inset is not actually enlarged relative to the main phone: {inset['id']}")
            if inset["id"] in ("series-decision", "system-dialog"):
                need((target[0], target[2]) == (screen[0], screen[2]), "Series/dialog focus must cover both native screen edges; no underlying UI gutter")
            style = inset_style(design, inset["id"])
            effect = target if style["shadowAlpha"] == 0 else expanded(target, style["shadowBlur"] * 3 + 2, style["shadowOffset"])
            effect = (min(target[0], effect[0]), min(target[1], effect[1]), max(target[2], effect[2]), max(target[3], effect[3]))
            need(all(not overlaps(effect, focus) for focus in mapped), f"Inset/shadow covers parent-protected primary evidence: slot {slot['id']} / {inset['id']}")
            visible_effect = (effect[0], effect[1], effect[2], min(effect[3], SIZE[1]))
            need(inside(effect, screen) and inside(visible_effect, geometry["visibleGeometry"])
                 and effect[1] >= screen[1] + design["layout"]["device"]["screenRadius"],
                 "Inset/shadow may not cross the visible top/left/right hardware frame")
            need(all(not overlaps(effect, design["layout"][key]) for key in ("wordmarkBox", "headlineBox", "subtitleBox")), "Inset shadow covers header")
            need(all(not overlaps(effect, other["effectBox"]) for other in insets), "Native insets/shadows may not obscure one another")
            insets.append({"id": inset["id"], "source": inset["source"], "crop": list(crop), "target": list(target),
                           "nativeScale": native_scale, "magnificationRelativeToPhone": native_scale / scale,
                           "cropEvidenceRects": evidence, "nativeRectEvidence": native_rect,
                           "requestedBox": inset["targetBox"], "verticalAnchor": inset["verticalAnchor"],
                           "effectBox": list(effect), "visibleEffectBox": list(visible_effect),
                           "shadowViewportClip": "bottom-only" if effect[3] > SIZE[1] else "none"})
        prepared.append({"primary": slot["primary"], "protectedSourceRects": [list(r) for r in protected],
                         "protectedOutputRects": [list(r) for r in mapped], "insets": insets})
    return branding, prepared


def read_native_rect_evidence(root: Path, binding: dict) -> dict:
    """Read the actual capture's frame JSON; never guess a dialog rectangle."""
    keys(binding, {"file", "sha256", "jsonPointer", "format", "coordinateScale"}, label="nativeRectEvidence")
    need(isinstance(binding["file"], str) and binding["file"].endswith(".json") and
         isinstance(binding["sha256"], str) and bool(SHA.fullmatch(binding["sha256"])), "Actual native frame JSON path/hash are pending")
    raw = safe_asset(root, binding["file"]).read_bytes()
    need(digest(raw) == binding["sha256"], "Actual native frame evidence hash drift")
    value = json.loads(raw, object_pairs_hook=unique_object)
    pointer = binding["jsonPointer"]
    need(isinstance(pointer, str) and pointer.startswith("/"), "Explicit native frame JSON pointer required")
    for token in pointer[1:].split("/"):
        token = token.replace("~1", "/").replace("~0", "~")
        value = value[int(token)] if isinstance(value, list) else value[token]
    fmt, scale = binding["format"], binding["coordinateScale"]
    need(fmt in ("xywh", "xyxy") and type(scale) in (int, float) and math.isfinite(scale) and 0 < scale <= 3,
         "Native frame coordinates require explicit xywh/xyxy and scale (points=3, pixels=1)")
    if isinstance(value, dict):
        value = [value[k] for k in (("x", "y", "width", "height") if fmt == "xywh" else ("left", "top", "right", "bottom"))]
    need(isinstance(value, list) and len(value) == 4 and all(type(n) in (int, float) and math.isfinite(n) for n in value), "Native JSON frame must be four actual finite coordinates")
    a, b, c, d = value
    if fmt == "xywh":
        c, d = a + c, b + d
    native = list(rect([math.floor(a * scale), math.floor(b * scale), math.ceil(c * scale), math.ceil(d * scale)], "Actual JSON system-dialog frame"))
    return {**binding, "nativePixelRect": native}


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    radius = min(radius, min(size) // 2)
    big = Image.new("L", (size[0] * 4, size[1] * 4), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, big.width - 1, big.height - 1), radius=radius * 4, fill=255)
    return big.resize(size, RESAMPLE)


def background(design: dict) -> Image.Image:
    top = tuple(bytes.fromhex(design["background"]["top"][1:]))
    bottom = tuple(bytes.fromhex(design["background"]["bottom"][1:]))
    strip = Image.new("RGB", (1, SIZE[1]))
    rows = []
    for y in range(SIZE[1]):
        t = y / (SIZE[1] - 1)
        t = t * t * (3 - 2 * t)
        rows.append(tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    strip.putdata(rows)
    return strip.resize(SIZE, Image.Resampling.NEAREST)


def place_mask(local: Image.Image, box: tuple | list) -> Image.Image:
    whole = Image.new("L", SIZE, 0)
    whole.paste(local, box[:2])
    return whole


def shadow(canvas: Image.Image, box: tuple | list, mask: Image.Image, style: dict) -> Image.Image:
    field = Image.new("L", SIZE, 0)
    offset = style["shadowOffset"]
    field.paste(mask, (box[0] + offset[0], box[1] + offset[1]))
    field = field.filter(ImageFilter.GaussianBlur(style["shadowBlur"]))
    alpha = field.point(lambda v: round(v * style["shadowAlpha"] / 255))
    canvas.paste((20, 29, 36), (0, 0), alpha)
    return alpha


@dataclass
class PixelLayer:
    description: dict
    expected: Image.Image
    mask: Image.Image
    occlusion: Image.Image
    wordmark: bool = False


def native_layer(canvas: Image.Image, source: NativeSource, crop: tuple | list, target: tuple | list,
                 scale: float, radius: int, style: dict | None, layer_id: str) -> PixelLayer:
    # Defined ICC normalization, then one original crop and known LANCZOS resample. No UI edits.
    need(wh(target)[0] <= wh(crop)[0] and wh(target)[1] <= wh(crop)[1], "Native resolution exceeded")
    need(type(scale) in (int, float) and math.isfinite(scale) and 0 < scale <= 1 and
         all(abs(actual - original * scale) <= 0.5 + 1e-9 for actual, original in zip(wh(target), wh(crop))),
         "Native aspect may differ only by <=0.5px documented proportional integer rounding")
    tile = source.image.crop(crop)
    if tile.size != wh(target):
        tile = tile.resize(wh(target), RESAMPLE)
    is_wordmark = source.path == WORDMARK
    if is_wordmark:
        mask = tile.getchannel("A")
        expected = canvas.crop(target)
        expected.paste(tile.convert("RGB"), (0, 0), mask)
        occlusion = place_mask(mask, target)
        canvas.paste(tile.convert("RGB"), target[:2], mask)
    else:
        need(tile.mode == "RGB", "Native screen pixels must remain RGB")
        mask = rounded_mask(tile.size, radius)
        occlusion = shadow(canvas, target, mask, style) if style else Image.new("L", SIZE, 0)
        occlusion = ImageChops.lighter(occlusion, place_mask(mask, target))
        expected = tile
        canvas.paste(tile, target[:2], mask)
    viewport = viewport_mask(target)
    desc = {"id": layer_id, "originalSource": source.path, "sourceSHA256": source.sha256, "sourceSize": list(source.image.size),
            "sourceMode": source.original_mode, "sourceICC": source.icc, "crop": list(crop), "targetGeometry": list(target),
            "nativeScale": scale, "effectiveNativeScaleXY": [wh(target)[0] / wh(crop)[0], wh(target)[1] / wh(crop)[1]],
            "resample": "Pillow LANCZOS, one proportional contain; <=0.5 px per-axis integer rounding",
            "rotationDegrees": 0, "colorManagement": source.color_management,
            "colorOperations": [source.color_management["operation"]] if source.color_management else [],
            "mask": "original native wordmark alpha" if is_wordmark else "outer rounded mask, 4x antialiased",
            "maskSHA256": digest(mask.tobytes()), **viewport_geometry(target, crop),
            "viewportMaskSHA256": digest(viewport.tobytes()),
            "visibleMaskSHA256": digest(ImageChops.multiply(mask, viewport).tobytes())}
    return PixelLayer(desc, expected, mask, occlusion, is_wordmark)


def verify_native_pixels(canvas: Image.Image, layers: list[PixelLayer]) -> list[dict]:
    """Exact known-resample proof over every unobscured, fully opaque native interior."""
    proofs = []
    for i, layer in enumerate(layers):
        box = layer.description["targetGeometry"]
        # The alpha-edged wordmark compares to its exact original-alpha composite, not opaque RGB.
        eligible = layer.mask.point(lambda v: 255 if (v > 0 if layer.wordmark else v == 255) else 0)
        full_opaque_count = eligible.histogram()[255]
        eligible = ImageChops.multiply(eligible, viewport_mask(box))
        opaque_count = eligible.histogram()[255]
        need(opaque_count > 0, "No verifiable native interior pixels")
        for above in layers[i + 1:]:
            blocker = above.occlusion.crop(box).point(lambda v: 255 if v else 0)
            eligible = ImageChops.subtract(eligible, blocker)
        visible_count = eligible.histogram()[255]
        # The explicitly requested whole tall dialog repeats SAME-source evidence.
        # Account for its real occlusion; never lower equality or omit more pixels.
        same_dialog = any(above.description["id"] == "system-dialog" and
                          above.description["originalSource"] == layer.description["originalSource"] for above in layers[i + 1:])
        minimum_visible = (0.25 if same_dialog else 0.5) if layer.description["id"] == "full-phone" else 1
        need(visible_count >= opaque_count * minimum_visible, "Native evidence is excessively occluded")
        actual = canvas.crop(box).convert("RGB")
        difference = ImageChops.difference(actual, layer.expected)
        difference = Image.composite(difference, Image.new("RGB", difference.size), eligible)
        need(difference.getbbox() is None, f"Native interior pixels changed: {layer.description['id']}")
        ref = Image.composite(layer.expected, Image.new("RGB", layer.expected.size), eligible)
        got = Image.composite(actual, Image.new("RGB", actual.size), eligible)
        proofs.append({**layer.description, "pixelQA": {"status": "PASS", "comparedPixels": visible_count,
                       "opaqueInteriorPixels": opaque_count, "fullTargetOpaqueInteriorPixels": full_opaque_count,
                       "offCanvasOpaqueInteriorPixels": full_opaque_count - opaque_count,
                       "occludedByLaterInsetOrShadowPixels": opaque_count - visible_count,
                       "minimumVisibleViewportFraction": minimum_visible,
                       "maxChannelDifference": 0, "maskedKnownResampleSHA256": digest(ref.tobytes()),
                       "maskedOutputSHA256": digest(got.tobytes()),
                       "method": "Exact equality over the explicitly visible viewport mask; off-canvas pixels are not claimed visible. Rounded alpha edge and actual later inset/shadow occlusion excluded. Wordmark uses exact original-alpha composite."}})
    return proofs


def verify_frame_pixels(canvas: Image.Image, design: dict) -> dict:
    """Every fully opaque, visible hardware-ring pixel, no occlusion exemption."""
    geometry = phone_geometry(design)
    device = design["layout"]["device"]
    screen, frame = geometry["fullTargetGeometry"], geometry["fullFrameGeometry"]
    outer = place_mask(rounded_mask(wh(frame), device["screenRadius"] + device["frameWidth"]), frame)
    inner = place_mask(rounded_mask(wh(screen), device["screenRadius"]), screen)
    eligible = ImageChops.multiply(outer.point(lambda n: 255 if n == 255 else 0), inner.point(lambda n: 255 if n == 0 else 0))
    count = eligible.histogram()[255]
    need(count > 1000, "No actual visible hardware ring to verify")
    expected = Image.new("RGB", SIZE, device["frameColor"])
    diff = Image.composite(ImageChops.difference(canvas, expected), Image.new("RGB", SIZE), eligible)
    need(diff.getbbox() is None, "Visible hardware-frame pixels changed or are covered")
    return {"status": "PASS", "comparedPixels": count, "maxChannelDifference": 0,
            "visibleFrameMaskSHA256": digest(eligible.tobytes()), "topLeftRightVisible": True,
            "bottomIntentionallyClipped": True, "geometry": geometry}


def draw_text(canvas: Image.Image, plan: dict, color: str) -> None:
    font = ImageFont.truetype(plan["fontPath"], plan["fontSize"])
    draw = ImageDraw.Draw(canvas)
    for line, origin in zip(plan["lines"], plan["origins"]):
        draw.text(origin, line, font=font, fill=color)


def draw_arrow(canvas: Image.Image, box: tuple | list, direction: str, color: str) -> None:
    """Marketing arrows only; never drawn into a native screenshot."""
    w, h = wh(box)
    tile = Image.new("RGBA", (w * 4, h * 4), (0, 0, 0, 0))
    points = [(0.04, 0.36), (0.57, 0.36), (0.57, 0.08), (0.96, 0.50), (0.57, 0.92), (0.57, 0.64), (0.04, 0.64)]
    if direction == "left":
        points = [(1 - x, y) for x, y in points]
    elif direction == "up":
        points = [(y, 1 - x) for x, y in points]
    else:
        need(direction == "right", "Unsupported gesture direction")
    ImageDraw.Draw(tile).polygon([(round(x * (tile.width - 1)), round(y * (tile.height - 1))) for x, y in points], fill=color)
    tile = tile.resize((w, h), RESAMPLE)
    canvas.paste(tile.convert("RGB"), box[:2], tile.getchannel("A"))


def render_one(design: dict, slot: dict, text: dict, prepared: dict, branding: dict, gate: SourceGate) -> tuple[Image.Image, list[PixelLayer]]:
    canvas = background(design)
    layout = design["layout"]
    device = layout["device"]
    screen = tuple(device["screenBox"])
    frame = expanded(screen, device["frameWidth"])
    frame_mask = rounded_mask(wh(frame), device["screenRadius"] + device["frameWidth"])
    # Hardware shadow stays behind all marketing ink, never tints action-color labels.
    shadow(canvas, frame, frame_mask, device)
    canvas.paste(device["frameColor"], frame, frame_mask)
    layers = [native_layer(canvas, gate.load(WORDMARK), branding["crop"], branding["target"], branding["nativeScale"], 0, None, "native-wordmark")]
    draw_text(canvas, text["headline"], design["colors"]["ink"])
    if text["subtitle"]:
        draw_text(canvas, text["subtitle"], design["colors"]["subtitle"])
    for gesture in text["gestures"]:
        color = design["colors"][gesture["color"]]
        draw_arrow(canvas, gesture["arrowBox"], gesture["direction"], color)
        draw_text(canvas, gesture["textPlan"], color)
    layers.append(native_layer(canvas, gate.load(slot["primary"]), (0, 0, *SIZE), screen, wh(screen)[0] / SIZE[0], device["screenRadius"], None, "full-phone"))
    for inset in prepared["insets"]:
        style = inset_style(design, inset["id"])
        layers.append(native_layer(canvas, gate.load(inset["source"]), inset["crop"], inset["target"], inset["nativeScale"], style["radius"], style, inset["id"]))
    verify_native_pixels(canvas, layers)
    verify_frame_pixels(canvas, design)
    return canvas, layers


@functools.lru_cache(maxsize=1)
def srgb_profile() -> bytes:
    return ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()


def check_encoded_image(raw: bytes, size: tuple[int, int], fmt: str, icc: bytes) -> Image.Image:
    with Image.open(io.BytesIO(raw)) as image:
        image.load()
        need(image.format == fmt and image.size == size and image.mode == "RGB" and "A" not in image.getbands(), "Export format/dimensions/RGB/no-alpha check failed")
        need(image.info.get("icc_profile") == icc, "Export lost/changed the embedded sRGB ICC profile")
        profile_info(image.info["icc_profile"])
        return image.copy()


def write_exclusive_image(path: Path, image: Image.Image, fmt: str, icc: bytes) -> tuple[dict, Image.Image]:
    # Exclusive creation: never replace or delete an existing deliverable, even after a failed run.
    kwargs = {"icc_profile": icc}
    if fmt == "JPEG":
        kwargs.update(quality=94, subsampling=0)
    else:
        kwargs.update(optimize=False, compress_level=6)
    with path.open("xb") as stream:
        image.save(stream, format=fmt, **kwargs)
    raw = path.read_bytes()
    reopened = check_encoded_image(raw, image.size, fmt, icc)
    return {"file": path.name, "sha256": digest(raw), "width": image.width, "height": image.height,
            "mode": "RGB", "alpha": False, "format": fmt, "ICC": {"colorSpace": "sRGB", "embedded": True, "sha256": digest(icc)}}, reopened


def preview_image(design: dict, images: list[Image.Image], kind: str) -> tuple[Image.Image, dict]:
    spec = design["previews"][kind]
    ids = spec["slotIds"]
    need(len(ids) == spec["columns"], "Previews must be a single horizontal row")
    width = spec["tileWidth"]
    height = round(SIZE[1] * width / SIZE[0])
    margin, gap = spec["margin"], spec["gap"]
    sheet = Image.new("RGB", (2 * margin + len(ids) * width + (len(ids) - 1) * gap, height + 2 * margin), design["background"]["top"])
    need(kind != "search" or sheet.width == 390, "Search preview must be exactly 390 pixels wide")
    cells = []
    for index, slot_id in enumerate(ids):
        x, y = margin + index * (width + gap), margin
        tile = images[slot_id - 1].resize((width, height), RESAMPLE)
        sheet.paste(tile, (x, y))
        cells.append({"slot": slot_id, "targetGeometry": [x, y, x + width, y + height]})
    return sheet, {"slotIds": ids, "rows": 1, "columns": len(ids), "cells": cells, "tileSize": [width, height]}


def public_text_plan(plan: dict | None) -> dict | None:
    if plan is None:
        return None
    # Font hashes/portable relative paths are separately recorded, not host-dependent absolute paths.
    return {key: value for key, value in plan.items() if key != "fontPath"}


def render_all(design: dict, design_path: Path, gate: SourceGate, fonts: dict, texts: list[dict],
               branding: dict, prepared: list[dict], output: Path, reuse_icc_from: Path | None = None) -> dict:
    need(not output.exists(), f"Output already exists; nothing is overwritten/deleted: {output}")
    resolved = output.resolve()
    need(not resolved.is_relative_to(gate.root) and not gate.root.is_relative_to(resolved), "Output and native-source trees must be separate")
    need(not resolved.is_relative_to(ROOT), "Export outside the release worktree; renderer writes only the explicitly selected output directory")
    images, layer_sets = [], []
    # All source, crop, typography and pixel gates run before an output directory is created.
    for slot, text, source_plan in zip(design["slots"], texts, prepared):
        image, layers = render_one(design, slot, text, source_plan, branding, gate)
        images.append(image)
        layer_sets.append(layers)
    if reuse_icc_from is None:
        icc = srgb_profile()
    else:
        with Image.open(reuse_icc_from) as prior:
            need(prior.format == "PNG" and prior.mode == "RGB" and prior.size == SIZE, "Profile reuse requires a real prior full-size RGB PNG")
            icc = prior.info.get("icc_profile")
        need(isinstance(icc, bytes) and "srgb" in profile_info(icc)["description"].lower(), "Prior export must contain a valid sRGB ICC")
    previews = {kind: preview_image(design, images, kind) for kind in ("overview", "search")}
    output.mkdir(parents=True, exist_ok=False)
    exported = []
    for slot, image, layers, text, source_plan in zip(design["slots"], images, layer_sets, texts, prepared):
        record, reopened = write_exclusive_image(output / slot["file"], image, "PNG", icc)
        record.update({"slot": slot["id"], "headline": public_text_plan(text["headline"]), "subtitle": public_text_plan(text["subtitle"]),
                       "gestures": [{**g, "textPlan": public_text_plan(g["textPlan"])} for g in text["gestures"]],
                       "nativeLayers": verify_native_pixels(reopened, layers), "protectedEvidence": source_plan,
                       "framePixelQA": verify_frame_pixels(reopened, design),
                       "layoutQA": {"status": "PASS", "safeMargin": 70, "headlineMaxLines": 2, "subtitleMaxLines": 2,
                                    "phoneGeometry": phone_geometry(design), "originalNativeCrop": [0, 0, *SIZE],
                                    "phoneProportionalWithinHalfPixel": True, "nativeUpscaling": False, "secondDynamicIsland": False,
                                    "protectedPrimaryEvidenceUnobscured": True, "allTextBBoxesInsideContainers": True}})
        exported.append(record)
    preview_records = []
    for kind, (image, geometry) in previews.items():
        record, _ = write_exclusive_image(output / design["previews"][kind]["file"], image, "JPEG", icc)
        preview_records.append({**record, **geometry, "kind": kind})
    pngs = sorted(p.name for p in output.glob("*.png"))
    need(pngs == sorted(slot["file"] for slot in design["slots"]) and len(pngs) == 10, "Exactly the requested ten numbered PNGs must exist")
    manifest = {"schemaVersion": 1, "creativeRevision": 3, "layoutRevision": 3, "nativeRevision": 3,
                "runAttempt": gate.expected_attempt,
                "sampleMediaPolicy": design["sampleMediaPolicy"], "capturePolicy": "single-new-green-stock-only-run",
                "nativeScenePolicy": design["nativeScenePolicy"],
                "concept": "A", "locale": "en-US", "size": list(SIZE),
                "renderer": {"path": "scripts/store/render_concept_a.py", "sha256": digest(Path(__file__).read_bytes()),
                             "pillowVersion": Image.__version__, "pythonVersion": sys.version.split()[0]},
                "design": {"path": str(design_path.resolve()), "logicalPath": "app-store/concepts/A/design.json", "sha256": digest(design_path.read_bytes())},
                "sourceGate": {"status": "PASS", "passedTest": True, "sourceRoot": str(gate.root), "provenanceSHA256": gate.provenance_sha256, "provenance": gate.provenance,
                               "expectedRunAttempt": gate.expected_attempt,
                               "note": "Offline artifact/hash/explicit QA gate. Parent independently verifies CI run/commit/test and image content; not cryptographic CI attestation."},
                "originalSources": [{"path": s.path, "sha256": s.sha256, "size": list(s.image.size), "mode": s.original_mode,
                                     "ICC": s.icc, "colorManagement": s.color_management, "provenance": s.provenance} for s in sorted(gate.loaded.values(), key=lambda x: x.path)],
                "sourceVisualQA": design["finalSourceVisualQA"],
                "fonts": {kind: {k: v for k, v in data.items() if k != "path"} for kind, data in fonts.items()},
                "ICC": {"embedded": True, "colorSpace": "sRGB", "sha256": digest(icc), "description": profile_info(icc)["description"],
                        "reusedFromPriorExport": str(reuse_icc_from.resolve()) if reuse_icc_from else None},
                "outputs": exported, "previews": preview_records,
                "layoutQA": {"status": "PASS", "pngCount": len(pngs), "identicalFullTargetAndVisiblePhoneGeometry": True,
                             "phoneGeometry": phone_geometry(design), "requiredInsetSlots": [2, 3, 7], "subtitleCount": 10,
                             "screenBox": design["layout"]["device"]["screenBox"],
                             "frameBox": list(expanded(design["layout"]["device"]["screenBox"], design["layout"]["device"]["frameWidth"])),
                             "backgroundColors": design["background"],
                             "overviewSlots": list(range(1, 11)), "overviewRows": 1, "searchSlots": [1, 2, 3], "nativePixelComparison": "PASS",
                             "background": "Continuous smooth ice-blue gradient; no horizon/split; no page numerals or slogan",
                             "finalHumanVisualQA": "NOT_RUN: parent must inspect full-size exports and both previews before delivery"},
                "localizationRule": design["localizationRule"]}
    with (output / "render-manifest.json").open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    need(set(p.name for p in output.iterdir()) == set(pngs) | {"00-overview.jpg", "00-search-preview.jpg", "render-manifest.json"}, "Unexpected output files")
    return {"status": "PASS", "output": str(output), "pngCount": len(pngs), "previewCount": len(preview_records), "manifest": "render-manifest.json", "finalHumanVisualQA": "NOT_RUN"}


def self_test(design: dict, fonts: dict) -> dict:
    """Only rectangles, typography and failure injections, in memory; no UI or final PNGs."""
    passed: list[str] = []

    def check(name: str, fn) -> None:
        fn()
        passed.append(name)

    def rejected(name: str, fn) -> None:
        try:
            fn()
        except GateError:
            passed.append(name)
            return
        raise GateError(f"Self-test did not reject: {name}")

    check("design-contract", lambda: validate_design(design))
    wrong_media_policy = copy.deepcopy(design)
    wrong_media_policy["sampleMediaPolicy"] = "allow-app-screenshots"
    rejected("wrong-sample-media-policy-rejected", lambda: validate_design(wrong_media_policy))
    # Schema-only failure; never creates native-looking source data or files.
    from types import SimpleNamespace
    rejected("no-media-policy-native-proof-rejected", lambda: verify_sample_media_policy(SimpleNamespace(provenance={})))
    rejected("old-green-capture-without-v3-scene-proof-rejected", lambda: verify_native_scene_policy(SimpleNamespace(provenance={})))
    held_later_design = copy.deepcopy(design)
    held_later_design["nativeRevision"] = 3
    held_later_design["slots"][4]["primary"] = "screenshots/concept-a-later-swipe.png"
    check("v3-requires-genuine-held-later-primary", lambda: validate_design(held_later_design))
    for wrong_later in ("later", "swipe"):
        incorrect = copy.deepcopy(held_later_design)
        incorrect["slots"][4]["primary"] = f"screenshots/concept-a-{wrong_later}.png"
        rejected(f"v3-{wrong_later}-is-not-held-later", lambda candidate=incorrect: validate_design(candidate))
    for removed_slot in (4, 5, 6, 8, 9, 10):
        duplicate_overlay = copy.deepcopy(design)
        duplicate_overlay["slots"][removed_slot - 1]["insets"] = [{"enabled": True}]
        rejected(f"removed-duplicate-overlay-slot-{removed_slot}-rejected", lambda candidate=duplicate_overlay: validate_design(candidate))
    plans = layout_plan(design, fonts)
    check("ten-font-layouts", lambda: need(len(plans) == 10, "layout count"))
    check("all-headlines-max-two-lines-and-floor", lambda: need(all(len(p["headline"]["lines"]) <= 2 and p["headline"]["fontSize"] >= 84 for p in plans), "headline layout"))
    check("all-subtitles-max-two-lines-and-46px-floor", lambda: need(all(not p["subtitle"] or (len(p["subtitle"]["lines"]) <= 2 and p["subtitle"]["fontSize"] >= 46) for p in plans), "subtitle layout"))
    check("stepwise-font-reduction-exercised", lambda: need(any(p["headline"]["shrinkSteps"] > 0 for p in plans), "No shrink step exercised"))
    rejected("impossible-copy-rejected-at-floor", lambda: fit_text("This cannot fit", (70, 70, 72, 72), design["fonts"]["headline"], fonts["headline"]["path"]))
    rejected("invalid-crop-rejected", lambda: rect((0, 0, 1207, 2622), "test crop"))
    rejected("null-parent-crop-rejected", lambda: rect(None, "test unset crop"))
    check("contain-does-not-upscale", lambda: need(contained_geometry((80, 40), (70, 70, 1070, 1070))[0] == (530, 550, 610, 590), "native contain"))
    check("v3-phone-proportional-rounding-and-bottom-only-clip", lambda: phone_geometry(design))
    for name, box in (("old-full-visible-v2", list(V2_SCREEN)), ("left-clipped", [-9, 844, 935, 2896]),
                      ("top-clipped", [131, -1, 1075, 2051]), ("stretched", [131, 844, 1075, 2900])):
        bad = copy.deepcopy(design)
        bad["layout"]["device"]["screenBox"] = box
        rejected(name + "-rejected", lambda candidate=bad: phone_geometry(candidate))
    for number in (2, 3, 7):
        bad = copy.deepcopy(design)
        bad["slots"][number - 1]["insets"][0]["enabled"] = False
        rejected(f"required-v3-inset-{number}-cannot-be-disabled", lambda candidate=bad: validate_design(candidate))
    mask = rounded_mask((160, 320), 24)
    check("rounded-mask-antialias-outer-edge-only", lambda: need(mask.getpixel((80, 160)) == 255 and mask.getpixel((0, 0)) == 0 and any(0 < i < 255 and n for i, n in enumerate(mask.histogram())), "AA mask"))
    canvas = Image.new("RGB", SIZE, (224, 239, 249))
    source = NativeSource("rectangles-not-ui", "0" * 64, Image.new("RGB", (320, 640), (20, 80, 120)), "RGB", {}, {})
    layer = native_layer(canvas, source, (0, 0, 320, 640), (300, 900, 460, 1220), 0.5, 24, None, "rectangle-test")
    check("native-known-resample-pixel-equality", lambda: verify_native_pixels(canvas, [layer]))
    # This is a transparent rectangle, NOT substitute branding or an app screenshot.
    alpha_rectangle = Image.new("RGBA", (100, 36), (28, 25, 22, 0))
    ImageDraw.Draw(alpha_rectangle).rectangle((8, 8, 92, 28), fill=(28, 25, 22, 180))
    alpha_source = NativeSource(WORDMARK, "0" * 64, alpha_rectangle, "RGBA", {}, {})
    alpha_layer = native_layer(canvas, alpha_source, (0, 0, 100, 36), (70, 78, 170, 114), 1, 0, None, "alpha-rectangle-test")
    check("original-alpha-wordmark-path-pixel-proof", lambda: verify_native_pixels(canvas, [layer, alpha_layer]))
    corrupt = canvas.copy()
    corrupt.putpixel((350, 1000), (200, 20, 20))
    rejected("one-native-pixel-corruption-rejected", lambda: verify_native_pixels(corrupt, [layer]))
    clipped_canvas = Image.new("RGB", SIZE, (224, 239, 249))
    clipped = native_layer(clipped_canvas, source, (0, 0, 320, 640), (300, 2400, 460, 2720), 0.5, 24, None, "clipped-rectangle-unit-only")
    check("clipped-visible-native-known-resample-equality", lambda: verify_native_pixels(clipped_canvas, [clipped]))
    check("full-vs-visible-mask-coordinates-explicit", lambda: need(clipped.description["visibleGeometry"] == [300, 2400, 460, 2622]
          and clipped.description["viewportClipPixels"] == {"left": 0, "top": 0, "right": 0, "bottom": 98}, "clipped geometry"))
    clipped_canvas.putpixel((350, 2621), (200, 20, 20))
    rejected("one-visible-bottom-row-pixel-corruption-rejected", lambda: verify_native_pixels(clipped_canvas, [clipped]))
    rejected("native-upscale-rejected", lambda: native_layer(canvas, source, (0, 0, 320, 640), (0, 0, 640, 1280), 2.0, 24, None, "bad-upscale"))
    layer.description["id"] = "full-phone"
    inset_source = NativeSource("inset-rectangle-not-ui", "0" * 64, Image.new("RGB", (80, 40), (180, 110, 70)), "RGB", {}, {})
    inset_layer = native_layer(canvas, inset_source, (0, 0, 80, 40), (330, 1070, 410, 1110), 1, 8,
                               {"shadowBlur": 3, "shadowOffset": [0, 2], "shadowAlpha": 24}, "inset-rectangle-test")
    check("native-inset-shadow-occlusion-accounted", lambda: verify_native_pixels(canvas, [layer, alpha_layer, inset_layer]))
    raw = io.BytesIO()
    icc = srgb_profile()
    Image.new("RGB", (10, 20), (224, 239, 249)).save(raw, format="PNG", icc_profile=icc)
    check("in-memory-RGB-no-alpha-sRGB-PNG", lambda: check_encoded_image(raw.getvalue(), (10, 20), "PNG", icc))
    raw = io.BytesIO()
    Image.new("RGB", (10, 20), (224, 239, 249)).save(raw, format="JPEG", icc_profile=icc, quality=94, subsampling=0)
    check("in-memory-preview-JPEG-RGB-sRGB", lambda: check_encoded_image(raw.getvalue(), (10, 20), "JPEG", icc))
    # Schema-only records are never linked to files, SourceGate or the export path.
    rows = [{"file": name, "sha256": "0" * 64, "width": 1206, "height": 2622, "mode": "RGBA", "opaque": True}
            for name in sorted(CAPTURES - {"screenshots/concept-a-vault-locked.png"})]
    provenance = {"schema_version": 1, "status": "PASS", "fresh_capture": True, "locale": "en-US", "app_language": "en",
                  "base_commit": BASE_COMMIT, "commit": "a" * 40, "workflow_run": "1", "run_attempt": "1", "workflow_url": "https://github.com/test/rectangles/actions/runs/1",
                  "device": {"name": "iPhone 17 Pro"}, "capture_summary": {"result": "Passed", "passedTests": 1, "failedTests": 0, "skippedTests": 0},
                  "outputs": rows, "branding": {"file": WORDMARK, "sha256": "0" * 64}}
    validate = lambda data: validate_provenance(data, "a" * 40, "1", "1")
    check("parent-provenance-schema-contract", lambda: validate(provenance))
    check("fresh-capture-commit-distinct-from-base-accepted", lambda: need(provenance["commit"] != BASE_COMMIT and bool(validate(provenance)), "commit handling"))
    for field, bad in (("commit", "b" * 40), ("workflow_run", "2"), ("workflow_url", "https://github.com/test/rectangles/actions/runs/2"),
                       ("locale", "de-DE"), ("app_language", "enUS"), ("fresh_capture", "true"), ("status", "FAIL"), ("base_commit", "b" * 40)):
        changed = copy.deepcopy(provenance)
        changed[field] = bad
        rejected(f"provenance-{field}-mismatch-rejected", lambda data=changed: validate(data))
    changed = copy.deepcopy(provenance)
    changed["outputs"].pop()
    rejected("missing-native-provenance-record-rejected", lambda: validate(changed))
    changed = copy.deepcopy(provenance)
    changed["capture_summary"]["skippedTests"] = 1
    rejected("skipped-capture-test-rejected", lambda: validate(changed))
    # Exercise the exact ICC normalization/reference stage on rectangles, preserving alpha.
    rgba = Image.new("RGBA", (24, 36), (60, 110, 180, 255))
    rgba.putpixel((0, 0), (60, 110, 180, 0))
    normalized, transform = normalize_native(rgba, icc)
    check("ICC-normalization-defined-and-alpha-preserved", lambda: need(normalized.mode == "RGBA" and
          normalized.getchannel("A").tobytes() == rgba.getchannel("A").tobytes() and
          transform["outputICC_SHA256"] == digest(icc), "ICC normalization"))
    rejected("malformed-ICC-rejected-not-silently-ignored", lambda: normalize_native(rgba, b"not-an-ICC-profile"))
    from unittest.mock import Mock, patch
    review_gate = Mock(provenance_sha256="c" * 64, provenance={"commit": "a" * 40, "workflow_run": "1", "run_attempt": "1"}, expected_attempt=1, load=lambda name: source)
    stale_review = copy.deepcopy(design)
    stale_review["finalSourceVisualQA"].update(approved=True, provenanceSHA256="d" * 64, commit="a" * 40, workflowRun="1", runAttempt=1, reviewer="UNIT TEST ONLY", notes="No native UI approval")
    # Keep negative fixtures explicit even after the real design is approved.
    unapproved_review = copy.deepcopy(stale_review)
    unapproved_review["finalSourceVisualQA"].update(approved=False, provenanceSHA256="c" * 64)
    # Isolate REVIEW negatives so the earlier media/scene gates cannot satisfy them.
    # Schema mocks only; no files, native captures or approval are produced.
    with patch(__name__ + ".verify_sample_media_policy", return_value={}), patch(__name__ + ".verify_native_scene_policy", return_value={}):
        rejected("unset-parent-source-vision-approval-rejected", lambda: prepare_sources(unapproved_review, review_gate))
        rejected("stale-parent-source-vision-provenance-rejected", lambda: prepare_sources(stale_review, review_gate))
        stale_review["finalSourceVisualQA"]["provenanceSHA256"] = "c" * 64
        stale_review["finalSourceVisualQA"]["requirements"]["noLoadingSpinner"] = False
        rejected("unreviewed-v3-source-scene-requirements-rejected", lambda: prepare_sources(stale_review, review_gate))
    isolated_gate = SourceGate.__new__(SourceGate)
    isolated_gate.root, isolated_gate.rows, isolated_gate.loaded = ROOT, {"test.png": {"sha256": "0" * 64}}, {}
    with patch(__name__ + ".safe_asset", return_value=Mock(read_bytes=lambda: b"rectangle-test-bytes-not-ui")):
        rejected("native-source-hash-mismatch-rejected-before-decode", lambda: isolated_gate.load("test.png"))
    rejected("missing-source-directory-rejected", lambda: SourceGate(ROOT / "__unit_test_absent_sources__", "a" * 40, "1", "1"))
    rejected("duplicate-JSON-provenance-keys-rejected", lambda: json.loads('{"commit":"a","commit":"b"}', object_pairs_hook=unique_object))
    rejected("malformed-literal-commit-rejected", lambda: validate_provenance(provenance, "a" * 39, "1", "1"))
    rejected("malformed-literal-run-rejected", lambda: validate_provenance(provenance, "a" * 40, "01", "1"))
    rejected("independent-workflow-url-mismatch-rejected", lambda: validate_provenance(provenance, "a" * 40, "1", "1", "https://github.com/another/repo/actions/runs/1"))
    changed = copy.deepcopy(design)
    changed["slots"][0]["headline"] = "SWIPE THE CLUTTER. KEEP THE MEMORIES."
    rejected("changed-copy-rejected", lambda: validate_design(changed))
    # Preview geometry/order is checked on plain rectangles, never substitute app UI.
    rectangles = [Image.new("RGB", SIZE, (10 + i, 40 + i, 70 + i)) for i in range(10)]
    overview, overview_geometry = preview_image(design, rectangles, "overview")
    search, search_geometry = preview_image(design, rectangles, "search")
    check("overview-all-ten-one-horizontal-row", lambda: need(overview_geometry["slotIds"] == list(range(1, 11)) and len({c["targetGeometry"][1] for c in overview_geometry["cells"]}) == 1, "overview"))
    check("search-first-three-390px-wide", lambda: need(search_geometry["slotIds"] == [1, 2, 3] and search.width == 390, "search geometry"))
    return {"status": "PASS", "checks": len(passed), "passed": passed, "nativeCapturesUsed": False, "filesWritten": [],
            "note": "In-memory rectangles/font/schema tests only. Actual native SourceGate and final rendering remain for parent CI.",
            "fontLayouts": [{"slot": p["slot"], "headlineSize": p["headline"]["fontSize"], "headlineLines": p["headline"]["lines"],
                             "subtitleSize": p["subtitle"]["fontSize"] if p["subtitle"] else None} for p in plans],
            "previewGeometry": {"overview": [overview.width, overview.height], "search": [search.width, search.height]}}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--design", type=Path, default=DEFAULT_DESIGN)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--self-test", action="store_true", help="Memory-only rectangles/font/schema tests; no output files")
    modes.add_argument("--check-layout", action="store_true", help="Validate shared geometry/fonts only; not native/source acceptance")
    modes.add_argument("--print-provenance-schema", action="store_true", help="Print the complete JSON Schema; no source files needed")
    modes.add_argument("--validate-only", action="store_true", help="Full source/crop/layout gates, but no render/output")
    parser.add_argument("--sources", type=Path, help="Fresh native artifact root containing capture_provenance.json")
    parser.add_argument("--output", type=Path, help="NEW directory outside repo and source tree; no overwrite/deletion")
    parser.add_argument("--reuse-icc-from", type=Path, help="Reuse a previous export's embedded sRGB ICC so unchanged PNGs stay byte-identical")
    parser.add_argument("--expected-commit", help="Independent exact lowercase 40-hex captured commit (not inferred from provenance)")
    parser.add_argument("--expected-workflow-run", help="Independent exact GitHub workflow run ID string")
    parser.add_argument("--expected-run-attempt", help="Required independent positive capture attempt; never inferred from provenance")
    parser.add_argument("--expected-workflow-url", help="Optional independently pinned exact GitHub capture run URL (run ID is always checked)")
    args = parser.parse_args(argv)
    try:
        if args.print_provenance_schema:
            print(json.dumps(provenance_schema(), indent=2))
            return 0
        design = read_json(args.design)
        validate_design(design)
        fonts = font_files(design)
        texts = layout_plan(design, fonts)
        if args.self_test:
            result = self_test(design, fonts)
        elif args.check_layout:
            result = {"status": "PASS", "scope": "geometry-and-fonts-only", "slots": len(texts), "sourceGate": "NOT_RUN", "filesWritten": [],
                      "texts": [{"slot": p["slot"], "headline": public_text_plan(p["headline"]), "subtitle": public_text_plan(p["subtitle"])} for p in texts]}
        else:
            need(args.sources is not None and args.expected_commit is not None and args.expected_workflow_run is not None and args.expected_run_attempt is not None,
                 "Render/validate requires --sources, --expected-commit, --expected-workflow-run and --expected-run-attempt; no defaults/legacy fallback")
            need(args.validate_only or args.output is not None, "Render requires an explicit NEW --output directory")
            gate = SourceGate(args.sources, args.expected_commit, args.expected_workflow_run, args.expected_run_attempt, args.expected_workflow_url)
            branding, prepared = prepare_sources(design, gate)
            if args.validate_only:
                result = {"status": "PASS", "scope": "source-provenance-crop-and-layout-gates", "sourceCount": len(gate.loaded), "slots": len(texts), "filesWritten": [], "nativePixelsAndFinalExports": "NOT_RUN"}
            else:
                result = render_all(design, args.design, gate, fonts, texts, branding, prepared, args.output, args.reuse_icc_from)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (GateError, KeyError, TypeError, OSError, json.JSONDecodeError, UnicodeError) as exc:
        print(json.dumps({"status": "BLOCKED", "error": str(exc), "policy": "Fail closed; no substitute/old capture, reconstructed UI, overwrite or automatic deletion"}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
