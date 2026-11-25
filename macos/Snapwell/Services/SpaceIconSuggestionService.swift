import Foundation
#if SNAPWELL_FOUNDATION_MODELS_VISION
import FoundationModels
#endif

struct SpaceIconCandidate: Codable, Hashable, Sendable {
    let id: String
    let title: String
}

protocol SpaceIconSuggesting: Sendable {
    func suggestSymbols(for candidates: [SpaceIconCandidate]) async throws -> [String: String]
}

final class SpaceIconSuggestionService: SpaceIconSuggesting, Sendable {
    static let shared = SpaceIconSuggestionService()

    private let session: URLSession
    private let ollamaClient: OllamaClient
    private let appleIntelligenceGenerator: any AppleIntelligenceSpaceIconGenerating

    init(
        session: URLSession = .shared,
        ollamaClient: OllamaClient = .shared,
        appleIntelligenceGenerator: any AppleIntelligenceSpaceIconGenerating = SystemAppleIntelligenceSpaceIconGenerator()
    ) {
        self.session = session
        self.ollamaClient = ollamaClient
        self.appleIntelligenceGenerator = appleIntelligenceGenerator
    }

    func suggestSymbols(for candidates: [SpaceIconCandidate]) async throws -> [String: String] {
        guard !candidates.isEmpty else { return [:] }
        #if SNAPWELL_AUTOMATION
        if AutomationEnvironment.usesFixtureProviders {
            return Dictionary(uniqueKeysWithValues: candidates.map {
                ($0.id, SpaceSymbolCatalog.fallbackSymbol(for: $0.title))
            })
        }
        #endif

        let provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "openai") ?? .openai
        let storedModel = UserDefaults.standard.string(forKey: "\(provider.rawValue)Model")
            ?? ModelDiscoveryService.autoModelValue
        let model: String
        if provider == .appleIntelligence {
            model = provider.defaultModel
        } else if storedModel == ModelDiscoveryService.autoModelValue {
            model = await ModelDiscoveryService.shared.resolveAutoModel(for: provider)
        } else {
            model = storedModel
        }

        let systemPrompt = Self.systemPrompt
        let userPrompt = try Self.userPrompt(for: candidates)
        let responseText: String

        switch provider {
        case .appleIntelligence:
            responseText = try await appleIntelligenceGenerator.generate(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
        case .ollama:
            responseText = try await ollamaClient.generateStructured(
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                schema: Self.responseSchema
            )
        case .openai, .anthropic, .gemini, .openrouter:
            guard let apiKey = try KeychainService.get(service: provider.keychainService) else {
                throw SuggestionError.noAIConfiguration
            }
            let request = try Self.request(
                provider: provider,
                model: model,
                apiKey: apiKey,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SuggestionError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                throw SuggestionError.httpError(http.statusCode)
            }
            responseText = try Self.extractText(from: data, provider: provider)
        }

        return try Self.parse(responseText, candidates: candidates)
    }

    static func parse(_ text: String, candidates: [SpaceIconCandidate]) throws -> [String: String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if trimmed.hasPrefix("```") {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            json = lines.dropFirst().dropLast().joined(separator: "\n")
                .replacingOccurrences(of: "^json\\s*", with: "", options: .regularExpression)
        } else {
            json = trimmed
        }
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(SuggestionResponse.self, from: data) else {
            throw SuggestionError.invalidResponse
        }
        let candidateIDs = Set(candidates.map(\.id))
        var result: [String: String] = [:]
        for suggestion in response.suggestions
        where candidateIDs.contains(suggestion.id) && SpaceSymbolCatalog.names.contains(suggestion.symbolName) {
            result[suggestion.id] = suggestion.symbolName
        }
        guard !result.isEmpty else { throw SuggestionError.invalidResponse }
        return result
    }

    private static let systemPrompt = """
    Choose one semantically appropriate SF Symbol for each named visual collection. Return JSON only.
    Use only a symbol name from this allowlist:
    \(SpaceSymbolCatalog.symbols.map(\.name).joined(separator: ", "))
    """

    private static func userPrompt(for candidates: [SpaceIconCandidate]) throws -> String {
        let data = try JSONEncoder().encode(candidates)
        guard let json = String(data: data, encoding: .utf8) else { throw SuggestionError.invalidResponse }
        return "Choose a symbol for every entry. Preserve each id exactly. Entries: \(json)"
    }

