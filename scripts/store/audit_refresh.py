#!/usr/bin/env python3
"""Audit current native assets, their real UI results, upload formats and explicit visual review."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from PIL import Image
from assemble_refresh import HEROES, SIZES, validate


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit_device(root, code, device_class, photos):
    provenance = json.loads((root / 'provenance.json').read_text())
    assert provenance['locale'] == code and provenance['mode'] == 'dark'
    validate(provenance['capture_summary'], provenance['actual_library'], photos, provenance['device'], device_class)
    shots = json.loads((root / 'screenshots.json').read_text())
    assert len(shots) >= 20
    originals = {}
    for row in shots:
        path = root / 'all-pages' / row['file']
        assert row['locale'] == code and digest(path) == row['sha256']
        with Image.open(path) as image:
            assert image.size == (row['width'], row['height']) and image.size in SIZES[device_class]
        originals['all-pages/' + row['file']] = row['sha256']
    uploads = json.loads((root / 'selection.json').read_text())
    assert len(uploads) == 10 and len(list((root / 'app-store-selection').glob('*.png'))) == 10
    for i, (hero, row) in enumerate(zip(HEROES, uploads), 1):
        path = root / row['file']
        assert path.name == f'{i:02}-{hero}.png' and digest(path) == row['sha256']
        assert originals[row['native_source']] == row['native_sha256']
        with Image.open(path) as upload, Image.open(root / row['native_source']) as native:
            assert upload.mode == 'RGB' and upload.size == native.size
            assert upload.tobytes() == native.convert('RGB').tobytes(), 'Upload pixels differ from the genuine native capture'
    reviews = json.loads((root / 'review/manifest.json').read_text())
    assert reviews and all(sheet['review'] == 'PASS' for sheet in reviews), 'Visual review still pending'
    viewed = set()
    excluded = set()
    for sheet in reviews:
        for row in sheet['originals']:
            assert digest(root / row['file']) == row['sha256']
            viewed.add(row['file'])
            if row.get('store_suitability') == 'EXCLUDE':
                excluded.add(row['file'])
    assert set(originals) <= viewed, 'Native screenshots missing visual review'
    assert not any(row['native_source'] in excluded for row in uploads), 'An excluded archive image is in the upload selection'
    videos = []
    if device_class != 'iphone-medium':
        for folder, count in [('previews', 3), ('alternatives', 1)]:
            manifest = json.loads((root / folder / 'manifest.json').read_text())
            assert len(manifest) == count and len(list((root / folder).glob('*.mp4'))) == count
            for row in manifest:
                path = root / folder / row['file']
                relative = str(path.relative_to(root))
                assert row['locale'] == code and row['status'] == 'PASS'
                assert digest(path) == row['sha256'] and relative in viewed
                assert any(s['kind'] == 'video' and s['full_decode'] == 'PASS'
                           and any(x['file'] == relative for x in s['originals']) for s in reviews)
                poster = root / folder / row['poster_file']
                assert digest(poster) == row['poster_sha256'] and str(poster.relative_to(root)) in viewed
                probe = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)]))
                video = next(s for s in probe['streams'] if s['codec_type'] == 'video')
                audio = next(s for s in probe['streams'] if s['codec_type'] == 'audio')
                seconds = float(probe['format']['duration'])
                assert 15 <= seconds <= 30 and (video['width'], video['height']) == (886, 1920)
                assert video['codec_name'] == 'h264' and video['r_frame_rate'] == '30/1'
                assert abs(float(video['duration']) - seconds) <= 0.05 and abs(float(audio['duration']) - seconds) <= 0.05
                assert audio['codec_name'] == 'aac' and audio['channels'] == 2 and audio['sample_rate'] == '48000'
                assert path.stat().st_size < 500_000_000
                if row['file'] == '02-photo-games.mp4':
                    assert len(row['sources']) == 2 and all(s['playback_speed'] == 1 for s in row['sources'])
                    assert all(s['recording']['returncode'] == 0 for s in row['sources'])
                videos.append({'file': relative, 'sha256': row['sha256'], 'duration': seconds})
    return {'status': 'PASS', 'locale': code, 'device_class': device_class,
            'device': provenance['device'], 'native_screenshots': len(shots), 'selected_screenshots': 10,
            'videos': videos, 'native_test_count': provenance['capture_summary']['passedTests'],
            'source_commit': provenance['commit'], 'capture_run': provenance['workflow_run']}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path, default=Path('app-store/current'))
    p.add_argument('--locales', default='all')
    p.add_argument('--devices', default='iphone-large,iphone-medium')
    a = p.parse_args()
    mapping = json.loads(Path('app-store/localizations.json').read_text())
    codes = list(mapping) if a.locales == 'all' else a.locales.split(',')
    assert all(code in mapping for code in codes)
    photos = json.loads(Path('app-store/media/manifest.json').read_text())['photos']
    rows = []
    for code in codes:
        for device in a.devices.split(','):
            try:
                row = audit_device(a.root / 'locales' / code / device, code, device, photos)
            except Exception as error:
                row = {'status': 'FAIL', 'locale': code, 'device_class': device, 'error': str(error)}
            rows.append(row)
            print(json.dumps({k: row[k] for k in ('status', 'locale', 'device_class')} | ({'error': row['error']} if 'error' in row else {})))
    (a.root / 'audit.json').write_text(json.dumps(rows, indent=2) + '\n')
    if any(row['status'] != 'PASS' for row in rows):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
