#!/usr/bin/env python3
"""STRUCTURAL ONLY: V4 contract/negative controls, not native or visual PASS.

No screenshots, mock UI, provenance files, native run, network, CI, installation,
commits or Store delivery are created. Unit rectangle/alpha files exist only in
F:/HermesTemp temporary directories and never enter a SourceGate or render pack.
Run with TEMP/TMP/TMPDIR=F:/HermesTemp and PYTHONDONTWRITEBYTECODE=1.
"""
from __future__ import annotations

import ast
import contextlib
import copy
import io
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import re

from PIL import Image, ImageChops, ImageDraw

import render_concept_a_v4 as renderer
import audit_concept_a_v4 as auditor
import render_concept_a as engine
import audit_concept_a as reference
import collect_concept_a_v4_provenance as collector

ROOT = Path(__file__).resolve().parents[2]
TEMP_ROOT = Path("F:/HermesTemp")
# These are invalid/unpublished structural pins, NOT a claim about a real run.
STRUCTURAL_COMMIT = "f" * 40
STRUCTURAL_RUN = "999999999999999999999"


class V4StructuralTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.design = renderer.read_json(renderer.DEFAULT_DESIGN)
        # Ordinary-gate negatives must not inherit the live design's C5-only
        # exception: that earlier pin gate would mask the approval/history gate
        # being tested. C5ExceptionStructuralTests loads the real design separately.
        cls.design["captureBinding"].pop("workflowException", None)
        cls.fonts = engine.font_files(cls.design)
        TEMP_ROOT.mkdir(parents=True, exist_ok=True)
        cls.legacy_constants = copy.deepcopy((engine.COPY, engine.CAPTURES, engine.INSETS, reference.COPY, reference.INSETS))
        cls.legacy_hashes = {path: auditor.digest(ROOT / path) for path in (
            "scripts/store/render_concept_a.py", "scripts/store/audit_concept_a.py", "scripts/store/package_concept_a.py",
            "app-store/concepts/A/design.json", "app-store/concepts/A/v3/design.json")}

    @classmethod
    def tearDownClass(cls):
        if cls.legacy_constants != (engine.COPY, engine.CAPTURES, engine.INSETS, reference.COPY, reference.INSETS):
            raise AssertionError("Legacy module globals were mutated")
        if cls.legacy_hashes != {path: auditor.digest(ROOT / path) for path in cls.legacy_hashes}:
            raise AssertionError("Protected accepted files changed during structural tests")

    def rejects_design(self, mutate):
        value = copy.deepcopy(self.design)
        mutate(value)
        for module in (renderer, auditor):
            with self.subTest(module=module.__name__):
                with self.assertRaises((ValueError, KeyError, TypeError)):
                    module.validate_design(value)

    def test_separate_v4_contract_is_structurally_valid(self):
        renderer.validate_design(self.design)
        auditor.validate_design(self.design)
        self.assertEqual(renderer.VERSION, auditor.VERSION)
        self.assertEqual(renderer.LEGACY_SCREENS, auditor.LEGACY_SCREENS)
        self.assertEqual(renderer.NEW_SCREENS, auditor.NEW_SCREENS)
        self.assertEqual(len(renderer.LEGACY_SCREENS), 14)
        self.assertEqual(len(renderer.CAPTURES), 20)
        self.assertEqual(renderer.REVIEW, auditor.REVIEW)

    def test_current_collector_mandatory_optional_and_legacy_source_inventory(self):
        legacy = {f"screenshots/concept-a-{name}.png" for name in collector.legacy.REQUIRED}
        added = {"screenshots/" + name for name in collector.NEW_SCREENS}
        optional = "screenshots/" + collector.OPTIONAL_WARM
        self.assertEqual(legacy, renderer.LEGACY_SCREENS)
        self.assertEqual(added, renderer.NEW_SCREENS)
        self.assertEqual(legacy | added, renderer.CAPTURES)
        self.assertEqual(renderer.CAPTURES, auditor.LEGACY_SCREENS | auditor.NEW_SCREENS)
        self.assertEqual(len(legacy | added), 20)
        self.assertNotIn(optional, renderer.CAPTURES)
        self.assertEqual(optional, "screenshots/concept-a-v4-editor-filter-selected.png")
        # The accepted base validator permits extra same-artifact outputs. Its old
        # canonical subset must fit the new 20; never require base outputs == 14:
        # the real base collector scans all screenshots before V4 replaces outputs.
        base_required = engine.CAPTURES - {"screenshots/concept-a-vault-locked.png"}
        self.assertTrue(base_required <= legacy)
        self.assertIn("screenshots/concept-a-games-menu.png", legacy)
        base_tree = ast.parse(Path(collector.legacy.__file__).read_text(encoding="utf-8"))
        self.assertTrue(any(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                            and node.func.attr == "glob" and node.args
                            and isinstance(node.args[0], ast.Constant) and node.args[0].value == "*.png"
                            for node in ast.walk(base_tree)))
        self.assertEqual(collector.DEFAULT_CAPTURE_TEST, renderer.CAPTURE_TEST)
        self.assertEqual(collector.DEFAULT_CAPTURE_TEST, auditor.CAPTURE_TEST)
        self.assertEqual(collector.V4_SCENE_POLICY, renderer.SCENE_POLICY)
        self.assertEqual(collector.MEDIA_POLICY, auditor.MEDIA_POLICY)

    def test_current_collector_subgate_names_match_the_render_contract(self):
        # Inspect the actual producer, without constructing or writing a PASS
        # provenance object. Raw library/fixture values are not status wrappers;
        # exact_attempt_api may remain NOT RUN until the separate post-run readback.
        producer = ast.parse(Path(collector.__file__).read_text(encoding="utf-8"))
        collect = next(node for node in producer.body if isinstance(node, ast.FunctionDef) and node.name == "collect")
        labels = {node.args[0].value for node in ast.walk(collect)
                  if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "check"
                  and node.args and isinstance(node.args[0], ast.Constant)}
        consumer = ast.parse((ROOT / "scripts/store/render_concept_a_v4.py").read_text(encoding="utf-8"))
        validate = next(node for node in consumer.body if isinstance(node, ast.FunctionDef) and node.name == "validate_provenance")
        required = next(ast.literal_eval(node.value) for node in ast.walk(validate)
                        if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "required" for target in node.targets))
        self.assertEqual(required, labels)
        self.assertEqual(required, {"literal_run_pins", "capture_test", "fixture_manifest", "original_sources",
            "fixture_records", "fixture_files", "captured_fixture_manifest_bytes", "native_screens", "actual_library",
            "sample_media", "month_progress", "editor_pair", "exact_attempt_api"})
        self.assertIn("audits['native_screens'] = {'status': 'PASS', 'required_count': len(screens)", Path(collector.__file__).read_text(encoding="utf-8"))

    def test_actual_native_editor_pair_geometry_and_core_field_mappings(self):
        # Source interface checks only: no PhotoKit IDs, publication hashes, PNGs,
        # action receipts, observed snapshots or native provenance are fabricated.
        native = (ROOT / "PhotoMaidUITests/AppStoreCaptureTests.swift").read_text(encoding="utf-8")
        core = native.split("private func conceptAV4EditorCore", 1)[1].split("private func conceptAV4EditorReady", 1)[0]
        fields = set(re.findall(r'"([A-Za-z][A-Za-z0-9]+)"', core.split("let keys = [", 1)[1].split("]", 1)[0]))
        self.assertEqual(fields, {"assetID", "loadState", "originalReady", "previewReady", "rendering", "requestedRecipeHash",
            "publishedRecipeHash", "renderGeneration", "publishedRenderGeneration", "publishedFilter", "publishedFilterStrength",
            "publishedIsIdentity", "sourceOriginalPixelSHA256", "publishedPreviewPixelSHA256"})
        self.assertIn('"editorV4": readback, "editorObservation": observation', native)
        self.assertIn('"photoNativeFrame": conceptAV4Rect(nativeRect)', native)
        self.assertIn('["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]', native)
        entry = native.split("func test08ConceptAV4StoreScreenshots()", 1)[1].split("} catch", 1)[0]
        self.assertEqual(entry.count("try captureConceptAV4BaseScreenshots()"), 1)
        self.assertNotIn("try test07ConceptAStoreScreenshots()", entry)
        # The fixture suite separately byte-compares every mirrored base/Vault gate;
        # only V4's real Next/secure-field readiness differs from the frozen legacy path.
        for module in (renderer, auditor):
            code = Path(module.__file__).read_text(encoding="utf-8")
            self.assertIn('proof["checkpoints"]["after"]["photoNativeFrame"]', code)
            for key in ("x", "y", "width", "height"):
                self.assertIn('["' + key + '"]', code)
        model = (ROOT / "PhotoMaid/Features/Editor/EditorModel.swift").read_text(encoding="utf-8")
        self.assertTrue(fields <= set(re.findall(r'"([A-Za-z][A-Za-z0-9]+)"', model)))

    def test_exact_sequence_and_fixed_native_primary_paths(self):
        expected = ["swipe", "large-files", "analysis", "delete-confirm", "vault", "later-swipe", "v4-months", "collage", "v4-editor-after", "games"]
        self.assertEqual([s["primary"] for s in self.design["slots"]], ["screenshots/concept-a-" + p + ".png" for p in expected])
        self.assertEqual([s["id"] for s in self.design["slots"] if s["insets"]], [2, 3, 4])
        self.assertEqual(self.design["slots"][5]["insets"], [])
        self.assertEqual([r["new"] for r in self.design["slotMapping"] if r["old"] == 7], [3])
        self.assertEqual(self.design["slots"][4]["subtitle"], "Encrypted vault, protected by your own code and Face ID.")
        self.assertEqual(self.design["slots"][9]["subtitle"], "Match pairs with your own photos.")

    def test_actual_bundled_font_fit_all_ten_without_render(self):
        plans = engine.layout_plan(self.design, self.fonts)
        self.assertEqual(len(plans), 10)
        for slot, plan in zip(self.design["slots"], plans):
            for kind, floor, preferred in (("headline", 84, 112), ("subtitle", 46, 52)):
                text = plan[kind]
                self.assertEqual(" ".join(text["lines"]), slot[kind])
                self.assertLessEqual(len(text["lines"]), 2)
                self.assertTrue(floor <= text["fontSize"] <= preferred)
                self.assertTrue(all(engine.inside(b, text["container"]) for b in text["lineBBoxes"]))

    def test_unknown_design_keys_rejected_at_every_mutable_level(self):
        mutations = [lambda d: d.update(unknown=True), lambda d: d["layout"].update(unknown=True),
            lambda d: d["captureBinding"].update(unknown=True), lambda d: d["captureBinding"]["exactAttemptReadback"].update(unknown=True),
            lambda d: d["sourceGate"].update(allowLegacyFallback=True), lambda d: d["finalSourceVisualQA"].update(unknown=True),
            lambda d: d["finalSourceVisualQA"]["sourceReview"].update(unknown=True), lambda d: d["slots"][0].update(unknown=True),
            lambda d: d["slots"][1]["insets"][0].update(unknown=True), lambda d: d["slots"][8]["editorComparison"].update(unknown=True),
            lambda d: d["slots"][8]["editorComparison"]["proof"].update(unknown=True), lambda d: d["fonts"]["headline"].update(unknown=True),
            lambda d: d["previews"]["search"].update(rows=2), lambda d: d["localizationRule"].update(unknown=True)]
        for mutation in mutations:
            self.rejects_design(mutation)

    def test_old_revision_and_old_primary_sources_rejected(self):
        for key in ("schemaVersion", "creativeRevision", "layoutRevision", "nativeRevision"):
            self.rejects_design(lambda d, k=key: d.update({k: 1 if k == "schemaVersion" else 3}))
        for index, source in ((6, "screenshots/concept-a-months.png"), (8, "screenshots/concept-a-editor.png")):
            self.rejects_design(lambda d, i=index, s=source: d["slots"][i].update(primary=s))

    def test_copy_and_security_claims_cannot_silently_drift(self):
        self.rejects_design(lambda d: d["slots"][1].update(headline="You freed 2 GB."))
        self.rejects_design(lambda d: d["slots"][4].update(subtitle="100% secure."))
        self.rejects_design(lambda d: d["slots"][6].update(subtitle="Start exactly where you left off."))
        self.rejects_design(lambda d: d["slots"][9].update(subtitle="You win every time."))

    def test_wrong_inset_slot_or_native_evidence_set_rejected(self):
        self.rejects_design(lambda d: d["slots"][5]["insets"].append(copy.deepcopy(d["slots"][1]["insets"][0])))
        self.rejects_design(lambda d: d["slots"][2]["insets"][0]["cropEvidenceRects"].pop("keep5-trash1"))
        self.rejects_design(lambda d: d["slots"][3]["insets"][0]["nativeRectEvidence"].update(file="guessed-frame.json"))
        self.rejects_design(lambda d: d["layout"]["seriesInsetStyle"].update(radius=1))
        self.rejects_design(lambda d: d["layout"]["dialogInsetStyle"].update(shadowAlpha=1))

    def test_common_phone_bottom_clip_and_independent_coordinates(self):
        actual, independent = renderer.phone_geometry(self.design), auditor.phone_geometry(self.design)
        self.assertEqual(actual, independent)
        self.assertEqual(actual["fullTargetGeometry"], [131, 844, 1075, 2896])
        self.assertEqual(actual["visibleGeometry"], [131, 844, 1075, 2622])
        self.assertEqual(actual["viewportClipPixels"], {"left": 0, "top": 0, "right": 0, "bottom": 274})
        self.assertFalse(actual["completePhoneVisible"])
        self.assertLessEqual(abs(actual["resampleRoundingXY"][1]), .5)
        for box in ([132, 844, 1076, 2896], [131, 700, 1075, 2752], [131, 844, 1075, 2622]):
            self.rejects_design(lambda d, b=box: d["layout"]["device"].update(screenBox=b))

    def test_gesture_directions_and_localization_stay_locked(self):
        self.rejects_design(lambda d: d["layout"]["gestures"][1].update(direction="right"))
        self.rejects_design(lambda d: d["layout"].update(alignment="center"))
        self.rejects_design(lambda d: d.update(locale="de-DE"))
        self.rejects_design(lambda d: d["localizationRule"].update(renderNow=["en-US", "de-DE"]))

    def test_unapproved_capture_fails_before_source_access(self):
        value = copy.deepcopy(self.design)
        value["captureBinding"]["approved"] = False
        value["finalSourceVisualQA"]["approved"] = False
        for module in (renderer, auditor):
            with self.assertRaisesRegex(ValueError, "UNAPPROVED"):
                module.require_calibrated(value, STRUCTURAL_COMMIT, STRUCTURAL_RUN, "1")

    def test_unapproved_source_review_is_independent_negative(self):
        value = copy.deepcopy(self.design)
        value["captureBinding"].update(approved=True, commit=STRUCTURAL_COMMIT, workflowRun=STRUCTURAL_RUN,
            runAttempt=1, provenanceSHA256="0" * 64, exactAttemptReadback={"file": "structural-only-not-real.json", "sha256": "0" * 64})
        value["finalSourceVisualQA"]["approved"] = False
        for module in (renderer, auditor):
            with self.assertRaisesRegex(ValueError, "VQA"):
                module.require_calibrated(value, STRUCTURAL_COMMIT, STRUCTURAL_RUN, 1)

    def test_historical_capture_can_never_satisfy_new_gate(self):
        for module in (renderer, auditor):
            with self.assertRaisesRegex(ValueError, "Historical"):
                module.require_calibrated(self.design, "8ffdc943d8a3cc57ad8212320a0fea586609c6da", "43865738891", 1)
            with self.assertRaisesRegex(ValueError, "Historical"):
                module.require_calibrated(self.design, renderer.BASELINE, STRUCTURAL_RUN, 1)

    def test_malformed_attempt_tokens_never_repaired(self):
        for invalid in (None, True, False, 0, -1, 1.0, "0", "01", "+1", "1.0", " 1", "1 ", "1\n", "１"):
            for module in (renderer, auditor):
                with self.subTest(value=invalid, module=module.__name__):
                    with self.assertRaises(ValueError):
                        module.require_calibrated(self.design, STRUCTURAL_COMMIT, STRUCTURAL_RUN, invalid)
        for valid in (1, "1", 2, "2"):
            self.assertEqual(engine.canonical_run_attempt(valid, "structural"), reference.canonical_run_attempt(valid, "structural"))

    def test_malformed_literal_source_hashes_and_run_pins_rejected(self):
        for token in ("0" * 63, "A" * 64, "0" * 64 + "\n", True, "" ):
            self.rejects_design(lambda d, t=token: d["slots"][0].update(primarySourceSHA256=t))
        for token in ("01", "+2", " 2", 2, True):
            self.rejects_design(lambda d, t=token: d["captureBinding"].update(workflowRun=t))

    def test_missing_required_native_sources_and_v3_schema_rejected(self):
        # Deliberately NOT a synthetic provenance PASS. This object cannot pass
        # the V4 header gate, even if a historical artifact has green metadata.
        for value in ({}, {"schema_version": 1, "creative_revision": 3}, {"schema_version": 2, "creative_revision": 4, "status": "FAIL"}):
            with self.assertRaises(ValueError):
                renderer.validate_provenance(value, STRUCTURAL_COMMIT, STRUCTURAL_RUN, 1)

    def test_comparison_must_be_disclosed_two_real_sources_not_native_split_ui(self):
        self.rejects_design(lambda d: d["slots"][8]["editorComparison"].update(nativeSideBySideClaim=True))
        self.rejects_design(lambda d: d["slots"][8]["editorComparison"].update(kind="native-split-view"))
        self.rejects_design(lambda d: d["slots"][8]["editorComparison"].update(labels=["Bad", "Better"]))
        self.rejects_design(lambda d: d["slots"][8]["editorComparison"].update(disclosure=""))
        self.rejects_design(lambda d: d["slots"][8]["editorComparison"].update(sourceBefore="screenshots/concept-a-editor.png"))
        self.rejects_design(lambda d: d["slots"][8]["editorComparison"]["layout"].update(shadowAlpha=32))

    def test_comparison_equal_crop_geometry_and_scale_never_native_upscale(self):
        # Coordinates are abstract unit geometry only, not calibration or evidence.
        value = copy.deepcopy(self.design["slots"][8]["editorComparison"])
        for crop, box in (([10, 210, 810, 810], [200, 1300, 1000, 1900]),
                          ([10, 210, 110, 310], [200, 1300, 1000, 1900]),
                          ([10, 210, 1000, 400], [200, 1300, 999, 1800])):
            value.update(photoCrop=crop, targetBox=box)
            result = renderer.comparison_geometry(value)
            self.assertEqual(result, auditor.comparison_geometry(value))
            self.assertLessEqual(result["nativeScale"], 1)
            self.assertEqual(engine.wh(result["photoTargets"][0]), engine.wh(result["photoTargets"][1]))
            for target in result["photoTargets"]:
                self.assertTrue(engine.inside(target, box))
                self.assertTrue(all(actual <= original for actual, original in zip(engine.wh(target), engine.wh(crop))))
        value.update(targetBox=[200, 1300, 220, 1320])
        for module in (renderer, auditor):
            with self.assertRaises(ValueError):
                module.comparison_geometry(value)

    def test_preview_geometry_is_independently_single_row_and_spatially_ordered(self):
        for kind, ids in (("overview", list(range(1, 11))), ("search", [1, 2, 3])):
            result = reference.preview_geometry(self.design, kind)
            self.assertEqual(result["slotIds"], ids)
            self.assertEqual(result["rows"], 1)
            self.assertEqual(len({c["targetGeometry"][1] for c in result["cells"]}), 1)
            left = [c["targetGeometry"][0] for c in result["cells"]]
            self.assertEqual(left, sorted(left))
        self.assertEqual(reference.preview_geometry(self.design, "search")["width"], 390)
        self.rejects_design(lambda d: d["previews"]["overview"].update(columns=5))
        self.rejects_design(lambda d: d["previews"]["search"].update(slotIds=[3, 2, 1]))
        self.rejects_design(lambda d: d["previews"]["search"].update(gap=12))

    def test_preview_manifest_false_geometry_rejected_before_file_read(self):
        outputs = [{"slot": n, "file": f"{n:02d}-unit-not-an-export.png"} for n in range(1, 11)]
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT, prefix="v4-structure-preview-") as tmp:
            for mutation in (lambda r: r.update(rows=2), lambda r: r["cells"].reverse(), lambda r: r.update(width=r["width"] + 1)):
                rows = [{"kind": kind, **reference.preview_geometry(self.design, kind)} for kind in ("overview", "search")]
                mutation(rows[0])
                with self.assertRaisesRegex(ValueError, "geometry"):
                    reference.verify_previews(Path(tmp), rows, outputs, self.design)

    def test_duplicate_and_nonfinite_json_rejected(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT, prefix="v4-structure-json-") as tmp:
            path = Path(tmp) / "structural-only.json"
            for raw in ('{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}', '[]'):
                path.write_text(raw, encoding="utf-8")
                for module, fn in ((renderer, renderer.read_json), (auditor, auditor.load)):
                    with self.subTest(raw=raw, module=module.__name__):
                        with self.assertRaises(ValueError):
                            fn(path)

    def test_path_traversal_and_noncanonical_sources_rejected(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT, prefix="v4-structure-path-") as tmp:
            for token in ("../x.png", "/x.png", "a\\x.png", "C:/x.png", "./x.png", "a//x.png", "a/../x.png", ""):
                with self.assertRaises((ValueError, OSError)):
                    auditor.source_path(Path(tmp), token)

    def rectangle_layer(self, root, *, wordmark=False):
        # A pure color/alpha unit rectangle, explicitly NOT native UI or provenance.
        if wordmark:
            image = Image.new("RGBA", (120, 70))
            ImageDraw.Draw(image).rectangle([5, 5, 114, 64], fill=(31, 42, 53, 255))
            ImageDraw.Draw(image).rectangle([8, 8, 111, 61], fill=(72, 93, 104, 180))
            source_name, layer_id, crop, target, scale = "branding/native-wordmark.png", "native-wordmark", [5, 5, 115, 65], [70, 78, 125, 108], .5
        else:
            image = Image.new("RGB", renderer.SIZE, (40, 90, 150))
            source_name, layer_id, crop, target, scale = "structural-only-rectangle.png", "editor-original-photo", [200, 300, 600, 700], [200, 1200, 400, 1400], .5
        path = Path(root) / source_name
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path, format="PNG", icc_profile=engine.srgb_profile())
        normalized, management = engine.normalize_native(image, engine.srgb_profile())
        native = engine.NativeSource(source_name, auditor.digest(path), normalized, image.mode, engine.profile_info(engine.srgb_profile()), {}, management)
        canvas = engine.background(self.design)
        layer = engine.native_layer(canvas, native, crop, target, scale, 0, None, layer_id)
        return canvas, layer

    def test_pure_rectangle_pixel_negative_control_not_native_source_pass(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT, prefix="v4-structure-pixels-") as tmp:
            canvas, layer = self.rectangle_layer(tmp)
            proof = renderer.verify_native_pixels(canvas, [layer])[0]
            count = auditor.verify_pixels(canvas, Path(tmp), proof, [], self.design)
            self.assertEqual(count, 200 * 200)
            changed = canvas.copy()
            changed.putpixel((230, 1230), (41, 90, 150))
            with self.assertRaisesRegex(ValueError, "pixels changed"):
                renderer.verify_native_pixels(changed, [layer])
            with self.assertRaisesRegex(ValueError, "pixel mismatch"):
                auditor.verify_pixels(changed, Path(tmp), proof, [], self.design)
            altered = copy.deepcopy(proof)
            altered["nativeScale"] = 1.01
            with self.assertRaisesRegex(ValueError, "upscale"):
                auditor.verify_pixels(canvas, Path(tmp), altered, [], self.design)

    def test_original_alpha_resample_negative_control_is_structural_only(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT, prefix="v4-structure-alpha-") as tmp:
            canvas, layer = self.rectangle_layer(tmp, wordmark=True)
            proof = renderer.verify_native_pixels(canvas, [layer])[0]
            self.assertGreater(auditor.verify_pixels(canvas, Path(tmp), proof, [], self.design), 100)
            changed = canvas.copy()
            changed.putpixel((90, 90), (1, 2, 3))
            with self.assertRaises(ValueError):
                auditor.verify_pixels(changed, Path(tmp), proof, [], self.design)

    def test_frame_ring_negative_control_without_a_phone_or_ui(self):
        geometry = renderer.phone_geometry(self.design)
        device = self.design["layout"]["device"]
        frame, screen = geometry["fullFrameGeometry"], geometry["fullTargetGeometry"]
        canvas = engine.background(self.design)
        canvas.paste(device["frameColor"], frame, engine.rounded_mask(engine.wh(frame), 124))
        # Empty interior is a geometry test, NOT a rendered native phone.
        canvas.paste("#112233", screen, engine.rounded_mask(engine.wh(screen), 115))
        proof = engine.verify_frame_pixels(canvas, self.design)
        self.assertGreater(auditor.verify_frame(canvas, self.design, proof), 1000)
        changed = canvas.copy()
        changed.putpixel((123, 1400), (255, 0, 0))
        with self.assertRaises(ValueError):
            auditor.verify_frame(changed, self.design, proof)

    def test_gesture_pixel_reconstruction_and_negative_control(self):
        canvas = engine.background(self.design)
        geometry = renderer.phone_geometry(self.design)
        frame = geometry["fullFrameGeometry"]
        engine.shadow(canvas, frame, engine.rounded_mask(engine.wh(frame), 124), self.design["layout"]["device"])
        plans = engine.layout_plan(self.design, self.fonts)[0]["gestures"]
        for gesture in plans:
            color = self.design["colors"][gesture["color"]]
            engine.draw_arrow(canvas, gesture["arrowBox"], gesture["direction"], color)
            engine.draw_text(canvas, gesture["textPlan"], color)
        row = {"slot": 1, "gestures": [{**g, "textPlan": engine.public_text_plan(g["textPlan"])} for g in plans]}
        auditor.verify_gestures(canvas, row, self.design, self.fonts)
        changed = canvas.copy()
        changed.putpixel((90, 760), (255, 0, 255))
        with self.assertRaisesRegex(ValueError, "pixels mismatch"):
            auditor.verify_gestures(changed, row, self.design, self.fonts)

    def test_auditor_does_not_import_renderer_or_mutate_legacy(self):
        tree = ast.parse((ROOT / "scripts/store/audit_concept_a_v4.py").read_text(encoding="utf-8"))
        imported = [node.module for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)]
        imported += [name.name for node in ast.walk(tree) if isinstance(node, ast.Import) for name in node.names]
        self.assertFalse(any(name and "render_concept" in name for name in imported))
        for path in ("scripts/store/render_concept_a_v4.py", "scripts/store/audit_concept_a_v4.py"):
            parsed = ast.parse((ROOT / path).read_text(encoding="utf-8"))
            for node in ast.walk(parsed):
                if isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
                    targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                    for target in targets:
                        if isinstance(target, ast.Attribute) and isinstance(target.value, ast.Name):
                            self.assertNotIn(target.value.id, {"engine", "reference"})

    def test_cli_renderer_and_auditor_fail_closed_without_any_source_or_output(self):
        # Both CLIs read only a temporary explicitly UNAPPROVED config. Invalid
        # structural pins are not represented as a capture result or provenance.
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT, prefix="v4-structure-cli-") as tmp:
            tmp = Path(tmp)
            design = copy.deepcopy(self.design)
            design["captureBinding"]["approved"] = False
            design["finalSourceVisualQA"]["approved"] = False
            path = tmp / "unapproved-v4.json"
            path.write_text(json.dumps(design), encoding="utf-8")
            sources, output = tmp / "NO-NATIVE-SOURCES", tmp / "NO-EXPORTS"
            common = ["--design", str(path), "--sources", str(sources), "--expected-commit", STRUCTURAL_COMMIT,
                      "--expected-workflow-run", STRUCTURAL_RUN, "--expected-run-attempt", "1"]
            commands = [[sys.executable, str(ROOT / "scripts/store/render_concept_a_v4.py"), *common, "--output", str(output)],
                        [sys.executable, str(ROOT / "scripts/store/audit_concept_a_v4.py"), *common, "--render", str(output)]]
            env = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1", "TEMP": str(TEMP_ROOT), "TMP": str(TEMP_ROOT), "TMPDIR": str(TEMP_ROOT)}
            for cmd in commands:
                result = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=60)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                value = json.loads(result.stdout)
                self.assertIn("UNAPPROVED", value["error"])
                self.assertFalse(sources.exists())
                self.assertFalse(output.exists())


