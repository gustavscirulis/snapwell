import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('ci_summary', Path(__file__).parents[1] / 'ci_validation_summary.py')
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)


class PublicEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.report = {'suite': 'all', 'platforms': ['ios'], 'results': [
            {'name': name, 'status': 'passed', 'log': 'private local path', 'account': 'private account'}
            for name in ('tooling-python', 'tooling-swift', 'core', 'ios')]}
        self.native = {'ios': {'totalTestCount': 12, 'passedTests': 12, 'failedTests': 0, 'skippedTests': 0,
                               'deviceIdentifier': 'private device', 'testFailures': [], 'hostName': 'private host'}}

    def test_export_drops_all_unrecognized_personal_and_runtime_fields(self):
        data = summary.sanitized(self.report, self.native, 'a' * 40)
        self.assertNotIn('private', str(data))
        self.assertEqual(set(data), {'source_commit', 'headless', 'native'})
        self.assertEqual(set(data['native']['ios']), set(summary.COUNTS))

    def test_failure_diagnostics_expose_only_known_suite_states(self):
        self.report['results'][0].update(status='failed', error='private failure text')
        self.report['results'] += [{'name': 'private name', 'status': 'failed'},
                                   {'name': 'macos', 'status': 'private status'}]
        data = summary.diagnostics(self.report)
        self.assertEqual(data['suites']['tooling-python'], 'failed')
        self.assertNotIn('private', str(data))

    def test_skips_failures_missing_suites_and_zero_tests_are_failures(self):
        for counts in ({'skippedTests': 1}, {'failedTests': 1}, {'totalTestCount': 0}, {'passedTests': 11}):
            with self.subTest(counts=counts):
                native = {'ios': {**self.native['ios'], **counts}}
                with self.assertRaises(RuntimeError):
                    summary.sanitized(self.report, native, 'a' * 40)
        self.report['results'].pop()
        with self.assertRaisesRegex(RuntimeError, 'incomplete'):
            summary.sanitized(self.report, self.native, 'a' * 40)
