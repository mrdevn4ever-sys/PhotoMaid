#!/usr/bin/env python3
"""Build the separate Concept A v4 stock-only disposable PhotoKit fixture.

The owner-curated --sources/manifest.json must contain exactly 15 original JPEGs,
with explicit integer capture_role values, and --allowlist is mandatory. Neither
inherited filename prefixes nor the old 55-photo manifest establish a v4 role.
No downloads, source edits, screenshots, file padding, or upscaling are allowed.
The unchanged CA resource names retain compatibility with the native capture.
--skip-videos produces IMAGES_ONLY_NOT_CAPTURE_READY, never capture PASS.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
import threading
from pathlib import Path
from urllib.parse import urlsplit

from PIL import Image, ImageEnhance, ImageFile, ImageFilter, ImageOps

ROLES = (1, 4, 5, 6, 7, 9, 10, 13, 28, 29, 31, 33, 35, 36, 38)
PRETTY_ROLES = (5, 10, 1, 4, 6, 7, 9, 13, 28, 29, 31, 33, 35, 36)
DERIVATIVE_ROLES = (5, 10, 1, 4, 6, 7, 13, 35, 5, 7)
VIDEO_ROLES = (13, 35)
MEDIA_POLICY = 'approved-stock-photos-and-videos-no-app-screenshots'
REPO_ROOT = Path(__file__).resolve().parents[2]
SHA256 = re.compile(r'[0-9a-f]{64}')
JPEG_SAVE_LOCK = threading.Lock()


def need(condition: bool, message: str) -> None:
    # Unlike assert, these input gates remain active under python -O.
    if not condition:
        raise ValueError(message)


def digest(path: Path) -> str:
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def _unique_object(pairs):
    value = {}
    for key, item in pairs:
        need(key not in value, 'Duplicate JSON key: ' + key)
        value[key] = item
    return value


def load_json(path: Path) -> dict:
    value = json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=_unique_object,
                       parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Nonfinite JSON: ' + value)))
    need(type(value) is dict, f'{path}: JSON object required')
    return value


def _text(value) -> bool:
    return type(value) is str and bool(value.strip()) and value == value.strip()


def _url(value) -> bool:
    if not _text(value):
        return False
    parsed = urlsplit(value)
    return parsed.scheme in ('https', 'http') and bool(parsed.hostname) and not parsed.username and not parsed.password


def _filename(value) -> bool:
    return (_text(value) and '/' not in value and '\\' not in value and ':' not in value
            and value not in ('.', '..') and not any(ord(char) < 32 for char in value)
            and Path(value).suffix.lower() in ('.jpg', '.jpeg')
            and not any(word in value.lower() for word in ('screenshot', 'app-screen', 'native-library')))


def validate_registry(registry: dict, allowlist: dict) -> dict[int, dict]:
    """Validate metadata without trusting counts, coercing roles, or repairing hashes."""
    photos = registry.get('photos')
    need(type(photos) is list and len(photos) == 15, 'v4 registry must contain exactly 15 originals')
    need(all(type(row) is dict for row in photos), 'Registry photo rows must be objects')
    roles, names, hashes = [], [], []
    for row in photos:
        name, role = row.get('file'), row.get('capture_role')
        need(_filename(name), f'Unsafe/non-photo source filename: {name!r}')
        need(type(role) is int and role in ROLES, f'{name}: explicit integer capture_role required')
        need(type(row.get('sha256')) is str and SHA256.fullmatch(row['sha256']) is not None,
             f'{name}: literal lowercase source SHA-256 required')
        need(row.get('license') == 'CC0-1.0', f'{name}: CC0-1.0 required')
        need(_url(row.get('source')) and _text(row.get('author')), f'{name}: source URL and author required')
        license_url = row.get('license_url')
        need(_url(license_url) and urlsplit(license_url).hostname == 'creativecommons.org'
             and re.fullmatch(r'/publicdomain/zero/1\.0/(?:deed\.[a-zA-Z_-]+)?', urlsplit(license_url).path) is not None,
             f'{name}: genuine CC0 license URL required')
        need(all(type(row.get(key)) is int and row[key] > 0 for key in ('width', 'height')),
             f'{name}: positive integer original dimensions required')
        roles.append(role)
        names.append(name)
        hashes.append(row['sha256'])
    need(set(roles) == set(ROLES) and len(set(roles)) == 15, 'v4 capture_role set must exactly match the 15 locked roles')
    need(len(set(names)) == len({name.casefold() for name in names}) == 15, 'Original filenames must be unique, including case')
    need(len(set(hashes)) == 15, 'The registry must contain 15 distinct original hashes')
    approved = allowlist.get('approved')
    need(allowlist.get('status') == 'PASS_SELECTED_SUBSET_ONLY', 'Selected-subset visual approval required')
    need(type(allowlist.get('approved_count')) is int and allowlist['approved_count'] == 15
         and type(approved) is list and len(approved) == 15, 'Exactly 15 explicit approved rows required')
    approved_by_name = {}
    for row in approved:
        need(type(row) is dict and _filename(row.get('source')) and row.get('verdict') == 'PASS',
             'Every selected allowlist row must be an explicit PASS original')
        need(type(row.get('sha256')) is str and SHA256.fullmatch(row['sha256']) is not None,
             'Allowlist requires literal lowercase SHA-256 values')
        need(row['source'] not in approved_by_name, 'Duplicate allowlist original: ' + row['source'])
        if 'capture_role' in row:
            original_role = next((photo['capture_role'] for photo in photos if photo['file'] == row['source']), None)
            need(type(row['capture_role']) is int and row['capture_role'] == original_role,
                 'Allowlist capture_role disagrees with its exact registry original')
        approved_by_name[row['source']] = row['sha256']
    need(approved_by_name == dict(zip(names, hashes)), 'Registry and approved original filename/hash sets must be exactly equal')
    return {row['capture_role']: row for row in photos}


def load_sources(source: Path, allowlist_path: Path) -> tuple[dict[int, dict], str, str]:
    """Read and fully decode every approved original before any fixture write."""
    source, allowlist_path = Path(source).resolve(), Path(allowlist_path).resolve()
    manifest_path = source / 'manifest.json'
    manifest_sha, allowlist_sha = digest(manifest_path), digest(allowlist_path)
    roles = validate_registry(load_json(manifest_path), load_json(allowlist_path))
    for row in roles.values():
        path = source / row['file']
        need(path.is_file() and not path.is_symlink() and path.resolve().parent == source,
             'Source must be a regular original inside its registry folder: ' + row['file'])
        need(digest(path) == row['sha256'], 'Original SHA-256 mismatch: ' + row['file'])
        with Image.open(path) as image:
            need(image.format == 'JPEG', 'Original must decode as a real JPEG: ' + row['file'])
            image.load()
            need(image.size == (row['width'], row['height']), 'Original dimension metadata mismatch: ' + row['file'])
            if 'bytes' in row:
                need(type(row['bytes']) is int and row['bytes'] == path.stat().st_size,
                     'Original byte metadata mismatch: ' + row['file'])
    need(digest(manifest_path) == manifest_sha and digest(allowlist_path) == allowlist_sha,
         'Registry/allowlist changed during validation')
    return roles, manifest_sha, allowlist_sha


def expected_image_roles() -> dict[str, int]:
    return {
        'CA_01_clutter_blur.jpg': 5, 'CA_02_clutter_shake.jpg': 10, 'CA_03_clutter_dark.jpg': 5,
        'CA_10_duplicate_a.jpg': 38, 'CA_11_duplicate_b.jpg': 38,
        **{f'CA_20_series_{n:02d}.jpg': 36 for n in range(1, 7)},
        **{f'CA_30_pretty_{n:02d}.jpg': role for n, role in enumerate(PRETTY_ROLES + DERIVATIVE_ROLES, 1)},
    }


def save_derivative_jpeg(image: Image.Image, destination: Path) -> None:
    # Pillow guesses only width*height bytes for optimized quality-94 JPEGs.
    # High-entropy 4:4:4 photos can exceed that buffer (libjpeg: "Suspension not
    # allowed here"). Supply raw-pixel headroom, not padding in the output file.
    # This is process-local, restored on errors, and never changes image pixels.
    with JPEG_SAVE_LOCK:
        previous = ImageFile.MAXBLOCK
        try:
            ImageFile.MAXBLOCK = max(previous, image.width * image.height * 4)
            image.save(destination, 'JPEG', quality=94, subsampling=0, optimize=True)
        finally:
            ImageFile.MAXBLOCK = previous


def build_fixture(sources: Path, allowlist_path: Path, output: Path, *, skip_videos: bool = False,
                  video_count: int = 2) -> dict:
    source, output, allowlist_path = Path(sources).resolve(), Path(output).resolve(), Path(allowlist_path).resolve()
    need(type(skip_videos) is bool and type(video_count) is int and video_count == 2,
         'v4 requires exactly two videos (or explicit image-only preparation)')
    need(output != source and source not in output.parents, 'Fixture output must be outside the protected source folder')
    need(output != REPO_ROOT and REPO_ROOT not in output.parents, 'Runtime fixture output must remain outside the repository')
    need(not output.exists() or (output.is_dir() and not any(output.iterdir())), 'Refusing to overwrite a nonempty fixture directory')
    roles, source_manifest_sha, allowlist_sha = load_sources(source, allowlist_path)
    ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    if not skip_videos:
        need(bool(ffmpeg and ffprobe), 'ffmpeg and ffprobe must already be installed; no installation is attempted')
        for role in VIDEO_ROLES:
            with Image.open(source / roles[role]['file']) as image:
                oriented = ImageOps.exif_transpose(image)
                need(oriented.width >= 1920 and oriented.height >= 1080,
                     f'Video capture_role {role}: source cannot fill 1920x1080 without upscaling')
    output.mkdir(parents=True, exist_ok=True)
    records = []

    def source_fields(role):
        row = roles[role]
        return {'capture_role': role, 'source': row['file'], 'source_sha256': row['sha256'],
                'source_url': row['source'], 'author': row['author'], 'license': row['license'],
                'license_url': row['license_url'], 'source_width': row['width'], 'source_height': row['height']}

    def add(name, role, category, transform=None, details='Unchanged source bytes'):
        row = roles[role]
        src, dst = source / row['file'], output / name
        need(digest(src) == row['sha256'], 'Original changed after validation: ' + row['file'])
        if transform is None:
            shutil.copyfile(src, dst)
        else:
            with Image.open(src) as image:
                original = ImageOps.exif_transpose(image).convert('RGB')
                result = transform(original)
                need(0 < result.width <= original.width and 0 < result.height <= original.height,
                     name + ': empty crop or prohibited upscaling')
                save_derivative_jpeg(result, dst)
        with Image.open(dst) as image:
            image.load()
            size = list(image.size)
        records.append({'file': name, 'category': category, 'media_type': 'image', 'sha256': digest(dst),
                        'bytes': dst.stat().st_size, 'size': size, **source_fields(role), 'adaptation': details})

    add('CA_01_clutter_blur.jpg', 5, 'clutter-blurry', lambda image: image.filter(ImageFilter.GaussianBlur(26)),
        'CC0 cat-photo fixture derivative: 26px defocus; no upscale')
    add('CA_02_clutter_shake.jpg', 10, 'clutter-challenging', lambda image: image.filter(ImageFilter.GaussianBlur(18)),
        'CC0 everyday-photo fixture derivative: 18px defocus; no upscale')
    add('CA_03_clutter_dark.jpg', 5, 'clutter-dark', lambda image: ImageEnhance.Brightness(image).enhance(0.25),
        'CC0 cat-photo fixture derivative: brightness factor 0.25; no upscale')
    add('CA_10_duplicate_a.jpg', 38, 'exact-duplicate')
    add('CA_11_duplicate_b.jpg', 38, 'exact-duplicate')
    for index in range(6):
        def variation(image, index=index):
            inset = index * 5
            need(image.width > 2 * inset and image.height > 2 * inset, 'Dog-series source too small for declared crop')
            return ImageEnhance.Brightness(image.crop((inset, inset, image.width - inset, image.height - inset))).enhance(0.98 + index * 0.008)
        add(f'CA_20_series_{index + 1:02d}.jpg', 36, 'near-similar-series', variation,
            f'CC0 dog-photo fixture derivative: crop inset {index * 5}px; exposure factor {0.98 + index * 0.008:.3f}; no upscale')
    for index, role in enumerate(PRETTY_ROLES, 1):
        add(f'CA_30_pretty_{index:02d}.jpg', role, 'pretty')
    for offset, role in enumerate(DERIVATIVE_ROLES):
        inset, exposure = 48 + offset * 7, 1.04 + offset * 0.005
        def variation(image, inset=inset, exposure=exposure):
            need(image.width > 2 * inset and image.height > 2 * inset, 'Source too small for declared fixture crop')
            return ImageEnhance.Brightness(image.crop((inset, inset, image.width - inset, image.height - inset))).enhance(exposure)
        add(f'CA_30_pretty_{15 + offset:02d}.jpg', role, 'pretty-derivative', variation,
            f'CC0 fixture derivative: crop inset {inset}px; exposure factor {exposure:.3f}; no upscale')
    by_hash = {}
    for row in records:
        by_hash.setdefault(row['sha256'], []).append(row['file'])
    need(sorted(sorted(names) for names in by_hash.values() if len(names) > 1)
         == [['CA_10_duplicate_a.jpg', 'CA_11_duplicate_b.jpg']], 'Only the intended exact duplicate pair may share bytes')
    need({row['file']: row['capture_role'] for row in records} == expected_image_roles(), '35-image filename/role plan drifted')

    if not skip_videos:
        for index, role in enumerate(VIDEO_ROLES):
            row = roles[role]
            need(digest(source / row['file']) == row['sha256'], 'Video original changed after approval')
            name = f'CA_40_large_{index + 1:02d}.mp4'
            temporary = output / f'CA_40_large_{index + 1:02d}.encoding.mp4'
            # Same genuinely encoded grain strategy as v1-v3; no append/padding.
            # The dimension gate above prevents force_original_aspect_ratio from upscaling.
            for seconds in (12, 24, 48):
                command = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
                           '-loop', '1', '-i', str(source / row['file']),
                           '-vf', f'scale=1920:1080:force_original_aspect_ratio=increase:out_range=tv,crop=1920:1080,noise=alls=18:allf=t+u:all_seed={20261115 + index}',
                           '-t', str(seconds), '-r', '24', '-c:v', 'libx264', '-preset', 'ultrafast',
                           '-crf', '16', '-pix_fmt', 'yuv420p', '-color_range', 'tv', '-an', '-movflags', '+faststart', str(temporary)]
                subprocess.run(command, check=True, timeout=300, stdout=subprocess.DEVNULL)
                if temporary.stat().st_size > 110_000_000:
                    break
            need(temporary.stat().st_size > 110_000_000, 'A truly measured >110MB encoded video is required; padding is forbidden')
            destination = output / name
            temporary.rename(destination)
            probe = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(destination)], text=True))
            streams = probe.get('streams', [])
            need(len(streams) == 1 and streams[0].get('codec_type') == 'video', 'Expected one silent video stream')
            video = streams[0]
            duration = float(probe['format']['duration'])
            need((video.get('codec_name'), video.get('width'), video.get('height'), video.get('pix_fmt'))
                 == ('h264', 1920, 1080, 'yuv420p'), 'Encoded video metadata mismatch')
            need(math.isfinite(duration) and duration > 0 and int(probe['format']['size']) == destination.stat().st_size,
                 'Encoded video duration/measured byte mismatch')
            subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-xerror',
                            '-i', str(destination), '-f', 'null', '-'], check=True, timeout=180, stdout=subprocess.DEVNULL)
            records.append({'file': name, 'category': 'large-video', 'media_type': 'video', 'sha256': digest(destination),
                            'bytes': destination.stat().st_size, 'size': [1920, 1080], **source_fields(role),
                            'adaptation': 'Real encoded silent CC0-photo clip with film grain; no upscale, padding, or fake size',
                            'video': {'width': 1920, 'height': 1080, 'codec': 'h264', 'duration': duration,
                                      'full_decode': 'PASS', 'audio_streams': 0, 'frame_rate': video.get('avg_frame_rate')}})
    images = sum(row['media_type'] == 'image' for row in records)
    videos = sum(row['media_type'] == 'video' for row in records)
    need(images == 35 and videos == (0 if skip_videos else 2), 'Fixture count mismatch')
    need({path.name for path in output.iterdir()} == {row['file'] for row in records}, 'Unexpected extra fixture files')
    # Bind the bytes actually validated, never stale legacy hashes.
    need(digest(source / 'manifest.json') == source_manifest_sha and digest(allowlist_path) == allowlist_sha,
         'Registry/allowlist changed during fixture generation')
    for row in roles.values():
        need(digest(source / row['file']) == row['sha256'], 'Original changed during fixture generation: ' + row['file'])
    report = {'schema_version': 2, 'creative_revision': 4,
              'purpose': 'Separate v4 disposable stock PhotoKit fixture: cat, meals, everyday, coffee, dog, travel and nature originals',
              'status': 'IMAGES_ONLY_NOT_CAPTURE_READY' if skip_videos else 'PASS',
              'source_manifest_sha256': source_manifest_sha, 'source_library_verified': 15,
              'visual_source_gate': {'status': 'PASS', 'allowlist_status': 'PASS_SELECTED_SUBSET_ONLY',
                                     'allowlist_sha256': allowlist_sha, 'approved_original_count': 15,
                                     'all_used_sources_approved': True},
              'images': images, 'videos': videos,
              'native_screenshot_fixture': 'Excluded by owner: no app/UI screenshot is imported as photo media',
              'sample_media_policy': MEDIA_POLICY, 'records': records}
    with (output / 'fixture-manifest.json').open('x', encoding='utf-8', newline='\n') as stream:
        stream.write(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources', type=Path, required=True, help='v4 registry folder containing manifest.json and 15 originals')
    parser.add_argument('--allowlist', type=Path, required=True, help='Explicit v4 selected-subset original-hash allowlist')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--skip-videos', action='store_true', help='Image-only local preparation, explicitly not capture-ready')
    parser.add_argument('--video-count', type=int, choices=(2,), default=2)
    args = parser.parse_args(argv)
    try:
        report = build_fixture(args.sources, args.allowlist, args.output, skip_videos=args.skip_videos, video_count=args.video_count)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(json.dumps({'status': 'FAIL', 'creative_revision': 4, 'error': f'{type(error).__name__}: {error}'}))
        return 1
    print(json.dumps({key: value for key, value in report.items() if key != 'records'}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
