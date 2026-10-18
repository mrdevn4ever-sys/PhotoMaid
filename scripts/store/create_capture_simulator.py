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
    if a.device == 'iphone-duo':
        matches = [t for t in types if 'iPhone Duo' in t['name']]
        sdk_numbers = tuple(map(int, sdk.split('.')))
        assert sdk_numbers >= (27, 1) and matches, 'BLOCKED: genuine iPhone Duo device type and iOS 27.1 SDK are required'
        candidates = [r for r in runtimes if r['isAvailable'] and r['name'].startswith('iOS ')
                      and tuple(map(int, r['version'].split('.'))) >= (27, 1)]
        assert candidates, 'BLOCKED: no available iOS 27.1+ runtime'
        runtime = max(candidates, key=lambda r: tuple(map(int, r['version'].split('.'))))
        device = matches[0]
    else:
        name = 'iPhone 17 Pro Max' if a.device == 'iphone-large' else 'iPhone 17 Pro'
        device = next(t for t in types if t['name'] == name)
        runtime = next(r for r in runtimes if r['isAvailable'] and r['name'] == 'iOS 26.2')
    udid = run('xcrun', 'simctl', 'create', 'PhotoMaid Store Current', device['identifier'], runtime['identifier'])
    report = {'device_class': a.device, 'name': device['name'], 'device_type': device['identifier'],
              'runtime': runtime['identifier'], 'os_version': runtime['version'], 'sdk': sdk,
              'udid': udid, 'actual_duo': 'iPhone Duo' in device['name']}
    a.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
