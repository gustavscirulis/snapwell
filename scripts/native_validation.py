"""Reusable native evidence for unchanged app/test inputs, independent of release numbers."""
import argparse
from datetime import datetime
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import time
import zipfile

try:
    from scripts import release_state
except ImportError:
    import release_state

COUNTS = ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests')
REPOSITORY = 'gustavscirulis/snapwell'


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL)


def normalized_input(name, data):
    if name in ('macos/project.yml', 'macos/Snapwell.xcodeproj/project.pbxproj',
                'ios/Snapwell.xcodeproj/project.pbxproj'):
        data = re.sub(rb'(MARKETING_VERSION\s*[:=]\s*)[^\r\n;]+', rb'\1<version>', data)
        data = re.sub(rb'(CURRENT_PROJECT_VERSION\s*[:=]\s*)[^\r\n;]+', rb'\1<build>', data)
    return data


def fingerprint(root, platform, ref=None):
    if platform not in ('macos', 'ios'):
        raise RuntimeError('Unknown native platform')
    paths = (platform, 'Shared', 'Tests')
    if ref:
        entries = []
        for row in git(root, 'ls-tree', '-rz', ref, '--', *paths).split(b'\0'):
            if row:
                meta, name = row.split(b'\t', 1)
                mode, kind, oid = meta.split()
                if kind == b'blob':
                    entries.append((name.decode(), mode, git(root, 'cat-file', 'blob', oid.decode())))
    else:
        names = set(git(root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', *paths).decode().split('\0'))
        entries = []
        for name in sorted(filter(None, names)):
            path = Path(root) / name
            if path.is_symlink():
                entries.append((name, b'120000', os.readlink(path).encode()))
            elif path.is_file():
                mode = b'100755' if path.stat().st_mode & 0o111 else b'100644'
                entries.append((name, mode, path.read_bytes()))
    digest = hashlib.sha256(b'Snapwell Automation all native inputs v1\0' + platform.encode())
    for name, mode, data in sorted(entries):
        if 'xcuserdata' in Path(name).parts or name == 'macos/Snapwell.xcodeproj/project.pbxproj':
            continue
        data = normalized_input(name, data)
        digest.update(name.encode() + b'\0' + mode + b'\0' + str(len(data)).encode() + b'\0' + data)
    return digest.hexdigest()


def checked_counts(raw):
    counts = {key: raw.get(key) for key in COUNTS}
    if (any(type(value) is not int for value in counts.values()) or counts['totalTestCount'] <= 0
            or counts['passedTests'] != counts['totalTestCount']
            or counts['failedTests'] != 0 or counts['skippedTests'] != 0):
        raise RuntimeError('Native evidence requires positive passed counts with zero failures/skips')
    return counts


def state_root(root):
    path = Path(os.environ.get('SNAPWELL_VALIDATION_STATE_DIR', '~/.appstoreconnect/validation')).expanduser()
    if path.resolve().is_relative_to(Path(root).resolve()):
        raise RuntimeError('Reusable native evidence must stay outside the repository')
    return path


def cache_path(root, platform, inputs):
    return state_root(root) / (platform + '-' + inputs + '.json')


def pending(root, platform, inputs):
    path = cache_path(root, platform, inputs)
    release_state.protect(path.parent)
    release_state.atomic_private(path, json.dumps({'status': 'pending', 'verified_at': time.time()}).encode())


def save(root, platform, inputs, counts, verified_at=None):
    if not re.fullmatch(r'[a-f0-9]{64}', inputs) or platform not in ('macos', 'ios'):
        raise RuntimeError('Invalid native evidence identity')
    verified_at = time.time() if verified_at is None else verified_at
    data = {'platform': platform, 'input_fingerprint': inputs, 'counts': checked_counts(counts),
            'status': 'passed', 'verified_at': verified_at}
    directory = state_root(root)
    release_state.protect(directory)
    path = cache_path(root, platform, inputs)
    if path.is_file() and json.loads(path.read_text()).get('verified_at', 0) > verified_at:
        raise RuntimeError('Newer native evidence exists; an older CI run cannot replace it')
    release_state.atomic_private(path,
                                 (json.dumps(data, sort_keys=True) + '\n').encode())
    return data


def record_pass(root, platform, bundle, inputs):
    if fingerprint(root, platform) != inputs:
        raise RuntimeError('Native inputs changed during validation')
    raw = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(bundle)])
    return save(root, platform, inputs, json.loads(raw))


