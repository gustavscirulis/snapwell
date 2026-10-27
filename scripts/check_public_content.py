#!/usr/bin/env python3
"""Scan Git blobs without printing sensitive matches. No dependencies or credentials."""
from __future__ import annotations
import argparse
import json
from pathlib import PurePosixPath
import re
import subprocess
import sys

RULES = {
    'private-key': re.compile(rb'-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----'),
    'local-apple-key-reference': re.compile(rb'AuthKey_[A-Z0-9]{10}\.p8'),
    'service-token': re.compile(rb'(?:sk-(?:proj-|ant-api)|gh[pousr]_)[A-Za-z0-9_-]{16,}'),
    'github-token': re.compile(rb'github_pat_[A-Za-z0-9_]{30,}'),
    'aws-access-key': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'signed-token': re.compile(rb'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{20,}'),
    'personal-home-path': re.compile(rb'/(?:Users|home)/(?!Shared/)[A-Za-z0-9_.-]+/'),
    'personal-email': re.compile(rb'[A-Za-z0-9._%+-]+@(?:gmail|icloud|me|outlook|hotmail|yahoo)\.com\b', re.I),
}
PRIVATE_PARTS = {'.context', '.appstoreconnect', 'xcuserdata'}
PRIVATE_SUFFIXES = {'.p8', '.p12', '.pfx', '.key', '.mobileprovision', '.provisionprofile',
                    '.keychain', '.keychain-db', '.xcuserstate', '.xcresult', '.ipa', '.xcarchive'}


def git(*args, data=None):
    return subprocess.check_output(['git', *args], input=data, stderr=subprocess.DEVNULL)


def private_path(name):
    path = PurePosixPath(name)
    return (bool(PRIVATE_PARTS.intersection(path.parts))
            or any(PurePosixPath(part).suffix.lower() in PRIVATE_SUFFIXES for part in path.parts)
            or (path.name.startswith('.env') and path.name not in ('.env.example', '.env.sample'))
            or name in ('.claude/settings.local.json', '.conductor/settings.local.toml'))


def findings(name, data):
    result = ['private-artifact'] if private_path(name) else []
    result.extend(rule for rule, pattern in RULES.items() if pattern.search(data))
    # Catch sensitive paths in symlink targets and filenames, too.
    encoded = name.encode()
    result.extend(rule for rule in ('personal-home-path', 'personal-email')
                  if RULES[rule].search(encoded) and rule not in result)
    return result


def blobs(entries):
    if not entries:
        return
    raw = git('cat-file', '--batch', data=b'\n'.join(oid for _, oid in entries) + b'\n')
    position = 0
    for name, _ in entries:
        end = raw.index(b'\n', position)
        header = raw[position:end].split()
        if len(header) != 3 or header[1] != b'blob':
            raise RuntimeError('Could not read Git blob')
        size = int(header[2])
        yield name, raw[end + 1:end + 1 + size]
        position = end + size + 2


def index_entries():
    entries = []
    for row in git('ls-files', '--stage', '-z').split(b'\0'):
        if not row:
            continue
        meta, name = row.split(b'\t', 1)
        mode, oid, stage = meta.split()
        if stage != b'0':
            raise RuntimeError('Resolve merge conflicts before the public-content check')
        if mode != b'160000':
            entries.append((name.decode('utf-8', errors='replace'), oid))
    return entries


def changed_entries(commit):
    names = git('diff-tree', '--root', '--no-commit-id', '--name-only', '--diff-filter=ACMT', '-r', '-m', '-z', commit).split(b'\0')
    names = [name.decode('utf-8', errors='replace') for name in names if name]
    if not names:
        return []
    entries = []
    for row in git('ls-tree', '-rz', commit, '--', *names).split(b'\0'):
        if not row:
            continue
        meta, name = row.split(b'\t', 1)
        mode, kind, oid = meta.split()
        if kind == b'blob':
            entries.append((name.decode('utf-8', errors='replace'), oid))
    return entries


