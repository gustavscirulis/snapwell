import AVFoundation
import SwiftData
import UIKit

struct AnalysisAlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// A small, deterministic queue that coalesces duplicate work while preserving arrival order.
/// A request for the active ID becomes one follow-up entry, updated to the latest value if the
/// same ID is requested repeatedly.
struct AnalysisWorkQueue<Value> {
    struct Entry {
        let id: String
        let value: Value
    }

    private var pending: [Entry] = []
    private var pendingIDs: Set<String> = []
    private(set) var activeID: String?

    var isEmpty: Bool { pending.isEmpty && activeID == nil }

    var ownedIDs: Set<String> {
        var ids = pendingIDs
        if let activeID { ids.insert(activeID) }
        return ids
    }

    /// Returns true only when the ID became newly owned by the queue.
    @discardableResult
    mutating func enqueue(id: String, value: Value) -> Bool {
        let entry = Entry(id: id, value: value)

        if activeID == id {
            if let index = pending.firstIndex(where: { $0.id == id }) {
                pending[index] = entry
            } else {
                pending.append(entry)
                pendingIDs.insert(id)
            }
            return false
        }

        if pendingIDs.contains(id) {
            if let index = pending.firstIndex(where: { $0.id == id }) {
                pending[index] = entry
            }
            return false
        }

        pending.append(entry)
        pendingIDs.insert(id)
        return true
    }

    mutating func next() -> Entry? {
        guard activeID == nil, !pending.isEmpty else { return nil }
        let entry = pending.removeFirst()
        pendingIDs.remove(entry.id)
        activeID = entry.id
        return entry
    }

    /// Finishes the active entry. When allowed, a coalesced follow-up is appended once.
    /// Returns true when the active ID remains owned by that follow-up.
    @discardableResult
    mutating func finishActive(enqueueRerun: Bool) -> Bool {
        let finishedID = activeID
        activeID = nil

        guard let finishedID else { return false }
        guard enqueueRerun else {
            pending.removeAll { $0.id == finishedID }
            pendingIDs.remove(finishedID)
            return false
        }
        return pendingIDs.contains(finishedID)
    }

    /// Removes pending and follow-up work, leaving the active entry for finishActive().
    mutating func removeAllPending() -> [Entry] {
        let removed = pending
        pending.removeAll()
        pendingIDs.removeAll()
        return removed
    }
}

/// Coordinates AI analysis of media items, extracting this logic from MainView.
@Observable
@MainActor
final class AnalysisCoordinator {
    typealias AnalysisRunner = @MainActor (
        MediaItem, URL, AIProvider, String, String, String?, String?
    ) async throws -> AnalysisResult
    typealias MediaAvailabilityChecker = @MainActor (URL, MediaType) async throws -> Void

    private struct AnalysisConfiguration {
        let rootURL: URL
        let provider: AIProvider
        let apiKey: String
        let storedModel: String
        let usesRecommendedModel: Bool
    }

    private struct AnalysisJob {
        let item: MediaItem
        let configuration: AnalysisConfiguration
    }

    enum MediaPreparationError: Error {
        case unavailable(MediaType)
        case unreadable(MediaType)
    }

    private var analysisTask: Task<Void, Never>?
    private var workQueue = AnalysisWorkQueue<AnalysisJob>()
    private let analysisRunner: AnalysisRunner?
    private let mediaAvailabilityChecker: MediaAvailabilityChecker?

    var analysisAlert: AnalysisAlertState?

    // Dependencies — set once via configure(), used by all analysis methods.
    private var keySyncService: KeySyncService?
    private var fileSystem: FileSystemManager?
    private var modelContext: ModelContext?
    private var searchService: SearchIndexService?

    init(
        analysisRunner: AnalysisRunner? = nil,
        mediaAvailabilityChecker: MediaAvailabilityChecker? = nil
    ) {
        self.analysisRunner = analysisRunner
        self.mediaAvailabilityChecker = mediaAvailabilityChecker
    }