def passing_evidence(root, platform):
    inputs = fingerprint(root, platform)
    path = cache_path(root, platform, inputs)
    if path.is_symlink() or not path.is_file():
        return None
    try:
        data = json.loads(path.read_text())
        if data.get('status') != 'passed':
            raise RuntimeError('A newer native run failed or is incomplete; inspect it before releasing')
        if data['platform'] == platform and data['input_fingerprint'] == inputs:
            checked_counts(data['counts'])
            return data
    except (ValueError, KeyError):
        pass
    return None


def gh(path):
    return subprocess.check_output(['gh', 'api', 'repos/' + REPOSITORY + path], timeout=180)


def import_ci(root, run_id):
    """Read GitHub's actual successful run and artifact, rather than trusting a pasted claim."""
    run = json.loads(gh('/actions/runs/' + str(run_id)))
    if (run.get('status') != 'completed' or run.get('conclusion') != 'success'
            or run.get('path') != '.github/workflows/quality.yml'):
        raise RuntimeError('Expected a successful Snapwell Quality workflow run')
    artifacts = json.loads(gh('/actions/runs/' + str(run_id) + '/artifacts'))['artifacts']
    artifact = next((item for item in artifacts if item['name'] == 'public-validation-' + str(run_id)
                     and not item['expired'] and item['size_in_bytes'] < 1_000_000), None)
    if artifact is None:
        raise RuntimeError('No retained native validation artifact; inspect actual native evidence')
    archive = gh('/actions/artifacts/' + str(artifact['id']) + '/zip')
    with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
        files = [item for item in bundle.infolist() if not item.is_dir()]
        if len(files) != 1 or files[0].filename != 'public-validation.json' or files[0].file_size > 1_000_000:
            raise RuntimeError('Unexpected validation artifact contents')
        data = json.loads(bundle.read(files[0]))
    source = data['source_commit']
    if not re.fullmatch(r'[a-f0-9]{40}', source):
        raise RuntimeError('Invalid tested source commit')
    # PR checks test a merge commit; push checks test head_sha itself.
    try:
        parents = git(root, 'rev-list', '--parents', '-n', '1', source).decode().split()
    except subprocess.CalledProcessError:
        git(root, 'fetch', '--no-tags', 'origin', source)
        parents = git(root, 'rev-list', '--parents', '-n', '1', source).decode().split()
    if run['head_sha'] not in parents:
        raise RuntimeError('Artifact source does not belong to the selected workflow run')
    if data.get('headless') != {name: 'passed' for name in ('tooling-python', 'tooling-swift', 'core')}:
        raise RuntimeError('Incomplete headless validation evidence')
    records = []
    for platform, counts in data['native'].items():
        inputs = fingerprint(root, platform, source)
        if data['native_fingerprints'].get(platform) != inputs:
            raise RuntimeError('Native evidence fingerprint differs from tested Git source')
        records.append((platform, inputs, checked_counts(counts)))
    if not records:
        raise RuntimeError('No native validation evidence')
    for platform, inputs, counts in records:
        save(root, platform, inputs, counts, datetime.fromisoformat(run['updated_at'].replace('Z', '+00:00')).timestamp())
        print(f'Imported verified {platform} native evidence: {counts["passedTests"]} passed; zero failures/skips.')


if __name__ == '__main__':
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('import-ci',))
    parser.add_argument('--run', type=int, required=True)
    args = parser.parse_args()
    import_ci(Path(__file__).resolve().parents[1], args.run)
