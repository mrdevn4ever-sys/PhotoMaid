#!/usr/bin/env python3
"""STRUCTURAL ONLY: truthful C5 retained-evidence validation controls.

Uses the actual immutable C5 artifact and actual local prepared fixture. The
positive report is built/recomputed IN MEMORY only. No native run, CI, capture,
environment/plist reconstruction, canonical report write, render or visual
approval is performed. Negative mutations are labelled structural controls,
never replacement native evidence. Disposable altered input-photo bytes live
only in F:/HermesTemp; no raw/derived/source-photo input is changed.
"""
from __future__ import annotations

import ast
import contextlib
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from PIL import Image

import build_concept_a_v4_fixture as builder
import collect_concept_a_v4_provenance as collector
import concept_a_v4_c5_exception as materials

TEMP_ROOT = Path("F:/HermesTemp")
FIXTURE_ROOT = materials.OUTPUT_ROOT / "qa/fixture-v4-c2"
REGISTRY_ROOT = materials.ROOT / "app-store/concepts/A/v4-source-media"
ENV_KEYS = ("GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_REPOSITORY", "GITHUB_REF_NAME", "RUNNER_TEMP")


@contextlib.contextmanager
def forbid_native_collection():
    """Fail if a positive data check tries any real collector/write entrypoint."""
    prohibited = {function.__code__ for function in (
        collector.collect, collector.run_legacy, collector.legacy.main,
        collector.verify_fixture_files, collector._same_manifest_bytes, builder.build_fixture,
    )}
    previous = sys.getprofile()

    def profile(frame, event, arg):
        if event == "call" and frame.f_code in prohibited:
            raise AssertionError("STRUCTURAL control: native/CI collection must never run here")

    sys.setprofile(profile)
    try:
        yield
    finally:
        sys.setprofile(previous)


