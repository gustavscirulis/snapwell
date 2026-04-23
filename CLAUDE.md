# Snapwell

AI-native media library for collecting, organizing, and analyzing images and videos. Two native apps share the same `~/Documents/Snapwell/` storage.

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

Syncs media and spaces via iCloud. Can run AI analysis and write results back to sidecars. Zero external dependencies.

**iCloud handling is critical** — files may exist as `.icloud` placeholders. All loading code must detect placeholders, trigger downloads with `startDownloadingUbiquitousItem()`, and wait for completion.

**Folder access** uses security-scoped URL bookmarks via `FileSystemManager`. User picks the Snapwell folder once on first launch.

**FullScreenImageOverlay gestures** use a mode-locking pattern (dismiss/scroll/swipe/zoom lock on first touch). Respect this when modifying gesture code.

Bundle ID: `co.snapwell.app`.

## Mac app

Uses XcodeGen — run `cd macos && xcodegen generate && scripts/post-xcodegen.sh` after adding/removing Swift files. The post-xcodegen script patches the `AppIcon.icon` file type in the generated `.pbxproj` (XcodeGen doesn't know the `folder.iconcomposer.icon` type).

Bundle ID: `co.snapwell.app`.

## Architecture patterns

**iOS AppState**: UI state lives in `AppState` (`@Observable @MainActor`), not scattered `@State` on views. Match this pattern for new state.

**Analysis coordination**: AI analysis logic lives in `AnalysisCoordinator` (iOS) and `ImportService` (Mac), NOT in views.

**Sidecar writes**: ALL sidecar JSON mutations go through `SidecarWriteService` (iOS) or `MetadataSidecarService` (Mac). NEVER write sidecar JSON directly in views.

**Supported media types**: Use `SupportedMedia` enum (Mac) for file extensions and UTTypes. Don't define inline extension sets.

**SwiftData saves**: Use `modelContext.saveOrLog()` (not `try? modelContext.save()`). The `saveOrLog()` extension logs errors and asserts in DEBUG to prevent silent data loss.

**`isAnalyzing` is transient** — it's persisted on `MediaItem` but represents in-flight state. Both apps reset stuck flags on launch. Don't add more persisted transient flags; track ephemeral state on coordinators instead.

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
