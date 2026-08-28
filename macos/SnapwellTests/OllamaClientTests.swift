import Foundation
import AppKit
import SwiftData
import Testing
@testable import Snapwell

@Suite("Ollama Client", .serialized)
struct OllamaClientTests {
    @Test("Model discovery retains only installed vision models")
    func filtersVisionModels() async throws {
        let client = makeClient { request in
            switch request.url?.path {
            case "/api/tags":
                return Self.response(for: request, body: #"{"models":[{"name":"llama3.2:3b"},{"name":"gemma3:4b"},{"name":"llava:latest"}]}"#)
            case "/api/show":
                let body = try #require(Self.bodyData(from: request))
                let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let model = try #require(json["model"] as? String)
                let capabilities = model == "llama3.2:3b" ? ["completion"] : ["completion", "vision"]
                let data = try JSONSerialization.data(withJSONObject: ["capabilities": capabilities])
                return Self.response(for: request, data: data)
            default:
                return Self.response(for: request, statusCode: 404, body: #"{"error":"not found"}"#)
            }
        }

        let models = try await client.fetchVisionModels()

        #expect(models.map(\.id) == ["gemma3:4b", "llava:latest"])
    }

    @Test("Chat sends an image and Snapwell's structured response schema")
    func sendsStructuredChatRequest() async throws {
        let client = makeClient { request in
            #expect(request.url?.path == "/api/chat")
            #expect(request.httpMethod == "POST")

            let body = try #require(Self.bodyData(from: request))
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["model"] as? String == "gemma3:4b")
            #expect(json["stream"] as? Bool == false)

            let options = try #require(json["options"] as? [String: Any])
            #expect(options["temperature"] as? Int == 0)

            let schema = try #require(json["format"] as? [String: Any])
            #expect(schema["type"] as? String == "object")
            #expect(schema["required"] as? [String] == ["imageContext", "imageSummary", "patterns"])

            let messages = try #require(json["messages"] as? [[String: Any]])
            #expect(messages.count == 2)
            #expect(messages[0]["role"] as? String == "system")
            #expect(messages[0]["content"] as? String == "Use this prompt")
            #expect(messages[1]["images"] as? [String] == ["base64-image"])

            return Self.response(
                for: request,
                body: #"{"message":{"content":"{\"imageContext\":\"A photo\",\"imageSummary\":\"Photo\",\"patterns\":[]}"}}"#
            )
        }

        let content = try await client.analyze(
            model: "gemma3:4b",
            prompt: "Use this prompt",
            base64Image: "base64-image"
        )

        #expect(content.contains(#""imageSummary":"Photo""#))
    }

    @Test("A missing chat model produces the actionable missing-model error")
    func missingModelError() async {
        let client = makeClient { request in
            Self.response(for: request, statusCode: 404, body: #"{"error":"model not found"}"#)
        }

        do {
            _ = try await client.analyze(model: "missing", prompt: "Prompt", base64Image: "image")
            Issue.record("Expected modelNotInstalled")
        } catch let error as OllamaError {
            #expect(error == .modelNotInstalled)
            #expect(error.localizedDescription == "The selected Ollama model isn’t installed. Install it or choose another model, then retry.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Connection failures report that Ollama is not running")
    func offlineError() async {
        let client = makeClient { _ in throw URLError(.cannotConnectToHost) }

        do {
            _ = try await client.fetchVisionModels()
            Issue.record("Expected notRunning")
        } catch let error as OllamaError {
            #expect(error == .notRunning)
            #expect(error.localizedDescription == "Couldn’t connect to Ollama. Open Ollama on this Mac, then retry.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Malformed successful responses are rejected")
    func invalidResponse() async {
        let client = makeClient { request in
            Self.response(for: request, body: #"{"unexpected":true}"#)
        }

        do {
            _ = try await client.fetchVisionModels()
            Issue.record("Expected invalidResponse")
        } catch let error as OllamaError {
            #expect(error == .invalidResponse)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Recommended Ollama model prefers Gemma 3 4B")
    func recommendsGemmaThree4B() {
        let service = ModelDiscoveryService(ollamaClient: makeClient { request in
            Self.response(for: request, body: #"{"models":[]}"#)
        })
        let models = [
            DiscoveredModel(id: "llava:latest", displayName: "llava:latest"),
            DiscoveredModel(id: "gemma3:12b", displayName: "gemma3:12b"),
            DiscoveredModel(id: "gemma3:4b", displayName: "gemma3:4b")
        ]

        #expect(service.preferredModel(from: models, for: .ollama)?.id == "gemma3:4b")
    }

    @Test("A failed item stops the batch and a successful retry resumes untouched items")
    @MainActor func retryResumesQueue() async throws {
        let tempRoot = try IntegrationTestSupport.makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let storage = MediaStorageService(baseURL: tempRoot)
        let sidecars = MetadataSidecarService(storage: storage)
        let container = try TestContainer.create()
        let context = ModelContext(container)

        let imageData = try Self.testPNGData()
        try storage.saveMedia(data: imageData, filename: "first.png")
        try storage.saveMedia(data: imageData, filename: "second.png")
        let first = MediaItem(id: "first", mediaType: .image, filename: "first.png", width: 2, height: 2)
        let second = MediaItem(id: "second", mediaType: .image, filename: "second.png", width: 2, height: 2)
        context.insert(first)
        context.insert(second)
        try context.save()

        let offlineClient = makeClient { _ in throw URLError(.cannotConnectToHost) }
        let offlineService = ImportService(
            storage: storage,
            sidecarService: sidecars,
            analysisService: AIAnalysisService(ollamaClient: offlineClient),
            providerOverride: .ollama,
            modelOverride: "gemma3:4b"
        )

        await offlineService.analyzeUnanalyzedItems(from: [first, second], context: context)

        #expect(first.analysisError == "Couldn’t connect to Ollama. Open Ollama on this Mac, then retry.")
        #expect(first.analysisResult == nil)
        #expect(second.analysisError == nil)
        #expect(second.analysisResult == nil)

        let successClient = makeClient { request in
            Self.response(
                for: request,
                body: #"{"message":{"content":"{\"imageContext\":\"A test image\",\"imageSummary\":\"Test Image\",\"patterns\":[{\"name\":\"Test Pattern\",\"confidence\":0.9}]}"}}"#
            )
        }
        let retryService = ImportService(
            storage: storage,
            sidecarService: sidecars,
            analysisService: AIAnalysisService(ollamaClient: successClient),
            providerOverride: .ollama,
            modelOverride: "gemma3:4b"
        )

        await retryService.retryFailedItems([first], continuingWith: [first, second], context: context)

        #expect(first.analysisError == nil)
        #expect(first.analysisResult?.provider == "ollama")
        #expect(first.analysisResult?.model == "gemma3:4b")
        #expect(second.analysisError == nil)
        #expect(second.analysisResult?.provider == "ollama")
        #expect(second.analysisResult?.model == "gemma3:4b")
    }

    private func makeClient(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> OllamaClient {
        OllamaMockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OllamaMockURLProtocol.self]
        return OllamaClient(session: URLSession(configuration: configuration))
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        body: String
    ) -> (HTTPURLResponse, Data) {
        response(for: request, statusCode: statusCode, data: Data(body.utf8))
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        data: Data
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4_096)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func testPNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 2, height: 2))
        image.unlockFocus()

        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

}

private final class OllamaMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