class C5RetainedStructuralTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if Path(tempfile.gettempdir()).resolve() != TEMP_ROOT.resolve():
            raise RuntimeError("Run with explicit TEMP/TMP/TMPDIR=F:/HermesTemp")
        if any(os.environ.get(key) != value for key, value in (
                ("UV_CACHE_DIR", "F:/HermesCache/uv"), ("PYTHONDONTWRITEBYTECODE", "1"))):
            raise RuntimeError("Explicit F-backed cache/no-bytecode environment required")
        cls.env_before = {key: os.environ.get(key) for key in ENV_KEYS}
        cls.original = builder.load_json(materials.RAW_ROOT / "capture_provenance.json")
        cls.fixture = builder.load_json(materials.RAW_ROOT / "fixture-manifest.json")
        cls.local_fixture = builder.load_json(FIXTURE_ROOT / "fixture-manifest.json")
        cls.snapshot = builder.load_json(materials.OUTPUT_ROOT / "qa/c5-original-artifact-immutable-snapshot.json")
        cls.canonical_before = materials.digest(materials.DERIVED_ROOT / "capture_provenance.json")
        cls.protected_before = {name: materials.digest(materials.ROOT / name) for name in (
            "scripts/store/collect_concept_a_v4_provenance.py", "scripts/store/collect_concept_a_provenance.py",
            "scripts/store/build_concept_a_v4_fixture.py", "scripts/store/test_concept_a_v4_fixture.py",
            "PhotoMaidUITests/AppStoreCaptureTests.swift",
        )}
        cls.collector_source = Path(collector.__file__).read_text(encoding="utf-8")
        cls.captured_source = subprocess.run(["git", "-C", str(materials.ROOT), "show",
            materials.C5_COMMIT + ":scripts/store/collect_concept_a_v4_provenance.py"], check=True,
            capture_output=True, timeout=30).stdout.decode("utf-8")
        start = time.monotonic()
        with forbid_native_collection():
            cls.report = materials.build_postcapture_revalidation_report(materials.DERIVED_ROOT, FIXTURE_ROOT)
        cls.build_seconds = time.monotonic() - start
        print("STRUCTURAL positive actual-data report: " + json.dumps({
            "report_kind": cls.report["report_kind"], "status": cls.report["status"],
            "scope": cls.report["postcapture_revalidation"]["scope"],
            "build_seconds": cls.build_seconds,
        }), flush=True)

    @classmethod
    def tearDownClass(cls):
        if cls.env_before != {key: os.environ.get(key) for key in ENV_KEYS}:
            raise AssertionError("Native CI environment was changed/reconstructed")
        if materials.digest(materials.DERIVED_ROOT / "capture_provenance.json") != cls.canonical_before:
            raise AssertionError("Derived canonical provenance was written during tests")
        if cls.protected_before != {name: materials.digest(materials.ROOT / name) for name in cls.protected_before}:
            raise AssertionError("Ordinary collector/fixture/native harness code changed during tests")
        result = materials.verify_immutable_inventory(cls.snapshot, materials.DERIVED_ROOT)
        if result["original_files_verified"] != 228 or result["unchanged_derived_inputs_verified"] != 227:
            raise AssertionError("Raw/derived inputs were not all preserved")

    def recompute(self, report=None, original=None):
        with forbid_native_collection():
            return materials.recompute_local_data(materials.DERIVED_ROOT, FIXTURE_ROOT,
                self.report if report is None else report, self.original if original is None else original)

    def test_actual_positive_is_targeted_and_preserves_failed_native_run(self):
        report, evidence = self.report, self.report["postcapture_revalidation"]
        self.assertEqual(report["report_kind"], materials.REPORT_KIND)
        self.assertEqual(evidence["scope"], materials.REVALIDATION_SCOPE)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["errors"], [])
        self.assertEqual(self.original["status"], "FAIL")
        self.assertEqual(self.original["errors"], materials.ORIGINAL_ERRORS)
        self.assertEqual(evidence["actual_workflow_conclusion"], "failure")
        self.assertIs(evidence["workflow_success"], False)
        self.assertIs(evidence["fresh_native_collection"], False)
        self.assertIs(evidence["source_or_final_visual_approval_granted"], False)
        self.assertEqual(evidence["original_provenance_sha256"], materials.ORIGINAL_SHA)
        self.assertEqual(evidence["immutable_inventory"]["original_files_verified"], 228)
        self.assertEqual(evidence["immutable_inventory"]["unchanged_derived_inputs_verified"], 227)
        self.assertEqual(evidence["local_35_image_bytechecks"]["actual_files"], 35)
        self.assertEqual(len(evidence["local_35_image_bytechecks"]["files"]), 35)
        self.assertEqual(evidence["local_15_original_checks"]["actual_originals"], 15)
        self.assertEqual(len(evidence["local_15_original_checks"]["files"]), 15)
        self.assertEqual(len(report["outputs"]), 21)
        self.assertEqual(set(report["v4_audits"]), materials.LOCAL_GATE_NAMES)
        self.assertEqual(report["v4_audits"]["native_screens"]["status"], "PASS")
        self.assertEqual(report["v4_audits"]["month_progress"]["status"], "PASS")
        self.assertEqual(report["v4_audits"]["editor_pair"]["status"], "PASS")
        for key in materials.NATIVE_HEADER_FIELDS:
            self.assertTrue(materials._equal_json(report[key], self.original[key]), key)
        for key in ("native_encoded_video_byte_recheck", "native_encoded_video_full_decode_recheck",
                    "native_app_plist_recheck", "native_ci_metadata_recollection"):
            self.assertEqual(evidence[key], "NOT RUN", key)
        self.assertIs(evidence["local_videos_match_native_capture"], False)
        for gate in ("fixture_files", "captured_fixture_manifest_bytes"):
            self.assertEqual(report["v4_audits"][gate], self.original["v4_audits"][gate])
            retained = evidence["retained_native_gates"][gate]
            self.assertEqual(retained["source"]["sha256"], materials.ORIGINAL_SHA)
            self.assertEqual(retained["result"], self.original["v4_audits"][gate])
            self.assertEqual(retained["local_rerun"], "NOT RUN")

    def test_actual_positive_is_independently_recomputed_and_receipt_compatible(self):
        result = self.recompute()
        self.assertEqual(set(result), {"auditsSHA256", "sourceHashesSHA256", "codeSHA256", "localDataStatus", "apiGreenStatus"})
        self.assertEqual(result["auditsSHA256"], materials.json_sha256(self.report["v4_audits"]))
        self.assertEqual(result["codeSHA256"], materials.current_code_hashes())
        source_map = {row["file"]: row["sha256"] for row in self.report["outputs"]}
        source_map[self.report["branding"]["file"]] = self.report["branding"]["sha256"]
        self.assertEqual(result["sourceHashesSHA256"], materials.json_sha256(source_map))
        self.assertEqual(result["localDataStatus"], "PASS")
        self.assertEqual(result["apiGreenStatus"], "NOT RUN")

    def test_no_silent_fallback_to_full_collect_or_old_scope(self):
        for mutation in (
            lambda r: r.pop("report_kind"), lambda r: r.update(report_kind="full-native-collect"),
            lambda r: r.pop("postcapture_revalidation"),
            lambda r: r["postcapture_revalidation"].update(scope="local-data-validation-only"),
            lambda r: r["postcapture_revalidation"].update(scope="full-native-collect-PASS"),
        ):
            report = copy.deepcopy(self.report)
            mutation(report)
            with self.assertRaisesRegex(ValueError, "mode/scope"):
                self.recompute(report)
        for status in ("FAIL", "PASS_WITH_EXCEPTION", "PASS_WITH_OWNER_EXCEPTION", "NOT RUN"):
            report = copy.deepcopy(self.report)
            report["status"] = status
            with self.assertRaisesRegex(ValueError, "corrected LOCAL collector must PASS"):
                self.recompute(report)

    def test_wrong_native_metadata_or_source_header_hash_rejected(self):
        for mutation in (
            lambda r: r["app"].update(CFBundleVersion="999"),
            lambda r: r["device"].update(name="STRUCTURAL wrong device"),
            lambda r: r["capture_summary"].update(totalTestCount=2),
            lambda r: r.update(run_attempt="2"),
            lambda r: r.update(fixture_manifest_sha256="0" * 64),
            lambda r: r["branding"].update(sha256="0" * 64),
        ):
            report = copy.deepcopy(self.report)
            mutation(report)
            with self.assertRaisesRegex(ValueError, "immutable native header"):
                self.recompute(report)

    def test_supplied_original_must_be_exact_pinned_fail(self):
        for mutation in (
            lambda r: r.update(status="PASS", errors=[]),
            lambda r: r["base_c14_provenance"].update(collector_sha256="0" * 64),
            lambda r: r["v4_audits"]["fixture_files"].update(independent_video_full_decode="NOT RUN"),
        ):
            original = copy.deepcopy(self.original)
            mutation(original)
            with self.assertRaisesRegex(ValueError, "exact immutable native C5 report"):
                self.recompute(original=original)

    def test_native_video_local_pass_lies_rejected_independently(self):
        for key, value in (("native_encoded_video_byte_recheck", "PASS"),
                           ("native_encoded_video_full_decode_recheck", "PASS"),
                           ("local_videos_match_native_capture", True)):
            report = copy.deepcopy(self.report)
            report["postcapture_revalidation"][key] = value
            with self.subTest(claim=key):
                with self.assertRaisesRegex(ValueError, "actual read-only recomputation"):
                    self.recompute(report)

    def test_forged_image_source_hash_and_retained_binding_rejected_independently(self):
        for label, mutation in (
            ("source hash", lambda r: r["outputs"][0].update(sha256="0" * 64)),
            ("retained source binding", lambda r: r["postcapture_revalidation"]["retained_native_gates"]["fixture_files"]["source"].update(sha256="0" * 64)),
            ("decoded image hash", lambda r: next(iter(r["postcapture_revalidation"]["local_35_image_bytechecks"]["files"].values())).update(decoded_rgb_sha256="0" * 64)),
        ):
            report = copy.deepcopy(self.report)
            mutation(report)
            with self.subTest(claim=label):
                with self.assertRaisesRegex(ValueError, "actual read-only recomputation"):
                    self.recompute(report)

    def test_deleted_retention_proof_or_added_pass_flag_rejected_independently(self):
        for mutation in (lambda r: r["postcapture_revalidation"].pop("retained_native_gates"),
                         lambda r: r["postcapture_revalidation"].update(allow_unverified_video_PASS=True)):
            report = copy.deepcopy(self.report)
            mutation(report)
            with self.assertRaisesRegex(ValueError, "actual read-only recomputation"):
                self.recompute(report)

    def test_actual_local_mp4_hash_cannot_be_relabelled_as_native_or_unchecked(self):
        local = copy.deepcopy(self.local_fixture)
        local["records"][35]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "LOCAL manifest"):
            materials._verify_local_prepared_files(FIXTURE_ROOT.resolve(), self.fixture, local)
        with self.assertRaisesRegex(ValueError, "exact prepared fixture-manifest bytes"):
            collector._same_manifest_bytes(materials.DERIVED_ROOT, FIXTURE_ROOT)

    def test_manifest_diff_is_exactly_four_video_encoding_measurements(self):
        result = materials._validate_prepared_manifest(self.fixture, self.local_fixture)
        self.assertEqual({row["path"] for row in result}, {f"/records/{n}/{key}" for n in (35, 36) for key in ("bytes", "sha256")})
        for mutation in (
            lambda r: r.update(images=34), lambda r: r["records"][0].update(sha256="0" * 64),
            lambda r: r["records"][0].update(bytes=r["records"][0]["bytes"] + 1),
            lambda r: r["records"][11]["source_crop"].__setitem__(0, r["records"][11]["source_crop"][0] + 1),
            lambda r: r["records"][35]["video"].update(duration=24.0),
            lambda r: r["records"][35]["video"].update(full_decode="NOT RUN"),
            lambda r: r["records"][35].update(source_sha256="0" * 64),
            lambda r: r.update(extra_approval=True),
        ):
            local = copy.deepcopy(self.local_fixture)
            mutation(local)
            with self.assertRaisesRegex(ValueError, "ONLY"):
                materials._validate_prepared_manifest(self.fixture, local)
        with self.assertRaisesRegex(ValueError, "ONLY"):
            materials._validate_prepared_manifest(self.fixture, self.fixture)
        self.assertFalse(materials._equal_json(True, 1))
        self.assertFalse(materials._equal_json(1, 1.0))

    def test_actual_available_jpeg_one_byte_mutation_rejected_without_touching_input(self):
        row = self.fixture["records"][0]
        original_bytes = (FIXTURE_ROOT / row["file"]).read_bytes()
        altered = bytearray(original_bytes)
        altered[len(altered) // 2] ^= 1
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT, prefix="c5-STRUCTURAL-input-photo-") as temporary:
            temporary = Path(temporary).resolve()
            (temporary / row["file"]).write_bytes(altered)
            with self.assertRaisesRegex(ValueError, "exact native fixture bytes"):
                materials._verify_available_images(temporary, {row["file"]: row}, REGISTRY_ROOT)
        self.assertEqual((FIXTURE_ROOT / row["file"]).read_bytes(), original_bytes)

    def test_independent_crop_and_one_pixel_recipe_negatives(self):
        crop_row = copy.deepcopy(self.fixture["records"][11])
        crop_row["source_crop"][0] += 1
        with self.assertRaisesRegex(ValueError, "crop mismatch"):
            materials._expected_image_pixels(crop_row, REGISTRY_ROOT)
        row = self.fixture["records"][0]
        with Image.open(FIXTURE_ROOT / row["file"]) as image:
            altered = image.convert("RGB")
        pixel = altered.getpixel((0, 0))
        altered.putpixel((0, 0), ((pixel[0] + 1) % 256, pixel[1], pixel[2]))
        with patch.object(materials, "_expected_image_pixels", return_value=altered):
            with self.assertRaisesRegex(ValueError, "pixel mismatch"):
                materials._verify_available_images(FIXTURE_ROOT.resolve(), {row["file"]: row}, REGISTRY_ROOT)

    def test_inherited_gate_changes_rejected_from_actual_capture_git_ast(self):
        actual = materials.verify_inherited_gate_code()
        self.assertEqual(set(actual["inherited_function_ast_sha256"]), set(materials.INHERITED_GATES))
        self.assertEqual(actual["legacy_collector_sha256"], materials.LEGACY_SHA)
        for name in materials.INHERITED_GATES:
            tree = ast.parse(self.collector_source)
            node = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == name)
            node.body.insert(0, ast.Return(value=ast.Constant(value="STRUCTURAL bypass, never executed")))
            mutated = ast.unparse(ast.fix_missing_locations(tree))
            with self.subTest(gate=name):
                with self.assertRaisesRegex(ValueError, "gate changed.*" + name):
                    materials._verify_inherited_gate_source(mutated, self.captured_source)
        self.assertEqual(materials._verify_inherited_gate_source(self.collector_source + "\n# STRUCTURAL comment\n", self.captured_source),
                         actual["inherited_function_ast_sha256"])

    def test_exact_green_default_stays_closed_and_raw_cannot_be_revalidated(self):
        readback = builder.load_json(materials.OUTPUT_ROOT / "qa/run-43949822336-readback.json")
        with self.assertRaisesRegex(ValueError, "completed/success"):
            collector.validate_exact_attempt_readback(readback, self.report)
        with self.assertRaisesRegex(ValueError, "raw C5 root"):
            materials.build_postcapture_revalidation_report(materials.RAW_ROOT, FIXTURE_ROOT)
        with self.assertRaisesRegex(ValueError, "raw C5 root"):
            materials.recompute_local_data(materials.RAW_ROOT, FIXTURE_ROOT, self.report, self.original)

    def test_no_writer_env_reconstruction_or_native_collector_call_in_helper(self):
        tree = ast.parse(Path(materials.__file__).read_text(encoding="utf-8"))
        calls = {node.func.attr if isinstance(node.func, ast.Attribute) else node.func.id
                 for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, (ast.Attribute, ast.Name))}
        self.assertFalse(calls & {"collect", "run_legacy", "main", "verify_fixture_files", "_same_manifest_bytes",
                                 "write_text", "write_bytes", "build_fixture", "render_all"})
        self.assertFalse(any(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                             and isinstance(node.func.value, ast.Name) and node.func.value.id == "json"
                             and node.func.attr == "dump" for node in ast.walk(tree)))
        self.assertFalse(any(isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name)
                             and node.value.id == "os" and node.attr in ("environ", "putenv") for node in ast.walk(tree)))
        self.assertEqual(self.env_before, {key: os.environ.get(key) for key in ENV_KEYS})


if __name__ == "__main__":
    print("STRUCTURAL ONLY: real preserved bytes/local data; no native rerun, CI, source/final visual approval or delivery acceptance.", flush=True)
    unittest.main(verbosity=2)
