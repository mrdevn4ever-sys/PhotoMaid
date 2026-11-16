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
import math
import re
from pathlib import Path, PurePosixPath
from PIL import Image, ImageChops, ImageCms, ImageDraw, ImageFilter, ImageFont, ImageStat

COPY = [
    'Swipe the clutter. Keep the memories.', 'Spot large files. Find duplicates.',
    'Nothing deletes without you.', 'Private photos. Locked away.',
    'Unsure? Choose later.', 'One month. A fresh start.',
    'Blurry or similar? Take a closer look.', 'Make a collage. Keep the moment.',
    'A new look. Your own photo.', 'A small break. Your photos play.',
]
SUBTITLES = dict(enumerate([
    'Keep, trash or decide later.', 'Find extra copies and space-hungry files.',
    'Review first. You make the final call.', 'Encrypted vault, protected by your own code and Face ID.',
    'Swipe right. Come back to it later.', 'Sort your library, one month at a time.',
    'Compare your shots. Choose what stays.', 'Bring your favorite moments together.',
    'Add a new look to a photo you love.', 'Free with ads. GaleriQ Pro: one purchase, no subscription.'
], 1))
SIZE = (1206, 2622)
MEDIA_POLICY = 'approved-stock-photos-and-videos-no-app-screenshots'
INSETS = {2: ('duplicate-results', 'duplicates', {'duplicate-pair', 'selection-labels'}),
          3: ('system-dialog', 'delete-confirm', {'system-dialog'}),
          7: ('series-decision', 'analysis', {'series', 'keep5-trash1'})}
PRIMARIES = ('swipe', 'large-files', 'delete-confirm', 'vault', 'later-swipe', 'months', 'analysis', 'collage', 'editor', 'games')
REVIEW = {'stockOnlyEveryMediaTile', 'sharpRecognizableFirstPhoto', 'opaqueSystemDialogNoUnderlyingHome',
          'noLoadingSpinner', 'heldRightwardLater', 'filledNativePairsBoard', 'nativeKeep5Trash1', 'completeDuplicatePair'}
V3_SCENE_POLICY = 'sharp-stock-hero-opaque-confirmation-filled-photo-game'


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def load(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            need(key not in result, 'Duplicate JSON key: ' + key)
            result[key] = value
        return result
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=unique)


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


def raw_sha(raw):
    return hashlib.sha256(raw).hexdigest()


def dimensions(box):
    return box[2] - box[0], box[3] - box[1]


def within(a, b):
    return b[0] <= a[0] < a[2] <= b[2] and b[1] <= a[1] < a[3] <= b[3]


def intersects(a, b):
    return max(a[0], b[0]) < min(a[2], b[2]) and max(a[1], b[1]) < min(a[3], b[3])


def source_path(root, name):
    need(isinstance(name, str) and '\\' not in name, 'Noncanonical native path')
    rel = PurePosixPath(name)
    need(not rel.is_absolute() and '..' not in rel.parts and str(rel) == name, 'Unsafe native path')
    path = root.joinpath(*rel.parts)
    need(path.is_file() and not path.is_symlink() and path.resolve().is_relative_to(root.resolve()), 'Native path escapes source tree')
    return path


def clip_geometry(box, crop):
    visible = [max(0, box[0]), max(0, box[1]), min(SIZE[0], box[2]), min(SIZE[1], box[3])]
    need(visible[0] < visible[2] and visible[1] < visible[3], 'No visible native pixels')
    local = [visible[0] - box[0], visible[1] - box[1], visible[2] - box[0], visible[3] - box[1]]
    w, h = dimensions(box)
    cw, ch = dimensions(crop)
    return {'visibleGeometry': visible, 'visibleLocalRect': local,
            'visibleSourceBounds': [crop[0] + local[0] * cw / w, crop[1] + local[1] * ch / h,
                                    crop[0] + local[2] * cw / w, crop[1] + local[3] * ch / h],
            'viewportClipPixels': {'left': local[0], 'top': local[1], 'right': w - local[2], 'bottom': h - local[3]}}


def phone_geometry(design):
    need(design.get('creativeRevision') == design.get('layoutRevision') == design.get('nativeRevision') == 3, 'Old full-phone contract is not v3')
    need(design.get('nativeScenePolicy') == V3_SCENE_POLICY, 'Old native scene/blurred-hero/menu contract is not v3')
    device = design['layout']['device']
    box = device['screenBox']
    need(isinstance(box, list) and len(box) == 4 and all(type(n) is int for n in box), 'Full target geometry must be integer pixels')
    w, h = dimensions(box)
    scale = w / 1206
    need(0 < scale <= 1 and abs(h - 2622 * scale) <= 0.5, 'Native phone aspect/upscale violation')
    f = device['frameWidth']
    need(type(f) is int and f > 0, 'Invalid hardware frame width')
    frame = [box[0] - f, box[1] - f, box[2] + f, box[3] + f]
    need(70 <= frame[0] < frame[2] <= 1136 and 70 <= frame[1] < 2622 < box[3], 'Only bottom clipping is authorized; top/side frame must stay visible')
    ratios = [w / 804, h / 1748]
    need(all(1.15 <= r <= 1.20 for r in ratios), 'Phone not 15-20% larger than actual v2')
    need(device.get('viewportClip') == 'bottom-only' and device.get('v2ReferenceScreenBox') == [201, 760, 1005, 2508], 'Missing actual v2/bottom-clip contract')
    return {'fullTargetGeometry': box, **clip_geometry(box, [0, 0, *SIZE]), 'fullFrameGeometry': frame,
            'visibleFrameGeometry': clip_geometry(frame, [0, 0, *dimensions(frame)])['visibleGeometry'],
            'nativeScale': scale, 'sizeRelativeToV2XY': ratios, 'resampleRoundingXY': [0, h - 2622 * scale],
            'clipping': 'bottom-only', 'completePhoneVisible': False}


