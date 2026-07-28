import UIKit
import Foundation

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case openai
    case anthropic
    case gemini
    case openrouter

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic Claude"
        case .gemini: return "Google Gemini"
        case .openrouter: return "OpenRouter"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-5.6-luna"
        case .anthropic: return "claude-sonnet-5"
        case .gemini: return "gemini-3.5-flash"
        case .openrouter: return "google/gemini-3.5-flash"
        }
    }
}

final class AIAnalysisService: Sendable {
    static let shared = AIAnalysisService()

    private let systemPrompt = """
    You are an expert image analyst.

    <output_format>
    Return a JSON object with this structure:
    {
      "imageContext": "Detailed description of the image",
      "imageSummary": "1-2 word summary",
      "patterns": [
        {"name": "Element Name", "confidence": 0.95}
      ]
    }
    </output_format>

    <rules>
    - imageSummary: 1-2 words only
    - imageContext: detailed description of the entire image, its purpose and characteristics
    - Pattern names: 1-2 words, title case, not duplicating imageSummary
    - Up to 6 unique patterns, ordered by confidence (0.8–1.0)
    - Respond with valid JSON only — no markdown, code blocks, or explanations
    </rules>
    """

    static let defaultGuidance = """
    For UI screenshots, app interfaces, and websites:

    Name components with the term a designer would use in a spec — the \
    conventional name for that thing, whatever it is. Match the level of \
    specificity in "kebab menu" and "segmented control" rather than "menu" and \
    "buttons," but never force an observed element into a familiar label: if it \
    has a well-known name, use it; if it doesn't, name it in the most conventional \
    terms available. Novel and domain-specific components matter most, since \
    they're the hardest to find later.

    imageContext: open with what the product is and what this screen does, then \
    walk the layout region by region and name every distinct component visible, \
    including small ones. Close with visual style, colour treatment, typography, \
    and component states such as loading, empty, selected, disabled, or in \
    progress. This text is searched, so name things explicitly rather than \
    describing them loosely.

    patterns: pick the six most distinctive and searchable. Prefer layout \
    structures, screen archetypes, and unusual components over elements present in \
    nearly every interface — a tag that narrows a search beats one that doesn't.

    For general scenes: apply the same approach. imageContext names subjects, \
    objects, materials, colours, setting, lighting, and composition in detail; \
    patterns capture the six most distinctive of those.

    Use specific, concrete language. Describe only what is visible — never infer \
    off-screen content or product identity.
    """

    private let userText = "Analyze this image."

    private let maxRetries = 2

