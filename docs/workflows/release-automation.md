# Fully delegated App Store releases

## Goal and current boundaries

The user says “bump the version and release both apps.” The agent picks patch versions,
checks each platform's next build number, drafts notes, commits the prepared changes,
runs required tests, archives/signs, verifies and uploads the binaries, fills version
metadata, attaches the exact builds, submits for review with AFTER_APPROVAL, and reports
Apple's state. Publication still depends on Apple's review.

The existing release commands implement that sequence for one platform and preserve
resumable receipts. Local credentials persist across Conductor workspaces outside Git.
Submission-only resume is implemented. A hosted runner is not yet installed or verified;
this document defines the setup, rather than claiming unattended releases are operational.

Two independent environment problems must be addressed:

- API reads/uploads can work while metadata/review writes are forbidden. A read-only
  doctor check cannot certify submission permissions.
- An agent's local sandbox can block testmanagerd, CoreSimulator, Icon Studio or Xcode
  signing services. Signing into Xcode does not change that sandbox or sign into a browser.

## One-time Apple setup

Use an App Manager credential for release metadata and App Review, rather than Admin.
For the narrowest app access, use an individual API key belonging to a dedicated App
Manager user restricted to Snapwell. Individual keys inherit that user's access and cannot
use provisioning endpoints. Explicit signing certificates/profiles are then managed separately.

A simpler alternative is a team key with App Manager access, created under App Store Connect
→ Users and Access → Integrations → App Store Connect API → Team Keys → Generate API Key.
Team keys apply to every app in the Apple account; their role cannot be edited later.
The account owner must make this access decision and create the credential. Do not revoke a
working upload key until its dependencies have been checked and the replacement is verified.

Download the .p8 once and save it outside the checkout, for example in
`~/.appstoreconnect/`. Configure the existing `snapwell.json` as described in
[Releases](../releases.md). The user can supply the key ID/path and issuer ID; private key
contents never belong in chat, Git, logs, screenshots or a release artifact. Validate reads,
then verify writes as part of the user's real authorized release. Do not claim a key's role
or write access based on successful reads alone.

For the prepared October 2026 releases, preserve the successful uploaded build receipts
and use submission-only resume after access is repaired. Neither build needs re-uploading.

## Recommended execution environment

Use a GitHub-hosted macOS runner, with the agent dispatching and monitoring a manual release
workflow. This is a separate CI execution environment with its own explicit credentials;
it does not require weakening Conductor's sandbox or giving arbitrary agents an unrestricted
local command service. A dedicated Mac CI host is an alternative if native UI tests prove
unreliable on hosted runners, but requires its own maintenance and access controls.

The concrete hosted workflow should:

1. Run only by explicit workflow dispatch from the trusted main branch. Release-preparation
   changes must be reviewed and landed before dispatch; never inject signing credentials
   into pull-request or fork builds. Verify the requested prepared versions and exact SHA.
2. Use a macOS 26 runner and an explicitly chosen supported Xcode 26 installation. Install
   XcodeGen, verify toolchains/runtimes, then run the existing isolated Automation suites for
   both platforms. Require actual xcresult evidence; unavailable UI services are failures.
3. After tests pass, load signing materials from GitHub environment secrets into a temporary
   keychain. Required identities are Apple Development (current archive configuration),
   Apple Distribution and Mac Installer Distribution, each with its private key. Install
   the app/share-extension provisioning profiles or explicitly configure a provisioning API
   credential. Never rely on an interactive Xcode account login on an ephemeral runner.
4. Supply API credentials through environment values, not a committed config. Archive/upload
   commands must pass explicit Xcode authentication arguments if using provisioning updates;
   the current interactive dev.sh implementation needs that integration before hosted use.
   Keep `manageAppVersionAndBuildNumber=false`; verify the iOS extension and universal Mac
   archive, privacy manifests, entitlements and signatures before upload.
5. Run publish/submit using the checked-in notes and exact build IDs. Serialize releases
   across both platforms and preserve failure status; do not retry invalid native tests
   into a green result or upload a duplicate build after an ambiguous response.
6. Always retain test logs/xcresults, sanitized upload logs, receipts, review checkpoints and
   final manifests as restricted artifacts with a defined retention period. Exclude keys,
   certificates, profiles, temporary keychains and export options containing sensitive data.
   Restore the exact prior receipt on a resume; do not guess based on a build number alone.
7. Remove temporary credentials and keychains in an always-run cleanup step. Use minimal
   GitHub token permissions and actions pinned to immutable commits. The agent downloads
   the records, verifies them against Apple and commits the resulting submission records;
   CI does not need a repository-write token merely to publish an Apple app.

Suggested encrypted secret inventory: API private key, key ID and optional issuer ID;
signing certificate/private-key bundle plus its password; provisioning profile bundle.
Create a fresh random temporary-keychain password per run. Keep this separate from source
and never auto-export a developer's whole login keychain.

Before enabling unattended dispatch, perform one controlled end-to-end run and verify both
platforms' hosted native tests, signatures, Apple upload, metadata writes and review states.
A workflow file alone is not proof that this setup works. Reconcile any already uploaded
builds first. Inspect Actions availability and billing before enabling regular use.

## Routine agent behavior after setup

The release request is the approval to execute this workflow. The agent handles preparation,
notes, dispatch, monitoring, recovery, submission and record keeping. Ask the user only for
an unavoidable account action, legal agreement, missing factual compliance answer, or a
materially changed release scope. Report the exact blocker and preserve all progress.

## Primary references

- [Apple: submit an app and required roles](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- [Apple: API key types and provisioning limits](https://developer.apple.com/documentation/AppStoreConnectAPI/creating-api-keys-for-app-store-connect-api)
- [Apple: create and manage API keys](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/)
- [GitHub: installing Apple signing materials on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [GitHub: available macOS runner images](https://github.com/actions/runner-images)