    /// Store dependencies so they don't need to be passed on every call.
    func configure(
        keySyncService: KeySyncService,
        fileSystem: FileSystemManager,
        modelContext: ModelContext,
        searchService: SearchIndexService
    ) {
        self.keySyncService = keySyncService
        self.fileSystem = fileSystem
        self.modelContext = modelContext
        self.searchService = searchService
    }

    /// Whether a persisted isAnalyzing flag belongs to live coordinator work.
    func ownsAnalysis(for itemID: String) -> Bool {
        workQueue.ownedIDs.contains(itemID)
    }

    /// Analyze specific items. New work is coalesced into the existing serial queue instead of
    /// cancelling an in-flight provider request.
    func analyzeItems(_ items: [MediaItem], allItems _: [MediaItem]) {
        guard let configuration = currentConfiguration() else { return }
        guard let modelContext else { return }
        guard !items.isEmpty else {
            print("[Analysis] No items to analyze")
            return
        }

        analysisAlert = nil
        var newlyScheduled = 0
        for item in items {
            let job = AnalysisJob(item: item, configuration: configuration)
            if workQueue.enqueue(id: item.id, value: job) {
                newlyScheduled += 1
            }
            item.isAnalyzing = true
            item.analysisError = nil
        }
        modelContext.saveOrLog()

        print("[Analysis] Queued \(items.count) item(s), \(newlyScheduled) newly scheduled")
        startWorkerIfNeeded()
    }

    /// Find and analyze all unanalyzed items.
    func analyzeUnanalyzed(allItems: [MediaItem]) {
        guard let modelContext else {
            print("[Analysis] Skipped — coordinator not configured")
            return
        }
        let descriptor = FetchDescriptor<MediaItem>()
        let allCurrentItems = (try? modelContext.fetch(descriptor)) ?? []
        let unanalyzed = allCurrentItems.filter {
            $0.analysisResult == nil && !$0.isAnalyzing && $0.analysisError == nil
        }

        analyzeItems(unanalyzed, allItems: allItems)
    }

    // MARK: - Queue Processing

    private func currentConfiguration() -> AnalysisConfiguration? {
        guard let keySyncService, let fileSystem, modelContext != nil, searchService != nil else {
            print("[Analysis] Skipped — coordinator not configured")
            return nil
        }
        guard let providerString = keySyncService.activeProvider,
              let provider = AIProvider(rawValue: providerString) else {
            print("[Analysis] Skipped — no active provider")
            return nil
        }
        guard provider.canAnalyzeOnCurrentPlatform else {
            print("[Analysis] Skipped — \(provider.displayName) analysis runs on Mac")
            return nil
        }
        guard keySyncService.isUnlocked else {
            print("[Analysis] Skipped — keySyncService not unlocked")
            return nil
        }
        guard let apiKey = keySyncService.activeAPIKey() else {
            print("[Analysis] Skipped — no API key for provider \(providerString)")
            return nil
        }
        guard let rootURL = fileSystem.rootURL else {
            print("[Analysis] Skipped — no rootURL")
            return nil
        }

        let storedModel = keySyncService.activeModel ?? ModelDiscoveryService.autoModelValue
        return AnalysisConfiguration(
            rootURL: rootURL,
            provider: provider,
            apiKey: apiKey,
            storedModel: storedModel,
            usesRecommendedModel: storedModel == ModelDiscoveryService.autoModelValue
        )
    }

