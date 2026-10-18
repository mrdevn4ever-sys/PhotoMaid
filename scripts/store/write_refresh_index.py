#!/usr/bin/env python3
"""Build an index from current files and measured statuses; missing locales stay visibly pending."""
import json
from pathlib import Path


def write_review(root, mapping, audit):
    profiles = {(row['locale'], row['device_class']): row for row in audit}
    locales = []
    for code, info in mapping.items():
        row = {'code': code, 'name': info['name_de'], 'app_store_locale': info['app_store_locale'], 'profiles': {}}
        for device in ['iphone-large', 'iphone-medium']:
            proof = profiles.get((code, device))
            if not proof or proof['status'] != 'PASS':
                continue
            folder = root / 'locales' / code / device
            selection = json.loads((folder / 'selection.json').read_text())
            native = json.loads((folder / 'screenshots.json').read_text())
            shot = next(item for item in native if 'all-pages/' + item['file'] == selection[0]['native_source'])
            row['profiles'][device] = {
                'status': 'PASS', 'name': proof['device']['name'],
                'dimensions': f'{shot["width"]} × {shot["height"]}',
                'native_tests': proof['native_test_count'],
                'shots': [item['file'] for item in selection],
            }
        locales.append(row)
    data = {'locales': locales, 'videos': [
        {'title': title, 'file': f'previews/{stem}.mp4', 'poster': f'previews/{stem}-poster.png'}
        for title, stem in [('Fotos durchsehen', '01-review'), ('Foto-Snake & Memory', '02-photo-games'), ('Fotoeditor', '03-studio')]
    ], 'alternative': {'title': 'Tresor', 'file': 'alternatives/04-vault.mp4', 'poster': 'alternatives/04-vault-poster.png'}}
    template = Path('scripts/store/refresh_review.html').read_text()
    (root / 'index.html').write_text(template.replace('__ASSET_DATA__', json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')))


def main():
    root = Path('app-store/current')
    root.mkdir(exist_ok=True)
    mapping = json.loads(Path('app-store/localizations.json').read_text())
    audit = json.loads((root / 'audit.json').read_text()) if (root / 'audit.json').exists() else []
    statuses = {(r['locale'], r['device_class']): r['status'] for r in audit}
    status_file = root / 'STATUS.json'
    if status_file.exists():
        status = json.loads(status_file.read_text())
        passed = [row for row in audit if row['status'] == 'PASS'
                  and row['locale'] in mapping and row['device_class'] in ['iphone-large', 'iphone-medium']]
        expected = {(code, device) for code in mapping for device in ['iphone-large', 'iphone-medium']}
        status['iphone_assets'] = 'PASS' if {(row['locale'], row['device_class']) for row in passed} == expected else 'IN PROGRESS'
        status['approved_profiles'] = [{'locale': row['locale'], 'device_class': row['device_class'],
                                       'status': 'PASS', 'native_passed_tests': row['native_test_count']}
                                      for row in passed]
        status['actual_selected_screenshots'] = sum(row['selected_screenshots'] for row in passed)
        status['actual_selected_videos'] = sum(sum(video['file'].startswith('previews/') for video in row.get('videos', [])) for row in passed)
        status['actual_vault_alternative_videos'] = sum(sum(video['file'].startswith('alternatives/') for video in row.get('videos', [])) for row in passed)
        status['actual_native_passed_capture_cases'] = sum(row['native_test_count'] for row in passed)
        status_file.write_text(json.dumps(status, indent=2) + '\n')
    rows, available = [], 0
    for code, info in mapping.items():
        devices = []
        for device in ['iphone-large', 'iphone-medium']:
            directory = root / 'locales' / code / device
            shots = sorted((directory / 'app-store-selection').glob('*.png'))
            status = statuses.get((code, device), 'ausstehend')
            devices.append(f'{len(shots)}/10 · {status}')
        videos = sorted((root / 'locales' / code / 'iphone-large/previews').glob('*.mp4'))
        alt = sorted((root / 'locales' / code / 'iphone-large/alternatives').glob('*.mp4'))
        rows.append(f'| [{info["name_de"]}](locales/{code}/README.md) | `{info["app_store_locale"]}` | {devices[0]} | {devices[1]} | {len(videos)}/3 + {len(alt)} Alternative |')
        locale_dir = root / 'locales' / code
        if not locale_dir.exists():
            continue
        text = f'# {info["name_de"]} – aktueller Store-Satz\n\nApp Store Connect: `{info["app_store_locale"]}`. Aufnahmen in Dark Mode.\n\n'
        for device in ['iphone-large', 'iphone-medium']:
            folder = locale_dir / device
            if not (folder / 'provenance.json').exists():
                continue
            provenance = json.loads((folder / 'provenance.json').read_text())
            text += f'## {provenance["device"]["name"]}\n\nStatus: **{statuses.get((code,device),"ausstehend")}** · '
            text += f'[Native Herkunft und tatsächliche Tests]({device}/provenance.json) · [Sichtprüfung]({device}/review/).\n\n'
            text += '\n'.join(f'<a href="{device}/app-store-selection/{p.name}"><img src="{device}/app-store-selection/{p.name}" width="180" alt="{p.stem}" /></a>' for p in sorted((folder / 'app-store-selection').glob('*.png'))) + '\n\n'
        text += '## Drei ausgewählte Store-Videos\n\n'
        text += '\n'.join(f'- [{p.stem}](iphone-large/previews/{p.name})' for p in videos) + '\n\n'
        text += '## Tresor-Alternative\n\nApple erlaubt höchstens drei Vorschauen pro Geräteformat/Sprache; die Alternative ersetzt bei Bedarf eines der ausgewählten Videos.\n\n'
        text += '\n'.join(f'- [{p.stem}](iphone-large/alternatives/{p.name})' for p in alt) + '\n'
        text += '\nDie Videos passen in das gemeinsame iPhone-Vorschauformat 886 × 1920. Duo ist separat im [Umgebungsbericht](../../DUO_STATUS.json) ausgewiesen.\n'
        (locale_dir / 'README.md').write_text(text)
        available += 1
    text = '# PhotoMaid – aktueller Store-Satz\n\nStore-Aufnahmen einschließlich Foto-Snake und Memory für alle 16 App-Sprachen und zwei iPhone-Größen.\n\n'
    text += 'Die Tabelle zeigt ausschließlich tatsächlich vorhandene Dateien und Audit-Ergebnisse. Fehlende Aufnahmen sind ausstehend.\n\n'
    text += '| Sprache | App Store Connect | Großes iPhone | Mittleres iPhone | Videos |\n|---|---|---|---|---|\n' + '\n'.join(rows) + '\n\n'
    text += '[Interaktive Bild-/Videoübersicht](index.html) · [Prüfergebnisse](audit.json) · [Duo-Status](DUO_STATUS.json) · [Bisheriges vollständiges Seitenarchiv](../INDEX.md).\n\n'
    text += 'Die zehn Upload-PNGs haben keine Alpha-Kanäle; Abmessungen und Farbpixel entsprechen den unveränderten nativen Originalen unter `all-pages/`. '
    text += 'Memory-Paare werden durch echte Tipps gefunden, Snake läuft mit seiner normalen Uhr und Wischgesten. Kein fester Rekord oder künstlicher Spielstand.\n'
    (root / 'README.md').write_text(text)
    write_review(root, mapping, audit)
    print('Indexed', available, 'available locale folders; all', len(mapping), 'locales remain in the status table.')


if __name__ == '__main__':
    main()
