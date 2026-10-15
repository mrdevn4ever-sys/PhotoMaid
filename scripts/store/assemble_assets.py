#!/usr/bin/env python3
"""Preserves native screenshots and chooses ten originals without altering UI or image pixels."""
import argparse,hashlib,json,shutil,os
from pathlib import Path
from PIL import Image

HEROES=['today','feed','library','cleanup','collage','editor-filter','editor-markup','movie','vault-media','vault-viewer']
def category(name):
 if name.startswith('introduction'):return '01-introduction'
 if name.startswith(('today','feed')):return '02-today-and-review'
 if name.startswith(('library','album','grid','favorites','search','selection','tags','hidden','viewer','slideshow')):return '03-photos'
 if name.startswith(('cleanup','trash','later','months','large-files','duplicates','storage','files','series','collections','blurry','similar','documents','categories')):return '04-cleanup'
 if name.startswith('vault'):return '06-vault'
 if name.startswith(('settings','pro','privacy','help','excluded-albums','backup','controls')):return '07-settings'
 if name.startswith('history'):return '08-history'
 return '05-studio'

def main():
 p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('destination',type=Path);p.add_argument('--locale',required=True);a=p.parse_args()
 allshots=a.destination/'all-pages';selected=a.destination/'app-store-selection';allshots.mkdir(parents=True,exist_ok=True);selected.mkdir(exist_ok=True)
 photos=json.loads(Path('app-store/media/manifest.json').read_text())['photos'];assert len(photos)==55
 for photo in photos:
  path=Path('app-store/media')/photo['file'];assert hashlib.sha256(path.read_bytes()).hexdigest()==photo['sha256']
 inventory=json.loads((a.source/'library.json').read_text())
 assert inventory['count']==55 and set(inventory['sourceFiles'])=={x['file']for x in photos},inventory
 shutil.copy2(a.source/'library.json',a.destination/'library.json')
 rows=[];paths={}
 for path in sorted((a.source/'screenshots').glob('*.png')):
  with Image.open(path)as im:
   width,height=im.size;assert (width,height)in[(1320,2868),(1290,2796),(1260,2736)],(path,width,height)
   if 'A'in im.getbands():assert im.getchannel('A').getextrema()==(255,255)
  group=category(path.stem);directory=allshots/group;directory.mkdir(exist_ok=True)
  shutil.copy2(path,directory/path.name);paths[path.stem]=directory/path.name
  rows.append({'file':group+'/'+path.name,'locale':a.locale,'appearance':'dark','width':width,'height':height,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
 for n,name in enumerate(HEROES,1):
  source=paths.get(name)
  if source is not None:os.link(source,selected/f'{n:02}-{name}.png')
 (a.destination/'screenshots.json').write_text(json.dumps(rows,indent=2)+'\n')
 (a.destination/'provenance.json').write_text(json.dumps({'locale':a.locale,'commit':os.environ.get('GITHUB_SHA'),'workflow_run':os.environ.get('GITHUB_RUN_ID'),'device':'iPhone 17 Pro Max','mode':'dark','media_manifest':'app-store/media/manifest.json','media_count':55,'data':'Real PhotoKit, Core Data, analysis and encrypted vault; no QA fixtures','capture_summary':json.loads((a.source/'summary.json').read_text())if(a.source/'summary.json').exists()else None},indent=2)+'\n')
 print('Native screenshots:',len(rows),'selection:',len(list(selected.glob('*.png'))))
if __name__=='__main__':main()
