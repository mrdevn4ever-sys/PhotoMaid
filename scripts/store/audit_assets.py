#!/usr/bin/env python3
"""Audit final native assets and explicit visual-review records; never invent completeness."""
import argparse,hashlib,json,subprocess
from pathlib import Path
from PIL import Image


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def audit_locale(root,language,photos,require_videos):
    provenance=json.loads((root/'provenance.json').read_text())
    summary=provenance['capture_summary'];assert summary['result']=='Passed' and summary['failedTests']==0 and summary['skippedTests']==0
    inventory=provenance['actual_library'];assert inventory['count']==55 and set(inventory['sourceFiles'])==photos
    shots=json.loads((root/'screenshots.json').read_text());assert len(shots)>=80
    hashes=set()
    for row in shots:
        path=root/'all-pages'/row['file'];assert row['locale']==language and digest(path)==row['sha256']
        with Image.open(path)as image:assert image.size==(row['width'],row['height']) and image.height>image.width
        hashes.add(row['sha256'])
    selected=list((root/'app-store-selection').glob('*.png'));assert len(selected)==10
    assert all(digest(path)in hashes for path in selected)
    reviews=json.loads((root/'review/manifest.json').read_text())
    viewed={item['file']for sheet in reviews if sheet['review']=='PASS' for item in sheet['originals']}
    assert all('all-pages/'+row['file']in viewed for row in shots),'Screenshots await visual review'
    for sheet in reviews:
        for item in sheet['originals']:assert digest(root/item['file'])==item['sha256']
    videos=[]
    if require_videos:
        preview_provenance=json.loads((root/'preview-provenance.json').read_text())
        preview_summary=preview_provenance['capture_summary'];assert preview_summary['result']=='Passed' and preview_summary['failedTests']==0 and preview_summary['skippedTests']==0
        assert preview_provenance['actual_library']['count']==55
        video_manifest=json.loads((root/'previews/manifest.json').read_text());assert len(video_manifest)==3
        for item in video_manifest:
            path=root/'previews'/item['file'];assert 'previews/'+item['file']in viewed
            poster=root/'previews'/item['poster_file']
            assert 'previews/'+item['poster_file']in viewed and digest(poster)==item['poster_sha256']
            with Image.open(poster)as image:assert image.size==(886,1920)
            stream=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
            video=next(s for s in stream['streams']if s['codec_type']=='video');audio=next(s for s in stream['streams']if s['codec_type']=='audio')
            duration=float(stream['format']['duration'])
            assert 15<=duration<=30 and (video['width'],video['height'])==(886,1920) and video['codec_name']=='h264' and video['r_frame_rate']=='30/1'
            assert audio['codec_name']=='aac' and audio['channels']==2 and audio['sample_rate']=='48000' and path.stat().st_size<500_000_000
            videos.append({'file':item['file'],'sha256':digest(path),'duration':duration})
    return {'language':language,'screenshots':len(shots),'selection':10,'videos':videos,'capture_run':provenance['workflow_run'],'capture_commit':provenance['commit'],'status':'PASS'}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path('app-store'));parser.add_argument('--screenshots-only',action='store_true');parser.add_argument('--locales',default='all');args=parser.parse_args()
    mapping=json.loads((args.root/'localizations.json').read_text());languages=list(mapping)if args.locales=='all'else args.locales.split(',')
    photos={p['file']for p in json.loads((args.root/'media/manifest.json').read_text())['photos']}
    rows=[]
    for language in languages:
        try:rows.append(audit_locale(args.root/'locales'/language,language,photos,not args.screenshots_only))
        except Exception as error:rows.append({'language':language,'status':'FAIL','error':str(error)})
    (args.root/'audit.json').write_text(json.dumps(rows,indent=2)+'\n')
    for row in rows:print(row)
    if any(row['status']!='PASS'for row in rows):raise SystemExit(1)

if __name__=='__main__':main()
