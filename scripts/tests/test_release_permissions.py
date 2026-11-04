from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).parents[1] / 'release_permissions.sh'


class ReleasePermissionsTests(unittest.TestCase):
    def test_private_release_state_does_not_make_installed_app_unreadable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / 'App.app'
            signature = app / 'Contents/_CodeSignature/CodeResources'
            signature.parent.mkdir(parents=True, mode=0o700)
            signature.write_text('cached signature')
            signature.chmod(0o600)
            executable = app / 'Contents/executable'
            executable.write_text('synthetic executable')
            executable.chmod(0o700)
            receipt = root / 'receipt.json'
            receipt.write_text('{}')
            receipt.chmod(0o600)
            log = root / 'archive-upload.log'
            log.touch(mode=0o600)
            child = "from pathlib import Path; import sys; (Path(sys.argv[1])/'App.app/new-resource').write_text('new resource')"
            command = '''set -euo pipefail
source "$1"
umask 077
run_release_command "$2" -c "$3" "$4"
prepare_release_bundle "$4/App.app"
umask
'''
            with log.open('w') as output:
                result = subprocess.run(['bash', '-c', command, 'permissions-test',
                                         str(HELPER), sys.executable, child, directory],
                                        stdout=output, stderr=subprocess.PIPE, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('0077', log.read_text(), 'The private caller mask must remain unchanged')
            self.assertEqual(stat.S_IMODE(signature.stat().st_mode), 0o644)
            self.assertEqual(stat.S_IMODE((app / 'new-resource').stat().st_mode), 0o644)
            self.assertEqual(stat.S_IMODE(executable.stat().st_mode), 0o755)
            for path in (app, signature.parent):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o755)
            self.assertEqual(stat.S_IMODE(root.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(receipt.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(log.stat().st_mode), 0o600)

    def test_release_command_keeps_a_failed_export_failed(self):
        result = subprocess.run(['bash', '-c',
                                 'source "$1"; run_release_command "$2" -c "raise SystemExit(19)"',
                                 'permissions-test', str(HELPER), sys.executable], capture_output=True)
        self.assertEqual(result.returncode, 19)
