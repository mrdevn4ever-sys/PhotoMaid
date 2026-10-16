"""Regression cases for repeated ITMS-91064 failures; no Apple services required."""
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

from check_privacy_manifests import audit, inspect_manifest


class PrivacyTrackingTests(unittest.TestCase):
    def check(self, manifest):
        return inspect_manifest("PrivacyInfo.xcprivacy", plistlib.dumps(manifest))

    def test_build10_declaration_fails_until_real_domain_is_added(self):
        original = {"NSPrivacyTracking": True, "NSPrivacyTrackingDomains": []}
        self.assertTrue(self.check(original)["errors"])
        original["NSPrivacyTrackingDomains"] = ["googleads.g.doubleclick.net"]
        self.assertFalse(self.check(original)["errors"])

    def test_domains_require_true_in_the_same_manifest(self):
        for tracking in (False, None):
            manifest = {"NSPrivacyTrackingDomains": ["tracking.example.com"]}
            if tracking is not None:
                manifest["NSPrivacyTracking"] = tracking
            self.assertTrue(self.check(manifest)["errors"])

    def test_vendor_manifest_can_omit_both_tracking_keys(self):
        self.assertFalse(self.check({"NSPrivacyCollectedDataTypes": []})["errors"])
        self.assertFalse(self.check({"NSPrivacyTracking": False})["errors"])
        empty = self.check({"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": []})
        self.assertFalse(empty["errors"])
        self.assertTrue(empty["warnings"])

    def test_xml_and_binary_require_actual_booleans_and_domain_arrays(self):
        invalid = [
            {"NSPrivacyTracking": "true", "NSPrivacyTrackingDomains": ["tracking.example.com"]},
            {"NSPrivacyTracking": 1, "NSPrivacyTrackingDomains": ["tracking.example.com"]},
            {"NSPrivacyTracking": True, "NSPrivacyTrackingDomains": "tracking.example.com"},
            {"NSPrivacyTracking": True, "NSPrivacyTrackingDomains": [123]},
        ]
        for manifest in invalid:
            for fmt in (plistlib.FMT_XML, plistlib.FMT_BINARY):
                self.assertTrue(inspect_manifest("test", plistlib.dumps(manifest, fmt=fmt))["errors"])

    def test_domains_cannot_be_urls_paths_wildcards_or_empty_strings(self):
        for domain in ("", "https://tracking.example.com", "tracking.example.com/", "*.example.com",
                       "tracking.example.com?x=1", " tracking.example.com", "-bad.example.com"):
            self.assertTrue(self.check({"NSPrivacyTracking": True,
                                        "NSPrivacyTrackingDomains": [domain]})["errors"])

    def test_duplicate_keys_and_malformed_plists_are_rejected(self):
        duplicate = b'<plist version="1.0"><dict><key>NSPrivacyTracking</key><false/>' \
                    b'<key>NSPrivacyTracking</key><true/></dict></plist>'
        self.assertTrue(inspect_manifest("test", duplicate)["errors"])
        self.assertTrue(inspect_manifest("test", b"not a plist")["errors"])
        self.assertTrue(inspect_manifest("test", b'<plist version="1.0"><dict>')["errors"])

    def test_ipa_checks_each_framework_manifest_without_merging_into_app(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / "PhotoMaid.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/PhotoMaid.app/PrivacyInfo.xcprivacy", plistlib.dumps({
                    "NSPrivacyTracking": True, "NSPrivacyTrackingDomains": ["tracking.example.com"]}))
                archive.writestr("Payload/PhotoMaid.app/Frameworks/Bad.framework/PrivacyInfo.xcprivacy",
                                 plistlib.dumps({"NSPrivacyTracking": False,
                                                  "NSPrivacyTrackingDomains": ["sdk.example.com"]}))
            report = audit([ipa], require_app_manifest=True)
            self.assertEqual(report["status"], "FAIL")
            self.assertEqual(len(report["manifests"]), 2)
            self.assertFalse(report["manifests"][0]["errors"])
            self.assertIn("Bad.framework", report["manifests"][1]["path"])
            self.assertTrue(report["manifests"][1]["errors"])

    def test_preflight_refuses_missing_inputs_and_missing_main_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertEqual(audit([root])["status"], "FAIL")
            self.assertEqual(audit([root / "missing.ipa"])["status"], "FAIL")
            ipa = root / "PhotoMaid.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/PhotoMaid.app/Frameworks/SDK.framework/PrivacyInfo.xcprivacy",
                                 plistlib.dumps({}))
            self.assertEqual(audit([ipa], require_app_manifest=True)["status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
