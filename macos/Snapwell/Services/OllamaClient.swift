import Foundation

final class OllamaClient: Sendable {
    static let shared = OllamaClient()
    static let defaultBaseURL = URL(string: "http://localhost:11434")!

    private let baseURL: URL
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.baseURL = Self.defaultBaseURL
        self.session = session
    }

    func fetchVisionModels() async throws -> [DiscoveredModel] {
        var request = URLRequest(url: endpoint("api/tags"))
        request.timeoutInterval = 5

        let data = try await perform(request)
        let response: TagsResponse
        do {
            response = try JSONDecoder().decode(TagsResponse.self, from: data)
        } catch {
            throw OllamaError.invalidResponse
        }
        var visionModels: [DiscoveredModel] = []

        for model in response.models {
            guard try await capabilities(for: model.name).contains("vision") else { continue }
            visionModels.append(DiscoveredModel(id: model.name, displayName: model.name))
        }

        return visionModels.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func analyze(model: String, prompt: String, base64Image: String) async throws -> String {
        var request = URLRequest(url: endpoint("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt],
                [
                    "role": "user",
                    "content": "Analyze this image.",
                    "images": [base64Image]
                ]
            ],
            "stream": false,
            "format": Self.analysisSchema,
            "options": ["temperature": 0]
        ])

        let data = try await perform(request)
        let response: ChatResponse
        do {
            response = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw OllamaError.invalidResponse
        }
        let content = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw OllamaError.invalidResponse }
        return content
    }

    private func capabilities(for model: String) async throws -> Set<String> {
        var request = URLRequest(url: endpoint("api/show"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])

        let data = try await perform(request)
        let response: ShowResponse
        do {
            response = try JSONDecoder().decode(ShowResponse.self, from: data)
        } catch {
            throw OllamaError.invalidResponse
        }
        return Set(response.capabilities)
    }

    private func endpoint(_ path: String) -> URL {
        path.split(separator: "/").reduce(baseURL) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                let message = Self.errorMessage(from: data)
                if http.statusCode == 404 {
                    throw OllamaError.modelNotInstalled
                }
                throw OllamaError.apiError(statusCode: http.statusCode, message: message)
            }
            return data
        } catch let error as OllamaError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                throw OllamaError.notRunning
            case .timedOut:
                throw OllamaError.timedOut
            default:
                throw error
            }
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? String,
              !error.isEmpty else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        return error
    }

    static var analysisSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "imageContext": ["type": "string"],
                "imageSummary": ["type": "string"],
                "patterns": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "confidence": ["type": "number"]
                        ],
                        "required": ["name", "confidence"]
                    ]
                ]
            ],
            "required": ["imageContext", "imageSummary", "patterns"]
        ]
    }

    private struct TagsResponse: Decodable {
        let models: [Model]

        struct Model: Decodable {
            let name: String
        }
    }

    private struct ShowResponse: Decodable {
        let capabilities: [String]
    }

    private struct ChatResponse: Decodable {
        let message: Message

        struct Message: Decodable {
            let content: String
        }
    }
}

enum OllamaError: LocalizedError, Equatable {
    case notRunning
    case timedOut
    case modelNotInstalled
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            "Couldn’t connect to Ollama. Open Ollama on this Mac, then retry."
        case .timedOut:
            "Ollama took too long to respond. Try again."
        case .modelNotInstalled:
            "The selected Ollama model isn’t installed. Install it or choose another model, then retry."
        case .invalidResponse:
            "Ollama returned an invalid response. Try again."
        case .apiError(let statusCode, let message):
            "Ollama returned HTTP \(statusCode): \(message)"
        }
    }
}
