# Testing and agent verification

## Commands

- `./dev.sh doctor` checks local tools and simulator availability; `--platform macos` skips simulator checks.
- `./dev.sh test --platform changed --suite all` runs affected native suites and tooling checks.
- `./dev.sh test --platform all --suite all` validates both platforms when their native inputs need testing. Version-only releases reuse verified PR results.
- `./dev.sh test --platform macos --suite logic --only SnapwellTests/SyncWatcherIntegrationTests` narrows investigation.
- `./dev.sh test --platform ios --suite ui` runs native interaction checks.
- `./dev.sh test --suite tools` runs the Python orchestration and Swift release-client tests.
- `./dev.sh test --suite core` runs production model, filesystem and HTTP tests without an app host or simulator.
- Headless checks reuse passing results with unchanged inputs by default, including during agent-to-Terminal handoffs.
- `./dev.sh test --suite tools --fresh` forces a fresh headless run; `--fresh` also works with core/logic/all. Native tests always run when selected.
- `./dev.sh test --dry-run` reports selection without changing files or running tests.

Change selection includes the diff from `origin/main`, local tracked changes and untracked
files. `Shared/`, native fixtures, scripts and release-tool changes select both platforms.
`--staged` selects only staged paths for the Git pre-commit hook. Documentation/site-only
changes skip native validation. Run `bash scripts/setup.sh` to install tracked hooks; an
existing custom hooksPath is preserved with integration instructions. Both agents use the
same commands; no Claude-only hook masks exit status.

Pre-commit runs the headless tooling and core suites, using `--reuse-passing --staged`.
Hosted native and UI tests run at the PR gate, rather than again on every commit. A full
validation run also records reusable headless results, so committing the tested files does
not rerun those checks. Native results still need to pass before opening the PR. Successful native runs also verify
actual xcresult counts and save private input-bound evidence for release reuse.

