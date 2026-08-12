import Foundation
import SwiftData
import AppKit

/// Watches the metadata/ directory for JSON sidecars arriving via iCloud from other devices.
/// When new or updated sidecars are detected, imports them into SwiftData.
///
/// File I/O (JSON reads, file-existence checks, iCloud download triggers) runs on background
/// threads via `Task.detached`. SwiftData mutations stay on `@MainActor`.
@MainActor
final class SyncWatcher {
    private var metadataSource: DispatchSourceFileSystemObject?
    private var mediaSource: DispatchSourceFileSystemObject?
    private var spacesSource: DispatchSourceFileSystemObject?
    private var metadataFD: Int32 = -1
    private var mediaFD: Int32 = -1
    private var spacesFD: Int32 = -1
    private var debounceTask: Task<Void, Never>?
    private var spacesDebounceTask: Task<Void, Never>?
    private var pendingRetryTask: Task<Void, Never>?
    private var pendingRetryAttempt = 0
    private var knownSidecarIds: [String: Date] = [:]
    private var pendingSidecarIds = Set<String>()
    private var context: ModelContext?
    /// When true, ignore file-system events (we caused them ourselves).
    private var suppressingLocalChanges = false

    let storage: MediaStorageService
    let sidecarService: MetadataSidecarService
    let downloadRequester: any DownloadRequesting

    init(
        storage: MediaStorageService = .shared,
        sidecarService: MetadataSidecarService = .shared,
        downloadRequester: any DownloadRequesting = DownloadRequester.shared
    ) {
        self.storage = storage
        self.sidecarService = sidecarService
        self.downloadRequester = downloadRequester
    }

    /// Called when new items without analysis are imported via sync.
    var onNewUnanalyzedItems: (([String]) -> Void)?

    // MARK: - Background I/O Types

    /// Sendable bridge carrying file-derived data from background thread to main actor.
    private struct SidecarImportData: Sendable {
        let id: String
        let sidecar: SidecarMetadata
        let mediaType: MediaType
        let filename: String
        let mediaState: DownloadState
        let needsThumbnail: Bool
    }

    /// Update for existing items whose sidecar changed (e.g. space assignment, analysis, source URL).
    private struct SidecarUpdateData: Sendable {
        let id: String
        let spaceIds: [String]
        let sourceURL: String?
        let imageContext: String?
        let imageSummary: String?
        let patterns: [SidecarPattern]?
        let analyzedAt: Date?
    }

    // MARK: - Public API

    /// Call BEFORE local mutations that write sidecar/spaces files.
    func beginLocalChange() {
        suppressingLocalChanges = true
    }

