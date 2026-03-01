import Foundation

struct MockLLMClient: LLMClientProtocol {
    func send(request: LLMRequest) async throws -> LLMResponse {
        let lastUserText = request.messages.last(where: { $0.role == .user })?.content ?? ""
        let prefix = request.settings.summarizationMode == .detailed ? "Detailed: " : "Reply: "
        return LLMResponse(
            content: "\(prefix)\(lastUserText)",
            inputTokens: max(8, request.messages.count * 4),
            outputTokens: 16,
            latencyMs: 120
        )
    }
}
