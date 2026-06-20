import Foundation
import SwiftData

// SupportedMedia, MediaFilenameResolver, and the Sidecar JSON models
// (SidecarMetadata/SidecarPattern/SidecarSpace/SidecarSpacesFile) now live in
// shared/SupportedMedia.swift and shared/SidecarModels.swift, compiled into both apps.

// MARK: - SyncService

/// Reads sidecar JSON files from the iCloud container and syncs them into SwiftData.
/// Read-only — never writes to the filesystem (the Mac app is the writer).
@MainActor
final class SyncService {

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Full sync from disk to SwiftData. Call on app launch and when returning to foreground.
    /// Returns the number of iCloud files that were still downloading (skipped).
    @discardableResult
    func sync(rootURL: URL, context: ModelContext) async -> Int {
        let metadataDir = rootURL.appendingPathComponent("metadata")
        let imagesDir = rootURL.appendingPathComponent("images")
        let fm = FileManager.default

        // Phase 1: Import spaces
        syncSpaces(rootURL: rootURL, context: context)

        // Phase 2: Scan metadata files
        guard let contents = try? fm.contentsOfDirectory(
            at: metadataDir,
            includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
            options: []
        ) else {
            print("[SyncService] Cannot read metadata directory")
            return 0
        }

        let isUsingiCloud = FileSystemManager.shared?.isUsingiCloud ?? false

        let jsonFiles = contents.filter { url in
            let name = url.lastPathComponent
            if isUsingiCloud {
                return name.hasSuffix(".json") || name.hasSuffix(".json.icloud")
            }
            return name.hasSuffix(".json")
        }

        print("[SyncService] Found \(jsonFiles.count) metadata files")

        // Phase 3: Load existing items from SwiftData for diffing
        let existingItems = (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
        var existingById: [String: MediaItem] = [:]
        for item in existingItems {
            existingById[item.id] = item
        }

        var seenIds = Set<String>()
        var skipped = 0
        var imported = 0

        for url in jsonFiles {
            let fileName = url.lastPathComponent

            // iCloud placeholder — trigger download, skip
            if isUsingiCloud && fileName.hasSuffix(".json.icloud") {
                var realName = String(fileName.dropLast(".icloud".count))
                if realName.hasPrefix(".") { realName = String(realName.dropFirst()) }
                let realURL = url.deletingLastPathComponent().appendingPathComponent(realName)
                try? fm.startDownloadingUbiquitousItem(at: realURL)
                skipped += 1
                continue
            }

            // Check if JSON is downloaded (iCloud only)
            if isUsingiCloud,
               let rv = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               let status = rv.ubiquitousItemDownloadingStatus,
               status != .current {
                try? fm.startDownloadingUbiquitousItem(at: url)
                skipped += 1
                continue
            }

            guard let data = try? Data(contentsOf: url) else { continue }
            guard let sidecar = try? Self.decoder.decode(SidecarMetadata.self, from: data) else { continue }

            let id = url.deletingPathExtension().lastPathComponent
            seenIds.insert(id)

            // Resolve the real on-disk media filename across all supported extensions
            // (not a mp4/png guess) so heic/webp/m4v/avi/webm files aren't orphaned.
            let preferredExts = sidecar.type == "video" ? ["mp4", "mov", "m4v", "webm"] : ["png", "jpg", "jpeg", "heic"]
            guard let mediaFilename = MediaFilenameResolver.resolveMediaFilename(
                id: id, in: imagesDir, preferredExtensions: preferredExts
            ) else {
                continue // Orphaned sidecar: no media file or iCloud placeholder for any supported extension
            }
            let mediaURL = imagesDir.appendingPathComponent(mediaFilename)

            if !fm.fileExists(atPath: mediaURL.path) {
                // Resolver matched an iCloud placeholder — trigger the download.
                if isUsingiCloud {
                    try? fm.startDownloadingUbiquitousItem(at: mediaURL)
                } else {
                    continue // Local mode: placeholder without a real file means orphaned
                }
            } else if isUsingiCloud,
                      let rv = try? mediaURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                      let status = rv.ubiquitousItemDownloadingStatus,
                      status != .current {
                // Real file present but evicted/not current — trigger the download.
                try? fm.startDownloadingUbiquitousItem(at: mediaURL)
            }

            // Upsert into SwiftData
            if let existing = existingById[id] {
                // Update existing item if analysis changed
                updateIfNeeded(existing, from: sidecar, context: context)
                existingById.removeValue(forKey: id)
            } else {
                // Create new item
                let mediaType: MediaType = sidecar.type == "video" ? .video : .image
                let item = MediaItem(
                    id: id,
                    mediaType: mediaType,
                    filename: mediaFilename,
                    width: sidecar.width,
                    height: sidecar.height,
                    createdAt: sidecar.createdAt,
                    duration: sidecar.duration
                )
                item.sourceURL = sidecar.sourceURL

                // Assign space
                let resolvedSpaces = spaces(for: sidecar.normalizedSpaceIDs, in: context)
                item.setMembership(resolvedSpaces)

                // Assign analysis result
                if let imageContext = sidecar.imageContext, !imageContext.isEmpty {
                    let patterns = (sidecar.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
                    item.analysisResult = AnalysisResult(
                        imageContext: imageContext,
                        imageSummary: sidecar.imageSummary ?? "",
                        patterns: patterns,
                        analyzedAt: sidecar.analyzedAt ?? .now,
                        provider: "synced",
                        model: "icloud-sync"
                    )
                }

                context.insert(item)
                imported += 1
            }

            // Yield periodically
            if imported % 20 == 0 && imported > 0 {
                context.saveOrLog()
                await Task.yield()
            }
        }

        // Phase 4: Remove orphaned SwiftData items (sidecar was deleted on Mac)
        for (_, orphan) in existingById {
            context.delete(orphan)
        }

        context.saveOrLog()
        print("[SyncService] Sync complete: \(imported) new, \(skipped) pending iCloud, \(existingById.count) removed")
        return skipped
    }

    // MARK: - Spaces

    private func syncSpaces(rootURL: URL, context: ModelContext) {
        let spacesURL = rootURL.appendingPathComponent("spaces.json")
        guard let data = try? Data(contentsOf: spacesURL) else { return }

        // Decode wrapper format first, fall back to legacy bare array
        let sidecars: [SidecarSpace]
        if let file = try? Self.decoder.decode(SidecarSpacesFile.self, from: data) {
            sidecars = file.spaces
            // Sync all-space guidance to UserDefaults so it's available during analysis
            if let allGuidance = file.allSpaceGuidance {
                UserDefaults.standard.set(allGuidance, forKey: "allSpacePrompt")
            }
            UserDefaults.standard.set(file.useAllSpaceGuidance, forKey: "useAllSpacePrompt")
        } else if let legacySpaces = try? Self.decoder.decode([SidecarSpace].self, from: data) {
            sidecars = legacySpaces
        } else {
            return
        }

        let existing = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        var existingById: [String: Space] = [:]
        for space in existing { existingById[space.id] = space }

        for sidecar in sidecars {
            if let space = existingById[sidecar.id] {
                space.name = sidecar.name
                space.order = sidecar.order
                space.customPrompt = sidecar.customPrompt
                space.useCustomPrompt = sidecar.useCustomPrompt
                space.hideFromAllMedia = sidecar.hideFromAllMedia
                existingById.removeValue(forKey: sidecar.id)
            } else {
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

        // Remove spaces that no longer exist in sidecar
        for (_, orphan) in existingById {
            context.delete(orphan)
        }

        context.saveOrLog()
    }

    // MARK: - Update Helpers

    private func updateIfNeeded(_ item: MediaItem, from sidecar: SidecarMetadata, context: ModelContext) {
        // Update space assignment if changed
        let resolvedSpaces = spaces(for: sidecar.normalizedSpaceIDs, in: context)
        if item.orderedSpaceIDs != resolvedSpaces.map(\.id) {
            item.setMembership(resolvedSpaces)
        }

        // Update source URL if it was added
        if item.sourceURL == nil, let sourceURL = sidecar.sourceURL {
            item.sourceURL = sourceURL
        }

        // Update analysis if the remote sidecar has newer or missing-locally analysis
        let hasAnalysis = sidecar.imageContext != nil && !(sidecar.imageContext?.isEmpty ?? true)
        if hasAnalysis {
            let shouldSync: Bool
            if item.analysisResult == nil {
                shouldSync = true
            } else if let remoteDate = sidecar.analyzedAt,
                      let localDate = item.analysisResult?.analyzedAt,
                      remoteDate > localDate {
                shouldSync = true
            } else {
                shouldSync = false
            }

            if shouldSync {
                let patterns = (sidecar.patterns ?? []).map { PatternTag(name: $0.name, confidence: $0.confidence) }
                item.analysisResult = AnalysisResult(
                    imageContext: sidecar.imageContext!,
                    imageSummary: sidecar.imageSummary ?? "",
                    patterns: patterns,
                    analyzedAt: sidecar.analyzedAt ?? .now,
                    provider: "synced",
                    model: "icloud-sync"
                )
            }
        }
    }

    private func spaces(for ids: [String], in context: ModelContext) -> [Space] {
        guard !ids.isEmpty else { return [] }
        let availableSpaces = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        let idSet = Set(ids)
        return availableSpaces
            .filter { idSet.contains($0.id) }
            .membershipSorted()
    }
}
