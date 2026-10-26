"""Private release evidence and narrowly scoped, resumable cleanup."""
import json
import os
from pathlib import Path
import shutil
import tempfile

EVIDENCE = ('receipt.json', 'submission.json', 'submission-audit.json')
DISPOSABLE = ('ExportOptions-Upload.plist', 'ExportOptions-Offline.plist',
              'offline-export', 'temporary')


def atomic_private(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, name = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as output:
            output.write(data)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def private_root(repository):
    root = Path(os.environ.get('SNAPWELL_RELEASE_STATE_DIR', '~/.appstoreconnect/releases')).expanduser().absolute()
    if root.resolve().is_relative_to(Path(repository).resolve()):
        raise RuntimeError('Durable release evidence must stay outside the repository')
    return root


def protect(directory):
    if directory.is_symlink():
        raise RuntimeError('Private evidence directory must not be a symlink')
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)


def backup(directory, repository):
    """Keep receipts when a Conductor workspace is removed; never copy credentials."""
    root = private_root(repository)
    protect(root)
    platform, version = directory.parent.name, directory.name
    target = root / platform / version
    protect(target.parent)
    protect(target)
    previous = target / 'receipt.json'
    current = directory / 'receipt.json'
    if previous.is_file() and current.is_file():
        old, new = json.loads(previous.read_text()), json.loads(current.read_text())
        identity = ('commit', 'platform', 'version', 'build', 'notes_sha256')
        if (any(old.get(key) != new.get(key) for key in identity)
                or (old.get('uploaded') is True and new.get('uploaded') is not True)):
            raise RuntimeError('Durable evidence belongs to a different release attempt; inspect before overwriting')
    for name in EVIDENCE:
        source = directory / name
        if source.is_symlink():
            raise RuntimeError('Release evidence must not be a symlink')
        if source.is_file():
            atomic_private(target / name, source.read_bytes())


def restore(directory, repository):
    root = private_root(repository) / directory.parent.name / directory.name
    # A current worktree receipt is authoritative; never combine a new attempt with
    # another worktree's old checkpoint or overwrite ambiguous evidence.
    if (directory / 'receipt.json').exists() or (directory / 'receipt.json').is_symlink():
        return
    if not (root / 'receipt.json').is_file():
        return
    if any((directory / name).exists() or (directory / name).is_symlink() for name in EVIDENCE):
        raise RuntimeError('Partial local release evidence needs inspection before restore')
    for name in EVIDENCE:
        source = root / name
        if source.is_symlink():
            raise RuntimeError('Release evidence must not be a symlink')
        if source.is_file():
            atomic_private(directory / name, source.read_bytes())


def cleanup(directory, repository, receipt, audit, dry_run=False):
    """Remove exports/temporary files only after audited submission and evidence backup."""
    if (receipt.get('uploaded') is not True or audit.get('notes_verified') is not True
            or audit.get('build_id') != receipt.get('build_id')
            or audit.get('version_id') != receipt.get('version_id')
            or audit.get('release_type') != 'AFTER_APPROVAL'
            or audit.get('version_state') not in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_APPLE_RELEASE',
                                                 'PROCESSING_FOR_DISTRIBUTION', 'READY_FOR_DISTRIBUTION', 'READY_FOR_SALE')):
        raise RuntimeError('Cleanup requires a successful upload and matching verified submission')
    expected = Path(repository) / '.context' / 'releases' / directory.parent.name / directory.name
    if directory.absolute() != expected.absolute():
        raise RuntimeError('Cleanup path is not the release-owned directory')
    # Reject redirects anywhere in the deletion path, including a symlinked .context.
    for path in (directory, *directory.parents):
        if path.is_symlink():
            raise RuntimeError('Cleanup refuses symlinked release paths')
        if path == Path(repository):
            break
    targets = [directory / name for name in DISPOSABLE if (directory / name).exists() or (directory / name).is_symlink()]
    if any(path.is_symlink() for path in targets):
        raise RuntimeError('Cleanup refuses symlinked artifacts')
    if not dry_run:
        backup(directory, repository)  # A backup failure must prevent deletion.
        for path in targets:
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
    return [path.name for path in targets]
