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
assert len(list(asset_root.rglob('*.png'))) == 71
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
for folder in ['SnakeHeads.atlas', 'SnakeBody.atlas', 'SnakeFood.atlas', 'SnakeUI.atlas', 'Backgrounds', 'Sounds']:
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
old = json.loads(subprocess.check_output(['git', 'show', '4bfba4f:PhotoMaid/Resources/Localizable.xcstrings'], cwd=ROOT))['strings']
new = json.loads((ROOT / 'PhotoMaid/Resources/Localizable.xcstrings').read_text())['strings']
assert all(new.get(key) == value for key, value in old.items()), 'Existing translations changed'
print('PASS: 77 byte-identical resources (71 PNG / 6 WAV), atlas sizes/alpha, target resource paths, SpriteKit dependency')
print('PASS: literal animation/food/UI references, swipe-only source, original Snake rules and 2657 localization entries preserved')
print('STATIC AUDIT ONLY: XcodeGen generation, compiled bundle loading, UIKit/SpriteKit rendering and device FPS still require Xcode.')
