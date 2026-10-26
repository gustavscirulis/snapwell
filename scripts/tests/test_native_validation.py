import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch
import zipfile

from scripts import native_validation as validation
from scripts.tests.git_environment import git_fixture_environment


class NativeReuseTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(git_fixture_environment())
        checkout = tempfile.TemporaryDirectory()
        private = tempfile.TemporaryDirectory()
        self.addCleanup(checkout.cleanup)
        self.addCleanup(private.cleanup)
        self.root = Path(checkout.name)
        self.enterContext(patch.dict(os.environ, SNAPWELL_VALIDATION_STATE_DIR=private.name))
        for name, data in {
            'ios/Snapwell.xcodeproj/project.pbxproj': 'MARKETING_VERSION = 1.2.3;\nCURRENT_PROJECT_VERSION = 9;\nCONFIG = Automation;\n',
            'ios/App.swift': 'let app = 1\n', 'macos/project.yml': 'MARKETING_VERSION: "1.2.3"\nCURRENT_PROJECT_VERSION: 9\n',
            'macos/App.swift': 'let app = 1\n', 'Shared/Model.swift': 'let model = 1\n',
            'Tests/fixture.json': '{}\n',
        }.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(data)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        subprocess.run(['git', '-C', str(self.root), 'config', 'commit.gpgsign', 'false'], check=True)
        subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Synthetic',
                        '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'Validated source'], check=True)
        self.commit = validation.git(self.root, 'rev-parse', 'HEAD').decode().strip()
        self.inputs = validation.fingerprint(self.root, 'ios')
        self.counts = dict(totalTestCount=12, passedTests=12, failedTests=0, skippedTests=0)

    def test_version_only_bumps_reuse_exact_app_test_configuration_evidence(self):
        for platform, path in (('ios', 'ios/Snapwell.xcodeproj/project.pbxproj'), ('macos', 'macos/project.yml')):
            before = validation.fingerprint(self.root, platform)
            self.assertEqual(before, validation.fingerprint(self.root, platform, self.commit))
            file = self.root / path
            file.write_text(file.read_text().replace('1.2.3', '2.0.0').replace('9', '15'))
            self.assertEqual(before, validation.fingerprint(self.root, platform))
        validation.save(self.root, 'ios', self.inputs, self.counts)
        self.assertIsNotNone(validation.passing_evidence(self.root, 'ios'))

    def test_source_tests_config_additions_deletions_and_file_modes_invalidate(self):
        for name in ('ios/App.swift', 'Shared/Model.swift', 'Tests/fixture.json', 'ios/Snapwell.xcodeproj/project.pbxproj'):
            file = self.root / name
            original = file.read_bytes()
            file.write_bytes(original + b'changed\n')
            self.assertNotEqual(self.inputs, validation.fingerprint(self.root, 'ios'))
            file.write_bytes(original)
        file = self.root / 'ios/New.swift'
        file.write_text('new source')
        self.assertNotEqual(self.inputs, validation.fingerprint(self.root, 'ios'))
        file.unlink()
        file = self.root / 'ios/App.swift'
        file.chmod(0o755)
        self.assertNotEqual(self.inputs, validation.fingerprint(self.root, 'ios'))
        file.chmod(0o644)
        file.unlink()
        self.assertNotEqual(self.inputs, validation.fingerprint(self.root, 'ios'))

    def test_actual_result_bundle_counts_are_required_and_private_fields_are_dropped(self):
        raw = dict(self.counts, hostName='private host', deviceIdentifier='private device')
        with patch.object(validation.subprocess, 'check_output', return_value=json.dumps(raw).encode()):
            with patch.object(validation, 'fingerprint', return_value=self.inputs):
                validation.record_pass(self.root, 'ios', 'result.xcresult', self.inputs)
        path = validation.cache_path(self.root, 'ios', self.inputs)
        self.assertNotIn('private', path.read_text())
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
        for field, value in (('failedTests', 1), ('skippedTests', 1), ('totalTestCount', 0)):
            with self.assertRaises(RuntimeError):
                validation.save(self.root, 'ios', self.inputs, dict(self.counts, **{field: value}))

    def test_newer_failed_or_incomplete_run_cannot_reuse_or_import_an_older_pass(self):
        validation.save(self.root, 'ios', self.inputs, self.counts)
        earlier = time.time() - 10
        validation.pending(self.root, 'ios', self.inputs)
        with self.assertRaisesRegex(RuntimeError, 'newer native run'):
            validation.passing_evidence(self.root, 'ios')
        with self.assertRaisesRegex(RuntimeError, 'older CI run'):
            validation.save(self.root, 'ios', self.inputs, self.counts, earlier)
        validation.save(self.root, 'ios', self.inputs, self.counts)
        self.assertIsNotNone(validation.passing_evidence(self.root, 'ios'))

    def ci_responses(self, fingerprint=None, conclusion='success'):
        evidence = {'source_commit': self.commit, 'headless': {name: 'passed' for name in
                     ('tooling-python', 'tooling-swift', 'core')}, 'native': {'ios': self.counts},
                    'native_fingerprints': {'ios': fingerprint or self.inputs}}
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as archive:
            archive.writestr('public-validation.json', json.dumps(evidence))
        return [json.dumps({'status': 'completed', 'conclusion': conclusion,
                            'path': '.github/workflows/quality.yml', 'head_sha': self.commit,
                            'updated_at': '2026-01-01T00:00:00Z'}).encode(),
                json.dumps({'artifacts': [{'id': 123, 'name': 'public-validation-123',
                                           'expired': False, 'size_in_bytes': 100}]}).encode(), output.getvalue()]

    def test_ci_import_checks_real_run_source_artifact_and_fingerprint(self):
        with patch.object(validation, 'gh', side_effect=self.ci_responses()):
            validation.import_ci(self.root, 123)
        self.assertEqual(validation.passing_evidence(self.root, 'ios')['counts'], self.counts)
        with patch.object(validation, 'gh', side_effect=self.ci_responses('a' * 64)):
            with self.assertRaisesRegex(RuntimeError, 'fingerprint differs'):
                validation.import_ci(self.root, 123)
        with patch.object(validation, 'gh', side_effect=self.ci_responses(conclusion='failure')):
            with self.assertRaisesRegex(RuntimeError, 'successful'):
                validation.import_ci(self.root, 123)
