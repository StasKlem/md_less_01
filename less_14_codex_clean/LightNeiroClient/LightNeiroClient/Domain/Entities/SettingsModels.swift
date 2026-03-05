import Foundation

/// Список поддерживаемых LLM-моделей.
enum LLMModel: String, CaseIterable, Codable {
    case deepseekV32 = "deepseek/deepseek-v3.2"
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
}

/// Пользовательские настройки LLM на уровне сессии.
struct LLMSettings: Codable, Equatable {
    var model: LLMModel
    var temperature: Double
    var windowSize: Int

    /// Значения настроек по умолчанию для новой сессии.
    static let `default` = LLMSettings(
        model: .deepseekV32,
        temperature: 0.4,
        windowSize: 3
    )

    private enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case windowSize
    }

    init(
        model: LLMModel,
        temperature: Double,
        windowSize: Int
    ) {
        self.model = model
        self.temperature = temperature
        self.windowSize = windowSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(LLMModel.self, forKey: .model)
        temperature = try container.decode(Double.self, forKey: .temperature)
        windowSize = try container.decode(Int.self, forKey: .windowSize)
    }
}

/// Метрика одного запроса в LLM.
struct RequestMetric: Identifiable, Codable, Equatable {
    let id: UUID
    let messageID: UUID
    let branchID: UUID
    let startedAt: Date
    let endedAt: Date
    let latencyMs: Int
    let inputTokens: Int
    let outputTokens: Int
}

/// Агрегированная статистика по ветке для панели Session Info.
struct SessionInfoSnapshot: Equatable {
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalRequests: Int
    let lastLatencyMs: Int
}
