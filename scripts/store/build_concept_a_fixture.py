#!/usr/bin/env python3
"""Build a real disposable PhotoKit library; no app models or results are fabricated.

All images derive from individually licensed, hash-pinned CC0 repository photographs.
Videos contain real encoded frames, not padding. The only screenshot fixture is captured
by simctl from the running app later, never drawn by this script. Runtime output must
remain outside the repository; the original app-store/media files are read-only.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path
from PIL import Image, ImageEnhance, ImageOps, ImageFilter


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--skip-videos', action='store_true', help='Image-only local preparation, not a complete capture library')
    parser.add_argument('--video-count', type=int, default=2, choices=(1, 2))
    args = parser.parse_args()
    source = args.sources.resolve()
    output = args.output.resolve()
    if output == source or source in output.parents:
        raise SystemExit('Fixture output must not replace or be nested inside the protected photo source library')
    if output.exists() and any(output.iterdir()):
        raise SystemExit('Refusing to overwrite a nonempty fixture directory')
    output.mkdir(parents=True, exist_ok=True)
    manifest_file = source / 'manifest.json'
    original = json.loads(manifest_file.read_text(encoding='utf-8'))
    photos = original['photos']
    assert len(photos) == 55 and len({row['file'] for row in photos}) == 55
    by_number = {int(row['file'][:2]): row for row in photos}
    # Verify the complete inherited licensing ledger and every source before deriving anything.
    for row in photos:
        assert row['license'] == 'CC0-1.0', row['file']
        assert digest(source / row['file']) == row['sha256'], row['file']
    visual_allowlist_path = source.parent / 'concepts/A/qa/fixture-source-allowlist.json'
    visual_allowlist = json.loads(visual_allowlist_path.read_text(encoding='utf-8'))
    approved = {row['source']: row['sha256'] for row in visual_allowlist['approved'] if row['verdict'] == 'PASS'}
    assert visual_allowlist['status'] == 'PASS_SELECTED_SUBSET_ONLY'
    assert len(approved) == visual_allowlist['approved_count'] == 16
    inventory: list[dict] = []

    def add(name: str, number: int, category: str, transform=None, details: str = 'Unchanged source bytes') -> Path:
        row = by_number[number]
        assert approved.get(row['file']) == row['sha256'], 'Unapproved visual source: ' + row['file']
        src, dst = source / row['file'], output / name
        if transform is None:
            shutil.copyfile(src, dst)
        else:
            with Image.open(src) as image:
                result = transform(ImageOps.exif_transpose(image).convert('RGB'))
                assert result.width <= image.width and result.height <= image.height, 'No upscaling'
                result.save(dst, 'JPEG', quality=94, subsampling=0, optimize=True)
        with Image.open(dst) as image:
            size = list(image.size)
        inventory.append({'file': name, 'category': category, 'media_type': 'image',
                          'sha256': digest(dst), 'bytes': dst.stat().st_size, 'size': size,
                          'source': row['file'], 'source_sha256': row['sha256'],
                          'source_url': row['source'], 'author': row['author'],
                          'license': row['license'], 'license_url': row['license_url'],
                          'adaptation': details})
        return dst

    # Deliberately challenging real photo-fixture pixels, never marketing retouching
    # of app screens or injected analysis results. Derivatives are declared below.
    add('CA_01_clutter_blur.jpg', 5, 'clutter-blurry',
        lambda image: image.filter(ImageFilter.GaussianBlur(26)),
        'CC0 photo-fixture derivative: pronounced 26px optical defocus; no upscale')
    add('CA_02_clutter_shake.jpg', 10, 'clutter-challenging',
        lambda image: image.filter(ImageFilter.GaussianBlur(18)),
        'CC0 photo-fixture derivative: pronounced 18px defocus; no upscale')
    add('CA_03_clutter_dark.jpg', 5, 'clutter-dark',
        lambda image: ImageEnhance.Brightness(image).enhance(0.25),
        'CC0 photo-fixture derivative: underexposed flower photo, brightness factor 0.25; no upscale')
    add('CA_10_duplicate_a.jpg', 38, 'exact-duplicate')
    add('CA_11_duplicate_b.jpg', 38, 'exact-duplicate')
    assert digest(output / 'CA_10_duplicate_a.jpg') == digest(output / 'CA_11_duplicate_b.jpg')
    for index in range(6):
        def variation(image, index=index):
            inset = index * 5
            crop = image.crop((inset, inset, image.width - inset, image.height - inset))
            return ImageEnhance.Brightness(crop).enhance(0.98 + index * 0.008)
        add(f'CA_20_series_{index + 1:02d}.jpg', 36, 'near-similar-series', variation,
            f'Fixture derivative: crop inset {index * 5}px; exposure factor {0.98 + index * 0.008:.3f}; no upscale')
    # Only individually reviewed original hashes. The deliberate duplicate source
    # is excluded here so that the real scanner finds exactly the intended pair.
    pretty_sources = [5, 10, 1, 4, 6, 7, 9, 13, 17, 28, 29, 31, 33, 35, 36]
    assert len(pretty_sources) == len(set(pretty_sources)) == 15
    for index, number in enumerate(pretty_sources, 1):
        add(f'CA_30_pretty_{index:02d}.jpg', number, 'pretty')
    # Nine distinct edited copies from the same approved nature originals complete
    # the two-per-month library. These are declared fixture photos, not invented UI.
    for offset, number in enumerate([5, 10, 1, 4, 6, 7, 13, 17, 35]):
        inset, exposure = 48 + offset * 7, 1.04 + offset * 0.005
        def pretty_variation(image, inset=inset, exposure=exposure):
            return ImageEnhance.Brightness(image.crop((inset, inset, image.width - inset, image.height - inset))).enhance(exposure)
        add(f'CA_30_pretty_{16 + offset:02d}.jpg', number, 'pretty-derivative', pretty_variation,
            f'CC0 fixture derivative: crop inset {inset}px; exposure factor {exposure:.3f}; no upscale')
    by_hash: dict[str, list[str]] = {}
    for row in inventory:
        by_hash.setdefault(row['sha256'], []).append(row['file'])
    assert [sorted(names) for names in by_hash.values() if len(names) > 1] == [['CA_10_duplicate_a.jpg', 'CA_11_duplicate_b.jpg']]

    if not args.skip_videos:
        ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
        assert ffmpeg and ffprobe, 'ffmpeg and ffprobe must be installed before the native capture job'
        for index in range(args.video_count):
            row = by_number[[13, 35][index]]
            assert approved.get(row['file']) == row['sha256'], 'Unapproved video-source photo: ' + row['file']
            name = f'CA_40_large_{index + 1:02d}.mp4'
            temporary = output / f'CA_40_large_{index + 1:02d}.encoding.mp4'
            # A nature-photo film-grain clip is genuinely encoded and decodable. High-detail
            # frames and an actual measured >100MB file make the normal Large files filter useful.
            for seconds in (12, 24, 48):
                command = [ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-y',
                           '-loop', '1', '-i', str(source / row['file']),
                           '-vf', f'scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,noise=alls=18:allf=t+u:all_seed={20261115 + index}',
                           '-t', str(seconds), '-r', '24', '-c:v', 'libx264', '-preset', 'ultrafast',
                           '-crf', '16', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart', str(temporary)]
                subprocess.run(command, check=True, timeout=300, stdout=subprocess.DEVNULL)
                actual_bytes = temporary.stat().st_size
                if actual_bytes > 110_000_000:
                    break
            assert actual_bytes > 110_000_000, 'No oversized-video fixture: never pretend a small video exceeds the real filter'
            destination = output / name
            temporary.rename(destination)
            probe = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(destination)], text=True))
            video = next(stream for stream in probe['streams'] if stream['codec_type'] == 'video')
            assert video['codec_name'] == 'h264' and video['width'] == 1920 and video['height'] == 1080
            assert not any(stream['codec_type'] == 'audio' for stream in probe['streams'])
            subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-i', str(destination), '-f', 'null', '-'],
                           check=True, timeout=180, stdout=subprocess.DEVNULL)
            inventory.append({'file': name, 'category': 'large-video', 'media_type': 'video', 'sha256': digest(destination),
                              'bytes': destination.stat().st_size, 'source': row['file'], 'source_sha256': row['sha256'],
                              'source_url': row['source'], 'author': row['author'], 'license': row['license'],
                              'license_url': row['license_url'], 'adaptation': 'Real encoded silent CC0-photo clip with film grain; no padding or fake size',
                              'video': {'width': video['width'], 'height': video['height'], 'codec': video['codec_name'],
                                        'duration': float(probe['format']['duration']), 'full_decode': 'PASS', 'audio_streams': 0}})
    image_count = sum(row['media_type'] == 'image' for row in inventory)
    video_count = sum(row['media_type'] == 'video' for row in inventory)
    assert image_count == 35
    report = {'schema_version': 1, 'purpose': 'Disposable genuine PhotoKit library for GaleriQ concept A en-US capture',
              'status': 'IMAGES_ONLY_NOT_CAPTURE_READY' if args.skip_videos else 'PASS',
              'source_manifest_sha256': digest(manifest_file), 'source_library_verified': len(photos),
              'visual_source_gate': {'status': 'PASS', 'allowlist_sha256': digest(visual_allowlist_path),
                                     'approved_original_count': len(approved),
                                     'all_used_sources_approved': all(approved.get(row['source']) == row['source_sha256'] for row in inventory)},
              'images': image_count, 'videos': video_count,
              'native_screenshot_fixture': 'Excluded by owner: no app/UI screenshot is imported as photo media',
              'sample_media_policy': 'approved-stock-photos-and-videos-no-app-screenshots',
              'records': inventory}
    (output / 'fixture-manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in report.items() if key != 'records'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
