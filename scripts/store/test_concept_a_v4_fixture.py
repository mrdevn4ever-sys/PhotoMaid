#!/usr/bin/env python3
"""Independent, offline local tests for the separate v4 fixture/provenance gates.

Every generated JPEG/PNG/JSON is explicitly unit-test data in a disposable temp
folder, never stock approval or native capture evidence. No native capture PASS,
video decode PASS, workflow run, API response, or visual acceptance is fabricated.
Metadata-validator control objects exercise types/contracts only. Production
collect() is exercised only as a negative test using the real, missing environment.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import time
import unittest

from PIL import Image, PngImagePlugin

import build_concept_a_v4_fixture as builder
import collect_concept_a_v4_provenance as collector

EXPECTED_ROLES = (1, 4, 5, 6, 7, 9, 10, 13, 28, 29, 31, 33, 35, 36, 38)
PRETTY = (5, 10, 1, 4, 6, 7, 9, 13, 28, 29, 31, 33, 35, 36)
DERIVATIVES = (5, 10, 1, 4, 6, 7, 13, 35, 5, 7)
SCRIPT = Path(__file__).with_name('build_concept_a_v4_fixture.py')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, allow_nan=False) + '\n', encoding='utf-8')


def make_sources(root):
    source = root / 'unit-test-originals-NOT-STOCK'
    source.mkdir()
    photos = []
    for index, role in enumerate(EXPECTED_ROLES):
        # Prefixes deliberately disagree with roles; v4 must use capture_role.
        name = f'{90 - index:02d}-unit-test-pattern-{role}.jpg'
        raw = random.Random(role).randbytes(384 * 288 * 3)
        image = Image.frombytes('RGB', (384, 288), raw)
        image.save(source / name, quality=95, subsampling=0)
        photos.append({'file': name, 'sha256': sha(source / name), 'source': f'https://example.invalid/unit-test/{role}',
                       'author': 'Synthetic unit test, not a licensed stock source', 'license': 'CC0-1.0',
                       'license_url': 'https://creativecommons.org/publicdomain/zero/1.0/', 'width': 384, 'height': 288,
                       'capture_role': role})
    registry = {'purpose': 'UNIT TEST ONLY; not approved owner stock', 'photos': photos}
    allowlist = {'purpose': 'UNIT TEST ONLY; not owner visual acceptance', 'status': 'PASS_SELECTED_SUBSET_ONLY',
                 'approved_count': 15, 'approved': [{'source': row['file'], 'sha256': row['sha256'], 'verdict': 'PASS'} for row in photos]}
    path = root / 'unit-test-allowlist.json'
    write_json(source / 'manifest.json', registry)
    write_json(path, allowlist)
    return source, path, registry, allowlist


def image_manifest(source, allowlist, output):
    return builder.build_fixture(source, allowlist, output, skip_videos=True)


def metadata_only_37(image_report):
    """Declared-only video metadata for isolated negative tests, never real fixture PASS."""
    result = copy.deepcopy(image_report)
    result.update(status='PASS', videos=2)
    for index, role in enumerate((13, 35), 1):
        row = next(row for row in result['records'] if row['capture_role'] == role)
        video = {key: copy.deepcopy(row[key]) for key in ('capture_role', 'source', 'source_sha256', 'source_url', 'author', 'license', 'license_url', 'source_width', 'source_height')}
        video.update(file=f'CA_40_large_{index:02d}.mp4', category='large-video', media_type='video',
                     sha256=hashlib.sha256(f'UNIT TEST DECLARATION ONLY {index}'.encode()).hexdigest(), bytes=111_000_000,
                     size=[1920, 1080], adaptation='UNIT TEST METADATA, NOT AN ENCODED VIDEO',
                     video={'width': 1920, 'height': 1080, 'codec': 'h264', 'duration': 12.0, 'full_decode': 'PASS', 'audio_streams': 0})
        result['records'].append(video)
    return result


def summary_control():
    return {'result': 'Passed', 'passedTests': 1, 'failedTests': 0, 'skippedTests': 0, 'totalTestCount': 1,
            'expectedFailures': 0, 'testFailures': [], 'devicesAndConfigurations': [
                {'passedTests': 1, 'failedTests': 0, 'skippedTests': 0,
                 'device': {'modelName': 'iPhone 17 Pro', 'platform': 'iOS Simulator'}}]}


def test_tree_control():
    selector = 'AppStoreCaptureTests/test08ConceptAV4StoreScreenshots'
    return {'testNodes': [{'nodeType': 'Test Plan', 'result': 'Passed', 'children': [
        {'nodeType': 'Test Case', 'result': 'Passed', 'nodeIdentifier': selector + '()', 'name': selector.split('/')[1] + '()'}]}]}


def pin_control():
    return {'commit': 'a' * 40, 'workflow_run': '123', 'run_attempt': '2', 'branch': 'hermes/store-concept-a-en',
            'fresh_capture': True, 'locale': 'en-US', 'app_language': 'en',
            'workflow_url': 'https://github.com/unit-test/not-a-real-run/actions/runs/123/attempts/2'}


def api_metadata_control():
    # Structural object only; this is NEVER written or represented as an actual API readback.
    api = 'https://api.github.com/repos/unit-test/not-a-real-run/actions/runs/123'
    return {'run_attempt': 2, 'request_url': api + '/attempts/2',
            'attempt_readback': {'id': 123, 'run_attempt': 2, 'head_sha': 'a' * 40,
                                 'head_branch': 'hermes/store-concept-a-en', 'event': 'workflow_dispatch',
                                 'status': 'completed', 'conclusion': 'success', 'url': api,
                                 'html_url': 'https://github.com/unit-test/not-a-real-run/actions/runs/123',
                                 'jobs_url': api + '/attempts/2/jobs'},
            'attempt_jobs_readback': {'total_count': 1, 'jobs': [
                {'id': 456, 'run_id': 123, 'run_attempt': 2, 'head_sha': 'a' * 40,
                 'head_branch': 'hermes/store-concept-a-en', 'status': 'completed', 'conclusion': 'success'}]}}


def editor_metadata_control():
    return {'assetID': 'unit-asset-NOT-PHOTOKIT', 'loadState': 'ready', 'modelLoadState': 'ready', 'errors': [],
            'originalReady': True, 'previewReady': True, 'previewAssigned': True, 'publicationMatchesRequest': True,
            'rendering': False, 'previewRendering': False, 'dirty': False, 'comparing': False,
            'sourceOriginalPixelSHA256': 'a' * 64, 'publishedPreviewPixelSHA256': 'b' * 64,
            'requestedRecipeHash': 'c' * 64, 'publishedRecipeHash': 'c' * 64,
            'renderGeneration': 3, 'publishedRenderGeneration': 3,
            'sourceOriginalPixelWidth': 384, 'sourceOriginalPixelHeight': 288,
            'publishedPreviewPixelWidth': 384, 'publishedPreviewPixelHeight': 288,
            'publicationOrigin': 'renderAssignment', 'publishedFilter': 'warm',
            'publishedFilterStrength': 1, 'publishedIsIdentity': False,
            'pixelHashFormat': 'SHA256 of assigned RGBA8 CGImage packed pixel rows; stride padding excluded'}


def editor_pair_publication_control():
    """UNIT CONTRACT ONLY: distinct raw/neutral pixel strings, not native evidence."""
    observations = {}
    for label, generation in (('before', 3), ('filterSelection', 4), ('after', 4), ('undo', 5), ('redo', 6)):
        neutral = label in ('before', 'undo')
        row = editor_metadata_control()
        row.update(publishedFilter='original' if neutral else 'warm', publishedIsIdentity=neutral,
                   publishedPreviewPixelSHA256=('b' if neutral else 'd') * 64,
                   requestedRecipeHash=('c' if neutral else 'e') * 64,
                   publishedRecipeHash=('c' if neutral else 'e') * 64,
                   renderGeneration=generation, publishedRenderGeneration=generation)
        observations[label] = row
    return observations


def editor_duplicate_contract_control():
    """IN-MEMORY STRUCTURAL CONTROL ONLY; never a native proof or capture PASS."""
    observations = editor_pair_publication_control()
    ready = {'fixtureMode': False, 'setupErrors': [], 'readReady': True, 'libraryLoaded': True}
    selection = {'page': 'concept-a-editor', 'assetIDs': [observations['before']['assetID']],
                 'sourceFiles': ['CA_30_pretty_08.jpg']}
    for label, observation in observations.items():
        observation['tool'] = 'filter' if label == 'filterSelection' else 'adjust'
    legacy = {**ready, 'selection': copy.deepcopy(selection), 'editorV4': copy.deepcopy(observations['filterSelection'])}
    baseline = {**ready, 'unit_test_only': 'STRUCTURAL baseline, not actual native evidence'}
    log = [{'checkpoint': 'editor-original-selected', 'state': legacy},
           {'checkpoint': 'v4-editor-inventory-before', 'state': baseline}]
    targets = ('editor.tool.adjust', 'editor.tool.filter', 'editor.filter.thumbnail.WARM', 'editor.tool.adjust',
               'editor.undo', 'editor.redo', 'unit-save', 'unit-cancel')
    actions = [{'action': 'tap', 'started': 10.0 + 10 * index, 'finished': 11.0 + 10 * index,
                'targetAX': {'identifier': target, 'exists': True, 'enabled': True, 'hittable': True,
                             'frame': {'x': 10, 'y': 20, 'width': 40, 'height': 40}}} for index, target in enumerate(targets)]
    proof = {'purpose': 'UNIT CONTRACT ONLY; no native status or provenance is emitted',
             'assetID': observations['before']['assetID'], 'filename': 'CA_30_pretty_08.jpg',
             'beforeState': baseline, 'actions': actions, 'checkpoints': {}}
    captures = [{'file': 'concept-a-editor.png', 'status': 'PASS', 'language': 'en', 'appearance': 'dark',
                 'purpose': 'STRUCTURAL receipt fields only; no actual capture'}]
    config = (('before', 'before', 'v4-editor-original-adjust', 0),
              ('filterSelection', 'filter-selected', 'v4-editor-warm-published', 2),
              ('after', 'after', 'v4-editor-warm-matched-adjust', 3),
              ('undo', 'undo', 'v4-editor-real-undo', 4), ('redo', 'redo', 'v4-editor-real-redo', 5))
    for label, stem, checkpoint, action_index in config:
        name = 'concept-a-v4-editor-' + stem
        observation = observations[label]
        state = {**ready, 'selection': copy.deepcopy(selection), 'editorV4': copy.deepcopy(observation)}
        log.extend([{'checkpoint': checkpoint, 'state': copy.deepcopy(state)},
                    {'checkpoint': name + '-capture-readback', 'state': copy.deepcopy(state)}])
        sha_value = hashlib.sha256(('UNIT CONTRACT ONLY ' + label).encode()).hexdigest()
        row = {'file': 'screenshots/' + name + '.png', 'screenshotSHA256': sha_value,
               'editorV4': {key: observation[key] for key in collector.EDITOR_CORE_FIELDS},
               'editorObservation': copy.deepcopy(observation),
               'stability': {'samples': [{'file': f'stills/{name}-stability-{index}.png',
                                         'captureStarted': actions[action_index]['finished'] + 1 + index,
                                         'captureFinished': actions[action_index]['finished'] + 1.25 + index,
                                         'screenshotSHA256': sha_value} for index in range(2)]}}
        proof['checkpoints'][label] = row
        captures.append({'file': name + '.png', 'status': 'PASS', 'language': 'en', 'appearance': 'dark',
                         'purpose': 'STRUCTURAL receipt fields only; no actual capture'})
    return proof, log, captures


class TempCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='galeriq-v4-unit-', dir=tempfile.gettempdir())
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)


class RegistryTests(TempCase):
    def setUp(self):
        super().setUp()
        self.source, self.allow_path, self.registry, self.allowlist = make_sources(self.root)

    def test_explicit_roles_not_filename_prefixes(self):
        result, manifest_sha, allow_sha = builder.load_sources(self.source, self.allow_path)
        self.assertEqual(set(result), set(EXPECTED_ROLES))
        self.assertTrue(result[5]['file'].startswith('88-'))
        self.assertEqual(manifest_sha, sha(self.source / 'manifest.json'))
        self.assertEqual(allow_sha, sha(self.allow_path))

    def test_missing_wrong_duplicate_and_coerced_roles_rejected(self):
        for role in (None, True, 5.0, '5', 2, 1):
            with self.subTest(role=role):
                data = copy.deepcopy(self.registry)
                data['photos'][2]['capture_role'] = role
                with self.assertRaises(ValueError):
                    builder.validate_registry(data, self.allowlist)

    def test_registry_and_allowlist_counts_not_trusted(self):
        for count in (14, 16, True, 15.0, '15'):
            with self.subTest(count=count):
                allow = copy.deepcopy(self.allowlist)
                allow['approved_count'] = count
                with self.assertRaises(ValueError):
                    builder.validate_registry(self.registry, allow)
        for rows in (self.registry['photos'][:-1], self.registry['photos'] + self.registry['photos'][:1]):
            with self.assertRaises(ValueError):
                builder.validate_registry({'photos': rows}, self.allowlist)

    def test_original_hash_mismatch_rejected_before_output(self):
        target = self.source / self.registry['photos'][0]['file']
        with target.open('ab') as stream:
            stream.write(b'UNIT TEST MUTATION')
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            image_manifest(self.source, self.allow_path, self.root / 'out')
        self.assertFalse((self.root / 'out').exists())

    def test_unapproved_and_blocked_and_missing_original_rejected(self):
        for mutation in ('verdict', 'missing', 'hash', 'duplicate', 'status'):
            with self.subTest(mutation=mutation):
                allow = copy.deepcopy(self.allowlist)
                if mutation == 'verdict':
                    allow['approved'][0]['verdict'] = 'BLOCKED'
                elif mutation == 'missing':
                    allow['approved'].pop()
                elif mutation == 'hash':
                    allow['approved'][0]['sha256'] = '0' * 64
                elif mutation == 'duplicate':
                    allow['approved'][-1] = allow['approved'][0]
                else:
                    allow['status'] = 'PASS'
                with self.assertRaises(ValueError):
                    builder.validate_registry(self.registry, allow)

    def test_license_author_url_and_dimensions_rejected(self):
        for key, value in (('license', 'Unsplash'), ('author', ''), ('source', '/local/not-a-source'),
                           ('license_url', 'https://example.invalid/CC0'), ('width', True), ('height', '288')):
            with self.subTest(key=key):
                data = copy.deepcopy(self.registry)
                data['photos'][0][key] = value
                with self.assertRaises(ValueError):
                    builder.validate_registry(data, self.allowlist)
        data = copy.deepcopy(self.registry)
        data['photos'][0]['height'] += 1
        write_json(self.source / 'manifest.json', data)
        with self.assertRaisesRegex(ValueError, 'dimension metadata mismatch'):
            builder.load_sources(self.source, self.allow_path)

    def test_bad_literal_hash_and_filename_rejected(self):
        for key, value in (('sha256', ' A' * 32), ('sha256', self.registry['photos'][0]['sha256'].upper()),
                           ('file', '../unit.jpg'), ('file', 'sub/stock.jpg'), ('file', 'C:stock.jpg'),
                           ('file', 'native-library.jpg'), ('file', 'app-screenshot.jpg')):
            with self.subTest(key=key, value=value):
                data = copy.deepcopy(self.registry)
                data['photos'][0][key] = value
                with self.assertRaises(ValueError):
                    builder.validate_registry(data, self.allowlist)

    def test_allowlist_role_if_recorded_must_match_original(self):
        allow = copy.deepcopy(self.allowlist)
        allow['approved'][0]['capture_role'] = 4
        with self.assertRaises(ValueError):
            builder.validate_registry(self.registry, allow)

    def test_duplicate_json_keys_and_nonfinite_values_rejected(self):
        target = self.root / 'bad.json'
        for raw in ('{"photos":[],"photos":[]}', '{"number":NaN}', '{"number":Infinity}'):
            target.write_text(raw, encoding='utf-8')
            with self.assertRaises(ValueError):
                builder.load_json(target)

    def test_output_inside_source_or_repository_or_nonempty_rejected(self):
        existing = self.root / 'nonempty'
        existing.mkdir()
        sentinel = existing / 'preserve.txt'
        sentinel.write_bytes(b'PRESERVE')
        for path in (self.source, self.source / 'derived', builder.REPO_ROOT / 'NEVER_CREATE_UNIT_FIXTURE', existing):
            with self.subTest(path=path):
                with self.assertRaises(ValueError):
                    image_manifest(self.source, self.allow_path, path)
        self.assertEqual(sentinel.read_bytes(), b'PRESERVE')

    def test_images_only_real_files_exact_names_roles_hashes_and_no_upscale(self):
        before = {path.name: sha(path) for path in self.source.iterdir()}
        output = self.root / 'images'
        report = image_manifest(self.source, self.allow_path, output)
        expected = {'CA_01_clutter_blur.jpg': 5, 'CA_02_clutter_shake.jpg': 10, 'CA_03_clutter_dark.jpg': 5,
                    'CA_10_duplicate_a.jpg': 38, 'CA_11_duplicate_b.jpg': 38,
                    **{f'CA_20_series_{n:02d}.jpg': 36 for n in range(1, 7)},
                    **{f'CA_30_pretty_{n:02d}.jpg': role for n, role in enumerate(PRETTY + DERIVATIVES, 1)}}
        self.assertEqual(report['status'], 'IMAGES_ONLY_NOT_CAPTURE_READY')
        self.assertEqual((report['creative_revision'], report['images'], report['videos']), (4, 35, 0))
        rows = {row['file']: row for row in report['records']}
        self.assertEqual({name: row['capture_role'] for name, row in rows.items()}, expected)
        self.assertEqual({path.name for path in output.iterdir()}, set(expected) | {'fixture-manifest.json'})
        original_rows = {row['capture_role']: row for row in self.registry['photos']}
        hashes = {}
        for name, row in rows.items():
            original = original_rows[row['capture_role']]
            self.assertEqual((row['sha256'], row['bytes']), (sha(output / name), (output / name).stat().st_size))
            self.assertEqual((row['source'], row['source_sha256'], row['source_url']), (original['file'], original['sha256'], original['source']))
            self.assertEqual((row['license'], row['author'], row['license_url']), (original['license'], original['author'], original['license_url']))
            with Image.open(output / name) as image:
                image.load()
                self.assertEqual(list(image.size), row['size'])
                self.assertLessEqual(image.width, original['width'])
                self.assertLessEqual(image.height, original['height'])
            hashes.setdefault(row['sha256'], []).append(name)
        self.assertEqual(sorted(sorted(value) for value in hashes.values() if len(value) > 1), [['CA_10_duplicate_a.jpg', 'CA_11_duplicate_b.jpg']])
        self.assertEqual(report['source_manifest_sha256'], sha(self.source / 'manifest.json'))
        self.assertEqual(report['visual_source_gate']['allowlist_sha256'], sha(self.allow_path))
        self.assertEqual(before, {path.name: sha(path) for path in self.source.iterdir()})
        with self.assertRaises(ValueError):
            collector.validate_fixture_metadata(report, self.registry, self.allowlist, sha(self.source / 'manifest.json'), sha(self.allow_path))

    def test_collage_input_crops_are_declared_portraits_without_resize(self):
        output = self.root / 'portrait-inputs'
        report = image_manifest(self.source, self.allow_path, output)
        originals = {row['capture_role']: row for row in self.registry['photos']}
        rows = {row['file']: row for row in report['records']}
        for index, role in enumerate((5, 10, 1, 4), 1):
            row = rows[f'CA_30_pretty_{index:02d}.jpg']
            original = originals[role]
            unit = min(original['width'] // 4, original['height'] // 5)
            w, h = unit * 4, unit * 5
            left, top = (original['width'] - w) // 2, (original['height'] - h) // 2
            self.assertEqual(row['source_crop'], [left, top, left + w, top + h])
            self.assertEqual(row['size'], [w, h])
            self.assertEqual(row['category'], 'pretty-collage-portrait')
            self.assertIn('no resize or upscale', row['adaptation'])
            self.assertNotEqual(row['sha256'], original['sha256'])
        self.assertEqual(builder.collage_portrait_rect(400, 500), [0, 0, 400, 500])
        for dims in ((True, 500), (400.0, 500), (0, 500), (3, 4)):
            with self.assertRaises(ValueError):
                builder.collage_portrait_rect(*dims)

    def test_two_videos_required_and_small_source_cannot_be_upscaled(self):
        for value in (0, 1, True, '2'):
            with self.assertRaises(ValueError):
                builder.build_fixture(self.source, self.allow_path, self.root / 'videos', video_count=value)
        with self.assertRaisesRegex(ValueError, 'without upscaling'):
            builder.build_fixture(self.source, self.allow_path, self.root / 'videos')
        self.assertFalse((self.root / 'videos').exists())

    def test_cli_requires_allowlist_and_rejects_single_video(self):
        env = {**os.environ, 'PYTHONDONTWRITEBYTECODE': '1', 'TEMP': 'F:/HermesTemp', 'TMP': 'F:/HermesTemp', 'TMPDIR': 'F:/HermesTemp'}
        common = [sys.executable, str(SCRIPT), '--sources', str(self.source), '--output', str(self.root / 'cli')]
        result = subprocess.run(common + ['--skip-videos'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        result = subprocess.run(common + ['--allowlist', str(self.allow_path), '--video-count', '1'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.root / 'cli').exists())


class FixtureMetadataTests(TempCase):
    def setUp(self):
        super().setUp()
        self.source, self.allow_path, self.registry, self.allowlist = make_sources(self.root)
        self.output = self.root / 'images'
        self.fixture = metadata_only_37(image_manifest(self.source, self.allow_path, self.output))
        self.manifest_sha, self.allow_sha = sha(self.source / 'manifest.json'), sha(self.allow_path)

    def validate(self, fixture=None):
        return collector.validate_fixture_metadata(fixture or self.fixture, self.registry, self.allowlist, self.manifest_sha, self.allow_sha)

    def test_structural_37_control_has_no_real_video_files(self):
        self.assertEqual(len(self.validate()), 37)
        with self.assertRaises(ValueError):
            collector.verify_fixture_files(self.output, self.fixture, self.validate(), self.source)

    def test_collage_crop_metadata_cannot_be_missing_coerced_or_forged(self):
        for key, value in (('source_crop', None), ('source_crop', [0, 0, 20, 25]),
                           ('source_crop', [78.0, 1, 306, 286]), ('source_crop', [True, 1, 306, 286]),
                           ('size', [230, 285]), ('category', 'pretty')):
            data = copy.deepcopy(self.fixture)
            row = next(row for row in data['records'] if row['file'] == 'CA_30_pretty_01.jpg')
            row[key] = value
            with self.subTest(key=key, value=value), self.assertRaisesRegex(ValueError, 'centered 4:5'):
                self.validate(data)
        data = copy.deepcopy(self.fixture)
        data['records'][0]['source_crop'] = [0, 0, 20, 25]
        with self.assertRaisesRegex(ValueError, 'unexpected collage crop'):
            self.validate(data)

    def test_wrong_asset_count_extra_missing_duplicate_rejected(self):
        for kind in ('extra', 'missing', 'duplicate', 'images-bool', 'videos-float'):
            with self.subTest(kind=kind):
                data = copy.deepcopy(self.fixture)
                if kind == 'extra':
                    data['records'].append(data['records'][0])
                elif kind == 'missing':
                    data['records'].pop()
                elif kind == 'duplicate':
                    data['records'][-1] = data['records'][0]
                elif kind == 'images-bool':
                    data['images'] = True
                else:
                    data['videos'] = 2.0
                with self.assertRaises(ValueError):
                    self.validate(data)

    def test_every_source_field_and_explicit_role_enforced(self):
        for key in ('source', 'source_sha256', 'source_url', 'author', 'license', 'license_url', 'source_width', 'source_height', 'capture_role'):
            with self.subTest(key=key):
                data = copy.deepcopy(self.fixture)
                data['records'][0].pop(key)
                with self.assertRaises(ValueError):
                    self.validate(data)
        data = copy.deepcopy(self.fixture)
        data['records'][-1]['capture_role'] = 13
        with self.assertRaises(ValueError):
            self.validate(data)

    def test_stale_registry_allowlist_or_v3_revision_rejected(self):
        for key, value in (('source_manifest_sha256', '0' * 64), ('creative_revision', 3), ('source_library_verified', 55)):
            data = copy.deepcopy(self.fixture)
            data[key] = value
            with self.assertRaises(ValueError):
                self.validate(data)
        data = copy.deepcopy(self.fixture)
        data['visual_source_gate']['allowlist_sha256'] = '0' * 64
        with self.assertRaises(ValueError):
            self.validate(data)

    def test_measured_large_video_metadata_required(self):
        for key, value in (('bytes', 1), ('media_type', 'image'), ('sha256', 'bad')):
            data = copy.deepcopy(self.fixture)
            data['records'][-1][key] = value
            with self.assertRaises(ValueError):
                self.validate(data)
        for key, value in (('full_decode', 'NOT RUN'), ('audio_streams', True), ('codec', 'hevc'), ('duration', float('inf'))):
            data = copy.deepcopy(self.fixture)
            data['records'][-1]['video'][key] = value
            with self.assertRaises(ValueError):
                self.validate(data)


class StrictRunAndSummaryTests(unittest.TestCase):
    def test_literal_attempt_rejects_repairable_and_wrong_types(self):
        for value in (None, '', '0', '-1', '+1', '01', ' 1', '1 ', '1.0', '1e0', '١', True, 1, 1.0):
            with self.subTest(value=value):
                data = pin_control()
                data['run_attempt'] = value
                with self.assertRaises(ValueError):
                    collector.validate_run_pins(data)
        self.assertEqual(collector.validate_run_pins(pin_control())['run_attempt'], '2')

    def test_url_attempt_run_commit_and_branch_rejected(self):
        for key, value in (('workflow_url', 'https://github.com/unit-test/not-a-real-run/actions/runs/123/attempts/02'),
                           ('workflow_url', 'https://github.com/unit-test/not-a-real-run/actions/runs/123/attempts/3'),
                           ('workflow_run', '0123'), ('commit', 'A' * 40), ('branch', 'main')):
            data = pin_control()
            data[key] = value
            with self.assertRaises(ValueError):
                collector.validate_run_pins(data)

    def test_api_integer_attempt_not_coerced_or_latest_run_substituted(self):
        self.assertEqual(collector.validate_exact_attempt_readback(api_metadata_control(), pin_control())['actual_api_run_attempt'], 2)
        for value in (None, 0, -1, True, 2.0, '2', '02', '+2', ' 2'):
            with self.subTest(value=value):
                data = api_metadata_control()
                data['attempt_readback']['run_attempt'] = value
                with self.assertRaises(ValueError):
                    collector.validate_exact_attempt_readback(data, pin_control())
        with self.assertRaises(ValueError):
            collector.validate_exact_attempt_readback({'run': {'status': 'completed', 'conclusion': 'success'}}, pin_control())

    def test_api_wrong_attempt_job_skip_pagination_and_wrong_sha_rejected(self):
        for kind in ('attempt', 'sha', 'skip-job', 'wrong-job-attempt', 'partial-jobs', 'wrong-endpoint'):
            with self.subTest(kind=kind):
                data = api_metadata_control()
                if kind == 'attempt':
                    data['attempt_readback']['run_attempt'] = 3
                elif kind == 'sha':
                    data['attempt_readback']['head_sha'] = 'b' * 40
                elif kind == 'skip-job':
                    data['attempt_jobs_readback']['jobs'][0]['conclusion'] = 'skipped'
                elif kind == 'wrong-job-attempt':
                    data['attempt_jobs_readback']['jobs'][0]['run_attempt'] = 3
                elif kind == 'partial-jobs':
                    data['attempt_jobs_readback']['total_count'] = 2
                else:
                    data['request_url'] = data['request_url'].replace('/attempts/2', '')
                with self.assertRaises(ValueError):
                    collector.validate_exact_attempt_readback(data, pin_control())

    def test_summary_rejects_skips_multiple_tests_bool_and_historical_test(self):
        self.assertEqual(collector.validate_capture_summary(summary_control(), test_tree_control())['passed'], 1)
        for key, value in (('passedTests', 2), ('passedTests', True), ('passedTests', 1.0), ('skippedTests', 1),
                           ('totalTestCount', 2), ('expectedFailures', 1), ('testFailures', ['failure'])):
            data = summary_control()
            data[key] = value
            with self.assertRaises(ValueError):
                collector.validate_capture_summary(data, test_tree_control())
        data = test_tree_control()
        data['testNodes'][0]['children'][0]['nodeIdentifier'] = 'AppStoreCaptureTests/test07ConceptAStoreScreenshots()'
        with self.assertRaises(ValueError):
            collector.validate_capture_summary(summary_control(), data)
        with self.assertRaises(ValueError):
            collector.validate_capture_summary(summary_control(), {'testNodes': []})


class NativeDuplicateContractTests(unittest.TestCase):
    """STRUCTURAL ONLY. No files here are accepted as native evidence."""
    def setUp(self):
        self.proof, self.log, self.captures = editor_duplicate_contract_control()

    def test_only_three_explicit_two_member_groups_are_candidates(self):
        self.assertEqual(set(collector.EDITOR_DUPLICATE_PAIRS),
                         {'before/undo', 'after/redo', 'legacy-warm/filter-selection'})
        screens = {}
        for index, pair in enumerate(collector.EDITOR_DUPLICATE_PAIRS.values()):
            sha_value = hashlib.sha256(f'UNIT GROUP {index}'.encode()).hexdigest()
            for name in pair:
                screens[name] = {'file': name, 'sha256': sha_value}
        groups = collector.validate_native_duplicate_groups(screens)
        self.assertEqual({row['pair'] for row in groups}, set(collector.EDITOR_DUPLICATE_PAIRS))
        self.assertTrue(all('status' not in row for row in groups))  # no native PASS from names

    def test_third_state_and_unrelated_groups_remain_rejected(self):
        for label, pair in collector.EDITOR_DUPLICATE_PAIRS.items():
            for third in ('screenshots/concept-a-trash.png', 'screenshots/concept-a-v4-editor-copy-default.png'):
                screens = {name: {'file': name, 'sha256': 'a' * 64} for name in (*pair, third)}
                with self.subTest(pair=label, third=third), self.assertRaisesRegex(ValueError, 'Unrelated required native screen'):
                    collector.validate_native_duplicate_groups(screens)
        pair = ('screenshots/concept-a-swipe.png', 'screenshots/concept-a-trash.png')
        with self.assertRaisesRegex(ValueError, 'Unrelated required native screen'):
            collector.validate_native_duplicate_groups({name: {'file': name, 'sha256': 'b' * 64} for name in pair})

    def test_group_hashes_and_inventory_keys_are_literal(self):
        for row in ({'file': 'other.png', 'sha256': 'a' * 64}, {'file': 'unit.png', 'sha256': 'A' * 64},
                    {'file': 'unit.png'}, {'file': 'unit.png', 'sha256': True}):
            with self.subTest(row=row), self.assertRaises(ValueError):
                collector.validate_native_duplicate_groups({'unit.png': row})

    def test_ordered_separate_action_capture_contract_only(self):
        result = collector.validate_editor_duplicate_receipts(self.proof, self.log, self.captures)
        self.assertEqual(set(result), {'before', 'filterSelection', 'after', 'undo', 'redo'})
        self.assertLess(result['before']['capture_finished'], result['undo']['action_started'])
        self.assertLess(result['after']['published_generation'], result['redo']['published_generation'])

    def test_wrong_missing_repeated_and_reordered_capture_receipts_rejected(self):
        for kind in ('missing', 'wrong-file', 'repeated', 'reordered', 'failed', 'wrong-language', 'wrong-appearance', 'component'):
            captures = copy.deepcopy(self.captures)
            if kind == 'missing':
                captures.pop(4)
            elif kind == 'wrong-file':
                captures[4]['file'] = 'unrelated.png'
            elif kind == 'repeated':
                captures.append(copy.deepcopy(captures[4]))
            elif kind == 'reordered':
                captures[3], captures[4] = captures[4], captures[3]
            else:
                key, value = {'failed': ('status', 'FAIL'), 'wrong-language': ('language', 'de'),
                              'wrong-appearance': ('appearance', 'light'), 'component': ('kind', 'native-component')}[kind]
                captures[4][key] = value
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                collector.validate_editor_duplicate_receipts(self.proof, self.log, captures)

    def test_wrong_missing_and_out_of_order_native_actions_rejected(self):
        for kind in ('missing', 'wrong-target', 'reordered', 'stale-time', 'unhittable', 'bool-time'):
            proof = copy.deepcopy(self.proof)
            actions = proof['actions']
            if kind == 'missing':
                actions.pop(4)
            elif kind == 'wrong-target':
                actions[4]['targetAX']['identifier'] = 'editor.redo'
            elif kind == 'reordered':
                actions[4], actions[5] = actions[5], actions[4]
            elif kind == 'stale-time':
                actions[4]['started'] = actions[3]['started']
            elif kind == 'unhittable':
                actions[4]['targetAX']['hittable'] = False
            else:
                actions[4]['started'] = True
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                collector.validate_editor_duplicate_receipts(proof, self.log, self.captures)

    def test_separate_captures_must_be_between_their_own_actions(self):
        for kind in ('before-action', 'after-next-action', 'reused-still', 'missing-still', 'reordered-stills', 'wrong-final-hash', 'bool-time'):
            proof = copy.deepcopy(self.proof)
            row = proof['checkpoints']['undo']
            samples = row['stability']['samples']
            if kind == 'before-action':
                samples[0]['captureStarted'] = 2
            elif kind == 'after-next-action':
                samples[-1]['captureFinished'] = 61
            elif kind == 'reused-still':
                samples[0]['file'] = proof['checkpoints']['before']['stability']['samples'][0]['file']
            elif kind == 'missing-still':
                samples.pop()
            elif kind == 'reordered-stills':
                samples[0], samples[1] = samples[1], samples[0]
            elif kind == 'wrong-final-hash':
                row['screenshotSHA256'] = 'f' * 64
            else:
                samples[0]['captureStarted'] = True
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                collector.validate_editor_duplicate_receipts(proof, self.log, self.captures)

    def test_named_ready_and_capture_readbacks_cannot_be_missing_reused_or_reordered(self):
        for kind in ('missing', 'reordered', 'unready', 'wrong-state', 'wrong-publication'):
            log = copy.deepcopy(self.log)
            index = next(i for i, row in enumerate(log) if row['checkpoint'] == 'concept-a-v4-editor-undo-capture-readback')
            if kind == 'missing':
                log[index]['checkpoint'] = 'unit-unrelated'
            elif kind == 'reordered':
                log.insert(3, log.pop(index))
            elif kind == 'unready':
                log[index]['state']['readReady'] = False
            elif kind == 'wrong-state':
                log[index]['state']['editorV4']['publishedPreviewPixelSHA256'] = 'f' * 64
            else:
                log[index - 1]['state']['editorV4']['publishedPreviewPixelSHA256'] = 'f' * 64
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                collector.validate_editor_duplicate_receipts(self.proof, log, self.captures)

    def test_coherently_changed_asset_recipe_pixels_generation_and_unready_fail(self):
        for key, value in (('assetID', 'other-unit-asset'), ('sourceOriginalPixelSHA256', 'f' * 64),
                           ('publishedPreviewPixelSHA256', 'f' * 64), ('publishedRecipeHash', 'f' * 64),
                           ('publishedRenderGeneration', 4), ('previewAssigned', False), ('publicationOrigin', 'originalAssignment')):
            proof, log = copy.deepcopy(self.proof), copy.deepcopy(self.log)
            row = proof['checkpoints']['undo']
            row['editorObservation'][key] = value
            if key in row['editorV4']:
                row['editorV4'][key] = value
            for entry in log:
                if entry['checkpoint'] in ('v4-editor-real-undo', 'concept-a-v4-editor-undo-capture-readback'):
                    entry['state']['editorV4'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                collector.validate_editor_duplicate_receipts(proof, log, self.captures)

    def test_legacy_and_new_warm_must_bind_actual_same_publication(self):
        result = collector.validate_legacy_warm_duplicate(self.proof, self.log)
        self.assertLess(*result['readback_indices'])
        for key, value in (('assetID', 'other-unit-asset'), ('sourceOriginalPixelSHA256', 'f' * 64),
                           ('sourceOriginalPixelWidth', 385), ('publishedPreviewPixelSHA256', 'f' * 64),
                           ('requestedRecipeHash', 'f' * 64), ('publishedRecipeHash', 'f' * 64),
                           ('publishedFilterStrength', True), ('publishedRenderGeneration', 0),
                           ('loadState', 'notReady'), ('previewAssigned', False), ('tool', 'adjust')):
            for occurrence in (0, next(i for i, row in enumerate(self.log)
                                      if row['checkpoint'] == 'concept-a-v4-editor-filter-selected-capture-readback')):
                log = copy.deepcopy(self.log)
                log[occurrence]['state']['editorV4'][key] = value
                with self.subTest(key=key, occurrence=occurrence), self.assertRaises(ValueError):
                    collector.validate_legacy_warm_duplicate(self.proof, log)

    def test_legacy_warm_selection_readback_order_and_readiness_required(self):
        for kind in ('missing', 'reordered', 'unready', 'wrong-file', 'wrong-selection', 'wrong-page'):
            log = copy.deepcopy(self.log)
            if kind == 'missing':
                log[0]['checkpoint'] = 'unrelated'
            elif kind == 'reordered':
                log.append(log.pop(0))
            elif kind == 'unready':
                log[0]['state']['readReady'] = False
            else:
                key, value = {'wrong-file': ('sourceFiles', ['other.jpg']), 'wrong-selection': ('assetIDs', ['other']),
                              'wrong-page': ('page', 'concept-a-collage')}[kind]
                log[0]['state']['selection'][key] = value
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                collector.validate_legacy_warm_duplicate(self.proof, log)

    def test_xctest_legacy_and_new_warm_actions_are_distinct_and_ordered(self):
        operations = ('Checking existence of `"store.capture.concept-a-editor" Window`',
                      'Tap "editor.tool.filter" Button', 'Tap "editor.filter.thumbnail.WARM" Button')
        lines = [f'    t = {index + 1}.00s {operation}' for index, operation in enumerate(operations * 2)]
        text = 'UNIT STRUCTURAL LOG TEXT ONLY, NOT NATIVE EVIDENCE\n' + '\n'.join(lines)
        self.assertEqual(len(collector.validate_warm_duplicate_actions(text)['legacy']), 3)
        for kind in ('missing', 'wrong-action', 'repeated', 'reordered', 'reversed-time'):
            changed = list(lines)
            if kind == 'missing':
                changed.pop(2)
            elif kind == 'wrong-action':
                changed[2] = changed[2].replace('Tap ', 'Find the ')
            elif kind == 'repeated':
                changed.append(changed[2])
            elif kind == 'reordered':
                changed[2], changed[3] = changed[3], changed[2]
            else:
                changed[-1] = changed[-1].replace('6.00s', '0.00s')
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                collector.validate_warm_duplicate_actions('\n'.join(changed))


class ProofGateTests(TempCase):
    def test_actual_photo_crop_comparison_rejects_one_changed_pixel(self):
        # Geometry/pixel primitive only: these plainly labelled rectangles are
        # never submitted to collect() and never establish native capture PASS.
        name = 'concept-a-v4-editor-after'
        screen = 'screenshots/' + name + '.png'
        (self.root / 'screenshots').mkdir()
        (self.root / 'stills').mkdir()
        info = PngImagePlugin.PngInfo()
        info.add_text('purpose', 'UNIT TEST RECTANGLE ONLY, NOT A NATIVE APP SCREEN')
        image = Image.new('RGB', (1206, 2622), (61, 67, 71))
        image.save(self.root / screen, pnginfo=info)
        samples = []
        for index in range(2):
            path = f'stills/{name}-stability-{index}.png'
            image.save(self.root / path, pnginfo=info)
            samples.append({'file': path, 'screenshotSHA256': sha(self.root / path),
                            'photoPixelSHA256': 'd' * 64, 'captureStarted': index + 1.0, 'captureFinished': index + 1.5})
        def ax(identifier, frame, selected=False):
            return {'identifier': identifier, 'frame': frame, 'exists': True, 'enabled': True, 'hittable': True, 'selected': selected}
        observation = editor_metadata_control()
        state = {'fixtureMode': False, 'setupErrors': [], 'readReady': True, 'libraryLoaded': True, 'editorV4': observation}
        log = [{'checkpoint': name + '-capture-readback', 'state': state}]
        row = {'file': screen, 'screenshotSHA256': sha(self.root / screen),
               'editorV4': {key: observation[key] for key in collector.EDITOR_CORE_FIELDS},
               'editorObservation': copy.deepcopy(observation),
               'stageAX': ax('editor.stage', {'x': 9, 'y': 100, 'width': 384, 'height': 400}),
               'photoAXFrame': {'x': 9, 'y': 156, 'width': 384, 'height': 288},
               'photoNativeFrame': {'x': 29, 'y': 470, 'width': 1148, 'height': 860},
               'selectedToolAX': ax('editor.tool.adjust', {'x': 10, 'y': 700, 'width': 50, 'height': 40}, True),
               'undoAX': ax('editor.undo', {'x': 10, 'y': 60, 'width': 40, 'height': 40}),
               'redoAX': ax('editor.redo', {'x': 60, 'y': 60, 'width': 40, 'height': 40}),
               'stability': {'method': 'two consecutive real native photo-area RGBA8 pixel hashes',
                             'samples': samples, 'consecutiveEqualSamples': 2}}
        screens = {screen: {'sha256': row['screenshotSHA256']}}
        args = (self.root, row, name, screens, log, observation['assetID'], {'pixelWidth': 384, 'pixelHeight': 288}, (0, 0, 402, 874))
        result = collector.editor_checkpoint(*args)
        self.assertEqual(result[2], (29, 470, 1177, 1330))
        changed = image.copy()
        changed.putpixel((100, 500), (1, 2, 3))
        last = self.root / samples[-1]['file']
        changed.save(last, pnginfo=info)
        samples[-1]['screenshotSHA256'] = sha(last)
        with self.assertRaisesRegex(ValueError, 'Actual immutable consecutive native crops'):
            collector.editor_checkpoint(*args)

    def test_month_geometry_rejects_clipped_cells_or_forged_native_rect(self):
        def frame(x, y, width, height):
            return {'x': x, 'y': y, 'width': width, 'height': height}
        def ax(box):
            return {'exists': True, 'enabled': True, 'hittable': True, 'frame': box}
        rows = {}
        visible = []
        for index, (month, total, reviewed, role) in enumerate((('2026-11', 3, 1, 'partial'), ('2026-10', 2, 2, 'complete'), ('2026-09', 8, 0, 'untouched'))):
            y = 200 + index * 100
            row = {'month': month, 'title': 'UNIT TEST ' + month, 'total': total, 'reviewed': reviewed, 'later': 0}
            rows[month] = row
            visible.append({**row, 'role': role, 'visibleStatus': 'unit-test-status', 'actualAXText': 'unit-test-status',
                            'cellAX': ax(frame(10, y, 380, 70)), 'menuAX': ax(frame(350, y + 15, 40, 40)),
                            'cellNativeFrame': frame(30, 3 * y, 1140, 210), 'menuNativeFrame': frame(1050, 3 * (y + 15), 120, 120)})
        geometry = {'screenPixels': [1206, 2622], 'commonPhoneNativeVisibleRect': [0, 0, 1206, 2263],
                    'nativeVisibleYMax': 2263, 'completeCellsAndMenus': 3, 'scrollAttempts': 1,
                    'screenAXFrame': frame(0, 0, 402, 874), 'unobscuredViewport': frame(0, 150, 402, 550),
                    'nativeListViewport': frame(0, 100, 402, 600), 'rows': visible}
        collector.audit_month_geometry(geometry, rows)
        for kind in ('clipped-cell', 'forged-native-rectangle', 'wrong-order', 'unbounded-scroll'):
            with self.subTest(kind=kind):
                bad = copy.deepcopy(geometry)
                if kind == 'clipped-cell':
                    bad['rows'][0]['cellAX']['frame']['y'] = 50
                elif kind == 'forged-native-rectangle':
                    bad['rows'][0]['cellNativeFrame']['y'] += 1
                elif kind == 'wrong-order':
                    bad['rows'] = list(reversed(bad['rows']))
                else:
                    bad['scrollAttempts'] = 8
                with self.assertRaises(ValueError):
                    collector.audit_month_geometry(bad, rows)

    def test_missing_and_wrong_v4_proofs_fail_closed(self):
        for function in (collector.audit_month_progress, collector.audit_editor_pair):
            with self.assertRaises(ValueError):
                function(self.root, {}, {})
        for name, function, kind in (('month-progress-proof.json', collector.audit_month_progress, 'concept-a-v4-month-progress'),
                                      ('editor-pair-proof.json', collector.audit_editor_pair, 'concept-a-v4-editor-pair')):
            for value in ({'schema': 1, 'kind': kind, 'status': 'IN_PROGRESS'}, {'schema': 1, 'kind': kind, 'status': 'PASS'}):
                write_json(self.root / name, value)
                with self.assertRaises(ValueError):
                    function(self.root, {}, {})

    def test_source_hash_binding_rejects_wrong_hash_and_traversal(self):
        target = self.root / 'actual-test-bytes.txt'
        target.write_bytes(b'UNIT TEST ONLY')
        collector.validate_source_bindings(self.root, {'source_bindings': {target.name: sha(target)}}, [target.name])
        with self.assertRaises(ValueError):
            collector.validate_source_bindings(self.root, {'source_bindings': {target.name: '0' * 64}}, [target.name])
        for value in ('../x', '/absolute', 'sub/../actual-test-bytes.txt', './actual-test-bytes.txt', 'C:drive.txt'):
            with self.assertRaises(ValueError):
                collector.safe_file(self.root, value)

    def test_v4_qa_base_and_vault_retain_every_legacy_native_gate(self):
        source = (builder.REPO_ROOT / 'PhotoMaidUITests/AppStoreCaptureTests.swift').read_text(encoding='utf-8')
        def method(signature):
            start = source.index(signature)
            end = source.index('\n    }\n', start) + len('\n    }')
            return source[start:end]
        legacy_signature = '    func test07ConceptAStoreScreenshots() throws {'
        base_signature = '    private func captureConceptAV4BaseScreenshots() throws {'
        legacy, base = method(legacy_signature), method(base_signature)
        restored_base = base.replace(base_signature, legacy_signature, 1).replace(
            'try captureConceptAV4Vault(initial: initial)', 'try captureConceptAVault(initial: initial)', 1)
        self.assertEqual(restored_base, legacy)
        vault_signature = '    private func captureConceptAVault(initial: [String: Any]) throws {'
        new_signature = '    private func captureConceptAV4Vault(initial: [String: Any]) throws {'
        original_intro = ('        XCTAssertTrue(button("onb_next").waitForExistence(timeout: 20), "Fresh vault must be set up through its actual UI")\n'
                          '        tap(button("onb_next"))\n'
                          '        let fields = app.secureTextFields\n'
                          '        XCTAssertEqual(fields.count, 2)')
        restored_vault = method(new_signature).replace(new_signature, vault_signature, 1).replace(
            '        let fields = try conceptAV4AdvanceVaultIntro()', original_intro, 1)
        self.assertEqual(restored_vault, method(vault_signature))
        readiness = method('    private func conceptAV4AdvanceVaultIntro() throws -> XCUIElementQuery {')
        for required in ('for attempt in 0..<2', 'fields.count == 0', 'intro.exists',
                         'waitForExistence(timeout: 15)', 'fields.count == 2',
                         'conceptAV4Tap(next)', 'conceptAV4Write(proof', 'proof["status"] = "FAIL"'):
            self.assertIn(required, readiness)
        test = method('    func test08ConceptAV4StoreScreenshots() throws {')
        self.assertEqual(test.count('try captureConceptAV4BaseScreenshots()'), 1)
        self.assertNotIn('try test07ConceptAStoreScreenshots()', test)

    def test_feed_readiness_requires_actual_assigned_same_asset_poster_and_session(self):
        # UNIT CONTRACT ONLY; no native capture or readiness PASS is fabricated.
        asset = {'id': 'unit-asset', 'isVideo': False}
        observation = {'assetID': asset['id'], 'isVideo': False, 'isLoaded': True, 'isCommitting': False,
                       'previewState': 'ready', 'sessionPreviewReady': True, 'posterAssigned': True,
                       'loadState': 'ready', 'posterPixelWidth': 384, 'posterPixelHeight': 288,
                       'posterProviderByteCount': 384 * 288 * 4, 'posterPixelDataSHA256': 'a' * 64,
                       'source': 'FeedViewModel.posters[current] supplied as FeedMediaPage.cachedPoster',
                       'pixelHashFormat': 'SHA256 of assigned poster CGImage data-provider bytes; row padding included'}
        self.assertEqual(collector.validate_feed_observation({'feedV4': observation}, asset), observation)
        self.assertEqual(collector.validate_feed_checkpoint_observation(
            {'feedObservation': copy.deepcopy(observation)}, {'feedV4': observation}, asset), observation)
        video = {**observation, 'isVideo': True}
        self.assertEqual(collector.validate_feed_observation({'feedV4': video}, {**asset, 'isVideo': True}), video)
        for key, value in (('assetID', 'other'), ('isVideo', True), ('isVideo', 0), ('isLoaded', False),
                           ('isLoaded', 1), ('isCommitting', True), ('isCommitting', 0), ('previewState', 'loading'),
                           ('loadState', 'notReady'), ('sessionPreviewReady', False), ('posterAssigned', False),
                           ('posterPixelWidth', True), ('posterPixelHeight', 0), ('posterProviderByteCount', -1),
                           ('posterPixelDataSHA256', 'ABC'), ('source', 'guessed pixels'), ('pixelHashFormat', 'screenshot')):
            with self.subTest(key=key, value=value):
                bad = {**observation, key: value}
                with self.assertRaises(ValueError):
                    collector.validate_feed_observation({'feedV4': bad}, asset)
                with self.assertRaises(ValueError):
                    collector.validate_feed_checkpoint_observation({'feedObservation': bad}, {'feedV4': observation}, asset)
        changed = {**observation, 'posterPixelDataSHA256': 'b' * 64}
        with self.assertRaisesRegex(ValueError, 'exact actual successful feed publication'):
            collector.validate_feed_checkpoint_observation({'feedObservation': changed}, {'feedV4': observation}, asset)
        for key in observation:
            with self.subTest(missing=key):
                bad = dict(observation); bad.pop(key)
                with self.assertRaises(ValueError):
                    collector.validate_feed_observation({'feedV4': bad}, asset)

    def test_feed_observer_is_qa_only_registered_after_real_load_and_never_sets_ready(self):
        source = (builder.REPO_ROOT / 'PhotoMaid/Features/Feed/FeedViewModel.swift').read_text(encoding='utf-8')
        start = source.index('    // Read-only C4 evidence.')
        end = source.index('#endif', start)
        observer = source[start:end]
        self.assertIn('private static weak var storeCaptureV4Model: FeedViewModel?', observer)
        self.assertIn('model.app.feed?.id == model.request.id else { return [:] }', observer)
        self.assertIn('model.session.isPreviewReady(ref)', observer)
        self.assertIn('let poster = model.posters[ref]', observer)
        self.assertIn('SHA256.hash(data: data as Data)', observer)
        for forbidden in ('markPreviewReady(', 'previewResult(', 'PHAssetChangeRequest', 'model.posters[ref] =', 'model.previews[ref] ='):
            self.assertNotIn(forbidden, observer)
        init = source[source.index('    init(request: FeedRequest, app: AppModel) {'):source.index('    #if DEBUG')]
        self.assertNotIn('storeCaptureV4Model', init)
        load = source[source.index('    func load() async {'):source.index('    nonisolated static func matches(')]
        self.assertIn('if Self.storeCaptureV4Enabled, !Task.isCancelled, app.feed?.id == request.id {', load)
        self.assertLess(load.index('isLoaded = true'), load.index('Self.storeCaptureV4Model = self'))
        self.assertEqual(source.count('Self.storeCaptureV4Model = self'), 1)
        test = (builder.REPO_ROOT / 'PhotoMaidUITests/AppStoreCaptureTests.swift').read_text(encoding='utf-8')
        keep = test[test.index('    private func conceptAV4Keep('):test.index('    private func conceptAV4MonthGeometry(')]
        self.assertNotIn('self.e("feed.media").exists', keep)
        for required in ('state["feedV4"]', 'media["assetID"]', 'media["sessionPreviewReady"]', 'media["posterPixelDataSHA256"]',
                         'self.e("feed.stage").value as? String == metadata', '!self.e("feed.preview.loading").exists',
                         '!self.e("feed.preview.failed").exists', 'e("feed.stage").swipeUp()', '"feedObservation"'):
            self.assertIn(required, keep)

    def test_requested_recipe_is_not_published_pixel_evidence(self):
        control = editor_metadata_control()
        self.assertEqual(collector.validate_editor_observation({'editorV4': control}, control['assetID']), control)
        for key, value in (('publishedRecipeHash', 'd' * 64), ('publishedRenderGeneration', 2), ('previewAssigned', False),
                           ('publicationMatchesRequest', False), ('originalReady', False), ('renderGeneration', True),
                           ('rendering', True), ('previewRendering', True), ('dirty', True), ('comparing', True),
                           ('publishedPreviewPixelSHA256', None), ('loadState', 'notReady'), ('assetID', 'other-asset')):
            with self.subTest(key=key):
                data = copy.deepcopy(control)
                data[key] = value
                with self.assertRaises(ValueError):
                    collector.validate_editor_observation({'editorV4': data}, control['assetID'])

    def test_neutral_render_baseline_keeps_raw_original_separate(self):
        data = editor_pair_publication_control()
        before = data['before']
        self.assertNotEqual(before['sourceOriginalPixelSHA256'], before['publishedPreviewPixelSHA256'])
        result = collector.validate_editor_pair_publications(data)
        self.assertEqual(result, tuple(data[key] for key in ('before', 'after', 'undo', 'redo')))
        # An actual neutral graph MAY be byte-equal to raw, but this is not required.
        for row in data.values():
            row['sourceOriginalPixelSHA256'] = before['publishedPreviewPixelSHA256']
        collector.validate_editor_pair_publications(data)

    def test_neutral_pair_rejects_transient_raw_assignment_and_zero_generation(self):
        for label in ('before', 'undo'):
            for kind in ('originalAssignment', 'zero-generation'):
                data = editor_pair_publication_control()
                if kind == 'originalAssignment':
                    data[label]['publicationOrigin'] = 'originalAssignment'
                else:
                    data[label]['renderGeneration'] = data[label]['publishedRenderGeneration'] = 0
                with self.subTest(label=label, kind=kind), self.assertRaises(ValueError):
                    collector.validate_editor_pair_publications(data)

    def test_editor_pair_rejects_changed_raw_source_asset_or_dimensions(self):
        for key, value in (('sourceOriginalPixelSHA256', 'f' * 64), ('sourceOriginalPixelWidth', 385),
                           ('sourceOriginalPixelHeight', 289), ('assetID', 'other-unit-asset')):
            for label in ('filterSelection', 'after', 'undo', 'redo'):
                data = editor_pair_publication_control()
                data[label][key] = value
                with self.subTest(key=key, label=label), self.assertRaises(ValueError):
                    collector.validate_editor_pair_publications(data)

    def test_editor_pair_requires_exact_neutral_and_warm_undo_redo_restoration(self):
        for label in ('undo', 'redo', 'filterSelection'):
            for kind in ('pixel', 'recipe'):
                data = editor_pair_publication_control()
                if kind == 'pixel':
                    # Undo must restore the rendered Before, not its raw source.
                    data[label]['publishedPreviewPixelSHA256'] = data[label]['sourceOriginalPixelSHA256']
                else:
                    data[label]['requestedRecipeHash'] = data[label]['publishedRecipeHash'] = 'f' * 64
                with self.subTest(label=label, kind=kind), self.assertRaises(ValueError):
                    collector.validate_editor_pair_publications(data)
        data = editor_pair_publication_control()
        for label in ('filterSelection', 'after', 'redo'):
            data[label]['publishedPreviewPixelSHA256'] = data['before']['publishedPreviewPixelSHA256']
        with self.assertRaises(ValueError):
            collector.validate_editor_pair_publications(data)

    def test_editor_pair_rejects_stale_busy_or_wrong_neutral_publication(self):
        for key, value in (('publishedRenderGeneration', 2), ('previewAssigned', False), ('rendering', True),
                           ('errors', ['UNIT TEST ERROR']), ('publishedIsIdentity', False), ('publishedFilter', 'warm')):
            data = editor_pair_publication_control()
            data['before'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                collector.validate_editor_pair_publications(data)
        data = editor_pair_publication_control()
        data['undo']['renderGeneration'] = data['undo']['publishedRenderGeneration'] = data['after']['renderGeneration']
        with self.assertRaises(ValueError):
            collector.validate_editor_pair_publications(data)

    def test_native_editor_wait_binds_real_neutral_render_not_raw_hash_equality(self):
        source = (builder.REPO_ROOT / 'PhotoMaidUITests/AppStoreCaptureTests.swift').read_text(encoding='utf-8')
        start = source.index('    private func conceptAV4EditorReady(')
        end = source.index('    /// Canonical actual screenshot pixel buffer', start)
        ready = source[start:end]
        self.assertNotIn('original == preview', ready)
        self.assertNotIn('original != preview', ready)
        for required in ('editor["publicationOrigin"] as? String == "renderAssignment"',
                         'editor["previewAssigned"] as? Bool == true', 'editor["publicationMatchesRequest"] as? Bool == true',
                         'editor["modelLoadState"] as? String == "ready"', 'errors.isEmpty', 'generation > 0',
                         'requested == published', 'editor["publishedRenderGeneration"] as? Int == generation',
                         'editor["publishedIsIdentity"] as? Bool == identity', 'pixelHash == nil || preview == pixelHash'):
            self.assertIn(required, ready)
        capture = source[source.index('    private func captureConceptAV4Editor('):source.index('    private func conceptASystemDeleteAlert(')]
        self.assertIn('conceptAV4JSON(filtered) == conceptAV4JSON(after)', capture)
        self.assertIn('after["publishedPreviewPixelSHA256"] as? String != before["publishedPreviewPixelSHA256"] as? String', capture)
        self.assertIn('pixelHash: before["publishedPreviewPixelSHA256"] as? String', capture)
        self.assertIn('pixelHash: after["publishedPreviewPixelSHA256"] as? String', capture)
        self.assertIn('undoScreen["photoPixelSHA256"] as? String == beforeScreen["photoPixelSHA256"] as? String', capture)
        self.assertIn('redoScreen["photoPixelSHA256"] as? String == afterScreen["photoPixelSHA256"] as? String', capture)

    def test_native_editor_core_projection_and_rich_readback_are_separate(self):
        rich = editor_metadata_control()
        rich.update(publishedFilter='warm', publishedFilterStrength=1, publishedIsIdentity=False, tool='adjust')
        expected = ('assetID', 'loadState', 'originalReady', 'previewReady', 'rendering', 'requestedRecipeHash',
                    'publishedRecipeHash', 'renderGeneration', 'publishedRenderGeneration', 'publishedFilter',
                    'publishedFilterStrength', 'publishedIsIdentity', 'sourceOriginalPixelSHA256', 'publishedPreviewPixelSHA256')
        self.assertEqual(collector.EDITOR_CORE_FIELDS, expected)
        core = {key: rich[key] for key in expected}
        row = {'editorV4': core, 'editorObservation': copy.deepcopy(rich)}
        self.assertEqual(collector.validate_editor_checkpoint_observation(row, {'editorV4': rich}, rich['assetID']), rich)
        for kind in ('full-in-core', 'missing-core', 'extra-core', 'core-hash', 'core-bool-as-int', 'missing-rich', 'rich-pixels', 'rich-diagnostics'):
            data = copy.deepcopy(row)
            if kind == 'full-in-core':
                data['editorV4'] = copy.deepcopy(rich)
            elif kind == 'missing-core':
                data['editorV4'].pop('publishedRecipeHash')
            elif kind == 'extra-core':
                data['editorV4']['tool'] = 'adjust'
            elif kind == 'core-hash':
                data['editorV4']['publishedPreviewPixelSHA256'] = 'f' * 64
            elif kind == 'core-bool-as-int':
                data['editorV4']['previewReady'] = 1
            elif kind == 'missing-rich':
                data.pop('editorObservation')
            elif kind == 'rich-pixels':
                data['editorObservation']['publishedPreviewPixelSHA256'] = 'f' * 64
            else:
                data['editorObservation']['tool'] = 'filter'
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                collector.validate_editor_checkpoint_observation(data, {'editorV4': rich}, rich['assetID'])

    def test_snapshot_must_be_real_ready_and_bound_to_log_in_order(self):
        state = {'fixtureMode': False, 'setupErrors': [], 'readReady': True, 'libraryLoaded': True, 'eventCount': 1}
        log = [{'checkpoint': 'unit-control', 'state': state}]
        self.assertEqual(collector.observed_snapshot(log, state), 0)
        with self.assertRaises(ValueError):
            collector.observed_snapshot(log, state, minimum=1)
        for key, value in (('fixtureMode', True), ('readReady', False), ('setupErrors', ['error'])):
            data = {**state, key: value}
            with self.assertRaises(ValueError):
                collector.observed_snapshot([{'checkpoint': 'unit-invalid', 'state': data}], data)

    def test_named_editor_cancel_occurrence_can_repeat_redo_state(self):
        # UNIT CONTROL ONLY: no native source/provenance acceptance is created.
        ready = {'fixtureMode': False, 'setupErrors': [], 'readReady': True, 'libraryLoaded': True}
        baseline, restored = {**ready, 'unitState': 'before'}, {**ready, 'unitState': 'restored'}
        name = 'v4-editor-save-options-cancelled'
        log = [{'checkpoint': 'unit-baseline', 'state': baseline},
               {'checkpoint': 'unit-redo-ready', 'state': copy.deepcopy(restored)},
               {'checkpoint': 'concept-a-v4-editor-redo-capture-readback', 'state': copy.deepcopy(restored)},
               {'checkpoint': name, 'state': copy.deepcopy(restored)}]
        self.assertEqual(collector.observed_snapshot(log, restored, minimum=1), 1)
        final = collector.observed_named_snapshot(log, restored, name, minimum=1, label='editor.afterState')
        self.assertEqual(final, 3)
        self.assertTrue(all(a < b for a, b in zip([0, 2, final], [2, final])))
        for kind in ('missing-cancel', 'reordered-cancel', 'wrong-state', 'unready-cancel'):
            rows, state = copy.deepcopy(log), copy.deepcopy(restored)
            if kind == 'missing-cancel':
                rows[-1]['checkpoint'] = 'unit-other'
            elif kind == 'reordered-cancel':
                rows.insert(1, rows.pop())
            elif kind == 'wrong-state':
                state['unitState'] = 'different'
            else:
                rows[-1]['state']['readReady'] = False
            redo_index = next(i for i, row in enumerate(rows) if row['checkpoint'] == 'concept-a-v4-editor-redo-capture-readback')
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                collector.observed_named_snapshot(rows, state, name, minimum=redo_index + 1, label='editor.afterState')

    def test_native_screen_header_hash_uniqueness_and_opacity(self):
        directory = self.root / 'screenshots'
        directory.mkdir()
        names = [f'concept-a-{name}.png' for name in collector.legacy.REQUIRED] + list(collector.NEW_SCREENS)
        info = PngImagePlugin.PngInfo()
        info.add_text('purpose', 'UNIT TEST RECTANGLE ONLY, NOT NATIVE CAPTURE')
        for index, name in enumerate(names):
            Image.new('RGB', (1206, 2622), (index, 17, 31)).save(directory / name, pnginfo=info)
        self.assertEqual(len(collector.validate_native_screens(self.root)), 20)
        # Plain rectangles cannot prove separate native captures. Even an exact
        # named pair must fail without the real independent editor/receipt audit.
        after = directory / 'concept-a-v4-editor-after.png'
        redo = directory / 'concept-a-v4-editor-redo.png'
        undo = directory / 'concept-a-v4-editor-undo.png'
        original_redo, original_undo = redo.read_bytes(), undo.read_bytes()
        redo.write_bytes(after.read_bytes())
        with self.assertRaisesRegex(ValueError, 'Missing/out-of-root evidence'):
            collector.validate_native_screens(self.root)
        undo.write_bytes(after.read_bytes())
        with self.assertRaisesRegex(ValueError, 'Unrelated required native screen'):
            collector.validate_native_screens(self.root)
        undo.write_bytes(original_undo)
        redo.write_bytes(original_redo)
        target = directory / collector.NEW_SCREENS[-1]
        target.write_bytes((directory / names[0]).read_bytes())
        with self.assertRaisesRegex(ValueError, 'Unrelated required native screen'):
            collector.validate_native_screens(self.root)
        Image.new('RGBA', (1206, 2622), (1, 2, 3, 1)).save(target, pnginfo=info)
        with self.assertRaisesRegex(ValueError, 'opaque native'):
            collector.validate_native_screens(self.root)
        Image.new('RGB', (100, 200), (1, 2, 3)).save(target, pnginfo=info)
        with self.assertRaisesRegex(ValueError, '1206x2622'):
            collector.validate_native_screens(self.root)

    def test_preservation_rejects_extra_event_asset_or_changed_unrelated_ledger(self):
        state = {'inventory': [{'id': 'a', 'filename': 'unit-a.jpg'}], 'decisions': [{'id': 'x', 'disposition': 'later', 'revision': 1, 'dueDay': '2026-11-18'}],
                 'basketIDs': [], 'eventCount': 1}
        collector.verify_preservation(state, copy.deepcopy(state), set())
        for kind in ('event', 'inventory', 'ledger'):
            after = copy.deepcopy(state)
            if kind == 'event':
                after['eventCount'] += 1
            elif kind == 'inventory':
                after['inventory'].append({'id': 'b', 'filename': 'unit-b.jpg'})
            else:
                after['decisions'][0]['dueDay'] = '2026-11-19'
            with self.assertRaises(ValueError):
                collector.verify_preservation(state, after, set())

    def test_real_unmodified_collector_cannot_pass_missing_native_evidence(self):
        original_sha = sha(Path(collector.legacy.__file__))
        canonical = self.root / 'capture_provenance.json'
        prior = b'{"purpose":"UNIT TEST prior artifact; preserve, do not accept as native"}\n'
        canonical.write_bytes(prior)
        report = collector.collect(self.root, self.root / 'absent-sources', self.root / 'absent-allowlist', self.root / 'absent-fixture')
        self.assertEqual(report['status'], 'FAIL')
        self.assertEqual(report['creative_revision'], 4)
        self.assertEqual(report['native_scene_policy'], collector.V4_SCENE_POLICY)
        self.assertNotEqual(report['native_scene_policy'], collector.legacy.V3_SCENE_POLICY)
        self.assertEqual(report['base_c14_provenance']['status'], 'FAIL')
        self.assertEqual(report['v4_audits']['month_progress']['status'], 'FAIL')
        self.assertEqual(report['v4_audits']['editor_pair']['status'], 'FAIL')
        self.assertEqual(report['exact_api_run_acceptance'], 'NOT RUN')
        self.assertEqual(report['native_visual_acceptance'], 'NOT RUN')
        base = report['base_c14_provenance']
        self.assertEqual(sha(self.root / base['file']), base['sha256'])
        saved_prior = self.root / base['previous_canonical']['file']
        self.assertEqual(saved_prior.read_bytes(), prior)
        self.assertEqual(original_sha, sha(Path(collector.legacy.__file__)))
        self.assertEqual(json.loads(canonical.read_text(encoding='utf-8'))['status'], 'FAIL')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path)
    args, unittest_args = parser.parse_known_args(argv)
    # Refuse accidental C-backed unit-test bulk writes on this Windows task.
    if os.name == 'nt' and not Path(tempfile.gettempdir()).drive.upper().startswith('F:'):
        parser.error('Set TEMP/TMP/TMPDIR=F:/HermesTemp before running the local tests')
    start = time.monotonic()
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = {'schema_version': 1, 'creative_revision': 4, 'local_tests': 'PASS' if result.wasSuccessful() else 'FAIL',
              'tests_run': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors), 'skipped': len(result.skipped),
              'duration_seconds': round(time.monotonic() - start, 3), 'temporary_root': tempfile.gettempdir(),
              'native_capture': 'NOT RUN', 'real_approved_stock_fixture': 'NOT RUN', 'real_video_encode_decode': 'NOT RUN',
              'api_readback': 'NOT RUN', 'visual_acceptance': 'NOT RUN',
              'scope': 'Synthetic unit-test files only; no downloads, installation, CI, or native capture',
              'failure_details': [{'test': str(test), 'traceback': detail} for test, detail in result.failures + result.errors]}
    if args.report:
        allowed = Path('F:/HermesOutput/GaleriQ/concept-a-en-v4').resolve()
        target = args.report.resolve()
        if os.name == 'nt' and (allowed not in target.parents or not any(part in ('qa', 'tools') for part in target.relative_to(allowed).parts[:-1])):
            parser.error('Local test reports must remain under the v4 output tools/qa subtree')
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('x', encoding='utf-8', newline='\n') as stream:
            stream.write(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'failure_details'}))
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    raise SystemExit(main())
