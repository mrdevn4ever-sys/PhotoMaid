#!/usr/bin/env python3
"""Guard against green workflows masking skipped/failed native captures or fake Duo attribution."""
import unittest
from assemble_refresh import validate, validate_native_screenshot
from PIL import Image


class CaptureEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.photos = [{'file': f'{i}.jpg'} for i in range(55)]
        self.inventory = {'count': 55, 'sourceFiles': [p['file'] for p in self.photos]}
        self.summary = {'result': 'Passed', 'passedTests': 5, 'failedTests': 0, 'skippedTests': 0}
        self.device = {'device_class': 'iphone-large', 'actual_duo': False, 'name': 'iPhone 17 Pro Max', 'sdk': '26.6'}

    def test_complete_native_capture_passes(self):
        validate(self.summary, self.inventory, self.photos, self.device, 'iphone-large')

    def test_failed_or_skipped_or_partial_tests_rejected(self):
        for field, value in [('failedTests', 1), ('skippedTests', 1), ('passedTests', 4), ('result', 'Failed')]:
            summary = self.summary | {field: value}
            with self.subTest(field=field), self.assertRaises(AssertionError):
                validate(summary, self.inventory, self.photos, self.device, 'iphone-large')

    def test_extra_stock_photos_or_wrong_original_rejected(self):
        for inventory in [self.inventory | {'count': 61}, self.inventory | {'sourceFiles': self.inventory['sourceFiles'][:-1] + ['wrong.jpg']}]:
            with self.assertRaises(AssertionError):
                validate(self.summary, inventory, self.photos, self.device, 'iphone-large')

    def test_tablet_or_old_sdk_cannot_be_called_duo(self):
        summary = self.summary | {'passedTests': 1}
        for device in [self.device | {'device_class': 'iphone-duo'},
                       self.device | {'device_class': 'iphone-duo', 'actual_duo': True, 'name': 'iPad mini'},
                       self.device | {'device_class': 'iphone-duo', 'actual_duo': True, 'name': 'iPhone Duo'}]:
            with self.assertRaises(AssertionError):
                validate(summary, self.inventory, self.photos, device, 'iphone-duo')

    def test_medium_screenshots_require_their_actual_single_test(self):
        device = self.device | {'device_class': 'iphone-medium', 'name': 'iPhone 17 Pro'}
        validate(self.summary | {'passedTests': 1}, self.inventory, self.photos, device, 'iphone-medium')
        with self.assertRaises(AssertionError):
            validate(self.summary, self.inventory, self.photos, device, 'iphone-medium')

    def test_duo_requires_genuine_native_result_and_supported_runtime(self):
        device = {'device_class': 'iphone-duo', 'actual_duo': True, 'name': 'iPhone Duo',
                  'sdk': '27.1', 'os_version': '27.1',
                  'device_type': 'com.apple.CoreSimulator.SimDeviceType.iPhone-Duo'}
        summary = self.summary | {'passedTests': 1, 'devicesAndConfigurations': [
            {'device': {'modelName': 'iPhone Duo', 'osVersion': '27.1'}}]}
        validate(summary, self.inventory, self.photos, device, 'iphone-duo')
        for invalid in [device | {'os_version': '27.0'}, device | {'sdk': '26.6'},
                        device | {'device_type': 'com.apple.CoreSimulator.SimDeviceType.iPad-mini'}]:
            with self.assertRaises(AssertionError):
                validate(summary, self.inventory, self.photos, invalid, 'iphone-duo')
        mislabeled = summary | {'devicesAndConfigurations': [
            {'device': {'modelName': 'iPhone 17 Pro', 'osVersion': '27.1'}}]}
        with self.assertRaises(AssertionError):
            validate(mislabeled, self.inventory, self.photos, device, 'iphone-duo')

    def test_successful_native_tool_must_not_admit_a_blank_duo_frame(self):
        with Image.new('RGB', (2007, 2853), 'black') as blank:
            with self.assertRaisesRegex(AssertionError, 'blank native frame'):
                validate_native_screenshot(blank, {(2007, 2853)})


if __name__ == '__main__':
    unittest.main()
