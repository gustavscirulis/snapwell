import Testing
import SwiftData
import UIKit
@testable import Snapwell

/// Tests for the WS4 "Performance at scale" hardening work:
///  1. `analyzeUnanalyzed` predicate fetch returns the same set as the old in-memory filter.
///  2. The full-screen overlay decodes a bounded, downsampled image (smaller than source).
///  3. `ThumbnailCache.pruneDiskCache` removes orphaned cache files but keeps live ones.
@Suite("Performance hardening", .tags(.state))
@MainActor
struct PerformanceHardeningTests {

    // Tiny placeholder bytes used to populate disk-cache files in GC tests.
    // Content doesn't matter — the GC only inspects filenames.
    private static let placeholderData = Data([0x00, 0x01, 0x02, 0x03])

    /// Unique throwaway directory for filesystem tests; caller removes it.
    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapwellPerfTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 1. Predicate fetch parity

    /// The new predicate-narrowed fetch + relationship filter must return exactly
    /// the same MediaItems as the previous fetch-all-then-filter implementation.
    @Test("Unanalyzed predicate fetch matches the legacy in-memory filter", .tags(.state))
    func unanalyzedFetchMatchesLegacyFilter() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        // analyzable: no result, not analyzing, no error  -> SHOULD be selected
        let analyzable = MediaItem(mediaType: .image, filename: "a.png", width: 10, height: 10)

        // analyzing in flight -> excluded
        let analyzing = MediaItem(mediaType: .image, filename: "b.png", width: 10, height: 10)
        analyzing.isAnalyzing = true

        // previously errored -> excluded
        let errored = MediaItem(mediaType: .image, filename: "c.png", width: 10, height: 10)
        errored.analysisError = "boom"

        // already analyzed (has a result) -> excluded
        let analyzed = MediaItem(mediaType: .image, filename: "d.png", width: 10, height: 10)
        analyzed.analysisResult = AnalysisResult(
            imageContext: "ctx", imageSummary: "sum", patterns: [], provider: "test", model: "test")

        // second analyzable -> SHOULD be selected
        let analyzable2 = MediaItem(mediaType: .video, filename: "e.mp4", width: 10, height: 10)

        for item in [analyzable, analyzing, errored, analyzed, analyzable2] {
            context.insert(item)
        }
        context.saveOrLog()

        // Legacy behavior: fetch all, filter in memory.
        let allItems = try context.fetch(FetchDescriptor<MediaItem>())
        let legacy = Set(allItems.filter {
            $0.analysisResult == nil && !$0.isAnalyzing && $0.analysisError == nil
        }.map(\.id))

