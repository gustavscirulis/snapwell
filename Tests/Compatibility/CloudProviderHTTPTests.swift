import Foundation
import Testing
@testable import Snapwell

@Suite("Cloud provider HTTP", .timeLimit(.minutes(1)))
struct CloudProviderHTTPTests {
    private static let providers: [AIProvider] = [.openai, .anthropic, .gemini, .openrouter]
    private static let analysis = #"{"imageContext":"An orange screen","imageSummary":"Orange Screen","patterns":[{"name":"Toolbar","confidence":0.9}]}"#

    @Test("Each provider sends authenticated image content and decodes its response", arguments: providers)
    func successfulRequest(provider: AIProvider) async throws {
        let fixture = HTTPFixture(steps: [.response(200, Self.envelope(provider))])
        defer { fixture.close() }
        let result = try await analyze(fixture.service(), provider: provider)
        #expect(result.imageSummary == "Orange Screen")
        #expect(result.imageContext == "An orange screen")
        #expect(result.patterns == [PatternTag(name: "Toolbar", confidence: 0.9)])
        #expect(result.provider == provider.rawValue)
        #expect(result.model == "test-model")
        let request = try #require(fixture.requests.first)
        #expect(fixture.requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encoded = try #require(String(data: data, encoding: .utf8))
        #expect(encoded.contains("aW1hZ2U="))
        #expect(encoded.contains("Test guidance"))
        switch provider {
        case .openai, .openrouter:
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fake-test-key")
            #expect(body["model"] as? String == "test-model")
            let messages = try #require(body["messages"] as? [[String: Any]])
            #expect(messages.first?["content"] as? String == "Test guidance")
            let content = try #require(messages.last?["content"] as? [[String: Any]])
            let image = try #require(content.first(where: { $0["type"] as? String == "image_url" })?["image_url"] as? [String: Any])
            #expect(image["url"] as? String == "data:image/jpeg;base64,aW1hZ2U=")
            if provider == .openrouter {
                #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
                #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://snapwell.co")
                let format = try #require(body["response_format"] as? [String: Any])
                #expect(format["type"] as? String == "json_schema")
            } else {
                #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
            }
        case .anthropic:
            #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "fake-test-key")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            #expect(body["system"] as? String == "Test guidance")
            #expect(body["model"] as? String == "test-model")
            let messages = try #require(body["messages"] as? [[String: Any]])
            let content = try #require(messages.first?["content"] as? [[String: Any]])
            let image = try #require(content.first?["source"] as? [String: Any])
            #expect(image["media_type"] as? String == "image/jpeg")
            #expect(image["data"] as? String == "aW1hZ2U=")
        case .gemini:
            #expect(request.url?.path == "/v1beta/models/test-model:generateContent")
            #expect(request.url?.host == "generativelanguage.googleapis.com")
            #expect(request.url?.query == nil, "Keys must stay out of the URL")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "fake-test-key")
            let contents = try #require(body["contents"] as? [[String: Any]])
            let parts = try #require(contents.first?["parts"] as? [[String: Any]])
            let image = try #require(parts.last?["inlineData"] as? [String: Any])
            #expect(image["mimeType"] as? String == "image/jpeg")
            #expect(image["data"] as? String == "aW1hZ2U=")
        case .ollama: Issue.record("Cloud test must not reach Ollama")
        }
    }

