import Foundation

struct OpenAILLMHackerNewsTranslateRepository: HackerNewsTranslateRepository {
    private let config: OpenAIConfig
    private let httpClient: OpenAIHTTPClient

    init(config: OpenAIConfig, httpClient: OpenAIHTTPClient = URLSessionOpenAIHTTPClient()) {
        self.config = config
        self.httpClient = httpClient
    }

    func translate(story: HackerNewsStoryForTranslation, language: String) async throws -> String {
        let request = OpenAIChatCompletionRequest(
            model: config.model,
            messages: [
                .init(role: "system", content: systemPrompt(language: language)),
                .init(role: "user", content: makePrompt(story: story))
            ],
            temperature: 0.2
        )

        let response = try await httpClient.postJSON(
            url: config.baseURL.appendingPathComponent("chat/completions"),
            bearerToken: config.apiKey,
            body: request
        )

        let decoded = try decode(response)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            throw HackerNewsTranslateToolError.llmFailure("LLM response is empty.")
        }

        return content
    }

    private func systemPrompt(language: String) -> String {
        if let customSystemPrompt = config.systemPrompt, !customSystemPrompt.isEmpty {
            return customSystemPrompt
        }

        return """
        You translate Hacker News story cards to \(language).
        Keep the same line-by-line structure and list bullets.
        Preserve numeric fields, IDs, timestamps, and URL values exactly.
        Return only the translated story text without markdown fences.
        """
    }

    private func makePrompt(story: HackerNewsStoryForTranslation) -> String {
        "Translate this Hacker News story:\n\n\(story.rawText)"
    }

    private func decode(_ data: Data) throws -> OpenAIChatCompletionResponse {
        do {
            return try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw HackerNewsTranslateToolError.llmFailure("Unable to decode LLM response: \(bodyPreview)")
        }
    }
}

struct OpenAIConfig: Sendable {
    let baseURL: URL
    let apiKey: String
    let model: String
    let systemPrompt: String?
}

private struct OpenAIChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}
