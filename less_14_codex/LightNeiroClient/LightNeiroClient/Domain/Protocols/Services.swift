import Foundation

struct LLMRequest {
    let systemPrompt: String
    let shortTermMessages: [ChatMessage]
    let workingMemory: [WorkingMemoryItem]
    let longTermMemory: [LongTermMemoryItem]
    let settings: LLMSettings
}

struct LLMResponse {
    let content: String
    let inputTokens: Int
    let outputTokens: Int
    let latencyMs: Int
}

protocol LLMClientProtocol {
    func send(request: LLMRequest) async throws -> LLMResponse
}

protocol ContextBuilderProtocol {
    func buildContext(
        sessionID: UUID,
        branchID: UUID,
        settings: LLMSettings
    ) async throws -> MemoryContext
}

protocol APIKeyStoreProtocol {
    nonisolated func fetchAPIKey() throws -> String?
    nonisolated func saveAPIKey(_ apiKey: String) throws
    nonisolated func deleteAPIKey() throws
}

struct VacationSlotsExtractionResult: Equatable {
    let slots: VacationSlots
    let validationErrors: [String]
}

protocol VacationSlotExtractionServiceProtocol {
    func extractSlots(from userText: String, current: VacationSlots) async throws -> VacationSlotsExtractionResult
}

protocol VacationOptionGenerationServiceProtocol {
    func generateOptions(context: VacationPlanningContext) async throws -> [VacationOption]
}

protocol VacationItineraryServiceProtocol {
    func generateItinerary(context: VacationPlanningContext) async throws -> VacationItinerary
}

protocol VacationBudgetEstimatorProtocol {
    func estimateBudget(context: VacationPlanningContext) async throws -> VacationBudgetBreakdown
}

struct QuestionnaireQuestionContext {
    let schema: QuestionnaireSchema
    let state: QuestionnaireState
    let latestUserMessage: String?
    let settings: LLMSettings
}

protocol QuestionGenerationServiceProtocol {
    func generateQuestion(
        context: QuestionnaireQuestionContext,
        targetField: QuestionnaireFieldDefinition?,
        toneHints: [String]
    ) async throws -> QuestionPrompt
}

protocol AnswerExtractionServiceProtocol {
    func extractFields(
        userText: String,
        schema: QuestionnaireSchema,
        currentState: QuestionnaireState,
        settings: LLMSettings
    ) async throws -> QuestionnaireExtractionResult
}
