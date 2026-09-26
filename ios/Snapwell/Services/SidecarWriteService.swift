import Foundation

/// Owns iOS sidecar writes. Edits made while an iCloud file is a placeholder are
/// journaled locally, then merged into the downloaded JSON before the next sync.
@MainActor
enum SidecarWriteService {
    private struct PendingAnalysis: Codable {
        let imageContext: String
        let imageSummary: String
        let patterns: [SidecarPattern]
        let analyzedAt: Date
    }

    private struct PendingItemEdit: Codable {
        let baseline: SidecarMetadata
        var spaceIds: [String]?
        var analysis: PendingAnalysis?
    }

    private struct PendingSpaceEdit: Codable {
        let id: String
        /// Nil means delete this space.
        let value: SidecarSpace?
    }

    private struct PendingRoot: Codable {
        var items: [String: PendingItemEdit] = [:]
        var spaces: [String: PendingSpaceEdit] = [:]
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let journalURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Snapwell/pending-sidecar-edits.json")
    }()

    private static func loadJournal() -> [String: PendingRoot] {
        guard let data = try? Data(contentsOf: journalURL),
              let decoded = try? decoder.decode([String: PendingRoot].self, from: data) else { return [:] }
        return decoded
    }

    private static var journal: [String: PendingRoot] = loadJournal()

    static func reloadPendingFromDisk() {
        journal = loadJournal()
    }

    private static func key(for rootURL: URL) -> String { rootURL.standardizedFileURL.path }

