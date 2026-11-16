"""Package only an actually accepted Concept A export. No uploads or ref changes."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def write_verified_archive(archive, members):
    """Byte-preserving exclusive ZIP writer, also exercisable with unit rectangles."""
    need(len(members) == 13, 'Expected ten PNGs, two JPEGs and README')
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as stream:
        for name, raw in members.items():
            stream.writestr(name, raw)
    with zipfile.ZipFile(archive) as stream:
        need(len(stream.namelist()) == 13 and stream.testzip() is None and set(stream.namelist()) == set(members), 'ZIP CRC/membership failed')
        for name, expected in members.items():
            need(stream.read(name) == expected, 'ZIP member byte/hash mismatch: ' + name)


def verify_exact_attempt_readback(readback, provenance, expected_attempt):
    """Bind the saved GET /runs/ID/attempts/N response, not latest-run success."""
    from audit_concept_a import canonical_run_attempt, validate_run_binding
    attempt = validate_run_binding(provenance, provenance['commit'], provenance['workflow_run'], expected_attempt)
    run, actual = readback['run'], readback.get('attempt_readback')
    need(isinstance(actual, dict), 'Exact-attempt API readback is required; latest-run status is insufficient')
    for label, value in (('readback.run_attempt', readback.get('run_attempt')),
                         ('run.runAttempt', run.get('runAttempt')), ('attempt_readback.run_attempt', actual.get('run_attempt'))):
        need(canonical_run_attempt(value, label) == attempt, label + ' differs from independently pinned attempt')
    need(run['status'] == actual.get('status') == 'completed' and run['conclusion'] == actual.get('conclusion') == 'success',
         'Exact native capture attempt has not passed in the actual API readback')
    need(str(run['databaseId']) == str(actual.get('id')) == provenance['workflow_run']
         and run['headSha'] == actual.get('head_sha') == provenance['commit'], 'Exact-attempt API run/SHA binding differs')
    need(run['headBranch'] == actual.get('head_branch') == provenance.get('branch') == 'hermes/store-concept-a-en',
         'Exact-attempt API branch binding differs')
    need(run['event'] == actual.get('event') == 'workflow_dispatch', 'Exact-attempt API capture event differs')
    roots = []
    for label, url in (('provenance.workflow_url', provenance['workflow_url']),
                       ('run.url', run['url']), ('attempt_readback.html_url', actual.get('html_url'))):
        match = re.fullmatch(r'(https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/([1-9][0-9]*))(?:/attempts/([1-9][0-9]*))?', url) if isinstance(url, str) else None
        need(match and match.group(2) == provenance['workflow_run'], label + ' has the wrong run URL')
        need(match.group(3) is None or match.group(3) == str(attempt), label + ' has the wrong attempt URL')
        roots.append(match.group(1))
    need(len(set(roots)) == 1, 'Exact-attempt API repository/run URL differs')
    return attempt


def verify_report_attempts(technical, visual, expected_attempt):
    from audit_concept_a import canonical_run_attempt
    attempt = canonical_run_attempt(expected_attempt, '--expected-run-attempt')
    need(canonical_run_attempt(technical.get('run_attempt'), 'technical.run_attempt') == attempt
         and canonical_run_attempt(visual.get('run_attempt'), 'visual.run_attempt') == attempt, 'Technical/visual QA references another attempt')
    return attempt


def package(render, technical_path, visual_path, readback_path, archive, version, expected_attempt):
    manifest = load(render / 'render-manifest.json')
    need(version == 3 and manifest.get('creativeRevision') == manifest.get('layoutRevision') == manifest.get('nativeRevision') == 3
         and manifest.get('capturePolicy') == 'single-new-green-stock-only-run'
         and manifest.get('nativeScenePolicy') == 'sharp-stock-hero-opaque-confirmation-filled-photo-game'
         and manifest.get('sampleMediaPolicy') == 'approved-stock-photos-and-videos-no-app-screenshots',
         'v3 packaging cannot relabel old full-phone/copy/fixture or mixed-capture exports')
    manifest_sha = sha((render / 'render-manifest.json').read_bytes())
    technical, visual, readback = map(load, (technical_path, visual_path, readback_path))
    provenance = manifest['sourceGate']['provenance']
    run = readback['run']
    attempt = verify_exact_attempt_readback(readback, provenance, expected_attempt)
    from audit_concept_a import verify_manifest_attempt
    verify_manifest_attempt(manifest, attempt)
    verify_report_attempts(technical, visual, attempt)
    need(technical['technical_export_status'] == 'PASS' and technical['png_count'] == 10, 'Independent technical export gate is incomplete')
    need(technical['workflow_run'] == provenance['workflow_run'] and technical['commit'] == provenance['commit'], 'Technical report references another capture')
    need(technical.get('creative_revision') == 3 and technical.get('render_manifest_sha256') == manifest_sha
         and technical.get('design_sha256') == manifest['design']['sha256']
         and technical.get('provenance_sha256') == manifest['sourceGate']['provenanceSHA256']
         and technical.get('required_inset_slots') == [2, 3, 7] and technical.get('subtitle_count') == 10,
         'Technical report must bind this exact v3 manifest/design/provenance/three-inset/subtitle contract')
    need(all(visual.get(k) == v for k, v in {'creative_revision': 3, 'render_manifest_sha256': manifest_sha,
         'design_sha256': manifest['design']['sha256'], 'provenance_sha256': manifest['sourceGate']['provenanceSHA256'],
         'workflow_run': provenance['workflow_run'], 'commit': provenance['commit']}.items()), 'Visual QA is not bound to this exact single-run v3 export')
    # Re-read the exact target instead of accepting a report's asserted PASS alone.
    from audit_concept_a import audit
    actual = audit(render, Path(manifest['sourceGate']['sourceRoot']), provenance['commit'], provenance['workflow_run'], attempt)
    need(actual['images'] == technical['images'] and actual['previews'] == technical['previews']
         and actual['phone_geometry'] == technical['phone_geometry'] and actual['stock_library'] == technical['stock_library']
         and actual['native_scene_audit'] == technical['native_scene_audit'] and actual['native_scene_policy'] == technical['native_scene_policy'],
         'Current original/export pixels or stock-only library differ from the technical review')
    technical_images = {row['file']: row['sha256'] for row in technical['images']}
    need(len(technical['images']) == len(technical_images) == 10, 'Ten actual technical output hashes required')
    need(visual['status'] in ('PASS', 'PASS_WITH_OBSERVATIONS') and visual['blockers'] == [], 'Final visual blockers remain')
    outputs = manifest['outputs']
    need(len(outputs) == 10 and [row['slot'] for row in outputs] == list(range(1, 11)), 'Ten ordered outputs are required')
    need(len(visual['images']) == 10 and len({row['file'] for row in visual['images']}) == 10, 'Exactly ten individual visual reviews are required')
    reviews = {row['file']: row for row in visual['images']}
    reviewed_previews = {row['file']: row for row in visual['previews']}
    need(len(visual['previews']) == len(reviewed_previews) == 2 and set(reviewed_previews) == {'00-overview.jpg', '00-search-preview.jpg'}, 'Exactly two preview reviews required')
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
        need(Path(name).name == name and name in reviewed_previews and sha(raw) == row['sha256'] == reviewed_previews[name]['sha256'], 'Preview changed after review')
        need(reviewed_previews[name]['reviewed'] is True and reviewed_previews[name]['status'] in ('PASS', 'PASS_WITH_OBSERVATIONS'), 'Actual preview visual review missing')
        members[name] = raw
    need(set(members) == {'en-US/' + row['file'] for row in outputs} | {'00-overview.jpg', '00-search-preview.jpg'}, 'Unexpected/missing package assets')
    notes = visual.get('notes', [])
    geometry = actual['phone_geometry']
    stock = actual['stock_library']
    inset_lines = []
    for output in outputs:
        for inset in output['protectedEvidence']['insets']:
            layer = next(layer for layer in output['nativeLayers'] if layer['id'] == inset['id'])
            inset_lines.append(f"- Bild{output['slot']:02d}: {inset['id']}; {inset['source']}; SHA256 {layer['sourceSHA256']}; "
                               f"Original-Crop {inset['crop']}; Ziel {inset['target']}; native Skalierung {inset['nativeScale']:.6f}; "
                               f"Vergrößerung gegenüber Haupttelefon {inset['magnificationRelativeToPhone']:.3f}×.")
    copy_lines = [f"{row['slot']:02d}. {row['headline']['text']}\n    {row['subtitle']['text']}" for row in outputs]
    readme = f'''GaleriQ – Konzept A „Space to Breathe“ – en-US – v{version}

Inhalt: exakt 13 Archivmitglieder
10 verlustfreie PNGs, 1206 × 2622 Pixel, 8-Bit-RGB, kein Alpha, eingebettetes sRGB.
00-overview.jpg: alle zehn Motive in einer horizontalen Reihe.
00-search-preview.jpg: die ersten drei Motive, 390px breite Suchansicht.
README.txt: diese Quellen-, Geometrie- und Prüfhinweise.

Genau eine neue echte native Aufnahme
Branch: hermes/store-concept-a-en
Basis-Commit: {provenance['base_commit']}
Tatsächlich aufgenommener App-Commit: {provenance['commit']}
GaleriQ 1.0.1; iPhone-17-Pro-Simulator; App-Sprache en, Marketing en-US.
Einziger Aufnahme-Run: {provenance['workflow_run']}
Exakter Aufnahme-Attempt: {attempt}; Erfolg aus dem gespeicherten exakten Attempts-API-Readback.
Workflow-URL: {run['url']}
Quellenartefakt-ID: {readback.get('artifact_id', 'siehe Run')}
Originalquellen: {readback['evidence_path']}
Provenienz SHA256: {manifest['sourceGate']['provenanceSHA256']}
Render-Manifest SHA256: {manifest_sha}
Design SHA256: {manifest['design']['sha256']}
Renderer: {manifest['renderer']['path']}; SHA256 {manifest['renderer']['sha256']}
Python {manifest['renderer']['pythonVersion']}; Pillow {manifest['renderer']['pillowVersion']}.
Keine gemischten Runs und keine alten v2/C5-Captures als Finalquellen.

Native Beispielmedien: ausschließlich geprüfte Stockfotos und echte Videos
Policy: {stock['policy']}
Tatsächliche initiale PhotoKit-Bibliothek: {stock['actual_photo_count']} Fotos,
{stock['actual_video_count']} Videos, {stock['actual_asset_count']} eindeutige Ressourcen.
PhotoKit-JSON SHA256: {stock['actual_library_sha256']}
Dateinamen und Medientypen stimmen exakt mit der hashgebundenen Fixture überein.
Keine App-/UI-Screenshots als Testfoto, nächste Karte, Miniatur, Dialogvorschau,
Collage- oder Spielfoto. Frühere Screenshot-Fixtures wurden nicht weiterverwendet.
Die echte unveränderte native App-Oberfläche selbst ist die Produktevidenz.

Bewusste v3-Geometrie – NICHT vollständig sichtbare Telefone
Alle zehn iPhones besitzen dieselbe vollständige Zielgeometrie und Position.
Referenz v2: Bildschirm [201, 760, 1005, 2508], 804 × 1748 Pixel.
Vollständiges v3-Ziel: {geometry['fullTargetGeometry']}.
Tatsächlich sichtbarer Bildschirm: {geometry['visibleGeometry']}.
Vollständiger Hardware-Rahmen: {geometry['fullFrameGeometry']}.
Sichtbarer Hardware-Rahmen: {geometry['visibleFrameGeometry']}.
Größenfaktor gegenüber v2: {geometry['sizeRelativeToV2XY'][0]:.6f}× horizontal,
{geometry['sizeRelativeToV2XY'][1]:.6f}× vertikal; innerhalb 15–20% Vergrößerung.
Viewport-Abschneidung: ausschließlich unten, {geometry['viewportClipPixels']['bottom']} Zielpixel.
Originalquelle bleibt [0, 0, 1206, 2622]; sichtbare Originalkoordinaten:
{geometry['visibleSourceBounds']} (Resample-Viewport-Grenzen, keine erfundenen Crop-Pixel).
Bekannte proportionale LANCZOS-Verkleinerung mit maximal 0,5px Rundung je Achse;
kein natives Upscaling, keine Rotation, keine gestauchte oder nachgebaute UI.
Nur obere/linke/rechte Rahmenabschnitte sind vollständig sichtbar; unten bewusst angeschnitten.
Alle sichtbaren vollständig opaken Rahmenpixel wurden tatsächlich gegen die Exportpixel geprüft.
Originale native VaultDialWordmark mit originalem Alpha/Tresor-Q, nicht nachgezeichnet.
Eisblau, Fonts und Farben unverändert; keine Seitennummern oder wiederholter Slogan.

Genau drei erlaubte native Fokusdetails
Bild02: vollständiges echtes Duplikatpaar mit seinen nativen Auswahl-Labels.
Bild03: ganze echte deckende iOS-Bestätigung mit Originaltext, Vorschau und beiden
Buttons, durch tatsächliche Frame-JSON-Datei und Quellhash gebunden. Kein Ladekreisel.
Bild07: echte Serie und nativer „Keep 5 · Trash 1“-Button gemeinsam in einem Crop.
Kein zusammengesetzter Dialog, keine künstlichen Buttons, kein Retuschieren der Quellen.
Alle Fokus-Crops bleiben vollständig im sichtbaren Display. Schatten dürfen nur unten
am Viewportrand auslaufen; obere/linke/rechte Hardware-Rahmenpixel bleiben unverdeckt.
''' + '\n'.join(inset_lines) + '''

Copy: jedes Bild mit kurzem Untertitel
''' + '\n'.join(copy_lines) + f'''

Bild01 verwendet ein klar erkennbares echtes Stock-Startmotiv statt App-Screenshot.
Bild05 zeigt den echten gehaltenen Rechts-Swipe „Later“.
Bild10 zeigt ein tatsächlich gefülltes natives Photo-Pairs-Spielbrett, nicht das
kleine Drei-Karten-Spielemenü mit leerer unterer Fläche.
Tresor- und Geschäftsmodell-Untertitel blieben wörtlich unverändert.

Schriftregel
Höchstens zwei Zeilen je Headline und Untertitel. Wortumbruch, dann in 1px-Schritten
verkleinern; mindestens 84px Headline und 46px Untertitel. Kein Abschneiden/Umschreiben.
Andere Sprachen/RTL erst nach gesonderter ausdrücklicher Freigabe und Quellenprüfung.

Prüfstatus
PASS: ein echter nativer Aufnahme-XCTest ohne Fehler oder Skips, grüner exakter Run.
PASS: jede Quelle aus demselben stock-only Run, exakte Source-QA-/Provenienz-Bindung.
PASS: neu berechnete v3-Szenen-/Hash-Prüfung: tatsächliches scharfes Startfoto,
Reduce Transparency über reale iOS-Einstellungen, stabiler ganzer nativer Dialog
und echtes 24-Karten-Photo-Pairs-Spiel mit mindestens sechs gematchten Karten.
PASS: alle zehn individuellen technischen PNG-Hashes und beide JPEG-Hashes.
PASS: unabhängiger exakter Pixelvergleich der sichtbaren nativen Originale inklusive
letzter sichtbarer Zeile und original-alpha Wordmark; definierte ICC-Normalisierung,
proportionales Resampling, explizite Sichtbarkeitsmasken und tatsächliche Rahmenpixel.
{visual['status']}: jedes PNG einzeln in voller und kleiner Größe sowie beide Previews.
Nicht behauptet: Pixelgleichheit unsichtbarer/off-canvas Bereiche oder vollständige Telefone.
NOT RUN: reale Geräte-, Sicherheits-, Face-ID-/Conversion- oder Store-Upload-Abnahme.
Keine Veröffentlichung, Einreichung, Release, PR oder Merge durch diesen Packager.
Vorherige v1/v2-Medien und Archive bleiben unverändert; neue Dateien exklusiv erstellt.

Beobachtungen / unveränderte native UI
'''
    readme += '\n'.join('- ' + str(note) for note in notes) if notes else '- Keine bekannten visuellen Pflichtblocker.'
    readme += '\n\nNur en-US; weitere Sprachen erst nach ausdrücklichem Nutzer-Feedback.\n'
    members['README.txt'] = readme.encode('utf-8')
    need(len(members) == 13, 'Expected exactly ten PNGs, two JPEGs and README')
    expected_name = f'GaleriQ-Konzept-A-en-US-v{version}.zip'
    need(archive.name == expected_name and version >= 1, 'Versioned archive name differs')
    write_verified_archive(archive, members)
    receipt = {'status': 'PASS', 'archive': str(archive), 'archive_sha256': sha(archive.read_bytes()),
               'archive_bytes': archive.stat().st_size, 'member_count': len(members),
               'members': [{'file': name, 'sha256': sha(raw), 'bytes': len(raw)} for name, raw in members.items()],
               'workflow_run': provenance['workflow_run'], 'run_attempt': attempt, 'capture_commit': provenance['commit'],
               'native_readback_sha256': sha(readback_path.read_bytes()),
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
    parser.add_argument('--expected-run-attempt', required=True)
    args = parser.parse_args()
    print(json.dumps(package(args.render, args.technical, args.visual, args.native_readback, args.archive, args.version, args.expected_run_attempt), ensure_ascii=False))
