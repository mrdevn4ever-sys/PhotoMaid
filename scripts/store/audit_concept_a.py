#!/usr/bin/env python3
"""Independently audit ten lossless exports and their exact fresh native provenance.

This is an export-integrity gate, not a substitute for native/source/final visual QA.
It never edits Store assets and never uploads or publishes anything.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageCms, ImageDraw, ImageStat

COPY = [
    'Swipe the clutter. Keep the memories.', 'Find duplicates. Spot large files.',
    'Nothing deletes without you.', 'Private photos. Locked away.',
    'Unsure? Choose later.', 'One month. A fresh start.',
    'Blurry or similar? Take a closer look.', 'Make a collage. Keep the moment.',
    'A new look. Your own photo.', 'A small break. Your photos play.',
]
SUBTITLES = {4: 'Encrypted vault, protected by your own code and Face ID.',
             10: 'Free with ads. GaleriQ Pro: one purchase, no subscription.'}


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def need(condition, message):
    if not condition:
        raise ValueError(message)


def profile(path):
    with Image.open(path) as image:
        image.load()
        raw = image.info.get('icc_profile')
        need(raw is not None, f'Missing embedded ICC: {path.name}')
        icc = ImageCms.ImageCmsProfile(io.BytesIO(raw))
        description = ImageCms.getProfileDescription(icc).strip()
        need('srgb' in description.lower(), f'Final export is not explicitly sRGB: {description}')
        need(image.mode == 'RGB' and 'A' not in image.getbands() and 'transparency' not in image.info,
             f'Final export contains alpha or is not RGB: {path.name}')
        return {'size': list(image.size), 'mode': image.mode, 'format': image.format,
                'icc_description': description, 'icc_sha256': hashlib.sha256(raw).hexdigest()}


def verify_pixels(final, sources, layer, later_layers, inset_style):
    """Independent equality check: actual original pixels, not manifest assertions.

    Conservatively omit rounded edges and later inset/shadow rectangles. Wordmark
    glyphs are compared where original alpha is fully opaque; never redraw text.
    """
    with Image.open(sources / layer['originalSource']) as original:
        original.load()
        alpha = original.getchannel('A') if original.mode == 'RGBA' else None
        rgb = original.convert('RGB')
        raw_icc = original.info.get('icc_profile')
        if raw_icc:
            rgb = ImageCms.profileToProfile(rgb, ImageCms.ImageCmsProfile(io.BytesIO(raw_icc)),
                                           ImageCms.createProfile('sRGB'), outputMode='RGB',
                                           renderingIntent=ImageCms.Intent.RELATIVE_COLORIMETRIC, flags=0)
        box = layer['targetGeometry']
        size = (box[2] - box[0], box[3] - box[1])
        expected = rgb.crop(layer['crop']).resize(size, Image.Resampling.LANCZOS)
        mask = Image.new('L', size, 0)
        if layer['id'] == 'native-wordmark':
            need(alpha is not None, 'Original wordmark lost its actual alpha')
            mask = alpha.crop(layer['crop']).resize(size, Image.Resampling.LANCZOS).point(lambda value: 255 if value == 255 else 0)
        else:
            # Strictly internal pixels only; no reliance on renderer's round-mask code.
            radius = 98 if layer['id'] == 'full-phone' else inset_style['radius']
            ImageDraw.Draw(mask).rectangle((radius, radius, size[0] - radius - 1, size[1] - radius - 1), fill=255)
        for above in later_layers:
            obstacle = above['targetGeometry']
            margin = 4 * inset_style['shadowBlur'] + max(map(abs, inset_style['shadowOffset']))
            ImageDraw.Draw(mask).rectangle((obstacle[0] - box[0] - margin, obstacle[1] - box[1] - margin,
                                           obstacle[2] - box[0] + margin, obstacle[3] - box[1] + margin), fill=0)
        pixels = mask.histogram()[255]
        need(pixels > 100, 'Insufficient independently comparable native interior')
        difference = ImageChops.difference(final.crop(box), expected)
        difference = Image.composite(difference, Image.new('RGB', size), mask)
        need(difference.getbbox() is None, f"Independent native pixel mismatch: {layer['id']}")
        return pixels


def audit(render, sources, expected_commit, expected_run):
    manifest = load(render / 'render-manifest.json')
    design_path = Path(manifest['design']['path'])
    need(digest(design_path) == manifest['design']['sha256'], 'Actual reviewed design file drift')
    design = load(design_path)
    provenance = load(sources / 'capture_provenance.json')
    need(provenance['status'] == 'PASS' and provenance['fresh_capture'] is True, 'Fresh native capture PASS is required')
    need(provenance['commit'] == expected_commit and provenance['workflow_run'] == expected_run, 'Independently pinned native run/SHA mismatch')
    need(provenance['locale'] == 'en-US' and provenance['app_language'] == 'en', 'Only en-US is authorized')
    need(manifest['sourceGate']['provenance'] == provenance, 'Render manifest is not bound to the exact fresh source provenance')
    need(manifest['sourceGate']['provenanceSHA256'] == digest(sources / 'capture_provenance.json'), 'Source-provenance file hash drift')
    need(manifest['sourceVisualQA']['approved'] is True, 'Actual source visual approval is absent')
    rows = manifest['outputs']
    need(len(rows) == 10 and [row['slot'] for row in rows] == list(range(1, 11)), 'Exactly ten ordered outputs are required')
    files = [row['file'] for row in rows]
    need(len(set(files)) == 10 and all(Path(name).name == name for name in files), 'Nonunique/unsafe export names')
    need([name[:3] for name in files] == [f'{index:02d}-' for index in range(1, 11)], 'Files must be numbered 01 through 10')
    need(sorted(path.name for path in render.glob('*.png')) == sorted(files), 'Unexpected or missing PNG exports')
    native = {row['file']: row for row in provenance['outputs']}
    native[provenance['branding']['file']] = provenance['branding']
    for row in manifest['originalSources']:
        need(row['path'] in native and row['sha256'] == native[row['path']]['sha256'], 'Render references an unbound native source')
        need(digest(sources / row['path']) == row['sha256'], 'Native source file drift')
    checked, phone_boxes, hashes = [], [], []
    for index, row in enumerate(rows, 1):
        path = render / row['file']
        need(digest(path) == row['sha256'], f'Output hash drift: {path.name}')
        meta = profile(path)
        need(meta['size'] == [1206, 2622] and meta['format'] == 'PNG', f'Wrong PNG geometry: {path.name}')
        raw = path.read_bytes()
        need(raw[:8] == b'\x89PNG\r\n\x1a\n' and raw[24] == 8 and raw[25] == 2, 'Final PNG must be true 8-bit RGB without alpha')
        need(row['headline']['text'] == COPY[index - 1], f'Headline drift at {index}')
        need(len(row['headline']['lines']) <= 2 and row['headline']['fontSize'] >= 84, 'Headline wrapping/size failed')
        subtitle = row['subtitle']
        if index in SUBTITLES:
            need(subtitle['text'] == SUBTITLES[index] and len(subtitle['lines']) <= 2 and subtitle['fontSize'] >= 46, 'Subtitle copy/wrapping/readability failed')
        else:
            need(subtitle is None, 'Unrequested subtitle')
        for text in [row['headline'], subtitle]:
            if text:
                for box in text['lineBBoxes']:
                    need(box[0] >= 70 and box[2] <= 1136 and box[1] >= 70 and box[3] <= 2552, 'Marketing text violates 70px safe margin')
        layers = row['nativeLayers']
        phones = [layer for layer in layers if layer['id'] == 'full-phone']
        need(len(phones) == 1 and phones[0]['crop'] == [0, 0, 1206, 2622], 'Missing complete native phone')
        phone_boxes.append(phones[0]['targetGeometry'])
        need(any(layer['id'] == 'native-wordmark' and layer['originalSource'] == 'branding/native-wordmark.png' for layer in layers), 'Missing original native wordmark pixels')
        independent_pixels = 0
        with Image.open(path) as reopened:
            reopened.load()
            final = reopened.copy()
        for layer_index, layer in enumerate(layers):
            need(layer['sourceSHA256'] == native[layer['originalSource']]['sha256'], 'Layer uses unbound source hash')
            need(max(layer['effectiveNativeScaleXY']) <= 1.0, 'Native pixel upscaling')
            proof = layer['pixelQA']
            need(proof['status'] == 'PASS' and proof['comparedPixels'] > 0 and proof['maxChannelDifference'] == 0
                 and proof['maskedKnownResampleSHA256'] == proof['maskedOutputSHA256'], 'Native pixel equality proof failed')
            independent_pixels += verify_pixels(final, sources, layer, layers[layer_index + 1:], design['layout']['insetStyle'])
        layout = row['layoutQA']
        need(layout['status'] == 'PASS' and layout['protectedPrimaryEvidenceUnobscured'] is True
             and layout['allTextBBoxesInsideContainers'] is True and layout['nativeUpscaling'] is False
             and layout['secondDynamicIsland'] is False, 'Per-file composition gate failed')
        checked.append({'slot': index, 'file': row['file'], 'sha256': row['sha256'], **meta,
                        'native_layers_verified': len(layers), 'independently_compared_native_pixels': independent_pixels})
        hashes.append(row['sha256'])
    need(len(set(hashes)) == 10 and all(box == phone_boxes[0] for box in phone_boxes), 'Duplicate final image or inconsistent complete-phone geometry')
    need(manifest['layoutQA']['overviewRows'] == 1 and manifest['layoutQA']['overviewSlots'] == list(range(1, 11)), 'Overview must contain all ten in one row')
    need(manifest['layoutQA']['searchSlots'] == [1, 2, 3], 'Search-preview order mismatch')
    need({row['file'] for row in manifest['previews']} == {'00-overview.jpg', '00-search-preview.jpg'}, 'Exactly both named previews required')
    for row in manifest['previews']:
        path = render / row['file']
        need(digest(path) == row['sha256'], 'Preview hash drift')
        meta = profile(path)
        need(meta['format'] == 'JPEG' and row['rows'] == 1, 'Preview must be one actual horizontal JPEG row')
        expected_ids = list(range(1, 11)) if row['kind'] == 'overview' else [1, 2, 3]
        need(row['slotIds'] == expected_ids and [cell['slot'] for cell in row['cells']] == expected_ids, 'Preview membership/order drift')
        with Image.open(path) as preview:
            for cell in row['cells']:
                box = cell['targetGeometry']
                with Image.open(render / rows[cell['slot'] - 1]['file']) as image:
                    reference = image.resize((box[2] - box[0], box[3] - box[1]), Image.Resampling.LANCZOS)
                mean_difference = ImageStat.Stat(ImageChops.difference(preview.crop(box), reference)).mean
                need(max(mean_difference) < 4, 'Preview cells do not match actual numbered exports (JPEG tolerance)')
    return {'schema_version': 1, 'technical_export_status': 'PASS', 'workflow_run': expected_run,
            'commit': expected_commit, 'locale': 'en-US', 'png_count': len(checked), 'images': checked,
            'preview_count': len(manifest['previews']), 'uniform_phone_box': phone_boxes[0],
            'native_pixels': 'PASS, independently compared to ICC-normalized original native files; outer alpha edges excluded',
            'human_final_visual_acceptance': 'NOT RUN by this automatic auditor',
            'security_runtime_conversion_or_store_upload_acceptance': 'NOT RUN'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', required=True, type=Path)
    parser.add_argument('--sources', required=True, type=Path)
    parser.add_argument('--expected-commit', required=True)
    parser.add_argument('--expected-workflow-run', required=True)
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    try:
        result = audit(args.render, args.sources, args.expected_commit, args.expected_workflow_run)
    except Exception as error:
        result = {'technical_export_status': 'FAIL', 'error': f'{type(error).__name__}: {error}',
                  'human_final_visual_acceptance': 'NOT RUN'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in result.items() if key != 'images'}, ensure_ascii=False))
    if result['technical_export_status'] != 'PASS':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