    private static var responseSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "suggestions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "id": ["type": "string"],
                            "symbolName": ["type": "string", "enum": SpaceSymbolCatalog.symbols.map(\.name)]
                        ],
                        "required": ["id", "symbolName"]
                    ]
                ]
            ],
            "required": ["suggestions"]
        ]
    }

    private static func request(
        provider: AIProvider,
        model: String,
        apiKey: String,
        systemPrompt: String,
        userPrompt: String
    ) throws -> URLRequest {
        let url: URL
        var headers = ["Content-Type": "application/json"]
        let body: [String: Any]
        switch provider {
        case .openai:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
            headers["Authorization"] = "Bearer \(apiKey)"
            body = openAICompatibleBody(model: model, systemPrompt: systemPrompt, userPrompt: userPrompt)
        case .openrouter:
            url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            headers["Authorization"] = "Bearer \(apiKey)"
            headers["HTTP-Referer"] = "https://snapwell.co"
            headers["X-Title"] = "Snapwell"
            var routed = openAICompatibleBody(model: model, systemPrompt: systemPrompt, userPrompt: userPrompt)
            routed.removeValue(forKey: "max_completion_tokens")
            routed["max_tokens"] = 1200
            routed["provider"] = ["require_parameters": true]
            body = routed
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
            body = [
                "model": model,
                "max_tokens": 1200,
                "system": systemPrompt,
                "messages": [["role": "user", "content": userPrompt]]
            ]
        case .gemini:
            guard let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let geminiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")
            else { throw SuggestionError.invalidResponse }
            url = geminiURL
            headers["x-goog-api-key"] = apiKey
            body = [
                "contents": [["parts": [["text": userPrompt]]]],
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "generationConfig": [
                    "temperature": 0,
                    "maxOutputTokens": 1200,
                    "responseMimeType": "application/json",
                    "responseSchema": responseSchema
                ]
            ]
        case .ollama, .appleIntelligence:
            throw SuggestionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func openAICompatibleBody(
        model: String,
        systemPrompt: String,
        userPrompt: String
    ) -> [String: Any] {
        [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_completion_tokens": 1200,
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "snapwell_space_icons",
                    "strict": true,
                    "schema": responseSchema
                ]
            ]
        ]
    }

    private static func extractText(from data: Data, provider: AIProvider) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SuggestionError.invalidResponse
        }
        let text: String?
        switch provider {
        case .openai, .openrouter:
            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
        case .anthropic:
            let content = json["content"] as? [[String: Any]]
            text = content?.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        case .gemini:
            let candidates = json["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            text = parts?.first?["text"] as? String
        case .ollama, .appleIntelligence:
            text = nil
        }
        guard let text, !text.isEmpty else { throw SuggestionError.invalidResponse }
        return text
    }

    private struct SuggestionResponse: Codable {
        let suggestions: [Suggestion]
    }

    private struct Suggestion: Codable {
        let id: String
        let symbolName: String
    }

    enum SuggestionError: Error, Equatable {
        case noAIConfiguration
        case invalidResponse
        case httpError(Int)
    }
}

protocol AppleIntelligenceSpaceIconGenerating: Sendable {
    func generate(systemPrompt: String, userPrompt: String) async throws -> String
}

struct SystemAppleIntelligenceSpaceIconGenerator: AppleIntelligenceSpaceIconGenerating {
    func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        #if SNAPWELL_FOUNDATION_MODELS_VISION
        if #available(macOS 27.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw SpaceIconSuggestionService.SuggestionError.noAIConfiguration
            }
            let session = LanguageModelSession(model: model, instructions: Instructions(systemPrompt))
            let response = try await session.respond(
                generating: AppleIntelligenceSpaceIconResponse.self,
                options: GenerationOptions(samplingMode: .greedy)
            ) {
                userPrompt
            }
            let value = response.content.suggestions.map {
                ["id": $0.id, "symbolName": $0.symbolName]
            }
            let data = try JSONSerialization.data(withJSONObject: ["suggestions": value])
            guard let text = String(data: data, encoding: .utf8) else {
                throw SpaceIconSuggestionService.SuggestionError.invalidResponse
            }
            return text
        }
        #endif
        throw SpaceIconSuggestionService.SuggestionError.noAIConfiguration
    }
}

#if SNAPWELL_FOUNDATION_MODELS_VISION
@available(macOS 27.0, *)
@Generable
private struct AppleIntelligenceSpaceIconChoice {
    @Guide(description: "The input collection id copied exactly")
    var id: String

    @Guide(description: "An SF Symbol name from the provided allowlist")
    var symbolName: String
}

@available(macOS 27.0, *)
@Generable
private struct AppleIntelligenceSpaceIconResponse {
    @Guide(description: "One icon choice for every input collection")
    var suggestions: [AppleIntelligenceSpaceIconChoice]
}
#endif
