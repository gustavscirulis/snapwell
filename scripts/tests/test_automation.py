import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from scripts.tests.git_environment import git_fixture_environment

spec = importlib.util.spec_from_file_location('automation', Path(__file__).parents[1] / 'automation.py')
automation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(automation)


class AutomationTests(unittest.TestCase):
    def test_shared_changes_select_both_platforms(self):
        self.assertEqual(automation.affected_platforms(['Shared/Sync/ICloudFile.swift']), ['ios', 'macos'])
        self.assertEqual(automation.affected_platforms(['ios/Snapwell/App.swift']), ['ios'])
        self.assertEqual(automation.affected_platforms(['CLAUDE.md', 'docs/testing.md', 'site/app/page.tsx']), [])

    def test_cli_reuses_headless_by_default_and_allows_fresh(self):
        for flags, expected in (([], True), (["--reuse-passing"], True), (["--fresh"], False)):
            with self.subTest(flags=flags), patch.object(automation.sys, 'argv', ['automation.py', 'test', *flags]), \
                 patch.object(automation, 'test') as check:
                self.assertEqual(automation.main(), 0)
                self.assertEqual(check.call_args.args[0].reuse_passing, expected)

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


class AppleHelperTests(unittest.TestCase):
    def test_build_and_api_have_separate_timeouts_and_build_once(self):
        with patch.object(automation, '_asc_executable', None), \
             patch.object(automation, 'run', side_effect=['', '{}', '{}']) as command:
            automation.asc('status', 'ios')
            automation.asc('status', 'macos')
        self.assertEqual(command.call_count, 3)
        self.assertEqual(command.call_args_list[0].args[0][:2], ['swift', 'build'])
        self.assertEqual(command.call_args_list[0].kwargs['timeout'], 600)
        self.assertEqual(command.call_args_list[1].kwargs['timeout'], 180)
        self.assertEqual(command.call_args_list[1].args[0][1:], ['status', '--platform', 'ios'])


class HeadlessReuseTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(git_fixture_environment())
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.context = self.root / '.context'
        self.context.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        for name in ('macos/App.swift', 'ios/App.swift', 'Shared/Model.swift',
                     'Tests/Fixtures/media.png', 'scripts/automation.py', 'tools/Package.swift',
                     '.githooks/pre-commit', 'docs/testing.md'):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('original\n')
        (self.root / '.gitignore').write_text('.context/\n')
        subprocess.run(['git', 'add', '.'], cwd=self.root, check=True)
        original_run = automation.run
        self.swift_version = 'Swift test toolchain'
        def local_run(command, **kwargs):
            if command == ['swift', '--version']:
                return self.swift_version
            return original_run(command, **kwargs)
        for mock in (patch.object(automation, 'ROOT', self.root),
                     patch.object(automation, 'CONTEXT', self.context),
                     patch.object(automation, 'run', side_effect=local_run)):
            mock.start()
            self.addCleanup(mock.stop)
        self.args = argparse.Namespace(staged=False, reuse_passing=True)

    def record(self, result, label='previous'):
        path = self.context / 'testing' / label / 'summary.json'
        automation.write_json(path, {'suite': 'all', 'results': [result]})
        return path

    def passed(self, name='core'):
        return automation.headless_check(['python3', '-c', 'print("verified")'],
                                         self.context / 'testing/original', name,
                                         argparse.Namespace(staged=False, reuse_passing=False))

    def test_unchanged_full_run_result_is_reused_for_staged_commit(self):
        result = self.passed()
        report = self.record(result)
        self.args.staged = True
        with patch.object(automation, 'logged') as logged:
            reused = automation.headless_check([], self.context / 'next', 'core', self.args)
        logged.assert_not_called()
        self.assertEqual(reused['status'], 'passed')
        self.assertEqual(reused['log'], result['log'])
        self.assertEqual(reused['reused_from'], str(report))

    def test_default_command_reuses_agent_results_during_terminal_handoff(self):
        result = self.passed()
        self.record(result)
        with patch.object(automation, 'logged') as logged:
            reused = automation.headless_check([], self.context / 'next', 'core',
                                               argparse.Namespace(staged=False))
        logged.assert_not_called()
        self.assertEqual(reused['log'], result['log'])

    def test_full_command_reuses_headless_but_still_runs_native_tests(self):
        for name in ('tooling-python', 'tooling-swift', 'core'):
            self.record(self.passed(name), label=name)
        original_run = automation.run
        def native_setup(command, **kwargs):
            if command[0] in ('xcodegen', 'bash'):
                return ''
            return original_run(command, **kwargs)
        args = argparse.Namespace(platform='macos', suite='all', only=None,
                                  staged=False, dry_run=False, simulator=None)
        with patch.object(automation, 'run', side_effect=native_setup), \
             patch.object(automation, 'native_lock', return_value=contextlib.nullcontext()), \
             patch.object(automation.native_validation, 'record_pass', return_value={'counts': {}}), \
             patch.object(automation.native_validation, 'pending'), \
             patch.object(automation, 'logged', return_value={'name': 'macos', 'status': 'passed'}) as logged:
            automation.test(args)
        logged.assert_called_once()
        self.assertEqual(logged.call_args.args[0][:2], ['xcodebuild', 'test'])
        reports = list(self.context.glob('testing/*/summary.json'))
        results = [r for path in reports for r in json.loads(path.read_text())['results']]
        self.assertEqual(sum('reused_from' in r for r in results), 3)

    def test_relevant_edits_additions_and_deletions_invalidate_result(self):
        result = self.passed()
        self.record(result)
        for change in ('content', 'addition', 'deletion', 'mode', 'fixture', 'runner'):
            with self.subTest(change=change):
                path = self.root / 'macos/App.swift'
                original_stat = path.stat()
                if change == 'content':
                    path.write_text('modified\n')
                    os.utime(path, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
                elif change == 'addition':
                    path = self.root / 'ios/New.swift'
                    path.write_text('new')
                elif change == 'deletion':
                    path.unlink()
                elif change == 'mode':
                    path.chmod(0o755)
                else:
                    path = self.root / ('Tests/Fixtures/media.png' if change == 'fixture' else 'scripts/automation.py')
                    path.write_text('modified\n')
                fingerprint = automation.headless_fingerprint('core')
                self.assertIsNone(automation.passing_headless_result('core', fingerprint))
                if change == 'addition':
                    path.unlink()
                else:
                    path.write_text('original\n')
                    path.chmod(0o644)

    def test_docs_do_not_invalidate_results_and_native_edits_leave_tooling_valid(self):
        core = automation.headless_fingerprint('core')
        tools = automation.headless_fingerprint('tooling-python')
        (self.root / 'docs/testing.md').write_text('new docs')
        self.assertEqual(automation.headless_fingerprint('core'), core)
        (self.root / 'Shared/Model.swift').write_text('new model')
        self.assertNotEqual(automation.headless_fingerprint('core'), core)
        self.assertEqual(automation.headless_fingerprint('tooling-python'), tools)

    def test_version_only_changes_do_not_invalidate_headless_core(self):
        path = self.root / 'macos/project.yml'
        path.write_text('MARKETING_VERSION: "1.2.3"\nCURRENT_PROJECT_VERSION: 9\n')
        before = automation.headless_fingerprint('core')
        path.write_text('MARKETING_VERSION: "2.0.0"\nCURRENT_PROJECT_VERSION: 15\n')
        self.assertEqual(automation.headless_fingerprint('core'), before)
        path.write_text(path.read_text() + 'OTHER_SWIFT_FLAGS: -DCHANGED\n')
        self.assertNotEqual(automation.headless_fingerprint('core'), before)

    def test_toolchain_changes_invalidate_results(self):
        before = automation.headless_fingerprint('core')
        self.swift_version = 'Different Swift version'
        self.assertNotEqual(automation.headless_fingerprint('core'), before)

    def test_newer_failure_cannot_reuse_older_pass(self):
        result = self.passed()
        previous = self.record(result, 'older')
        os.utime(previous, ns=(1, 1))
        for status in ('failed', 'timed_out', 'unavailable', 'inputs_changed'):
            with self.subTest(status=status):
                self.record(dict(result, status=status), 'newer')
                self.assertIsNone(automation.passing_headless_result('core', result['input_fingerprint']))

    def test_missing_evidence_and_legacy_reports_cannot_be_reused(self):
        result = self.passed()
        for invalid in (dict(result, log='missing.log'),
                        {key: value for key, value in result.items() if key != 'input_fingerprint'}):
            self.record(invalid)
            self.assertIsNone(automation.passing_headless_result('core', result['input_fingerprint']))
        (self.context / 'testing/previous/summary.json').write_text('incomplete JSON')
        self.assertIsNone(automation.passing_headless_result('core', result['input_fingerprint']))

    def test_editing_inputs_during_a_check_invalidates_success(self):
        command = ['python3', '-c', f'from pathlib import Path; Path({str(self.root / "macos/App.swift")!r}).write_text("changed")']
        result = automation.headless_check(command, self.context / 'testing/run', 'core', self.args)
        self.assertEqual(result['status'], 'inputs_changed')
        self.record(result)
        self.assertIsNone(automation.passing_headless_result('core', automation.headless_fingerprint('core')))

    def test_partially_staged_or_untracked_inputs_reject_cached_pass(self):
        self.record(self.passed())
        self.args.staged = True
        for name in ('macos/App.swift', 'macos/New.swift'):
            with self.subTest(name=name):
                path = self.root / name
                path.write_text('unstaged')
                with patch.object(automation, 'logged') as logged:
                    with self.assertRaisesRegex(RuntimeError, 'Stage or stash'):
                        automation.headless_check([], self.context / 'next', 'core', self.args)
                    logged.assert_not_called()
                if name.endswith('New.swift'):
                    path.unlink()
                else:
                    path.write_text('original\n')

    def test_fresh_request_reruns_previously_passing_checks(self):
        self.record(self.passed())
        with patch.object(automation, 'logged', return_value={'name': 'core', 'status': 'passed'}) as logged:
            automation.headless_check([], self.context / 'next', 'core',
                                      argparse.Namespace(staged=False, reuse_passing=False))
        logged.assert_called_once()


class ReleasePipelineTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(automation.native_validation, 'passing_evidence', return_value=None))
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
        self.private = tempfile.TemporaryDirectory()
        self.addCleanup(self.private.cleanup)
        private_environment = patch.dict(os.environ, SNAPWELL_RELEASE_STATE_DIR=self.private.name)
        private_environment.start(); self.addCleanup(private_environment.stop)
        audit = patch.object(automation, 'verify_submission', return_value={
            'notes_verified': True, 'build_id': 'build', 'version_id': 'version',
            'version_state': 'WAITING_FOR_REVIEW', 'release_type': 'AFTER_APPROVAL'})
        audit.start(); self.addCleanup(audit.stop)

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

    def test_upload_handoff_does_not_change_metadata_or_repeat_validated_work(self):
        self.save_upload_receipt()
        self.args.action = 'upload'
        with patch.object(automation, 'asc', return_value={'versions': [], 'builds': [self.build]}) as apple, \
             patch.object(automation, 'test') as tests, patch.object(automation.subprocess, 'run') as upload:
            automation.release(self.args)
        self.assertEqual([call.args[0] for call in apple.call_args_list], ['status'])
        tests.assert_not_called()
        upload.assert_not_called()
        self.assertEqual(json.loads((self.directory / 'release.json').read_text())['status'], 'prepared')
        self.assertEqual(json.loads(self.receipt.read_text())['build_id'], 'build')

    def test_confirmed_upload_not_yet_visible_is_never_uploaded_twice(self):
        self.save_upload_receipt()
        with patch.object(automation, 'asc', return_value={'versions': [], 'builds': []}), \
             patch.object(automation, 'test') as tests, patch.object(automation.subprocess, 'run') as upload:
            with self.assertRaisesRegex(RuntimeError, 'still processing'):
                automation.release(self.args)
        tests.assert_not_called()
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

    def test_failed_readback_does_not_record_success_or_clean_evidence(self):
        self.save_upload_receipt()
        def apple(command, *args, **kwargs):
            if command == 'stage':
                return {'version_id': 'version'}
            if command == 'submit':
                return {'submission': {'id': 'review'}}
            return {'versions': [], 'builds': [self.build]}
        with patch.object(automation, 'asc', side_effect=apple), patch.object(automation, 'test'), \
             patch.object(automation, 'verify_submission', side_effect=RuntimeError('read-back mismatch')), \
             patch.object(automation.release_state, 'cleanup') as cleanup:
            with self.assertRaisesRegex(RuntimeError, 'read-back mismatch'):
                automation.release(self.args)
            cleanup.assert_not_called()
        self.assertEqual(json.loads((self.directory / 'release.json').read_text())['status'], 'prepared')
        self.assertTrue(json.loads(self.receipt.read_text())['uploaded'])



class CoordinatedUploadTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(automation.native_validation, 'passing_evidence', return_value=None))
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.enterContext(patch.object(automation, 'ROOT', self.root))
        self.enterContext(patch.object(automation, 'CONTEXT', self.root / '.context'))
        self.enterContext(patch.object(automation.release_state, 'restore'))
        self.requests = []
        for platform, version in (('macos', '1.2.3'), ('ios', '2.3.4')):
            args = argparse.Namespace(platform=platform, version=version, action='upload',
                                      dry_run=False, locale=None, wait_minutes=0)
            self.requests.append(args)
            path = automation.release_dir(platform, version)
            path.mkdir(parents=True)
            (path / 'release.json').write_text(json.dumps({'status': 'prepared'}))
        self.events = []
        self.enterContext(patch.object(automation, 'run', side_effect=lambda command, **kwargs:
                                     'source\n' if command[1] == 'rev-parse' else ''))
        self.preview = self.enterContext(patch.object(automation, 'release', side_effect=lambda args:
                                                     self.events.append(('preview', args.platform, args.dry_run))))
        self.upload = self.enterContext(patch.object(automation, 'release_with_backup', side_effect=lambda args:
                                                    self.events.append(('upload', args.platform, args.validated_commit))))
        self.tests = self.enterContext(patch.object(automation, 'test', side_effect=lambda args:
                                                   self.events.append(('test', args.platform))))

    def test_independent_versions_require_committed_prepared_manifests(self):
        args = argparse.Namespace(platform='all', version=None, action='upload')
        with patch.object(automation, 'local_version', side_effect=['1.2.3', '2.3.4']):
            requests = automation.release_requests(args)
        self.assertEqual([(item.platform, item.version) for item in requests],
                         [('macos', '1.2.3'), ('ios', '2.3.4')])
        args.version = '1.2.3'
        with self.assertRaisesRegex(RuntimeError, 'own version'):
            automation.release_requests(args)

    def test_both_platforms_pass_before_either_upload_and_are_not_retested(self):
        automation.upload_all(self.requests)
        self.assertEqual(self.events, [('preview', 'macos', True), ('preview', 'ios', True),
                                       ('test', 'all'), ('upload', 'macos', 'source'), ('upload', 'ios', 'source')])

    def test_verified_pr_evidence_avoids_native_rerun_for_version_only_handoff(self):
        with patch.object(automation.native_validation, 'passing_evidence',
                          return_value={'counts': {'passedTests': 12}}):
            automation.upload_all(self.requests)
        self.tests.assert_not_called()
        self.assertEqual(self.upload.call_count, 2)

    def test_failed_validation_stops_both_uploads(self):
        self.tests.side_effect = RuntimeError('native failure')
        with self.assertRaisesRegex(RuntimeError, 'native failure'):
            automation.upload_all(self.requests)
        self.upload.assert_not_called()

    def test_dry_run_and_receipted_resume_do_not_repeat_native_tests(self):
        for request in self.requests:
            request.dry_run = True
        automation.upload_all(self.requests)
        self.tests.assert_not_called()
        self.upload.assert_not_called()
        for request in self.requests:
            request.dry_run = False
            path = automation.CONTEXT / 'releases' / request.platform / request.version
            path.mkdir(parents=True)
            (path / 'receipt.json').write_text('{"uploaded":true}')
        automation.upload_all(self.requests)
        self.tests.assert_not_called()
        self.assertEqual(self.upload.call_count, 2)

    def test_source_change_after_first_upload_stops_second_and_preserves_progress(self):
        state = {'commit': 'source'}
        def git(command, **kwargs):
            return state['commit'] if command[1] == 'rev-parse' else ''
        def uploaded(args):
            self.events.append(('uploaded', args.platform))
            state['commit'] = 'another source'
        self.upload.side_effect = uploaded
        with patch.object(automation, 'run', side_effect=git):
            with self.assertRaisesRegex(RuntimeError, 'between platform uploads'):
                automation.upload_all(self.requests)
        self.assertEqual(self.upload.call_count, 1)
        self.assertEqual(self.events[-1], ('uploaded', 'macos'))


