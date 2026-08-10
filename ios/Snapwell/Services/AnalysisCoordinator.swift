import AVFoundation
import SwiftData
import UIKit

/// Coordinates AI analysis of media items, extracting this logic from MainView.
@Observable
@MainActor
final class AnalysisCoordinator {
    private var analysisTask: Task<Void, Never>?
    var analysisAlertError: String?

    // Dependencies — set once via configure(), used by all analysis methods.
    private var keySyncService: KeySyncService?
    private var fileSystem: FileSystemManager?
    private var modelContext: ModelContext?
    private var searchService: SearchIndexService?

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

    /// Analyze specific items.
    func analyzeItems(_ items: [MediaItem], allItems: [MediaItem]) {
        guard let keySyncService, let fileSystem, let modelContext, let searchService else {
            print("[Analysis] Skipped — coordinator not configured")
            return
        }

        guard keySyncService.isUnlocked else {
            print("[Analysis] Skipped — keySyncService not unlocked")
            return
        }
        guard let providerStr = keySyncService.activeProvider,
              let provider = AIProvider(rawValue: providerStr) else {
            print("[Analysis] Skipped — no active provider")
            return
        }
        guard let apiKey = keySyncService.activeAPIKey() else {
            print("[Analysis] Skipped — no API key for provider \(providerStr)")
            return
        }
        guard let rootURL = fileSystem.rootURL else {
            print("[Analysis] Skipped — no rootURL")
            return
        }

        let storedModel = keySyncService.activeModel ?? ModelDiscoveryService.autoModelValue
        let usesRecommendedModel = storedModel == ModelDiscoveryService.autoModelValue

        guard !items.isEmpty else {
            print("[Analysis] No items to analyze")
            return
        }

        print("[Analysis] Starting analysis of \(items.count) item(s)")

        analysisAlertError = nil
        analysisTask?.cancel()
        analysisTask = Task {
            var rejectedRecommendedModels: Set<String> = []
            var resolvedModel = usesRecommendedModel
                ? await ModelDiscoveryService.shared.resolveAutoModel(for: provider)
                : storedModel

            for item in items {
                guard !Task.isCancelled else { break }

                item.isAnalyzing = true
                do {
                    let (guidance, spaceContext) = SpaceGuidanceResolver.resolve(for: item)

                    let result: AnalysisResult
                    do {
                        result = try await runAnalysis(
                            item,
                            rootURL: rootURL,
                            provider: provider,
                            model: resolvedModel,
                            apiKey: apiKey,
                            guidance: guidance,
                            spaceContext: spaceContext
                        )
                    } catch let error as AIAnalysisService.AnalysisError
                        where usesRecommendedModel && Self.indicatesUnusableModel(error) {
                        rejectedRecommendedModels.insert(resolvedModel)
                        ModelDiscoveryService.shared.clearCache(for: provider)
                        let fallback = await ModelDiscoveryService.shared.resolveAutoModel(
                            for: provider,
                            excluding: rejectedRecommendedModels
                        )
                        guard fallback != resolvedModel else { throw error }
                        resolvedModel = fallback
                        result = try await runAnalysis(
                            item,
                            rootURL: rootURL,
                            provider: provider,
                            model: resolvedModel,
                            apiKey: apiKey,
                            guidance: guidance,
                            spaceContext: spaceContext
                        )
                    }
                    item.analysisResult = result
                    item.isAnalyzing = false
                    item.analysisError = nil

                    SidecarWriteService.writeAnalysis(for: item, rootURL: rootURL)
                    searchService.addToIndex(item: item)
                    modelContext.saveOrLog()
                    print("[Analysis] Completed: \(item.id)")
                } catch {
                    item.isAnalyzing = false
                    item.analysisError = error.localizedDescription
                    self.analysisAlertError = error.localizedDescription
                    print("[Analysis] Failed for \(item.id): \(error.localizedDescription)")
                    break
                }
            }
        }
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

    // MARK: - Private Helpers

    nonisolated static func indicatesUnusableModel(_ error: AIAnalysisService.AnalysisError) -> Bool {
        guard case .apiError(let code, _, _) = error else { return false }
        return code == 400 || code == 404
    }

    private func runAnalysis(
        _ item: MediaItem,
        rootURL: URL,
        provider: AIProvider,
        model: String,
        apiKey: String,
        guidance: String?,
        spaceContext: String?
    ) async throws -> AnalysisResult {
        if item.isVideo {
            let frames = try extractVideoFrames(for: item, rootURL: rootURL)
            return try await AIAnalysisService.shared.analyzeVideo(
                frames: frames,
                provider: provider,
                model: model,
                apiKey: apiKey,
                guidance: guidance,
                spaceContext: spaceContext
            )
        }

        let image = try loadImage(for: item, rootURL: rootURL)
        return try await AIAnalysisService.shared.analyze(
            image: image,
            provider: provider,
            model: model,
            apiKey: apiKey,
            guidance: guidance,
            spaceContext: spaceContext
        )
    }

    private func loadImage(for item: MediaItem, rootURL: URL) throws -> UIImage {
        let fileURL = rootURL.appendingPathComponent("images/\(item.filename)")
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            throw AIAnalysisService.AnalysisError.imageConversionFailed
        }
        return image
    }

    /// Extract frames at 33% and 66% of video duration for multi-frame analysis,
    /// matching the Mac app's VideoFrameExtractor.extractAnalysisFrames behavior.
    private func extractVideoFrames(for item: MediaItem, rootURL: URL) throws -> [UIImage] {
        let fileURL = rootURL.appendingPathComponent("images/\(item.filename)")
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)

        let duration = CMTimeGetSeconds(asset.duration)
        guard duration > 0 else {
            // Fall back to first frame for very short or broken videos
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return [UIImage(cgImage: cgImage)]
        }

        let fractions = [0.33, 0.66]
        var frames: [UIImage] = []
        for fraction in fractions {
            let time = CMTime(seconds: duration * fraction, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            frames.append(UIImage(cgImage: cgImage))
        }
        return frames
    }

}
