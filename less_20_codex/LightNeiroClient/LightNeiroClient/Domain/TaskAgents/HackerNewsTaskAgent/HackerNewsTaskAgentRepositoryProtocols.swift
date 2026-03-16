import Foundation

/// Контракт хранения состояния task-агента Hacker News.
protocol HackerNewsTaskAgentStateRepositoryProtocol {
    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentSnapshot?
    func saveSnapshot(_ snapshot: HackerNewsTaskAgentSnapshot) async throws
}

/// Контракт файлового архива статей Hacker News.
protocol HackerNewsArticleArchiveRepositoryProtocol {
    /// Сохраняет одну fetched-статью в JSON.
    /// - Returns: Путь к сохраненному файлу.
    @discardableResult
    func saveArticle(_ record: HackerNewsTaskAgentArticleRecord) async throws -> URL
}
