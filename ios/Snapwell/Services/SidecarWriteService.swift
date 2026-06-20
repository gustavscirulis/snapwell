import Foundation

/// Centralizes all sidecar JSON write operations for the iOS app.
/// Uses a merge strategy when the sidecar exists, or creates a complete
/// sidecar from model data when the file hasn't downloaded from iCloud yet.
///
/// Implemented as an `actor` so that read-modify-write updates to the same
/// sidecar file cannot interleave. Concurrent `writeAnalysis` +
/// `writeSpaceMembership` on the same item would otherwise race
/// (last-writer-wins, clobbering each other's fields). All updates funnel
/// through the shared serial actor, which guarantees they run one at a time.
///
/// The public API is `@MainActor` static methods: they snapshot the
/// `MediaItem` (a non-`Sendable` SwiftData `@Model`) into plain value types on
/// the main actor, then hand those values to the actor for the serialized write.
actor SidecarWriteService {

    static let shared = SidecarWriteService()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // MARK: - Snapshot

    /// A `Sendable` snapshot of the fields a sidecar write needs, captured on the
    /// main actor so the non-`Sendable` `MediaItem` never crosses the actor boundary.
    private struct ItemSnapshot: Sendable {
        let id: String
        let mediaType: String
        let width: Int
        let height: Int
        let createdAt: Date
        let duration: Double?
        let spaceIds: [String]
        let sourceURL: String?
        let imageContext: String?
        let imageSummary: String?
        let patterns: [SidecarPattern]?
        let analyzedAt: Date?

        @MainActor
        init(_ item: MediaItem) {
            id = item.id
            mediaType = item.mediaType.rawValue
            width = item.width
            height = item.height
            createdAt = item.createdAt
            duration = item.duration
            spaceIds = item.orderedSpaceIDs
            sourceURL = item.sourceURL
            imageContext = item.analysisResult?.imageContext
            imageSummary = item.analysisResult?.imageSummary
            patterns = item.analysisResult?.patterns.map { SidecarPattern(name: $0.name, confidence: $0.confidence) }
            analyzedAt = item.analysisResult?.analyzedAt
        }
    }

    // MARK: - Public API (main-actor entry points)

    /// Update the spaceIds field in a media item's sidecar JSON.
    /// Removes both membership keys when the item has no spaces.
    /// Falls back to writing a complete sidecar if the file doesn't exist yet.
    @MainActor
    static func writeSpaceMembership(for item: MediaItem, rootURL: URL) async {
        let snapshot = ItemSnapshot(item)
        await shared.applySpaceMembership(snapshot, rootURL: rootURL)
    }

    @MainActor
    static func writeSpaceId(for item: MediaItem, rootURL: URL) async {
        await writeSpaceMembership(for: item, rootURL: rootURL)
    }

    /// Write analysis results back to a media item's sidecar JSON.
    /// Falls back to writing a complete sidecar if the file doesn't exist yet.
    @MainActor
    static func writeAnalysis(for item: MediaItem, rootURL: URL) async {
        let snapshot = ItemSnapshot(item)
        await shared.applyAnalysis(snapshot, rootURL: rootURL)
    }

    /// Write the full spaces list to spaces.json, mirroring the Mac app's format.
    /// Preserves allSpaceGuidance from UserDefaults so it round-trips through iCloud.
    @MainActor
    static func writeSpaces(_ spaces: [Space], rootURL: URL) async {
        let sidecars = spaces.map { space in
            SidecarSpace(
                id: space.id,
                name: space.name,
                order: space.order,
                createdAt: space.createdAt,
                customPrompt: space.customPrompt,
                useCustomPrompt: space.useCustomPrompt,
                hideFromAllMedia: space.hideFromAllMedia
            )
        }

        let allGuidance = UserDefaults.standard.string(forKey: "allSpacePrompt")
        let useAllGuidance = UserDefaults.standard.bool(forKey: "useAllSpacePrompt")

        let file = SidecarSpacesFile(
            spaces: sidecars,
            allSpaceGuidance: allGuidance,
            useAllSpaceGuidance: useAllGuidance
        )
        await shared.applySpaces(file, rootURL: rootURL)
    }

    // MARK: - Serialized writes (actor-isolated)

    private func applySpaceMembership(_ snapshot: ItemSnapshot, rootURL: URL) {
        updateSidecar(snapshot, rootURL: rootURL) { json in
            if snapshot.spaceIds.isEmpty {
                json.removeValue(forKey: "spaceIds")
                json.removeValue(forKey: "spaceId")
            } else {
                json["spaceIds"] = snapshot.spaceIds
                json.removeValue(forKey: "spaceId")
            }
        }
    }

    private func applyAnalysis(_ snapshot: ItemSnapshot, rootURL: URL) {
        updateSidecar(snapshot, rootURL: rootURL) { json in
            // analyzedAt is set iff the item has an analysisResult (all-or-nothing snapshot).
            guard let analyzedAt = snapshot.analyzedAt else { return }
            json["imageContext"] = snapshot.imageContext
            json["imageSummary"] = snapshot.imageSummary
            json["patterns"] = (snapshot.patterns ?? []).map { ["name": $0.name, "confidence": $0.confidence] }
            let formatter = ISO8601DateFormatter()
            json["analyzedAt"] = formatter.string(from: analyzedAt)
        }
    }

    private func applySpaces(_ file: SidecarSpacesFile, rootURL: URL) {
        let spacesURL = rootURL.appendingPathComponent("spaces.json")
        if let data = try? Self.encoder.encode(file) {
            try? data.write(to: spacesURL, options: .atomic)
        }
    }

    // MARK: - Private

    /// Read-modify-write helper: loads existing sidecar JSON, applies the update
    /// closure, and writes back. Falls back to a full sidecar if the file
    /// hasn't downloaded from iCloud yet. Actor-isolated, so calls for any sidecar
    /// are serialized and cannot interleave.
    private func updateSidecar(
        _ snapshot: ItemSnapshot,
        rootURL: URL,
        update: (inout [String: Any]) -> Void
    ) {
        let sidecarURL = rootURL.appendingPathComponent("metadata/\(snapshot.id).json")

        if let existingData = try? Data(contentsOf: sidecarURL),
           var json = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            update(&json)
            if let updatedData = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                try? updatedData.write(to: sidecarURL, options: .atomic)
            }
        } else {
            writeFullSidecar(snapshot, to: sidecarURL)
        }
    }

    /// Construct and write a complete sidecar JSON from the snapshot.
    /// Used as a fallback when the existing sidecar hasn't downloaded from iCloud.
    private func writeFullSidecar(_ snapshot: ItemSnapshot, to url: URL) {
        let sidecar = SidecarMetadata(
            id: snapshot.id,
            type: snapshot.mediaType,
            width: snapshot.width,
            height: snapshot.height,
            createdAt: snapshot.createdAt,
            duration: snapshot.duration,
            spaceIds: snapshot.spaceIds,
            imageContext: snapshot.imageContext,
            imageSummary: snapshot.imageSummary,
            patterns: snapshot.patterns,
            sourceURL: snapshot.sourceURL,
            analyzedAt: snapshot.analyzedAt
        )

        if let data = try? Self.encoder.encode(sidecar) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
