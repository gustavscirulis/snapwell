import Testing
import Foundation
@testable import Snapwell

@Suite("ModelDiscovery Scoring", .tags(.parsing))
struct ModelDiscoveryScoringTests {

    let service = ModelDiscoveryService.shared

    // MARK: - OpenAI Vision Capability

    @Test("GPT-4o is vision capable")
    func gpt4oVisionCapable() {
        #expect(service.isOpenAIVisionCapable("gpt-4o") == true)
    }

    @Test("GPT-4o-mini is vision capable")
    func gpt4oMiniVisionCapable() {
        #expect(service.isOpenAIVisionCapable("gpt-4o-mini") == true)
    }

    @Test("GPT-4.1 is vision capable")
    func gpt41VisionCapable() {
        #expect(service.isOpenAIVisionCapable("gpt-4.1") == true)
    }

    @Test("Embedding models are excluded")
    func embeddingExcluded() {
        #expect(service.isOpenAIVisionCapable("text-embedding-ada") == false)
    }

    @Test("Whisper models are excluded")
    func whisperExcluded() {
        #expect(service.isOpenAIVisionCapable("whisper-1") == false)
    }

    @Test("DALL-E models are excluded")
    func dalleExcluded() {
        #expect(service.isOpenAIVisionCapable("dall-e-3") == false)
    }

    @Test("Date snapshot models are excluded",
          arguments: ["gpt-4o-2024-01-01", "gpt-4o-20240101"])
    func dateSnapshotExcluded(_ modelId: String) {
        #expect(service.isOpenAIVisionCapable(modelId) == false)
    }

    // MARK: - OpenAI Scoring

    @Test("GPT-5 scores higher than GPT-4o")
    func gpt5ScoresHigher() {
        #expect(service.openAIScore("gpt-5") > service.openAIScore("gpt-4o"))
    }

    @Test("GPT-4.1 scores higher than GPT-4o")
    func gpt41ScoresHigher() {
        #expect(service.openAIScore("gpt-4.1") > service.openAIScore("gpt-4o"))
    }

    @Test("Mini variant scores lower than base")
    func miniScoresLower() {
        #expect(service.openAIScore("gpt-4o-mini") < service.openAIScore("gpt-4o"))
    }

    // MARK: - Anthropic

    @Test("Claude models are vision capable")
    func claudeVisionCapable() {
        #expect(service.isAnthropicVisionCapable("claude-sonnet-4-5") == true)
        #expect(service.isAnthropicVisionCapable("claude-haiku-3-5") == true)
    }

    @Test("Non-claude models are not vision capable")
    func nonClaudeNotCapable() {
        #expect(service.isAnthropicVisionCapable("some-other-model") == false)
    }

    @Test("Anthropic date snapshots excluded")
    func anthropicDateExcluded() {
        #expect(service.isAnthropicVisionCapable("claude-sonnet-4-5-20250514") == false)
    }

    @Test("Sonnet scores higher than Haiku for same version")
    func sonnetOverHaiku() {
        #expect(service.anthropicScore("claude-sonnet-4-5") > service.anthropicScore("claude-haiku-4-5"))
    }

    // MARK: - Gemini

    @Test("Gemini models are vision capable")
    func geminiVisionCapable() {
        #expect(service.isGeminiVisionCapable("gemini-2.0-flash") == true)
    }

    @Test("Gemini embedding models excluded")
    func geminiEmbeddingExcluded() {
        #expect(service.isGeminiVisionCapable("gemini-embedding-001") == false)
    }

    @Test("Gemini pro scores higher than flash")
    func geminiProOverFlash() {
        #expect(service.geminiScore("gemini-2.0-pro") > service.geminiScore("gemini-2.0-flash"))
    }

    @Test("Higher Gemini version scores higher")
    func geminiVersionScoring() {
        #expect(service.geminiScore("gemini-2.5-flash") > service.geminiScore("gemini-2.0-flash"))
    }

    // MARK: - Date Snapshot Detection

    @Test("Detects date with dashes",
          arguments: ["gpt-4o-2024-01-01", "claude-3-2023-06-15"])
    func dateWithDashes(_ input: String) {
        #expect(service.hasDateSnapshot(input) == true)
    }

    @Test("Detects date without dashes")
    func dateWithoutDashes() {
        #expect(service.hasDateSnapshot("gpt-4o-20240101") == true)
    }

    @Test("No date detected in clean model names",
          arguments: ["gpt-4o", "claude-sonnet-4-5", "gemini-2.0-flash"])
    func noDateDetected(_ input: String) {
        #expect(service.hasDateSnapshot(input) == false)
    }

