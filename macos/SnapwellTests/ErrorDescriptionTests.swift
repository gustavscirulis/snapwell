import Testing
import Foundation
@testable import Snapwell

@Suite("Error Descriptions")
struct ErrorDescriptionTests {

    // MARK: - AIAnalysisService.AnalysisError

    @Test("AnalysisError.noAPIKey has description")
    func analysisNoAPIKey() {
        let error = AIAnalysisService.AnalysisError.noAPIKey
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("AnalysisError.imageConversionFailed has description")
    func analysisImageConversion() {
        let error = AIAnalysisService.AnalysisError.imageConversionFailed
        #expect(error.errorDescription != nil)
    }

    @Test("AnalysisError.invalidResponse has description")
    func analysisInvalidResponse() {
        let error = AIAnalysisService.AnalysisError.invalidResponse
        #expect(error.errorDescription != nil)
    }

    @Test("AnalysisError 429 shows generic rate limit message")
    func analysisApiError429() {
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: 429, message: "Rate limited", provider: .openai)
        let desc = error.errorDescription!
        #expect(desc.contains("Rate limit exceeded"))
        #expect(!desc.contains("Flash"))
    }

    @Test("AnalysisError 429 from Gemini suggests Flash model")
    func analysisApiError429Gemini() {
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: 429, message: "Rate limited", provider: .gemini)
        let desc = error.errorDescription!
        #expect(desc.contains("Flash"))
    }

    @Test("AnalysisError 400 surfaces the provider's explanation")
    func analysisApiError400IncludesDetail() throws {
        let body = #"{"error":{"message":"image dimensions exceed max allowed size"}}"#
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: 400, message: body, provider: .anthropic)
        let desc = try #require(error.errorDescription)
        #expect(desc.contains("HTTP 400"))
        #expect(desc.contains("image dimensions exceed max allowed size"))
    }

    @Test("AnalysisError 400 with an empty body falls back to generic copy")
    func analysisApiError400EmptyBody() throws {
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: 400, message: "", provider: .anthropic)
        let desc = try #require(error.errorDescription)
        #expect(desc == "API request failed with HTTP 400. Check your provider settings.")
    }

    @Test("AnalysisError auth failures keep tailored copy and do not leak the body",
          arguments: [401, 403])
    func analysisApiErrorAuthDoesNotLeakBody(_ code: Int) throws {
        let body = #"{"error":{"message":"x-api-key header LEAKED-KEY-FIXTURE is invalid"}}"#
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: code, message: body, provider: .anthropic)
        let desc = try #require(error.errorDescription)
        #expect(!desc.contains("LEAKED-KEY-FIXTURE"))
        #expect(desc.contains("Check your key in Settings"))
    }

    @Test("AnalysisError 5xx appends the provider's explanation")
    func analysisApiError500IncludesDetail() throws {
        let body = #"{"error":{"message":"upstream connect error"}}"#
        let error = AIAnalysisService.AnalysisError.apiError(statusCode: 503, message: body, provider: .openrouter)
        let desc = try #require(error.errorDescription)
        #expect(desc.contains("HTTP 503"))
        #expect(desc.contains("upstream connect error"))
    }

    @Test("AnalysisError.parseFailed has description")
    func analysisParseFailed() {
        let error = AIAnalysisService.AnalysisError.parseFailed
        #expect(error.errorDescription != nil)
    }

    // MARK: - KeySyncCrypto.KeySyncError

    @Test("KeySyncError.unsupportedVersion has description")
    func keySyncUnsupportedVersion() {
        let error = KeySyncCrypto.KeySyncError.unsupportedVersion
        #expect(error.errorDescription != nil)
    }

    @Test("KeySyncError.corruptedData has description")
    func keySyncCorruptedData() {
        let error = KeySyncCrypto.KeySyncError.corruptedData
        #expect(error.errorDescription != nil)
    }

    // MARK: - TwitterVideoService.TwitterError

    @Test("TwitterError cases all have descriptions",
          arguments: [
            TwitterVideoService.TwitterError.invalidURL,
            .noMediaInTweet,
            .apiRequestFailed(502),
            .malformedResponse
          ])
    func twitterErrors(_ error: TwitterVideoService.TwitterError) {
        #expect(error.errorDescription != nil)
        #expect(!error.errorDescription!.isEmpty)
    }

    @Test("TwitterError.apiRequestFailed includes status code")
    func twitterApiErrorCode() {
        let error = TwitterVideoService.TwitterError.apiRequestFailed(503)
        #expect(error.errorDescription!.contains("503"))
    }

    // MARK: - ModelDiscoveryService.DiscoveryError

    @Test("DiscoveryError.noAPIKey has description")
    func discoveryNoAPIKey() {
        let error = ModelDiscoveryService.DiscoveryError.noAPIKey
        #expect(error.errorDescription != nil)
    }

    @Test("DiscoveryError.apiError includes message")
    func discoveryApiError() {
        let error = ModelDiscoveryService.DiscoveryError.apiError("timeout")
        #expect(error.errorDescription!.contains("timeout"))
    }
}
