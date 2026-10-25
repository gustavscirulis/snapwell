# Changelog

User-visible changes are recorded as they are implemented. Release manifests under
`releases/` track submission and distribution separately for macOS and iOS.

## Unreleased

### macOS

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

## Releases

See the platform/version manifests under `releases/`. Earlier changes remain in Git
history; this ledger begins with the agent-workflow setup and does not claim past releases.