def outgoing_commits(remote_name):
    commits = set()
    for line in sys.stdin:
        fields = line.split()
        if len(fields) != 4:
            raise RuntimeError('Invalid pre-push input')
        _, local, _, remote = fields
        if set(local) == {'0'}:
            continue  # Ref deletion has no new content.
        if not all(re.fullmatch(r'[a-f0-9]{40,64}', value) for value in (local, remote)):
            raise RuntimeError('Invalid Git object ID')
        args = ('rev-list', local, '--not', '--remotes=' + remote_name) if set(remote) == {'0'} else ('rev-list', remote + '..' + local)
        commits.update(git(*args).decode().splitlines())
    return sorted(commits)


def public_identity(email):
    return (email.endswith('@users.noreply.github.com') or email == 'noreply@github.com'
            or email.endswith('@example.invalid'))


def check_identity(commit=None):
    if commit:
        emails = git('show', '-s', '--format=%ae%n%ce', commit).decode().splitlines()
    else:
        emails = []
        for role in ('GIT_AUTHOR_IDENT', 'GIT_COMMITTER_IDENT'):
            identity = git('var', role).decode()
            match = re.search(r'<([^<>]+)>', identity)
            if not match:
                raise RuntimeError('Missing Git identity')
            emails.append(match[1])
    if commit:
        raw = git('cat-file', 'commit', commit)
        message = raw.split(b'\n\n', 1)[-1]
        if findings('commit-message', message):
            print(f'{commit[:12]}: private data pattern in commit message.', file=sys.stderr)
            return 1
    # Historical author emails are intentionally public Git metadata, not credentials.
    # Prefer no-reply for new local commits without forcing a history rewrite.
    if commit is None and not all(public_identity(email) for email in emails):
        label = commit[:12] if commit else 'configured Git identity'
        print(f'{label}: author-email privacy check failed; use a GitHub no-reply address.', file=sys.stderr)
        return 1
    return 0


def check(entries, label, seen):
    failures = 0
    fresh = []
    for name, oid in entries:
        if (name, oid) not in seen:
            seen.add((name, oid))
            fresh.append((name, oid))
    for name, data in blobs(fresh):
        rules = findings(name, data)
        if rules:
            # Filenames can themselves contain PII; redact and JSON-escape diagnostics.
            safe = name.encode()
            for rule in ('personal-home-path', 'personal-email'):
                safe = RULES[rule].sub(b'[redacted]', safe)
            print(f'{label}: {json.dumps(safe.decode(errors="replace"))}: {", ".join(rules)}', file=sys.stderr)
            failures += 1
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument('--all', action='store_true', help='Scan the complete Git index (default)')
    scope.add_argument('--staged', action='store_true', help='Scan the complete staged snapshot, not working files')
    scope.add_argument('--pre-push', action='store_true', help='Also scan every outgoing commit from Git hook input')
    scope.add_argument('--history', metavar='RANGE', help='Also scan changed blobs in each commit in a Git range')
    parser.add_argument('--remote', default='origin', help='Destination remote for the pre-push check')
    args = parser.parse_args()
    try:
        seen = set()
        failures = check(index_entries(), 'index', seen)
        if args.staged:
            failures += check_identity()
        commits = outgoing_commits(args.remote) if args.pre_push else (git('rev-list', args.history, '--').decode().splitlines() if args.history else [])
        for commit in commits:
            failures += check_identity(commit)
            failures += check(changed_entries(commit), commit[:12], seen)
        if failures:
            print('Public-content check failed. Remove private data; never bypass the hook to publish it.', file=sys.stderr)
            return 1
        print(f'Public-content check passed ({len(seen)} file versions; {len(commits)} outgoing commits).')
        return 0
    except (subprocess.CalledProcessError, RuntimeError, ValueError) as error:
        print(f'Public-content check could not finish ({type(error).__name__}); refusing to pass.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
