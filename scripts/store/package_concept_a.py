"""Package only an actually accepted Concept A export. No uploads or ref changes."""
from __future__ import annotations
import argparse
import hashlib
import json
import zipfile
from pathlib import Path


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def package(render, technical_path, visual_path, readback_path, archive, version):
    manifest = load(render / 'render-manifest.json')
    technical, visual, readback = map(load, (technical_path, visual_path, readback_path))
    provenance = manifest['sourceGate']['provenance']
    run = readback['run']
    need(run['status'] == 'completed' and run['conclusion'] == 'success', 'Actual native workflow has not passed')
    need(str(run['databaseId']) == provenance['workflow_run'] and run['headSha'] == provenance['commit'], 'Run/SHA binding differs')
    need(run['headBranch'] == 'hermes/store-concept-a-en', 'Wrong native capture branch')
    need(technical['technical_export_status'] == 'PASS' and technical['png_count'] == 10, 'Independent technical export gate is incomplete')
    need(technical['workflow_run'] == provenance['workflow_run'] and technical['commit'] == provenance['commit'], 'Technical report references another capture')
    technical_images = {row['file']: row['sha256'] for row in technical['images']}
    need(len(technical['images']) == len(technical_images) == 10, 'Ten actual technical output hashes required')
    need(visual['status'] in ('PASS', 'PASS_WITH_OBSERVATIONS') and visual['blockers'] == [], 'Final visual blockers remain')
    outputs = manifest['outputs']
    need(len(outputs) == 10 and [row['slot'] for row in outputs] == list(range(1, 11)), 'Ten ordered outputs are required')
    need(len(visual['images']) == 10 and len({row['file'] for row in visual['images']}) == 10, 'Exactly ten individual visual reviews are required')
    reviews = {row['file']: row for row in visual['images']}
    reviewed_previews = {row['file']: row for row in visual['previews']}
    members = {}
    for row in outputs:
        name = row['file']
        need(Path(name).name == name and name in reviews, 'Missing/unsafe individual review target')
        raw = (render / name).read_bytes()
        need(sha(raw) == row['sha256'] == reviews[name]['sha256'] == technical_images.get(name), 'Final PNG differs from actual technical or visual review')
        need(reviews[name]['full_size_reviewed'] is True and reviews[name]['search_scale_reviewed'] is True
             and reviews[name]['status'] in ('PASS', 'PASS_WITH_OBSERVATIONS'), 'Individual full/thumbnail QA is incomplete')
        members['en-US/' + name] = raw
    for row in manifest['previews']:
        name = row['file']
        raw = (render / name).read_bytes()
        need(name in reviewed_previews and sha(raw) == row['sha256'] == reviewed_previews[name]['sha256'], 'Preview changed after review')
        need(reviewed_previews[name]['reviewed'] is True and reviewed_previews[name]['status'] in ('PASS', 'PASS_WITH_OBSERVATIONS'), 'Actual preview visual review missing')
        members[name] = raw
    need(set(members) == {'en-US/' + row['file'] for row in outputs} | {'00-overview.jpg', '00-search-preview.jpg'}, 'Unexpected/missing package assets')
    notes = visual.get('notes', [])
    readme = f'''GaleriQ – Konzept A „Space to Breathe“ – en-US – v{version}

Inhalt
10 verlustfreie PNGs, 1206 × 2622 Pixel, 8-Bit-RGB, kein Alpha, eingebettetes sRGB.
00-overview.jpg: alle zehn Motive in einer horizontalen Reihe.
00-search-preview.jpg: erste drei Motive in 390px Suchskalierung.

Quelle und Reproduzierbarkeit
Repo: https://github.com/mrdevn4ever-sys/photomaid
Eigener Branch: hermes/store-concept-a-en
Basisbranch: claude/galeriq-localization-1-0-1-bgpw9u
Basis-Commit: {provenance['base_commit']}
Tatsächlich aufgenommener App-Commit: {provenance['commit']}
App: GaleriQ 1.0.1; echter iPhone-17-Pro-Simulator; App-Sprache en.
Aufnahme-Workflow-Run: {provenance['workflow_run']}
Workflow-URL: {run['url']}
Quellenartefakt-ID: {readback.get('artifact_id', 'siehe Run')}
Originalquellen lokal archiviert: {readback['evidence_path']}
Provenienzdatei SHA256: {manifest['sourceGate']['provenanceSHA256']}
Render-Design SHA256: {manifest['design']['sha256']}
Renderer: {manifest['renderer']['path']}
Renderer SHA256: {manifest['renderer']['sha256']}
Renderumgebung: Python {manifest['renderer']['pythonVersion']}, Pillow {manifest['renderer']['pillowVersion']}.
Verworfene Aufnahme-Runs: 43770703076, 43772843048 (fehlgeschlagen; keine Finalquellen).

Änderungen gegenüber der Referenz
- Neue Reihenfolge: Swipe, Duplikate/große Dateien, Löschsicherheit, Tresor,
  Später, Monate, Serienvergleich, Collage, Editor, Spiele.
- Frische echte App-Aufnahmen, reale Duplikate und gemessene große Videodateien.
- Einheitliches vollständiges iPhone, gleiche Größe und Position, weicher Eisblau-Verlauf.
- Keine Seitennummern und kein wiederholter „SPACE TO BREATHE“-Slogan.
- Originale native GaleriQ-Wordmark mit echtem Tresor-Q, nicht nachgezeichnet.
- Fokusdetails aus echten Originalaufnahmen, keine nachgebaute oder retuschierte UI.
- Sämtliche Fokusdetails samt Schatten innerhalb des Displays; alle Rahmenabschnitte frei.
- Bild03 zeigt die ganze echte Systembestätigung in der unveränderten nativen Ansicht.
- Exakte englische Headlines und geforderte Tresor-/Geschäftsmodell-Untertexte.
- Neutrale, lizenzierte CC0-Fotofixtures; erklärte Fotoderivate wurden vor dem Import
  erstellt, niemals als Retusche der App-Oberfläche oder als Scan-Ergebnis-Injektion.

Schriftregel für spätere freigegebene Sprachen
Höchstens zwei Zeilen pro Headline/Untertitel. Umbruch an Wortgrenzen, anschließend
schrittweise um 1px verkleinern. Mindestgrößen: Headline 84px; Untertitel 46px.
Wenn es dann nicht passt: harter Abbruch statt Abschneiden, Stauchen oder Umschreiben.
RTL benötigt eine gesonderte Shaping-/Spiegelungs-/Quellenprüfung und ist nicht abgenommen.

Prüfstatus
PASS: nativer Build und genau ein bestandener Aufnahme-XCTest ohne Skips.
PASS: zehn PNGs, Maße/RGB/kein Alpha/sRGB, Originalquellen- und Ausgabedatei-Hashes.
PASS: unabhängiger Pixelvergleich gegen echte farbverwaltete Original-Captures;
      dokumentierte proportionale Verkleinerung, kein Upscaling der nativen UI.
PASS: echte Rahmenpixel aller zehn Bilder unverdeckt und identisch geprüft.
{visual['status']}: jedes Finalbild einzeln sowie Übersicht und erste-drei-Suchansicht.
BLOCKED: exakter nativer Wortlaut „Remove 2 photos“; tatsächlich „Remove 2 photos and videos“.
NOT RUN: zusätzliche reale Geräte-/Sicherheits-/Conversion-Abnahme.
Nicht ausgeführt: App Store Connect, Einreichung, Release, PR oder Merge.
Bestehende Store-Medien und andere Branches wurden nicht ersetzt.

Beobachtungen / unveränderte Original-UI
'''
    readme += '\n'.join('- ' + str(note) for note in notes) if notes else '- Keine bekannten visuellen Pflichtblocker.'
    readme += '\n\nNur en-US. Andere Sprachen erst nach ausdrücklicher Nutzerfreigabe „perfekt“.\n'
    members['README.txt'] = readme.encode('utf-8')
    need(len(members) == 13, 'Expected exactly ten PNGs, two JPEGs and README')
    expected_name = f'GaleriQ-Konzept-A-en-US-v{version}.zip'
    need(archive.name == expected_name and version >= 1, 'Versioned archive name differs')
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as stream:
        for name, raw in members.items():
            stream.writestr(name, raw)
    with zipfile.ZipFile(archive) as stream:
        need(stream.testzip() is None and set(stream.namelist()) == set(members), 'ZIP CRC/membership failed')
        for name, expected in members.items():
            need(stream.read(name) == expected, 'ZIP member byte/hash mismatch: ' + name)
    receipt = {'status': 'PASS', 'archive': str(archive), 'archive_sha256': sha(archive.read_bytes()),
               'archive_bytes': archive.stat().st_size, 'member_count': len(members),
               'members': [{'file': name, 'sha256': sha(raw), 'bytes': len(raw)} for name, raw in members.items()],
               'workflow_run': provenance['workflow_run'], 'capture_commit': provenance['commit'],
               'technical_report_sha256': sha(technical_path.read_bytes()), 'visual_report_sha256': sha(visual_path.read_bytes()),
               'external_publication': 'NOT RUN; local lossless delivery archive only'}
    report = archive.with_suffix('.verification.json')
    with report.open('x', encoding='utf-8') as stream:
        json.dump(receipt, stream, ensure_ascii=False, indent=2)
    return {key: value for key, value in receipt.items() if key != 'members'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', required=True, type=Path)
    parser.add_argument('--technical', required=True, type=Path)
    parser.add_argument('--visual', required=True, type=Path)
    parser.add_argument('--native-readback', required=True, type=Path)
    parser.add_argument('--archive', required=True, type=Path)
    parser.add_argument('--version', required=True, type=int)
    args = parser.parse_args()
    print(json.dumps(package(args.render, args.technical, args.visual, args.native_readback, args.archive, args.version), ensure_ascii=False))
