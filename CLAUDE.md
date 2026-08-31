# Snapwell

Native, AI-powered media library for collecting, organizing, and analyzing images and videos. Two native apps share the same `~/Documents/Snapwell/` storage.

| Project | Location | Stack |
|---------|----------|-------|
| Mac app (primary) | `/macos/` | SwiftUI + SwiftData, macOS 15+ |
| iOS companion app | `/ios/` | SwiftUI + SwiftData, iOS 17+ |

The Mac app is the reference implementation. iOS matches its patterns.

## Shared file storage

All apps read/write the same structure. iOS syncs via iCloud.

```
~/Documents/Snapwell/
├── images/     (media files: {id}.png, {id}.mp4, etc.)
├── metadata/   (sidecar JSON: {id}.json — same ID as media)
├── thumbnails/ (generated: {id}.jpg)
├── spaces.json (space definitions + guidance config)
├── .trash/     (auto-emptied after 30 days)
└── queue/      (mobile import staging, auto-watched by Mac)
```

## iOS app

Syncs media and spaces via iCloud. Can run AI analysis and write results back to sidecars. The only external dependency is [DialKit](https://github.com/mikelikesdesign/dialkit-ios) (pinned to 0.3.0), a **DEBUG-only** dev tool — every reference lives inside `#if DEBUG`, isolated to `Views/Debug/DebugDialOverlay.swift`. Its floating panel triggers the nudge sheets on demand and tunes their layout live; Release builds reference no DialKit symbols.

Note the iOS project does **not** use XcodeGen — `ios/Snapwell.xcodeproj/project.pbxproj` is hand-maintained, so a new Swift file needs a `PBXFileReference`, a `PBXBuildFile`, a group `children` entry, and a `Sources` build-phase entry. Files added inside `Assets.xcassets` need no pbxproj edit.

**iCloud handling is critical** — files may exist as `.icloud` placeholders. All loading code must detect placeholders, trigger downloads with `startDownloadingUbiquitousItem()`, and wait for completion.

**Folder access** uses security-scoped URL bookmarks via `FileSystemManager`. User picks the Snapwell folder once on first launch.

**FullScreenImageOverlay gestures** use a mode-locking pattern (dismiss/scroll/swipe/zoom lock on first touch). Respect this when modifying gesture code.

Bundle ID: `co.snapwell`.

## Mac app

Uses XcodeGen — run `cd macos && xcodegen generate && scripts/post-xcodegen.sh` after adding/removing Swift files. The post-xcodegen script patches the `AppIcon.icon` file type in the generated `.pbxproj` (XcodeGen doesn't know the `folder.iconcomposer.icon` type).

Bundle ID: `co.snapwell`.

## App Store releases

**App Store Connect is the source of truth for build numbers.** Builds may have been uploaded without a corresponding Git commit, so never infer the next `CFBundleVersion` only from `CURRENT_PROJECT_VERSION`, Git history, or the other platform.

Before bumping versions or preparing an App Store archive:

1. Find the highest build number already uploaded to App Store Connect for **macOS and iOS separately**. Query App Store Connect when credentials are available; otherwise ask for the latest uploaded number for each platform.
2. Set each platform's `CURRENT_PROJECT_VERSION` strictly higher than its own latest uploaded build. The Mac and iOS build numbers do not need to match.
3. For macOS, update `macos/project.yml`, then run `cd macos && xcodegen generate && scripts/post-xcodegen.sh`. Do not edit only the generated `.pbxproj`.
4. For iOS, update the app and share-extension build settings in `ios/Snapwell.xcodeproj/project.pbxproj`.
5. Build or archive each changed platform and inspect the resulting app's `Info.plist` to verify both `CFBundleShortVersionString` and `CFBundleVersion` before reporting completion or uploading.

When handing off a release, explicitly report the verified marketing version and build number for each platform.

### Archive and upload workflow

Run `./dev.sh`, choose the Mac or iOS app, then choose one of the platform actions:

- **Run locally** uses the existing local device or simulator workflow.
- **Publish to the App Store** shows the configured marketing/build versions, requires confirmation that the build exceeds App Store Connect, creates a signed archive, verifies the archived metadata, and uploads it with Xcode. The iOS workflow also verifies that the app and share extension versions match. Xcode must be signed in to the correct Apple developer account.
- Uploading does **not** submit the version for App Review. After processing, select the build, add the What's New text, and submit from App Store Connect.

The interactive archive/upload implementation lives in the root `dev.sh`; keep the release path there rather than splitting it across new scripts. Never run an upload until the App Store Connect build-number check and version bump above are complete.

### What's New copy

Write App Store What's New text as 2–4 concise, user-facing bullets. Start every line with `•`, keep one benefit or fix per bullet, and omit headings, implementation details, provider error codes, and internal terminology. Describe what improved for the user rather than how the code changed.

## Architecture patterns

**iOS AppState**: UI state lives in `AppState` (`@Observable @MainActor`), not scattered `@State` on views. Match this pattern for new state.

**Analysis coordination**: AI analysis logic lives in `AnalysisCoordinator` (iOS) and `ImportService` (Mac), NOT in views.

**Sidecar writes**: ALL sidecar JSON mutations go through `SidecarWriteService` (iOS) or `MetadataSidecarService` (Mac). NEVER write sidecar JSON directly in views.

**Supported media types**: Use `SupportedMedia` enum (Mac) for file extensions and UTTypes. Don't define inline extension sets.

**SwiftData saves**: Use `modelContext.saveOrLog()` (not `try? modelContext.save()`). The `saveOrLog()` extension logs errors and asserts in DEBUG to prevent silent data loss.

**`isAnalyzing` is transient** — it's persisted on `MediaItem` but represents in-flight state. Both apps reset stuck flags on launch. Don't add more persisted transient flags; track ephemeral state on coordinators instead.

**One-time nudges (iOS)**: eligibility and "already seen" state live in `NudgeStore` (pure logic over `UserDefaults`, injectable for tests); `MainView.evaluateNudges()` runs after every `loadContent()` and presents at most one. Add new nudges as `Nudge` cases with a rule in `nextNudge`, ordered by priority — never stack two modals.

## Testing

Both native apps use Swift Testing (`import Testing`, `@Test`, `@Suite`, `#expect`). Do NOT use XCTest for new tests. Tests run automatically via pre-commit hook (`.claude/scripts/run-tests-for-staged.sh`).

```bash
# Mac tests
cd macos && xcodegen generate && scripts/post-xcodegen.sh && xcodebuild test -project Snapwell.xcodeproj -scheme Snapwell -destination 'platform=macOS' 2>&1 | xcbeautify --quiet

# iOS tests
cd ios && xcodebuild test -project Snapwell.xcodeproj -scheme Snapwell -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | xcbeautify --quiet
```

### When to add tests

**Always add tests when changing:**
- Sync logic (`SyncWatcher`, `SyncService`) — cross-platform sync has been the #1 source of regressions
- Import flow (`ImportService`, `ImageImportService`) — ordering bugs (save-before-sidecar, double-analysis) are hard to catch otherwise
- Sidecar read/write (`MetadataSidecarService`, `SidecarWriteService`) — format changes break cross-platform compat
- Trash/restore (`MediaStorageService.moveToTrash`, `MediaDeleteService`) — rollback logic is subtle
- Spaces sync (spaces.json parsing, space assignment) — empty-array edge cases have caused bugs
- Data model changes (`MediaItem`, `AnalysisResult`, `Space`) — relationship and cascade behavior

**Skip tests for:** View-only changes, animation tweaks, layout adjustments.

### Test infrastructure

**SwiftData tests** use in-memory containers via `TestContainer.create()` — never touch the real database.

**Integration tests** use temp directories via `IntegrationTestSupport.makeTempRoot()` — creates `/tmp/SnapwellTests/{UUID}/` with the full directory structure. Each test gets its own unique dir; safe for parallel runs across git worktrees.

**Injectable services (Mac):** `MediaStorageService(baseURL:)`, `MetadataSidecarService(storage:)`, `SyncWatcher(storage:sidecarService:)`, and `ImportService(storage:sidecarService:)` all accept injected dependencies for testing. Production code uses default `.shared` singletons.

**iOS services** already accept `rootURL` parameters — no injection needed.

**Test tags:** `.integration`, `.sync`, `.filesystem`, `.model`, `.parsing`, `.crypto`, `.serialization`, `.search`, `.state`, `.layout`.

**Access levels:** Change `private` to `internal` (Swift default) to make methods testable. Use `@testable import Snapwell`.

## Browser screenshots

Save all browser screenshots and visual testing artifacts to `.screenshots/` (gitignored). When using Chrome DevTools MCP or Playwright MCP, always pass a `filePath` inside `.screenshots/` to avoid dumping images in the repo root. The `.playwright-mcp/` directory is also gitignored for Playwright's default output.

## Common gotchas

- Check `@Environment(\.accessibilityReduceMotion)` / `UIAccessibility.isReduceMotionEnabled` before spring animations or shimmer effects
- Use `.glassEffect` on macOS 26+ / iOS 26+ with `.ultraThinMaterial` fallback for older versions
- Menu bar commands use `NotificationCenter` to communicate with `ContentView` — add new notifications in `SnapwellApp.swift`
- `NSWindow.allowsAutomaticWindowTabbing = false` — native tab bar is disabled; the app has its own Spaces tab bar
