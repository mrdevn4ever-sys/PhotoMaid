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
python3 - <<'PY'
import glob,json,plistlib,subprocess
from pathlib import Path
# Record actual bundle locations before attempting another GUI launch. Some runner
# images supply SDK/CLI components without the usual Simulator.app bundle.
developer=Path(subprocess.check_output(['xcode-select','-p'],text=True).strip())
patterns=['/Applications/*.app',
          '/Applications/Xcode*.app/Contents/Developer/Applications/*.app',
          '/Applications/Xcode*.app/Contents/Applications/*.app',
          '/Library/Developer/Applications/*.app',
          '/Library/Developer/Simulator/*.app']
bundles=[]
for raw in sorted({p for pattern in patterns for p in glob.glob(pattern)}):
    path=Path(raw);info_path=path/'Contents/Info.plist';info={}
    if info_path.is_file():
        with info_path.open('rb') as stream:info=plistlib.load(stream)
    executable=info.get('CFBundleExecutable')
    bundles.append({'path':raw,'resolved_path':str(path.resolve()),
                    'bundle_id':info.get('CFBundleIdentifier'),
                    'version':info.get('CFBundleShortVersionString'),
                    'executable_exists':bool(executable and (path/'Contents/MacOS'/executable).is_file())})
usual=developer/'Applications/Simulator.app'
report={'selected_developer':str(developer),'usual_simulator_path':str(usual),
        'usual_simulator_exists':usual.is_dir(),'bundles':bundles}
Path('duo-environment/gui-bundles.json').write_text(json.dumps(report,indent=2)+'\n')
print('Selected Xcode Simulator.app exists:',report['usual_simulator_exists'])
print('Discovered Simulator bundles:',[b['path'] for b in bundles if 'Simulator' in b['path']])
PY
xcodebuild -showsdks > duo-environment/sdks.txt
xcrun simctl list devicetypes -j > duo-environment/device-types.json
xcrun simctl list runtimes -j > duo-environment/runtimes.json
xcrun simctl list devices available -j > duo-environment/devices.json
xcrun simctl help > duo-environment/simctl-help.txt 2>&1
python3 - <<'PY'
import subprocess
from pathlib import Path
for name,args in [('simctl-io-help',['xcrun','simctl','help','io']),
                  ('agent-skills-help',['xcrun','agent','skills','export','--help'])]:
    try:
        result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=10)
        text=result.stdout
    except subprocess.TimeoutExpired as error:
        text=(error.stdout or b'').decode(errors='replace') if isinstance(error.stdout,bytes) else (error.stdout or '')
        text+='\nDIAGNOSTIC TIMEOUT (10s); capability discovery continues.\n'
    Path('duo-environment',name+'.txt').write_text(text)
PY
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
