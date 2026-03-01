import Foundation

enum LLMModel: String, CaseIterable, Codable {
    case deepseekV32 = "deepseek/deepseek-v3.2"
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
}

struct LLMSettings: Codable, Equatable {
    var model: LLMModel
    var temperature: Double
    var windowSize: Int

    static let `default` = LLMSettings(
        model: .deepseekV32,
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
