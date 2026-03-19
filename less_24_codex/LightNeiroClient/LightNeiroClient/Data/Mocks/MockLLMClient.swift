import Foundation

struct MockLLMClient: LLMClientProtocol {
    func send(request: LLMRequest) async throws -> LLMResponse {
        let lastUserText = request.shortTermMessages.last(where: { $0.role == .user })?.content ?? ""
        return LLMResponse(
            content: "Reply: \(lastUserText)",
            inputTokens: max(8, request.shortTermMessages.count * 4),
            outputTokens: 16,
            latencyMs: 120
        )
    }
}
