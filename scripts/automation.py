#!/usr/bin/env python3
"""Local agent validation and release preparation. No third-party Python packages."""
from __future__ import annotations
import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
CONTEXT = ROOT / '.context'


def run(args, *, capture=False, cwd=ROOT, env=None, timeout=1800):
    result = subprocess.run([str(a) for a in args], cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None, timeout=timeout)
    if result.returncode:
        if capture:
            raise RuntimeError(f'{args[0]} failed ({result.returncode}):\n{result.stderr[-6000:]}\n{result.stdout[-2000:]}')
        raise RuntimeError(f'{args[0]} failed ({result.returncode})')
    return result.stdout if capture else None


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')
    temp.replace(path)


def changed_files(staged=False):
    if staged:
        return run(['git', 'diff', '--cached', '--name-only', '-z'], capture=True).split('\0')
    files = []
    for args in (['git', 'diff', '--name-only', '-z', 'origin/main...HEAD'],
                 ['git', 'diff', '--name-only', '-z', 'HEAD'],
                 ['git', 'ls-files', '--others', '--exclude-standard', '-z']):
        files.extend(run(args, capture=True).split('\0'))
    return sorted(set(filter(None, files)))


def affected_platforms(files):
    platforms = set()
    for name in files:
        if name.startswith('macos/'):
            platforms.add('macos')
        elif name.startswith('ios/'):
            platforms.add('ios')
        elif name.startswith(('Shared/', 'Tests/', 'scripts/', 'tools/', '.githooks/')) or name == 'dev.sh':
            platforms.update(('macos', 'ios'))
    return sorted(platforms)


