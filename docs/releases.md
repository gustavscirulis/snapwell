# Releases

Agents maintain `CHANGELOG.md` in the same change as every user-visible improvement.
Each entry has a permanent unique ID: `- [short-change-id] User-facing benefit.`
Group unreleased changes under `macOS`, `iOS`, or `Both`. Release manifests record which
entries shipped on each platform; a shared entry remains pending on the other platform.
Do not invent historical release notes. Existing entries are a starting point for future releases.

## One-time local configuration

Export `ASC_KEY_PATH` (absolute path to the existing .p8 outside the repository),
`ASC_KEY_ID`, and `ASC_ISSUER_ID` for a team key. Individual keys omit issuer ID.
`ASC_APP_ID` defaults to Snapwell's `6762541353`; the helper verifies the bundle ID.
Never commit keys or tokens. The key must permit version metadata and App Review submissions.
Xcode must have the signing certificates/profiles needed to archive both apps.

Run `./dev.sh doctor --platform macos --apple` to verify read-only API access.

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
6. Commit the updated submission record. `./dev.sh release status --platform macos --version 1.0.8`
   reads Apple's status and marks the release as distributed only after Apple confirms it.

`release status --dry-run` is read-only, including local files. Publishing requires a
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
