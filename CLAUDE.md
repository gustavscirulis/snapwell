# Snapwell

Native AI media library: SwiftUI + SwiftData, macOS 15+ and iOS 17+.
The Mac app is the reference implementation; both apps share media and JSON sidecars.

## Route by task

- [Architecture and platform conventions](docs/architecture.md): storage, iCloud, state ownership, project generation and native interaction patterns.
- [Testing](docs/testing.md): validation commands, automation builds, fixtures and evidence.
- [Releases](docs/releases.md): changelog, build numbers, notes, upload, App Review and public-content updates. A request to release delegates notes, submission, relevant site/help-center updates and automatic publication after approval; follow the release runbook without asking the user to repeat these steps.
- [Public repository hygiene](docs/workflows/public-repository.md): privacy hooks, commit identity, private validation artifacts, durable release evidence and safe cleanup.
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

Testing and privacy checks run locally; there are no GitHub validation workflows.
Choose validation in proportion to the change. Do not automatically run full native or UI
suites before every handoff. Use the narrowest check that can catch a realistic regression,
and skip automated tests for trivial copy, icon, spacing or other visual-only edits when code
inspection or a direct preview is sufficient. Run full affected-platform suites for broad or
cross-cutting changes, release work, explicit user requests, or when narrower evidence cannot
establish confidence.
Headless checks reuse passing results for unchanged inputs by default; use `--fresh` only
when a fresh rerun is needed. The core suite is included in logic/all, even when native
services are blocked. Do not rerun it separately if that run already passed core.
Swift Testing is required for logic/integration tests; XCTest is allowed in native UI-test
targets only. Add regression tests for sync, import, sidecars, trash, spaces and model changes.
For view-only work, prefer direct inspection or a focused preview. Exercise UI automation only
when the change affects interaction, accessibility, navigation, persistence or a user flow;
do not create unit tests that merely mirror layout constants.

Before creating a PR (including a draft), perform the risk-based checks relevant to the
change and report what was intentionally not run. Full native suites are required only when
the scope or risk calls for them, not merely because native files changed. If a required
native check is blocked by the agent environment, explain the specific blocker and ask the
user to run that same focused command from a normal Terminal. A successful build, skipped
tests or an unavailable test service does not count as a passing required check. Reuse
passing results when the code they cover has not changed.
Pre-commit runs headless tooling/core checks and reuses unchanged passing results; it does
not repeat hosted native or UI tests. Keep any risk-based native PR validation separate from
committing.

Every user-visible change adds an entry to `CHANGELOG.md` in the same PR; otherwise state
that it has no user-visible change. Report what passed, what failed, and what could not run.
Screenshots, logs and local handoffs belong under `.context/`; preserve useful evidence.
Before committing or pushing, run the public-content checks and use a GitHub no-reply
commit identity. Never publish credentials, personal paths/contact details or raw artifacts.
Complete releases with the independent Apple audit, durable private evidence backup and
scoped cleanup, then commit the release records and update the PR. Reuse verified PR native
evidence for version-only bumps. If signing is sandbox-blocked, use the single local Terminal
upload handoff; keep secrets on the Mac. Follow
[public repository hygiene](docs/workflows/public-repository.md); do not claim unattended
signing is configured until a credentialed release runner has passed a real verification.

Every release also reviews the actual user-visible changes since the preceding release on
that platform. Prepare and validate any relevant `site/` and Help Center updates before
submission, include tracked site changes in the release PR, and publish applicable Help
Center changes with `fin` during the App Store submission phase. Keep landing-page changes
minimal unless a release materially changes positioning or setup. Re-fetch changed articles
and verify the site after its normal merge/deployment. Platform-specific releases update only
applicable content; explicitly record when reliability-only or visual-polish work needs no
public-content change.
