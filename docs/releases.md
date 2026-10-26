# Releases

Agents maintain `CHANGELOG.md` in the same change as every user-visible improvement.
Each entry has a permanent unique ID: `- [short-change-id] User-facing benefit.`
Group unreleased changes under `macOS`, `iOS`, or `Both`. Release manifests record which
entries shipped on each platform; a shared entry remains pending on the other platform.
Do not invent historical release notes. Existing entries are a starting point for future releases.

## Delegating a release

A user request such as “bump the version and release iOS and Mac” authorizes the agent to
prepare, draft notes, validate, upload, fill the version metadata, submit for App Review,
and choose automatic publication after approval. Do not ask the user to write notes or
click Submit for Review when suitable API access is configured. Default an unspecified
version bump to the next patch version of each platform independently, after checking
Apple's versions and build numbers. Preserve existing store descriptions, screenshots,
privacy information and review contact details unless the release requires changes.
Answer new required compliance questions from verified app facts; ask only when a required
answer cannot be established. Legal agreements and account ownership remain human tasks.

Draft notes from the platform's unshipped changelog entries and the actual changes. Complete
all authorized steps and report Apple's exact state. Uploaded/VALID is not submitted;
submitted is not approved or released. Resume a partially completed release before creating
another version or uploading another build. Read the saved receipt and Apple state first.

For unattended native tests and signing, see the concrete
[release automation setup](workflows/release-automation.md). Local API credentials alone do
not give an agent sandbox access to Apple's native services.

## One-time local configuration

For automatic access across local Conductor workspaces, create
`~/.appstoreconnect/snapwell.json` on your Mac (outside every repository):

```json
{
  "key_path": "/absolute/path/to/AuthKey_YOUR_KEY_ID.p8",
  "key_id": "YOUR_KEY_ID",
  "issuer_id": "YOUR_ISSUER_ID"
}
```

Use the existing private key; the configuration contains only identifiers and its path.
For an individual key, omit `issuer_id`. Keep the directory private (`chmod 700
~/.appstoreconnect`) and the JSON and `.p8` files readable only by your macOS user
(`chmod 600` on each file). Never copy these files into workspaces or cloud environments.
The helper loads this file directly, so new workspaces need no shell exports, copied
`.env`, browser login or remembered chat context. Other processes running as your macOS
user can also read these files; filesystem permissions do not isolate one agent from another.

Alternatively, export `ASC_KEY_PATH` (absolute path to the existing .p8 outside the repository),
`ASC_KEY_ID`, and `ASC_ISSUER_ID` for a team key. Environment values override local fields;
setting both key path and key ID bypasses the local configuration entirely, so an individual
environment key does not inherit a team issuer. An empty `ASC_ISSUER_ID` clears a local issuer.
`ASC_APP_ID` defaults to Snapwell's `6762541353`; the helper verifies the bundle ID.
Never commit keys or tokens. The key must permit version metadata and App Review submissions.
Xcode must have the signing certificates/profiles needed to archive both apps.

Use the narrowest Apple permissions suitable for releases. Team keys apply to all apps;
an individual key inherits its user's app access, so an App Manager user limited to Snapwell
can provide narrower app access. The local configuration makes commands available; it is
not standing authorization to publish. Live publication still requires a user release request.

Run `./dev.sh doctor --platform macos --apple` to verify read-only API access. A successful
read does **not** prove permission to change metadata or submit a review. Apple requires
Account Holder, Admin or App Manager for submission. A 403 for version creation/submission
requires a suitable replacement key; team-key roles cannot be edited after creation.

## Prepare, draft, validate, publish

1. `./dev.sh release prepare --platform macos --version 1.0.8 --dry-run`
2. Remove `--dry-run` to update the authoritative version/build settings and create
   `releases/macos/1.0.8/release.json` and `en-US.txt`. iOS is prepared independently.
3. The working agent drafts **2–4 concise • bullets** in that notes file from the selected
   changelog entries. Combine related improvements; omit implementation details. Never
   ask a release subprocess to invent marketing copy. The default locale uses the existing English primary locale returned by Apple;
   use `--locale` for another existing English localization.
