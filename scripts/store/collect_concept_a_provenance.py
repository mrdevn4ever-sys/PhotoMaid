#!/usr/bin/env python3
"""Inventory actual native evidence and fail closed; never infer PASS from a filename."""
from __future__ import annotations
import argparse
import datetime
import hashlib
import io
import json
import os
import plistlib
from pathlib import Path
from PIL import Image, ImageCms

BASE_SHA = '583eb804a81401aa2010996875b35d05afc61539'
MEDIA_POLICY = 'approved-stock-photos-and-videos-no-app-screenshots'
REQUIRED = ('swipe', 'duplicates', 'large-files', 'trash', 'delete-confirm', 'vault',
            'later', 'later-swipe', 'months', 'analysis', 'collage', 'editor', 'games')


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def image_record(path, root):
    with Image.open(path) as image:
        image.load()
        alpha = 'A' in image.getbands() or 'transparency' in image.info
        opaque = not alpha or image.convert('RGBA').getchannel('A').getextrema() == (255, 255)
        profile = image.info.get('icc_profile')
        description = None
        if profile:
            try:
                description = ImageCms.getProfileDescription(ImageCms.ImageCmsProfile(io.BytesIO(profile))).strip()
            except Exception:
                description = 'Embedded ICC, description unreadable'
        return {'file': path.relative_to(root).as_posix(), 'sha256': digest(path),
                'bytes': path.stat().st_size, 'width': image.width, 'height': image.height,
                'mode': image.mode, 'opaque': opaque, 'icc_embedded': bool(profile), 'icc_description': description}