    private func startWorkerIfNeeded() {
        guard analysisTask == nil else { return }
        analysisTask = Task { [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        guard let modelContext, let searchService else {
            releasePendingWork()
            analysisTask = nil
            return
        }

        while let entry = workQueue.next() {
            let job = entry.value
            let item = job.item
            let configuration = job.configuration

            do {
                try Task.checkCancellation()
                let result = try await performAnalysis(job)

                item.analysisResult = result
                item.analysisError = nil
                let hasRerun = workQueue.finishActive(enqueueRerun: true)
                item.isAnalyzing = hasRerun

                SidecarWriteService.writeAnalysis(for: item, rootURL: configuration.rootURL)
                searchService.addToIndex(item: item)
                modelContext.saveOrLog()
                print("[Analysis] Completed: \(item.id)")
            } catch {
                if Task.isCancelled {
                    workQueue.finishActive(enqueueRerun: false)
                    item.isAnalyzing = false
                    item.analysisError = nil
                    releasePendingWork()
                    modelContext.saveOrLog()
                    print("[Analysis] Cancelled coordinator work without recording a failure")
                    analysisTask = nil
                    return
                }

                let alert = Self.alertState(
                    for: error,
                    mediaType: item.mediaType,
                    provider: configuration.provider
                )
                workQueue.finishActive(enqueueRerun: false)
                item.isAnalyzing = false
                item.analysisError = alert.message
                analysisAlert = alert
                modelContext.saveOrLog()
                print("[Analysis] Failed for \(item.id): \(alert.message)")

                if Self.isProviderWideFailure(error) {
                    releasePendingWork()
                    modelContext.saveOrLog()
                    break
                }
            }
        }

        analysisTask = nil
    }

    private func releasePendingWork() {
        for entry in workQueue.removeAllPending() {
            entry.value.item.isAnalyzing = false
        }
    }

    private func performAnalysis(_ job: AnalysisJob) async throws -> AnalysisResult {
        let item = job.item
        let configuration = job.configuration
        let (guidance, spaceContext) = SpaceGuidanceResolver.resolve(for: item)
        var rejectedRecommendedModels: Set<String> = []
        var resolvedModel = configuration.usesRecommendedModel
            ? await ModelDiscoveryService.shared.resolveAutoModel(for: configuration.provider)
            : configuration.storedModel

        do {
            return try await runAnalysis(
                item,
                rootURL: configuration.rootURL,
                provider: configuration.provider,
                model: resolvedModel,
                apiKey: configuration.apiKey,
                guidance: guidance,
                spaceContext: spaceContext
            )
        } catch let error as AIAnalysisService.AnalysisError
            where configuration.usesRecommendedModel && Self.indicatesUnusableModel(error) {
            rejectedRecommendedModels.insert(resolvedModel)
            ModelDiscoveryService.shared.clearCache(for: configuration.provider)
            let fallback = await ModelDiscoveryService.shared.resolveAutoModel(
                for: configuration.provider,
                excluding: rejectedRecommendedModels
            )
            guard fallback != resolvedModel else { throw error }
            resolvedModel = fallback
            return try await runAnalysis(
                item,
                rootURL: configuration.rootURL,
                provider: configuration.provider,
                model: resolvedModel,
                apiKey: configuration.apiKey,
                guidance: guidance,
                spaceContext: spaceContext
            )
        }
    }

    // MARK: - Error Presentation

    nonisolated static func indicatesUnusableModel(_ error: AIAnalysisService.AnalysisError) -> Bool {
        guard case .apiError(let code, _, _) = error else { return false }
        return code == 400 || code == 404
    }

    nonisolated static func alertState(
        for error: Error,
        mediaType: MediaType,
        provider: AIProvider
    ) -> AnalysisAlertState {
        let mediaName = mediaType == .video ? "video" : "image"
        let title = "Couldn’t analyze \(mediaName)"

        if let preparationError = error as? MediaPreparationError {
            switch preparationError {
            case .unavailable:
                return AnalysisAlertState(
                    title: title,
                    message: "This \(mediaName) isn’t available on this device yet. Wait for iCloud to finish downloading it, then try again."
                )
            case .unreadable:
                return AnalysisAlertState(
                    title: title,
                    message: "Snapwell couldn’t read this \(mediaName). Try downloading it again or choose another file."
                )
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let message: String
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                message = "You appear to be offline. Reconnect, then try again."
            case NSURLErrorTimedOut:
                message = "\(provider.displayName) took too long to respond. Try again."
            case NSURLErrorCancelled, NSURLErrorNetworkConnectionLost:
                message = "The connection to \(provider.displayName) was interrupted. Try again."
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                message = "Snapwell couldn’t connect to \(provider.displayName). Check your connection and try again."
            default:
                message = "\(provider.displayName) couldn’t complete the analysis. Check your connection and try again."
            }
            return AnalysisAlertState(title: title, message: message)
        }

        if let analysisError = error as? AIAnalysisService.AnalysisError {
            let message: String
            switch analysisError {
            case .imageConversionFailed:
                message = "Snapwell couldn’t read this \(mediaName). Try downloading it again or choose another file."
            default:
                message = analysisError.localizedDescription
            }
            return AnalysisAlertState(title: title, message: message)
        }

        return AnalysisAlertState(
            title: title,
            message: "Snapwell couldn’t complete the analysis. Try again. If this keeps happening, check your \(provider.displayName) settings."
        )
    }

    nonisolated static func isProviderWideFailure(_ error: Error) -> Bool {
        if error is MediaPreparationError { return false }
        if (error as NSError).domain == NSURLErrorDomain { return true }
        if let analysisError = error as? AIAnalysisService.AnalysisError {
            if case .imageConversionFailed = analysisError { return false }
            return true
        }
        return false
    }

    // MARK: - Media Loading

    private func runAnalysis(
        _ item: MediaItem,
        rootURL: URL,
        provider: AIProvider,
        model: String,
        apiKey: String,
        guidance: String?,
        spaceContext: String?
    ) async throws -> AnalysisResult {
        if let analysisRunner {
            return try await analysisRunner(
                item, rootURL, provider, model, apiKey, guidance, spaceContext
            )
        }

        let fileURL = rootURL.appendingPathComponent("images/\(item.filename)")
        try await ensureMediaAvailable(at: fileURL, mediaType: item.mediaType)

        if item.isVideo {
            let frames = try await extractVideoFrames(from: fileURL)
            return try await AIAnalysisService.shared.analyzeVideo(
                frames: frames,
                provider: provider,
                model: model,
                apiKey: apiKey,
                guidance: guidance,
                spaceContext: spaceContext
            )
        }

        let image = try loadImage(from: fileURL)
        return try await AIAnalysisService.shared.analyze(
            image: image,
            provider: provider,
            model: model,
            apiKey: apiKey,
            guidance: guidance,
            spaceContext: spaceContext
        )
    }

    private func ensureMediaAvailable(at url: URL, mediaType: MediaType) async throws {
        if let mediaAvailabilityChecker {
            try await mediaAvailabilityChecker(url, mediaType)
            return
        }

        let monitor = iCloudDownloadMonitor.shared
        if !monitor.isDownloaded(url) {
            await monitor.waitForDownload(of: url, timeout: 180)
        }
        try Task.checkCancellation()

        guard monitor.isDownloaded(url),
              FileManager.default.fileExists(atPath: url.path) else {
            throw MediaPreparationError.unavailable(mediaType)
        }
    }

    private func loadImage(from fileURL: URL) throws -> UIImage {
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            throw MediaPreparationError.unreadable(.image)
        }
        return image
    }

    /// Extract frames at 33% and 66% of video duration for multi-frame analysis,
    /// matching the Mac app's VideoFrameExtractor.extractAnalysisFrames behavior.
    private func extractVideoFrames(from fileURL: URL) async throws -> [UIImage] {
        do {
            let asset = AVURLAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 1280)

            let durationTime = try await asset.load(.duration)
            let duration = CMTimeGetSeconds(durationTime)
            guard duration > 0 else {
                let (cgImage, _) = try await generator.image(at: .zero)
                return [UIImage(cgImage: cgImage)]
            }

            var frames: [UIImage] = []
            for fraction in [0.33, 0.66] {
                try Task.checkCancellation()
                let time = CMTime(seconds: duration * fraction, preferredTimescale: 600)
                let (cgImage, _) = try await generator.image(at: time)
                frames.append(UIImage(cgImage: cgImage))
            }
            return frames
        } catch {
            try Task.checkCancellation()
            throw MediaPreparationError.unreadable(.video)
        }
    }
}
