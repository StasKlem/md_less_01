import Foundation

/// Список поддерживаемых LLM-моделей.
enum LLMModel: String, CaseIterable, Codable {
    case seed20Mini = "bytedance-seed/seed-2.0-mini"
    case deepseekV32 = "deepseek/deepseek-v3.2"
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
}

/// Пользовательские настройки LLM на уровне сессии.
struct LLMSettings: Codable, Equatable {
    var model: LLMModel
    var temperature: Double
    var windowSize: Int
    var isRAGEnabled: Bool
    var isMemoryEnabled: Bool
    var plannerInvariants: [String]

    /// Значения настроек по умолчанию для новой сессии.
    static let `default` = LLMSettings(
        model: .seed20Mini,
        temperature: 0.4,
        windowSize: 3,
        isRAGEnabled: false,
        isMemoryEnabled: true,
        plannerInvariants: [
            "Даты поездки: дата начала не позже даты окончания.",
            "Бюджет: если указан, должен быть больше 0.",
            "Количество путешественников: минимум 1.",
            "Маршрут можно строить только после заполнения: даты, бюджет, направление/стиль.",
            "Финализация плана возможна только при наличии маршрута и бюджета.",
            "После подтверждения план не меняется без явного revise-запроса."
        ]
    )

    private enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case windowSize
        case isRAGEnabled
        case isMemoryEnabled
        case plannerInvariants
    }

    init(
        model: LLMModel,
        temperature: Double,
        windowSize: Int,
        isRAGEnabled: Bool,
        isMemoryEnabled: Bool = true,
        plannerInvariants: [String]
    ) {
        self.model = model
        self.temperature = temperature
        self.windowSize = windowSize
        self.isRAGEnabled = isRAGEnabled
        self.isMemoryEnabled = isMemoryEnabled
        self.plannerInvariants = plannerInvariants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(LLMModel.self, forKey: .model)
        temperature = try container.decode(Double.self, forKey: .temperature)
        windowSize = try container.decode(Int.self, forKey: .windowSize)
        isRAGEnabled = try container.decodeIfPresent(Bool.self, forKey: .isRAGEnabled) ?? Self.default.isRAGEnabled
        isMemoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .isMemoryEnabled) ?? Self.default.isMemoryEnabled
        plannerInvariants = try container.decodeIfPresent([String].self, forKey: .plannerInvariants) ?? Self.default.plannerInvariants
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
