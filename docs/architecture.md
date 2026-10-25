# Architecture and platform conventions

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

Fullscreen metadata reveals once per detail session, only after scrolling down brings
40 pt of its title area into view. The trigger uses the scroll viewport and the metadata's
content position, including the image and panel padding; opening alone never consumes it.
The panel and title lead, followed by description/status,
patterns as one group, and file details at 80 ms intervals; absent groups add no delay.
Each beat uses a 220 ms ease-out opacity/4 pt offset reveal, completing within 460 ms.
Browsing to another item consumes the reveal and shows subsequent metadata immediately.
Reduce Motion uses one 150 ms fade without movement; enabling it mid-reveal completes the
remaining groups. Navigation, dismissal and disappearance cancel pending reveal work.

Bundle ID: `co.snapwell`.

## Architecture patterns

**iOS AppState**: UI state lives in `AppState` (`@Observable @MainActor`), not scattered `@State` on views. Match this pattern for new state.

**Analysis coordination**: AI analysis logic lives in `AnalysisCoordinator` (iOS) and `ImportService` (Mac), NOT in views.

**Sidecar writes**: ALL sidecar JSON mutations go through `SidecarWriteService` (iOS) or `MetadataSidecarService` (Mac). NEVER write sidecar JSON directly in views.

**Supported media types**: Use `SupportedMedia` enum (Mac) for file extensions and UTTypes. Don't define inline extension sets.

**SwiftData saves**: Use `modelContext.saveOrLog()` (not `try? modelContext.save()`). The `saveOrLog()` extension logs errors and asserts in DEBUG to prevent silent data loss.

**`isAnalyzing` is transient** — it's persisted on `MediaItem` but represents in-flight state. Both apps reset stuck flags on launch. Don't add more persisted transient flags; track ephemeral state on coordinators instead.

**One-time nudges (iOS)**: eligibility and "already seen" state live in `NudgeStore` (pure logic over `UserDefaults`, injectable for tests); `MainView.evaluateNudges()` runs after every `loadContent()` and presents at most one. Add new nudges as `Nudge` cases with a rule in `nextNudge`, ordered by priority — never stack two modals.

## Common gotchas

- Check `@Environment(\.accessibilityReduceMotion)` / `UIAccessibility.isReduceMotionEnabled` before spring animations or shimmer effects
- Use `.glassEffect` on macOS 26+ / iOS 26+ with `.ultraThinMaterial` fallback for older versions
- Menu bar commands use `NotificationCenter` to communicate with `ContentView` — add new notifications in `SnapwellApp.swift`
- `NSWindow.allowsAutomaticWindowTabbing = false` — native tab bar is disabled; the app has its own Spaces tab bar

## Import and recovery guarantees

`ShareStagingStore` publishes media before its sidecar; the extension reports save failures.
`ShareImportService` retains the staged pair until the destination sidecar commits, preserves
existing enriched sidecars and leaves conflicting media staged for recovery. Automation hosts
only import explicitly supplied temporary staging folders, never the real App Group.
Destination media is published through a temporary file before metadata is published atomically.
Retries can finish a media-only import without its staged media and wait for evicted destination
files to download before inspecting them. Staged metadata is removed last after publication.

Local-to-cloud migration keeps local sources and its completion flag unset after read/copy/merge
failures or remote placeholders. The app switches its active root only after migration succeeds.
Retries repair partial copies. Newer local analysis updates only
analysis fields, preserving remote memberships/source metadata. Cleanup removes copied item files
and merged spaces only; unrelated files, pending imports and trash remain local.

`AnalysisRecovery` clears stale persisted analysis flags at load while preserving IDs owned by
the iOS coordinator. Provider services accept isolated HTTP sessions and retry delays; production
uses the normal URL session/backoff, and task cancellation propagates on both platforms.

## Search and thumbnail loading

Mac initial, foreground and filesystem sync use the same existing-item reconciliation rules:
accept missing or newer remote analysis, preserve newer or equal local analysis, and notify
search when analysis changes. Keyword indexing and background embeddings start before automatic
analysis; incremental updates and deletions take precedence over an in-flight embedding snapshot.

iOS lazy grid cells request thumbnails as they appear. Content refresh does not prefetch the
whole library; thumbnail caching, downsampling and the decode concurrency limit remain in place.