def rounded(size, radius):
    # Independent implementation of the documented 4x antialiased outer mask.
    big = Image.new('L', (size[0] * 4, size[1] * 4))
    ImageDraw.Draw(big).rounded_rectangle((0, 0, big.width - 1, big.height - 1), radius=min(radius, min(size) // 2) * 4, fill=255)
    return big.resize(size, Image.Resampling.LANCZOS)


def full_mask(local, box):
    mask = Image.new('L', SIZE)
    mask.paste(local, box[:2])
    return mask


def focus_style(design, layer_id):
    if layer_id in ('series-decision', 'system-dialog'):
        style_key = 'seriesInsetStyle' if layer_id == 'series-decision' else 'dialogInsetStyle'
        style = design['layout'].get(style_key)
        need(style == {'radius': 0, 'shadowBlur': 0, 'shadowOffset': [0, 0], 'shadowAlpha': 0},
             'Series focus must close the full visible screen width without gutter/shadow')
        return style
    return design['layout']['insetStyle']


def layer_occlusion(layer, design):
    box = layer['targetGeometry']
    radius = design['layout']['device']['screenRadius'] if layer['id'] == 'full-phone' else focus_style(design, layer['id'])['radius']
    mask = rounded(dimensions(box), radius)
    coverage = full_mask(mask, box)
    if layer['id'] != 'full-phone':
        style = focus_style(design, layer['id'])
        field = Image.new('L', SIZE)
        field.paste(mask, (box[0] + style['shadowOffset'][0], box[1] + style['shadowOffset'][1]))
        field = field.filter(ImageFilter.GaussianBlur(style['shadowBlur']))
        field = field.point(lambda value: round(value * style['shadowAlpha'] / 255))
        coverage = ImageChops.lighter(coverage, field)
    return coverage


def marketing_background(design):
    a, b = (tuple(bytes.fromhex(design['background'][k][1:])) for k in ('top', 'bottom'))
    strip = Image.new('RGB', (1, SIZE[1]))
    values = []
    for y in range(SIZE[1]):
        t = y / (SIZE[1] - 1)
        t = t * t * (3 - 2 * t)
        values.append(tuple(round(x + (z - x) * t) for x, z in zip(a, b)))
    strip.putdata(values)
    return strip.resize(SIZE, Image.Resampling.NEAREST)


def verify_pixels(final, sources, layer, later_layers, design):
    """Exact original-pixel comparison, including every visible bottom row.

    No renderer imports/buffers; no broad rectangle exclusions. Only actual
    rounded alpha edges, off-canvas pixels and actual later alpha/shadows are omitted.
    Original-alpha wordmark edges are compared to their known composite too.
    """
    with Image.open(source_path(sources, layer['originalSource'])) as original:
        original.load()
        need(original.format == 'PNG' and original.mode in ('RGB', 'RGBA') and original.getexif().get(274, 1) == 1, 'Invalid original native image')
        need(layer['sourceSize'] == list(original.size) and layer['sourceMode'] == original.mode, 'Layer/source size or mode drift')
        alpha = original.getchannel('A') if original.mode == 'RGBA' else None
        rgb = original.convert('RGB')
        raw_icc = original.info.get('icc_profile')
        if raw_icc:
            rgb = ImageCms.profileToProfile(rgb, ImageCms.ImageCmsProfile(io.BytesIO(raw_icc)), ImageCms.createProfile('sRGB'),
                                           outputMode='RGB', renderingIntent=ImageCms.Intent.RELATIVE_COLORIMETRIC, flags=0)
        normalized = rgb.copy()
        if alpha is not None:
            normalized.putalpha(alpha)
        need(layer['colorManagement']['normalizedPixelSHA256'] == raw_sha(normalized.tobytes()), 'Normalized original color/alpha pixel buffer differs')
        box, crop = layer['targetGeometry'], layer['crop']
        need(within(crop, [0, 0, *original.size]), 'Crop exceeds actual native source')
        size, crop_size, scale = dimensions(box), dimensions(crop), layer['nativeScale']
        need(type(scale) in (int, float) and math.isfinite(scale) and 0 < scale <= 1 and
             all(actual <= native and abs(actual - native * scale) <= 0.5 + 1e-9 for actual, native in zip(size, crop_size)), 'Unknown proportional resample or native upscale')
        need(layer['effectiveNativeScaleXY'] == [size[0] / crop_size[0], size[1] / crop_size[1]] and layer['rotationDegrees'] == 0, 'False scale/rotation metadata')
        geometry = clip_geometry(box, crop)
        need(all(layer[k] == value for k, value in geometry.items()), 'Full/visible/source coordinate metadata drift')
        viewport = Image.new('L', size)
        viewport.paste(255, geometry['visibleLocalRect'])
        if layer['id'] == 'native-wordmark':
            need(alpha is not None and alpha.getextrema()[0] == 0, 'Canonical native wordmark lost original transparency')
            need(crop == list(alpha.getbbox()), 'Wordmark crop must retain complete native ink')
            tile = normalized.crop(crop)
            if tile.size != size:
                tile = tile.resize(size, Image.Resampling.LANCZOS)
            mask = tile.getchannel('A')
            expected = marketing_background(design).crop(box)
            expected.paste(tile.convert('RGB'), (0, 0), mask)
            eligible = mask.point(lambda v: 255 if v > 0 else 0)
        else:
            need(original.size == SIZE and (alpha is None or alpha.getextrema() == (255, 255)), 'Nonopaque or wrong-size native source')
            expected = rgb.crop(crop)
            if expected.size != size:
                expected = expected.resize(size, Image.Resampling.LANCZOS)
            radius = design['layout']['device']['screenRadius'] if layer['id'] == 'full-phone' else focus_style(design, layer['id'])['radius']
            mask = rounded(size, radius)
            eligible = mask.point(lambda v: 255 if v == 255 else 0)
        need(layer['maskSHA256'] == raw_sha(mask.tobytes()) and layer['viewportMaskSHA256'] == raw_sha(viewport.tobytes())
             and layer['visibleMaskSHA256'] == raw_sha(ImageChops.multiply(mask, viewport).tobytes()), 'False full/visible mask metadata')
        full_count = eligible.histogram()[255]
        eligible = ImageChops.multiply(eligible, viewport)
        viewport_count = eligible.histogram()[255]
        for above in later_layers:
            blocker = layer_occlusion(above, design).crop(box).point(lambda v: 255 if v else 0)
            eligible = ImageChops.subtract(eligible, blocker)
        pixels = eligible.histogram()[255]
        same_dialog = any(above['id'] == 'system-dialog' and above['originalSource'] == layer['originalSource'] for above in later_layers)
        minimum_visible = (0.25 if same_dialog else 0.5) if layer['id'] == 'full-phone' else 1
        need(pixels > 100 and pixels >= viewport_count * minimum_visible, 'Insufficient visible native evidence')
        actual = final.crop(box).convert('RGB')
        difference = Image.composite(ImageChops.difference(actual, expected), Image.new('RGB', size), eligible)
        need(difference.getbbox() is None, f"Independent native pixel mismatch: {layer['id']}")
        reference = Image.composite(expected, Image.new('RGB', size), eligible)
        output = Image.composite(actual, Image.new('RGB', size), eligible)
        proof = layer['pixelQA']
        need(proof['status'] == 'PASS' and proof['maxChannelDifference'] == 0 and proof['comparedPixels'] == pixels
             and proof['opaqueInteriorPixels'] == viewport_count and proof['fullTargetOpaqueInteriorPixels'] == full_count
             and proof['offCanvasOpaqueInteriorPixels'] == full_count - viewport_count
             and proof['occludedByLaterInsetOrShadowPixels'] == viewport_count - pixels
             and proof['minimumVisibleViewportFraction'] == minimum_visible
             and proof['maskedKnownResampleSHA256'] == raw_sha(reference.tobytes()) == proof['maskedOutputSHA256'] == raw_sha(output.tobytes()), 'Native proof is not the actual visible pixel comparison')
        return pixels


def verify_frame(final, design, proof):
    geometry = phone_geometry(design)
    d = design['layout']['device']
    box, frame = geometry['fullTargetGeometry'], geometry['fullFrameGeometry']
    outer = full_mask(rounded(dimensions(frame), d['screenRadius'] + d['frameWidth']), frame)
    inner = full_mask(rounded(dimensions(box), d['screenRadius']), box)
    eligible = ImageChops.multiply(outer.point(lambda n: 255 if n == 255 else 0), inner.point(lambda n: 255 if n == 0 else 0))
    count = eligible.histogram()[255]
    difference = Image.composite(ImageChops.difference(final, Image.new('RGB', SIZE, d['frameColor'])), Image.new('RGB', SIZE), eligible)
    need(count > 1000 and difference.getbbox() is None, 'Actual visible top/side hardware-frame pixels are obscured or changed')
    need(proof == {'status': 'PASS', 'comparedPixels': count, 'maxChannelDifference': 0,
                   'visibleFrameMaskSHA256': raw_sha(eligible.tobytes()), 'topLeftRightVisible': True,
                   'bottomIntentionallyClipped': True, 'geometry': geometry}, 'False frame-pixel or viewport proof')
    return count


def verify_stock_library(sources, provenance, fixture):
    need(provenance.get('sample_media_policy') == fixture.get('sample_media_policy') == MEDIA_POLICY, 'Actual native library is not explicitly stock-only')
    library_path = source_path(sources, 'concept-a-library.json')
    library, recorded = load(library_path), provenance['sample_media_audit']
    need(recorded['status'] == 'PASS' and digest(library_path) == recorded['actual_library_sha256'], 'Actual PhotoKit inventory/hash has not passed')
    rows, assets = fixture['records'], library['assets']
    expected = {Path(row['file']).name: row for row in rows}
    names = [row['filename'] for row in assets]
    need(len(expected) == len(rows) == len(assets) == len(set(names)) == 37 and set(names) == set(expected), 'Actual PhotoKit resources do not exactly match 37 approved stock inputs')
    need(all(row.get('isScreenshot') is False and isinstance(row.get('isVideo'), bool) and row['filename'].startswith('CA_')
             and not row['filename'].lower().endswith('.png') and 'screenshot' not in row['filename'].lower()
             and 'native-library' not in row['filename'].lower() and row['isVideo'] is (expected[row['filename']]['media_type'] == 'video') for row in assets), 'Nested app screenshot/unknown media in actual native library')
    photos, videos = sum(not row['isVideo'] for row in assets), sum(row['isVideo'] for row in assets)
    need((photos, videos) == (fixture['images'], fixture['videos']) == (35, 2)
         and (library['count'], library['photoCount'], library['videoCount']) == (37, 35, 2), 'Actual PhotoKit counters/types differ')
    need(recorded['actual_asset_count'] == 37 and recorded['actual_photo_count'] == 35 and recorded['actual_video_count'] == 2
         and recorded['actual_screenshot_subtype_count'] == 0 and recorded['fixture_filename_set_exact'] is True, 'False stock-only library counters')
    need(not (sources / 'stills/concept-a-native-library.fixture.json').exists(), 'Rejected old app-screenshot PhotoKit fixture remains')
    return {'policy': MEDIA_POLICY, 'actual_library_sha256': digest(library_path), 'actual_asset_count': 37,
            'actual_photo_count': 35, 'actual_video_count': 2, 'actual_screenshot_subtype_count': 0}


def actual_dialog_rect(sources, binding):
    path = source_path(sources, binding['file'])
    need(digest(path) == binding['sha256'] and path.suffix == '.json', 'Native dialog-frame JSON hash differs')
    value, pointer = load(path), binding['jsonPointer']
    need(isinstance(pointer, str) and pointer.startswith('/'), 'Explicit dialog frame JSON pointer required')
    for token in pointer[1:].split('/'):
        token = token.replace('~1', '/').replace('~0', '~')
        value = value[int(token)] if isinstance(value, list) else value[token]
    fmt, scale = binding['format'], binding['coordinateScale']
    need(fmt in ('xywh', 'xyxy') and type(scale) in (int, float) and math.isfinite(scale) and 0 < scale <= 3, 'Wrong native frame units')
    if isinstance(value, dict):
        value = [value[k] for k in (('x', 'y', 'width', 'height') if fmt == 'xywh' else ('left', 'top', 'right', 'bottom'))]
    need(isinstance(value, list) and len(value) == 4 and all(type(n) in (int, float) and math.isfinite(n) for n in value), 'Invalid native dialog frame coordinates')
    a, b, c, d = value
    if fmt == 'xywh':
        c, d = a + c, b + d
    result = [math.floor(a * scale), math.floor(b * scale), math.ceil(c * scale), math.ceil(d * scale)]
    need(within(result, [0, 0, *SIZE]), 'Actual native dialog frame exceeds capture')
    return result


def verify_v3_scenes(sources, provenance, fixture):
    need(provenance.get('native_scene_policy') == V3_SCENE_POLICY and provenance.get('native_scene_audit', {}).get('status') == 'PASS',
         'Actual sharp-hero/opaque-dialog/filled-board scene audit is absent; old green C6 is not final')
    from collect_concept_a_provenance import V3_SCENE_POLICY as collector_policy, audit_v3_scenes
    need(collector_policy == V3_SCENE_POLICY, 'Actual collector scene policy differs')
    actual = audit_v3_scenes(sources, fixture)
    need(actual.get('status') == 'PASS' and actual == provenance['native_scene_audit'], 'Actual native scene source evidence/hash audit differs')
    return actual


def verify_insets(row, slot, design, sources, native):
    index, layers = slot['id'], row['nativeLayers']
    expected = ['native-wordmark', 'full-phone'] + ([INSETS[index][0]] if index in INSETS else [])
    need([layer['id'] for layer in layers] == expected, 'Missing/extra/reordered genuine inset or native wordmark')
    need(layers[1]['originalSource'] == slot['primary'] == f'screenshots/concept-a-{PRIMARIES[index - 1]}.png'
         and layers[1]['sourceSHA256'] == slot['primarySourceSHA256'] == native[slot['primary']]['sha256'], 'Wrong/unbound v3 native primary')
    need(layers[1]['crop'] == [0, 0, *SIZE] and layers[1]['targetGeometry'] == design['layout']['device']['screenBox'], 'Original full-native coordinates/target lost')
    need(layers[0]['originalSource'] == 'branding/native-wordmark.png', 'Missing canonical native wordmark')
    with Image.open(source_path(sources, layers[0]['originalSource'])) as original_wordmark:
        wordmark_crop = original_wordmark.getchannel('A').getbbox()
    ww, hh = dimensions(wordmark_crop)
    container = design['layout']['wordmarkBox']
    wordmark_scale = min(1.0, dimensions(container)[0] / ww, dimensions(container)[1] / hh)
    need(layers[0]['targetGeometry'] == [container[0], container[1], container[0] + math.floor(ww * wordmark_scale + 0.5),
                                        container[1] + math.floor(hh * wordmark_scale + 0.5)]
         and layers[0]['nativeScale'] == wordmark_scale, 'Canonical original wordmark size/alignment changed')
    protected = [[0, 0, 1206, 200]] + slot['primaryProtectedRects']
    need(len(protected) > 1 and all(within(r, [0, 0, *SIZE]) for r in protected), 'Source-protected native regions missing')
    box = layers[1]['targetGeometry']
    sx, sy = dimensions(box)[0] / 1206, dimensions(box)[1] / 2622
    mapped = [[box[0] + math.floor(r[0] * sx), box[1] + math.floor(r[1] * sy), box[0] + math.ceil(r[2] * sx), box[1] + math.ceil(r[3] * sy)] for r in protected]
    geometry = phone_geometry(design)
    need(all(within(r, geometry['visibleGeometry']) for r in mapped), 'Viewport clip hides protected decisive primary evidence')
    need(row['protectedEvidence']['primary'] == slot['primary'] and row['protectedEvidence']['protectedSourceRects'] == protected
         and row['protectedEvidence']['protectedOutputRects'] == mapped, 'False protected source/output coordinates')
    if index not in INSETS:
        need(slot['insets'] == [] and row['protectedEvidence']['insets'] == [], 'Unexpected duplicated native UI focus')
        return
    name, source, evidence_keys = INSETS[index]
    need(len(slot['insets']) == 1 and len(row['protectedEvidence']['insets']) == 1, 'Exactly one required native inset')
    ins, layer, prepared = slot['insets'][0], layers[2], row['protectedEvidence']['insets'][0]
    need(ins['enabled'] is True and ins['required'] is True and ins['id'] == name and ins['source'] == f'screenshots/concept-a-{source}.png'
         and layer['originalSource'] == ins['source'] and layer['crop'] == ins['crop'] and layer['sourceSHA256'] == ins['cropSourceSHA256'] == native[ins['source']]['sha256'], 'Inset source/crop/hash binding differs')
    crop = ins['crop']
    need(within(crop, [0, 200, *SIZE]) and set(ins['cropEvidenceRects']) == evidence_keys
         and all(within(r, crop) for r in ins['cropEvidenceRects'].values()), 'Required whole native pair/dialog/series/button missing from actual crop')
    requested, cw, ch = ins['targetBox'], *dimensions(crop)
    scale = min(1.0, dimensions(requested)[0] / cw, dimensions(requested)[1] / ch)
    w, h = max(1, math.floor(cw * scale + 0.5)), max(1, math.floor(ch * scale + 0.5))
    x, y = requested[0] + (dimensions(requested)[0] - w) // 2, requested[1] + (dimensions(requested)[1] - h) // 2
    target = [x, y, x + w, y + h]
    need(ins.get('verticalAnchor') == ('bottom' if index in (3, 7) else 'center'), 'Wrong inset anchoring leaves repeated lower controls')
    if ins['verticalAnchor'] == 'bottom':
        target[1], target[3] = requested[3] - h, requested[3]
        y = target[1]
    need(layer['targetGeometry'] == target and layer['nativeScale'] == scale > max(sx, sy), 'Inset not enlarged truthfully by one contain resample')
    if name in ('series-decision', 'system-dialog'):
        need((target[0], target[2]) == (box[0], box[2]), 'Series/dialog focus leaves an exposed underlying native UI gutter')
    style = focus_style(design, name)
    radius = style['shadowBlur'] * 3 + 2
    dx, dy = style['shadowOffset']
    effect = [min(x, x - radius + dx), min(y, y - radius + dy), max(x + w, x + w + radius + dx), max(y + h, y + h + radius + dy)]
    if style['shadowAlpha'] == 0:
        effect = list(target)
    visible_effect = [effect[0], effect[1], effect[2], min(effect[3], SIZE[1])]
    need(within(target, geometry['visibleGeometry']) and within(effect, geometry['fullTargetGeometry'])
         and within(visible_effect, geometry['visibleGeometry'])
         and effect[1] >= box[1] + design['layout']['device']['screenRadius'] and not any(intersects(effect, r) for r in mapped), 'Native inset/shadow covers frame or parent-protected evidence')
    need(not any(intersects(effect, design['layout'][k]) for k in ('wordmarkBox', 'headlineBox', 'subtitleBox')), 'Inset shadow obscures marketing header')
    frame_binding = None
    if index == 3:
        frame = actual_dialog_rect(sources, ins['nativeRectEvidence'])
        binding = ins['nativeRectEvidence']
        need(binding['file'] == 'concept-a-delete-confirm-frame.json' and binding['jsonPointer'] == '/nativeRect'
             and binding['format'] == 'xyxy' and binding['coordinateScale'] == 1, 'Dialog frame must be the actual native scene receipt, not alternate guessed metadata')
        need(ins['cropEvidenceRects']['system-dialog'] == frame and within(frame, crop), 'Crop omits actual JSON-bound system dialog')
        frame_binding = {**ins['nativeRectEvidence'], 'nativePixelRect': frame}
    need(prepared == {'id': name, 'source': ins['source'], 'crop': crop, 'target': target,
                      'nativeScale': scale, 'magnificationRelativeToPhone': scale / sx,
                      'cropEvidenceRects': ins['cropEvidenceRects'], 'nativeRectEvidence': frame_binding,
                      'requestedBox': requested, 'verticalAnchor': ins['verticalAnchor'], 'effectBox': effect,
                      'visibleEffectBox': visible_effect, 'shadowViewportClip': 'bottom-only' if effect[3] > SIZE[1] else 'none'},
         'Inset prepared evidence differs from actual geometry')


def verify_marketing_text(final, row, design, font_records):
    """Read actual exported headline/subtitle pixels, not copy metadata alone."""
    root = Path(__file__).resolve().parents[2]
    for kind, color in (('headline', 'ink'), ('subtitle', 'subtitle')):
        plan, spec = row[kind], design['fonts'][kind]
        expected_font = 'PMDisplay-Bold.ttf' if kind == 'headline' else 'PMText-Medium.ttf'
        need(spec['path'] == f'PhotoMaid/Resources/Fonts/{expected_font}', 'Bundled app font changed')
        path = source_path(root, spec['path'])
        need(digest(path) == font_records[kind]['sha256'], 'App font hash drift')
        need(1 <= len(plan['lines']) <= 2 and ' '.join(plan['lines']) == plan['text'].replace('\n', ' ')
             and plan['fontSize'] >= (84 if kind == 'headline' else 46), 'Actual text plan rewrites/omits copy')
        container = design['layout'][kind + 'Box']
        need(plan['container'] == container, 'Text container changed')
        font = ImageFont.truetype(str(path), plan['fontSize'])
        expected = marketing_background(design)
        draw = ImageDraw.Draw(expected)
        actual_boxes = []
        for text, origin in zip(plan['lines'], plan['origins']):
            b = font.getbbox(text)
            actual_boxes.append([origin[0] + b[0], origin[1] + b[1], origin[0] + b[2], origin[1] + b[3]])
            draw.text(origin, text, font=font, fill=design['colors'][color])
        need(len(plan['origins']) == len(plan['lines']) and actual_boxes == plan['lineBBoxes']
             and all(within(b, container) for b in actual_boxes), 'Text bbox metadata differs from actual glyph ink')
        need(ImageChops.difference(final.crop(container), expected.crop(container)).getbbox() is None,
             f'Actual exported {kind} pixels differ from exact app-font/copy/color rendering')


def canonical_run_attempt(value, label):
    # Independently accept the collector's literal string or the API's integer.
    need((type(value) is int and value > 0) or
         (type(value) is str and re.fullmatch(r'[1-9][0-9]*', value) is not None),
         f'{label}: canonical positive run attempt required')
    return int(value)


def validate_run_binding(provenance, expected_commit, expected_run, expected_attempt):
    need(isinstance(expected_commit, str) and re.fullmatch('[0-9a-f]{40}', expected_commit)
         and isinstance(expected_run, str) and re.fullmatch('[1-9][0-9]*', expected_run),
         'Malformed literal independent native commit/run pin')
    attempt = canonical_run_attempt(expected_attempt, '--expected-run-attempt')
    need(provenance.get('commit') == expected_commit and provenance.get('workflow_run') == expected_run,
         'Independently pinned native run/SHA mismatch')
    need(canonical_run_attempt(provenance.get('run_attempt'), 'provenance.run_attempt') == attempt,
         'Native provenance differs from independently pinned run attempt')
    url = provenance.get('workflow_url')
    match = re.fullmatch(r'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/([1-9][0-9]*)(?:/attempts/([1-9][0-9]*))?', url) if isinstance(url, str) else None
    need(match and match.group(1) == expected_run, 'Native workflow URL/run disagreement')
    need(match.group(2) is None or match.group(2) == str(attempt), 'Native workflow URL/attempt disagreement')
    return attempt


def verify_manifest_attempt(manifest, expected_attempt):
    attempt = canonical_run_attempt(expected_attempt, '--expected-run-attempt')
    need(type(manifest.get('runAttempt')) is int and manifest['runAttempt'] == attempt
         and type(manifest.get('sourceGate', {}).get('expectedRunAttempt')) is int
         and manifest['sourceGate']['expectedRunAttempt'] == attempt, 'Render manifest lacks the independent exact attempt pin')
    return attempt


def preview_geometry(design, kind):
    """Derive every expected box from the SHA-bound design, never renderer metadata."""
    need(kind in ('overview', 'search'), 'Unknown preview kind')
    need(design['canvas']['width'] == 1206 and design['canvas']['height'] == 2622, 'Wrong preview source canvas')
    spec = design['previews'][kind]
    ids = list(range(1, 11)) if kind == 'overview' else [1, 2, 3]
    filename = '00-overview.jpg' if kind == 'overview' else '00-search-preview.jpg'
    need(spec['file'] == filename and spec['slotIds'] == ids and all(type(n) is int for n in spec['slotIds'])
         and type(spec['columns']) is int and spec['columns'] == len(ids), 'Design preview membership/order/single-row drift')
    need(all(type(spec[k]) is int and spec[k] > 0 for k in ('tileWidth', 'margin', 'gap'))
         and spec['tileWidth'] <= 1206, 'Invalid design preview sizing/upscale')
    w, margin, gap = spec['tileWidth'], spec['margin'], spec['gap']
    # Integer half-to-even rounding independently reconstructs round(2622*w/1206).
    h, remainder = divmod(2622 * w, 1206)
    h += int(2 * remainder > 1206 or (2 * remainder == 1206 and h % 2 == 1))
    width, height = 2 * margin + len(ids) * w + (len(ids) - 1) * gap, h + 2 * margin
    need(kind != 'search' or width == 390, 'Search preview must be exactly 390 pixels wide')
    cells = [{'slot': slot, 'targetGeometry': [margin + n * (w + gap), margin,
                                             margin + n * (w + gap) + w, margin + h]}
             for n, slot in enumerate(ids)]
    return {'file': filename, 'width': width, 'height': height, 'rows': 1, 'columns': len(ids),
            'slotIds': ids, 'tileSize': [w, h], 'cells': cells}


def verify_previews(render, previews, outputs, design):
    """Exact design/image/manifest geometry plus all actual numbered-PNG cell pixels."""
    need(isinstance(previews, list) and len(previews) == 2
         and {row['kind'] for row in previews} == {'overview', 'search'}, 'Exactly both unique preview kinds required')
    need(len(outputs) == 10 and [row['slot'] for row in outputs] == list(range(1, 11)), 'Preview needs ten ordered numbered exports')
    checked = []
    for row in previews:
        expected = preview_geometry(design, row['kind'])
        need(all(row.get(k) == v for k, v in expected.items()), 'Preview manifest geometry differs from SHA-bound design')
        need(all(type(row[k]) is int for k in ('width', 'height', 'rows', 'columns'))
             and isinstance(row['tileSize'], list) and all(type(n) is int for n in row['tileSize'])
             and all(type(n) is int for n in row['slotIds'])
             and isinstance(row['cells'], list) and all(isinstance(cell, dict) and set(cell) == {'slot', 'targetGeometry'}
                 and type(cell['slot']) is int and isinstance(cell['targetGeometry'], list)
                 and all(type(n) is int for n in cell['targetGeometry']) for cell in row['cells']), 'Noninteger preview geometry')
        path = render / expected['file']
        need(digest(path) == row['sha256'], 'Preview hash drift')
        meta = profile(path)
        need(meta['format'] == 'JPEG' and meta['size'] == [expected['width'], expected['height']],
             'Actual JPEG canvas differs from SHA-bound design')
        differences = []
        with Image.open(path) as preview:
            preview.load()
            for cell in expected['cells']:
                box = cell['targetGeometry']
                with Image.open(render / outputs[cell['slot'] - 1]['file']) as image:
                    need(image.format == 'PNG' and image.mode == 'RGB' and image.size == SIZE, 'Invalid actual numbered PNG for preview')
                    reference = image.resize(tuple(expected['tileSize']), Image.Resampling.LANCZOS)
                mean_difference = ImageStat.Stat(ImageChops.difference(preview.crop(box), reference)).mean
                need(max(mean_difference) < 4, 'Preview cells do not match actual numbered exports (JPEG tolerance)')
                differences.append(max(mean_difference))
        checked.append({'kind': row['kind'], **expected, 'sha256': row['sha256'],
                        'max_mean_channel_difference': max(differences)})
    return checked


def audit(render, sources, expected_commit, expected_run, expected_attempt):
    manifest = load(render / 'render-manifest.json')
    attempt = canonical_run_attempt(expected_attempt, '--expected-run-attempt')
    need(manifest.get('creativeRevision') == manifest.get('layoutRevision') == manifest.get('nativeRevision') == 3 and manifest.get('sampleMediaPolicy') == MEDIA_POLICY
         and manifest.get('nativeScenePolicy') == V3_SCENE_POLICY
         and manifest.get('capturePolicy') == 'single-new-green-stock-only-run', 'Old/mixed capture contract cannot pass v3')
    design_path = Path(manifest['design']['path'])
    need(digest(design_path) == manifest['design']['sha256'], 'Actual reviewed design file drift')
    design = load(design_path)
    geometry = phone_geometry(design)
    need(design.get('sampleMediaPolicy') == MEDIA_POLICY, 'Screenshot-free stock policy must not be disabled')
    need(design['background'] == {'top': '#E0EFF9', 'bottom': '#EAF4FB', 'interpolation': 'smoothstep'}, 'Locked ice-blue background drift')
    provenance = load(sources / 'capture_provenance.json')
    need(validate_run_binding(provenance, expected_commit, expected_run, attempt) == attempt, 'Native run binding differs')
    verify_manifest_attempt(manifest, attempt)
    need(provenance['status'] == 'PASS' and provenance['fresh_capture'] is True, 'Fresh native capture PASS is required')
    need(provenance['base_commit'] == '583eb804a81401aa2010996875b35d05afc61539' and provenance['branch'] == 'hermes/store-concept-a-en', 'Wrong native baseline/branch')
    summary = provenance['capture_summary']
    need(summary['result'] == 'Passed' and tuple(summary[k] for k in ('passedTests', 'failedTests', 'skippedTests')) == (1, 0, 0), 'Exactly one native passed test and no skips required')
    need(provenance['device']['name'] == 'iPhone 17 Pro', 'Native device disagreement')
    fixture = load(sources / 'fixture-manifest.json')
    need(digest(sources / 'fixture-manifest.json') == provenance['fixture_manifest_sha256'], 'Actual PhotoKit input manifest hash drift')
    stock_library = verify_stock_library(sources, provenance, fixture)
    scene_audit = verify_v3_scenes(sources, provenance, fixture)
    allowlist_path = Path(__file__).resolve().parents[2] / 'app-store/concepts/A/qa/fixture-source-allowlist.json'
    approved = {row['source']: row['sha256'] for row in load(allowlist_path)['approved'] if row['verdict'] == 'PASS'}
    visual_gate = provenance.get('fixture_visual_source_gate', {})
    need(visual_gate.get('status') == 'PASS' and visual_gate.get('all_used_sources_approved') is True
         and visual_gate.get('allowlist_sha256') == digest(allowlist_path), 'Native capture is not from the visually approved fixture subset')
    need(fixture['visual_source_gate'] == visual_gate and all(approved.get(row['source']) == row['source_sha256'] for row in fixture['records']), 'A rejected/unknown original was included in the actual native fixture')
    need(provenance['commit'] == expected_commit and provenance['workflow_run'] == expected_run, 'Independently pinned native run/SHA mismatch')
    need(provenance['locale'] == 'en-US' and provenance['app_language'] == 'en', 'Only en-US is authorized')
    need(manifest['sourceGate']['provenance'] == provenance, 'Render manifest is not bound to the exact fresh source provenance')
    need(manifest['sourceGate']['provenanceSHA256'] == digest(sources / 'capture_provenance.json'), 'Source-provenance file hash drift')
    need(Path(manifest['sourceGate']['sourceRoot']).resolve() == sources.resolve(), 'Native layers must all use exactly one source artifact/run')
    review = manifest['sourceVisualQA']
    need(review == design['finalSourceVisualQA'] and review['approved'] is True and review['provenanceSHA256'] == digest(sources / 'capture_provenance.json')
         and review['commit'] == expected_commit and review['workflowRun'] == expected_run
         and canonical_run_attempt(review.get('runAttempt'), 'source visual QA runAttempt') == attempt
         and all(isinstance(review.get(k), str) and review[k].strip() for k in ('reviewer', 'notes'))
         and set(review.get('requirements', {})) == REVIEW and all(v is True for v in review['requirements'].values()), 'Actual v3 source visual approval/hash requirements are absent or stale')
    need(review['nativeWordmarkComponent'] == 'VaultDialWordmark' and review['nativeWordmarkForeground'] == 'lightForeground'
         and review['nativeStatusBar'] == {'time': '9:41', 'fullBattery': True, 'dynamicIsland': True, 'appearance': 'dark'}, 'Canonical native branding/status confirmation missing')
    rows = manifest['outputs']
    need(len(rows) == 10 and [row['slot'] for row in rows] == list(range(1, 11)), 'Exactly ten ordered outputs are required')
    files = [row['file'] for row in rows]
    need(len(set(files)) == 10 and all(Path(name).name == name for name in files), 'Nonunique/unsafe export names')
    need([name[:3] for name in files] == [f'{index:02d}-' for index in range(1, 11)], 'Files must be numbered 01 through 10')
    need(sorted(path.name for path in render.glob('*.png')) == sorted(files), 'Unexpected or missing PNG exports')
    native = {row['file']: row for row in provenance['outputs']}
    need(len(native) == len(provenance['outputs']), 'Duplicate actual native output name')
    native[provenance['branding']['file']] = provenance['branding']
    for row in manifest['originalSources']:
        need(row['path'] in native and row['sha256'] == native[row['path']]['sha256'], 'Render references an unbound native source')
        need(digest(source_path(sources, row['path'])) == row['sha256'], 'Native source file drift')
    required_sources = {f'screenshots/concept-a-{name}.png' for name in set(PRIMARIES) | {'duplicates', 'trash', 'later'}} | {'branding/native-wordmark.png'}
    need(required_sources <= {row['path'] for row in manifest['originalSources']} and required_sources <= native.keys(), 'Missing exact required native evidence; no substitute source allowed')
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

        for text in [row['headline'], subtitle]:
            if text:
                for box in text['lineBBoxes']:
                    need(box[0] >= 70 and box[2] <= 1136 and box[1] >= 70 and box[3] <= 2552, 'Marketing text violates 70px safe margin')
        layers = row['nativeLayers']
        verify_insets(row, design['slots'][index - 1], design, sources, native)
        phones = [layer for layer in layers if layer['id'] == 'full-phone']
        need(len(phones) == 1 and phones[0]['crop'] == [0, 0, 1206, 2622], 'Missing original full native source coordinates')
        phone_boxes.append(phones[0]['targetGeometry'])
        need(any(layer['id'] == 'native-wordmark' and layer['originalSource'] == 'branding/native-wordmark.png' for layer in layers), 'Missing original native wordmark pixels')
        independent_pixels = 0
        with Image.open(path) as reopened:
            reopened.load()
            final = reopened.copy()
        verify_marketing_text(final, row, design, manifest['fonts'])
        for layer_index, layer in enumerate(layers):
            need(layer['sourceSHA256'] == native[layer['originalSource']]['sha256'], 'Layer uses unbound source hash')
            need(max(layer['effectiveNativeScaleXY']) <= 1.0, 'Native pixel upscaling')
            proof = layer['pixelQA']
            need(proof['status'] == 'PASS' and proof['comparedPixels'] > 0 and proof['maxChannelDifference'] == 0
                 and proof['maskedKnownResampleSHA256'] == proof['maskedOutputSHA256'], 'Native pixel equality proof failed')
            need(digest(source_path(sources, layer['originalSource'])) == layer['sourceSHA256'], 'Actual layer source hash drift')
            independent_pixels += verify_pixels(final, sources, layer, layers[layer_index + 1:], design)
        frame_pixels = verify_frame(final, design, row['framePixelQA'])
        layout = row['layoutQA']
        need(layout['status'] == 'PASS' and layout['protectedPrimaryEvidenceUnobscured'] is True
             and layout['allTextBBoxesInsideContainers'] is True and layout['nativeUpscaling'] is False
             and layout['secondDynamicIsland'] is False, 'Per-file composition gate failed')
        need(layout['phoneGeometry'] == geometry and layout['originalNativeCrop'] == [0, 0, *SIZE]
             and layout['phoneProportionalWithinHalfPixel'] is True and 'phoneAspectExact' not in layout, 'Old full-visible-phone assertion or false viewport geometry')
        checked.append({'slot': index, 'file': row['file'], 'sha256': row['sha256'], **meta,
                        'native_layers_verified': len(layers), 'independently_compared_native_pixels': independent_pixels,
                        'visible_hardware_frame_pixels_verified': frame_pixels, 'phone_geometry': geometry})
        hashes.append(row['sha256'])
    need(len(set(hashes)) == 10 and all(box == phone_boxes[0] for box in phone_boxes), 'Duplicate final image or inconsistent full-target phone geometry')
    need(manifest['layoutQA']['phoneGeometry'] == geometry and manifest['layoutQA']['requiredInsetSlots'] == [2, 3, 7]
         and manifest['layoutQA']['subtitleCount'] == 10 and manifest['layoutQA']['identicalFullTargetAndVisiblePhoneGeometry'] is True,
         'Old or false all-ten viewport/inset/subtitle contract')
    need(manifest['layoutQA']['overviewRows'] == 1 and manifest['layoutQA']['overviewSlots'] == list(range(1, 11)), 'Overview must contain all ten in one row')
    need(manifest['layoutQA']['searchSlots'] == [1, 2, 3], 'Search-preview order mismatch')
    preview_checks = verify_previews(render, manifest['previews'], rows, design)
    return {'schema_version': 1, 'creative_revision': 3, 'technical_export_status': 'PASS', 'workflow_run': expected_run,
            'run_attempt': attempt,
            'commit': expected_commit, 'locale': 'en-US', 'png_count': len(checked), 'images': checked,
            'preview_count': len(manifest['previews']), 'uniform_phone_box': phone_boxes[0],
            'fixture_visual_source_allowlist_sha256': digest(allowlist_path),
            'phone_geometry': geometry, 'required_inset_slots': [2, 3, 7], 'subtitle_count': 10, 'stock_library': stock_library,
            'native_scene_policy': V3_SCENE_POLICY, 'native_scene_audit': scene_audit,
            'render_manifest_sha256': digest(render / 'render-manifest.json'), 'design_sha256': manifest['design']['sha256'],
            'provenance_sha256': digest(sources / 'capture_provenance.json'),
            'previews': preview_checks,
            'native_pixels': 'PASS, independently compared to ICC-normalized original native files; outer alpha edges excluded',
            'human_final_visual_acceptance': 'NOT RUN by this automatic auditor',
            'security_runtime_conversion_or_store_upload_acceptance': 'NOT RUN'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', required=True, type=Path)
    parser.add_argument('--sources', required=True, type=Path)
    parser.add_argument('--expected-commit', required=True)
    parser.add_argument('--expected-workflow-run', required=True)
    parser.add_argument('--expected-run-attempt', required=True)
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    try:
        result = audit(args.render, args.sources, args.expected_commit, args.expected_workflow_run, args.expected_run_attempt)
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
