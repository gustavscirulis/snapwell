# Delegated releases with one local Terminal handoff

## Default workflow

Keep Apple API credentials in the existing private machine-local configuration and signing
identities in the Mac's Keychain. Do not introduce GitHub signing secrets, export the login
keychain, install an unrestricted agent command service, or weaken Conductor's sandbox.
The user prefers one explicit local Terminal command when native Apple services are blocked.

A request to bump and release delegates version/build selection, notes, preparation, review
submission, verification, public records and scoped cleanup to the agent. The agent:

1. Reads Apple state and private receipts first, resuming existing work rather than uploading
   another build. Prepares each platform's next patch/build and drafts its checked-in notes.
2. Reuses the passing PR validation for unchanged app/test/build inputs. A version-only bump
   does not require another native run. Imports hosted evidence when needed, verifies its
   fingerprint and commits the prepared versions/notes before any Terminal handoff.
3. Runs the release itself where Apple services permit. If the sandbox blocks native signing,
   supplies this single command from the prepared workspace root:

   ```bash
   ./dev.sh release upload --platform all
   ```

4. Inspects the saved upload receipts/logs when the command finishes. Uses `release submit`
   independently for each prepared platform to wait for processing, fill notes, attach the
   exact build and submit for review with automatic publication after approval. No second
   Terminal command is normally needed for metadata or review.
5. Independently reads Apple state back, backs up private evidence, cleans only temporary
   exports, commits the submission records, pushes and updates the PR with sanitized results.

The Terminal command discovers the two versions from their authoritative project settings
and requires matching prepared manifests, notes and a clean revision. It checks both plans
before uploading, reuses verified native evidence, and validates any genuinely untested
platform before either upload. It stops if source changes, preserves progress on failure,
and does not repeat a receipted upload just because Apple has not exposed the build yet.
It never invents release notes or silently picks an unprepared version.

`./dev.sh release upload --platform all --dry-run` previews both plans without tests,
archives, uploads, receipt restoration or writes. This release is already submitted;
do not run another upload merely to verify the new handoff command.

## Validation reuse

Native runs require actual xcresult summaries with positive test counts and zero failures
or skips. Passing evidence is stored with private permissions outside workspaces under
`~/.appstoreconnect/validation/`, keyed by the platform's app, tests, fixtures, entitlements,
shared source and build configuration contents. Version/build fields are normalized; Mac
configuration uses authoritative `project.yml`, since the project is regenerated for tests
and archives. Other source/configuration changes invalidate the evidence.

A newer failed or incomplete native run blocks release reuse of an older pass for the same
inputs. An intentional fresh `dev.sh test` run can replace it after all tests pass. Missing
evidence requires validation; a successful archive is never substituted for passing tests.

For hosted PR validation, the agent runs:

```bash
python3 scripts/native_validation.py import-ci --run RUN_ID
```

This reads GitHub's successful Quality run and retained artifact directly, checks its tested
Git commit and native fingerprints against Git source, validates counts, and saves only the
allowlisted evidence privately. It does not trust a pasted success claim or import arbitrary
logs. Import it when completing PR validation so the evidence survives workspace removal and
artifact expiration. Local native runs save equivalent verified evidence automatically.
`SNAPWELL_VALIDATION_STATE_DIR` can select a private directory outside the repository for tests.

The Quality workflow remains secret-free validation only. A credentialed hosted release
runner is not configured or required for the preferred local handoff.

## Archives, interruptions and cleanup

New archives use unique attempt directories under
`.context/releases/<platform>/<version>/archives/`. Another release or retry must not delete
an earlier archive. Both app/extension versions and signatures are checked; Mac archives
must contain both arm64 and x86_64. Export options and upload intermediates stay in the exact
release-owned temporary paths.

A confirmed upload receipt survives metadata errors and new workspaces. After an ambiguous
upload failure, inspect Apple and the private log before retrying; never fabricate success
or erase evidence to force another upload. API permission errors require an appropriate
App Manager key; legal agreements and unknown factual compliance answers remain human tasks.
See [Releases](../releases.md) for key configuration and submission-only resume, and
[public repository hygiene](public-repository.md) for audit, backup, cleanup and privacy rules.

## Primary references

- [Apple: submit an app and required roles](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- [Apple: API key types](https://developer.apple.com/documentation/AppStoreConnectAPI/creating-api-keys-for-app-store-connect-api)
- [Apple: manage API keys](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)
