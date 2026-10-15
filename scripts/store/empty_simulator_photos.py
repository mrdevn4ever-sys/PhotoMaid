#!/usr/bin/env python3
"""Removes factory photo data from ONE stopped, disposable store-capture simulator."""
import json,re,shutil,subprocess,sys
from pathlib import Path
udid=sys.argv[1]
assert re.fullmatch(r'[0-9A-Fa-f-]{36}',udid)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','-j']))['devices']
device=next(d for group in devices.values()for d in group if d['udid']==udid)
assert device['name'].startswith('PhotoMaid Store ') and device['state']=='Shutdown',device
root=Path.home()/'Library/Developer/CoreSimulator/Devices'/udid/'data/Media'
assert root.parent.name=='data' and root.parent.parent.name==udid
for name in ['DCIM','PhotoData','PhotoStreamsData']:
 path=root/name
 if path.exists():
  assert not path.is_symlink()
  shutil.rmtree(path)
  print('Reset factory library directory:',name)
print('Disposable simulator ready for the selected 55 photos:',udid)
