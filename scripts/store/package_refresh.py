#!/usr/bin/env python3
"""Package only the complete, audited 16-language upload selection. Keep native files intact."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=Path('app-store/current'))
    parser.add_argument('--destination', type=Path, default=Path('app-store/current/packages'))
    args = parser.parse_args()
    status_file = args.root / 'STATUS.json'
    if status_file.exists() and json.loads(status_file.read_text()).get('asset_naming', {}).get('status') == 'RECAPTURE_REQUIRED':
        parser.error('Spielname wurde in Paare geändert. Spielbilder und Spiele-Vorschauen zuerst nativ neu aufnehmen; der alte Bildsatz ist nur ein Archiv.')
    mapping = json.loads(Path('app-store/localizations.json').read_text())
    audit = json.loads((args.root / 'audit.json').read_text())
    profiles = {(row['locale'], row['device_class']): row for row in audit}
    devices = ['iphone-large', 'iphone-medium']
    for locale in mapping:
        for device in devices:
            assert profiles[(locale, device)]['status'] == 'PASS', (locale, device)
    args.destination.mkdir(parents=True, exist_ok=True)
    packages = []
    for locale, info in mapping.items():
        folder = args.root / 'locales' / locale
        files = []
        for device in devices:
            files += list((folder / device / 'app-store-selection').glob('*.png'))
            files += [folder / device / name for name in [
                'provenance.json', 'selection.json', 'artifact-receipt.json', 'review/manifest.json']]
        for category, expected in [('previews', 3), ('alternatives', 1)]:
            source = folder / 'iphone-large' / category
            manifest = json.loads((source / 'manifest.json').read_text())
            assert len(manifest) == expected
            files.append(source / 'manifest.json')
            for row in manifest:
                path = source / row['file']
                assert digest(path) == row['sha256']
                files += [path, source / row['poster_file']]
        assert sum(path.suffix == '.png' and 'app-store-selection' in path.parts for path in files) == 20
        assert sum(path.suffix == '.mp4' for path in files) == 4
        for device in devices:
            for row in json.loads((folder / device / 'selection.json').read_text()):
                assert digest(folder / device / row['file']) == row['sha256']
        manifest = {
            'locale': locale, 'app_store_locale': info['app_store_locale'],
            'status': 'PASS', 'selected_screenshots': 20,
            'selected_previews': 3, 'vault_alternatives': 1,
            'upload_status': 'NOT RUN',
            'instructions': 'Ten PNGs per iPhone size. Three selected previews use the common iPhone format. The vault alternative replaces one preview; never submit four at once. Native archives and review sheets remain in the existing project and source workflow artifacts.',
            'audit': [profiles[(locale, device)] for device in devices],
            'files': [{'file': str(path.relative_to(folder)), 'bytes': path.stat().st_size,
                       'sha256': digest(path)} for path in sorted(files)],
        }
        target = args.destination / f'PhotoMaid-Store-{info["app_store_locale"]}.zip'
        with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_STORED) as archive:
            for path in sorted(files):
                archive.write(path, str(path.relative_to(folder)))
            archive.writestr('PACKAGE.json', json.dumps(manifest, indent=2) + '\n')
        with zipfile.ZipFile(target) as archive:
            assert archive.testzip() is None
        packages.append({'locale': locale, 'app_store_locale': info['app_store_locale'],
                         'file': target.name, 'bytes': target.stat().st_size,
                         'sha256': digest(target), 'zip_integrity': 'PASS'})
        print(locale, target.stat().st_size, 'bytes; ZIP integrity PASS', flush=True)
    (args.destination / 'manifest.json').write_text(json.dumps(packages, indent=2) + '\n')


if __name__ == '__main__':
    main()
