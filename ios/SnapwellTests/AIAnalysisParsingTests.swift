import Testing
import Foundation
@testable import Snapwell

@Suite("AI Response Parsing", .tags(.parsing))
struct AIAnalysisParsingTests {

    let service = AIAnalysisService.shared

    // MARK: - parseResponse

    @Test("Valid JSON produces correct AnalysisResult")
    func validJSON() throws {
        let json = """
        {
            "imageContext": "A screenshot of a login form",
            "imageSummary": "Login Form",
            "patterns": [
                {"name": "Text Field", "confidence": 0.95},
                {"name": "Submit Button", "confidence": 0.90}
            ]
        }
        """
        let result = try service.parseResponse(json, provider: "openai", model: "gpt-4o")
        #expect(result.imageContext == "A screenshot of a login form")
        #expect(result.imageSummary == "Login Form")
        #expect(result.patterns.count == 2)
        #expect(result.patterns[0].name == "Text Field")
        #expect(result.provider == "openai")
        #expect(result.model == "gpt-4o")
    }

    @Test("Markdown-fenced JSON is correctly stripped")
    func markdownFencedJSON() throws {
        let fenced = """
        ```json
        {
            "imageContext": "A photo",
            "imageSummary": "Photo",
            "patterns": [{"name": "Sky", "confidence": 0.9}]
        }
        ```
        """
        let result = try service.parseResponse(fenced, provider: "anthropic", model: "claude")
        #expect(result.imageSummary == "Photo")
        #expect(result.patterns.count == 1)
    }

    @Test("Patterns below 0.7 confidence are filtered out")
    func lowConfidenceFiltered() throws {
        let json = """
        {
            "imageContext": "Test",
            "imageSummary": "Test",
            "patterns": [
                {"name": "High", "confidence": 0.95},
                {"name": "Low", "confidence": 0.5},
                {"name": "Border", "confidence": 0.69},
                {"name": "Exact", "confidence": 0.7}
            ]
        }
        """
        let result = try service.parseResponse(json, provider: "openai", model: "gpt-4o")
        #expect(result.patterns.count == 2)
        let names = result.patterns.map(\.name)
        #expect(names.contains("High"))
        #expect(names.contains("Exact"))
        #expect(!names.contains("Low"))
        #expect(!names.contains("Border"))
    }

    @Test("Maximum 6 patterns are kept, sorted by confidence descending")
    func maxSixPatternsSorted() throws {
        let json = """
        {
            "imageContext": "Test",
            "imageSummary": "Test",
            "patterns": [
                {"name": "P1", "confidence": 0.81},
                {"name": "P2", "confidence": 0.82},
                {"name": "P3", "confidence": 0.83},
                {"name": "P4", "confidence": 0.84},
                {"name": "P5", "confidence": 0.85},
                {"name": "P6", "confidence": 0.86},
                {"name": "P7", "confidence": 0.87},
                {"name": "P8", "confidence": 0.88},
                {"name": "P9", "confidence": 0.89},
                {"name": "P10", "confidence": 0.90}
            ]
        }
        """
        let result = try service.parseResponse(json, provider: "openai", model: "gpt-4o")
        #expect(result.patterns.count == 6)
        for i in 0..<(result.patterns.count - 1) {
            #expect(result.patterns[i].confidence >= result.patterns[i + 1].confidence)
        }
        #expect(result.patterns[0].name == "P10")
        #expect(result.patterns[5].name == "P5")
    }

