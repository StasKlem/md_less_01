import Foundation

protocol SendMessageUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID, userText: String) async throws -> ChatMessage
}

protocol BuildContextUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID, settings: LLMSettings) async throws -> (facts: [StickyFact], messages: [ChatMessage])
}

protocol FetchBranchesUseCaseProtocol {
    func execute(sessionID: UUID) async throws -> [ChatBranch]
}

protocol FetchMessagesUseCaseProtocol {
    func execute(branchID: UUID) async throws -> [ChatMessage]
}

protocol CloneDialogToBranchUseCaseProtocol {
    func execute(sourceBranchID: UUID, targetBranchID: UUID) async throws
}

protocol UpdateFactsUseCaseProtocol {
    func execute(sessionID: UUID, latestUserMessage: String, settings: LLMSettings) async throws
}

protocol CreateCheckpointUseCaseProtocol {
    func execute(branchID: UUID, messageID: UUID, name: String) async throws -> ChatCheckpoint
}

protocol CreateBranchUseCaseProtocol {
    func execute(sessionID: UUID, parentCheckpointID: UUID?, name: String) async throws -> ChatBranch
}

protocol AddBranchCreatedSystemMessageUseCaseProtocol {
    func execute(branchID: UUID, sourceBranchName: String) async throws
}

protocol SwitchBranchUseCaseProtocol {
    func execute(sessionID: UUID, targetBranchID: UUID) async throws -> ChatSession
}

protocol ApplySettingsUseCaseProtocol {
    func execute(sessionID: UUID, settings: LLMSettings) async throws
}

protocol FetchSettingsUseCaseProtocol {
    func execute(sessionID: UUID) async throws -> LLMSettings
}

protocol CollectSessionMetricsUseCaseProtocol {
    func execute(sessionID: UUID) async throws -> SessionInfoSnapshot
}

protocol LoadAPIKeyUseCaseProtocol {
    func execute() throws -> String?
}

protocol SaveAPIKeyUseCaseProtocol {
    func execute(apiKey: String) throws
    func delete() throws
}
