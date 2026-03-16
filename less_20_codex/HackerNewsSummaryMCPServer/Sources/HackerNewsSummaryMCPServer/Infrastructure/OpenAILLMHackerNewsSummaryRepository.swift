import Foundation

struct OpenAILLMHackerNewsSummaryRepository: HackerNewsSummaryRepository {
    private let config: OpenAIConfig
    private let httpClient: OpenAIHTTPClient

    init(config: OpenAIConfig, httpClient: OpenAIHTTPClient = URLSessionOpenAIHTTPClient()) {
        self.config = config
        self.httpClient = httpClient
    }

    func summarize(stories: [HackerNewsStoryForSummary], language: String) async throws -> String {
        let request = OpenAIChatCompletionRequest(
            model: config.model,
            messages: [
                .init(role: "system", content: systemPrompt(language: language)),
                .init(role: "user", content: makePrompt(stories: stories))
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
            throw HackerNewsSummaryToolError.llmFailure("LLM response is empty.")
        }

        return content
    }

    private func systemPrompt(language: String) -> String {
        if let customSystemPrompt = config.systemPrompt, !customSystemPrompt.isEmpty {
            return customSystemPrompt
        }

        return "You summarize lists of Hacker News stories. Write a concise summary in \(language). Keep it factual, no markdown." 
    }

    private func makePrompt(stories: [HackerNewsStoryForSummary]) -> String {
        let lines = stories.enumerated().map { index, story in
            var result = "#\(index + 1) | title=\(story.title)"
            if let id = story.id {
                result += " | id=\(id)"
            }
            if let author = story.author, !author.isEmpty {
                result += " | author=\(author)"
            }
            if let score = story.score {
                result += " | score=\(score)"
            }
            if let publishedAtUTC = story.publishedAtUTC, !publishedAtUTC.isEmpty {
                result += " | time=\(publishedAtUTC)"
            }
            if let url = story.url, !url.isEmpty {
                result += " | url=\(url)"
            }
            return result
        }

        return "Summarize these Hacker News stories:\n\n\(lines.joined(separator: "\n"))"
    }

    private func decode(_ data: Data) throws -> OpenAIChatCompletionResponse {
        do {
            return try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw HackerNewsSummaryToolError.llmFailure("Unable to decode LLM response: \(bodyPreview)")
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
