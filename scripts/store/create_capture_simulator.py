#!/usr/bin/env python3
"""Select a real device/runtime; never label a tablet or resized iPhone as iPhone Duo."""
import argparse
import json
import subprocess
from pathlib import Path


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('device', choices=['iphone-large', 'iphone-medium', 'iphone-duo'])
    p.add_argument('report', type=Path)
    a = p.parse_args()
    types = json.loads(run('xcrun', 'simctl', 'list', 'devicetypes', '-j'))['devicetypes']
    runtimes = json.loads(run('xcrun', 'simctl', 'list', 'runtimes', '-j'))['runtimes']
    sdk = run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version')
    sdk_numbers = tuple(map(int, sdk.split('.')))
    assert sdk_numbers[0] == 27, 'BLOCKED: Xcode 27 simulator SDK is required'
    if a.device == 'iphone-duo':
        matches = [t for t in types if t['name'] == 'iPhone Duo']
        assert sdk_numbers >= (27, 1) and matches, 'BLOCKED: genuine iPhone Duo device type and iOS 27.1 SDK are required'
        # iOS 27.2 ships separate Duo and non-Duo images; 27.1 is Duo-only.
        candidates = [r for r in runtimes if r['isAvailable'] and r['version'] == '27.1']
        assert candidates, 'BLOCKED: no available iPhone Duo iOS 27.1 runtime'
        runtime = candidates[0]
        device = matches[0]
    else:
        assert sdk_numbers >= (27, 2), 'BLOCKED: iPhone 18 Pro capture requires Xcode 27.2+ SDK'
        name = 'iPhone 18 Pro Max' if a.device == 'iphone-large' else 'iPhone 18 Pro'
        matches = [t for t in types if t['name'] == name]
        assert matches, f'BLOCKED: genuine {name} device type is unavailable'
        device = matches[0]
        # 27.1 is Duo-only, while the GA image supplies iPhone 18 Pro/Max on 27.2.
        candidates = [r for r in runtimes if r['isAvailable'] and r['version'] == '27.2'
                      and (not r.get('supportedDeviceTypes') or any(
                          t.get('name') == name or t.get('identifier') == device['identifier']
                          for t in r['supportedDeviceTypes']))]
        assert candidates, f'BLOCKED: no compatible iOS 27.2 runtime for {name}'
        runtime = candidates[0]
    udid = run('xcrun', 'simctl', 'create', 'PhotoMaid Store Current', device['identifier'], runtime['identifier'])
    report = {'device_class': a.device, 'name': device['name'], 'device_type': device['identifier'],
              'runtime': runtime['identifier'], 'os_version': runtime['version'], 'sdk': sdk,
              'udid': udid, 'actual_duo': 'iPhone Duo' in device['name']}
    a.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