    func analyze(image: UIImage, provider: AIProvider, model: String, apiKey: String, guidance: String? = nil, spaceContext: String? = nil) async throws -> AnalysisResult {
        guard let base64 = imageToBase64(image) else {
            throw AnalysisError.imageConversionFailed
        }

        let prompt = buildPrompt(guidance: guidance, spaceContext: spaceContext)

        var lastError: Error?
        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = Double(attempt) * 2.0
                try? await Task.sleep(for: .seconds(delay))
                print("[Analysis] Retry attempt \(attempt)")
            }
            do {
                let req = buildProviderRequest(
                    provider: provider, apiKey: apiKey, model: model,
                    base64Image: base64, prompt: prompt
                )
                let responseText = try await sendProviderRequest(req)
                return try parseResponse(responseText, provider: provider.rawValue, model: model)
            } catch {
                lastError = error
                if !isRetryable(error) { throw error }
            }
        }
        throw lastError!
    }

    func analyzeVideo(frames: [UIImage], provider: AIProvider, model: String, apiKey: String, guidance: String? = nil, spaceContext: String? = nil) async throws -> AnalysisResult {
        // Analyze each frame and merge results
        var allPatterns: [String: [Double]] = [:]
        var contexts: [String] = []
        var summaries: [String] = []

        for frame in frames {
            let result = try await analyze(image: frame, provider: provider, model: model, apiKey: apiKey, guidance: guidance, spaceContext: spaceContext)
            contexts.append(result.imageContext)
            summaries.append(result.imageSummary)

            for pattern in result.patterns {
                allPatterns[pattern.name, default: []].append(pattern.confidence)
            }
        }

        return Self.mergeFrameResults(
            allPatterns: allPatterns,
            contexts: contexts,
            summaries: summaries,
            provider: provider.rawValue,
            model: model
        )
    }

    /// Merge analysis results from multiple video frames. Averages confidence per pattern,
    /// filters below 0.7, caps at 10, sorts descending.
    static func mergeFrameResults(
        allPatterns: [String: [Double]],
        contexts: [String],
        summaries: [String],
        provider: String,
        model: String
    ) -> AnalysisResult {
        let mergedPatterns = allPatterns.map { name, confidences in
            PatternTag(name: name, confidence: confidences.reduce(0, +) / Double(confidences.count))
        }
        .filter { $0.confidence >= 0.7 }
        .sorted { $0.confidence > $1.confidence }
        .prefix(10)

        return AnalysisResult(
            imageContext: contexts.joined(separator: "\n\n"),
            imageSummary: summaries.first ?? "Video",
            patterns: Array(mergedPatterns),
            provider: provider,
            model: model
        )
    }

    func isRetryable(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [-1001, -1005, -1009].contains(nsError.code)
        }
        if case AnalysisError.apiError(let code, _, _) = error {
            return [429, 502, 503].contains(code)
        }
        return false
    }

    // MARK: - Provider Request Infrastructure

    private struct ProviderRequest {
        let url: URL
        let headers: [String: String]
        let body: [String: Any]
        let provider: AIProvider
        let extractText: ([String: Any]) throws -> String
    }

    private func buildProviderRequest(
        provider: AIProvider, apiKey: String, model: String,
        base64Image: String, prompt: String
    ) -> ProviderRequest {
        switch provider {
        case .openai:
            return ProviderRequest(
                url: URL(string: "https://api.openai.com/v1/chat/completions")!,
                headers: ["Authorization": "Bearer \(apiKey)"],
                body: [
                    "model": model,
                    "messages": [
                        ["role": "system", "content": prompt],
                        ["role": "user", "content": [
                            ["type": "text", "text": userText],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                        ]]
                    ],
                    "max_completion_tokens": 800
                ],
                provider: provider,
                extractText: Self.extractOpenAIText
            )
        case .anthropic:
            return ProviderRequest(
                url: URL(string: "https://api.anthropic.com/v1/messages")!,
                headers: ["x-api-key": apiKey, "anthropic-version": "2023-06-01"],
                body: [
                    "model": model,
                    // Recent Claude models think by default and count thinking against
                    // max_tokens, so this must stay well above the 1024 thinking floor.
                    "max_tokens": 2000,
                    "system": prompt,
                    "messages": [
                        ["role": "user", "content": [
                            ["type": "image", "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]],
                            ["type": "text", "text": userText]
                        ]]
                    ]
                ],
                provider: provider,
                extractText: Self.extractAnthropicText
            )
        case .gemini:
            return ProviderRequest(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
                headers: ["x-goog-api-key": apiKey],
                body: [
                    "contents": [
                        ["parts": [
                            ["text": userText],
                            ["inlineData": ["mimeType": "image/jpeg", "data": base64Image]]
                        ]]
                    ],
                    "systemInstruction": ["parts": [["text": prompt]]],
                    "generationConfig": ["maxOutputTokens": 800]
                ],
                provider: provider,
                extractText: { json in
                    let candidates = json["candidates"] as? [[String: Any]]
                    let content = candidates?.first?["content"] as? [String: Any]
                    let parts = content?["parts"] as? [[String: Any]]
                    guard let text = parts?.first?["text"] as? String else {
                        throw AnalysisError.invalidResponse
                    }
                    return text
                }
            )
        case .openrouter:
            return ProviderRequest(
                url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                headers: [
                    "Authorization": "Bearer \(apiKey)",
                    "HTTP-Referer": "https://snapwell.co",
                    "X-Title": "Snapwell"
                ],
                body: [
                    "model": model,
                    "messages": [
                        ["role": "system", "content": prompt],
                        ["role": "user", "content": [
                            ["type": "text", "text": userText],
                            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                        ]]
                    ],
                    "max_tokens": 1200
                ],
                provider: provider,
                extractText: Self.extractOpenAIText
            )
        }
    }

    private static func extractOpenAIText(_ json: [String: Any]) throws -> String {
        let choices = json["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw AnalysisError.invalidResponse
        }
        return content
    }

    /// Pulls the human-readable reason out of a provider error body. The result is persisted
    /// to MediaItem.analysisError and written to sidecar JSON, so it is length-capped.
    static func providerErrorMessage(from body: String) -> String? {
        var extracted: String?

        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let msg = error["message"] as? String {
                extracted = msg
            } else if let msg = json["message"] as? String {
                extracted = msg
            }
        }

        let candidate = (extracted ?? body).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard candidate.count > 300 else { return candidate }
        return candidate.prefix(300).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Text extractor for the Anthropic Messages format. Scans for the first text block
    /// rather than taking content[0] — thinking-enabled models emit a thinking block first.
    static func extractAnthropicText(_ json: [String: Any]) throws -> String {
        let content = json["content"] as? [[String: Any]] ?? []
        guard let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnalysisError.invalidResponse
        }
        return text
    }

    private func sendProviderRequest(_ req: ProviderRequest) async throws -> String {
        var request = URLRequest(url: req.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in req.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: req.body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, provider: req.provider)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnalysisError.invalidResponse
        }
        return try req.extractText(json)
    }

    // MARK: - Helpers

    func buildPrompt(guidance: String? = nil, spaceContext: String? = nil) -> String {
        let effectiveGuidance = (guidance?.isEmpty == false ? guidance : nil) ?? Self.defaultGuidance
        var result = systemPrompt + "\n<analysis_focus>\n" + effectiveGuidance + "\n</analysis_focus>"
        if let spaceContext, !spaceContext.isEmpty {
            result += "\n\n" + spaceContext
        }
        return result
    }

    private let maxImageDimension: CGFloat = 1568

    private func imageToBase64(_ image: UIImage) -> String? {
        // Resize if needed
        let size = image.size
        let longest = max(size.width, size.height)
        let targetImage: UIImage
        if longest > maxImageDimension {
            let scale = maxImageDimension / longest
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            targetImage = image
        }

        guard let jpegData = targetImage.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data, provider: AIProvider) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AnalysisError.apiError(statusCode: httpResponse.statusCode, message: body, provider: provider)
        }
    }

    func parseResponse(_ text: String, provider: String, model: String) throws -> AnalysisResult {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw AnalysisError.parseFailed
        }

        struct AIResponse: Decodable {
            let imageContext: String
            let imageSummary: String
            let patterns: [PatternEntry]

            struct PatternEntry: Decodable {
                let name: String
                let confidence: Double
            }
        }

        let decoded = try JSONDecoder().decode(AIResponse.self, from: data)

        let patterns = decoded.patterns
            .filter { $0.confidence >= 0.7 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(6)
            .map { PatternTag(name: $0.name, confidence: $0.confidence) }

        return AnalysisResult(
            imageContext: decoded.imageContext,
            imageSummary: decoded.imageSummary,
            patterns: patterns,
            provider: provider,
            model: model
        )
    }

    enum AnalysisError: LocalizedError {
        case noAPIKey
        case imageConversionFailed
        case invalidResponse
        case apiError(statusCode: Int, message: String, provider: AIProvider)
        case parseFailed

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No API key configured"
            case .imageConversionFailed: return "Failed to convert image for analysis"
            case .invalidResponse: return "Invalid response from AI provider"
            case .apiError(let code, let message, let provider):
                let detail = AIAnalysisService.providerErrorMessage(from: message)
                switch code {
                case 401, 403: return "Your API key is invalid or unauthorized. Check your key in Settings."
                case 402: return "Insufficient credits. Check your account balance with your AI provider."
                case 429:
                    if provider == .gemini {
                        return "Rate limit exceeded. Gemini Flash models have a free tier — try switching to a Flash model in Settings."
                    }
                    return "Rate limit exceeded. Wait a moment and try again."
                case 500...599:
                    let base = "The AI provider is experiencing issues (HTTP \(code)). Try again later."
                    return detail.map { "\(base) \($0)" } ?? base
                default:
                    if let detail {
                        return "API request failed with HTTP \(code): \(detail)"
                    }
                    return "API request failed with HTTP \(code). Check your provider settings."
                }
            case .parseFailed: return "Failed to parse AI response"
            }
        }
    }
}
