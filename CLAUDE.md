# Snapwell

Native AI media library: SwiftUI + SwiftData, macOS 15+ and iOS 17+.
The Mac app is the reference implementation; both apps share media and JSON sidecars.

## Route by task

- [Architecture and platform conventions](docs/architecture.md): storage, iCloud, state ownership, project generation and native interaction patterns.
- [Testing](docs/testing.md): validation commands, automation builds, fixtures and evidence.
- [Releases](docs/releases.md): changelog, build numbers, notes, upload and App Review.
- [Agent workflow](docs/workflows/agent-loop.md): task handoffs and focused reviews.
- [Change history](CHANGELOG.md): user-visible changes waiting to ship.

Load the relevant docs before editing that subsystem. Update the owning document in the
same task when its behavior changes. User instructions always take precedence.

## Essential invariants

- All sidecar mutations go through `MetadataSidecarService` (Mac) or `SidecarWriteService` (iOS).
- Analysis belongs to `ImportService` (Mac) or `AnalysisCoordinator` (iOS), never views.
- iOS UI state belongs in `AppState`. Persisted `isAnalyzing` is transient and reset on launch.
- Handle iCloud placeholders explicitly: request download and wait; unreadable storage is not an empty library.
- Use `modelContext.saveOrLog()`. Tests must never use the real library, database or credentials.
- Use `SupportedMedia` for Mac media extensions and UTTypes.
- Preserve mode locking in iOS full-screen gestures and respect Reduce Motion.
- After adding/removing Mac sources: `cd macos && xcodegen generate && scripts/post-xcodegen.sh`.
- iOS uses a hand-maintained project: register new files in its references, groups and build phases.
- App Store Connect is the source of truth for each platform's build numbers. Verify archive metadata before uploading.

## Completion

Run `./dev.sh test --platform changed --suite all` before handing off native work.
Headless checks reuse passing results for unchanged inputs by default; use `--fresh` only
when a fresh rerun is needed. The core suite is included in logic/all, even when native
services are blocked. Do not rerun it separately if that run already passed core.
Swift Testing is required for logic/integration tests; XCTest is allowed in native UI-test
targets only. Add regression tests for sync, import, sidecars, trash, spaces and model changes.
For view-only work, exercise relevant UI tests and inspect captured images; do not create
unit tests that merely mirror layout constants.

Before creating a PR (including a draft) for native changes, require passing results for
the affected platforms and suites against the latest relevant code. Run the checks
yourself whenever possible. If the agent environment blocks native testing, explain the
specific blocker and ask the user to run `./dev.sh test --platform changed --suite all`
from a normal Terminal. Wait for the results, inspect the logs, and resolve failures before
creating the PR. A successful build, skipped tests or an unavailable test service does not
count as a passing test run. Reuse passing results when the code they cover has not changed.
Pre-commit runs headless tooling/core checks and reuses unchanged passing results; it does
not repeat hosted native or UI tests. Keep the full native PR gate separate from committing.

Every user-visible change adds an entry to `CHANGELOG.md` in the same PR; otherwise state
that it has no user-visible change. Report what passed, what failed, and what could not run.
Screenshots, logs and local handoffs belong under `.context/`; preserve useful evidence.
