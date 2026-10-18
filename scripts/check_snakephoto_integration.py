#!/usr/bin/env python3
"""Local, read-only resource/target audit. Does not build, dispatch CI or contact Apple."""
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import wave
import yaml

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'docs/snakephoto/ASSET_INTEGRATION.json').read_text())
spec = yaml.safe_load((ROOT / 'project.yml').read_text())
target = spec['targets']['PhotoMaid']
entries = {entry['path']: entry for entry in target['sources']}
asset_root = ROOT / 'PhotoMaid/Resources/SnakePhoto'
assert len(manifest['assets']) == 77
assert len({entry['path'] for entry in manifest['assets']}) == 77
assert len(list(asset_root.rglob('*.png'))) == 71 + 92
assert len(list(asset_root.rglob('*.wav'))) == 6
for asset in manifest['assets']:
    path = ROOT / asset['path']
    data = path.read_bytes()
    assert len(data) == asset['bytes'], path
    assert hashlib.sha256(data).hexdigest() == asset['sha256'], path
    if path.suffix == '.png':
        assert data[:8] == b'\x89PNG\r\n\x1a\n'
        width, height = struct.unpack('>II', data[16:24])
        if path.parent.suffix == '.atlas':
            assert (width, height) == (256, 256), path
            assert data[25] == 6, f'Expected RGBA: {path}'
    else:
        with wave.open(str(path)) as sound:
            assert sound.getframerate() == 44100 and sound.getnchannels() == 1, path
for folder in ['SnakeHeads.atlas', 'SnakeBody.atlas', 'SnakeFood.atlas', 'SnakeUI.atlas', 'SnakeTopDown.atlas', 'Backgrounds', 'Sounds']:
    entry = entries['PhotoMaid/Resources/SnakePhoto/' + folder]
    assert entry['buildPhase'] == 'resources', folder
    if folder.endswith('.atlas'):
        assert entry['type'] == 'file', folder
assert 'Resources/SnakePhoto' in entries['PhotoMaid']['excludes'], 'Avoid duplicate atlas resource paths'
assert {'sdk': 'SpriteKit.framework'} in target['dependencies']
assert target['info']['properties']['UISupportedInterfaceOrientations'] == ['UIInterfaceOrientationPortrait']
assert target['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER'] == 'com.mrdevn4ever.photomaid'

# Every literal sprite referenced by the renderer/composer/menu must be an actual resource.
names = {path.stem for path in asset_root.rglob('*.png')}
for path in (ROOT / 'PhotoMaid/Features/Snake').glob('*.swift'):
    text = path.read_text()
    for name in re.findall(r'SnakeArt\.(?:texture|image)\("([a-z0-9_]+)"\)', text):
        assert name in names, (path, name)
    assert not re.search(r'"ui_(?:up|down|left|right)"|snake\.direction\.', text), 'No movement buttons: ' + str(path)
    assert 'SKCropNode' not in text, 'Photos must be composed once, not cropped per segment'
style = (ROOT / 'Sources/PhotoMaidCore/Games/PhotoSnakeStyle.swift').read_text()
for name in re.findall(r'"((?:head|dragon|dino|monster)_[a-z0-9_]+)"', style):
    assert name in names, name
for character in ['dragon', 'dino', 'monster']:
    for state in ['idle', 'blink', 'eat', 'dead']:
        assert character + '_' + state in names
for food in ['apple', 'star', 'heart', 'gem', 'grapes', 'donut', 'cheese', 'cake', 'pizza']:
    assert 'food_' + food in names

rules = 'Sources/PhotoMaidCore/Games/PhotoSnakeGame.swift'
original = subprocess.check_output(['git', 'show', '4bfba4f:' + rules], cwd=ROOT)
assert (ROOT / rules).read_bytes() == original, 'Existing collision/growth/direction rules changed'
old = json.loads(subprocess.check_output(['git', 'show', 'e9da9db:PhotoMaid/Resources/Localizable.xcstrings'], cwd=ROOT))['strings']
new = json.loads((ROOT / 'PhotoMaid/Resources/Localizable.xcstrings').read_text())['strings']
allowed_copy = {'snake_eaten', 'game_best_eaten', 'snake_controls_hint', 'snake_start_game',
                'snake_other_games', 'snake_record_empty'}
assert old.keys() <= new.keys(), 'Existing translation keys removed'
assert all(key in allowed_copy or key.startswith('blocks_') for key in new.keys() - old.keys()), 'Unexpected new translations'
assert all(new[key] == value for key, value in old.items() if key not in allowed_copy), 'Unrelated translations changed'
for key in allowed_copy:
    assert len(new[key]['localizations']) == 16, key
# The head frames are authored separately; do not alter the original kit resources.
overhead = json.loads((ROOT / 'docs/snake-readable-20261018/head-art.json').read_text())
assert len(overhead['assets']) == 92
from PIL import Image
for asset in overhead['assets']:
    path = asset_root / 'SnakeTopDown.atlas' / (asset['name'] + '.png')
    data = path.read_bytes()
    assert len(data) == asset['bytes'] and hashlib.sha256(data).hexdigest() == asset['sha256'], path
    with Image.open(path) as image:
        assert image.mode == 'RGBA' and image.size == (256, 256), path
        bounds = image.getchannel('A').getbbox()
        assert bounds and 0 < bounds[0] < bounds[2] < 256 and 0 < bounds[1] < bounds[3] < 256, path
        nose, eyes = asset['nose'], asset['eyes']
        eye_centre = [sum(p[i] for p in eyes) / 2 for i in [0, 1]]
        axis = 0 if asset['direction'] in ['left', 'right'] else 1
        assert (nose[axis] > eye_centre[axis]) == (asset['direction'] in ['right', 'down'])
for character in ['snake', 'dragon', 'dino', 'monster']:
    poses = ['idle', 'blink', 'halfBlink', 'tongue', 'eat', 'hurt', 'dead', 'sleep', 'surprised', 'lookLeft', 'lookRight'] if character == 'snake' else ['idle', 'blink', 'eat', 'dead']
    for pose in poses:
        for direction in ['up', 'down', 'left', 'right']:
            assert f'top_{character}_{pose}_{direction}' in names
for preserved in ['Sources/PhotoMaidCore/Games/PhotoSnakeGallery.swift',
                  'Sources/PhotoMaidCore/Games/PhotoGameRecords.swift',
                  'PhotoMaid/Features/Snake/PhotoSnakeModel.swift']:
    assert (ROOT / preserved).read_bytes() == subprocess.check_output(['git', 'show', 'e9da9db:' + preserved], cwd=ROOT), preserved
print('PASS: 77 byte-identical resources (71 PNG / 6 WAV), atlas sizes/alpha, target resource paths, SpriteKit dependency')
print('PASS: 92 new 256px RGBA overhead frames, hashes, uncut alpha bounds and four correct nose/eye directions')
print(f'PASS: animation/food/UI references, swipe-only source, original Snake rules; {len(new)} localization entries, six authorized Snake copy keys plus Blocks additions')
print('PASS: gallery archive/order, record persistence and native game model unchanged from e9da9db')
print('STATIC AUDIT ONLY: XcodeGen generation, compiled bundle loading, UIKit/SpriteKit rendering and device FPS still require Xcode.')
