#!/usr/bin/env python3
"""Bound public-tool discovery; optional help/skill queries must not block a real Duo boot."""
import json
import os
import signal
import subprocess
import sys
from pathlib import Path


root = Path('duo-environment')
root.mkdir(exist_ok=True)
commands = []


def run(name, argv, timeout=30, required=True):
    print('Duo phase:', name, flush=True)
    path = root / (name + '.log')
    process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    state = 'PASS'
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        state = 'TIMEOUT'
    path.write_text(output)
    if process.returncode and state == 'PASS':
        state = 'FAIL'
    commands.append({'phase': name, 'command': argv, 'status': state,
                     'returncode': process.returncode, 'timeout_seconds': timeout, 'log': path.name})
    (root / 'preparation-commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    print(name, state, 'returncode', process.returncode, flush=True)
    if required and state != 'PASS':
        print(output[-3500:], flush=True)
        raise RuntimeError(name + ': ' + state)
    return output


device = None
report = {'native_duo_boot': 'NOT RUN', 'native_screenshot': 'NOT RUN', 'skill_export': 'NOT RUN'}
try:
    run('runtime-download', ['xcodebuild', '-downloadPlatform', 'iOS', '-buildVersion', '27.1'], 300)
    # The read-only environment script also bounds its optional diagnostic commands.
    run('environment-after-download', ['bash', 'scripts/ci/duo_environment.sh'], 120)
    run('create-genuine-device', [sys.executable, 'scripts/store/create_capture_simulator.py',
                                'iphone-duo', str(root / 'capture-device.json')], 45)
    device = json.loads((root / 'capture-device.json').read_text())
    udid = device['udid']
    run('device-boot', ['xcrun', 'simctl', 'boot', udid], 45)
    run('device-bootstatus', ['xcrun', 'simctl', 'bootstatus', udid, '-b'], 180)
    report['native_duo_boot'] = 'PASS'
    run('duo-screens', ['xcrun', 'simctl', 'io', udid, 'enumerate'], 30)
    run('duo-default-capture', ['xcrun', 'simctl', 'io', udid, 'screenshot',
                                str(root / 'duo-default-screen.png')], 45)
    run('duo-image-size', ['sips', '-g', 'pixelWidth', '-g', 'pixelHeight',
                         str(root / 'duo-default-screen.png')], 15)
    report['native_screenshot'] = 'PASS'
    run('simctl-ui-help', ['xcrun', 'simctl', 'help', 'ui'], 10, required=False)
    run('simctl-io-help', ['xcrun', 'simctl', 'help', 'io'], 10, required=False)
    run('duo-ui-help', ['xcrun', 'simctl', 'ui', udid, '--help'], 10, required=False)
    run('apple-skill-export', ['xcrun', 'agent', 'skills', 'export', '--output-dir',
                              str(root.resolve() / 'skills')], 60, required=False)
    report['skill_export'] = commands[-1]['status']
    report['status'] = 'PASS'
except Exception as error:
    report['status'] = 'BLOCKED'
    report['error'] = str(error)
finally:
    report['device'] = device
    (root / 'preparation-result.json').write_text(json.dumps(report, indent=2) + '\n')
    if device:
        # Only the freshly created, explicitly named disposable Store device.
        run('device-shutdown', ['xcrun', 'simctl', 'shutdown', device['udid']], 20, required=False)
        run('device-delete', ['xcrun', 'simctl', 'delete', device['udid']], 20, required=False)
print(json.dumps(report, indent=2), flush=True)
if report['status'] != 'PASS':
    raise SystemExit(1)
