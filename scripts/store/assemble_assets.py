#!/usr/bin/env python3
"""Preserve native screenshots, select ten originals and audit the actual capture."""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path
from PIL import Image

HEROES = ['today', 'feed', 'library', 'cleanup', 'collage', 'editor-filter', 'editor-markup', 'movie', 'vault-media', 'vault-viewer']

def category(name):
    if name.startswith('introduction'): return '01-introduction'
    if name.startswith(('today', 'feed')): return '02-today-and-review'
    if name.startswith(('library', 'album', 'grid', 'favorites', 'search', 'selection', 'tags', 'hidden', 'viewer', 'slideshow')): return '03-photos'
    if name.startswith(('cleanup', 'trash', 'later', 'months', 'large-files', 'duplicates', 'storage', 'files', 'series', 'collections', 'blurry', 'similar', 'documents', 'categories')): return '04-cleanup'
    if name.startswith('vault'): return '06-vault'
    if name.startswith(('settings', 'pro', 'privacy', 'help', 'excluded-albums', 'backup', 'controls')): return '07-settings'
    if name.startswith('history'): return '08-history'
    return '05-studio'

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--locale', required=True)
    parser.add_argument('--mode', choices=['all', 'screenshots', 'previews'], default='all')
    args = parser.parse_args()
    args.destination.mkdir(parents=True, exist_ok=True)
    photos = json.loads(Path('app-store/media/manifest.json').read_text())['photos']
    assert len(photos) == 55
    for photo in photos:
        path = Path('app-store/media') / photo['file']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == photo['sha256']
    inventory_path = args.source / 'library.json'
    inventory = json.loads(inventory_path.read_text()) if inventory_path.exists() else None
    summary_path = args.source / 'summary.json'
    summary = json.loads(summary_path.read_text()) if summary_path.exists() else None
    preview_only = args.mode == 'previews'
    provenance = {
        'locale': args.locale, 'commit': os.environ.get('GITHUB_SHA'), 'workflow_run': os.environ.get('GITHUB_RUN_ID'),
        'device': 'iPhone 17 Pro Max', 'mode': 'dark', 'capture': args.mode,
        'media_manifest': 'app-store/media/manifest.json', 'actual_library': inventory,
        'data': 'Real PhotoKit, Core Data, analysis and encrypted vault; no QA fixtures', 'capture_summary': summary,
    }
    if os.environ.get('STORE_EXPORT_RUN'):
        provenance.update(export_run=os.environ['STORE_EXPORT_RUN'], export_commit=os.environ['STORE_EXPORT_COMMIT'])
    prefix = 'preview-' if preview_only else ''
    (args.destination / (prefix + 'provenance.json')).write_text(json.dumps(provenance, indent=2) + '\n')
    if inventory_path.exists(): shutil.copy2(inventory_path, args.destination / (prefix + 'library.json'))
    rows, paths = [], {}
    if not preview_only:
        allshots, selected = args.destination / 'all-pages', args.destination / 'app-store-selection'
        allshots.mkdir(exist_ok=True); selected.mkdir(exist_ok=True)
        for path in sorted((args.source / 'screenshots').glob('*.png')):
            with Image.open(path) as image:
                width, height = image.size
                assert (width, height) in [(1320, 2868), (1290, 2796), (1260, 2736)], (path, width, height)
                if 'A' in image.getbands(): assert image.getchannel('A').getextrema() == (255, 255)
            group = category(path.stem)
            directory = allshots / group; directory.mkdir(exist_ok=True)
            shutil.copy2(path, directory / path.name); paths[path.stem] = directory / path.name
            rows.append({'file': group + '/' + path.name, 'locale': args.locale, 'appearance': 'dark', 'width': width, 'height': height, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        for number, name in enumerate(HEROES, 1):
            if name in paths: os.link(paths[name], selected / f'{number:02}-{name}.png')
        (args.destination / 'screenshots.json').write_text(json.dumps(rows, indent=2) + '\n')
        print('Native screenshots:', len(rows), 'selection:', len(list(selected.glob('*.png'))))
    # Partial evidence is preserved above. Only a genuinely complete capture passes these checks.
    assert inventory and inventory['count'] == 55 and set(inventory['sourceFiles']) == {photo['file'] for photo in photos}, inventory
    assert summary and summary['result'] == 'Passed' and summary['failedTests'] == 0 and summary['skippedTests'] == 0, summary
    expected_tests = 2 if args.mode == 'screenshots' else (4 if preview_only else 5)
    assert summary['passedTests'] == expected_tests, summary
    if not preview_only:
        assert all(name in paths for name in HEROES), sorted(set(HEROES) - set(paths))
    print('PASS: exact 55-photo library; successful native capture with no skipped tests.')

if __name__ == '__main__': main()