4. Review and commit the prepared release. `./dev.sh release publish --platform macos --version 1.0.8 --dry-run`
   reads Apple state and prints the exact notes, version, build and publication policy.
5. Invoke the same publish command without `--dry-run` when releasing. It runs the full
   platform test suite, archives and verifies metadata, uploads, waits for processing,
   updates What's New, attaches the exact build, and **submits for App Review** with
   **automatic publication after approval**. This is the live release action.
6. The command independently verifies the exact remote build, notes, review and publication policy, backs up private evidence, and cleans temporary exports. Commit the updated submission record. `./dev.sh release status --platform macos --version 1.0.8`
   reads Apple's status and marks the release as distributed only after Apple confirms it.

If upload succeeded and only processing/notes/review remain, use
`./dev.sh release submit --platform macos --version 1.0.8` (and independently for iOS).
This path never runs native tests, archives or uploads. It requires the original successful
upload receipt, unchanged native source/build inputs, identical notes, and the exact Apple
build with a matching marketing version. Tooling/docs or another release record may advance
without discarding the original uploaded source commit. It saves submission checkpoints and
recovers a confirmed remote submission after interruption. Do not use it to bypass failed
validation or fabricate an upload receipt.

The API helper compiles once per command with a separate build timeout, then executes the
prebuilt binary for Apple requests. Swift compilation cannot consume the request timeout.

Use `./dev.sh release verify --platform macos --version 1.0.8` to repeat the independent
read-back without resubmission. Use `release cleanup` with the same platform/version to
verify, back up, and remove known temporary exports; add `--dry-run` to preview cleanup.
Archives, symbols, logs and receipts are retained. Private evidence is automatically backed
up outside the repository and restored in new workspaces; see
[public repository hygiene](workflows/public-repository.md) for permissions and scope.

`release status --dry-run` does not change release records or restore/back up evidence. Publishing requires a
clean prepared revision and validated notes. Artifacts and resumable receipts live under
`.context/releases/`. A processing timeout is resumable; failed builds and API errors are
reported as failures. If an upload is interrupted before success can be recorded, the
command refuses to attach an ambiguous existing build; inspect the saved upload log and
Apple state before reconciling the receipt. Review drafts are resumed only when their
IDs match the saved checkpoint. Do not erase a receipt to force an upload or attach an unverified build.

Native archive/upload orchestration remains in root `dev.sh`; the Swift helper only
handles API authentication, read/write metadata and submission. Normal interactive
Run locally and archive/upload choices remain available.

## Versioning invariants

**App Store Connect is the source of truth for build numbers.** Builds may have been uploaded without a corresponding Git commit, so never infer the next `CFBundleVersion` only from `CURRENT_PROJECT_VERSION`, Git history, or the other platform.

Before bumping versions or preparing an App Store archive:

1. Find the highest build number already uploaded to App Store Connect for **macOS and iOS separately**. Query App Store Connect when credentials are available; otherwise ask for the latest uploaded number for each platform.
2. Set each platform's `CURRENT_PROJECT_VERSION` strictly higher than its own latest uploaded build. The Mac and iOS build numbers do not need to match.
3. For macOS, update `macos/project.yml`, then run `cd macos && xcodegen generate && scripts/post-xcodegen.sh`. Do not edit only the generated `.pbxproj`.
4. For iOS, update the app and share-extension build settings in `ios/Snapwell.xcodeproj/project.pbxproj`.
5. Build or archive each changed platform and inspect the resulting app's `Info.plist` to verify both `CFBundleShortVersionString` and `CFBundleVersion` before reporting completion or uploading.

When handing off a release, explicitly report the verified marketing version and build number for each platform.


## Verification boundaries

Test the tooling using mocked Apple responses and dry runs. Implementing release tooling
is not an instruction to publish a real app version. During development, use read-only
API calls to verify configuration; live release commands are invoked for actual releases.
