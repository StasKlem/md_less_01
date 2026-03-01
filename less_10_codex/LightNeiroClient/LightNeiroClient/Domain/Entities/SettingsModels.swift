import Foundation

enum LLMModel: String, CaseIterable, Codable {
    case deepseekV32 = "deepseek/deepseek-v3.2"
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
}

enum ContextStrategy: String, CaseIterable, Codable {
    case normal
    case slidingWindow
    case stickyFacts
}

struct LLMSettings: Codable, Equatable {
    var model: LLMModel
    var contextStrategy: ContextStrategy
    var temperature: Double
    var windowSize: Int
    var contextStrategyByBranch: [UUID: ContextStrategy]

    static let `default` = LLMSettings(
        model: .deepseekV32,
        contextStrategy: .normal,
        temperature: 0.4,
        windowSize: 3,
        contextStrategyByBranch: [:]
    )

    func contextStrategy(for branchID: UUID) -> ContextStrategy {
        contextStrategyByBranch[branchID] ?? contextStrategy
    }

    mutating func setContextStrategy(_ strategy: ContextStrategy, for branchID: UUID) {
        contextStrategyByBranch[branchID] = strategy
        contextStrategy = strategy
    }
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
