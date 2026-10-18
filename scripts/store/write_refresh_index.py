#!/usr/bin/env python3
"""Build an index from current files and measured statuses; missing locales stay visibly pending."""
import html
import json
from pathlib import Path


def main():
    root = Path('app-store/current')
    root.mkdir(exist_ok=True)
    mapping = json.loads(Path('app-store/localizations.json').read_text())
    audit = json.loads((root / 'audit.json').read_text()) if (root / 'audit.json').exists() else []
    statuses = {(r['locale'], r['device_class']): r['status'] for r in audit}
    rows, sections = [], []
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
        sections.append(f'<section id="{code}"><h2>{html.escape(info["name_de"])}</h2><p><a href="locales/{code}/README.md">Bilder, Videos und Nachweise öffnen</a></p></section>')
    text = '# PhotoMaid – aktueller Store-Satz\n\nStore-Aufnahmen einschließlich Foto-Snake und Memory für alle 16 App-Sprachen und zwei iPhone-Größen.\n\n'
    text += 'Die Tabelle zeigt ausschließlich tatsächlich vorhandene Dateien und Audit-Ergebnisse. Fehlende Aufnahmen sind ausstehend.\n\n'
    text += '| Sprache | App Store Connect | Großes iPhone | Mittleres iPhone | Videos |\n|---|---|---|---|---|\n' + '\n'.join(rows) + '\n\n'
    text += '[Prüfergebnisse](audit.json) · [Duo-Status](DUO_STATUS.json) · [Bisheriges vollständiges Seitenarchiv](../INDEX.md).\n\n'
    text += 'Die zehn Upload-PNGs haben keine Alpha-Kanäle; Abmessungen und Farbpixel entsprechen den unveränderten nativen Originalen unter `all-pages/`. '
    text += 'Memory-Paare werden durch echte Tipps gefunden, Snake läuft mit seiner normalen Uhr und Wischgesten. Kein fester Rekord oder künstlicher Spielstand.\n'
    (root / 'README.md').write_text(text)
    (root / 'index.html').write_text('<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>PhotoMaid – Store-Assets</title><style>body{margin:40px auto;padding:0 20px;max-width:1100px;background:#141b18;color:#edf5ef;font:17px system-ui}a{color:#9adeaa}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:16px}section{padding:22px;background:#202c25;border-radius:20px}h1{font-size:40px}</style><h1>PhotoMaid · Store-Assets</h1><p>Alle vorhandenen Sprachsätze mit Bildern, Videos und Prüfnachweisen.</p><p><a href="README.md">Vollständige Statusübersicht</a></p><main>' + ''.join(sections) + '</main></html>')
    print('Indexed', len(sections), 'available locale folders; all', len(mapping), 'locales remain in the status table.')


if __name__ == '__main__':
    main()
