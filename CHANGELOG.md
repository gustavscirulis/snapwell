# Changelog

User-visible changes are recorded as they are implemented. Release manifests under
`releases/` track submission and distribution separately for macOS and iOS.

## Unreleased

### macOS

- [fullscreen-metadata-reveal] Reveal fullscreen metadata in reading order once scrolling brings its title into view, with a readable stagger that plays once per session and respects Reduce Motion.

- [remote-analysis-sync] Pick up missing or newer analysis from iCloud and refresh search results.
- [search-before-analysis] Make existing content searchable while automatic analysis runs.
- [cancel-analysis-retry] Stop pending analysis retries when the task is cancelled.
- [accessible-media-actions] Open media and reach its actions more reliably with accessibility tools.

### iOS

- [lazy-thumbnails] Load thumbnails as grid cells appear instead of prefetching the whole library on refresh.
- [partial-share-recovery] Resume partial shared-media imports and wait for existing iCloud files to download before retrying.
- [share-import-recovery] Keep shared images and videos recoverable when saving or importing is interrupted.
- [safe-local-migration] Preserve local media when iCloud migration fails, and retain remote organization when merging newer analysis.

### Both

- [fullscreen-hero-motion] Open and close fullscreen media with a smooth eased transition, keeping the image and its crop synchronized on iOS.
- [library-shuffle] Shuffle media in All Media and Spaces from Settings, or turn shuffle off to return to newest first.
- [grid-columns] Adjust media-grid columns with a native slider in Settings: 1–4 on iPhone, 1–8 on iPad and 2–8 on Mac. Layouts adapt to available space.

## Releases

See the platform/version manifests under `releases/`. Earlier changes remain in Git
history; this ledger begins with the agent-workflow setup and does not claim past releases.