    // MARK: - Preferred Model Selection

    private func models(_ ids: [String]) -> [DiscoveredModel] {
        ids.map { DiscoveredModel(id: $0, displayName: $0) }
    }

    @Test("Prefers the earliest listed family over a newer unlisted one")
    func preferredFamilyOrdering() {
        let live = models(["gpt-5.5", "gpt-5.6-luna", "gpt-4o"])
        #expect(service.preferredModel(from: live, for: .openai)?.id == "gpt-5.6-luna")
    }

    @Test("Prefers the base model over -pro and other suffixed variants")
    func preferredShortestWins() {
        let live = models(["gpt-5.6-luna-pro", "gpt-5.6-luna"])
        #expect(service.preferredModel(from: live, for: .openai)?.id == "gpt-5.6-luna")

        let gemini = models(["gemini-3-pro-image", "gemini-3-pro"])
        #expect(service.preferredModel(from: gemini, for: .gemini)?.id == "gemini-3-pro")
    }

    @Test("Falls back through the preference list when top families are absent")
    func preferredFallsThroughList() {
        let live = models(["gpt-4o", "gpt-4.1"])
        #expect(service.preferredModel(from: live, for: .openai)?.id == "gpt-4.1")
    }

    @Test("Returns nil when nothing in the live list is recognised")
    func preferredNoMatch() {
        #expect(service.preferredModel(from: models(["mystery-model-9"]), for: .openai) == nil)
    }

    @Test("Does not pick a chat alias over a real model")
    func preferredSkipsChatAlias() {
        let live = models(["gpt-5-chat-latest", "gpt-5.6-luna"])
        #expect(service.preferredModel(from: live, for: .openai)?.id == "gpt-5.6-luna")
    }

    @Test("Anthropic and OpenRouter preferences resolve")
    func preferredOtherProviders() {
        let anthropic = models(["claude-haiku-4-5", "claude-sonnet-5"])
        #expect(service.preferredModel(from: anthropic, for: .anthropic)?.id == "claude-sonnet-5")

        let openrouter = models(["openai/gpt-5.6-luna", "google/gemini-3.5-flash"])
        #expect(service.preferredModel(from: openrouter, for: .openrouter)?.id == "google/gemini-3.5-flash")
    }

    @Test("OpenRouter preference skips models without structured outputs")
    func openRouterPreferenceRequiresStructuredOutputs() {
        let models = [
            DiscoveredModel(
                id: "google/gemini-3.5-flash",
                displayName: "Gemini 3.5 Flash",
                supportsStructuredOutputs: false
            ),
            DiscoveredModel(
                id: "openai/gpt-5.6-luna",
                displayName: "GPT-5.6 Luna",
                supportsStructuredOutputs: true
            )
        ]

        #expect(service.preferredModel(from: models, for: .openrouter)?.id == "openai/gpt-5.6-luna")
    }

    @Test("OpenRouter discovery keeps vision models and records structured-output support")
    func openRouterCapabilityParsing() throws {
        let payload: [String: Any] = ["data": [
            [
                "id": "supported/model",
                "name": "Supported",
                "architecture": ["input_modalities": ["text", "image"]],
                "supported_parameters": ["max_tokens", "structured_outputs"]
            ],
            [
                "id": "unsupported/model",
                "name": "Unsupported",
                "architecture": ["input_modalities": ["image"]],
                "supported_parameters": ["max_tokens"]
            ],
            [
                "id": "text/model",
                "name": "Text Only",
                "architecture": ["input_modalities": ["text"]],
                "supported_parameters": ["structured_outputs"]
            ]
        ]]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let models = try ModelDiscoveryService.parseOpenRouterModels(from: data)

        #expect(models.count == 2)
        #expect(models.first(where: { $0.id == "supported/model" })?.supportsStructuredOutputs == true)
        #expect(models.first(where: { $0.id == "unsupported/model" })?.supportsStructuredOutputs == false)
        #expect(!models.contains(where: { $0.id == "text/model" }))
    }

    @Test("Every provider has a preference list and a discoverable default",
          arguments: AIProvider.allCases)
    func everyProviderHasPreferences(_ provider: AIProvider) throws {
        let prefixes = try #require(ModelDiscoveryService.preferredModelPrefixes[provider])
        #expect(!prefixes.isEmpty)
        // The last-resort default must itself be something the preference list would pick,
        // otherwise auto-resolution and the offline fallback disagree.
        #expect(prefixes.contains { provider.defaultModel.hasPrefix($0) })
    }
}
