import Foundation

protocol ChatSessionRepositoryProtocol {
    func fetchAllSessions() async throws -> [ChatSession]
    func fetchSession(id: UUID) async throws -> ChatSession?
    func saveSession(_ session: ChatSession) async throws
}

protocol BranchRepositoryProtocol {
    func fetchBranches(sessionID: UUID) async throws -> [ChatBranch]
    func saveBranch(_ branch: ChatBranch) async throws
    func saveCheckpoint(_ checkpoint: ChatCheckpoint) async throws
}

protocol MessageRepositoryProtocol {
    func fetchMessages(branchID: UUID) async throws -> [ChatMessage]
    func saveMessage(_ message: ChatMessage) async throws
}

protocol FactsRepositoryProtocol {
    func fetchFacts(sessionID: UUID) async throws -> [StickyFact]
    func upsertFacts(sessionID: UUID, facts: [StickyFact]) async throws
}

protocol SettingsRepositoryProtocol {
    func fetchSettings(sessionID: UUID) async throws -> LLMSettings
    func saveSettings(sessionID: UUID, settings: LLMSettings) async throws
}

protocol MetricsRepositoryProtocol {
    func appendMetric(_ metric: RequestMetric) async throws
    func fetchMetrics(sessionID: UUID) async throws -> [RequestMetric]
}
