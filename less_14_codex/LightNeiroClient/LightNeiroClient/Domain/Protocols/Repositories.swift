import Foundation

protocol ChatSessionRepositoryProtocol {
    func fetchAllSessions() async throws -> [ChatSession]
    func fetchSession(id: UUID) async throws -> ChatSession?
    func saveSession(_ session: ChatSession) async throws
}

protocol BranchRepositoryProtocol {
    func fetchBranches(sessionID: UUID) async throws -> [ChatBranch]
    func fetchCheckpoints(branchID: UUID) async throws -> [ChatCheckpoint]
    func saveBranch(_ branch: ChatBranch) async throws
    func saveCheckpoint(_ checkpoint: ChatCheckpoint) async throws
}

protocol MessageRepositoryProtocol {
    func fetchMessages(branchID: UUID) async throws -> [ChatMessage]
    func saveMessage(_ message: ChatMessage) async throws
}

protocol ShortTermMemoryRepositoryProtocol {
    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> ShortTermMemorySnapshot?
    func saveSnapshot(_ snapshot: ShortTermMemorySnapshot) async throws
    func clear(sessionID: UUID, branchID: UUID) async throws
}

protocol WorkingMemoryRepositoryProtocol {
    func fetchActive(sessionID: UUID, branchID: UUID) async throws -> [WorkingMemoryItem]
    func upsert(sessionID: UUID, branchID: UUID, items: [WorkingMemoryItem]) async throws
    func resolve(sessionID: UUID, branchID: UUID, keys: [String]) async throws
}

protocol LongTermMemoryRepositoryProtocol {
    func fetch(sessionID: UUID, namespaces: [LongTermMemoryNamespace]?) async throws -> [LongTermMemoryItem]
    func upsert(sessionID: UUID, items: [LongTermMemoryItem]) async throws
    func delete(sessionID: UUID, keys: [String]) async throws
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

protocol VacationPlanningStateRepositoryProtocol {
    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningSnapshot?
    func saveSnapshot(_ snapshot: VacationPlanningSnapshot) async throws
}

protocol VacationPlanRepositoryProtocol {
    func fetchFinalPlan(sessionID: UUID, branchID: UUID) async throws -> VacationPlan?
    func saveFinalPlan(_ plan: VacationPlan) async throws
}