def simulator():
    devices = json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], capture=True))['devices']
    record = CONTEXT / 'testing/simulator.json'
    if record.exists():
        identifier = json.loads(record.read_text())['id']
        if any(d['udid'] == identifier for group in devices.values() for d in group):
            return identifier
    candidates = [(runtime, device) for runtime, group in devices.items() if '.iOS-' in runtime
                  for device in group if 'iPhone' in device['name'] and device.get('isAvailable')]
    if not candidates:
        raise RuntimeError('No available iPhone simulator runtime. Open Xcode Settings → Components and install an iOS runtime.')
    runtime, template = sorted(candidates, key=lambda pair: tuple(map(int, re.findall(r'\d+', pair[0]))))[-1]
    device_type = template.get('deviceTypeIdentifier', 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro')
    name = 'Snapwell-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:8]
    identifier = run(['xcrun', 'simctl', 'create', name, device_type, runtime], capture=True).strip()
    write_json(record, {'id': identifier, 'name': name})
    return identifier


@contextlib.contextmanager
def native_lock():
    path = Path(os.environ.get('TMPDIR', '/tmp')) / 'snapwell-native-tests.lock'
    with path.open('w') as lock:
        print('Waiting for the native-test slot…', flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def doctor(args):
    failures = []
    for name in ('xcodebuild', 'xcrun', 'xcodegen', 'swift', 'python3', 'git'):
        location = shutil.which(name)
        print(f'{name}: {location or "MISSING"}')
        if not location:
            failures.append(name)
    try:
        print(run(['xcodebuild', '-version'], capture=True).strip())
    except RuntimeError as error:
        failures.append(str(error))
    if args.platform in ('ios', 'all'):
        try:
            data = json.loads(run(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'], capture=True))
            count = sum(len(group) for group in data['devices'].values())
            print(f'Simulator: {count} available devices')
            if not count:
                failures.append('No simulator devices installed')
        except RuntimeError as error:
            failures.append('Simulator unavailable. Restart Xcode/Simulator after updating Xcode; run xcodebuild -runFirstLaunch if components need installation.\n' + str(error))
    if args.apple:
        try:
            result = asc('inspect', args.platform if args.platform != 'all' else 'macos', local_build='0')
            print(f'App Store Connect: authenticated for app {result["app_id"]}')
        except RuntimeError as error:
            failures.append(str(error))
    if failures:
        raise RuntimeError('\n'.join(failures))
    print('Doctor checks passed.')


def logged(args, directory, name):
    directory.mkdir(parents=True, exist_ok=True)
    log = directory / (name + '.log')
    print(f'Running {name}; log: {log.relative_to(ROOT)}', flush=True)
    try:
        with log.open('w') as output:
            result = subprocess.run([str(a) for a in args], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                    text=True, timeout=1800)
        if result.returncode:
            print('\n'.join(log.read_text(errors='replace').splitlines()[-35:]), file=sys.stderr)
            return {'name': name, 'status': 'failed', 'exit_code': result.returncode, 'log': str(log)}
        return {'name': name, 'status': 'passed', 'log': str(log)}
    except subprocess.TimeoutExpired:
        return {'name': name, 'status': 'timed_out', 'log': str(log)}


def headless_input(name, path):
    if path.startswith(('scripts/', 'tools/', '.githooks/')) or path in ('dev.sh', '.gitignore'):
        return True
    return name == 'core' and path.startswith(('macos/', 'ios/', 'Shared/', 'Tests/'))


def headless_fingerprint(name, staged=False):
    files = run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], capture=True, cwd=ROOT).split('\0')
    if staged:
        unstaged = run(['git', 'diff', '--name-only', '-z'], capture=True, cwd=ROOT).split('\0')
        untracked = run(['git', 'ls-files', '--others', '--exclude-standard', '-z'], capture=True, cwd=ROOT).split('\0')
        mismatches = sorted({path for path in unstaged + untracked if path and headless_input(name, path)})
        if mismatches:
            raise RuntimeError('Stage or stash test inputs that differ from the index before committing:\n' + '\n'.join(mismatches))
    digest = hashlib.sha256()
    digest.update(json.dumps(['headless-v1', name, sys.version, os.uname().release,
                              run(['swift', '--version'], capture=True, cwd=ROOT)], sort_keys=True).encode())
    for path in sorted(set(filter(None, files))):
        if not headless_input(name, path):
            continue
        source = ROOT / path
        if not source.exists() and not source.is_symlink():
            continue
        digest.update(path.encode() + b'\0')
        digest.update(str(source.lstat().st_mode).encode() + b'\0')
        if source.is_symlink():
            digest.update(os.readlink(source).encode() + b'\0')
        digest.update(hashlib.sha256(source.read_bytes()).digest())
    return digest.hexdigest()


def passing_headless_result(name, fingerprint):
    for path in sorted((CONTEXT / 'testing').glob('*/summary.json'), key=lambda p: p.stat().st_mtime_ns, reverse=True):
        try:
            report = json.loads(path.read_text())
            for result in report['results']:
                if result['name'] == name and result.get('input_fingerprint') == fingerprint:
                    # A newer failure must not be hidden by an older pass on the same inputs.
                    if result['status'] != 'passed' or not Path(result.get('log', '')).is_file():
                        return None
                    return dict(result, reused_from=str(path))
        except (OSError, ValueError, KeyError, TypeError):
            continue
    return None


def headless_check(command, directory, name, args):
    fingerprint = headless_fingerprint(name, args.staged)
    if getattr(args, 'reuse_passing', True):
        previous = passing_headless_result(name, fingerprint)
        if previous:
            print(f'Reusing {name}; passed for unchanged inputs: {previous["reused_from"]}', flush=True)
            return previous
    result = logged(command, directory, name)
    result['input_fingerprint'] = fingerprint
    if headless_fingerprint(name, args.staged) != fingerprint:
        result['status'] = 'inputs_changed'
        result['error'] = 'Test inputs changed during validation; rerun against the final files.'
    return result


def test(args):
    platforms = affected_platforms(changed_files(args.staged)) if args.platform == 'changed' else (
        ['macos', 'ios'] if args.platform == 'all' else [args.platform])
    if args.suite in ('tools', 'core'):
        platforms = []
    if args.dry_run:
        print(json.dumps({'platforms': platforms, 'suite': args.suite, 'only': args.only, 'staged': args.staged}, indent=2))
        return
    if args.platform == 'changed' and not platforms and args.suite not in ('tools', 'core'):
        print('No affected native platforms; native tests skipped (documentation/site-only changes).')
        return
    directory = CONTEXT / 'testing' / (dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:6])
    directory.mkdir(parents=True)
    results = []
    if args.suite in ('logic', 'all', 'tools'):
        results.append(headless_check(['python3', '-m', 'unittest', 'discover', '-s', 'scripts/tests', '-v'], directory, 'tooling-python', args))
        results.append(headless_check(['swift', 'test', '--disable-sandbox', '--package-path', 'tools/ReleaseTools', '--scratch-path', str(CONTEXT / 'release-tools-build')], directory, 'tooling-swift', args))
    if args.suite in ('logic', 'all', 'core'):
        results.append(headless_check(['python3', 'scripts/test_core.py'], directory, 'core', args))
    with native_lock() if platforms else contextlib.nullcontext():
        for platform in platforms:
            try:
                if platform == 'macos':
                    run(['xcodegen', 'generate', '--spec', 'macos/project.yml', '--project', 'macos'])
                    run(['bash', 'macos/scripts/post-xcodegen.sh'])
                    destination = 'platform=macOS'
                else:
                    destination = 'platform=iOS Simulator,id=' + (args.simulator or simulator())
                command = ['xcodebuild', 'test', '-project', f'{platform}/Snapwell.xcodeproj', '-scheme', 'Snapwell',
                           '-configuration', 'Automation', '-destination', destination,
                           '-derivedDataPath', str(CONTEXT / 'testing' / (platform + '-derived')),
                           '-resultBundlePath', str(directory / (platform + '.xcresult')),
                           '-parallel-testing-enabled', 'NO', '-enableCodeCoverage', 'YES',
                           '-disableAutomaticPackageResolution', '-skipPackageUpdates']
                if args.only:
                    target = args.only.split('/')[0]
                    expected = {'logic': 'SnapwellTests', 'ui': 'SnapwellUITests'}.get(args.suite)
                    if target not in ('SnapwellTests', 'SnapwellUITests') or (expected and target != expected):
                        raise RuntimeError('--only must name a test target matching --suite')
                    command += ['-only-testing:' + args.only]
                elif args.suite == 'logic':
                    command += ['-only-testing:SnapwellTests']
                elif args.suite == 'ui':
                    command += ['-only-testing:SnapwellUITests']
                if os.environ.get('SNAPWELL_DISABLE_MACRO_SANDBOX') == '1':
                    command += ['OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox',
                                '-IDEPackageSupportDisableManifestSandbox=YES']
                if platform == 'macos':
                    command += ['CODE_SIGN_IDENTITY=-']
                else:
                    command += ['CODE_SIGNING_ALLOWED=NO']
                results.append(logged(command, directory, platform))
            except (RuntimeError, subprocess.TimeoutExpired) as error:
                results.append({'name': platform, 'status': 'unavailable', 'error': str(error)})
                print(str(error), file=sys.stderr)
    report = {'results': results, 'platforms': platforms, 'suite': args.suite}
    write_json(directory / 'summary.json', report)
    print(f'Results: {directory.relative_to(ROOT)}/summary.json')
    if any(result['status'] != 'passed' for result in results):
        raise RuntimeError('Validation did not pass; see the report for failed or unavailable checks.')


_asc_executable = None


def asc(command, platform, **options):
    global _asc_executable
    if _asc_executable is None:
        # Build separately: a cold Swift build must not consume the API timeout.
        scratch = CONTEXT / 'release-tools-build'
        run(['swift', 'build', '--disable-sandbox', '--package-path', 'tools/ReleaseTools',
             '--scratch-path', str(scratch), '--product', 'snapwell-asc'], capture=True, timeout=600)
        _asc_executable = scratch / 'debug/snapwell-asc'
    args = [str(_asc_executable), command, '--platform', platform]
    for key, value in options.items():
        if value is not None:
            args += ['--' + key.replace('_', '-'), str(value)]
    return json.loads(run(args, capture=True, timeout=180))


def pending_changes(platform):
    text = (ROOT / 'CHANGELOG.md').read_text()
    section = None
    entries = []
    seen = set()
    for line in text.splitlines():
        if line == '## Unreleased':
            section = ''
        elif line.startswith('## ') and section is not None:
            break
        elif section is not None and line.startswith('### '):
            section = line[4:].strip().lower()
            if section not in ('macos', 'ios', 'both'):
                raise RuntimeError(f'Unknown changelog platform: {section}')
        elif section is not None and line.startswith('- '):
            match = re.fullmatch(r'- \[([a-z0-9-]+)\] (.+)', line)
            if not match or not section:
                raise RuntimeError('Changelog entries need a platform heading and - [unique-id] benefit.')
            identifier, benefit = match.groups()
            if identifier in seen:
                raise RuntimeError(f'Duplicate changelog ID: {identifier}')
            seen.add(identifier)
            if section in (platform, 'both'):
                entries.append({'id': identifier, 'text': benefit})
    released_ids = set()
    for manifest in (ROOT / 'releases' / platform).glob('*/release.json'):
        data = json.loads(manifest.read_text())
        if data.get('status') in ('submitted', 'released'):
            released_ids.update(entry['id'] for entry in data['changes'])
    return [entry for entry in entries if entry['id'] not in released_ids]


def release_dir(platform, version):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise RuntimeError('Version must be numeric major.minor.patch')
    return ROOT / 'releases' / platform / version


def local_build(platform):
    if platform == 'macos':
        text = (ROOT / 'macos/project.yml').read_text()
        return int(re.search(r'CURRENT_PROJECT_VERSION: (\d+)', text)[1])
    text = (ROOT / 'ios/Snapwell.xcodeproj/project.pbxproj').read_text()
    return max(map(int, re.findall(r'CURRENT_PROJECT_VERSION = (\d+);', text)))


def set_version(platform, version, build):
    path = ROOT / ('macos/project.yml' if platform == 'macos' else 'ios/Snapwell.xcodeproj/project.pbxproj')
    text = path.read_text()
    if platform == 'macos':
        text = re.sub(r'MARKETING_VERSION: "[^"]+"', f'MARKETING_VERSION: "{version}"', text)
        text = re.sub(r'CURRENT_PROJECT_VERSION: \d+', f'CURRENT_PROJECT_VERSION: {build}', text)
    else:
        text = re.sub(r'MARKETING_VERSION = [^;]+;', f'MARKETING_VERSION = {version};', text)
        text = re.sub(r'CURRENT_PROJECT_VERSION = \d+;', f'CURRENT_PROJECT_VERSION = {build};', text)
    path.write_text(text)
    if platform == 'macos':
        run(['xcodegen', 'generate', '--spec', 'macos/project.yml', '--project', 'macos'])
        run(['bash', 'macos/scripts/post-xcodegen.sh'])


def notes_text(path):
    text = path.read_text()
    lines = [line for line in text.splitlines() if line]
    if not 2 <= len(lines) <= 4 or not all(line.startswith('• ') and len(line) > 4 for line in lines) or len(text) > 4000:
        raise RuntimeError('Notes must have 2–4 nonempty • bullets and at most 4,000 characters. Ask the agent to draft them from release.json changes.')
    return text


def finish_submission(args, manifest, receipt, receipt_path, path, manifest_path):
    """Resume only the Apple processing/metadata/review steps of a verified upload."""
    deadline = time.monotonic() + args.wait_minutes * 60
    while True:
        remote = asc('status', args.platform)
        build = next((item for item in remote['builds'] if item['attributes']['version'] == str(manifest['build'])), None)
        state = build['attributes'].get('processingState') if build else 'NOT_VISIBLE'
        if state == 'VALID':
            break
        if state in ('FAILED', 'INVALID'):
            raise RuntimeError(f'Apple build processing failed: {state}')
        if time.monotonic() >= deadline:
            raise RuntimeError('Build is still processing. Rerun release submit to resume; the upload receipt is saved.')
        print(f'Apple processing: {state}; waiting 20 seconds…', flush=True)
        time.sleep(20)
    marketing = build['attributes'].get('snapwellMarketingVersion')
    if marketing != args.version:
        raise RuntimeError(f'Apple build belongs to version {marketing}, expected {args.version}')
    if receipt.get('build_id') and receipt['build_id'] != build['id']:
        raise RuntimeError('Apple build ID differs from the upload receipt.')
    if hashlib.sha256(notes_text(path).encode()).hexdigest() != receipt['notes_sha256']:
        raise RuntimeError('Release notes changed before staging.')
    receipt['build_id'] = build['id']
    write_json(receipt_path, receipt)
    result = asc('stage', args.platform, version=args.version, build_id=build['id'], notes=path, locale=manifest['locale'])
    receipt['version_id'] = result['version_id']
    write_json(receipt_path, receipt)
    submission = asc('submit', args.platform, version_id=result['version_id'], checkpoint=receipt_path.parent / 'submission.json')['submission']
    receipt['submission'] = submission
    write_json(receipt_path, receipt)
    manifest.update(status='submitted', source_commit=receipt['commit'], build_id=build['id'], version_id=result['version_id'],
                    notes_sha256=receipt['notes_sha256'], submission_id=submission['id'],
                    submitted_at=dt.datetime.now(dt.timezone.utc).isoformat())
    write_json(manifest_path, manifest)
    print(f'Submitted {args.platform} {args.version} build {manifest["build"]}. Apple will publish automatically after approval. Commit the updated release record.')


def release(args):
    if args.locale is not None and not re.fullmatch(r'[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*', args.locale):
        raise RuntimeError('Invalid release locale')
    directory = release_dir(args.platform, args.version)
    manifest_path = directory / 'release.json'
    if args.action == 'prepare':
        if manifest_path.exists():
            raise RuntimeError('Release already prepared; edit its notes or use status/publish.')
        remote = asc('inspect', args.platform, local_build=local_build(args.platform))
        locale = args.locale or remote.get('primary_locale', 'en-US')
        if not locale.startswith('en-'):
            raise RuntimeError('Set --locale to an existing English localization.')
        manifest = {'platform': args.platform, 'version': args.version, 'build': remote['next_build'],
                    'locale': locale, 'status': 'prepared', 'changes': pending_changes(args.platform)}
        if not manifest['changes']:
            raise RuntimeError('No pending changes for this platform; add changelog entries first.')
        if args.dry_run:
            print(json.dumps(manifest, indent=2))
            return
        set_version(args.platform, args.version, manifest['build'])
        write_json(manifest_path, manifest)
        (directory / (locale + '.txt')).write_text(''.join('• ' + change['text'] + '\n' for change in manifest['changes']))
        print(f'Prepared {directory.relative_to(ROOT)}. Agent: condense the notes into 2–4 bullets, then commit the prepared release.')
        return
    if not manifest_path.exists():
        raise RuntimeError('Run release prepare first.')
    manifest = json.loads(manifest_path.read_text())
    if manifest['platform'] != args.platform or manifest['version'] != args.version:
        raise RuntimeError('Release manifest does not match requested platform/version.')
    remote = asc('status', args.platform)
    version = next((item for item in remote['versions'] if item['attributes']['versionString'] == args.version), None)
    if args.action == 'status':
        output = {'local': manifest, 'remote_version': version}
        print(json.dumps(output, indent=2))
        if not args.dry_run and version:
            state = version['attributes'].get('appVersionState', version['attributes'].get('appStoreState'))
            linked_build = ((version.get('relationships', {}).get('build', {}).get('data') or {}).get('id'))
            if state in ('READY_FOR_DISTRIBUTION', 'READY_FOR_SALE') and manifest.get('status') == 'submitted' and linked_build == manifest.get('build_id'):
                manifest['status'] = 'released'
                manifest['released_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
                write_json(manifest_path, manifest)
        return
    if not re.fullmatch(r'[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*', manifest['locale']):
        raise RuntimeError('Invalid manifest locale')
    path = directory / (manifest['locale'] + '.txt')
    text = notes_text(path)
    build = next((item for item in remote['builds'] if item['attributes']['version'] == str(manifest['build'])), None)
    plan = {'platform': args.platform, 'version': args.version, 'build': manifest['build'],
            'notes': text, 'submission': 'App Review', 'publication': 'AFTER_APPROVAL'}
    print(json.dumps(plan, indent=2), flush=True)
    if args.dry_run:
        return
    state = version['attributes'].get('appVersionState', version['attributes'].get('appStoreState')) if version else None
    linked_build = ((version.get('relationships', {}).get('build', {}).get('data') or {}).get('id')) if version else None
    submitted_states = ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_APPLE_RELEASE', 'PROCESSING_FOR_DISTRIBUTION', 'READY_FOR_DISTRIBUTION', 'READY_FOR_SALE')
    if state in submitted_states and manifest.get('status') in ('submitted', 'released'):
        if not build or linked_build != manifest.get('build_id') or build['id'] != manifest.get('build_id') or hashlib.sha256(text.encode()).hexdigest() != manifest.get('notes_sha256'):
            raise RuntimeError('Remote submission/build or local notes do not match the release record.')
        print('Version already submitted; no upload or submission repeated.')
        return
    if args.action == 'submit':
        receipt_path = CONTEXT / 'releases' / args.platform / args.version / 'receipt.json'
        if not receipt_path.exists():
            raise RuntimeError('Submission requires the original successful upload receipt; use publish for a new release.')
        receipt = json.loads(receipt_path.read_text())
        if not receipt.get('uploaded') or any(receipt.get(key) != manifest[key] for key in ('platform', 'version', 'build')):
            raise RuntimeError('Upload receipt does not confirm this platform/version/build.')
        if receipt.get('notes_sha256') != hashlib.sha256(text.encode()).hexdigest():
            raise RuntimeError('Release notes changed since upload; inspect the receipt before submitting.')
        source = receipt.get('commit', '')
        if not re.fullmatch(r'[0-9a-f]{40,64}', source):
            raise RuntimeError('Upload receipt is missing a valid source commit.')
        # Tooling/docs and another platform's submission record may have advanced since
        # upload. Require the actual native inputs to remain byte-for-byte identical.
        inputs = ['macos', 'ios', 'Shared', 'Tests', 'dev.sh']
        changed = run(['git', 'diff', '--name-only', source, '--', *inputs], capture=True).strip()
        untracked = run(['git', 'ls-files', '--others', '--exclude-standard', '--', *inputs], capture=True).strip()
        if changed or untracked:
            raise RuntimeError('Native inputs differ from the uploaded source; inspect before submitting.')
        if not build:
            raise RuntimeError('The receipted build is not visible in Apple; submission never builds or uploads.')
        if receipt.get('build_id') and receipt['build_id'] != build['id']:
            raise RuntimeError('Apple build ID differs from the upload receipt.')
        if state in submitted_states:
            checkpoint = receipt_path.parent / 'submission.json'
            saved = json.loads(checkpoint.read_text()) if checkpoint.exists() else {}
            if (linked_build != build['id'] or receipt.get('version_id') != version['id']
                    or saved.get('version_id') != version['id'] or not saved.get('submission_id')):
                raise RuntimeError('Remote submission has no matching local receipt/checkpoint; inspect before proceeding.')
            manifest.update(status='submitted', source_commit=source, build_id=build['id'],
                            version_id=version['id'], notes_sha256=receipt['notes_sha256'],
                            submission_id=saved['submission_id'])
            write_json(manifest_path, manifest)
            print('Recovered the confirmed remote submission. Commit the updated release record.')
            return
        finish_submission(args, manifest, receipt, receipt_path, path, manifest_path)
        return
    if run(['git', 'status', '--porcelain'], capture=True).strip():
        raise RuntimeError('Commit the prepared release and notes before publishing; working tree must be clean.')
    commit = run(['git', 'rev-parse', 'HEAD'], capture=True).strip()
    receipt_path = CONTEXT / 'releases' / args.platform / args.version / 'receipt.json'
    receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
    fingerprint = hashlib.sha256(text.encode()).hexdigest()
    if receipt and (receipt['commit'] != commit or receipt['notes_sha256'] != fingerprint):
        raise RuntimeError('Release source/notes changed since the previous attempt; inspect the receipt before resuming.')
    if state in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_APPLE_RELEASE', 'PROCESSING_FOR_DISTRIBUTION', 'READY_FOR_DISTRIBUTION', 'READY_FOR_SALE'):
        linked_build = ((version.get('relationships', {}).get('build', {}).get('data') or {}).get('id'))
        if not build or linked_build != build['id']:
            raise RuntimeError('Remote version is linked to a different build; inspect before proceeding.')
        if manifest.get('status') in ('submitted', 'released') and manifest.get('build_id') == build['id']:
            print('Version already submitted; no upload or submission repeated.')
            return
        checkpoint = receipt_path.parent / 'submission.json'
        if receipt.get('version_id') != version['id'] or not checkpoint.exists():
            raise RuntimeError('Remote submission has no matching local receipt; inspect before proceeding.')
        saved = json.loads(checkpoint.read_text())
        if saved.get('version_id') != version['id']:
            raise RuntimeError('Review checkpoint version mismatch.')
        manifest.update(status='submitted', source_commit=commit, build_id=build['id'], version_id=version['id'],
                        notes_sha256=fingerprint, submission_id=saved['submission_id'])
        write_json(manifest_path, manifest)
        print('Recovered the confirmed remote submission. Commit the updated release record.')
        return
    receipt = {**receipt, 'commit': commit, 'notes_sha256': fingerprint, **plan}
    write_json(receipt_path, receipt)
    test(argparse.Namespace(platform=args.platform, suite='all', only=None, staged=False, dry_run=False, simulator=None))
    if run(['git', 'status', '--porcelain'], capture=True).strip() or run(['git', 'rev-parse', 'HEAD'], capture=True).strip() != commit:
        raise RuntimeError('Source changed during validation; commit and validate again before publishing.')
    if hashlib.sha256(notes_text(path).encode()).hexdigest() != fingerprint:
        raise RuntimeError('Release notes changed during validation.')
    if build is None:
        if local_build(args.platform) != manifest['build']:
            raise RuntimeError('Local build differs from prepared release.')
        remote_next = asc('inspect', args.platform, local_build=0)['next_build']
        if remote_next > manifest['build']:
            raise RuntimeError('A newer build was uploaded since preparation; prepare a new build before uploading.')
        env = os.environ.copy()
        env.update(SNAPWELL_RELEASE_VERSION=args.version, SNAPWELL_RELEASE_BUILD=str(manifest['build']))
        receipt['upload_attempted'] = True
        write_json(receipt_path, receipt)
        log_directory = receipt_path.parent
        with (log_directory / 'archive-upload.log').open('a') as log:
            result = subprocess.run(['bash', 'dev.sh', '_archive-upload', args.platform], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=7200)
        if result.returncode:
            raise RuntimeError(f'Archive/upload failed. See {log_directory}/archive-upload.log; rerun publish after resolving the cause.')
        receipt['uploaded'] = True
        write_json(receipt_path, receipt)
    elif not receipt.get('uploaded'):
        raise RuntimeError('This build number already exists without an upload receipt; refusing to attach an unverified build.')
    finish_submission(args, manifest, receipt, receipt_path, path, manifest_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    check = commands.add_parser('doctor')
    check.add_argument('--platform', choices=('macos', 'ios', 'all'), default='all')
    check.add_argument('--apple', action='store_true', help='Verify API credentials using read-only Apple calls')
    tests = commands.add_parser('test')
    tests.add_argument('--platform', choices=('macos', 'ios', 'all', 'changed'), default='changed')
    tests.add_argument('--suite', choices=('logic', 'ui', 'all', 'tools', 'core'), default='all')
    tests.add_argument('--only')
    tests.add_argument('--staged', action='store_true')
    reuse = tests.add_mutually_exclusive_group()
    reuse.add_argument('--reuse-passing', action='store_true', dest='reuse_passing',
                       help='Reuse passing headless checks with unchanged inputs (default)')
    reuse.add_argument('--fresh', action='store_false', dest='reuse_passing',
                       help='Rerun headless checks even when unchanged passing results exist')
    tests.set_defaults(reuse_passing=True)
    tests.add_argument('--simulator')
    tests.add_argument('--dry-run', action='store_true')
    releases = commands.add_parser('release')
    releases.add_argument('action', choices=('prepare', 'publish', 'submit', 'status'))
    releases.add_argument('--platform', choices=('macos', 'ios'), required=True)
    releases.add_argument('--version', required=True)
    releases.add_argument('--locale')
    releases.add_argument('--wait-minutes', type=int, default=30)
    releases.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        if args.command == 'release':
            lock_path = Path(os.environ.get('TMPDIR', '/tmp')) / ('snapwell-release-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12] + '.lock')
            with lock_path.open('w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                release(args)
        else:
            {'doctor': doctor, 'test': test}[args.command](args)
    except (RuntimeError, subprocess.TimeoutExpired, OSError, ValueError) as error:
        print(f'Error: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