    @Test("Permanent request, authentication and billing failures are never retried", arguments: providers, [400, 401, 402, 403])
    func unauthorized(provider: AIProvider, status: Int) async throws {
        let fixture = HTTPFixture(steps: [.response(status, #"{"error":{"message":"Invalid test request"}}"#)])
        defer { fixture.close() }
        do {
            _ = try await analyze(fixture.service(), provider: provider)
            Issue.record("Expected an authentication error")
        } catch AIAnalysisService.AnalysisError.apiError(let actualStatus, let message, let actualProvider) {
            #expect(actualStatus == status)
            #expect(actualProvider == provider)
            #expect(message.contains("Invalid test request"))
        }
        #expect(fixture.requests.count == 1)
    }

    @Test("Rate limits and transient server errors retry the same request", arguments: [429, 502, 503])
    func transientHTTP(status: Int) async throws {
        let fixture = HTTPFixture(steps: [.response(status, "busy"), .response(200, Self.envelope(.openai))])
        defer { fixture.close() }
        let result = try await analyze(fixture.service())
        #expect(result.imageSummary == "Orange Screen")
        #expect(fixture.requests.count == 2)
        #expect(try canonicalBody(fixture.requests.first) == canonicalBody(fixture.requests.last))
    }

    @Test("Timeout recovers without changing the model or image")
    func transportRetry() async throws {
        let fixture = HTTPFixture(steps: [.failure(.timedOut), .response(200, Self.envelope(.gemini))])
        defer { fixture.close() }
        let result = try await analyze(fixture.service(), provider: .gemini)
        #expect(result.model == "test-model")
        #expect(fixture.requests.count == 2)
        #expect(try canonicalBody(fixture.requests.first) == canonicalBody(fixture.requests.last))
    }

    @Test("Retry budgets stop persistent failures after three requests")
    func exhaustedRetries() async throws {
        let fixture = HTTPFixture(steps: Array(repeating: .response(429, "busy"), count: 4))
        defer { fixture.close() }
        await #expect(throws: AIAnalysisService.AnalysisError.self) { try await analyze(fixture.service()) }
        #expect(fixture.requests.count == 3)
    }

    @Test("Malformed analysis gets one format retry independent of the network budget")
    func independentBudgets() async throws {
        let fixture = HTTPFixture(steps: [.response(503, "busy"), .response(200, Self.envelope(.openai, text: "not analysis")), .response(200, Self.envelope(.openai))])
        defer { fixture.close() }
        let result = try await analyze(fixture.service())
        #expect(result.imageSummary == "Orange Screen")
        #expect(fixture.requests.count == 3)
    }

    @Test("Repeated malformed analysis stops after its single format retry")
    func malformedAnalysis() async throws {
        let fixture = HTTPFixture(steps: Array(repeating: .response(200, Self.envelope(.openai, text: "not analysis")), count: 3))
        defer { fixture.close() }
        await #expect(throws: AIAnalysisService.AnalysisError.self) { try await analyze(fixture.service()) }
        #expect(fixture.requests.count == 2)
    }

    @Test("Missing provider response content fails without inventing an analysis", arguments: providers)
    func missingContent(provider: AIProvider) async throws {
        let fixture = HTTPFixture(steps: [.response(200, "{}")])
        defer { fixture.close() }
        await #expect(throws: AIAnalysisService.AnalysisError.self) { try await analyze(fixture.service(), provider: provider) }
        #expect(fixture.requests.count == 1)
    }

    @Test("Cancelling retry backoff stops requests and preserves cancellation")
    func cancellationDuringBackoff() async throws {
        let fixture = HTTPFixture(steps: [.response(503, "busy"), .response(200, Self.envelope(.openai))])
        defer { fixture.close() }
        let (events, continuation) = AsyncStream<Void>.makeStream()
        let service = fixture.service { _ in
            continuation.yield(())
            try await Task.sleep(for: .seconds(30))
        }
        let task = Task { _ = try await analyze(service) }
        for await _ in events { break }
        task.cancel()
        continuation.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.requests.count == 1)
    }

    private func canonicalBody(_ request: URLRequest?) throws -> Data {
        let data = try #require(request?.httpBody)
        return try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: .sortedKeys)
    }

    private func analyze(_ service: AIAnalysisService, provider: AIProvider = .openai) async throws -> AnalysisResult {
        try await service.analyzeEncodedImage(base64Image: "aW1hZ2U=", provider: provider,
                                             model: "test-model", apiKey: "fake-test-key", prompt: "Test guidance")
    }

    private static func envelope(_ provider: AIProvider, text: String = analysis) -> String {
        let object: [String: Any]
        switch provider {
        case .anthropic: object = ["content": [["type": "thinking", "thinking": "internal"], ["type": "text", "text": text]]]
        case .gemini: object = ["candidates": [["content": ["parts": [["text": text]]]]]]
        default: object = ["choices": [["message": ["content": text]]]]
        }
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
}

/// Every session has its own locked request queue; parallel tests cannot consume each other's responses.
private final class HTTPFixture: @unchecked Sendable {
    enum Step: Sendable { case response(Int, String), failure(URLError.Code) }
    let id = UUID().uuidString
    private let lock = NSLock()
    private var steps: [Step]
    private var recorded: [URLRequest] = []
    private var session: URLSession!
    var requests: [URLRequest] { lock.withLock { recorded } }

    init(steps: [Step]) {
        self.steps = steps
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["X-Snapwell-Test": id]
        configuration.protocolClasses = [CloudMockURLProtocol.self]
        session = URLSession(configuration: configuration)
        CloudMockURLProtocol.register(self)
    }

    func service(retryDelay: @escaping @Sendable (Int) async throws -> Void = { _ in }) -> AIAnalysisService {
        AIAnalysisService(session: session, retryDelay: retryDelay)
    }

    func close() {
        session.invalidateAndCancel()
        CloudMockURLProtocol.remove(id)
    }

    func consume(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = data
        }
        let step = lock.withLock { () -> Step in
            recorded.append(captured)
            return steps.isEmpty ? .failure(.resourceUnavailable) : steps.removeFirst()
        }
        switch step {
        case .failure(let code): throw URLError(code)
        case .response(let status, let body):
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                     headerFields: ["Content-Type": "application/json"])!, Data(body.utf8))
        }
    }
}

private final class CloudMockURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: HTTPFixture] = [:]
    static func register(_ fixture: HTTPFixture) { lock.withLock { fixtures[fixture.id] = fixture } }
    static func remove(_ id: String) { _ = lock.withLock { fixtures.removeValue(forKey: id) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let fixture = try #require(Self.lock.withLock { Self.fixtures[request.value(forHTTPHeaderField: "X-Snapwell-Test") ?? ""] })
            let (response, data) = try fixture.consume(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
