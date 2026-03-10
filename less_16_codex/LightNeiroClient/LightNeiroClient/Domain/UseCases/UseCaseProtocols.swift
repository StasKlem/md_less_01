import Foundation

protocol SendMessageUseCaseProtocol {
    func execute(
        sessionID: UUID,
        branchID: UUID,
        userText: String,
        assistantInstruction: String?
    ) async throws -> ChatMessage
}

extension SendMessageUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID, userText: String) async throws -> ChatMessage {
        try await execute(
            sessionID: sessionID,
            branchID: branchID,
            userText: userText,
            assistantInstruction: nil
        )
    }
}

protocol BuildMemoryContextUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID, settings: LLMSettings) async throws -> MemoryContext
}

protocol FetchMessagesUseCaseProtocol {
    func execute(branchID: UUID) async throws -> [ChatMessage]
}

protocol UpdateShortTermMemoryUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID, windowSize: Int) async throws -> MemoryWriteEvent?
}

protocol UpdateWorkingMemoryUseCaseProtocol {
    func execute(
        sessionID: UUID,
        branchID: UUID,
        latestUserMessage: String,
        latestAssistantMessage: String?
    ) async throws -> [MemoryWriteEvent]
}

protocol UpdateLongTermMemoryUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID, latestUserMessage: String, settings: LLMSettings) async throws -> [MemoryWriteEvent]
}

protocol ApplySettingsUseCaseProtocol {
    func execute(sessionID: UUID, settings: LLMSettings) async throws
}

protocol FetchSettingsUseCaseProtocol {
    func execute(sessionID: UUID) async throws -> LLMSettings
}

protocol CollectSessionMetricsUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID) async throws -> SessionInfoSnapshot
}

protocol LoadAPIKeyUseCaseProtocol {
    func execute() throws -> String?
}

protocol SaveAPIKeyUseCaseProtocol {
    func execute(apiKey: String) throws
    func delete() throws
}

protocol VacationPlannerReducerProtocol {
    func reduce(
        snapshot: VacationPlanningSnapshot,
        event: VacationPlanningEvent
    ) -> VacationPlanningTransitionResult
}

protocol StartVacationPlanningUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningTurnResult
}

protocol HandleVacationPlanningEventUseCaseProtocol {
    func execute(
        sessionID: UUID,
        branchID: UUID,
        userText: String,
        source: QuestionnaireAnswerSource
    ) async throws -> VacationPlanningTurnResult
}

extension HandleVacationPlanningEventUseCaseProtocol {
    func execute(
        sessionID: UUID,
        branchID: UUID,
        userText: String
    ) async throws -> VacationPlanningTurnResult {
        try await execute(
            sessionID: sessionID,
            branchID: branchID,
            userText: userText,
            source: .chat
        )
    }
}

protocol GetVacationPlanningStatusUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningSnapshot
}

protocol FinalizeVacationPlanUseCaseProtocol {
    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlan
}

protocol ProcessUserAnswerUseCaseProtocol {
    func execute(
        schema: QuestionnaireSchema,
        currentState: QuestionnaireState,
        currentSlots: VacationSlots,
        userText: String,
        settings: LLMSettings,
        source: QuestionnaireAnswerSource
    ) async -> QuestionnaireProcessingResult
}

protocol FetchVacationPlannerMCPToolsUseCaseProtocol {
    func execute() async -> String
}
