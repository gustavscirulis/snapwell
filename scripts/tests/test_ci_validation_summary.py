import importlib.util
import tempfile
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('ci_summary', Path(__file__).parents[1] / 'ci_validation_summary.py')
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class PublicEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.report = {'suite': 'all', 'platforms': ['ios'], 'results': [
            {'name': name, 'status': 'passed', 'input_fingerprint': 'b' * 64,
             'complete_native_suite': True,
             'log': 'private local path', 'account': 'private account'}
            for name in ('tooling-python', 'tooling-swift', 'core', 'ios')]}
        self.native = {'ios': {'totalTestCount': 12, 'passedTests': 12, 'failedTests': 0, 'skippedTests': 0,
                               'deviceIdentifier': 'private device', 'testFailures': [], 'hostName': 'private host'}}

    def test_export_drops_all_unrecognized_personal_and_runtime_fields(self):
        data = summary.sanitized(self.report, self.native, 'a' * 40)
        self.assertNotIn('private', str(data))
        self.assertEqual(set(data), {'source_commit', 'headless', 'native', 'native_fingerprints'})
        self.assertEqual(set(data['native']['ios']), set(summary.COUNTS))

    def test_failure_diagnostics_expose_only_known_suite_states(self):
        self.report['results'][0].update(status='failed', error='private failure text')
        self.report['results'] += [{'name': 'private name', 'status': 'failed'},
                                   {'name': 'macos', 'status': 'private status'}]
        data = summary.diagnostics(self.report)
        self.assertEqual(data['suites']['tooling-python'], 'failed')
        self.assertNotIn('private', str(data))

    def test_compiler_diagnostics_drop_absolute_paths_source_and_error_text(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'ios.log'
            path.write_text('/workspace/project/ios/Snapwell/MainView.swift:42:7: error: private failure text\nprivate source line\n')
            self.report['results'][-1].update(status='failed', log=str(path))
            data = summary.diagnostics(self.report)
        self.assertEqual(data['compiler_error_locations'], [{'file': 'ios/Snapwell/MainView.swift', 'line': 42, 'column': 7}])
        self.assertNotIn('private', str(data))
        self.assertNotIn('/workspace', str(data))

    def test_skips_failures_missing_suites_and_zero_tests_are_failures(self):
        for counts in ({'skippedTests': 1}, {'failedTests': 1}, {'totalTestCount': 0}, {'passedTests': 11}):
            with self.subTest(counts=counts):
                native = {'ios': {**self.native['ios'], **counts}}
                with self.assertRaises(RuntimeError):
                    summary.sanitized(self.report, native, 'a' * 40)
        self.report['results'].pop()
        with self.assertRaisesRegex(RuntimeError, 'incomplete'):
            summary.sanitized(self.report, self.native, 'a' * 40)

    def test_partial_native_run_cannot_export_full_suite_evidence(self):
        self.report['results'][-1]['complete_native_suite'] = False
        with self.assertRaisesRegex(RuntimeError, 'Partial native selection'):
            summary.sanitized(self.report, self.native, 'a' * 40)
