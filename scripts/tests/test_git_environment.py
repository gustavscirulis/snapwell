import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from scripts.tests.git_environment import git_fixture_environment


class HookIsolationTests(unittest.TestCase):
    def test_fixture_init_and_config_cannot_modify_the_parent_hook_repository(self):
        with tempfile.TemporaryDirectory() as directory, git_fixture_environment():
            outer = Path(directory) / 'outer'
            inner = Path(directory) / 'inner'
            subprocess.run(['git', 'init', '-q', str(outer)], check=True)
            config = outer / '.git/config'
            original = config.read_bytes()
            inherited = {'GIT_DIR': str(outer / '.git'), 'GIT_CONFIG': str(config),
                         'GIT_INDEX_FILE': str(outer / '.git/index'), 'GIT_WORK_TREE': str(outer),
                         'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'commit.gpgsign', 'GIT_CONFIG_VALUE_0': 'true'}
            with patch.dict(os.environ, inherited), git_fixture_environment():
                self.assertNotIn('GIT_DIR', os.environ)
                self.assertNotIn('GIT_CONFIG_COUNT', os.environ)
                subprocess.run(['git', 'init', '-q', str(inner)], check=True)
                subprocess.run(['git', 'config', 'user.name', 'Synthetic'], cwd=inner, check=True)
                (inner / 'file').write_text('fixture')
                subprocess.run(['git', 'add', '.'], cwd=inner, check=True)
            self.assertEqual(config.read_bytes(), original)
            self.assertFalse((outer / '.git/index').exists())
            self.assertTrue((inner / '.git/index').exists())
