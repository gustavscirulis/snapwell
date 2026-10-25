import argparse
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('automation', Path(__file__).parents[1] / 'automation.py')
automation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(automation)


class AutomationTests(unittest.TestCase):
    def test_shared_changes_select_both_platforms(self):
        self.assertEqual(automation.affected_platforms(['Shared/Sync/ICloudFile.swift']), ['ios', 'macos'])
        self.assertEqual(automation.affected_platforms(['ios/Snapwell/App.swift']), ['ios'])
        self.assertEqual(automation.affected_platforms(['CLAUDE.md', 'docs/testing.md', 'site/app/page.tsx']), [])

    def test_failed_commands_are_not_success(self):
        with self.assertRaisesRegex(RuntimeError, 'failed'):
            automation.run(['python3', '-c', 'import sys; sys.exit(7)'], capture=True)

    def test_logging_preserves_failure_and_complete_output(self):
        with tempfile.TemporaryDirectory(dir=automation.CONTEXT) as directory:
            report = automation.logged(['python3', '-c', 'print("failure evidence"); raise SystemExit(9)'], Path(directory), 'failure')
            self.assertEqual(report['status'], 'failed')
            self.assertEqual(report['exit_code'], 9)
            self.assertIn('failure evidence', Path(report['log']).read_text())

    def test_platform_release_history_keeps_shared_changes_pending(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'CHANGELOG.md').write_text('## Unreleased\n### Both\n- [shared-fix] Better sync.\n### macOS\n- [mac-fix] Better hover.\n### iOS\n- [ios-fix] Better gestures.\n## History\n')
            release = root/'releases/macos/1.0.9'
            release.mkdir(parents=True)
            (release/'release.json').write_text(json.dumps({'status': 'submitted', 'changes': [{'id': 'shared-fix'}]}))
            with patch.object(automation, 'ROOT', root):
                self.assertEqual([entry['id'] for entry in automation.pending_changes('macos')], ['mac-fix'])
                self.assertEqual([entry['id'] for entry in automation.pending_changes('ios')], ['shared-fix', 'ios-fix'])

    def test_dry_run_has_no_writes_or_uploads(self):
        args = argparse.Namespace(platform='all', suite='all', only=None, staged=False, dry_run=True)
        with patch.object(automation, 'logged') as logged, patch.object(automation, 'write_json') as write:
            with contextlib.redirect_stdout(io.StringIO()):
                automation.test(args)
            logged.assert_not_called()
            write.assert_not_called()

    def test_core_failure_is_reported_without_accessing_native_services(self):
        args = argparse.Namespace(platform='changed', suite='core', only=None, staged=False, dry_run=False)
        with tempfile.TemporaryDirectory(dir=automation.CONTEXT) as directory:
            context = Path(directory)
            with patch.object(automation, 'CONTEXT', context), patch.object(automation, 'changed_files', return_value=[]), \
                 patch.object(automation, 'logged', return_value={'name': 'core', 'status': 'failed', 'exit_code': 1}), \
                 patch.object(automation, 'native_lock') as lock, patch.object(automation, 'simulator') as simulator:
                with contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(RuntimeError, 'Validation did not pass'):
                    automation.test(args)
                lock.assert_not_called()
                simulator.assert_not_called()
            reports = list(context.glob('testing/*/summary.json'))
            self.assertEqual(len(reports), 1)
            summary = json.loads(reports[0].read_text())
            self.assertEqual(summary['platforms'], [])
            self.assertEqual(summary['results'][0]['status'], 'failed')

    def test_bad_notes_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'notes.txt'
            path.write_text('• Better search.\n• Better imports.\n')
            self.assertEqual(automation.notes_text(path), path.read_text())
            path.write_text('Technical implementation details')
            with self.assertRaises(RuntimeError):
                automation.notes_text(path)

    def test_notes_are_uploaded_without_normalization(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'notes.txt'
            original = '• Faster imports.\n\n• Better search.\n\n'
            path.write_text(original)
            self.assertEqual(automation.notes_text(path), original)

    def test_version_cannot_escape_release_directory(self):
        with self.assertRaises(RuntimeError):
            automation.release_dir('macos', '../../elsewhere')

    def test_release_dry_run_does_not_change_versions(self):
        args = argparse.Namespace(platform='ios', version='1.2.3', locale='en-US', action='prepare', dry_run=True)
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(automation, 'ROOT', Path(directory)), patch.object(automation, 'local_build', return_value=3), \
                 patch.object(automation, 'pending_changes', return_value=[{'id': 'fix', 'text': 'Better search.'}]), \
                 patch.object(automation, 'asc', return_value={'next_build': 9}), patch.object(automation, 'set_version') as version:
                with contextlib.redirect_stdout(io.StringIO()):
                    automation.release(args)
                version.assert_not_called()
                self.assertEqual(list(Path(directory).iterdir()), [])

    def test_native_failure_makes_entire_validation_fail(self):
        args = argparse.Namespace(platform='macos', suite='ui', only=None, staged=False, dry_run=False, simulator=None)
        with tempfile.TemporaryDirectory(dir=automation.CONTEXT) as directory:
            with patch.object(automation, 'CONTEXT', Path(directory)), patch.object(automation, 'run'), \
                 patch.object(automation, 'logged', return_value={'name': 'macos', 'status': 'failed'}):
                with self.assertRaises(RuntimeError):
                    automation.test(args)


class ReleasePipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.root_patch = patch.object(automation, 'ROOT', root)
        self.context_patch = patch.object(automation, 'CONTEXT', root/'.context')
        self.root_patch.start(); self.context_patch.start()
        self.addCleanup(self.root_patch.stop); self.addCleanup(self.context_patch.stop)
        self.directory = root/'releases/ios/1.2.3'
        self.directory.mkdir(parents=True)
        self.notes = '• Faster imports.\n• Better search.\n'
        self.manifest = {'platform': 'ios', 'version': '1.2.3', 'build': 9, 'locale': 'en-US', 'status': 'prepared', 'changes': []}
        automation.write_json(self.directory/'release.json', self.manifest)
        (self.directory/'en-US.txt').write_text(self.notes)
        self.args = argparse.Namespace(platform='ios', version='1.2.3', locale=None, action='publish', dry_run=False, wait_minutes=0)
        self.run_patch = patch.object(automation, 'run', side_effect=lambda args, **kwargs: '' if 'status' in args else 'commit\n')
        self.run_patch.start(); self.addCleanup(self.run_patch.stop)
        self.build = {'id': 'build', 'attributes': {'version': '9', 'processingState': 'VALID', 'snapwellMarketingVersion': '1.2.3'}}
        self.receipt = automation.CONTEXT/'releases/ios/1.2.3/receipt.json'

    def save_upload_receipt(self):
        automation.write_json(self.receipt, {'commit': 'commit', 'notes_sha256': automation.hashlib.sha256(self.notes.encode()).hexdigest(), 'uploaded': True})

    def test_failed_native_tests_prevent_upload_and_metadata_changes(self):
        with patch.object(automation, 'asc', return_value={'versions': [], 'builds': []}) as apple, \
             patch.object(automation, 'test', side_effect=RuntimeError('native tests failed')), \
             patch.object(automation.subprocess, 'run') as upload:
            with self.assertRaisesRegex(RuntimeError, 'native tests failed'):
                automation.release(self.args)
            self.assertEqual([call.args[0] for call in apple.call_args_list], ['status'])
            upload.assert_not_called()

    def test_processing_timeout_resumes_without_upload(self):
        self.save_upload_receipt()
        self.build['attributes']['processingState'] = 'PROCESSING'
        with patch.object(automation, 'asc', return_value={'versions': [], 'builds': [self.build]}) as apple, \
             patch.object(automation, 'test'), patch.object(automation.subprocess, 'run') as upload:
            with self.assertRaisesRegex(RuntimeError, 'still processing'):
                automation.release(self.args)
            self.assertEqual([call.args[0] for call in apple.call_args_list], ['status', 'status'])
            upload.assert_not_called()
            self.assertTrue(json.loads(self.receipt.read_text())['uploaded'])

    def test_resume_stages_exact_notes_and_records_submission(self):
        self.save_upload_receipt()
        def apple(command, *args, **kwargs):
            if command == 'stage':
                self.assertEqual(Path(kwargs['notes']).read_text(), self.notes)
                self.assertEqual(kwargs['build_id'], 'build')
                return {'version_id': 'version'}
            if command == 'submit':
                return {'submission': {'id': 'review'}}
            return {'versions': [], 'builds': [self.build]}
        with patch.object(automation, 'asc', side_effect=apple), patch.object(automation, 'test'), \
             patch.object(automation.subprocess, 'run') as upload:
            automation.release(self.args)
            upload.assert_not_called()
        result = json.loads((self.directory/'release.json').read_text())
        self.assertEqual(result['status'], 'submitted')
        self.assertEqual(result['build_id'], 'build')
        self.assertEqual(result['submission_id'], 'review')

    def test_wrong_marketing_version_is_never_attached(self):
        self.save_upload_receipt()
        self.build['attributes']['snapwellMarketingVersion'] = '0.9.0'
        with patch.object(automation, 'asc', return_value={'versions': [], 'builds': [self.build]}) as apple, patch.object(automation, 'test'):
            with self.assertRaisesRegex(RuntimeError, 'belongs to version'):
                automation.release(self.args)
            self.assertNotIn('stage', [call.args[0] for call in apple.call_args_list])

    def test_unverified_existing_build_is_never_attached(self):
        with patch.object(automation, 'asc', return_value={'versions': [], 'builds': [self.build]}), patch.object(automation, 'test'):
            with self.assertRaisesRegex(RuntimeError, 'without an upload receipt'):
                automation.release(self.args)

    def test_locale_cannot_escape_release_directory(self):
        self.args.locale = '../../bad'
        with self.assertRaisesRegex(RuntimeError, 'locale'):
            automation.release(self.args)

    def test_metadata_error_preserves_resumable_upload(self):
        self.save_upload_receipt()
        def apple(command, *args, **kwargs):
            if command == 'stage':
                raise RuntimeError('Apple metadata rejected')
            return {'versions': [], 'builds': [self.build]}
        with patch.object(automation, 'asc', side_effect=apple), patch.object(automation, 'test'):
            with self.assertRaisesRegex(RuntimeError, 'metadata rejected'):
                automation.release(self.args)
        self.assertTrue(json.loads(self.receipt.read_text())['uploaded'])
        self.assertEqual(json.loads((self.directory/'release.json').read_text())['status'], 'prepared')


if __name__ == '__main__':
    unittest.main()
