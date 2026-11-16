#!/usr/bin/env python3
"""Collect v4 native evidence without weakening or editing the C14/v3 collector.

Run the legacy collector with the real environment and built Info.plist first,
preserve its exact report, then independently enforce v4 inputs and proofs. A
legacy PASS alone never establishes v4 PASS. This program does not run XCTest.

Native proof contract: the actual test08 emitter's schema=1, explicit v4 kind,
status=PASS, observed snapshots/action receipts and literal screenshotSHA256.
Month before/after/actions must exist in concept-a-evidence.json and independently
prove three genuine Keeps, preserved inventory/ledger and complete native rows.
Editor checkpoints must bind real publication pixels/generations, screenshot
stability samples, matching Original/Warm/Undo/Redo photo geometry and the actual
untouched copy-default sheet, cancelled without exporting or changing inventory.
Unsupported/missing proof fields FAIL; they are never inferred from v3 captures.

--run-readback optionally validates the saved exact-attempt API response and its
jobs (attempt_readback + attempt_jobs_readback). It cannot be green while its own
CI job is running, so absence is explicitly NOT RUN, not API/final acceptance.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime
from fractions import Fraction
import hashlib
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import subprocess
import sys

from PIL import Image, ImageOps

import collect_concept_a_provenance as legacy
import build_concept_a_v4_fixture as builder

V4_SCENE_POLICY = 'v4-mixed-approved-originals-real-month-progress-published-editor-pair'
NEW_SCREENS = (
    'concept-a-v4-months.png', 'concept-a-v4-editor-before.png', 'concept-a-v4-editor-after.png',
    'concept-a-v4-editor-undo.png', 'concept-a-v4-editor-redo.png', 'concept-a-v4-editor-copy-default.png',
)
OPTIONAL_WARM = 'concept-a-v4-editor-filter-selected.png'
MEDIA_POLICY = 'approved-stock-photos-and-videos-no-app-screenshots'
BRANCH = 'hermes/store-concept-a-en'
DEFAULT_CAPTURE_TEST = 'AppStoreCaptureTests/test08ConceptAV4StoreScreenshots'


def need(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def hash_literal(value, label):
    need(type(value) is str and re.fullmatch(r'[0-9a-f]{64}', value) is not None,
         label + ': literal lowercase SHA-256 required')
    return value


def positive_string(value, label):
    need(type(value) is str and re.fullmatch(r'[1-9][0-9]*', value) is not None,
         label + ': canonical positive string required; no normalization')
    return value


def positive_api_integer(value, label):
    need(type(value) is int and value > 0, label + ': actual positive API integer required')
    return value


def validate_run_pins(provenance):
    need(type(provenance.get('commit')) is str and re.fullmatch(r'[0-9a-f]{40}', provenance['commit']) is not None,
         'Malformed literal native capture commit')
    run = positive_string(provenance.get('workflow_run'), 'workflow_run')
    attempt = positive_string(provenance.get('run_attempt'), 'run_attempt')
    need(provenance.get('branch') == BRANCH and provenance.get('fresh_capture') is True
         and provenance.get('locale') == 'en-US' and provenance.get('app_language') == 'en',
         'Exact native branch/fresh/en-US header required')
    url = provenance.get('workflow_url')
    match = re.fullmatch(r'https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/actions/runs/([1-9][0-9]*)(?:/attempts/([1-9][0-9]*))?', url) if type(url) is str else None
    need(match is not None and match.group(2) == run and (match.group(3) is None or match.group(3) == attempt),
         'Native workflow URL does not match literal run/attempt pins')
    return {'workflow_run': run, 'run_attempt': attempt, 'commit': provenance['commit'],
            'branch': BRANCH, 'repository': match.group(1)}


def validate_exact_attempt_readback(readback, provenance):
    """Never turn a latest-run success, float, bool, '+1' or '01' into an attempt."""
    pins = validate_run_pins(provenance)
    actual, jobs = readback.get('attempt_readback'), readback.get('attempt_jobs_readback')
    need(type(actual) is dict and type(jobs) is dict, 'Saved exact-attempt response AND attempt-jobs response required')
    run = positive_api_integer(actual.get('id'), 'attempt_readback.id')
    attempt = positive_api_integer(actual.get('run_attempt'), 'attempt_readback.run_attempt')
    need(str(run) == pins['workflow_run'] and str(attempt) == pins['run_attempt'], 'Exact API run/attempt pin mismatch')
    if 'run_attempt' in readback:
        need(positive_api_integer(readback['run_attempt'], 'readback.run_attempt') == attempt, 'Wrapper attempt pin mismatch')
    need(actual.get('head_sha') == pins['commit'] and actual.get('head_branch') == BRANCH
         and actual.get('event') == 'workflow_dispatch' and actual.get('status') == 'completed'
         and actual.get('conclusion') == 'success', 'Exact capture attempt is not completed/success on the pinned SHA/branch/event')
    web = f'https://github.com/{pins["repository"]}/actions/runs/{pins["workflow_run"]}'
    api = f'https://api.github.com/repos/{pins["repository"]}/actions/runs/{pins["workflow_run"]}'
    need(actual.get('html_url') in (web, web + '/attempts/' + pins['run_attempt'])
         and actual.get('url') in (api, api + '/attempts/' + pins['run_attempt'])
         and actual.get('jobs_url') == api + '/attempts/' + pins['run_attempt'] + '/jobs',
         'Saved API URLs do not bind the exact repository/run/attempt resource')
    if 'request_url' in readback:
        need(readback['request_url'] == api + '/attempts/' + pins['run_attempt'], 'Readback was requested from another endpoint')
    rows = jobs.get('jobs')
    need(type(rows) is list and bool(rows) and type(jobs.get('total_count')) is int
         and jobs['total_count'] == len(rows), 'Attempt job listing must be nonempty and complete, not paginated/partial')
    ids = []
    for job in rows:
        need(type(job) is dict, 'Attempt job must be an object')
        ids.append(positive_api_integer(job.get('id'), 'job.id'))
        need(positive_api_integer(job.get('run_id'), 'job.run_id') == run
             and positive_api_integer(job.get('run_attempt'), 'job.run_attempt') == attempt
             and job.get('head_sha') == pins['commit'] and job.get('head_branch') == BRANCH
             and job.get('status') == 'completed' and job.get('conclusion') == 'success',
             'Attempt job is skipped/failed/incomplete or bound to another run/SHA/attempt')
    need(len(set(ids)) == len(ids), 'Duplicate jobs in exact-attempt readback')
    latest = readback.get('run')
    if latest is not None:
        need(type(latest) is dict and positive_api_integer(latest.get('databaseId'), 'run.databaseId') == run
             and positive_api_integer(latest.get('runAttempt'), 'run.runAttempt') == attempt
             and latest.get('headSha') == pins['commit'] and latest.get('headBranch') == BRANCH
             and latest.get('event') == 'workflow_dispatch' and latest.get('status') == 'completed'
             and latest.get('conclusion') == 'success' and latest.get('url') in (web, web + '/attempts/' + pins['run_attempt']),
             'Latest-run wrapper disagrees with the exact-attempt response')
    return {**pins, 'status': 'PASS', 'actual_api_run_attempt': attempt, 'complete_jobs': len(rows)}


def validate_capture_summary(summary, tests, capture_test=DEFAULT_CAPTURE_TEST):
    need(type(capture_test) is str and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*/test08[A-Za-z0-9_]+', capture_test) is not None,
         'Explicit test08 native capture selector required')
    need(summary.get('result') == 'Passed'
         and all(type(summary.get(key)) is int and summary[key] == expected
                 for key, expected in (('passedTests', 1), ('failedTests', 0), ('skippedTests', 0), ('totalTestCount', 1))),
         'Exactly one passed native capture test, total one, with zero failures/skips is required')
    need(type(summary.get('expectedFailures', 0)) is int and summary.get('expectedFailures', 0) == 0
         and summary.get('testFailures', []) == [], 'Expected or recorded test failures are not accepted')
    configurations = summary.get('devicesAndConfigurations')
    need(type(configurations) is list and len(configurations) == 1, 'One actual native device/configuration required')
    configuration = configurations[0]
    need(type(configuration) is dict and all(type(configuration.get(key)) is int and configuration[key] == expected
         for key, expected in (('passedTests', 1), ('failedTests', 0), ('skippedTests', 0))), 'Per-device native test counters disagree')
    need(configuration.get('device', {}).get('modelName') == 'iPhone 17 Pro'
         and configuration.get('device', {}).get('platform') == 'iOS Simulator', 'Unexpected actual native test device')
    cases = []
    def walk(nodes):
        need(type(nodes) is list, 'Malformed actual XCTest node tree')
        for node in nodes:
            need(type(node) is dict, 'Malformed actual XCTest node')
            if 'result' in node:
                need(node['result'] == 'Passed', 'An actual XCTest node failed or skipped')
            if node.get('nodeType') == 'Test Case':
                cases.append(node)
            if 'children' in node:
                walk(node['children'])
    walk(tests.get('testNodes'))
    need(len(cases) == 1 and cases[0].get('nodeIdentifier') == capture_test + '()'
         and cases[0].get('name') == capture_test.split('/')[1] + '()'
         and cases[0].get('result') == 'Passed', 'Actual XCTest tree must identify the one new test08, not a historical test or summary-only PASS')
    return {'status': 'PASS', 'test': capture_test, 'passed': 1, 'failed': 0, 'skipped': 0}


def expected_fixture_roles():
    # Independently stated compatibility contract, not read from builder output.
    pretty = (5, 10, 1, 4, 6, 7, 9, 13, 28, 29, 31, 33, 35, 36, 5, 10, 1, 4, 6, 7, 13, 35, 5, 7)
    return {'CA_01_clutter_blur.jpg': 5, 'CA_02_clutter_shake.jpg': 10, 'CA_03_clutter_dark.jpg': 5,
            'CA_10_duplicate_a.jpg': 38, 'CA_11_duplicate_b.jpg': 38,
            **{f'CA_20_series_{n:02d}.jpg': 36 for n in range(1, 7)},
            **{f'CA_30_pretty_{n:02d}.jpg': role for n, role in enumerate(pretty, 1)},
            'CA_40_large_01.mp4': 13, 'CA_40_large_02.mp4': 35}


def validate_fixture_metadata(fixture, registry, allowlist, manifest_sha, allowlist_sha):
    roles = builder.validate_registry(registry, allowlist)
    need(fixture.get('status') == 'PASS' and type(fixture.get('creative_revision')) is int and fixture['creative_revision'] == 4
         and type(fixture.get('schema_version')) is int and fixture['schema_version'] == 2
         and fixture.get('sample_media_policy') == MEDIA_POLICY, 'A complete separate v4 stock-only fixture is required')
    need(all(type(fixture.get(key)) is int and fixture[key] == expected
             for key, expected in (('images', 35), ('videos', 2), ('source_library_verified', 15))), 'v4 fixture must declare exactly 35+2 assets from 15 verified originals')
    need(fixture.get('source_manifest_sha256') == hash_literal(manifest_sha, 'source registry hash'), 'Stale/wrong source registry hash')
    gate = fixture.get('visual_source_gate', {})
    need(type(gate) is dict and gate.get('status') == 'PASS' and gate.get('allowlist_status') == 'PASS_SELECTED_SUBSET_ONLY'
         and gate.get('all_used_sources_approved') is True and type(gate.get('approved_original_count')) is int
         and gate['approved_original_count'] == 15 and gate.get('allowlist_sha256') == hash_literal(allowlist_sha, 'allowlist hash'),
         'Fixture visual approval must bind the current exact 15-original allowlist')
    rows = fixture.get('records')
    need(type(rows) is list and len(rows) == 37 and all(type(row) is dict for row in rows), 'Exactly 37 actual v4 fixture records required')
    expected, found, hashes = expected_fixture_roles(), {}, {}
    for row in rows:
        name = row.get('file')
        need(type(name) is str and name in expected and name not in found, 'Unexpected/duplicate fixture filename: ' + repr(name))
        role = row.get('capture_role')
        need(type(role) is int and role == expected[name], name + ': wrong explicit capture_role')
        original = roles[role]
        for actual, source_key in (('source', 'file'), ('source_sha256', 'sha256'), ('source_url', 'source'),
                                   ('author', 'author'), ('license', 'license'), ('license_url', 'license_url'),
                                   ('source_width', 'width'), ('source_height', 'height')):
            need(row.get(actual) == original[source_key] and type(row.get(actual)) is type(original[source_key]),
                 name + ': missing/wrong source field ' + actual)
        need(type(row.get('bytes')) is int and row['bytes'] > 0 and type(row.get('adaptation')) is str and bool(row['adaptation'].strip()),
             name + ': real byte measurement and adaptation required')
        sha = hash_literal(row.get('sha256'), name + '.sha256')
        size = row.get('size')
        need(type(size) is list and len(size) == 2 and all(type(n) is int and n > 0 for n in size), name + ': actual dimensions required')
        media_type = 'video' if name.endswith('.mp4') else 'image'
        need(row.get('media_type') == media_type, name + ': wrong actual media type')
        if media_type == 'video':
            video = row.get('video', {})
            need(type(video) is dict and row['bytes'] > 110_000_000 and size == [1920, 1080]
                 and type(video.get('width')) is int and video['width'] == 1920
                 and type(video.get('height')) is int and video['height'] == 1080
                 and video.get('codec') == 'h264' and video.get('full_decode') == 'PASS'
                 and type(video.get('audio_streams')) is int and video['audio_streams'] == 0
                 and type(video.get('duration')) in (float, int) and math.isfinite(video['duration']) and video['duration'] > 0,
                 name + ': genuinely large fully decoded silent H.264 video required')
        found[name] = row
        hashes.setdefault(sha, []).append(name)
    need(set(found) == set(expected), 'Exact 35+2 CA fixture filename set required')
    need(sorted(sorted(names) for names in hashes.values() if len(names) > 1)
         == [['CA_10_duplicate_a.jpg', 'CA_11_duplicate_b.jpg']], 'Only the real duplicate pair may share a file hash')
    need({row['source'] for row in rows} == {row['file'] for row in roles.values()}, 'All and only the 15 approved originals must be used')
    return found


def verify_fixture_files(fixture_root, fixture, rows, sources):
    fixture_root, sources = Path(fixture_root).resolve(), Path(sources).resolve()
    need(fixture_root.is_dir() and {p.name for p in fixture_root.iterdir()} == set(rows) | {'fixture-manifest.json'},
         'Actual fixture directory must contain exactly 37 CA files plus its manifest; no extra screenshot/padding/temp files')
    need(builder.load_json(fixture_root / 'fixture-manifest.json') == fixture, 'Prepared and captured fixture manifests disagree')
    ffmpeg, ffprobe = shutil.which('ffmpeg'), shutil.which('ffprobe')
    need(ffmpeg and ffprobe, 'Independent video byte/decode verification requires installed ffmpeg and ffprobe')
    for name, row in rows.items():
        path = fixture_root / name
        need(path.is_file() and not path.is_symlink() and path.resolve().parent == fixture_root
             and path.stat().st_size == row['bytes'] and digest(path) == row['sha256'], name + ': actual file hash/bytes mismatch')
        if row['media_type'] == 'image':
            with Image.open(path) as image, Image.open(sources / row['source']) as original:
                image.load()
                oriented = ImageOps.exif_transpose(original)
                need(image.format == 'JPEG' and list(image.size) == row['size']
                     and image.width <= oriented.width and image.height <= oriented.height, name + ': image dimensions/format/upscaling mismatch')
            if row['category'] in ('pretty', 'exact-duplicate'):
                need(row['sha256'] == row['source_sha256'], name + ': unchanged source bytes were not preserved')
        else:
            probe = json.loads(subprocess.check_output([ffprobe, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(path)], text=True))
            streams = probe.get('streams', [])
            need(len(streams) == 1 and streams[0].get('codec_type') == 'video', name + ': must contain exactly one silent stream')
            video = streams[0]
            need((video.get('codec_name'), video.get('width'), video.get('height'), video.get('pix_fmt')) == ('h264', 1920, 1080, 'yuv420p')
                 and Fraction(video.get('avg_frame_rate', '0')) == 24
                 and int(probe['format']['size']) == row['bytes']
                 and abs(float(probe['format']['duration']) - row['video']['duration']) < 0.001, name + ': independent video probe disagrees')
            subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-nostdin', '-xerror', '-i', str(path), '-f', 'null', '-'],
                           check=True, timeout=180, stdout=subprocess.DEVNULL)
    return {'status': 'PASS', 'actual_files': len(rows), 'images': 35, 'videos': 2, 'independent_video_full_decode': 'PASS'}


def safe_file(root, name):
    need(type(name) is str and name and '\\' not in name and ':' not in name
         and not any(ord(char) < 32 for char in name), 'Unsafe evidence path')
    relative = PurePosixPath(name)
    need(not relative.is_absolute() and relative.as_posix() == name and all(part not in ('.', '..') for part in relative.parts),
         'Noncanonical/traversing evidence path')
    root = Path(root).resolve()
    path = root.joinpath(*relative.parts)
    need(path.is_file() and not path.is_symlink() and root in path.resolve().parents, 'Missing/out-of-root evidence: ' + name)
    return path


def validate_native_screens(root):
    required = [f'concept-a-{name}.png' for name in legacy.REQUIRED] + list(NEW_SCREENS)
    if (Path(root) / 'screenshots' / OPTIONAL_WARM).is_file():
        required.append(OPTIONAL_WARM)
    rows = []
    for name in required:
        path = safe_file(root, 'screenshots/' + name)
        with path.open('rb') as stream:
            header = stream.read(33)
        need(len(header) == 33 and header[:8] == b'\x89PNG\r\n\x1a\n' and header[12:16] == b'IHDR', name + ': actual PNG header required')
        width, height, depth, color = struct.unpack('>IIBB', header[16:26])
        row = legacy.image_record(path, Path(root))
        need((width, height, depth) == (1206, 2622, 8) and color in (2, 6)
             and row['mode'] in ('RGB', 'RGBA') and row['opaque'] is True, name + ': 8-bit opaque native RGB/RGBA 1206x2622 required')
        rows.append(row)
    need(len({row['sha256'] for row in rows}) == len(rows), 'Every legacy and new required native screen must have a unique file hash')
    return {row['file']: row for row in rows}


def validate_source_bindings(root, proof, required):
    bindings = proof.get('source_bindings')
    need(type(bindings) is dict and set(required).issubset(bindings), 'Native proof is missing exact screenshot hash bindings')
    for name, sha in bindings.items():
        need(digest(safe_file(root, name)) == hash_literal(sha, name), 'Native proof source hash mismatch: ' + name)
    return bindings


def load_evidence(root):
    path = safe_file(root, 'concept-a-evidence.json')
    value = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=builder._unique_object,
                       parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Nonfinite observation JSON: ' + value)))
    need(type(value) is list and bool(value), 'Actual read-only native observation log is required')
    for row in value:
        need(type(row) is dict and type(row.get('checkpoint')) is str and row['checkpoint']
             and type(row.get('state')) is dict, 'Malformed actual native checkpoint')
    return value


def checkpoint(log, name):
    need(type(name) is str and bool(name), 'Explicit observed checkpoint name required')
    hits = [(index, row['state']) for index, row in enumerate(log) if row['checkpoint'] == name]
    need(bool(hits), 'Missing actual read-only checkpoint: ' + name)
    index, state = hits[-1]  # bounded native polling can emit repeated checkpoint names
    need(state.get('fixtureMode') is False and state.get('setupErrors') == []
         and state.get('readReady') is True and state.get('libraryLoaded') is True,
         'Actual native checkpoint is unready, synthetic, or has setup errors: ' + name)
    return index, state


def proof_header(proof, kind):
    need(type(proof.get('schema')) is int and proof['schema'] == 1
         and proof.get('kind') == kind and proof.get('status') == 'PASS',
         'Unsupported/incomplete actual test08 proof schema: ' + kind)


def month_rows(state):
    rows = state.get('months')
    need(type(rows) is list and len(rows) >= 3, 'Real observed month groups are required')
    found = {}
    for row in rows:
        need(type(row) is dict and type(row.get('month')) is str and row['month'] not in found
             and re.fullmatch(r'[0-9]{4}-(?:0[1-9]|1[0-2])', row['month']) is not None
             and all(type(row.get(key)) is int for key in ('total', 'reviewed', 'later'))
             and row['total'] > 0 and 0 <= row['reviewed'] <= row['total'] and 0 <= row['later'] <= row['total'],
             'Malformed/duplicate actual month progress row')
        found[row['month']] = row
    return found


def decision_map(state):
    rows = state.get('decisions')
    need(type(rows) is list and all(type(row) is dict and type(row.get('id')) is str and row['id'] for row in rows), 'Actual observed decision ledger required')
    result = {row['id']: row for row in rows}
    need(len(result) == len(rows), 'Duplicate actual decision ledger IDs')
    return result


def inventory_map(rows):
    need(type(rows) is list and all(type(row) is dict and type(row.get('id')) is str and row['id'] for row in rows), 'Actual PhotoKit inventory rows required')
    result = {row['id']: row for row in rows}
    need(len(result) == len(rows) and len({row.get('filename') for row in rows}) == len(rows), 'Duplicate actual PhotoKit inventory IDs/filenames')
    return result


def library_by_id(library):
    found = inventory_map(library.get('assets'))
    need(len(found) == 37 and all(type(row.get('isVideo')) is bool and row.get('isScreenshot') is False for row in found.values()),
         'Actual initial 37-resource screenshot-free PhotoKit library required')
    need(all(type(library.get(key)) is int and library[key] == expected for key, expected in
             (('count', 37), ('photoCount', 35), ('videoCount', 2)))
         and sum(row['isVideo'] for row in found.values()) == 2,
         'Actual initial library counters/types must be exactly 35 photos and two videos')
    return found


def observed_snapshot(log, state, *, minimum=0, label='snapshot'):
    need(type(state) is dict and state.get('fixtureMode') is False and state.get('setupErrors') == []
         and state.get('readReady') is True and state.get('libraryLoaded') is True,
         label + ': real ready, nonsynthetic native snapshot required')
    matches = [index for index, row in enumerate(log) if index >= minimum and row['state'] == state]
    need(bool(matches), label + ': snapshot is not present in the actual native observation log in order')
    return matches[0]


def rect(value, label):
    need(type(value) is dict and set(value) == {'x', 'y', 'width', 'height'}
         and all(type(value[key]) in (float, int) and math.isfinite(value[key]) for key in value)
         and value['width'] > 0 and value['height'] > 0, label + ': finite nonempty observed rectangle required')
    return (value['x'], value['y'], value['x'] + value['width'], value['y'] + value['height'])


def contains(outer, inner):
    return outer[0] <= inner[0] < inner[2] <= outer[2] and outer[1] <= inner[1] < inner[3] <= outer[3]


def validate_ax(value, label, *, selected=None):
    need(type(value) is dict and value.get('exists') is True, label + ': actual existing AX control required')
    rect(value.get('frame'), label + '.frame')
    need(type(value.get('enabled')) is bool and type(value.get('hittable')) is bool, label + ': observed AX enabled/hittable state required')
    if selected is not None:
        need(value.get('selected') is selected, label + ': native selected state disagrees')
    return value


def validate_action(value, label, *, kind='tap'):
    need(type(value) is dict and value.get('action') == kind
         and all(type(value.get(key)) in (int, float) and math.isfinite(value[key]) and value[key] > 0 for key in ('started', 'finished'))
         and value['started'] <= value['finished'], label + ': real ordered native action timestamps required')
    target = validate_ax(value.get('targetAX'), label + '.targetAX')
    need(target['enabled'] is True and target['hittable'] is True, label + ': native tap target must actually be enabled/hittable')
    return target


def screenshot_binding(root, row, expected, screens=None):
    need(type(row) is dict and row.get('file') == expected, 'Wrong actual screenshot filename: ' + expected)
    sha = hash_literal(row.get('screenshotSHA256'), expected)
    path = safe_file(root, expected)
    need(digest(path) == sha, 'Actual native screenshot SHA-256 mismatch: ' + expected)
    metadata = legacy.image_record(path, Path(root))
    need((metadata['width'], metadata['height'], metadata['opaque']) == (1206, 2622, True)
         and metadata['mode'] in ('RGB', 'RGBA'), 'Actual native screenshot dimensions/opacity mismatch: ' + expected)
    if screens is not None:
        need(expected in screens and screens[expected]['sha256'] == sha, 'Proof does not bind an independently inventoried required source')
    return sha


def verify_preservation(before, after, kept_ids):
    need(inventory_map(before.get('inventory')) == inventory_map(after.get('inventory')), 'Actual PhotoKit inventory changed during v4 actions')
    need(type(before.get('basketIDs')) is list and type(after.get('basketIDs')) is list
         and sorted(before['basketIDs']) == sorted(after['basketIDs']), 'Real trash selections changed during v4 actions')
    old, new = decision_map(before), decision_map(after)
    need({key: value for key, value in old.items() if key not in kept_ids}
         == {key: value for key, value in new.items() if key not in kept_ids}, 'Unrelated decision/revision/due date changed')
    need(type(before.get('eventCount')) is int and type(after.get('eventCount')) is int
         and after['eventCount'] == before['eventCount'] + len(kept_ids), 'One and only one real ledger event per additional Keep required')
    for asset_id in kept_ids:
        need(new.get(asset_id, {}).get('disposition') == 'kept', 'Additional month Keep did not persist')


def audit_month_geometry(geometry, rows):
    need(type(geometry) is dict and geometry.get('screenPixels') == [1206, 2622]
         and geometry.get('commonPhoneNativeVisibleRect') == [0, 0, 1206, 2263]
         and type(geometry.get('nativeVisibleYMax')) is int and geometry['nativeVisibleYMax'] == 2263
         and type(geometry.get('completeCellsAndMenus')) is int and geometry['completeCellsAndMenus'] == 3
         and type(geometry.get('scrollAttempts')) is int and 0 <= geometry['scrollAttempts'] < 8,
         'Three complete real month cells/menus must fit inside the actual common phone crop after bounded native scrolling')
    screen = rect(geometry.get('screenAXFrame'), 'screenAXFrame')
    viewport = rect(geometry.get('unobscuredViewport'), 'unobscuredViewport')
    adjusted = rect(geometry.get('nativeListViewport'), 'nativeListViewport')
    need(contains(screen, viewport) and contains(adjusted, viewport), 'Unobscured native list viewport must respect adjusted insets/screen bounds')
    visible = geometry.get('rows')
    need(type(visible) is list and len(visible) == 3 and [row.get('role') for row in visible] == ['partial', 'complete', 'untouched']
         and [row.get('month') for row in visible] == ['2026-11', '2026-10', '2026-09'], 'Actual top-three complete status cells must be in their real month order')
    scale = 1206 / (screen[2] - screen[0])
    for row in visible:
        need(all(row.get(key) == rows[row['month']].get(key) for key in ('title', 'total', 'reviewed', 'later')), 'Visible month progress disagrees with the observed native rows')
        cell, menu = validate_ax(row.get('cellAX'), 'month.cellAX'), validate_ax(row.get('menuAX'), 'month.menuAX')
        need(menu['hittable'] is True and contains(viewport, rect(cell['frame'], 'cell.frame')) and contains(viewport, rect(menu['frame'], 'menu.frame')),
             'Whole actual month cell AND action menu must be inside the unobscured viewport')
        need(type(row.get('visibleStatus')) is str and row['visibleStatus'] and type(row.get('actualAXText')) is str
             and row['visibleStatus'] in row['actualAXText'], 'Actual visible native month status text required')
        for ax_key, native_key in (('cellAX', 'cellNativeFrame'), ('menuAX', 'menuNativeFrame')):
            actual = rect(row[native_key], native_key)
            ax = rect(row[ax_key]['frame'], ax_key + '.frame')
            expected = tuple((ax[i] - screen[i % 2]) * scale for i in range(4))
            need(all(abs(a - b) < 0.001 for a, b in zip(actual, expected)) and contains((0, 0, 1206, 2263), actual),
                 'Month native geometry must derive from complete actual AX bounds and fit above native Y=2263')
    return screen


def audit_month_progress(root, screens, library):
    proof = builder.load_json(safe_file(root, 'month-progress-proof.json'))
    proof_header(proof, 'concept-a-v4-month-progress')
    source = 'screenshots/concept-a-v4-months.png'
    need(proof.get('source') == source, 'Month proof must name its separate new native source')
    sha = screenshot_binding(root, {'file': source, 'screenshotSHA256': proof.get('screenshotSHA256')}, source, screens)
    log, initial = load_evidence(root), library_by_id(library)
    need(inventory_map(proof.get('initialInventory')) == initial, 'Month proof must retain the exact actual initial 37-resource library')
    before, after = proof.get('before'), proof.get('after')
    start = observed_snapshot(log, before, label='months.before')
    finish = observed_snapshot(log, after, minimum=start + 1, label='months.after')
    need(after.get('monthsTourSeen') is True, 'Native month tour must be dismissed')
    removed = {key for key, row in initial.items() if row.get('filename') in {f'CA_30_pretty_{n:02d}.jpg' for n in range(1, 6)}}
    need(set(inventory_map(before.get('inventory'))) == set(initial) - removed, 'Only the original scenario five genuine vault removals may precede v4')
    old, new = month_rows(before), month_rows(after)
    need(set(old) == set(new) and all(old[key]['total'] == new[key]['total'] for key in old), 'Native month groups/totals changed during extra Keeps')
    expected = {'2026-10': (2, 2), '2026-11': (3, 1), '2026-09': (8, 0)}
    for key, (total, reviewed) in expected.items():
        need(key in old and old[key]['total'] == total and old[key]['reviewed'] == old[key]['later'] == 0
             and new[key]['total'] == total and new[key]['reviewed'] == reviewed and new[key]['later'] == 0,
             'Genuine before/after month counts must prove complete October, partial November, untouched September')
    need(all(old[key] == new[key] for key in old if key not in ('2026-10', '2026-11')), 'Every unrelated actual month must remain identical')
    actions = proof.get('actions')
    files = ['CA_30_pretty_14.jpg', 'CA_02_clutter_shake.jpg', 'CA_40_large_02.mp4']
    need(type(actions) is list and len(actions) == 3 and [action.get('filename') for action in actions] == files
         and proof.get('actionFiles') == files, 'Exactly the three planned genuine native month Keeps are required')
    used, last, bindings, cumulative = [], start, {source: sha}, set()
    for index, action in enumerate(actions, 1):
        asset_id = action.get('assetID')
        need(action.get('action') == 'feed.stage.swipeUp' and type(asset_id) is str and asset_id in initial
             and action.get('asset') == initial[asset_id] and action['filename'] == initial[asset_id]['filename']
             and type(action.get('identityMatchCount')) is int and action['identityMatchCount'] == 1,
             'Native month swipe must identify exactly one real initial asset, not a guessed photo')
        stage = validate_ax(action.get('stageAX'), 'month.stageAX')
        need(stage.get('identifier') == 'feed.stage' and stage.get('value') == initial[asset_id].get('accessibilityValue'), 'Native stage identity does not match the actual PhotoKit resource')
        need(all(type(action.get(key)) in (int, float) and math.isfinite(action[key]) and action[key] > 0 for key in ('started', 'finished'))
             and action['started'] <= action['finished'], 'Native month swipe timing is absent/malformed')
        action_start = observed_snapshot(log, action.get('before'), minimum=last, label='Keep.before')
        action_end = observed_snapshot(log, action.get('after'), minimum=action_start + 1, label='Keep.after')
        need(action_end <= finish, 'Native month Keep occurred outside its actual proof interval')
        previous = decision_map(action['before']).get(asset_id)
        committed = decision_map(action['after']).get(asset_id, {})
        need((previous is None or previous.get('disposition') == 'undecided') and committed.get('disposition') == 'kept'
             and type(committed.get('revision')) is int and committed['revision'] > 0,
             'Month Keep must change a genuinely undecided persistent record')
        cumulative.add(asset_id)
        verify_preservation(before, action['after'], cumulative)
        for field, suffix in (('beforeScreenshot', 'before'), ('afterScreenshot', 'after')):
            name = f'stills/concept-a-v4-month-keep-{index:02d}-{suffix}.png'
            need(action.get(field) == name, 'Keep receipt must retain both real native stills')
            path = safe_file(root, name)
            metadata = legacy.image_record(path, Path(root))
            need((metadata['width'], metadata['height'], metadata['opaque']) == (1206, 2622, True), 'Keep receipt native still dimensions/opacity mismatch')
            bindings[name] = metadata['sha256']
        used.append(asset_id)
        last = action_end
    need(len(set(used)) == 3 and proof.get('actionAssetIDs') == used and proof.get('keptAssetIDs') == sorted(used), 'Actual month action ID receipts disagree')
    verify_preservation(before, after, set(used))
    complete = proof.get('afterCompleteMonth')
    observed_snapshot(log, complete, minimum=start + 1, label='months.afterCompleteMonth')
    need(month_rows(complete)['2026-10']['reviewed'] == 2, 'Intermediate real completed October publication required')
    navigation = proof.get('navigationActions')
    need(type(navigation) is list and len(navigation) == 4, 'Real month open/close navigation receipts required')
    for index, action in enumerate(navigation):
        target = validate_action(action, 'month.navigation')
        if index in (1, 3):
            need(target.get('identifier') == 'feed.close', 'Month progression must close the real feed to trigger the actual recount')
    preservation = proof.get('preservation', {})
    need(all(preservation.get(key) is True for key in ('inventoryUnchanged', 'basketIDsUnchanged', 'unrelatedDecisionsUnchanged', 'unrelatedMonthsUnchanged'))
         and type(preservation.get('additionalLedgerEvents')) is int and preservation['additionalLedgerEvents'] == 3,
         'Explicit truthful month preservation receipt required')
    audit_month_geometry(proof.get('geometry'), new)
    return {'status': 'PASS', 'schema_validation': 'STRICT_ACTUAL_TEST08_SCHEMA_1', 'source_bindings': bindings,
            'proof_sha256': digest(Path(root) / 'month-progress-proof.json'), 'observation_log_sha256': digest(Path(root) / 'concept-a-evidence.json'),
            'completed_month': '2026-10', 'partial_month': '2026-11', 'untouched_month': '2026-09', 'actual_decision_actions': 3,
            'native_visual_acceptance': 'NOT RUN'}


def validate_editor_observation(state, asset_id):
    observation = state.get('editorV4')
    need(type(observation) is dict and observation.get('assetID') == asset_id and observation.get('loadState') == 'ready'
         and observation.get('modelLoadState') == 'ready' and observation.get('errors') == [], 'Editor must report the real ready PhotoKit asset with no observer errors')
    for key in ('originalReady', 'previewReady', 'previewAssigned', 'publicationMatchesRequest'):
        need(observation.get(key) is True, 'Editor actual successful image publication required: ' + key)
    for key in ('rendering', 'previewRendering', 'dirty', 'comparing'):
        need(observation.get(key) is False, 'Editor is busy/stale or comparing instead of publishing: ' + key)
    for key in ('sourceOriginalPixelSHA256', 'publishedPreviewPixelSHA256', 'requestedRecipeHash', 'publishedRecipeHash'):
        hash_literal(observation.get(key), 'editor.' + key)
    need(observation['requestedRecipeHash'] == observation['publishedRecipeHash'], 'Requested recipe hash is not proof of actual published preview')
    need(type(observation.get('renderGeneration')) is int and observation['renderGeneration'] >= 0
         and type(observation.get('publishedRenderGeneration')) is int
         and observation['publishedRenderGeneration'] == observation['renderGeneration'], 'Editor preview publication generation is stale or unknown')
    need(all(type(observation.get(key)) is int and observation[key] > 0 for key in
             ('sourceOriginalPixelWidth', 'sourceOriginalPixelHeight', 'publishedPreviewPixelWidth', 'publishedPreviewPixelHeight')),
         'Editor actual assigned pixel-buffer dimensions required')
    need(observation['publishedPreviewPixelWidth'] <= observation['sourceOriginalPixelWidth']
         and observation['publishedPreviewPixelHeight'] <= observation['sourceOriginalPixelHeight'], 'Editor evidence must not upscale its original pixel buffer')
    need(observation.get('publicationOrigin') in ('originalAssignment', 'renderAssignment')
         and observation.get('pixelHashFormat') == 'SHA256 of assigned RGBA8 CGImage packed pixel rows; stride padding excluded',
         'Actual original/render assignment pixel-hash semantics required')
    return observation


def editor_checkpoint(root, row, name, screens, log, asset_id, asset, screen_frame):
    source = 'screenshots/' + name + '.png'
    sha = screenshot_binding(root, row, source, screens)
    index, state = checkpoint(log, name + '-capture-readback')
    observation = validate_editor_observation(state, asset_id)
    need(row.get('editorV4') == observation, 'Editor screenshot must bind its exact successful native publication readback')
    stage = validate_ax(row.get('stageAX'), 'editor.stageAX')
    need(stage.get('identifier') == 'editor.stage', 'Actual editor stage AX required')
    stage_box = rect(stage['frame'], 'editor.stage.frame')
    need(contains(screen_frame, stage_box), 'Complete actual editor stage must remain inside its native screen')
    width, height = asset.get('pixelWidth'), asset.get('pixelHeight')
    need(type(width) is int and type(height) is int and width > 0 and height > 0, 'Real initial PhotoKit photo dimensions required')
    factor = min((stage_box[2] - stage_box[0]) / width, (stage_box[3] - stage_box[1]) / height)
    mid_x, mid_y = (stage_box[0] + stage_box[2]) / 2, (stage_box[1] + stage_box[3]) / 2
    expected_photo = (mid_x - width * factor / 2, mid_y - height * factor / 2,
                      mid_x + width * factor / 2, mid_y + height * factor / 2)
    photo = rect(row.get('photoAXFrame'), 'photoAXFrame')
    need(all(abs(a - b) < 0.001 for a, b in zip(photo, expected_photo)), 'Actual editor photo rectangle must derive from aspect-fit original dimensions, never a guessed inset')
    scale = 1206 / (screen_frame[2] - screen_frame[0])
    crop = rect(row.get('photoNativeFrame'), 'photoNativeFrame')
    expected_crop = (math.floor((photo[0] - screen_frame[0]) * scale + 2),
                     math.floor((photo[1] - screen_frame[1]) * scale + 2),
                     math.ceil((photo[2] - screen_frame[0]) * scale - 2),
                     math.ceil((photo[3] - screen_frame[1]) * scale - 2))
    need(crop == expected_crop and contains((0, 0, 1206, 2622), crop), 'Native photo stability crop must match the real aspect-fit area and declared two-pixel inset')
    crop = tuple(int(value) for value in crop)  # only after exact integral geometry equality
    tool = 'filter' if name.endswith('filter-selected') else 'adjust'
    selected = validate_ax(row.get('selectedToolAX'), 'editor.selectedToolAX', selected=True)
    need(selected.get('identifier') == 'editor.tool.' + tool, 'Actual selected native tool does not match the screenshot layout')
    for key in ('undoAX', 'redoAX'):
        target = validate_ax(row.get(key), key)
        need(target.get('identifier') == 'editor.' + key[:-2], 'Actual Undo/Redo control identity required')
    stability = row.get('stability', {})
    samples = stability.get('samples')
    need(stability.get('method') == 'two consecutive real native photo-area RGBA8 pixel hashes'
         and type(stability.get('consecutiveEqualSamples')) is int and stability['consecutiveEqualSamples'] == 2
         and type(samples) is list and 2 <= len(samples) <= 6, 'Actual consecutive stable editor-photo samples required')
    bindings, crops, last_time = {source: sha}, [], 0
    for number, sample in enumerate(samples):
        filename = f'stills/{name}-stability-{number}.png'
        sample_sha = screenshot_binding(root, sample, filename)
        need(all(type(sample.get(key)) in (int, float) and math.isfinite(sample[key]) and sample[key] > 0
                 for key in ('captureStarted', 'captureFinished'))
             and last_time <= sample['captureStarted'] <= sample['captureFinished'], 'Editor stability acquisition timestamps must be real, finite and ordered')
        hash_literal(sample.get('photoPixelSHA256'), 'native photo pixel hash')
        with Image.open(safe_file(root, filename)) as image:
            crops.append(image.crop(crop).convert('RGBA').tobytes())
        bindings[filename] = sample_sha
        last_time = sample['captureFinished']
    with Image.open(safe_file(root, source)) as image:
        actual_crop = image.crop(crop).convert('RGBA').tobytes()
    need(samples[-1]['photoPixelSHA256'] == samples[-2]['photoPixelSHA256'] and crops[-1] == crops[-2] == actual_crop
         and samples[-1]['screenshotSHA256'] == sha, 'Actual immutable consecutive native crops and final source must agree, not just claimed stability flags')
    if 'photoPixelSHA256' in row:
        need(row['photoPixelSHA256'] == samples[-1]['photoPixelSHA256'], 'Editor screenshot photo-pixel summary differs from its actual final native sample')
    # CoreGraphics and Pillow can have different row orientation/color pipelines.
    # Independently compare real crop bytes; do not pretend its digest is the native observer's CGImage digest.
    return observation, index, crop, hashlib.sha256(actual_crop).hexdigest(), bindings


def audit_editor_pair(root, screens, library):
    proof = builder.load_json(safe_file(root, 'editor-pair-proof.json'))
    proof_header(proof, 'concept-a-v4-editor-pair')
    assets = library_by_id(library)
    asset_id = proof.get('assetID')
    need(type(asset_id) is str and asset_id in assets and assets[asset_id].get('isVideo') is False
         and proof.get('filename') == assets[asset_id].get('filename') == 'CA_30_pretty_08.jpg'
         and proof.get('asset') == assets[asset_id] and proof.get('matchedTool') == 'adjust', 'Editor must compare the one actual inventoried original in a matched native Adjust layout')
    checkpoints = proof.get('checkpoints')
    need(type(checkpoints) is dict and set(checkpoints) == {'before', 'filterSelection', 'after', 'undo', 'redo', 'copyDefault'}, 'Complete separate real editor checkpoint set required')
    log = load_evidence(root)
    baseline, final = proof.get('beforeState'), proof.get('afterState')
    baseline_index = observed_snapshot(log, baseline, label='editor.beforeState')
    final_index = observed_snapshot(log, final, minimum=baseline_index + 1, label='editor.afterState')
    verify_preservation(baseline, final, set())
    month_proof = builder.load_json(safe_file(root, 'month-progress-proof.json'))
    screen_frame = rect(month_proof.get('geometry', {}).get('screenAXFrame'), 'actual common screenAXFrame')
    observations, indices, crop_hashes, crops, bindings = {}, {}, {}, {}, {}
    names = {'before': 'concept-a-v4-editor-before', 'filterSelection': 'concept-a-v4-editor-filter-selected',
             'after': 'concept-a-v4-editor-after', 'undo': 'concept-a-v4-editor-undo', 'redo': 'concept-a-v4-editor-redo'}
    for label, name in names.items():
        observation, index, crop, pixel_hash, sources = editor_checkpoint(root, checkpoints[label], name, screens, log, asset_id, assets[asset_id], screen_frame)
        observations[label], indices[label], crops[label], crop_hashes[label] = observation, index, crop, pixel_hash
        bindings.update(sources)
    order = [baseline_index] + [indices[key] for key in names] + [final_index]
    need(all(a < b for a, b in zip(order, order[1:])), 'Actual editor publications/capture readbacks must be in real Original/Warm/Undo/Redo order')
    original, warm, undo, redo = (observations[label] for label in ('before', 'after', 'undo', 'redo'))
    need(all(observation['sourceOriginalPixelSHA256'] == original['sourceOriginalPixelSHA256']
             and (observation['sourceOriginalPixelWidth'], observation['sourceOriginalPixelHeight'])
             == (original['sourceOriginalPixelWidth'], original['sourceOriginalPixelHeight']) for observation in observations.values()), 'Every editor state must retain the same actually assigned original pixel buffer')
    for observation in (original, undo):
        need(observation.get('publishedFilter') == 'original' and observation.get('publishedIsIdentity') is True
             and observation['publishedPreviewPixelSHA256'] == observation['sourceOriginalPixelSHA256'], 'Before/Undo must publish the true unedited Original pixel buffer, not a requested recipe')
    for observation in (warm, redo, observations['filterSelection']):
        strength = observation.get('publishedFilterStrength')
        need(observation.get('publishedFilter') == 'warm' and observation.get('publishedIsIdentity') is False
             and type(strength) in (int, float) and strength == 1 and observation.get('publicationOrigin') == 'renderAssignment', 'Warm must be a real successful nonidentity publication at the observed default strength 100')
    need(original['publishedPreviewPixelSHA256'] == undo['publishedPreviewPixelSHA256']
         and original['publishedRecipeHash'] == undo['publishedRecipeHash']
         and warm['publishedPreviewPixelSHA256'] == redo['publishedPreviewPixelSHA256'] == observations['filterSelection']['publishedPreviewPixelSHA256']
         and warm['publishedRecipeHash'] == redo['publishedRecipeHash'] == observations['filterSelection']['publishedRecipeHash']
         and warm['publishedPreviewPixelSHA256'] != original['publishedPreviewPixelSHA256']
         and warm['publishedRecipeHash'] != original['publishedRecipeHash'], 'Actual Undo/Redo must restore the original/Warm pixel and recipe hashes')
    generations = [observations[label]['publishedRenderGeneration'] for label in ('before', 'after', 'undo', 'redo')]
    need(all(a < b for a, b in zip(generations, generations[1:])), 'Successful preview publications must advance real generations across Warm/Undo/Redo')
    need(all(crops[key] == crops['before'] for key in ('after', 'undo', 'redo'))
         and checkpoints['before']['stageAX'] == checkpoints['after']['stageAX']
         and crop_hashes['before'] == crop_hashes['undo'] and crop_hashes['after'] == crop_hashes['redo']
         and crop_hashes['before'] != crop_hashes['after'], 'Actual matched native photo pixels must change for Warm and restore identically under Undo/Redo')
    for label, expected in (('before', (False, False)), ('after', (True, False)), ('undo', (False, True)), ('redo', (True, False))):
        need((checkpoints[label]['undoAX']['enabled'], checkpoints[label]['redoAX']['enabled']) == expected, 'Real native Undo/Redo enabled states disagree: ' + label)
    filter_source = checkpoints['filterSelection']
    warm_ax = validate_ax(filter_source.get('warmAX'), 'Warm AX', selected=True)
    strength_ax = validate_ax(filter_source.get('strengthAX'), 'Strength AX')
    need(strength_ax.get('value') == '100', 'Native filter Strength=100 must actually be observed')
    copy = checkpoints['copyDefault']
    source = 'screenshots/concept-a-v4-editor-copy-default.png'
    bindings[source] = screenshot_binding(root, copy, source, screens)
    need(copy.get('underlyingEditorCheckpoint') == 'redo' and copy.get('defaultSelectionUntouched') is True
         and copy.get('saveExecuted') is False and proof.get('saveCancelled') is True and proof.get('noAssetCreated') is True, 'Save sheet must preserve actual copy default and be cancelled without exporting')
    options = copy.get('optionsAX')
    need(type(options) is list and len(options) == 3, 'All three actual native save options must be observed')
    for index, option in enumerate(options):
        validate_ax(option, 'save option', selected=(index == 0))
        need(contains(screen_frame, rect(option['frame'], 'save option frame')), 'All actual copy/replace/original save options must remain onscreen')
    need(len({option.get('label') for option in options}) == 3, 'Save copy/replace/original must be distinct real options')
    confirm = validate_ax(copy.get('confirmationAX'), 'save confirmation')
    need(confirm.get('identifier') == 'editor.save.confirm' and type(confirm.get('label')) is str and confirm['label'], 'Actual native Save copy confirmation must be visible but never tapped')
    need(contains(screen_frame, rect(confirm['frame'], 'save confirmation frame')), 'The complete actual Save copy confirmation must be onscreen')
    actions = proof.get('actions')
    need(type(actions) is list and 8 <= len(actions) <= 10, 'Real editor tool/filter/Undo/Redo/open-save/cancel receipts required')
    last_time = 0
    for index, action in enumerate(actions):
        is_drag = action.get('action') == 'native save sheet expand drag'
        target = validate_action(action, 'editor.action', kind='native save sheet expand drag' if is_drag else 'tap')
        need(action['started'] >= last_time and target.get('identifier') != 'editor.save.confirm', 'Editor actions must be ordered and must never execute Save copy/original')
        if is_drag:
            need(7 <= index < len(actions) - 1, 'Only bounded real save-sheet expansion drags are allowed')
        last_time = action['finished']
    for index, identifier in ((0, 'editor.tool.adjust'), (1, 'editor.tool.filter'), (3, 'editor.tool.adjust'), (4, 'editor.undo'), (5, 'editor.redo')):
        need(actions[index]['targetAX'].get('identifier') == identifier, 'Actual ordered editor tool/Undo/Redo action missing')
    need(actions[2]['targetAX'].get('identifier') == warm_ax.get('identifier')
         and actions[2]['targetAX'].get('label') == warm_ax.get('label'), 'Warm publication must follow an actual tap on the real Warm control')
    cancelled = validate_editor_observation(final, asset_id)
    need(cancelled == redo, 'Cancelling the actual native save sheet must not edit or republish the underlying photo')
    for field, expected in (('sourceOriginalPixelSHA256', original['sourceOriginalPixelSHA256']),
                            ('beforePreviewPixelSHA256', original['publishedPreviewPixelSHA256']), ('afterPreviewPixelSHA256', warm['publishedPreviewPixelSHA256']),
                            ('beforeRecipeHash', original['publishedRecipeHash']), ('afterRecipeHash', warm['publishedRecipeHash'])):
        need(proof.get(field) == expected, 'Editor summary hash differs from its actual published checkpoint: ' + field)
    preservation = proof.get('preservation', {})
    need(all(preservation.get(key) is True for key in ('inventoryUnchanged', 'basketIDsUnchanged', 'allDecisionsUnchanged'))
         and type(preservation.get('additionalLedgerEvents')) is int and preservation['additionalLedgerEvents'] == 0, 'Explicit unchanged actual editor library/ledger receipt required')
    return {'status': 'PASS', 'schema_validation': 'STRICT_ACTUAL_TEST08_SCHEMA_1', 'asset_id': asset_id, 'filename': proof['filename'],
            'source_bindings': bindings, 'proof_sha256': digest(Path(root) / 'editor-pair-proof.json'),
            'observation_log_sha256': digest(Path(root) / 'concept-a-evidence.json'),
            'published_preview_pixel_hashes': {key: value['publishedPreviewPixelSHA256'] for key, value in observations.items()},
            'published_generations': {key: value['publishedRenderGeneration'] for key, value in observations.items()},
            'independent_native_photo_crop_hashes': crop_hashes, 'actual_native_photo_crop_equality': 'PASS',
            'copy_default_selected': True, 'save_cancelled_without_export': True, 'native_visual_acceptance': 'NOT RUN'}


def _preserve(root, stem, raw):
    sha = hashlib.sha256(raw).hexdigest()
    path = Path(root) / f'{stem}-{sha}.json'
    if path.exists():
        need(path.read_bytes() == raw, 'Refusing to overwrite a preserved evidence report')
    else:
        with path.open('xb') as stream:
            stream.write(raw)
    return {'file': path.name, 'sha256': sha}


def run_legacy(root):
    """Use the unmodified collector, not reconstructed environment/app metadata."""
    canonical = Path(root) / 'capture_provenance.json'
    prior = _preserve(root, 'capture_provenance.before-v4', canonical.read_bytes()) if canonical.is_file() else None
    old_argv, code, failure = sys.argv[:], 0, None
    try:
        sys.argv = [str(Path(legacy.__file__)), str(root)]
        with contextlib.redirect_stdout(io.StringIO()):
            legacy.main()
    except SystemExit as error:
        code = error.code if type(error.code) is int else 1
    except Exception as error:
        code, failure = 1, f'{type(error).__name__}: {error}'
    finally:
        sys.argv = old_argv
    if failure:
        return {}, {'status': 'FAIL', 'exit_code': code, 'error': failure, 'previous_canonical': prior}
    need(canonical.is_file(), 'Legacy collector did not create its actual report')
    raw = canonical.read_bytes()
    preserved = _preserve(root, 'capture_provenance.base-c14', raw)
    report = builder.load_json(canonical)
    return report, {'status': 'PASS' if code == 0 and report.get('status') == 'PASS' else 'FAIL',
                    'exit_code': code, **preserved, 'collector_sha256': digest(Path(legacy.__file__)), 'previous_canonical': prior}


def collect(root, sources, allowlist, fixture_root, *, capture_test=DEFAULT_CAPTURE_TEST, run_readback=None):
    root = Path(root).resolve()
    need(root.is_dir() and root != builder.REPO_ROOT and builder.REPO_ROOT not in root.parents, 'Capture reports must remain outside the release repository')
    errors, audits = [], {}
    base, receipt = run_legacy(root)
    if receipt['status'] != 'PASS':
        errors.append('Unmodified C14 base collector did not PASS')
        errors.extend('base: ' + str(error) for error in base.get('errors', []))
    def check(label, function):
        try:
            value = function()
            audits[label] = value
            return value
        except Exception as error:
            message = f'{label}: {type(error).__name__}: {error}'
            errors.append(message)
            audits[label] = {'status': 'FAIL', 'errors': [message]}
            return None
    check('literal_run_pins', lambda: {'status': 'PASS', **validate_run_pins(base)})
    check('capture_test', lambda: validate_capture_summary(builder.load_json(root / 'summary.json'), builder.load_json(root / 'tests.json'), capture_test))
    fixture = check('fixture_manifest', lambda: builder.load_json(root / 'fixture-manifest.json'))
    inputs = check('original_sources', lambda: builder.load_sources(Path(sources), Path(allowlist)))
    if inputs is not None and fixture is not None:
        roles, source_sha, allowlist_sha = inputs
        audits['original_sources'] = {'status': 'PASS', 'verified_originals': len(roles), 'source_manifest_sha256': source_sha, 'allowlist_sha256': allowlist_sha}
        rows = check('fixture_records', lambda: validate_fixture_metadata(fixture, builder.load_json(Path(sources) / 'manifest.json'),
                     builder.load_json(Path(allowlist)), source_sha, allowlist_sha))
        if rows is not None:
            audits['fixture_records'] = {'status': 'PASS', 'actual_records': len(rows), 'filename_set_exact': True, 'all_source_fields_bound': True}
            check('fixture_files', lambda: verify_fixture_files(fixture_root, fixture, rows, sources))
            check('captured_fixture_manifest_bytes', lambda: _same_manifest_bytes(root, fixture_root))
    screens = check('native_screens', lambda: validate_native_screens(root))
    library = check('actual_library', lambda: builder.load_json(root / 'concept-a-library.json'))
    if library is not None and fixture is not None:
        def actual_media():
            result = legacy.audit_sample_media(library, fixture)
            need(result['status'] == 'PASS', '; '.join(result['errors']))
            library_by_id(library)
            return result
        check('sample_media', actual_media)
    if screens is not None:
        audits['native_screens'] = {'status': 'PASS', 'required_count': len(screens), 'outputs': list(screens.values())}
    # Missing screens/library still trigger explicit proof validation failures, not skipped gates.
    check('month_progress', lambda: audit_month_progress(root, screens or {}, library or {}))
    check('editor_pair', lambda: audit_editor_pair(root, screens or {}, library or {}))
    if run_readback is not None:
        result = check('exact_attempt_api', lambda: validate_exact_attempt_readback(builder.load_json(Path(run_readback)), base))
        if result is not None:
            result['readback_sha256'] = digest(Path(run_readback))
    else:
        audits['exact_attempt_api'] = {'status': 'NOT RUN', 'reason': 'Exact-attempt API completion/jobs readback is a separate post-run gate; no API success is inferred'}
    report = {**base, 'schema_version': 2, 'creative_revision': 4, 'status': 'FAIL' if errors else 'PASS',
              'native_scene_policy': V4_SCENE_POLICY, 'v4_native_scene_policy': V4_SCENE_POLICY,
              'base_c14_provenance': receipt, 'base_c14_native_scene_policy': base.get('native_scene_policy'),
              'v4_audits': audits, 'required_native_screens': [f'concept-a-{name}.png' for name in legacy.REQUIRED] + list(NEW_SCREENS),
              'collected_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'native_visual_acceptance': 'NOT RUN', 'store_export_acceptance': 'NOT RUN', 'real_device_or_security_acceptance': 'NOT RUN',
              'exact_api_run_acceptance': audits['exact_attempt_api']['status'],
              'errors': errors}
    if screens is not None:
        report['outputs'] = list(screens.values())
    raw = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
    (root / 'capture_provenance.json').write_text(raw, encoding='utf-8')
    return report


def _same_manifest_bytes(root, fixture_root):
    need(digest(Path(root) / 'fixture-manifest.json') == digest(Path(fixture_root) / 'fixture-manifest.json'), 'Capture must retain exact prepared fixture-manifest bytes')
    return {'status': 'PASS', 'sha256': digest(Path(root) / 'fixture-manifest.json')}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--sources', type=Path, required=True)
    parser.add_argument('--allowlist', type=Path, required=True)
    parser.add_argument('--fixture-root', type=Path, required=True, help='Actual prepared 37-file fixture, not just its asserted manifest')
    parser.add_argument('--capture-test', default=DEFAULT_CAPTURE_TEST, help='Exact Suite/test08Method selector, no parentheses')
    parser.add_argument('--run-readback', type=Path, help='Optional completed exact-attempt API + complete jobs readback')
    args = parser.parse_args(argv)
    try:
        report = collect(args.root, args.sources, args.allowlist, args.fixture_root,
                         capture_test=args.capture_test, run_readback=args.run_readback)
    except Exception as error:
        print(json.dumps({'status': 'FAIL', 'creative_revision': 4, 'error': f'{type(error).__name__}: {error}'}))
        return 1
    print(json.dumps({'status': report['status'], 'creative_revision': 4,
                      'exact_api_run_acceptance': report['exact_api_run_acceptance'], 'errors': report['errors']}))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
