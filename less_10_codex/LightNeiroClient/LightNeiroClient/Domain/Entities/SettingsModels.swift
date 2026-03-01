import Foundation

enum LLMModel: String, CaseIterable, Codable {
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
}

enum SummarizationMode: String, CaseIterable, Codable {
    case off
    case concise
    case detailed
}

struct LLMSettings: Codable, Equatable {
    var model: LLMModel
    var summarizationMode: SummarizationMode
    var temperature: Double
    var windowSize: Int

    static let `default` = LLMSettings(
        model: .gpt4oMini,
        summarizationMode: .concise,
        temperature: 0.4,
        windowSize: 12
    )
}

struct RequestMetric: Identifiable, Codable, Equatable {
    let id: UUID
    let messageID: UUID
    let startedAt: Date
    let endedAt: Date
    let latencyMs: Int
    let inputTokens: Int
    let outputTokens: Int
}

struct SessionInfoSnapshot: Equatable {
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalRequests: Int
    let lastLatencyMs: Int
}
