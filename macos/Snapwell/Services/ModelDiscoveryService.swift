import Foundation

struct DiscoveredModel: Identifiable, Sendable {
    let id: String
    let displayName: String
    let supportsStructuredOutputs: Bool

    init(id: String, displayName: String, supportsStructuredOutputs: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.supportsStructuredOutputs = supportsStructuredOutputs
    }
}

final class ModelDiscoveryService: @unchecked Sendable {
    static let shared = ModelDiscoveryService()
    static let autoModelValue = "auto"
    private static let cacheLifetime: TimeInterval = 15 * 60

    private struct CacheEntry {
        let models: [DiscoveredModel]
        let fetchedAt: Date
    }

    private var cache: [AIProvider: CacheEntry] = [:]
    private let lock = NSLock()
    private let ollamaClient: OllamaClient

    init(ollamaClient: OllamaClient = .shared) {
        self.ollamaClient = ollamaClient
    }

    // MARK: - Public API

    private func getCached(for provider: AIProvider) -> [DiscoveredModel]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[provider] else { return nil }
        guard Date().timeIntervalSince(entry.fetchedAt) < Self.cacheLifetime else {
            cache.removeValue(forKey: provider)
            return nil
        }
        return entry.models
    }

    private func setCached(_ models: [DiscoveredModel], for provider: AIProvider) {
        lock.lock()
        defer { lock.unlock() }
        cache[provider] = CacheEntry(models: models, fetchedAt: .now)
    }

    func fetchModels(for provider: AIProvider) async throws -> [DiscoveredModel] {
        if let cached = getCached(for: provider) {
            return cached
        }

        let apiKey: String
        if provider.requiresAPIKey {
            guard let storedKey = try KeychainService.get(service: provider.keychainService) else {
                throw DiscoveryError.noAPIKey
            }
            apiKey = storedKey
        } else {
            apiKey = ""
        }

        let models: [DiscoveredModel]
        switch provider {
        case .openai:
            models = try await fetchOpenAIModels(apiKey: apiKey)
        case .anthropic:
            models = try await fetchAnthropicModels(apiKey: apiKey)
        case .gemini:
            models = try await fetchGeminiModels(apiKey: apiKey)
        case .openrouter:
            models = try await fetchOpenRouterModels(apiKey: apiKey)
        case .ollama:
            models = try await ollamaClient.fetchVisionModels()
        }

        setCached(models, for: provider)
        return models
    }

    /// Ordered model-family preferences per provider, matched by prefix against the live
    /// model list. Prefixes rather than exact IDs so a point release still matches; the
    /// scoring heuristics below remain the fallback for families listed nowhere here.
    static let preferredModelPrefixes: [AIProvider: [String]] = [
        .openai: ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.5", "gpt-5.4", "gpt-5", "gpt-4.1", "gpt-4o"],
        .anthropic: ["claude-sonnet-5", "claude-opus-5", "claude-opus-4-8", "claude-haiku-4-5", "claude-sonnet-4-6"],
        .gemini: ["gemini-3.6-flash", "gemini-3.5-flash", "gemini-3.1-flash", "gemini-3-pro", "gemini-2.5-flash", "gemini-2.0-flash"],
        .openrouter: ["google/gemini-3.5-flash", "google/gemini-3.6-flash", "openai/gpt-5.6-luna", "anthropic/claude-sonnet-5"],
        .ollama: ["gemma3:4b", "gemma3:latest", "gemma3:12b", "gemma3:27b", "gemma3"]
    ]

    /// First model matching the earliest preferred prefix. Within a family the shortest ID
    /// wins, which favours the base model over `-pro` / `-image` / `-fast` variants.
    func preferredModel(from models: [DiscoveredModel], for provider: AIProvider) -> DiscoveredModel? {
        guard let prefixes = Self.preferredModelPrefixes[provider] else { return nil }
        let compatibleModels = models.filter {
            provider != .openrouter || $0.supportsStructuredOutputs
        }
        for prefix in prefixes {
            let matches = compatibleModels.filter { $0.id.lowercased().hasPrefix(prefix) }
            if let best = matches.min(by: { ($0.id.count, $0.id) < ($1.id.count, $1.id) }) {
                return best
            }
        }
        return nil
    }

    func resolveAutoModel(for provider: AIProvider, excluding excluded: Set<String> = []) async -> String {
        do {
            let models = try await fetchModels(for: provider).filter {
                !excluded.contains($0.id)
                    && (provider != .openrouter || $0.supportsStructuredOutputs)
            }
            if let preferred = preferredModel(from: models, for: provider) {
                return preferred.id
            }
            return models.first?.id ?? provider.defaultModel
        } catch {
            return provider.defaultModel
        }
    }

    func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    func clearCache(for provider: AIProvider) {
        lock.lock()
        cache.removeValue(forKey: provider)
        lock.unlock()
    }

    /// Returns OpenRouter's advertised structured-output support for a model. A nil result
    /// means discovery failed or the model is unknown, so request-time routing remains the
    /// source of truth via `provider.require_parameters`.
    func structuredOutputSupport(for modelID: String, provider: AIProvider) async -> Bool? {
        guard provider == .openrouter else { return true }
        do {
            return try await fetchModels(for: provider)
                .first(where: { $0.id == modelID })?
                .supportsStructuredOutputs
        } catch {
            return nil
        }
    }

    // MARK: - OpenAI

    private let visionPrefixes = ["gpt-4o", "gpt-4.1", "gpt-5"]
    private let excludedPatterns = [
        "embedding", "tts", "whisper", "dall-e", "davinci", "babbage",
        "moderation", "realtime", "transcribe", "audio", "search",
        "codex", "codecs", "image", "preview"
    ]
    private let dateSnapshotRegex = try! NSRegularExpression(pattern: "\\d{4}-?\\d{2}-?\\d{2}")

    func isOpenAIVisionCapable(_ modelId: String) -> Bool {
        let lower = modelId.lowercased()
        if excludedPatterns.contains(where: { lower.contains($0) }) { return false }
        if hasDateSnapshot(lower) { return false }
        return visionPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    func openAIScore(_ modelId: String) -> Int {
        let lower = modelId.lowercased()
        var score = 0
        if lower.hasPrefix("gpt-5") {
            score = 5000
            if let match = lower.range(of: "gpt-5\\.(\\d+)", options: .regularExpression),
               let digit = Int(String(lower[match].dropFirst(5))) {
                score += digit * 100
            }
        } else if lower.hasPrefix("gpt-4.1") {
            score = 4100
        } else if lower.hasPrefix("gpt-4o") {
            score = 4050
        }
        if lower.contains("-nano") { score -= 20 }
        else if lower.contains("-mini") { score -= 10 }
        return score
    }

    private func fetchOpenAIModels(apiKey: String) async throws -> [DiscoveredModel] {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["data"] as? [[String: Any]] ?? []

        return models
            .compactMap { $0["id"] as? String }
            .filter { isOpenAIVisionCapable($0) }
            .sorted { openAIScore($0) > openAIScore($1) }
            .map { DiscoveredModel(id: $0, displayName: $0) }
    }

    // MARK: - Anthropic

    func isAnthropicVisionCapable(_ modelId: String) -> Bool {
        let lower = modelId.lowercased()
        guard lower.hasPrefix("claude-") else { return false }
        return !hasDateSnapshot(lower)
    }

    func anthropicScore(_ modelId: String) -> Int {
        let lower = modelId.lowercased()
        var score = 0

        // Version: "claude-sonnet-4-5" → 4.5 * 1000
        if let match = lower.range(of: "claude-\\w+-(\\d+)-(\\d+)", options: .regularExpression) {
            let segment = String(lower[match])
            let parts = segment.split(separator: "-")
            if parts.count >= 4, let major = Int(parts[2]), let minor = Int(parts[3]) {
                score += (major * 10 + minor) * 100
            }
        }

        if lower.contains("sonnet") { score += 300 }
        else if lower.contains("opus") { score += 200 }
        else if lower.contains("haiku") { score += 100 }

        return score
    }

    private func fetchAnthropicModels(apiKey: String) async throws -> [DiscoveredModel] {
        let url = URL(string: "https://api.anthropic.com/v1/models?limit=1000")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["data"] as? [[String: Any]] ?? []

        return models
            .compactMap { dict -> (String, String)? in
                guard let id = dict["id"] as? String else { return nil }
                let display = dict["display_name"] as? String ?? id
                return (id, display)
            }
            .filter { isAnthropicVisionCapable($0.0) }
            .sorted { anthropicScore($0.0) > anthropicScore($1.0) }
            .map { DiscoveredModel(id: $0.0, displayName: $0.1) }
    }

    // MARK: - Gemini

    private let geminiExcluded = ["embedding", "aqa", "text", "tuning"]

    func isGeminiVisionCapable(_ modelId: String) -> Bool {
        let lower = modelId.lowercased()
        guard lower.contains("gemini") else { return false }
        if geminiExcluded.contains(where: { lower.contains($0) }) { return false }
        return !hasDateSnapshot(lower)
    }

    func geminiScore(_ modelId: String) -> Int {
        let lower = modelId.lowercased()
        var score = 0

        if let match = lower.range(of: "gemini-(\\d+)\\.(\\d+)", options: .regularExpression) {
            let segment = String(lower[match])
            let parts = segment.split(separator: "-")[1].split(separator: ".")
            if parts.count >= 2, let major = Int(parts[0]), let minor = Int(parts[1]) {
                score += (major * 10 + minor) * 100
            }
        }

        if lower.contains("pro") { score += 50 }
        else if lower.contains("flash") { score += 30 }

        return score
    }

    private func fetchGeminiModels(apiKey: String) async throws -> [DiscoveredModel] {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["models"] as? [[String: Any]] ?? []

        return models
            .compactMap { dict -> (String, String)? in
                guard let name = dict["name"] as? String else { return nil }
                let id = name.replacingOccurrences(of: "models/", with: "")
                let display = dict["displayName"] as? String ?? id
                return (id, display)
            }
            .filter { isGeminiVisionCapable($0.0) }
            .sorted { geminiScore($0.0) > geminiScore($1.0) }
            .map { DiscoveredModel(id: $0.0, displayName: $0.1) }
    }

    // MARK: - OpenRouter

    private func fetchOpenRouterModels(apiKey: String) async throws -> [DiscoveredModel] {
        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        return try Self.parseOpenRouterModels(from: data)
    }

    static func parseOpenRouterModels(from data: Data) throws -> [DiscoveredModel] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["data"] as? [[String: Any]] ?? []

        return models
            .compactMap { dict -> DiscoveredModel? in
                guard let id = dict["id"] as? String else { return nil }
                let arch = dict["architecture"] as? [String: Any]
                let modalities = arch?["input_modalities"] as? [String] ?? []
                guard modalities.contains("image") else { return nil }
                let display = dict["name"] as? String ?? id
                let parameters = dict["supported_parameters"] as? [String] ?? []
                return DiscoveredModel(
                    id: id,
                    displayName: display,
                    supportsStructuredOutputs: parameters.contains("structured_outputs")
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Helpers

    func hasDateSnapshot(_ lowercased: String) -> Bool {
        let range = NSRange(lowercased.startIndex..., in: lowercased)
        return dateSnapshotRegex.firstMatch(in: lowercased, range: range) != nil
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DiscoveryError.apiError(body)
        }
    }

    enum DiscoveryError: LocalizedError {
        case noAPIKey
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key configured"
            case .apiError(let msg):
                let detail = AIAnalysisService.providerErrorMessage(from: msg) ?? "Unknown error"
                return "API error: \(detail)"
            }
        }
    }
}
