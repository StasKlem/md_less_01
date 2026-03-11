import Foundation

/// Контракт MCP-сервиса для получения статьи из Hacker News.
protocol MCPHackerNewsServiceProtocol {
    func fetchRandomStory(serverURL: URL) async throws -> HackerNewsTaskAgentStory
}

/// Контракт LLM-сервиса для периодической сводки.
protocol HackerNewsLLMSummaryServiceProtocol {
    func summarize(
        sessionID: UUID,
        recentStories: [HackerNewsTaskAgentStoryDigest]
    ) async throws -> String
}
