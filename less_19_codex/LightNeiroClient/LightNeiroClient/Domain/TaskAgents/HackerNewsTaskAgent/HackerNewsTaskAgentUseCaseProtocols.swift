import Foundation

protocol StartHackerNewsTaskAgentUseCaseProtocol {
    func execute(
        sessionID: UUID,
        branchID: UUID,
        onSystemMessage: (@Sendable (String) async -> Void)?
    ) async throws -> HackerNewsTaskAgentTurnResult
}

protocol StopHackerNewsTaskAgentUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentTurnResult
}

protocol GetHackerNewsTaskAgentStatusUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentSnapshot
}

extension StartHackerNewsTaskAgentUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentTurnResult {
        try await execute(
            sessionID: sessionID,
            branchID: branchID,
            onSystemMessage: nil
        )
    }
}
