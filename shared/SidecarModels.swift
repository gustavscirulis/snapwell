import Foundation

// MARK: - Sidecar JSON Models (shared by the macOS and iOS apps)
//
// These value types are the on-disk contract for `metadata/{id}.json` and
// `spaces.json`. They were previously duplicated verbatim in the Mac
// (`MetadataSidecarService`) and iOS (`SyncService`) apps; any drift between the
// two copies silently broke cross-platform sync, so they now live in one place
// compiled into both targets.

struct SidecarMetadata: Codable, Sendable {
    let id: String
    let type: String
    let width: Int
    let height: Int
    let createdAt: Date
    let duration: Double?
    let spaceIds: [String]?
    let imageContext: String?
    let imageSummary: String?
    let patterns: [SidecarPattern]?
    let sourceURL: String?
    let analyzedAt: Date?

    init(
        id: String,
        type: String,
        width: Int,
        height: Int,
        createdAt: Date,
        duration: Double?,
        spaceIds: [String]? = nil,
        spaceId: String? = nil,
        imageContext: String?,
        imageSummary: String?,
        patterns: [SidecarPattern]?,
        sourceURL: String?,
        analyzedAt: Date?
    ) {
        self.id = id
        self.type = type
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.duration = duration
        if let spaceIds, !spaceIds.isEmpty {
            self.spaceIds = spaceIds
        } else if let spaceId {
            self.spaceIds = [spaceId]
        } else {
            self.spaceIds = nil
        }
        self.imageContext = imageContext
        self.imageSummary = imageSummary
        self.patterns = patterns
        self.sourceURL = sourceURL
        self.analyzedAt = analyzedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case width
        case height
        case createdAt
        case duration
        case spaceIds
        case spaceId
        case imageContext
        case imageSummary
        case patterns
        case sourceURL
        case analyzedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        if let decodedSpaceIds = try container.decodeIfPresent([String].self, forKey: .spaceIds),
           !decodedSpaceIds.isEmpty {
            spaceIds = decodedSpaceIds
        } else if let legacySpaceId = try container.decodeIfPresent(String.self, forKey: .spaceId) {
            spaceIds = [legacySpaceId]
        } else {
            spaceIds = nil
        }
        imageContext = try container.decodeIfPresent(String.self, forKey: .imageContext)
        imageSummary = try container.decodeIfPresent(String.self, forKey: .imageSummary)
        patterns = try container.decodeIfPresent([SidecarPattern].self, forKey: .patterns)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        analyzedAt = try container.decodeIfPresent(Date.self, forKey: .analyzedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(spaceIds, forKey: .spaceIds)
        try container.encodeIfPresent(imageContext, forKey: .imageContext)
        try container.encodeIfPresent(imageSummary, forKey: .imageSummary)
        try container.encodeIfPresent(patterns, forKey: .patterns)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(analyzedAt, forKey: .analyzedAt)
    }

    var normalizedSpaceIDs: [String] {
        spaceIds ?? []
    }

    var spaceId: String? {
        normalizedSpaceIDs.first
    }
}

struct SidecarPattern: Codable, Sendable {
    let name: String
    let confidence: Double
}

struct SidecarSpace: Codable, Sendable {
    let id: String
    let name: String
    let order: Int
    let createdAt: Date
    let customPrompt: String?
    let useCustomPrompt: Bool
    let hideFromAllMedia: Bool

    init(id: String, name: String, order: Int, createdAt: Date,
         customPrompt: String?, useCustomPrompt: Bool, hideFromAllMedia: Bool = false) {
        self.id = id
        self.name = name
        self.order = order
        self.createdAt = createdAt
        self.customPrompt = customPrompt
        self.useCustomPrompt = useCustomPrompt
        self.hideFromAllMedia = hideFromAllMedia
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(String.self, forKey: .id)
        name             = try c.decode(String.self, forKey: .name)
        order            = try c.decode(Int.self, forKey: .order)
        createdAt        = try c.decode(Date.self, forKey: .createdAt)
        customPrompt     = try c.decodeIfPresent(String.self, forKey: .customPrompt)
        useCustomPrompt  = try c.decodeIfPresent(Bool.self, forKey: .useCustomPrompt) ?? false
        hideFromAllMedia = try c.decodeIfPresent(Bool.self, forKey: .hideFromAllMedia) ?? false
    }
}

/// Wrapper for spaces.json that includes all-space guidance alongside the spaces array.
struct SidecarSpacesFile: Codable, Sendable {
    let spaces: [SidecarSpace]
    let allSpaceGuidance: String?
    let useAllSpaceGuidance: Bool

    init(spaces: [SidecarSpace], allSpaceGuidance: String?, useAllSpaceGuidance: Bool) {
        self.spaces = spaces
        self.allSpaceGuidance = allSpaceGuidance
        self.useAllSpaceGuidance = useAllSpaceGuidance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spaces              = try c.decode([SidecarSpace].self, forKey: .spaces)
        allSpaceGuidance    = try c.decodeIfPresent(String.self, forKey: .allSpaceGuidance)
        useAllSpaceGuidance = try c.decodeIfPresent(Bool.self, forKey: .useAllSpaceGuidance) ?? false
    }
}
