import Foundation

protocol StartHackerNewsTaskAgentUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval?) async throws -> HackerNewsTaskAgentTurnResult
}

protocol StopHackerNewsTaskAgentUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentTurnResult
}

protocol ConfigureHackerNewsTaskAgentIntervalUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval) async throws -> HackerNewsTaskAgentTurnResult
}

protocol TickHackerNewsTaskAgentUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentTurnResult
}

protocol GetHackerNewsTaskAgentStatusUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentSnapshot
}