    @Test("Invalid JSON throws a decoding error")
    func invalidJSONThrows() {
        #expect(throws: (any Error).self) {
            try service.parseResponse("not json {{{", provider: "openai", model: "gpt-4o")
        }
    }

    @Test("Provider is correctly set in result",
          arguments: ["openai", "anthropic", "gemini", "openrouter"])
    func parseResponseSetsProvider(_ provider: String) throws {
        let json = """
        {
            "imageContext": "Test",
            "imageSummary": "Test",
            "patterns": [{"name": "Item", "confidence": 0.9}]
        }
        """
        let result = try service.parseResponse(json, provider: provider, model: "test-model")
        #expect(result.provider == provider)
        #expect(result.model == "test-model")
    }

    // MARK: - buildPrompt

    @Test("Build prompt includes custom guidance")
    func buildPromptIncludesGuidance() {
        let prompt = service.buildPrompt(guidance: "Focus on typography")
        #expect(prompt.contains("Focus on typography"))
        #expect(!prompt.contains(AIAnalysisService.defaultGuidance))
    }

    @Test("Build prompt falls back to default guidance when nil")
    func buildPromptFallsBackToDefault() {
        let prompt = service.buildPrompt()
        #expect(prompt.contains(AIAnalysisService.defaultGuidance))
    }

    @Test("Build prompt falls back to default guidance when empty")
    func buildPromptFallsBackWhenEmpty() {
        let prompt = service.buildPrompt(guidance: "")
        #expect(prompt.contains(AIAnalysisService.defaultGuidance))
    }

    @Test("Build prompt appends space context")
    func buildPromptAppendsSpaceContext() {
        let prompt = service.buildPrompt(guidance: "test", spaceContext: "This is a UI collection")
        #expect(prompt.contains("This is a UI collection"))
    }

    // MARK: - isRetryable

    @Test("Retryable HTTP status codes",
          arguments: [429, 502, 503])
    func retryableStatusCodes(_ code: Int) {
        // provider is arbitrary — retryability depends only on status code
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: code, message: "error", provider: .openai)
        #expect(service.isRetryable(error) == true)
    }

    @Test("Non-retryable HTTP status codes",
          arguments: [400, 401, 403, 404, 500])
    func nonRetryableStatusCodes(_ code: Int) {
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: code, message: "error", provider: .openai)
        #expect(service.isRetryable(error) == false)
    }

    @Test("Recommended-model fallback accepts model rejection statuses", arguments: [400, 404])
    func recommendedModelFallbackStatuses(_ code: Int) {
        let error = AIAnalysisService.AnalysisError.apiError(
            statusCode: code,
            message: "error",
            provider: .openai
        )
        #expect(AnalysisCoordinator.indicatesUnusableModel(error))
    }

    @Test("Recommended-model fallback excludes auth, quota, rate-limit, and server statuses",
          arguments: [401, 403, 429, 500])
    func recommendedModelFallbackExcludedStatuses(_ code: Int) {
        let error = AIAnalysisService.AnalysisError.apiError(
            statusCode: code,
            message: "error",
            provider: .openai
        )
        #expect(!AnalysisCoordinator.indicatesUnusableModel(error))
    }

    @Test("Non-API failures do not trigger a model substitution")
    func recommendedModelFallbackIgnoresParsingFailures() {
        #expect(AnalysisCoordinator.indicatesUnusableModel(.invalidResponse) == false)
        #expect(AnalysisCoordinator.indicatesUnusableModel(.parseFailed) == false)
        #expect(AnalysisCoordinator.indicatesUnusableModel(.imageConversionFailed) == false)
    }

    // MARK: - AIProvider enum properties

    @Test("All providers have non-empty displayName",
          arguments: AIProvider.allCases)
    func providerDisplayName(_ provider: AIProvider) {
        #expect(!provider.displayName.isEmpty)
    }

    @Test("All providers have non-empty defaultModel",
          arguments: AIProvider.allCases)
    func providerDefaultModel(_ provider: AIProvider) {
        #expect(!provider.defaultModel.isEmpty)
    }

    @Test("Provider count is 4")
    func providerCount() {
        #expect(AIProvider.allCases.count == 4)
    }

    // MARK: - providerErrorMessage

    @Test("Extracts nested error.message (Anthropic / OpenAI / OpenRouter shape)")
    func providerErrorNestedMessage() {
        let body = #"{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens must be greater than thinking.budget_tokens"}}"#
        #expect(AIAnalysisService.providerErrorMessage(from: body) == "max_tokens must be greater than thinking.budget_tokens")
    }

    @Test("Extracts top-level message (Gemini shape)")
    func providerErrorTopLevelMessage() {
        let body = #"{"message":"API key not valid","status":"INVALID_ARGUMENT"}"#
        #expect(AIAnalysisService.providerErrorMessage(from: body) == "API key not valid")
    }

    @Test("Non-JSON body passes through trimmed")
    func providerErrorNonJSON() {
        #expect(AIAnalysisService.providerErrorMessage(from: "  Bad Gateway\n") == "Bad Gateway")
    }

    @Test("Empty and whitespace-only bodies produce nil")
    func providerErrorEmpty() {
        #expect(AIAnalysisService.providerErrorMessage(from: "") == nil)
        #expect(AIAnalysisService.providerErrorMessage(from: "   \n ") == nil)
    }

    @Test("Oversized body is truncated")
    func providerErrorTruncation() throws {
        let long = String(repeating: "x", count: 500)
        let result = try #require(AIAnalysisService.providerErrorMessage(from: long))
        #expect(result.count == 301)
        #expect(result.hasSuffix("…"))
    }

    // MARK: - apiError description

    @Test("400 surfaces the provider's explanation")
    func apiError400IncludesDetail() throws {
        let body = #"{"error":{"message":"image dimensions exceed max allowed size"}}"#
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: 400, message: body, provider: .anthropic)
        let description = try #require(error.errorDescription)
        #expect(description.contains("HTTP 400"))
        #expect(description.contains("image dimensions exceed max allowed size"))
    }

    @Test("400 with an empty body falls back to generic copy")
    func apiError400EmptyBody() throws {
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: 400, message: "", provider: .anthropic)
        let description = try #require(error.errorDescription)
        #expect(description == "API request failed with HTTP 400. Check your provider settings.")
    }

    @Test("Auth failures keep tailored copy and do not leak the body")
    func apiErrorAuthDoesNotLeakBody() throws {
        let body = #"{"error":{"message":"x-api-key header LEAKED-KEY-FIXTURE is invalid"}}"#
        for code in [401, 403] {
            let error = AIAnalysisService.AnalysisError.apiError(statusCode: code, message: body, provider: .anthropic)
            let description = try #require(error.errorDescription)
            #expect(!description.contains("LEAKED-KEY-FIXTURE"))
            #expect(description.contains("Check your key in Settings"))
        }
    }

    @Test("Rate limit keeps tailored per-provider copy")
    func apiErrorRateLimitUnchanged() throws {
        let body = #"{"error":{"message":"quota exceeded"}}"#
        let gemini = AIAnalysisService.AnalysisError.apiError(statusCode: 429, message: body, provider: .gemini)
        #expect(try #require(gemini.errorDescription).contains("free tier"))

        let openai = AIAnalysisService.AnalysisError.apiError(statusCode: 429, message: body, provider: .openai)
        #expect(try #require(openai.errorDescription).contains("Wait a moment"))
    }

    @Test("5xx appends the provider's explanation to the generic advice")
    func apiError500IncludesDetail() throws {
        let body = #"{"error":{"message":"upstream connect error"}}"#
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: 503, message: body, provider: .openrouter)
        let description = try #require(error.errorDescription)
        #expect(description.contains("HTTP 503"))
        #expect(description.contains("upstream connect error"))
    }

    // MARK: - extractAnthropicText

    @Test("Skips a leading thinking block to find the text block")
    func anthropicTextSkipsThinking() throws {
        let json: [String: Any] = ["content": [
            ["type": "thinking", "thinking": "considering the image..."],
            ["type": "text", "text": "{\"imageSummary\":\"Login Form\"}"]
        ]]
        #expect(try AIAnalysisService.extractAnthropicText(json) == "{\"imageSummary\":\"Login Form\"}")
    }

    @Test("Reads a lone text block")
    func anthropicTextSingleBlock() throws {
        let json: [String: Any] = ["content": [["type": "text", "text": "hello"]]]
        #expect(try AIAnalysisService.extractAnthropicText(json) == "hello")
    }

    @Test("Throws when no text block is present (thinking-only truncation)")
    func anthropicTextThinkingOnly() {
        let json: [String: Any] = ["content": [["type": "thinking", "thinking": "truncated"]]]
        #expect(throws: AIAnalysisService.AnalysisError.self) {
            try AIAnalysisService.extractAnthropicText(json)
        }
    }

    @Test("Throws on empty content array and blank text")
    func anthropicTextEmpty() {
        #expect(throws: AIAnalysisService.AnalysisError.self) {
            try AIAnalysisService.extractAnthropicText(["content": []])
        }
        #expect(throws: AIAnalysisService.AnalysisError.self) {
            try AIAnalysisService.extractAnthropicText(["content": [["type": "text", "text": "  \n "]]])
        }
    }
}