class SubmissionOnlyTests(unittest.TestCase):
    # Use a real temporary Git repository to verify uploaded-source comparisons.
    def setUp(self):
        self.enterContext(git_fixture_environment())
        ReleasePipelineTests.setUp(self)
        self.run_patch.stop()
        self.args.action = 'submit'
        self.root = automation.ROOT
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['git', 'config', 'commit.gpgsign', 'false'], cwd=self.root, check=True)
        (self.root / '.gitignore').write_text('.context/\n')
        (self.root / 'ios').mkdir()
        (self.root / 'ios/App.swift').write_text('uploaded source')
        subprocess.run(['git', 'add', '.'], cwd=self.root, check=True)
        subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                        'commit', '-qm', 'Prepared'], cwd=self.root, check=True)
        self.commit = automation.run(['git', 'rev-parse', 'HEAD'], capture=True, cwd=self.root).strip()
        # automation.run's cwd default is bound at import time; route calls to the fixture.
        original = automation.run
        def run_here(args, **kwargs):
            return original(args, **dict(kwargs, cwd=self.root))
        self.local_run = patch.object(automation, 'run', side_effect=run_here)
        self.local_run.start()
        self.addCleanup(self.local_run.stop)
        self.save_upload_receipt()

    def save_upload_receipt(self):
        automation.write_json(self.receipt, dict(self.manifest, commit=self.commit, uploaded=True,
            notes_sha256=automation.hashlib.sha256(self.notes.encode()).hexdigest()))

    def apple(self, command, *args, **kwargs):
        if command == 'stage':
            return {'version_id': 'version'}
        if command == 'submit':
            return {'submission': {'id': 'review'}}
        return {'versions': [], 'builds': [self.build]}

    def test_submit_does_not_test_archive_or_upload_and_preserves_source(self):
        # Updating tooling and another platform's record must not invalidate an upload.
        (self.root / 'scripts').mkdir()
        (self.root / 'scripts/automation.py').write_text('new tooling')
        with patch.object(automation, 'asc', side_effect=self.apple), \
             patch.object(automation, 'test') as tests, \
             patch.object(automation, 'logged') as archive:
            automation.release(self.args)
            tests.assert_not_called()
            archive.assert_not_called()
        result = json.loads((self.directory / 'release.json').read_text())
        self.assertEqual(result['source_commit'], self.commit)
        self.assertEqual(result['status'], 'submitted')
        self.assertEqual(result['build_id'], 'build')

    def test_submit_rejects_missing_receipt_changed_notes_and_native_inputs(self):
        for case, message in [('missing', 'original successful'), ('notes', 'notes changed'),
                              ('native', 'Native inputs differ'), ('new-native', 'Native inputs differ')]:
            with self.subTest(case=case):
                self.save_upload_receipt()
                (self.directory / 'en-US.txt').write_text(self.notes)
                (self.root / 'ios/App.swift').write_text('uploaded source')
                new = self.root / 'ios/New.swift'
                new.unlink(missing_ok=True)
                if case == 'missing':
                    self.receipt.unlink()
                elif case == 'notes':
                    (self.directory / 'en-US.txt').write_text('• New notes.\n• Different notes.\n')
                elif case == 'native':
                    (self.root / 'ios/App.swift').write_text('changed source')
                else:
                    new.write_text('new source')
                with patch.object(automation, 'asc', side_effect=self.apple) as apple, \
                     self.assertRaisesRegex(RuntimeError, message):
                    automation.release(self.args)
                self.assertEqual([c.args[0] for c in apple.call_args_list], ['status'])

    def test_submit_requires_exact_uploaded_platform_version_and_build(self):
        for field, value in [('platform', 'macos'), ('version', '1.0.0'), ('build', 10), ('uploaded', False)]:
            with self.subTest(field=field):
                self.save_upload_receipt()
                record = json.loads(self.receipt.read_text())
                record[field] = value
                automation.write_json(self.receipt, record)
                with patch.object(automation, 'asc', side_effect=self.apple), \
                     self.assertRaisesRegex(RuntimeError, 'does not confirm'):
                    automation.release(self.args)

    def test_submit_never_uploads_when_receipted_build_is_missing(self):
        with patch.object(automation, 'asc', return_value={'versions': [], 'builds': []}), \
             self.assertRaisesRegex(RuntimeError, 'never builds or uploads'):
            automation.release(self.args)

    def test_submit_recovers_after_remote_submission_without_staging_again(self):
        record = json.loads(self.receipt.read_text())
        record['version_id'] = 'version'
        automation.write_json(self.receipt, record)
        automation.write_json(self.receipt.parent / 'submission.json',
                              {'version_id': 'version', 'submission_id': 'review'})
        remote = {'builds': [self.build], 'versions': [{'id': 'version',
                  'attributes': {'versionString': '1.2.3', 'appVersionState': 'WAITING_FOR_REVIEW'},
                  'relationships': {'build': {'data': {'id': 'build'}}}}]}
        with patch.object(automation, 'asc', return_value=remote) as apple:
            automation.release(self.args)
        self.assertEqual([c.args[0] for c in apple.call_args_list], ['status'])
        self.assertEqual(json.loads((self.directory / 'release.json').read_text())['submission_id'], 'review')


if __name__ == '__main__':
    unittest.main()