class C5ExceptionStructuralTests(unittest.TestCase):
    """STRUCTURAL ONLY, using actual immutable C5 bytes, never fake native PASS.

    Positive controls validate only failed API facts, owner scope, inventory and
    receipt shape. No corrected native report is synthesized; no full exception,
    source VQA, render, final technical/visual or delivery acceptance is asserted.
    """
    @classmethod
    def setUpClass(cls):
        import concept_a_v4_c5_exception as materials
        cls.materials = materials
        cls.design = renderer.read_json(renderer.DEFAULT_DESIGN)
        needed = [materials.RAW_ROOT / "capture_provenance.json", materials.OUTPUT_ROOT / "qa/run-43949822336-readback.json",
                  materials.OUTPUT_ROOT / "qa/c5-owner-decision-20261117.json", materials.OUTPUT_ROOT / "qa/c5-original-artifact-immutable-snapshot.json"]
        if not all(p.is_file() for p in needed):
            raise unittest.SkipTest("Real preserved C5 evidence unavailable; never fabricate replacement native records")
        cls.raw = renderer.read_json(needed[0])
        cls.readback = renderer.read_json(needed[1])
        cls.owner = renderer.read_json(needed[2])
        cls.snapshot = renderer.read_json(needed[3])
        cls.original_hashes = {str(p): auditor.digest(p) for p in needed}
        cls.green_gate_source = cls.green_function_source()

    @staticmethod
    def green_function_source():
        code = Path(collector.__file__).read_text(encoding="utf-8")
        node = next(n for n in ast.parse(code).body if isinstance(n, ast.FunctionDef) and n.name == "validate_exact_attempt_readback")
        return ast.get_source_segment(code, node)

    @classmethod
    def tearDownClass(cls):
        if cls.original_hashes != {p: auditor.digest(Path(p)) for p in cls.original_hashes}:
            raise AssertionError("Structural tests changed immutable original/API/owner/snapshot bytes")
        if cls.green_gate_source != cls.green_function_source():
            raise AssertionError("Ordinary green exact-attempt validator changed during structural controls")

    def reject_readback(self, mutate, *, mutate_provenance=False):
        readback, raw = copy.deepcopy(self.readback), copy.deepcopy(self.raw)
        mutate(raw if mutate_provenance else readback)
        for module in (renderer, auditor):
            with self.subTest(module=module.__name__):
                with self.assertRaises((ValueError, KeyError, TypeError)):
                    module.validate_c5_readback(readback, raw)

    def schema_only_receipt(self):
        # An impossible collector reference to a structural text marker, NOT a
        # fabricated native record/report. Never written or sent to the full gate.
        marker_sha = renderer.sha(b"STRUCTURAL ONLY: not a corrected native collector report")
        receipt = {"schemaVersion": 1, "kind": renderer.C5_KIND, "workflowRun": renderer.C5_RUN, "runAttempt": 1,
            "commit": renderer.C5_COMMIT, "branch": "hermes/store-concept-a-en", "actualWorkflowConclusion": "failure",
            "ownerAuthorization": {"file": "qa/c5-owner-decision-20261117.json", "sha256": renderer.C5_OWNER_SHA},
            "originalInventory": {"file": "qa/c5-original-artifact-immutable-snapshot.json", "sha256": renderer.C5_INVENTORY_SHA},
            "originalProvenanceSHA256": renderer.C5_ORIGINAL_SHA, "originalErrors": copy.deepcopy(renderer.C5_ERRORS),
            "exactAttemptReadback": {"file": "run-43949822336-readback.json", "sha256": renderer.C5_READBACK_SHA},
            "correctedCollector": {"file": "capture_provenance.json", "sha256": marker_sha, "scope": "C5-retained-native-evidence-and-local-revalidation",
                "fixtureRoot": TEMP_ROOT.resolve().as_posix(), "codeSHA256": self.materials.current_code_hashes(),
                "auditsSHA256": marker_sha, "sourceHashesSHA256": marker_sha}}
        binding = {"commit": renderer.C5_COMMIT, "workflowRun": renderer.C5_RUN, "runAttempt": "1", "provenanceSHA256": marker_sha,
                   "exactAttemptReadback": copy.deepcopy(receipt["exactAttemptReadback"])}
        return receipt, binding, marker_sha

    def test_actual_failed_c5_api_facts_agree_without_claiming_workflow_success(self):
        self.assertEqual(auditor.digest(self.materials.OUTPUT_ROOT / "qa/run-43949822336-readback.json"), renderer.C5_READBACK_SHA)
        self.assertEqual(auditor.digest(self.materials.RAW_ROOT / "capture_provenance.json"), renderer.C5_ORIGINAL_SHA)
        actual = renderer.validate_c5_readback(self.readback, self.raw)
        self.assertEqual(actual, auditor.validate_c5_readback(self.readback, self.raw))
        self.assertEqual(actual["actual_workflow_conclusion"], "failure")
        self.assertIs(actual["workflow_success"], False)
        self.assertNotIn("status", actual)  # Facts alone cannot be accepted source PASS.
        self.assertEqual(actual["failed_postcapture_step"]["number"], 9)
        self.assertEqual(self.raw["status"], "FAIL")
        self.assertEqual(self.raw["errors"], renderer.C5_ERRORS)

    def test_actual_owner_scope_does_not_grant_capture_or_source_visual_approval(self):
        self.assertEqual(auditor.digest(self.materials.OUTPUT_ROOT / "qa/c5-owner-decision-20261117.json"), renderer.C5_OWNER_SHA)
        for module in (renderer, auditor):
            module.validate_c5_owner_authorization(self.owner, self.materials.DERIVED_ROOT)
            with self.assertRaises(ValueError):
                module.validate_c5_owner_authorization(self.owner, self.materials.RAW_ROOT)
        self.assertIs(self.owner["source_approval"], False)
        self.assertIs(self.owner["additional_native_run_authorized"], False)

    def test_missing_owner_wrong_owner_attempt_and_overbroad_permission_rejected(self):
        changes = [lambda v: v.pop("failed_workflow_exception_authorized"), lambda v: v.update(failed_workflow_exception_authorized=False),
            lambda v: v.update(failed_workflow_exception_authorized=1), lambda v: v.update(source_approval=True),
            lambda v: v.update(additional_native_run_authorized=True), lambda v: v.update(attempt=2), lambda v: v.update(attempt=True),
            lambda v: v.update(run="43949822337"), lambda v: v.update(capture_commit="f" * 40), lambda v: v.update(workflow_conclusion_preserved="success"),
            lambda v: v.update(quoted_offer="generic continue"), lambda v: v.update(restrictions=[]), lambda v: v.update(unknown=True)]
        for mutate in changes:
            owner = copy.deepcopy(self.owner)
            mutate(owner)
            for module in (renderer, auditor):
                with self.subTest(module=module.__name__, change=changes.index(mutate)):
                    with self.assertRaises((ValueError, KeyError, TypeError)):
                        module.validate_c5_owner_authorization(owner, self.materials.DERIVED_ROOT)
        for module in (renderer, auditor):
            with self.assertRaises(ValueError):
                module.validate_c5_owner_authorization(None, self.materials.DERIVED_ROOT)

    def test_ordinary_green_gate_remains_closed_to_c5_by_default_or_explicit_null(self):
        with self.assertRaisesRegex(ValueError, "completed/success"):
            collector.validate_exact_attempt_readback(self.readback, self.raw)
        for use_null in (False, True):
            design = copy.deepcopy(self.design)
            design["captureBinding"].pop("workflowException", None)
            if use_null:
                design["captureBinding"]["workflowException"] = None
            design["captureBinding"]["exactAttemptReadback"] = {"file": "run-43949822336-readback.json", "sha256": renderer.C5_READBACK_SHA}
            for module in (renderer, auditor):
                self.assertEqual(module.capture_policy(design), "single-new-green-v4-stock-only-run")
                with self.assertRaisesRegex(ValueError, "completed/success"):
                    module.verify_workflow_binding(design, self.materials.OUTPUT_ROOT / "qa", self.raw)

    def test_exception_pointer_closed_schema_and_unapproved_capture_still_blocks(self):
        for bad in (True, {}, {"file": "qa/allow-failed.json", "sha256": "0" * 64},
                    {"file": "qa/c5-postcapture-workflow-exception.json", "sha256": None},
                    {"file": "qa/c5-postcapture-workflow-exception.json", "sha256": "A" * 64},
                    {"file": "qa/c5-postcapture-workflow-exception.json", "sha256": "0" * 64, "allowFailed": True}):
            design = copy.deepcopy(self.design)
            design["captureBinding"]["workflowException"] = bad
            for module in (renderer, auditor):
                with self.assertRaises((ValueError, KeyError, TypeError)):
                    module.validate_design(design)
        design = copy.deepcopy(self.design)
        design["captureBinding"]["workflowException"] = {"file": "qa/c5-postcapture-workflow-exception.json", "sha256": "0" * 64}
        design["captureBinding"]["approved"] = False
        design["finalSourceVisualQA"]["approved"] = False
        for module in (renderer, auditor):
            module.validate_design(design)
            self.assertEqual(module.capture_policy(design), "single-C5-owner-authorized-postcapture-exception")
            with self.assertRaisesRegex(ValueError, "UNAPPROVED"):
                module.require_calibrated(design, renderer.C5_COMMIT, renderer.C5_RUN, 1)
            for commit, run, attempt in ((renderer.C5_COMMIT, renderer.C5_RUN, 2),
                                         (renderer.C5_COMMIT, "43949822337", 1), (STRUCTURAL_COMMIT, renderer.C5_RUN, 1)):
                with self.assertRaisesRegex(ValueError, "C5 exception cannot authorize"):
                    module.require_calibrated(design, commit, run, attempt)
        # A C5 exception is not an independent source-VQA bypass either.
        design["captureBinding"].update(approved=True, commit=renderer.C5_COMMIT, workflowRun=renderer.C5_RUN,
            runAttempt=1, provenanceSHA256="0" * 64,
            exactAttemptReadback={"file": "run-43949822336-readback.json", "sha256": renderer.C5_READBACK_SHA})
        for module in (renderer, auditor):
            with self.assertRaisesRegex(ValueError, "VQA"):
                module.require_calibrated(design, renderer.C5_COMMIT, renderer.C5_RUN, 1)

    def test_wrong_attempt_malformed_api_integer_and_third_run_rejected(self):
        for value in (2, 3, True, "1", "01", 1.0, None):
            self.reject_readback(lambda r, v=value: r["attempt_readback"].update(run_attempt=v))
        for value in ("2", "3", 1, True, "01", "1\n"):
            self.reject_readback(lambda p, v=value: p.update(run_attempt=v), mutate_provenance=True)
        self.reject_readback(lambda r: r["attempt_readback"].update(id=43949822337))
        self.reject_readback(lambda p: p.update(workflow_run="43949822337"), mutate_provenance=True)
        self.reject_readback(lambda r: r["attempt_jobs_readback"]["jobs"][0].update(run_attempt=2))
        self.reject_readback(lambda r: r["run"].update(runAttempt=2, conclusion="success"))

    def test_altered_commit_branch_workflow_or_artifact_rejected(self):
        self.reject_readback(lambda r: r["attempt_readback"].update(head_sha="f" * 40))
        self.reject_readback(lambda p: p.update(commit="f" * 40), mutate_provenance=True)
        self.reject_readback(lambda r: r["attempt_readback"].update(head_branch="main"))
        self.reject_readback(lambda r: r["attempt_readback"].update(workflow_id=389136992))
        self.reject_readback(lambda r: r["attempt_readback"].update(jobs_url=r["attempt_readback"]["url"] + "/jobs"))
        self.reject_readback(lambda r: r["artifacts"]["artifacts"][0].update(name="galeriq-C6-not-C5"))
        self.reject_readback(lambda r: r["artifacts"]["artifacts"][0].update(digest="sha256:" + "0" * 64))

    def test_only_one_failed_postcapture_step_no_skips_pending_or_failed_capture(self):
        for index in (4, 7, 9):
            self.reject_readback(lambda r, i=index: r["attempt_jobs_readback"]["jobs"][0]["steps"][i].update(conclusion="failure"))
        for conclusion in ("skipped", "cancelled", None):
            self.reject_readback(lambda r, v=conclusion: r["attempt_jobs_readback"]["jobs"][0]["steps"][7].update(conclusion=v))
        self.reject_readback(lambda r: r["attempt_jobs_readback"]["jobs"][0]["steps"][7].update(status="in_progress", conclusion=None))
        self.reject_readback(lambda r: r["attempt_readback"].update(status="in_progress", conclusion=None))
        self.reject_readback(lambda r: r["attempt_jobs_readback"]["jobs"][0]["steps"][8].update(name="Other postcapture failure"))
        self.reject_readback(lambda r: r["attempt_jobs_readback"]["jobs"][0]["steps"][7].update(completed_at="2026-11-16T21:04:00Z"))
        self.reject_readback(lambda r: r["attempt_jobs_readback"].update(total_count=2))
        self.reject_readback(lambda r: r["attempt_jobs_readback"]["jobs"][0]["steps"].pop())
        self.reject_readback(lambda r: r["actual_native_capture_test"].update(skipped=1))
        self.reject_readback(lambda r: r["actual_native_capture_test"].update(passed=True))

    def test_receipt_shape_controls_not_a_native_report_or_source_approval(self):
        receipt, binding, marker_sha = self.schema_only_receipt()
        for module in (renderer, auditor):
            self.assertIsNone(module.validate_c5_receipt(receipt, binding, marker_sha))
        changes = [lambda v: v.pop("ownerAuthorization"), lambda v: v.update(runAttempt=2), lambda v: v.update(runAttempt=True),
            lambda v: v.update(workflowRun="43949822337"), lambda v: v.update(commit="f" * 40),
            lambda v: v["ownerAuthorization"].update(sha256="0" * 64), lambda v: v["originalInventory"].update(sha256="0" * 64),
            lambda v: v.update(originalProvenanceSHA256="0" * 64), lambda v: v.update(originalErrors=[]),
            lambda v: v["exactAttemptReadback"].update(sha256="0" * 64), lambda v: v["correctedCollector"].update(scope="workflow-success"),
            lambda v: v["correctedCollector"].update(unknown=True), lambda v: v.update(allowFailed=True)]
        for mutate in changes:
            value = copy.deepcopy(receipt)
            mutate(value)
            for module in (renderer, auditor):
                with self.assertRaises((ValueError, KeyError, TypeError)):
                    module.validate_c5_receipt(value, binding, marker_sha)
        for module in (renderer, auditor):
            with self.assertRaises(ValueError):
                module.validate_c5_receipt(receipt, binding, "0" * 64)

    def test_changed_saved_readback_bytes_or_missing_owner_file_cannot_be_read(self):
        design = copy.deepcopy(self.design)
        design["captureBinding"].pop("workflowException", None)
        design["captureBinding"]["exactAttemptReadback"] = {"file": "run-43949822336-readback.json", "sha256": "0" * 64}
        for module in (renderer, auditor):
            with self.assertRaisesRegex(ValueError, "bytes changed"):
                module.verify_workflow_binding(design, self.materials.OUTPUT_ROOT / "qa", self.raw)
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT, prefix="v4-c5-structure-missing-") as temp:
            with self.assertRaisesRegex(ValueError, "Missing"):
                self.materials.bound_json(Path(temp), {"file": "missing-owner.json", "sha256": renderer.C5_OWNER_SHA}, renderer.read_json)

    def test_real_full_228_file_inventory_and_unchanged_derived_capture_inputs(self):
        self.assertEqual(auditor.digest(self.materials.OUTPUT_ROOT / "qa/c5-original-artifact-immutable-snapshot.json"), renderer.C5_INVENTORY_SHA)
        result = self.materials.verify_immutable_inventory(self.snapshot, self.materials.DERIVED_ROOT)
        self.assertEqual(result["original_files_verified"], 228)
        self.assertEqual(result["unchanged_derived_inputs_verified"], 227)
        altered = copy.deepcopy(self.snapshot)
        altered["files"]["summary.json"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "original C5 bytes changed"):
            self.materials.verify_immutable_inventory(altered, self.materials.DERIVED_ROOT)

    def test_original_fail_or_unsupported_local_status_never_qualifies_as_corrected_pass(self):
        for status in ("FAIL", "PASS_WITH_EXCEPTION", "PASS_WITH_OWNER_EXCEPTION", "NOT RUN"):
            raw = copy.deepcopy(self.raw)
            raw["status"] = status
            with self.assertRaisesRegex(ValueError, "corrected LOCAL collector must PASS"):
                self.materials.recompute_local_data(self.materials.DERIVED_ROOT, TEMP_ROOT, raw, self.raw)

    def test_helper_has_no_capture_or_collector_write_path_and_auditor_stays_independent(self):
        tree = ast.parse(Path(self.materials.__file__).read_text(encoding="utf-8"))
        calls = [n.func.attr if isinstance(n.func, ast.Attribute) else n.func.id for n in ast.walk(tree)
                 if isinstance(n, ast.Call) and isinstance(n.func, (ast.Attribute, ast.Name))]
        self.assertFalse(set(calls) & {"collect", "run_legacy", "write_text", "write_bytes", "render_all", "render_one", "goto_url"})
        for path in (Path(auditor.__file__), Path(self.materials.__file__)):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            imports = [n.module for n in ast.walk(tree) if isinstance(n, ast.ImportFrom)]
            imports += [a.name for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names]
            self.assertFalse(any(n and "render_concept" in n for n in imports))


if __name__ == "__main__":
    print("STRUCTURAL ONLY: no native capture, no native source approval, no final export/visual/delivery PASS.", flush=True)
    unittest.main(verbosity=2)