    private static func persist() {
        do {
            try FileManager.default.createDirectory(
                at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try encoder.encode(journal).write(to: journalURL, options: .atomic)
        } catch {
            print("[SidecarWrite] Failed to save pending edit journal: \(error)")
        }
    }

    private static func usesICloud(_ rootURL: URL) -> Bool {
        FileSystemManager.shared?.isUsingiCloud == true &&
            FileSystemManager.shared?.rootURL?.standardizedFileURL == rootURL.standardizedFileURL
    }

    private static func state(of url: URL, rootURL: URL) -> DownloadState {
        let hasPlaceholder = FileManager.default.fileExists(atPath: ICloudFile.placeholderURL(for: url).path)
        return ICloudFile.downloadState(of: url, isUsingiCloud: usesICloud(rootURL) || hasPlaceholder)
    }

    private static func baseline(for item: MediaItem) -> SidecarMetadata {
        SidecarMetadata(
            id: item.id, type: item.mediaType.rawValue, width: item.width, height: item.height,
            createdAt: item.createdAt, duration: item.duration, spaceIds: item.orderedSpaceIDs,
            imageContext: item.analysisResult?.imageContext,
            imageSummary: item.analysisResult?.imageSummary,
            patterns: item.analysisResult?.patterns.map {
                SidecarPattern(name: $0.name, confidence: $0.confidence)
            },
            sourceURL: item.sourceURL, analyzedAt: item.analysisResult?.analyzedAt
        )
    }

    static func writeSpaceMembership(for item: MediaItem, rootURL: URL) {
        let rootKey = key(for: rootURL)
        var root = journal[rootKey] ?? PendingRoot()
        var edit = root.items[item.id] ?? PendingItemEdit(baseline: baseline(for: item))
        edit.spaceIds = item.orderedSpaceIDs
        root.items[item.id] = edit
        journal[rootKey] = root
        persist()
        flushPending(rootURL: rootURL)
    }

    static func writeSpaceId(for item: MediaItem, rootURL: URL) {
        writeSpaceMembership(for: item, rootURL: rootURL)
    }

    static func writeAnalysis(for item: MediaItem, rootURL: URL) {
        guard let result = item.analysisResult else { return }
        let rootKey = key(for: rootURL)
        var root = journal[rootKey] ?? PendingRoot()
        var edit = root.items[item.id] ?? PendingItemEdit(baseline: baseline(for: item))
        edit.analysis = PendingAnalysis(
            imageContext: result.imageContext, imageSummary: result.imageSummary,
            patterns: result.patterns.map { SidecarPattern(name: $0.name, confidence: $0.confidence) },
            analyzedAt: result.analyzedAt
        )
        root.items[item.id] = edit
        journal[rootKey] = root
        persist()
        flushPending(rootURL: rootURL)
    }

    static func upsertSpace(_ space: Space, rootURL: URL) {
        let value = SidecarSpace(
            id: space.id, name: space.name, order: space.order, createdAt: space.createdAt,
            customPrompt: space.customPrompt, useCustomPrompt: space.useCustomPrompt,
            hideFromAllMedia: space.hideFromAllMedia
        )
        enqueueSpace(PendingSpaceEdit(id: space.id, value: value), rootURL: rootURL)
    }

    static func deleteSpace(id: String, rootURL: URL) {
        enqueueSpace(PendingSpaceEdit(id: id, value: nil), rootURL: rootURL)
    }

    private static func enqueueSpace(_ edit: PendingSpaceEdit, rootURL: URL) {
        let rootKey = key(for: rootURL)
        var root = journal[rootKey] ?? PendingRoot()
        root.spaces[edit.id] = edit
        journal[rootKey] = root
        persist()
        flushPending(rootURL: rootURL)
    }

    /// Legacy bulk writer. Merge each supplied space by ID so remote spaces are not dropped.
    static func writeSpaces(_ spaces: [Space], rootURL: URL) {
        for space in spaces { upsertSpace(space, rootURL: rootURL) }
    }

    static func hasPendingItemEdit(id: String, rootURL: URL) -> Bool {
        journal[key(for: rootURL)]?.items[id] != nil
    }

    static func discardItemEdit(id: String, rootURL: URL) {
        let rootKey = key(for: rootURL)
        guard var root = journal[rootKey] else { return }
        root.items.removeValue(forKey: id)
        if root.items.isEmpty && root.spaces.isEmpty {
            journal.removeValue(forKey: rootKey)
        } else {
            journal[rootKey] = root
        }
        persist()
    }

    static func hasPendingSpaceEdits(rootURL: URL) -> Bool {
        journal[key(for: rootURL)]?.spaces.isEmpty == false
    }

    static func flushPending(rootURL: URL) {
        let rootKey = key(for: rootURL)
        guard var root = journal[rootKey] else { return }
        for (id, edit) in root.items.sorted(by: { $0.key < $1.key }) {
            if flushItem(edit, id: id, rootURL: rootURL) { root.items.removeValue(forKey: id) }
        }
        for (id, edit) in root.spaces.sorted(by: { $0.key < $1.key }) {
            if flushSpace(edit, rootURL: rootURL) { root.spaces.removeValue(forKey: id) }
        }
        if root.items.isEmpty && root.spaces.isEmpty {
            journal.removeValue(forKey: rootKey)
        } else {
            journal[rootKey] = root
        }
        persist()
    }

    private static func flushItem(_ edit: PendingItemEdit, id: String, rootURL: URL) -> Bool {
        let url = rootURL.appendingPathComponent("metadata/\(id).json")
        let state = state(of: url, rootURL: rootURL)
        if state == .downloading {
            DownloadRequester.shared.requestDownload(for: url)
            return false
        }
        let data: Data
        if state == .downloaded {
            guard let existing = try? Data(contentsOf: url) else { return false }
            data = existing
        } else {
            guard let baseline = try? encoder.encode(edit.baseline) else { return false }
            data = baseline
        }
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let ids = edit.spaceIds {
            json.removeValue(forKey: "spaceId")
            if ids.isEmpty { json.removeValue(forKey: "spaceIds") }
            else { json["spaceIds"] = ids }
        }
        if let analysis = edit.analysis {
            json["imageContext"] = analysis.imageContext
            json["imageSummary"] = analysis.imageSummary
            json["patterns"] = analysis.patterns.map { ["name": $0.name, "confidence": $0.confidence] }
            json["analyzedAt"] = ISO8601DateFormatter().string(from: analysis.analyzedAt)
        }
        do {
            let output = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.write(to: url, options: .atomic)
            return true
        } catch {
            print("[SidecarWrite] Failed to merge \(id): \(error)")
            return false
        }
    }

    private static func flushSpace(_ edit: PendingSpaceEdit, rootURL: URL) -> Bool {
        let url = rootURL.appendingPathComponent("spaces.json")
        let state = state(of: url, rootURL: rootURL)
        if state == .downloading {
            DownloadRequester.shared.requestDownload(for: url)
            return false
        }
        var json: [String: Any] = [
            "spaces": [],
            "useAllSpaceGuidance": UserDefaults.standard.bool(forKey: "useAllSpacePrompt")
        ]
        if let guidance = UserDefaults.standard.string(forKey: "allSpacePrompt") {
            json["allSpaceGuidance"] = guidance
        }
        if state == .downloaded {
            guard let data = try? Data(contentsOf: url) else { return false }
            if let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = existing
            } else if let legacy = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                json["spaces"] = legacy
            } else {
                return false
            }
        }
        guard var spaces = json["spaces"] as? [[String: Any]] else { return false }
        let previous = spaces.first { $0["id"] as? String == edit.id }
        spaces.removeAll { $0["id"] as? String == edit.id }
        do {
            if let value = edit.value {
                let encoded = try encoder.encode(value)
                guard let fields = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                    return false
                }
                var merged = previous ?? [:]
                for (key, value) in fields { merged[key] = value }
                if value.customPrompt == nil { merged.removeValue(forKey: "customPrompt") }
                spaces.append(merged)
            }
            spaces.sort { ($0["order"] as? Int ?? 0) < ($1["order"] as? Int ?? 0) }
            json["spaces"] = spaces
            let output = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: url, options: .atomic)
            return true
        } catch {
            print("[SidecarWrite] Failed to merge spaces: \(error)")
            return false
        }
    }
}
