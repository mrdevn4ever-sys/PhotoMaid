"""Executable source-contract checks, NOT Swift/iOS runtime or compiler tests.

Run: python -m unittest discover -s scripts/tests -v
These assertions intentionally protect the isolated remodel's original main snapshot.
"""
from pathlib import Path
import json
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
BASE = "ca6f81850a0a4032bbf8093f241f99a7584ab4c6"


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def original(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)


def contrast(a, b):
    def luminance(value):
        rgb = [(value >> shift & 255) / 255 for shift in (16, 8, 0)]
        linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
        return sum(v * w for v, w in zip(linear, (0.2126, 0.7152, 0.0722)))
    x, y = sorted((luminance(a), luminance(b)))
    return (y + 0.05) / (x + 0.05)


class RemodelSourceContractTests(unittest.TestCase):
    def test_work_is_on_experiment_branch(self):
        branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
        self.assertTrue(branch.startswith("experiment/photomaid-liquid-glass-remodel"))

    def test_main_ref_has_not_moved(self):
        self.assertEqual(subprocess.check_output(["git", "rev-parse", "main"], cwd=ROOT, text=True).strip(), BASE)

    def test_all_typed_destinations_are_preserved(self):
        self.assertEqual((ROOT / "PhotoMaid/App/Routes.swift").read_text(encoding="utf-8").encode("utf-8"), original("PhotoMaid/App/Routes.swift"))

    def test_gesture_engine_and_fixed_mappings_are_unchanged(self):
        path = "Sources/PhotoMaidCore/Feed/FeedGestureMachine.swift"
        self.assertEqual((ROOT / path).read_text(encoding="utf-8").encode("utf-8"), original(path))

    def test_persistence_schema_and_settings_are_unchanged(self):
        paths = ["PhotoMaid/Persistence/PhotoMaid.xcdatamodeld/PhotoMaid 1.xcdatamodel/contents",
                 "PhotoMaid/Persistence/PhotoMaid.xcdatamodeld/.xccurrentversion",
                 "PhotoMaid/Persistence/AppSettings.swift", "PhotoMaid/Persistence/CoreDataStore.swift"]
        for path in paths:
            with self.subTest(path=path):
                self.assertEqual((ROOT / path).read_text(encoding="utf-8").encode("utf-8"), original(path))

    def test_purchase_and_final_deletion_rules_unchanged(self):
        for path in ["Sources/PhotoMaidCore/Capabilities/Capabilities.swift",
                     "PhotoMaid/Infrastructure/Purchases/StoreKitGateway.swift",
                     "PhotoMaid/Features/Cleanup/TrashView.swift"]:
            with self.subTest(path=path):
                self.assertEqual((ROOT / path).read_text(encoding="utf-8").encode("utf-8"), original(path))

    def test_no_signing_dependency_or_workflow_changes(self):
        for path in ["project.yml", "Package.swift", "Package.resolved", "PhotoMaid/App/PhotoMaid.entitlements",
                     ".github/workflows/ci.yml", ".github/workflows/testflight.yml"]:
            with self.subTest(path=path):
                self.assertEqual((ROOT / path).read_text(encoding="utf-8").encode("utf-8"), original(path))
        self.assertEqual({p.name for p in (ROOT / ".github/workflows").iterdir()}, {"ci.yml", "testflight.yml"})

    def test_original_five_tabs_keep_independent_stacks(self):
        root = source("PhotoMaid/App/RootView.swift")
        self.assertEqual(set(re.findall(r"value: AppTab\.(\w+)", root)), {"today", "library", "cleanup", "studio", "history"})
        self.assertIn("app.paths[tab]", root)
        self.assertIn(".tabBarMinimizeBehavior(.never)", root)

    def test_studio_entry_labels_preserved(self):
        old = original("PhotoMaid/Features/Studio/StudioView.swift").decode()
        new = source("PhotoMaid/Features/Studio/StudioView.swift")
        for title in re.findall(r'studioButton\("[^"]+", "([^"]+)"', old):
            with self.subTest(title=title):
                self.assertIn('"' + title + '"', new)

    def test_cleanup_exposes_trash_and_later_without_deleting(self):
        hub = source("PhotoMaid/Features/Cleanup/CleanUpHubView.swift")
        section = hub.split("private var reviewDestinations:", 1)[1].split("@ViewBuilder", 1)[0]
        self.assertIn("app.navigate(.trash, in: .cleanup)", section)
        self.assertIn("app.navigate(.later, in: .cleanup)", section)
        self.assertNotIn("deleteAssets", section)
        self.assertNotIn("perform(", section)

    def test_accessibility_grids_do_not_have_fixed_minimum_width(self):
        for path in ["PhotoMaid/Features/Studio/StudioView.swift", "PhotoMaid/Features/Cleanup/CleanUpHubView.swift"]:
            text = source(path)
            self.assertRegex(text, r"typeSize\.isAccessibilitySize\s*\?\s*\[GridItem\(\.flexible\(\)\)\]")

    def test_feature_tiles_have_no_caption_truncation_or_fake_action(self):
        chrome = source("PhotoMaid/DesignSystem/FeatureChrome.swift")
        self.assertIn("Button(action: action)", chrome)
        self.assertNotIn(".lineLimit(", chrome)
        self.assertIn(".accessibilityReduceMotion", chrome)
        self.assertIn(".fixedSize(horizontal: false, vertical: true)", chrome)

    def test_inactive_root_and_fullscreen_cover_are_shielded(self):
        root = source("PhotoMaid/App/RootView.swift")
        self.assertIn("private var shielded: Bool { scenePhase != .active }", root)
        full = root.split("struct FullScreenHost:", 1)[1].split("struct StartupErrorView:", 1)[0]
        for guard in ["if scenePhase != .active", "PrivacyShield()", ".privacySensitive()", ".allowsHitTesting(scenePhase == .active)"]:
            self.assertIn(guard, full)
        self.assertIn("if !shielded, let toast", root)

    def test_thumbnail_tasks_guard_late_results_and_reset_cells(self):
        text = source("PhotoMaid/DesignSystem/Components.swift")
        for name in ["struct AssetThumbnail:", "struct AssetCell:"]:
            section = text.split(name, 1)[1].split("\n}", 1)[0]
            self.assertIn("image = nil", section)
            self.assertIn("guard !Task.isCancelled else { return }", section)
            self.assertIn("scale)", section)

    def test_thumbnail_cache_has_count_and_cost_budget(self):
        text = source("PhotoMaid/DesignSystem/Components.swift")
        self.assertIn("cache.countLimit = 600", text)
        self.assertIn("cache.totalCostLimit = 64 * 1_024 * 1_024", text)
        self.assertIn("cost: cost", text)

    def test_glass_has_opaque_accessibility_fallbacks(self):
        glass = source("PhotoMaid/DesignSystem/Glass.swift")
        self.assertGreaterEqual(glass.count("reduceTransparency || contrast == .increased"), 3)
        self.assertIn("content.buttonStyle(.borderedProminent)", glass)

    def test_new_design_strings_exist_in_all_catalog_locales(self):
        strings = json.loads(source("PhotoMaid/Resources/Localizable.xcstrings"))["strings"]
        paths = ["PhotoMaid/DesignSystem/FeatureChrome.swift", "PhotoMaid/Features/Studio/StudioView.swift"]
        for path in paths:
            keys = re.findall(r'\bL\("([^"]+)"', source(path))
            for key in keys:
                with self.subTest(key=key):
                    self.assertIn(key, strings)
                    self.assertEqual(len(strings[key]["localizations"]), 16)

    def test_standard_text_and_blue_accent_contrast(self):
        tokens = source("PhotoMaid/DesignSystem/Tokens.swift")
        roles = {}
        for name, args in re.findall(r"static let (\w+) = dynamic\(([^\n]+)\)", tokens):
            roles[name] = [int(x, 16) for x in re.findall(r"0x([0-9A-Fa-f]+)", args)]
        for mode in range(4):
            for role in ["textPrimary", "textSecondary", "accent"]:
                for surface in ["background", "surface"]:
                    with self.subTest(mode=mode, role=role, surface=surface):
                        self.assertGreaterEqual(contrast(roles[role][mode], roles[surface][mode]), 4.5)
            self.assertGreaterEqual(contrast(0xFFFFFF, roles["accentFill"][mode]), 4.5)

    def test_existing_swift_tests_are_not_removed(self):
        for path in ["Tests/PhotoMaidCoreTests/GestureMachineTests.swift", "Tests/PhotoMaidCoreTests/FeedSessionTests.swift"]:
            before = set(re.findall(r"func (\w+)\(", original(path).decode()))
            after = set(re.findall(r"func (\w+)\(", source(path)))
            self.assertTrue(before <= after, before - after)


if __name__ == "__main__":
    unittest.main()
