#!/bin/bash
# Read-only capability discovery; does not build, sign, upload an app or change a personal simulator.
set -euo pipefail
mkdir -p duo-environment
python3 - <<'PY' > duo-environment/xcode-path.txt
import glob,re,os
requested=os.environ.get('PM_PROBE_XCODE','')
if requested:
    path='/Applications/Xcode_'+requested+'.app'
    if not os.path.isdir(path):raise SystemExit('Requested Xcode not installed: '+path)
    print(path)
    raise SystemExit(0)
def version(path):
    match=re.search(r'Xcode[_ ](\d+)(?:\.(\d+))?(?:\.(\d+))?',path)
    numbers=tuple(int(n or 0) for n in match.groups()) if match else (0,0,0)
    return numbers, not bool(re.search(r'beta|rc',path,re.I))
paths=glob.glob('/Applications/Xcode*.app')
if not paths: raise SystemExit('No Xcode installed')
print(max(paths,key=version))
PY
sudo xcode-select -s "$(cat duo-environment/xcode-path.txt)"
xcodebuild -version | tee duo-environment/xcode-version.txt
xcodebuild -showsdks > duo-environment/sdks.txt
xcrun simctl list devicetypes -j > duo-environment/device-types.json
xcrun simctl list runtimes -j > duo-environment/runtimes.json
xcrun simctl list devices available -j > duo-environment/devices.json
xcrun simctl help > duo-environment/simctl-help.txt 2>&1
xcrun simctl io help > duo-environment/simctl-io-help.txt 2>&1 || true
xcrun agent skills export --help > duo-environment/agent-skills-help.txt 2>&1 || true
python3 - <<'PY'
import json
from pathlib import Path
root=Path('duo-environment')
types=json.loads((root/'device-types.json').read_text()).get('devicetypes',[])
runtimes=json.loads((root/'runtimes.json').read_text()).get('runtimes',[])
summary={'device_types':[t for t in types if 'Duo' in t.get('name','')],
         'ios_runtimes':[r for r in runtimes if 'iOS' in r.get('name','')],
         'xcode':(root/'xcode-version.txt').read_text().strip()}
(root/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
PY
