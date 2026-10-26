# Public repository hygiene

## What may leave the machine

Commit application source, synthetic fixtures, user-facing change history, release notes,
and the release manifest. Required Apple bundle/team/app IDs and opaque build/review IDs
are identifiers, not authentication secrets; retain them where needed for signing or exact
release reconciliation. Keep actual API key IDs/issuer configuration outside the checkout.

Never commit or paste private keys, tokens, signing bundles/profiles, local environment
files, account/review contacts, personal home paths, device identifiers, real library data,
or raw test/upload/Apple responses. Logs, screenshots, archives and handoffs belong under
`.context/`, not in a public PR body or attachment. A gitignore rule alone is insufficient:
force-added files and earlier outgoing commits are checked too.

Git author and committer email addresses are public. Use your GitHub-provided no-reply
address in this repository's local Git configuration. Do not change global identity or
rewrite shared main history as a side effect of a release. Existing history and cached
copies require a separate, coordinated remediation if they contain private information.

## Enforced local and CI checks

`bash scripts/setup.sh` installs the tracked hook directory unless a custom hooksPath
already exists. Integrate both hooks if preserving a custom setup:

- Pre-commit scans the complete staged snapshot and configured author/committer identities,
  then runs/reuses headless tooling and core checks. Staged content is read from Git blobs;
  a safe unstaged copy cannot hide a private staged file, and symlinks are not followed.
- Pre-push scans every outgoing commit, including a secret added and removed in separate
  commits. The hook receives the destination remote and excludes only refs already known
  on that remote when pushing a new branch. It also requires no-reply commit identities.
- The Quality workflow checks the public snapshot/history without Apple or signing secrets.
  A separate ephemeral Mac job runs the affected isolated native and headless suites.
  Required checks must pass before the PR is approved/merged; a skipped or unavailable
  native service is not a pass. Branch-protection settings must enforce the checks remotely;
  adding workflow YAML does not configure repository protection rules.

Run `python3 scripts/check_public_content.py --all` before preparing a public diff and
`--history origin/main..HEAD` before publishing a branch. Diagnostics identify rules and
filenames without echoing the sensitive values. The scanner covers known patterns and
private artifact paths, not every possible form of PII or encoded secret. Review the diff,
PR body, commit identities and artifact contents as well. Never bypass a failed privacy
check or put real credentials in a test to prove the scanner works.

## CI logs and artifacts

The Quality workflow uses read-only repository permissions, does not persist checkout
credentials, and references actions by immutable commit IDs. It uses `pull_request`, not a
privileged workflow that executes PR code with signing secrets. Raw logs/xcresults remain
on the disposable runner. The only uploaded artifact is an allowlisted JSON summary:
source commit, suite pass states and native test counts. The exporter validates actual
xcresult bundles and requires positive counts with no failures or skips. It omits paths,
hostnames, device IDs, failure text and arbitrary Apple responses. Artifacts expire after
14 days. Public runner logs still need care: never add an environment dump or echo secrets.

Keep future release-signing jobs separate, trusted-main/manual-dispatch only, with a
short-lived keychain, explicit credentials, cleanup on every exit, and no raw artifacts.
Do not upload this Mac's private signing materials until the destination and credential
scope have been explicitly selected. See [release automation](release-automation.md).

## Release completion and cleanup

After submission, the release command independently reads Apple's version, build, notes,
publication policy and review membership/state. It writes a submitted record only after
that audit succeeds. Automatic publication after approval must be confirmed remotely.
`release verify` repeats this read-back without a new upload or submission.

Private receipts, review checkpoints and sanitized audits are backed up with user-only
permissions under `~/.appstoreconnect/releases/<platform>/<version>/`, outside every
workspace. A new workspace restores the complete saved attempt only when it has no local
receipt/checkpoint; it never combines different attempts. `SNAPWELL_RELEASE_STATE_DIR`
selects another private directory outside the repository, for an explicitly configured CI
or test environment. A failed backup blocks cleanup. The credential key is never copied.

`release cleanup` verifies Apple state again, backs up evidence, then removes only known
exports and temporary files in that exact release's `.context` directory. It refuses
symlinked paths. Archives/dSYMs, logs, receipts, notes, unrelated files and the user's other
simulators remain intact. `--dry-run` previews deletion without restoring/backing up or
removing files. Do not delete evidence to force a retry; do not clean the whole workspace
or alter another workspace as release housekeeping.

Finish by committing release/status records, running the public-content checks, pushing
the intended branch and updating its PR with concise, sanitized results. Preserve unrelated
changes. Follow CODEOWNERS/branch protection rather than merging or rewriting shared
history to make a status look clean. Record Apple failures and remaining setup explicitly.
