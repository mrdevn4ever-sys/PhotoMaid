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
            'publicationOrigin': 'renderAssignment',
            'pixelHashFormat': 'SHA256 of assigned RGBA8 CGImage packed pixel rows; stride padding excluded'}


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
        row = {'file': screen, 'screenshotSHA256': sha(self.root / screen), 'editorV4': observation,
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

    def test_native_screen_header_hash_uniqueness_and_opacity(self):
        directory = self.root / 'screenshots'
        directory.mkdir()
        names = [f'concept-a-{name}.png' for name in collector.legacy.REQUIRED] + list(collector.NEW_SCREENS)
        info = PngImagePlugin.PngInfo()
        info.add_text('purpose', 'UNIT TEST RECTANGLE ONLY, NOT NATIVE CAPTURE')
        for index, name in enumerate(names):
            Image.new('RGB', (1206, 2622), (index, 17, 31)).save(directory / name, pnginfo=info)
        self.assertEqual(len(collector.validate_native_screens(self.root)), 20)
        target = directory / collector.NEW_SCREENS[-1]
        target.write_bytes((directory / names[0]).read_bytes())
        with self.assertRaisesRegex(ValueError, 'unique file hash'):
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
