import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release_state', Path(__file__).parents[1] / 'release_state.py')
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)


class ReleaseEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'repository'
        self.directory = self.root / '.context/releases/ios/1.2.3'
        self.directory.mkdir(parents=True)
        self.private = Path(self.temp.name) / 'private'
        self.environment = patch.dict(os.environ, SNAPWELL_RELEASE_STATE_DIR=str(self.private))
        self.environment.start(); self.addCleanup(self.environment.stop)
        self.receipt = {'uploaded': True, 'build_id': 'build', 'version_id': 'version'}
        self.audit = {'notes_verified': True, 'build_id': 'build', 'version_id': 'version',
                      'version_state': 'WAITING_FOR_REVIEW', 'release_type': 'AFTER_APPROVAL'}
        for name, data in [('receipt.json', self.receipt), ('submission.json', {'id': 'review'}),
                           ('submission-audit.json', self.audit)]:
            (self.directory / name).write_text(json.dumps(data))

    def test_private_atomic_writes_and_backup_survive_new_workspace(self):
        state.backup(self.directory, self.root)
        saved = self.private / 'ios/1.2.3'
        self.assertEqual(stat.S_IMODE(saved.stat().st_mode), 0o700)
        for name in state.EVIDENCE:
            self.assertEqual(stat.S_IMODE((saved / name).stat().st_mode), 0o600)
            (self.directory / name).unlink()
        state.restore(self.directory, self.root)
        self.assertEqual(json.loads((self.directory / 'receipt.json').read_text()), self.receipt)

    def test_restore_does_not_mix_local_attempts_or_overwrite_receipts(self):
        state.backup(self.directory, self.root)
        (self.directory / 'receipt.json').write_text('current attempt')
        state.restore(self.directory, self.root)
        self.assertEqual((self.directory / 'receipt.json').read_text(), 'current attempt')
        (self.directory / 'receipt.json').unlink()
        with self.assertRaisesRegex(RuntimeError, 'Partial local'):
            state.restore(self.directory, self.root)

    def test_cleanup_only_removes_known_exports_after_backing_up_evidence(self):
        (self.directory / 'offline-export').mkdir()
        (self.directory / 'offline-export/package.ipa').write_bytes(b'disposable')
        for name in ('archive-upload.log', 'unrelated.txt'):
            (self.directory / name).write_text('keep')
        archive = self.root / 'ios/build/Snapwell.xcarchive'
        archive.mkdir(parents=True)
        with patch.object(state, 'backup', wraps=state.backup) as backup:
            removed = state.cleanup(self.directory, self.root, self.receipt, self.audit)
            backup.assert_called_once()
        self.assertEqual(removed, ['offline-export'])
        self.assertTrue(archive.exists())
        self.assertTrue((self.directory / 'archive-upload.log').exists())
        self.assertTrue((self.directory / 'unrelated.txt').exists())
        self.assertTrue((self.private / 'ios/1.2.3/receipt.json').exists())
        self.assertEqual(state.cleanup(self.directory, self.root, self.receipt, self.audit), [])

    def test_cleanup_dry_run_has_no_writes_or_deletions(self):
        (self.directory / 'temporary').mkdir()
        with patch.object(state, 'backup') as backup:
            self.assertEqual(state.cleanup(self.directory, self.root, self.receipt, self.audit, dry_run=True), ['temporary'])
            backup.assert_not_called()
        self.assertTrue((self.directory / 'temporary').exists())
        self.assertFalse(self.private.exists())

    def test_failed_audit_backup_or_symlink_prevents_cleanup(self):
        target = self.directory / 'temporary'
        target.mkdir()
        for bad in (dict(self.audit, notes_verified=False), dict(self.audit, build_id='other'),
                    dict(self.audit, version_state='PREPARE_FOR_SUBMISSION')):
            with self.assertRaises(RuntimeError):
                state.cleanup(self.directory, self.root, self.receipt, bad)
        with patch.object(state, 'backup', side_effect=OSError('storage unavailable')), self.assertRaises(OSError):
            state.cleanup(self.directory, self.root, self.receipt, self.audit)
        self.assertTrue(target.exists())
        target.rmdir()
        outside = Path(self.temp.name) / 'unrelated'
        outside.mkdir()
        target.symlink_to(outside)
        with self.assertRaisesRegex(RuntimeError, 'symlinked'):
            state.cleanup(self.directory, self.root, self.receipt, self.audit)
        self.assertTrue(outside.exists())

    def test_backup_does_not_overwrite_another_attempt_or_lose_upload_success(self):
        state.backup(self.directory, self.root)
        (self.directory / 'receipt.json').write_text(json.dumps(dict(self.receipt, commit='different')))
        with self.assertRaisesRegex(RuntimeError, 'different release attempt'):
            state.backup(self.directory, self.root)
        (self.directory / 'receipt.json').write_text(json.dumps(dict(self.receipt, uploaded=False)))
        with self.assertRaisesRegex(RuntimeError, 'different release attempt'):
            state.backup(self.directory, self.root)

    def test_durable_private_state_cannot_be_written_into_repository(self):
        with patch.dict(os.environ, SNAPWELL_RELEASE_STATE_DIR=str(self.root / 'private')):
            with self.assertRaisesRegex(RuntimeError, 'outside the repository'):
                state.backup(self.directory, self.root)
