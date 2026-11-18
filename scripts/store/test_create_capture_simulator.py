"""Offline contract tests for the Xcode 27 capture-device selection (no simctl writes)."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import create_capture_simulator as capture


class CaptureSimulatorSelectionTests(unittest.TestCase):
    def setUp(self):
        self.types = [{'name': name, 'identifier': 'com.apple.CoreSimulator.SimDeviceType.' + name.replace(' ', '-')}
                      for name in ('iPhone 18 Pro Max', 'iPhone 18 Pro', 'iPhone Duo')]
        self.runtimes = [
            {'name': 'iOS 27.1', 'version': '27.1', 'isAvailable': True,
             'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-27-1',
             'supportedDeviceTypes': [self.types[2]]},
            {'name': 'iOS 27.2', 'version': '27.2', 'isAvailable': True,
             'identifier': 'com.apple.CoreSimulator.SimRuntime.iOS-27-2',
             'supportedDeviceTypes': self.types[:2]},
        ]
        self.sdk = '27.2'
        self.creates = []

    def fake_run(self, *args):
        if args == ('xcrun', 'simctl', 'list', 'devicetypes', '-j'):
            return json.dumps({'devicetypes': self.types})
        if args == ('xcrun', 'simctl', 'list', 'runtimes', '-j'):
            return json.dumps({'runtimes': self.runtimes})
        if args == ('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'):
            return self.sdk
        if args[:3] == ('xcrun', 'simctl', 'create'):
            self.creates.append(args)
            return 'disposable-test-udid'
        raise AssertionError(args)

    def select(self, device):
        with tempfile.TemporaryDirectory() as temp:
            report = Path(temp) / 'device.json'
            with patch.object(capture, 'run', side_effect=self.fake_run), \
                 patch.object(sys, 'argv', ['create_capture_simulator.py', device, str(report)]), \
                 contextlib.redirect_stdout(io.StringIO()):
                capture.main()
            return json.loads(report.read_text())

    def test_large_and_medium_use_real_18_pro_types_on_27_2(self):
        for device_class, name in [('iphone-large', 'iPhone 18 Pro Max'),
                                   ('iphone-medium', 'iPhone 18 Pro')]:
            with self.subTest(device=device_class):
                report = self.select(device_class)
                self.assertEqual(report['name'], name)
                self.assertEqual(report['os_version'], '27.2')
                self.assertFalse(report['actual_duo'])
                self.assertEqual(self.creates[-1][-2:],
                                 ('com.apple.CoreSimulator.SimDeviceType.' + name.replace(' ', '-'),
                                  'com.apple.CoreSimulator.SimRuntime.iOS-27-2'))

    def test_duo_uses_its_27_1_runtime_not_non_duo_27_2(self):
        report = self.select('iphone-duo')
        self.assertTrue(report['actual_duo'])
        self.assertEqual(report['os_version'], '27.1')
        self.assertEqual(self.creates[-1][-1], 'com.apple.CoreSimulator.SimRuntime.iOS-27-1')

    def test_fails_closed_on_missing_type_runtime_or_old_sdk(self):
        for broken in ('type', 'runtime', 'sdk', 'unsupported'):
            with self.subTest(broken=broken):
                self.setUp()
                if broken == 'type':
                    self.types = self.types[1:]
                elif broken == 'runtime':
                    self.runtimes[1]['isAvailable'] = False
                elif broken == 'sdk':
                    self.sdk = '27.1'
                else:
                    self.runtimes[1]['supportedDeviceTypes'] = [self.types[2]]
                with self.assertRaisesRegex(AssertionError, 'BLOCKED'):
                    self.select('iphone-large')
                self.assertEqual(self.creates, [])


if __name__ == '__main__':
    unittest.main()