    /// Call AFTER local mutations complete. Updates known state so the watcher
    /// won't react to our own file changes when suppression ends.
    func endLocalChange() {
        updateKnownSidecars(Self.currentSidecarIdsWithDatesFromDisk(storage: storage))
        // Keep suppressed briefly to outlast any DispatchSource events
        // that are already queued from our write.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.suppressingLocalChanges = false
        }
    }

    func startWatching(context: ModelContext) {
        stopWatching()
        self.context = context

        updateKnownSidecars(Self.currentSidecarIdsWithDatesFromDisk(storage: storage))

        // Watch metadata/ directory — use main queue so event handler is
        // already on the main thread, avoiding cross-isolation captures.
        metadataFD = open(storage.metadataDir.path, O_EVTONLY)
        if metadataFD >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: metadataFD,
                eventMask: .write,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.scheduleSync()
                }
            }
            let fd = metadataFD
            source.setCancelHandler { close(fd) }
            source.resume()
            metadataSource = source
        }

        // Media materialization does not touch the sidecar, so it needs its own
        // watcher to re-evaluate pending imports immediately.
        mediaFD = open(storage.mediaDir.path, O_EVTONLY)
        if mediaFD >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: mediaFD,
                eventMask: .write,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.scheduleSync()
                }
            }
            let fd = mediaFD
            source.setCancelHandler { close(fd) }
            source.resume()
            mediaSource = source
        }

        // Watch base directory for spaces.json changes
        spacesFD = open(storage.baseURL.path, O_EVTONLY)
        if spacesFD >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: spacesFD,
                eventMask: .write,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.scheduleSyncSpaces()
                }
            }
            let fd = spacesFD
            source.setCancelHandler { close(fd) }
            source.resume()
            spacesSource = source
        }

        schedulePendingRetryIfNeeded()
    }

    func stopWatching() {
        metadataSource?.cancel()
        metadataSource = nil
        metadataFD = -1
        mediaSource?.cancel()
        mediaSource = nil
        mediaFD = -1
        spacesSource?.cancel()
        spacesSource = nil
        spacesFD = -1
        debounceTask?.cancel()
        spacesDebounceTask?.cancel()
        pendingRetryTask?.cancel()
        pendingRetryTask = nil
        context = nil
    }

    /// Perform an initial sync on launch — picks up items that arrived via iCloud while the app was closed.
    func initialSync(context: ModelContext) async {
        self.context = context
        iCloudDownloadManager.shared.ensureIndexDownloaded(
            storage: storage,
            downloadRequester: downloadRequester
        )
        await syncSpaces()          // Spaces FIRST so items can resolve space IDs
        await syncMetadataAsync()
    }

    /// Force a full re-sync by clearing cached state so every file on disk is re-evaluated.
    /// Handles additions, modifications, and deletions. Use on app focus to catch iCloud changes
    /// that DispatchSource may have missed.
    func resyncFromDisk() async {
        knownSidecarIds = [:]
        iCloudDownloadManager.shared.ensureIndexDownloaded(
            storage: storage,
            downloadRequester: downloadRequester
        )
        await syncSpaces()
        await syncMetadata()
    }

    // MARK: - Debouncing

    private func scheduleSync() {
        guard !suppressingLocalChanges else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, !self.suppressingLocalChanges else { return }
            await self.syncMetadata()
        }
    }

    private func scheduleSyncSpaces() {
        guard !suppressingLocalChanges else { return }
        spacesDebounceTask?.cancel()
        spacesDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, !self.suppressingLocalChanges else { return }
            await self.syncSpaces()
        }
    }

    private func requestDownloads(_ urls: [URL]) {
        for url in Set(urls) {
            downloadRequester.requestDownload(for: url)
        }
    }

    private func updateKnownSidecars(_ currentDates: [String: Date]) {
        knownSidecarIds = currentDates.filter { !pendingSidecarIds.contains($0.key) }
    }

    private func finishSync(currentDates: [String: Date], pendingIds: Set<String>) {
        pendingSidecarIds = pendingIds
        updateKnownSidecars(currentDates)

        if pendingIds.isEmpty {
            pendingRetryTask?.cancel()
            pendingRetryTask = nil
            pendingRetryAttempt = 0
        } else {
            schedulePendingRetryIfNeeded()
        }
    }

    private func schedulePendingRetryIfNeeded() {
        guard !pendingSidecarIds.isEmpty, pendingRetryTask == nil, context != nil else { return }
        let delays: [Duration] = [.seconds(5), .seconds(10), .seconds(20), .seconds(30)]
        let delay = delays[min(pendingRetryAttempt, delays.count - 1)]
        pendingRetryAttempt += 1

        pendingRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pendingRetryTask = nil
            guard !self.suppressingLocalChanges else {
                self.schedulePendingRetryIfNeeded()
                return
            }
            await self.syncMetadata()
        }
    }

    // MARK: - Metadata Sync

    /// Result of gathering file changes on a background thread.
    private struct GatheredChanges: Sendable {
        let newItems: [SidecarImportData]
        let updates: [SidecarUpdateData]
        let deletedIds: Set<String>
        let currentDates: [String: Date]
        let pendingIds: Set<String>
        let downloadURLs: [URL]
    }

    /// Shared Phase 1: Gather all file-derived changes on a background thread.
    ///
    /// Deletions are detected by diffing the persisted SwiftData records against disk rather
    /// than against `knownSidecarIds`, which is in-memory only and therefore empty on launch
    /// and after `resyncFromDisk()`. Diffing the store is what lets a deletion made on another
    /// device while this app was closed be noticed at all. Mirrors `SyncService.sync` on iOS.
    private func gatherChangesFromDisk() async -> GatheredChanges {
        let knownDates = knownSidecarIds
        let storage = self.storage
        let sidecarService = self.sidecarService
        let persistedIds = persistedItemIds()

        return await Task.detached(priority: .userInitiated) {
            let scannedMetadata = ContainerScanner.scanMetadata(
                storage.metadataDir,
                isUsingiCloud: storage.isUsingiCloud
            )
            let metadataFiles = scannedMetadata ?? [:]
            let mediaFiles = ContainerScanner.scanMedia(
                storage.mediaDir,
                isUsingiCloud: storage.isUsingiCloud
            ) ?? [:]
            let currentDates = metadataFiles.mapValues(\.modDate)
            let currentIds = Set(currentDates.keys)
            let knownIds = Set(knownDates.keys)
            let newIds = currentIds.subtracting(knownIds)
            var pendingIds = Set<String>()
            var downloadURLs: [URL] = []

            // Detect modified sidecars (existing IDs whose mod date changed)
            var modifiedIds: Set<String> = []
            for id in currentIds.intersection(knownIds) {
                if let currentDate = currentDates[id],
                   let knownDate = knownDates[id],
                   currentDate > knownDate {
                    modifiedIds.insert(id)
                }
            }

            var newItems: [SidecarImportData] = []
            newItems.reserveCapacity(newIds.count)
            for id in newIds {
                guard let metadataFile = metadataFiles[id] else { continue }
                guard metadataFile.state == .downloaded else {
                    pendingIds.insert(id)
                    downloadURLs.append(metadataFile.url)
                    continue
                }
                guard let mediaFile = mediaFiles[id] else {
                    pendingIds.insert(id)
                    continue
                }
                if mediaFile.state == .downloading {
                    downloadURLs.append(mediaFile.url)
                }
                guard let data = Self.gatherSidecarData(
                    id: id,
                    mediaFile: mediaFile,
                    storage: storage,
                    sidecarService: sidecarService
                ) else {
                    if storage.isUsingiCloud {
                        pendingIds.insert(id)
                        downloadURLs.append(metadataFile.url)
                    }
                    continue
                }
                newItems.append(data)
            }

            var updates: [SidecarUpdateData] = []
            for id in modifiedIds {
                guard metadataFiles[id]?.state == .downloaded else {
                    pendingIds.insert(id)
                    if let url = metadataFiles[id]?.url { downloadURLs.append(url) }
                    continue
                }
                if let sidecar = sidecarService.readSidecar(id: id) {
                    updates.append(SidecarUpdateData(
                        id: id,
                        spaceIds: sidecar.normalizedSpaceIDs,
                        sourceURL: sidecar.sourceURL,
                        imageContext: sidecar.imageContext,
                        imageSummary: sidecar.imageSummary,
                        patterns: sidecar.patterns,
                        analyzedAt: sidecar.analyzedAt
                    ))
                }
            }

            // Any persisted item whose sidecar is gone from disk was deleted elsewhere. A
            // present-but-still-downloading placeholder is in `currentIds`, so it protects its
            // own record. `.trash/` counts as gone: it lives inside the shared container, so a
            // sidecar sitting there was trashed by *some* device — a local delete already
            // removed its own record under change suppression, and undo restores the sidecar
            // to `metadata/` before re-inserting. A nil scan means the directory was unreadable
            // rather than emptied; acting on that would wipe the whole library.
            var deletedIds: Set<String> = []
            if scannedMetadata != nil {
                deletedIds = persistedIds.subtracting(currentIds)
            } else if !persistedIds.isEmpty {
                print("[SyncWatcher] metadata/ unreadable — skipping deletion pass for \(persistedIds.count) records")
            }

            return GatheredChanges(
                newItems: newItems, updates: updates,
                deletedIds: deletedIds, currentDates: currentDates,
                pendingIds: pendingIds, downloadURLs: downloadURLs
            )
        }.value
    }

    /// Initial sync on launch — gathers then applies in batches with yielding.
    private func syncMetadataAsync() async {
        guard context != nil else { return }

        let changes = await gatherChangesFromDisk()
        requestDownloads(changes.downloadURLs)
        var pendingIds = changes.pendingIds

        // Apply to SwiftData on main actor, in batches
        if !changes.newItems.isEmpty {
            print("[SyncWatcher] Initial sync: importing \(changes.newItems.count) items...")
            var count = 0
            for data in changes.newItems {
                let result = applyImport(data)
                if !result.fullyApplied { pendingIds.insert(data.id) }
                if result.inserted { count += 1 }
                if count % 20 == 0 {
                    context?.saveOrLog()
                    await Task.yield()
                }
            }
            print("[SyncWatcher] Initial sync complete: imported \(count) items")
        }

        for update in changes.updates {
            applySpaceUpdate(update)
        }

        for id in changes.deletedIds {
            removeItemFromContext(id: id)
        }

        context?.saveOrLog()
        finishSync(currentDates: changes.currentDates, pendingIds: pendingIds)
    }

    /// Ongoing sync — triggered by DispatchSource after debounce.
    private func syncMetadata() async {
        guard context != nil else { return }

        let changes = await gatherChangesFromDisk()
        requestDownloads(changes.downloadURLs)
        var pendingIds = changes.pendingIds

        var unanalyzedIds: [String] = []
        for data in changes.newItems {
            let result = applyImport(data)
            if !result.fullyApplied { pendingIds.insert(data.id) }
            if result.inserted,
               data.sidecar.imageContext == nil || (data.sidecar.imageContext?.isEmpty ?? true) {
                unanalyzedIds.append(data.id)
            }
        }

        for update in changes.updates {
            applySpaceUpdate(update)
        }

        for id in changes.deletedIds {
            removeItemFromContext(id: id)
        }

        if !changes.newItems.isEmpty || !changes.updates.isEmpty || !changes.deletedIds.isEmpty {
            context?.saveOrLog()
        }

        if !unanalyzedIds.isEmpty {
            onNewUnanalyzedItems?(unanalyzedIds)
        }

        finishSync(currentDates: changes.currentDates, pendingIds: pendingIds)
    }

    /// Apply pre-gathered sidecar data to SwiftData. No file I/O — only model operations.
    private struct ImportResult {
        let fullyApplied: Bool
        let inserted: Bool
    }

    private func applyImport(_ data: SidecarImportData) -> ImportResult {
        guard let context else { return ImportResult(fullyApplied: false, inserted: false) }

        let dataId = data.id
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == dataId })
        if let existing = try? context.fetch(descriptor), let existingItem = existing.first {
            // Item already imported — still reconcile space assignment and sourceURL
            let resolvedSpaces = spaces(for: data.sidecar.normalizedSpaceIDs)
            if existingItem.orderedSpaceIDs != resolvedSpaces.map(\.id) {
                existingItem.setMembership(resolvedSpaces)
            }
            if existingItem.sourceURL == nil, let sourceURL = data.sidecar.sourceURL {
                existingItem.sourceURL = sourceURL
            }
            if data.mediaState == .downloaded, data.needsThumbnail {
                generateThumbnail(for: data)
            }
            return ImportResult(fullyApplied: data.mediaState == .downloaded, inserted: false)
        }

        guard data.mediaState != .notPresent else {
            print("[SyncWatcher] Media file not found for \(data.id), skipping")
            return ImportResult(fullyApplied: false, inserted: false)
        }

        let item = MediaItem(
            id: data.id,
            mediaType: data.mediaType,
            filename: data.filename,
            width: data.sidecar.width,
            height: data.sidecar.height,
            createdAt: data.sidecar.createdAt,
            duration: data.sidecar.duration
        )

        item.sourceURL = data.sidecar.sourceURL

        item.setMembership(spaces(for: data.sidecar.normalizedSpaceIDs))

        if let imageContext = data.sidecar.imageContext, !imageContext.isEmpty {
            let patterns = (data.sidecar.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
            item.analysisResult = AnalysisResult(
                imageContext: imageContext,
                imageSummary: data.sidecar.imageSummary ?? "",
                patterns: patterns,
                analyzedAt: data.sidecar.analyzedAt ?? .now,
                provider: "synced",
                model: "icloud-sync"
            )
        }

        context.insert(item)

        if data.mediaState == .downloaded, data.needsThumbnail {
            generateThumbnail(for: data)
        }

        print("[SyncWatcher] Imported \(data.id) from iCloud")
        return ImportResult(fullyApplied: data.mediaState == .downloaded, inserted: true)
    }

    private func generateThumbnail(for data: SidecarImportData) {
        let filename = data.filename
        let mediaType = data.mediaType
        let id = data.id
        Task.detached { [storage] in
            if mediaType == .video {
                if let posterFrame = try? await VideoFrameExtractor.extractPosterFrame(from: storage.mediaURL(filename: filename)) {
                    _ = try? ThumbnailService.generateThumbnail(from: posterFrame, id: id, storage: storage)
                }
            } else {
                _ = try? await ThumbnailService.generateThumbnail(
                    from: storage.mediaURL(filename: filename),
                    id: id,
                    storage: storage
                )
            }
        }
    }

    /// IDs of every persisted item, used as the durable "last seen" set for deletion detection.
    private func persistedItemIds() -> Set<String> {
        guard let context,
              let items = try? context.fetch(FetchDescriptor<MediaItem>()) else { return [] }
        return Set(items.map(\.id))
    }

    /// Remove a SwiftData item by ID. No file I/O.
    private func removeItemFromContext(id: String) {
        guard let context else { return }
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = (try? context.fetch(descriptor))?.first else { return }
        context.delete(item)
        print("[SyncWatcher] Removed \(id) (sidecar deleted on other device)")
    }

    /// Update space assignment, analysis, and source URL on an existing item. No file I/O.
    private func applySpaceUpdate(_ update: SidecarUpdateData) {
        guard let context else { return }

        let updateId = update.id
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == updateId })
        guard let item = (try? context.fetch(descriptor))?.first else { return }

        let resolvedSpaces = spaces(for: update.spaceIds)
        if item.orderedSpaceIDs != resolvedSpaces.map(\.id) {
            item.setMembership(resolvedSpaces)
            print("[SyncWatcher] Updated spaces for \(update.id) -> \(resolvedSpaces.map(\.id))")
        }

        if item.sourceURL == nil, let sourceURL = update.sourceURL {
            item.sourceURL = sourceURL
            print("[SyncWatcher] Updated sourceURL for \(update.id)")
        }

        // Sync analysis results if the remote sidecar has newer or missing-locally analysis
        if let imageContext = update.imageContext, !imageContext.isEmpty {
            let shouldSync: Bool
            if item.analysisResult == nil {
                shouldSync = true
            } else if let remoteDate = update.analyzedAt,
                      let localDate = item.analysisResult?.analyzedAt,
                      remoteDate > localDate {
                shouldSync = true
            } else {
                shouldSync = false
            }

            if shouldSync {
                let patterns = (update.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
                item.analysisResult = AnalysisResult(
                    imageContext: imageContext,
                    imageSummary: update.imageSummary ?? "",
                    patterns: patterns,
                    analyzedAt: update.analyzedAt ?? .now,
                    provider: "synced",
                    model: "icloud-sync"
                )
                print("[SyncWatcher] Synced analysis result for \(update.id)")
            }
        }
    }

    private func spaces(for ids: [String]) -> [Space] {
        guard let context, !ids.isEmpty else { return [] }
        let availableSpaces = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        let idSet = Set(ids)
        return availableSpaces
            .filter { idSet.contains($0.id) }
            .membershipSorted()
    }

    // MARK: - Spaces Sync

    /// Read spaces.json on background thread, apply to SwiftData on main actor.
    private func syncSpaces() async {
        guard let context else { return }

        let spacesURL = storage.baseURL.appendingPathComponent("spaces.json")
        switch ICloudFile.downloadState(of: spacesURL, isUsingiCloud: storage.isUsingiCloud) {
        case .downloading:
            downloadRequester.requestDownload(for: spacesURL)
            return
        case .notPresent where storage.isUsingiCloud:
            // A temporarily incomplete iCloud directory listing must not be
            // interpreted as an authoritative empty spaces index.
            return
        case .downloaded, .notPresent:
            break
        }

        // Phase 1: Read JSON on background thread (use wrapper format for all-space guidance)
        let sidecarService = self.sidecarService
        let spacesFile = await Task.detached {
            sidecarService.readSpacesFile()
        }.value

        let sidecarSpaces = spacesFile.spaces

        // Phase 2: Sync all-space guidance to UserDefaults
        if let allGuidance = spacesFile.allSpaceGuidance {
            UserDefaults.standard.set(allGuidance, forKey: "allSpacePrompt")
        }
        UserDefaults.standard.set(spacesFile.useAllSpaceGuidance, forKey: "useAllSpacePrompt")

        // Phase 3: Apply spaces to SwiftData on main actor
        let descriptor = FetchDescriptor<Space>()
        let existingSpaces = (try? context.fetch(descriptor)) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: existingSpaces.map { ($0.id, $0) })
        let sidecarById = Dictionary(uniqueKeysWithValues: sidecarSpaces.map { ($0.id, $0) })

        for sidecar in sidecarSpaces {
            if existingById[sidecar.id] == nil {
                let space = Space(
                    id: sidecar.id,
                    name: sidecar.name,
                    order: sidecar.order,
                    createdAt: sidecar.createdAt
                )
                space.customPrompt = sidecar.customPrompt
                space.useCustomPrompt = sidecar.useCustomPrompt
                space.hideFromAllMedia = sidecar.hideFromAllMedia
                context.insert(space)
            }
        }

        for space in existingSpaces {
            if let sidecar = sidecarById[space.id] {
                if space.name != sidecar.name { space.name = sidecar.name }
                if space.order != sidecar.order { space.order = sidecar.order }
                if space.customPrompt != sidecar.customPrompt { space.customPrompt = sidecar.customPrompt }
                if space.useCustomPrompt != sidecar.useCustomPrompt { space.useCustomPrompt = sidecar.useCustomPrompt }
                if space.hideFromAllMedia != sidecar.hideFromAllMedia { space.hideFromAllMedia = sidecar.hideFromAllMedia }
            } else {
                // Space was deleted on the other device
                context.delete(space)
                print("[SyncWatcher] Removed space \(space.name) (deleted on other device)")
            }
        }

        context.saveOrLog()
    }

    // MARK: - Background File I/O Helpers (nonisolated)

    /// Gather all file-derived data for a single sidecar on a background thread.
    /// Reads JSON, checks media file existence, triggers iCloud downloads. No SwiftData access.
    private nonisolated static func gatherSidecarData(
        id: String,
        mediaFile: ScannedFile,
        storage: MediaStorageService,
        sidecarService: MetadataSidecarService
    ) -> SidecarImportData? {
        guard let sidecar = sidecarService.readSidecar(id: id) else { return nil }

        let mediaType: MediaType = sidecar.type == "video" ? .video : .image
        let filename = mediaFile.url.lastPathComponent

        let needsThumbnail = !storage.thumbnailExists(id: id)

        return SidecarImportData(
            id: id,
            sidecar: sidecar,
            mediaType: mediaType,
            filename: filename,
            mediaState: mediaFile.state,
            needsThumbnail: needsThumbnail
        )
    }

    /// List sidecar IDs with their modification dates from disk. Safe to call from any thread.
    private nonisolated static func currentSidecarIdsWithDatesFromDisk(storage: MediaStorageService = .shared) -> [String: Date] {
        (ContainerScanner.scanMetadata(
            storage.metadataDir,
            isUsingiCloud: storage.isUsingiCloud
        ) ?? [:]).mapValues(\.modDate)
    }
}
