#!/usr/bin/env python3
"""Prepare the current product-page selection, retaining every native source and its provenance."""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path
from PIL import Image
from assemble_assets import category

# Behalten und Papierkorb als Screenshots mitten in der echten, gehaltenen Wischgeste (Nutzer, 22.10.2026: „muss
# klar ersichtlich sein – behalten, löschen einmal mindestens“); Apple erlaubt höchstens zehn je Gerät.
HEROES = ['today', 'feed-keep', 'feed-trash', 'library', 'cleanup', 'snake-play', 'memory-play',
          'collage', 'editor-filter', 'vault-media']
SIZES = {'iphone-large': {(1320, 2868), (1290, 2796), (1260, 2736)},
         'iphone-medium': {(1206, 2622), (1179, 2556)},
         'iphone-duo': {(1398, 2034), (2007, 2853)}}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_native_screenshot(image, sizes):
    assert image.size in sizes, (image.size, sizes)
    if 'A' in image.getbands():
        assert image.getchannel('A').getextrema() == (255, 255), 'Native screenshot contains transparency'
    assert any(low != high for low, high in image.convert('RGB').getextrema()), 'Uniform/blank native frame is not a Store screenshot'


def validate(summary, inventory, photos, device, device_class):
    assert summary['result'] == 'Passed' and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
    expected = 5 if device_class == 'iphone-large' else 1
    assert summary['passedTests'] == expected, summary
    assert inventory['count'] == 55 and set(inventory['sourceFiles']) == {p['file'] for p in photos}, inventory
    assert device['device_class'] == device_class
    if device_class == 'iphone-duo':
        assert device['actual_duo'] and 'iPhone Duo' in device['name']
        assert tuple(map(int, device['sdk'].split('.'))) >= (27, 1)
        assert device['device_type'] == 'com.apple.CoreSimulator.SimDeviceType.iPhone-Duo'
        assert tuple(map(int, device['os_version'].split('.'))) >= (27, 1)
        configurations = summary['devicesAndConfigurations']
        assert configurations and all(c['device']['modelName'] == 'iPhone Duo' for c in configurations)
        assert all(tuple(map(int, c['device']['osVersion'].split('.'))) >= (27, 1) for c in configurations)
    else:
        assert not device['actual_duo']


def main():
    p = argparse.ArgumentParser()
    p.add_argument('source', type=Path)
    p.add_argument('destination', type=Path)
    p.add_argument('--locale', required=True)
    p.add_argument('--device', choices=list(SIZES), required=True)
    a = p.parse_args()
    photos = json.loads(Path('app-store/media/manifest.json').read_text())['photos']
    for row in photos:
        assert digest(Path('app-store/media') / row['file']) == row['sha256']
    summary = json.loads((a.source / 'summary.json').read_text())
    inventory = json.loads((a.source / 'library.json').read_text())
    device = json.loads((a.source / 'device.json').read_text())
    validate(summary, inventory, photos, device, a.device)
    sizes = SIZES[a.device]
    if a.device == 'iphone-duo' and device.get('display_role') == 'inner':
        sizes = {(2007, 2853)}
    a.destination.mkdir(parents=True, exist_ok=True)
    rows, paths = [], {}
    for path in sorted((a.source / 'screenshots').glob('*.png')):
        with Image.open(path) as image:
            size = image.size
            validate_native_screenshot(image, sizes)
        group = '09-photo-games' if path.stem.startswith(('memory-', 'snake-', 'games-')) else category(path.stem)
        target = a.destination / 'all-pages' / group / path.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        paths[path.stem] = target
        rows.append({'file': f'{group}/{path.name}', 'locale': a.locale, 'appearance': 'dark',
                     'width': size[0], 'height': size[1], 'sha256': digest(target)})
    assert all(name in paths for name in HEROES), sorted(set(HEROES) - set(paths))
    selection = a.destination / 'app-store-selection'
    selection.mkdir(exist_ok=True)
    uploads = []
    for i, name in enumerate(HEROES, 1):
        original = paths[name]
        target = selection / f'{i:02}-{name}.png'
        with Image.open(original) as image:
            # Store PNGs have no alpha channel. Pixel dimensions/colors stay identical;
            # the unmodified native file is kept in all-pages with its original hash.
            if image.mode == 'RGB':
                shutil.copyfile(original, target)
            else:
                image.convert('RGB').save(target)
        uploads.append({'file': f'app-store-selection/{target.name}', 'sha256': digest(target),
                        'native_source': str(original.relative_to(a.destination)), 'native_sha256': digest(original)})
    provenance = {'locale': a.locale, 'commit': os.environ.get('GITHUB_SHA'),
                  'workflow_run': os.environ.get('GITHUB_RUN_ID'), 'device': device, 'mode': 'dark',
                  'capture': 'refresh' if a.device == 'iphone-large' else 'refresh-screenshots',
                  'actual_library': inventory, 'capture_summary': summary,
                  'media_manifest': 'app-store/media/manifest.json',
                  'data': 'Actual PhotoKit images and real UI actions; no synthetic media, fixed scores or QA step clock',
                  'visual_review': 'PENDING'}
    (a.destination / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    (a.destination / 'screenshots.json').write_text(json.dumps(rows, indent=2) + '\n')
    (a.destination / 'selection.json').write_text(json.dumps(uploads, indent=2) + '\n')
    shutil.copyfile(a.source / 'xcode.txt', a.destination / 'xcode.txt')
    print('PASS:', a.locale, a.device, len(rows), 'unaltered native screenshots; 10 upload PNGs without alpha')


if __name__ == '__main__':
    main()
