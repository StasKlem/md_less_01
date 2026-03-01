import Foundation

struct LLMRequest {
    let systemPrompt: String
    let facts: [StickyFact]
    let messages: [ChatMessage]
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
    ) async throws -> (facts: [StickyFact], messages: [ChatMessage])
}
