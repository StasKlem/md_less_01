import Foundation

protocol HTTPClientProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClientProtocol {}

struct RouterAIConfiguration {
    let endpoint: URL
    let timeoutInterval: TimeInterval
    let apiKeyProvider: @Sendable () -> String?

    static let `default` = RouterAIConfiguration(
        endpoint: URL(string: "https://routerai.ru/api/v1/chat/completions")!,
        timeoutInterval: 120,
        apiKeyProvider: { ProcessInfo.processInfo.environment["ROUTERAI_API_KEY"] }
    )
}

enum RouterAILLMClientError: LocalizedError {
    case missingAPIKey
    case invalidHTTPResponse
    case api(statusCode: Int, message: String)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing ROUTERAI_API_KEY environment variable."
        case .invalidHTTPResponse:
            return "Invalid HTTP response."
        case let .api(statusCode, message):
            return "RouterAI API error (\(statusCode)): \(message)"
        case .invalidPayload:
            return "RouterAI response does not contain assistant message."
        }
    }
}

final class RouterAILLMClient: LLMClientProtocol {
    private let httpClient: HTTPClientProtocol
    private let configuration: RouterAIConfiguration
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        httpClient: HTTPClientProtocol = URLSession.shared,
        configuration: RouterAIConfiguration = .default
    ) {
        self.httpClient = httpClient
        self.configuration = configuration
    }

    func send(request: LLMRequest) async throws -> LLMResponse {
        guard let apiKey = configuration.apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw RouterAILLMClientError.missingAPIKey
        }

        let startedAt = Date()
        var urlRequest = URLRequest(url: configuration.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = configuration.timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let apiMessages = toAPIMessages(from: request)
        let payload = RouterAIChatCompletionRequest(
            model: request.settings.model.rawValue,
            messages: apiMessages
        )
        urlRequest.httpBody = try encoder.encode(payload)

        let (data, response) = try await httpClient.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RouterAILLMClientError.invalidHTTPResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseAPIErrorMessage(from: data)
            throw RouterAILLMClientError.api(statusCode: httpResponse.statusCode, message: message)
        }

        let apiResponse = try decoder.decode(RouterAIChatCompletionResponse.self, from: data)
        guard let content = apiResponse.firstContent, !content.isEmpty else {
            throw RouterAILLMClientError.invalidPayload
        }

        let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000.0)
        let inputTokens = apiResponse.usage?.promptTokens ?? estimatedTokens(in: apiMessages.map(\.content).joined(separator: " "))
        let outputTokens = apiResponse.usage?.completionTokens ?? estimatedTokens(in: content)

        return LLMResponse(
            content: content,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            latencyMs: latencyMs
        )
    }

    private func toAPIMessages(from request: LLMRequest) -> [RouterAIMessagePayload] {
        var messages: [RouterAIMessagePayload] = []

        let systemPrompt = request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemPrompt.isEmpty {
            messages.append(.init(role: .system, content: systemPrompt))
        }

        if !request.workingMemory.isEmpty {
            let workingBlock = request.workingMemory
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n")
            messages.append(.init(role: .system, content: "WORKING_MEMORY:\n\(workingBlock)"))
        }

        if !request.longTermMemory.isEmpty {
            let longTermBlock = request.longTermMemory
                .map { "[\($0.namespace.rawValue)] \($0.key): \($0.value)" }
                .joined(separator: "\n")
            messages.append(.init(role: .system, content: "LONG_TERM_MEMORY:\n\(longTermBlock)"))
        }

        messages.append(.init(role: .system, content: "RECENT_DIALOG:"))
        messages.append(contentsOf: request.shortTermMessages.map {
            RouterAIMessagePayload(role: .init(domainRole: $0.role), content: $0.content)
        })

        return messages
    }

    private func parseAPIErrorMessage(from data: Data) -> String {
        guard let envelope = try? decoder.decode(RouterAIAPIErrorEnvelope.self, from: data) else {
            return String(data: data, encoding: .utf8) ?? "Unknown API error"
        }

        if let nested = envelope.error?.message, !nested.isEmpty {
            return nested
        }
        if let message = envelope.message, !message.isEmpty {
            return message
        }
        return "Unknown API error"
    }

    private func estimatedTokens(in text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }
}

private struct RouterAIChatCompletionRequest: Encodable {
    let model: String
    let messages: [RouterAIMessagePayload]
}

private struct RouterAIMessagePayload: Encodable {
    enum Role: String, Encodable {
        case system
        case user
        case assistant

        init(domainRole: MessageRole) {
            switch domainRole {
            case .system:
                self = .system
            case .user:
                self = .user
            case .assistant:
                self = .assistant
            }
        }
    }

    let role: Role
    let content: String
}

private struct RouterAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String

            private enum CodingKeys: String, CodingKey {
                case content
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let text = try? container.decode(String.self, forKey: .content) {
                    content = text
                    return
                }

                let parts = try container.decode([MessagePart].self, forKey: .content)
                content = parts
                    .map(\.text)
                    .joined()
            }
        }

        let message: Message
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    let choices: [Choice]
    let usage: Usage?

    var firstContent: String? {
        choices.first?.message.content
    }
}

private struct MessagePart: Decodable {
    let text: String
}

private struct RouterAIAPIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
    let message: String?
}
