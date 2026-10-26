import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from scripts.tests.git_environment import git_fixture_environment

spec = importlib.util.spec_from_file_location('public_content', Path(__file__).parents[1] / 'check_public_content.py')
public = importlib.util.module_from_spec(spec)
spec.loader.exec_module(public)


class ContentRulesTests(unittest.TestCase):
    def test_private_artifacts_are_blocked_even_if_force_added(self):
        for name in ('.context/log.txt', '.env.production', 'keys/AuthKey_TEST.p8', 'signing.p12',
                     'app.mobileprovision', 'foo.xcresult/data', '.conductor/settings.local.toml'):
            with self.subTest(name=name):
                # Bundle directories need to be rejected as path components, too.
                self.assertIn('private-artifact', public.findings(name, b'anything'))

    def test_keys_tokens_personal_paths_and_email_are_blocked_without_disclosing_matches(self):
        samples = [('private-key', ('-----BEGIN ' + 'PRIVATE KEY-----').encode()),
                   ('service-token', ('sk-proj-' + 'x' * 32).encode()),
                   ('github-token', ('github_pat_' + 'x' * 40).encode()),
                   ('personal-home-path', ('/Users/' + 'private-person/Documents').encode()),
                   ('personal-email', ('private-person@' + 'gmail.com').encode())]
        for rule, sample in samples:
            with self.subTest(rule=rule):
                self.assertIn(rule, public.findings('docs/example.txt', sample))
                with patch.object(public, 'blobs', return_value=[('docs/example.txt', sample)]), \
                     contextlib.redirect_stderr(io.StringIO()) as output:
                    self.assertEqual(public.check([('docs/example.txt', b'oid')], 'index', set()), 1)
                self.assertNotIn(sample.decode(), output.getvalue())

    def test_public_identifiers_examples_and_shared_directory_are_allowed(self):
        data = b'co.example.app HJ4HYUU2Y6 6762541353 test@example.invalid /Users/Shared/MyApp $HOME/Documents/'
        self.assertEqual(public.findings('releases/ios/1.2.3/release.json', data), [])
        self.assertEqual(public.findings('.env.example', b'API_KEY=YOUR_KEY'), [])


class GitSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(git_fixture_environment())
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        original = public.git
        def in_fixture(*args, data=None):
            return subprocess.check_output(['git', *args], input=data, cwd=self.root, stderr=subprocess.DEVNULL)
        self.mock = patch.object(public, 'git', side_effect=in_fixture)
        self.mock.start()
        self.addCleanup(self.mock.stop)
        self.git('init', '-q')
        self.git('config', 'commit.gpgsign', 'false')  # Synthetic fixtures must not contact the real signing agent.
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, stderr=subprocess.DEVNULL)

    def test_scans_staged_blobs_including_binary_and_does_not_follow_symlinks(self):
        secret = ('-----BEGIN ' + 'PRIVATE KEY-----').encode()
        (self.root / 'binary.dat').write_bytes(b'\0' + secret)
        (self.root / 'link').symlink_to('/not-readable-private-target')
        self.git('add', '.')
        (self.root / 'binary.dat').write_bytes(b'clean working copy')
        contents = dict(public.blobs(public.index_entries()))
        self.assertEqual(contents['binary.dat'], b'\0' + secret)
        self.assertEqual(contents['link'], b'/not-readable-private-target')
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(public.check(public.index_entries(), 'index', set()), 1)

    def test_removed_secret_is_still_detected_in_outgoing_history(self):
        path = self.root / 'config.txt'
        path.write_text('safe')
        self.git('add', '.'); self.git('commit', '-qm', 'Base')
        base = self.git('rev-parse', 'HEAD').decode().strip()
        path.write_text('sk-proj-' + 'x' * 32)
        self.git('add', '.'); self.git('commit', '-qm', 'Bad intermediate commit')
        bad = self.git('rev-parse', 'HEAD').decode().strip()
        path.write_text('safe again')
        self.git('add', '.'); self.git('commit', '-qm', 'Remove secret')
        head = self.git('rev-parse', 'HEAD').decode().strip()
        line = f'refs/heads/release {head} refs/heads/release {base}\n'
        with patch.object(public.sys, 'stdin', io.StringIO(line)):
            commits = public.outgoing_commits('origin')
        self.assertIn(bad, commits)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(public.check(public.changed_entries(bad), 'history', set()), 1)
        self.assertEqual(public.findings('config.txt', path.read_bytes()), [])

    def test_commit_identity_rejects_contact_email_without_echoing_it(self):
        self.git('config', 'user.email', 'private-contact@example.org')
        with contextlib.redirect_stderr(io.StringIO()) as output:
            self.assertEqual(public.check_identity(), 1)
        self.assertNotIn('private-contact@example.org', output.getvalue())
        self.git('config', 'user.email', '123+test@users.noreply.github.com')
        self.assertEqual(public.check_identity(), 0)

    def test_deleted_refs_do_not_scan_or_mutate_anything(self):
        line = f'refs/heads/release {"0"*40} refs/heads/release {"a"*40}\n'
        with patch.object(public.sys, 'stdin', io.StringIO(line)):
            self.assertEqual(public.outgoing_commits('origin'), [])
