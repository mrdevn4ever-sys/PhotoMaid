#!/usr/bin/env python3
"""Open the device UI belonging to the selected Xcode, without substituting devices."""
import argparse
import json
import plistlib
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('udid')
    args = parser.parse_args()
    developer = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    candidates = [
        (developer.parent / 'Applications/DeviceHub.app', 'com.apple.dt.Devices'),
        (developer / 'Applications/Simulator.app', 'com.apple.iphonesimulator'),
    ]
    for path, expected_id in candidates:
        info_path = path / 'Contents/Info.plist'
        if not info_path.is_file():
            continue
        with info_path.open('rb') as stream:
            info = plistlib.load(stream)
        assert info.get('CFBundleIdentifier') == expected_id, (path, info.get('CFBundleIdentifier'))
        executable = info.get('CFBundleExecutable')
        assert executable and (path / 'Contents/MacOS' / executable).is_file(), path
        command = ['open', '-a', str(path)]
        if expected_id == 'com.apple.iphonesimulator':
            command += ['--args', '-CurrentDeviceUDID', args.udid]
        # Device Hub is opened without legacy Simulator-only arguments. The
        # simctl operations and native XCTest destination select the exact UDID.
        subprocess.run(command, check=True, timeout=30)
        print(json.dumps({'device_ui': str(path), 'bundle_id': expected_id,
                          'version': info.get('CFBundleShortVersionString'),
                          'native_test_destination_udid': args.udid}))
        return
    raise SystemExit('Selected Xcode has neither DeviceHub.app nor Simulator.app: ' + str(developer))


if __name__ == '__main__':
    main()