def audit_sample_media(library, fixture):
    """Check actual PhotoKit resources, not only the screenshot subtype flag.

    simctl can import a screen PNG as an ordinary photo, so exact fixture-name
    equality and a screenshot-free allowlisted input set are both required.
    """
    errors = []
    assets = library.get('assets', [])
    rows = fixture.get('records', [])
    expected = {Path(row['file']).name: row for row in rows}
    names = [row.get('filename') for row in assets]
    if fixture.get('sample_media_policy') != MEDIA_POLICY:
        errors.append('Fixture must explicitly exclude nested app/UI screenshots')
    if not assets or len(expected) != len(rows) or len(set(names)) != len(names) or set(names) != set(expected):
        errors.append('Actual PhotoKit library must exactly equal the approved photo/video fixture, with no extra app screenshot')
    if any(row.get('isScreenshot') is not False for row in assets):
        errors.append('Actual PhotoKit library contains screenshot or unknown-subtype assets')
    if any(not isinstance(name, str) or not name.startswith('CA_') or name.lower().endswith('.png')
           or 'screenshot' in name.lower() or 'native-library' in name.lower() for name in names):
        errors.append('App/UI screenshot filename found in the actual sample library')
    for asset in assets:
        record = expected.get(asset.get('filename'))
        if record and asset.get('isVideo') is not (record['media_type'] == 'video'):
            errors.append('Actual PhotoKit media type disagrees with imported stock fixture')
    photos = sum(row.get('isVideo') is False for row in assets)
    videos = sum(row.get('isVideo') is True for row in assets)
    if (photos, videos) != (fixture.get('images'), fixture.get('videos')):
        errors.append('Actual stock-only PhotoKit photo/video counts disagree with fixture')
    if (library.get('count'), library.get('photoCount'), library.get('videoCount')) != (len(assets), photos, videos):
        errors.append('Actual exported PhotoKit inventory counters disagree with its resource rows')
    return {'status': 'FAIL' if errors else 'PASS', 'policy': MEDIA_POLICY,
            'actual_asset_count': len(assets), 'actual_photo_count': photos, 'actual_video_count': videos,
            'actual_screenshot_subtype_count': sum(row.get('isScreenshot') is True for row in assets),
            'fixture_filename_set_exact': set(names) == set(expected), 'errors': errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    errors = []

    def load(name):
        try:
            return json.loads((root / name).read_text(encoding='utf-8'))
        except Exception as error:
            errors.append(f'{name}: {type(error).__name__}: {error}')
            return {}

    summary = load('summary.json')
    device = load('device.json')
    fixture = load('fixture-manifest.json')
    if not (summary.get('result') == 'Passed' and summary.get('passedTests') == 1
            and summary.get('failedTests') == 0 and summary.get('skippedTests') == 0):
        errors.append('The exact concept-A capture test must pass once with no failures or skips')
    if not (fixture.get('status') == 'PASS' and fixture.get('images') == 35 and fixture.get('videos') == 2):
        errors.append('The prepared real PhotoKit input library is incomplete')
    visual_gate = fixture.get('visual_source_gate', {})
    if not (visual_gate.get('status') == 'PASS' and visual_gate.get('all_used_sources_approved') is True):
        errors.append('The actual fixture uses no fully approved visual-source allowlist')
    videos = [row for row in fixture.get('records', []) if row.get('media_type') == 'video']
    if len(videos) != 2 or not all(row.get('bytes', 0) > 100_000_000 and row.get('video', {}).get('full_decode') == 'PASS' for row in videos):
        errors.append('Two genuinely measured and fully decoded large-video files are required')
    if not (device.get('name') == 'iPhone 17 Pro' and device.get('device_class') == 'iphone-medium'):
        errors.append('Unexpected native capture device')
    required_files = [f'concept-a-{name}.png' for name in REQUIRED]
    outputs = []
    screenshots = root / 'screenshots'
    for path in sorted(screenshots.glob('*.png')) if screenshots.is_dir() else []:
        # The app additionally exports its transparent native component here. It is
        # NOT a full-screen source; the same original bytes are bound under branding.
        if path.name == 'concept-a-logo.png':
            continue
        try:
            row = image_record(path, root)
            outputs.append(row)
            if path.name in required_files and (row['width'], row['height'], row['opaque']) != (1206, 2622, True):
                errors.append(f'{path.name}: not a genuine opaque 1206x2622 source')
        except Exception as error:
            errors.append(f'{path.name}: {type(error).__name__}: {error}')
    found = {Path(row['file']).name for row in outputs}
    missing = sorted(set(required_files) - found)
    if missing:
        errors.append('Missing required actual native screens: ' + ', '.join(missing))
    required_rows = [row for row in outputs if Path(row['file']).name in required_files]
    if len({row['sha256'] for row in required_rows}) != len(required_rows):
        errors.append('Different required screen states unexpectedly have identical pixel-file hashes')
    logo = root / 'branding/native-wordmark.png'
    branding = image_record(logo, root) if logo.is_file() else None
    if branding is None:
        errors.append('Missing native export of the app-owned canonical wordmark')
    library = load('concept-a-library.json')
    media_audit = audit_sample_media(library, fixture)
    errors.extend(media_audit['errors'])
    if (root / 'stills/concept-a-native-library.fixture.json').exists():
        errors.append('Current stock-only capture must not import an app/UI screenshot into PhotoKit')
    if library:
        media_audit['actual_library_sha256'] = digest(root / 'concept-a-library.json')
    environment = {name: os.environ.get(name) for name in ('GITHUB_SHA', 'GITHUB_RUN_ID', 'GITHUB_REPOSITORY', 'GITHUB_REF_NAME')}
    if not all(environment.values()) or environment['GITHUB_REF_NAME'] != 'hermes/store-concept-a-en':
        errors.append('Actual GitHub exact-run/branch provenance is absent or wrong')
    app_metadata = {}
    runtemp = os.environ.get('RUNNER_TEMP')
    plist = Path(runtemp or '_absent_') / 'store-build/Build/Products/Debug-iphonesimulator/PhotoMaid.app/Info.plist'
    if plist.is_file():
        with plist.open('rb') as stream:
            raw = plistlib.load(stream)
        app_metadata = {key: raw.get(key) for key in ('CFBundleDisplayName', 'CFBundleShortVersionString', 'CFBundleVersion', 'CFBundleIdentifier')}
    if not (app_metadata.get('CFBundleDisplayName') == 'GaleriQ' and app_metadata.get('CFBundleShortVersionString') == '1.0.1'):
        errors.append('Built app does not independently identify as GaleriQ 1.0.1')
    run_id = environment['GITHUB_RUN_ID']
    report = {'schema_version': 1, 'status': 'FAIL' if errors else 'PASS',
              'fresh_capture': True, 'locale': 'en-US', 'app_language': 'en', 'platform': 'iOS Simulator',
              'base_commit': BASE_SHA, 'commit': environment['GITHUB_SHA'],
              'workflow_run': run_id, 'run_attempt': os.environ.get('GITHUB_RUN_ATTEMPT'),
              'workflow_url': f'https://github.com/{environment["GITHUB_REPOSITORY"]}/actions/runs/{run_id}' if run_id else None,
              'branch': environment['GITHUB_REF_NAME'], 'captured_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'app': app_metadata, 'device': device, 'capture_summary': summary,
              'fixture_manifest_sha256': digest(root / 'fixture-manifest.json') if fixture else None,
              'fixture_visual_source_gate': visual_gate,
              'sample_media_policy': MEDIA_POLICY, 'sample_media_audit': media_audit,
              'required_native_screens': required_files, 'outputs': outputs, 'branding': branding,
              'native_visual_acceptance': 'NOT RUN', 'store_export_acceptance': 'NOT RUN',
              'real_device_or_security_acceptance': 'NOT RUN', 'errors': errors}
    (root / 'capture_provenance.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': report['status'], 'native_pngs': len(outputs), 'workflow_run': run_id, 'errors': errors}, ensure_ascii=False))
    if errors:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