Headless results include content fingerprints of their source, test, fixture, configuration
and runner inputs plus the Swift/Python toolchain and host OS version. Documentation-only
edits do not invalidate them. Added, deleted or modified inputs do; failures, timeouts,
missing logs and reports without fingerprints cannot be reused. A newer failure for the
same inputs takes precedence over an older pass. Inputs are checked before and after each
run; editing them during validation invalidates the result. Staged checks reject relevant
unstaged or untracked inputs so tests cannot accidentally validate different code from the
commit. Stage those inputs or stash them before committing. All test commands reuse verified
headless results by default; `--fresh` forces them to run again. `--reuse-passing` remains
supported for existing hooks and scripts. These options never skip native tests explicitly selected by `dev.sh test`. Release commands
reuse verified PR evidence for unchanged native inputs; version/build number changes alone
do not invalidate it. See [release automation](workflows/release-automation.md#validation-reuse).
When handing a blocked native run to a normal Terminal, use the same full command: already
passing headless checks are reused automatically. Do not separately rerun core after logic/all
already passed it. Reuse passing native evidence at the PR gate when the app, native tests,
and their build/test configuration have not changed; a headless-reuse-only runner change
requires tooling verification, not another run of unchanged native suites.

## Before creating a PR

Follow the verification gate in `CLAUDE.md`, including for draft PRs. Agents run checks
themselves where possible. If native execution is blocked, explain the blocker and ask
the user to run `./dev.sh test --platform changed --suite all` in a normal Terminal. Wait
for the results and inspect the logs before creating the PR. Required checks must pass
against the latest relevant code; builds, skips and unavailable services are not passes.
Documentation/site-only changes retain the native-test exemption described above.

## Isolation

All native test actions use **Automation**, not Debug/Release. This configuration defines
`SNAPWELL_AUTOMATION`, uses the `co.snapwell.automation` app identifier, removes production
iCloud/keychain entitlements, and redirects storage to per-run temporary directories.
SwiftData is in-memory, credentials are in-memory, iCloud migration/key sync is disabled,
and UI-test image/video AI calls and model discovery return deterministic fixture results.
Provider fixtures require the UI launch argument `--snapwell-fixture`; hosted logic tests
keep their injected provider clients so failure/retry tests exercise real service behavior.
Automation preferences are reset at launch; production preferences use a different bundle domain. Automation controls and
fixture generation are compiled out of Release.

Hosted unit tests also launch through this isolated configuration. Do not execute native
tests against normal Debug builds or physical devices with production data. Real cloud
and provider checks are a separate, explicit verification step.

The iOS runner creates one dedicated simulator per worktree, keeping normal simulator app
state separate, and waits for its boot services before XCTest installs or launches the app.
Native runs share a machine-wide lock to avoid competing for desktop UI.
`--simulator <UDID>` selects an explicitly chosen device instead. The runner does not reset
or delete unrelated simulators or kill the normal Snapwell app.

The iOS project's shared `Package.resolved` is tracked alongside its exact DialKit version.
Native runs use that lockfile without updating dependencies. Update the project requirement
and resolve/commit the lockfile together when changing a package version.

## Test selection and fixtures

Use Swift Testing for logic/integration tests and XCTest only for `SnapwellUITests`.
Keep in-memory containers and per-test temporary roots from the existing helpers.
Native UI fixtures cover empty and populated libraries; automation-only Import fixture
controls bypass the system picker while calling real import services. UI assertions still
exercise real image/video import and analysis, grid, search, space creation/assignment, detail and deletion behavior, with stable accessibility IDs.
The bundled `sidecar.json` and `spaces.json` are decoded and round-tripped by both native
logic-test targets. App Store builds exclude the video fixture and automation controls.
Generated image fixtures use explicit opaque RGBA pixels and correctly encoded PNG/JPEG
files. A shared regression test decodes both formats and verifies dimensions, opacity and
colors. Query iOS tab buttons by their accessible labels rather than requiring a `TabBar`
ancestor; the native tab presentation varies by OS and device layout. On Mac, choose the
visible context-menu item so a matching hidden menu-bar command cannot intercept the test.
Mac media clicks use the card's accessibility frame to send a real mouse event at its
center, after checking that the whole card is inside the app window. XCTest has reported
these visible cards as unhittable with the custom AppKit drag overlay present. Detail opening,
closing and reopening, visible context menus, deletion/Undo and space filtering remain
required assertions; a successful click alone is never a passing test.
iOS currently has no restore UI; Mac tests cover Undo restoration, while iOS covers deletion.

For sync, import, sidecar, trash, spaces and data-model changes, add targeted regression
tests. Reproduce a bug before fixing it where practical. Test cross-platform JSON against
the shared compatibility fixture rather than independently invented payloads.

## Core regression coverage

The `core` suite compiles links to actual production Swift sources into a generated SwiftPM
package under `.context/core-tests/`. It runs without `testmanagerd`, Simulator, an app launch,
real credentials or paid provider calls. Logic/all runs include it automatically; failures
remain failures even if a later native suite passes. It exercises the Mac provider implementation,
shared models and staging code, and the iOS share-import and local migration services. The same
shared HTTP, persistence and staging tests also run in both native hosted targets, covering the
iOS provider implementation there. Core success does not replace either platform's hosted/UI gate.

Coverage includes:

- On-disk SwiftData containers reopened between operations: media, analysis, memberships,
  guidance, durable cascade/nullify deletion, uncommitted edits and interrupted analysis recovery.
- Authenticated image request bodies and response envelopes for OpenAI, Anthropic, Gemini and
  OpenRouter; permanent HTTP errors, bounded rate-limit/server/timeout retries, malformed analysis,
  independent retry budgets and cancellation during backoff. HTTP interception is per session,
  with isolated response queues and no external requests. Test delays are injected.
- The share extension's actual staging transaction: image/video publication order, failure rollback,
  collision handling and safe filenames. Handoff tests cover import, repeat import, incomplete files,
  destination failure/retry, corrupt metadata, conflicting media and preserving enriched sidecars.
  The hosted iOS suite also verifies handoff through `SyncService` into SwiftData.
- Local-to-cloud migration using two temporary folders and isolated defaults: image/video copies,
  retry after failure, missing/corrupt files, placeholders, analysis and space conflict rules,
  spaces-only libraries, partial previous migrations and preserving unrelated local files/trash.

Native runs explicitly enable line coverage in their `.xcresult` bundles. Inspect app/extension
coverage separately from test-target coverage, for example:
`xcrun xccov view --report .context/testing/<run>/ios.xcresult`.
Core tests do not exercise Apple's share sheet/pickers, entitlement access, a physical device,
real cross-device iCloud delivery or subjective gesture/animation quality. Those remain release
checks; video playback, multi-touch gestures and full drag/drop UI still need broader coverage.

## Evidence and failures

Every executed run writes a unique `.context/testing/<run>/` directory containing full logs,
`.xcresult` bundles and `summary.json`. UI tests retain screenshots as result attachments
(the app window on Mac) and the accessibility hierarchy after a failure.
Failures, timeouts and unavailable toolchains fail the command; skips are reported explicitly.
The runner does not retry a failure into a success. Investigate the first failure and rerun
the smallest relevant case. Test helper logic changes with `--suite tools`.

This checkout initially reported an outdated CoreSimulator service after an Xcode update.
Use doctor first. Restart Xcode/Simulator and complete Xcode's first-launch component setup;
if it still fails, report the environment error instead of claiming that iOS tests passed.

Screenshots support inspection, not automatic proof of motion quality. Physical-device
sharing, real iCloud synchronization, entitlements and subjective animation polish remain
separate checks and must be called out when unverified.

If a constrained agent session rejects `sandbox-exec` while expanding Swift macros,
`SNAPWELL_DISABLE_MACRO_SANDBOX=1 ./dev.sh test …` disables that nested compiler sandbox
for the Automation build only and disables Xcode’s nested package-manifest sandbox for that run. This does not grant access to Apple's test-runner service.
A `com.apple.testmanagerd.control` sandbox error requires running the same command from
an environment with native test-service access, such as a normal local Terminal session.
Automation builds omit the app icon because Icon Studio export can require unavailable
Xcode services; release icon/signing checks still occur during the real archive.

## Public CI and privacy

The Quality workflow runs privacy checks on every PR and main push. Native selection
compares app/test/configuration fingerprints with the event's base revision, so version/build-only
changes reuse the tested base without rerunning native suites. Runner/tooling changes still
exercise both native platforms. Its ephemeral macOS
job uses the same affected-platform Automation command, without Apple accounts, real
provider credentials or signing secrets. The native exporter reads xcresult bundles and
requires positive native test counts, zero failures and zero skips. Failed CI runs print only allowlisted suite states for diagnosis. Only an allowlisted
source/suite/count summary from a fully passing run is retained for 14 days; raw logs and result bundles are not
published. A workflow definition is not passing evidence: inspect the actual run before
reusing it at the PR gate. See [public repository hygiene](workflows/public-repository.md).

Manual workflow runs use the separate `native-diagnostic` check name, even when selecting
all tests. They cannot replace the PR/main `native-validation` merge check. Partial test
selections never produce complete-suite release evidence.
