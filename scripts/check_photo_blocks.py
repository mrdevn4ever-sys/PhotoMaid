#!/usr/bin/env python3
"""Read-only source integration/privacy checks. Not a substitute for an iOS SDK build."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import yaml

ROOT = Path(__file__).resolve().parents[1]
def read(path): return (ROOT / path).read_text()

baseline = json.loads(read('docs/photo-blocks-20261018/snake-baseline.json'))
for path, digest in baseline.items():
    assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest() == digest, path
for path in ['Sources/PhotoMaidCore/Games/PhotoGameRecords.swift', 'PhotoMaid/Features/Games/PhotoGameScores.swift']:
    original = subprocess.check_output(['git', 'show', 'e9da9db:' + path], cwd=ROOT)
    assert (ROOT/path).read_bytes() == original, path

native = '\n'.join(p.read_text() for p in (ROOT/'PhotoMaid/Features/Blocks').glob('*.swift'))
core = '\n'.join(p.read_text() for p in (ROOT/'Sources/PhotoMaidCore/Games').glob('PhotoBlocks*.swift'))
assert all(word not in native + core for word in ['URLSession', 'CloudKit', 'Vision', 'loadTransferable', 'PhotosPicker', 'AdMob', 'NotificationRequest'])
assert 'PHCachingImageManager' not in native, 'Must reuse existing photo managers'
assert 'offlineGame: true' in native
assert 'game.phase != .discovered' in read('PhotoMaid/Features/Blocks/PhotoBlocksBoard.swift')
assert '.id(game.level)' in read('PhotoMaid/Features/Blocks/PhotoBlocksBoard.swift')
assert 'PhotoBlocksPhotos.revealedHeight(strips:' in native
assert '.analysisVisibilityChanged' in native and 'model.pause()' in native
assert '[weak self, weak app]' in native

loader = read('PhotoMaid/Features/Games/PhotoGamePhotos.swift')
offline = loader[loader.index('func prepareOfflineWindow'):loader.index('@discardableResult func validatePhotos')]
assert 'allowNetwork: false' in offline and 'exactSize: true' in offline and '.prefix(2)' in offline
assert 'self.permitted([id])' in offline and 'self.loadID == token' in offline
scope = loader[loader.index('static func offlineCandidates'):loader.index('private(set) var photoIDs')]
for guard in ['canRead', 'analysisReady', 'VaultConcealment.shared.visible', 'app.cleanupMedia', '!$0.isVideo']:
    assert guard in scope, guard
components = read('PhotoMaid/DesignSystem/Components.swift')
assert 'guard allowNetwork, !Task.isCancelled else { return nil }' in components
picker = read('PhotoMaid/Features/Studio/StudioMediaPicker.swift')
assert 'PhotoGamePhotos.offlineCandidates(app: app)' in picker and 'allowNetwork: !offlineGame' in picker

catalog = json.loads(read('PhotoMaid/Resources/Localizable.xcstrings'))['strings']
source = json.loads(read('PhotoMaid/Resources/ios_strings.json'))
keys = set(re.findall(r'"(blocks_[a-z_]+)"', native))
assert len(keys) == 41, len(keys)
for key in keys:
    assert len(catalog[key]['localizations']) == 16 and len(source[key]) == 16, key
    for lang, entry in catalog[key]['localizations'].items():
        value = entry['stringUnit']['value']
        assert value == source[key][lang] and value.strip(), (key, lang)
        assert not re.search(r'tetris', value, re.I), (key, lang)
        assert len(re.findall(r'%(?:\d+\$)?lld', value)) == len(re.findall(r'%(?:\d+\$)?lld', source[key]['en'])), key
spec = yaml.safe_load(read('project.yml'))
assert any(entry.get('path') == 'PhotoMaid' for entry in spec['targets']['PhotoMaid']['sources'])
assert 'selected = .blocks' in read('PhotoMaid/Features/Games/PhotoGamesView.swift')
assert 'games.blocks.v1' in read('PhotoMaid/Persistence/KeyValueStore.swift')
print('PASS: Snake byte-identical to task start; existing records formats unchanged')
print('PASS: central offline scope, guarded two-image window, offline picker, fixed reveal coordinates, weak single clock')
print('PASS: 41 Blocks strings in all 16 locales; native recursive target inclusion and navigation')
print('STATIC SOURCE AUDIT: no iOS type check, device privacy test or FPS measurement claimed')