        // New behavior: predicate narrows scalar flags, relationship filtered after.
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { !$0.isAnalyzing && $0.analysisError == nil }
        )
        descriptor.includePendingChanges = true
        let candidates = try context.fetch(descriptor)
        let predicated = Set(candidates.filter { $0.analysisResult == nil }.map(\.id))

        #expect(predicated == legacy)
        #expect(predicated == [analyzable.id, analyzable2.id])
        // The predicate alone must already drop the analyzing + errored items.
        #expect(!candidates.contains { $0.id == analyzing.id })
        #expect(!candidates.contains { $0.id == errored.id })
    }

    @Test("Predicate fetch returns empty when nothing is analyzable", .tags(.state))
    func unanalyzedFetchEmptyWhenNoneAnalyzable() throws {
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let analyzing = MediaItem(mediaType: .image, filename: "a.png", width: 10, height: 10)
        analyzing.isAnalyzing = true
        let analyzed = MediaItem(mediaType: .image, filename: "b.png", width: 10, height: 10)
        analyzed.analysisResult = AnalysisResult(
            imageContext: "c", imageSummary: "s", patterns: [], provider: "test", model: "test")
        context.insert(analyzing)
        context.insert(analyzed)
        context.saveOrLog()

        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { !$0.isAnalyzing && $0.analysisError == nil }
        )
        descriptor.includePendingChanges = true
        let result = try context.fetch(descriptor).filter { $0.analysisResult == nil }
        #expect(result.isEmpty)
    }

    // MARK: - 2. Overlay downsampling

    /// Decoding a large image with a bounded target width must produce a bitmap
    /// whose pixel dimensions are no larger than the source — i.e. full-res
    /// buffers are never created for the full-screen view.
    @Test("Bounded decode downsamples a large image below the source size", .tags(.layout))
    func boundedDecodeProducesSmallerImage() async throws {
        let root = try IntegrationTestSupport.makeTempRoot()
        defer { IntegrationTestSupport.cleanup(root) }

        // Build a deliberately large source image (4000px wide).
        let sourcePixels: CGFloat = 4000
        let bigURL = root.appendingPathComponent("images/big.jpg")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: sourcePixels, height: sourcePixels),
            format: format
        )
        let big = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: sourcePixels, height: sourcePixels))
        }
        try big.jpegData(compressionQuality: 0.9)!.write(to: bigURL)

        let targetWidth: CGFloat = 1000 // well below 4000
        let result = await ThumbnailCache.shared.loadImage(for: bigURL, targetPixelWidth: targetWidth)
        let loaded = try #require(result.image)

        let loadedPixelWidth = loaded.size.width * loaded.scale
        let sourcePixelWidth = big.size.width * big.scale

        // Downsampled, not full-res.
        #expect(loadedPixelWidth < sourcePixelWidth)
        // And it honors the requested bound (allow a small margin for ImageIO rounding).
        #expect(loadedPixelWidth <= targetWidth + 2)
        #expect(loadedPixelWidth > 0)

        // Clean up the cached entry/disk artifact so other tests aren't affected.
        ThumbnailCache.shared.clear()
        ThumbnailCache.shared.pruneDiskCache(liveItemIDs: [])
    }

    // MARK: - 3. Disk-cache garbage collection

    @Test("Cache filename parsing extracts the item id", .tags(.filesystem))
    func cacheFilenameParsing() {
        #expect(ThumbnailCache.itemID(fromCacheFilename: "ABC123.jpg") == "ABC123")
        #expect(ThumbnailCache.itemID(fromCacheFilename: "ABC123@2000w.jpg") == "ABC123")
        // UUID-style ids may contain hyphens; must survive intact.
        let uuid = "11111111-2222-3333-4444-555555555555"
        #expect(ThumbnailCache.itemID(fromCacheFilename: "\(uuid).jpg") == uuid)
        #expect(ThumbnailCache.itemID(fromCacheFilename: "\(uuid)@800w.jpg") == uuid)
        // Non-cache files are ignored.
        #expect(ThumbnailCache.itemID(fromCacheFilename: "notes.txt") == nil)
        #expect(ThumbnailCache.itemID(fromCacheFilename: ".DS_Store") == nil)
    }

    /// GC removes cache files with no live item but keeps files for live items,
    /// and never touches files it didn't write.
    @Test("Prune removes orphan cache files but keeps live ones", .tags(.filesystem))
    func pruneRemovesOrphansKeepsLive() throws {
        let fm = FileManager.default
        // Point the shared cache at a private temp dir for this test.
        let dir = fm.temporaryDirectory
            .appendingPathComponent("SnapwellThumbCacheTest")
            .appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let cache = ThumbnailCache.makeForTesting(diskCacheDir: dir)

        let liveID = "live-0001"
        let orphanID = "orphan-9999"

        let livePlain = dir.appendingPathComponent("\(liveID).jpg")
        let liveSized = dir.appendingPathComponent("\(liveID)@2000w.jpg")
        let orphanPlain = dir.appendingPathComponent("\(orphanID).jpg")
        let orphanSized = dir.appendingPathComponent("\(orphanID)@800w.jpg")
        let foreign = dir.appendingPathComponent("README.txt") // not ours

        let payload = IntegrationTestSupport.dummyPNGData
        for url in [livePlain, liveSized, orphanPlain, orphanSized, foreign] {
            try payload.write(to: url)
        }

        let removed = cache.pruneDiskCache(liveItemIDs: [liveID])

        #expect(removed == 2)
        #expect(fm.fileExists(atPath: livePlain.path))
        #expect(fm.fileExists(atPath: liveSized.path))
        #expect(!fm.fileExists(atPath: orphanPlain.path))
        #expect(!fm.fileExists(atPath: orphanSized.path))
        // A foreign (non-cache) file must be left completely alone.
        #expect(fm.fileExists(atPath: foreign.path))
    }

    @Test("Prune with no live items clears the whole cache directory", .tags(.filesystem))
    func pruneEmptyLiveSetClearsAll() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("SnapwellThumbCacheTest")
            .appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let cache = ThumbnailCache.makeForTesting(diskCacheDir: dir)
        for i in 0..<5 {
            try IntegrationTestSupport.dummyPNGData.write(
                to: dir.appendingPathComponent("item-\(i).jpg"))
        }

        let removed = cache.pruneDiskCache(liveItemIDs: [])
        #expect(removed == 5)
        let remaining = try fm.contentsOfDirectory(atPath: dir.path)
        #expect(remaining.isEmpty)
    }
}
