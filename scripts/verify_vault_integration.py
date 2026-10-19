#!/usr/bin/env python
"""Source-contract checks for the targeted vault transplant (NOT Swift/runtime tests).
Run: python scripts/verify_vault_integration.py
"""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = 'de90f1d67c2dbe753f5da6c012ae6feb9172b277'
BASE = '0c65547'

def text(path):
    return (ROOT / path).read_text(encoding='utf-8')

def git_bytes(rev, path):
    return subprocess.check_output(['git', '-C', str(ROOT), 'show', rev + ':' + path])

def body(path, marker):
    value = text(path)
    start = value.index(marker)
    start = value.index('{', start)
    depth = 1
    end = start + 1
    while depth:
        depth += (value[end] == '{') - (value[end] == '}')
        end += 1
    return value[start + 1:end - 1]

class VaultSourceContractTests(unittest.TestCase):
    def test_crypto_is_exact_source_bytes(self):
        path = 'PhotoMaid/Infrastructure/Vault/VaultCrypto.swift'
        actual = (ROOT / path).read_bytes()
        self.assertEqual(actual, git_bytes(SOURCE, path))
        self.assertEqual(hashlib.sha256(actual).hexdigest(), '4e326b01de50649c8b1189e09021e2b055202479bde21d3cb33c92cf5057022a')

    def test_complete_core_and_source_security_tests(self):
        paths = subprocess.check_output(['git', '-C', str(ROOT), 'ls-tree', '-r', '--name-only', SOURCE], text=True).splitlines()
        selected = [p for p in paths if p.endswith('.swift') and (p.startswith('Sources/PhotoMaidCore/Vault/') or
                    p in ['Tests/PhotoMaidCoreTests/VaultTests.swift', 'Tests/PhotoMaidCoreTests/VaultSecurityTests.swift',
                          'Tests/PhotoMaidCoreTests/VaultWorkspaceTests.swift', 'PhotoMaidTests/VaultKeychainTests.swift',
                          'PhotoMaidUITests/VaultDeletionTests.swift'])]
        self.assertEqual(len(selected), 12)
        for path in selected:
            with self.subTest(path=path):
                self.assertEqual((ROOT / path).read_bytes(), git_bytes(SOURCE, path))

    def test_preserved_product_schema_storekit_and_workflows(self):
        for path in ['Sources/PhotoMaidCore/Capabilities/Capabilities.swift', 'Sources/PhotoMaidCore/Ads/FeedAdPolicy.swift',
                     'PhotoMaid/App/AppConfig.swift', 'PhotoMaid/Infrastructure/Purchases/StoreKitGateway.swift',
                     'PhotoMaid/Persistence/CoreDataStore.swift', 'PhotoMaid/Persistence/KeyValueStore.swift',
                     'PhotoMaid/Resources/PhotoMaid.storekit', '.github/workflows/ci.yml', '.github/workflows/testflight.yml']:
            with self.subTest(path=path):
                self.assertEqual((ROOT / path).read_bytes().replace(b'\r\n', b'\n'), git_bytes(BASE, path).replace(b'\r\n', b'\n'))
        project = text('project.yml')
        project = ''.join(line for line in project.splitlines(keepends=True) if not re.match(r'\s*NS(FaceID|Microphone)UsageDescription:', line))
        self.assertEqual(project, git_bytes(BASE, 'project.yml').decode().replace('\r\n', '\n'))
        self.assertFalse((ROOT / 'PhotoMaid/Infrastructure/Ads').exists())

    def test_no_ads_in_vault_transplant(self):
        for folder in ['PhotoMaid/Features/Vault', 'PhotoMaid/Infrastructure/Vault']:
            for path in (ROOT / folder).glob('*.swift'):
                with self.subTest(path=path.name):
                    self.assertNotRegex(path.read_text(), r'AdsService|VaultFolderGate|GoogleMobileAds|AppTrackingTransparency')

    def test_unknown_visibility_is_closed_in_every_public_query(self):
        path = 'PhotoMaid/Infrastructure/Vault/VaultConcealment.swift'
        self.assertIn('loaded && !damaged &&', text(path))
        self.assertIn('!loaded || damaged ||', body(path, 'func isConcealed'))
        self.assertIn('guard loaded, !damaged else { return [] }', body(path, 'func visible<T>'))
        for marker in ['func conceal(', 'func reveal(']:
            self.assertIn('guard loaded, !damaged else { throw', body(path, marker))
        self.assertIn('set.version == VaultConcealmentSet.currentVersion', text(path))
        self.assertIn('set.salt.count == 32', text(path))
        self.assertIn('indexURL.path', body(path, 'private func current()'))
        self.assertNotIn('AnalysisDatabase', text(path))
        self.assertNotIn('SizeIndexDatabase', text(path))

    def test_isolation_precedes_index_and_import_success(self):
        path = 'PhotoMaid/Infrastructure/Vault/VaultStore.swift'
        commit = body(path, 'func commitSnapshot(')
        self.assertLess(commit.index('try VaultConcealment.shared.conceal(candidate.originalIDs.union(candidate.fileConcealmentKeys))'),
                        commit.index('try Self.persist(candidate, key: lease.key)'))
        self.assertLess(commit.index('try Self.persist(candidate, key: lease.key)'), commit.index('index = value.media'))
        importer = body(path, 'func importAssets(')
        self.assertLess(importer.index('try VaultConcealment.shared.conceal('), importer.index('try commit { $0.add(item) }'))
        self.assertLess(importer.index('try commit { $0.add(item) }'), importer.index('report.imported += 1'))
        self.assertNotRegex(text(path), r'try\?\s+VaultConcealment')
        opening = body(path, 'private func open(with key:')
        self.assertLess(opening.index('try VaultCrypto.open'), opening.index('phase = .unlocked'))
        self.assertLess(opening.index('try value.validate()'), opening.index('phase = .unlocked'))
        self.assertNotIn('VaultConcealment.shared.repair', opening)
        sync = body(path, 'func syncConcealment(')
        self.assertIn('guard phase == .unlocked else { return }', sync)
        self.assertLess(sync.index('VaultDerivation.copies'), sync.index('try boundary.repair'))

    def test_entries_fullscreen_lock_and_window_shield(self):
        root = text('PhotoMaid/App/RootView.swift')
        self.assertIn('.fullScreenCover(isPresented: $vault.isPresented', root)
        self.assertIn('VaultRootView().environment(app)', root)
        self.assertIn('vault.lock()', root)
        self.assertIn('cover.windowLevel = .alert + 1', root)
        self.assertIn('PrivacyCover.show()', root)
        self.assertIn('PrivacyCover.hide()', root)
        self.assertIn('VaultStore.shared.present()', text('PhotoMaid/Features/Settings/SettingsView.swift'))
        self.assertIn('VaultStore.shared.present()', text('PhotoMaid/Features/Today/TodayView.swift'))
        self.assertIn('openFromHiddenEntry()', text('PhotoMaid/Features/Today/TodayView.swift'))

    def test_public_reads_metadata_backup_and_derived_outputs(self):
        self.assertIn('guard !VaultConcealment.shared.isConcealed(id)', body('PhotoMaid/Infrastructure/PhotoLibrary/PhotoLibraryService.swift', 'static func phAsset('))
        app = text('PhotoMaid/App/AppModel.swift')
        for needle in ['backup.basket = organize.basket.filter(visible)', 'backup.hiddenMedia = settings.hiddenMedia.filter(visible)',
                       'records: state.records.filter', 'events: state.events.filter', 'snapshot.byID = snapshot.byID.filter',
                       'VaultDerivation.copies(of: roots, records: records)', 'previews.forgetCache()', 'ThumbnailLoader.shared.clear()']:
            self.assertIn(needle, app)
        self.assertIn('candidate.fileConcealmentKeys', text('PhotoMaid/Infrastructure/Vault/VaultStore.swift'))
        self.assertIn('VaultSnapshot.fileConcealmentKey', text('PhotoMaid/Infrastructure/LocalFiles/FileIndex.swift'))
        self.assertIn('sources: sources ?? original.map', text('PhotoMaid/Features/Editor/EditSaver.swift'))
        self.assertIn('sources: value.items.map', text('PhotoMaid/Features/Studio/CollageView.swift'))
        self.assertIn('sources: project.clips.map', text('PhotoMaid/Features/Studio/MovieView.swift'))
        self.assertIn('sourceImages', text('PhotoMaid/Features/Studio/CollageView.swift'))
        self.assertIn('withAnalysisAccess', text('PhotoMaid/Features/Common/MediaShare.swift'))
        self.assertIn('isPublic(url)', body('PhotoMaid/Infrastructure/LocalFiles/ConnectedSources.swift', 'static func safeURL('))
        self.assertIn('guard boundary.analysisReady else { return false }', body('PhotoMaid/Infrastructure/LocalFiles/ConnectedSources.swift', 'static func isPublic('))
        self.assertIn('urls.filter(FileScanner.isPublic)', text('PhotoMaid/Features/Files/ReceivedView.swift'))
        self.assertIn('visibilityRevision == boundary.revision', app)
        self.assertIn('sources: [id]', text('PhotoMaid/Infrastructure/Editing/BatchProcessor.swift'))
        self.assertIn('visibilityRevision == VaultConcealment.shared.revision', text('PhotoMaid/Features/Cleanup/DuplicatesView.swift'))
        self.assertIn('onCancel: { job.cancel() }', text('PhotoMaid/Features/Cleanup/DuplicatesView.swift'))

    def test_deletion_evidence_does_not_confuse_privacy_with_absence(self):
        deletion = body('PhotoMaid/Infrastructure/PhotoLibrary/PhotoLibraryService.swift', 'func delete(ids:')
        self.assertIn('let submittedIDs = Set(assets.map(\\.localIdentifier))', deletion)
        self.assertIn('guard access == .authorized else { return .partial(removed: []) }', deletion)
        self.assertIn('submittedIDs.subtracting(stillThere)', deletion)
        self.assertNotIn('self.assets(ids:', deletion)

    def test_localization_has_all_vault_languages_without_ads(self):
        values = json.loads(text('PhotoMaid/Resources/ios_strings.json'))
        keys = [k for k in values if k.startswith(('vault_', 'vault2_'))]
        self.assertGreater(len(keys), 150)
        languages = set(values['vault_title'])
        self.assertEqual(len(languages), 16)
        for key in keys:
            self.assertEqual(set(values[key]), languages, key)
            self.assertFalse(key.startswith('vault_ad_'))
        for key in ['NSFaceIDUsageDescription', 'NSMicrophoneUsageDescription']:
            self.assertEqual(set(values['_infoPlist'][key]), languages)

if __name__ == '__main__':
    unittest.main(verbosity=2)
