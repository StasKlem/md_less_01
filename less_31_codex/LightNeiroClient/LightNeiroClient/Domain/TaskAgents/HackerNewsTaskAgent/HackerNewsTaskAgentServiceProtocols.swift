import Foundation

/// Контракт MCP-сервиса для получения статьи из Hacker News.
protocol MCPHackerNewsServiceProtocol {
    func fetchRandomStory(serverURL: URL) async throws -> HackerNewsTaskAgentStory
    func translateStory(serverURL: URL, sessionID: UUID, story: String, language: String) async throws -> String
    func saveArchiveJSON(serverURL: URL, json: String) async throws -> String
}

/// Контракт LLM-сервиса для периодической сводки.
protocol HackerNewsLLMSummaryServiceProtocol {
    func summarize(
        sessionID: UUID,
        recentStories: [HackerNewsTaskAgentStoryDigest]
    ) async throws -> String
}
