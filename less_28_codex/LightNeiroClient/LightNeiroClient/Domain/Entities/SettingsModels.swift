import Foundation

/// Поддерживаемые LLM-бэкенды.
enum LLMBackendKind: String, CaseIterable, Codable {
    case routerAI
    case localhost

    /// Человекочитаемое название для UI.
    var title: String {
        switch self {
        case .routerAI:
            return "RouterAI"
        case .localhost:
            return "localhost"
        }
    }

    /// Совместимый с OpenAI endpoint для чата.
    var endpoint: URL {
        switch self {
        case .routerAI:
            return URL(string: "https://routerai.ru/api/v1/chat/completions")!
        case .localhost:
            return URL(string: "http://localhost:1234/v1/chat/completions")!
        }
    }
}

/// Список поддерживаемых LLM-моделей.
enum LLMModel: String, CaseIterable, Codable {
    case seed20Mini = "bytedance-seed/seed-2.0-mini"
    case deepseekV32 = "deepseek/deepseek-v3.2"
    case gpt5_4_nano = "openai/gpt-5.4-nano"
    case gemma34B = "google/gemma-3-4b"
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
}

/// Пользовательские настройки LLM на уровне сессии.
struct LLMSettings: Codable, Equatable {
    var backend: LLMBackendKind
    var model: LLMModel
    var temperature: Double
    var windowSize: Int
    var isRAGEnabled: Bool
    var ragChunkingStrategy: ChunkingStrategyType
    var isRAGPostFilteringEnabled: Bool
    var ragTopKBeforeFiltering: Int
    var ragTopKAfterFiltering: Int
    var ragRelevanceThreshold: Double
    var isMemoryEnabled: Bool
    var plannerInvariants: [String]

    /// Значения настроек по умолчанию для новой сессии.
    static let `default` = LLMSettings(
        backend: .routerAI,
        model: .seed20Mini,
        temperature: 0.4,
        windowSize: 3,
        isRAGEnabled: true,
        ragChunkingStrategy: .structural,
        isRAGPostFilteringEnabled: true,
        ragTopKBeforeFiltering: 8,
        ragTopKAfterFiltering: 4,
        ragRelevanceThreshold: 0.70,
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
        case backend
        case model
        case temperature
        case windowSize
        case isRAGEnabled
        case ragChunkingStrategy
        case isRAGPostFilteringEnabled
        case ragTopKBeforeFiltering
        case ragTopKAfterFiltering
        case ragRelevanceThreshold
        case isMemoryEnabled
        case plannerInvariants
    }

    init(
        backend: LLMBackendKind,
        model: LLMModel,
        temperature: Double,
        windowSize: Int,
        isRAGEnabled: Bool,
        ragChunkingStrategy: ChunkingStrategyType = .structural,
        isRAGPostFilteringEnabled: Bool = LLMSettings.default.isRAGPostFilteringEnabled,
        ragTopKBeforeFiltering: Int = LLMSettings.default.ragTopKBeforeFiltering,
        ragTopKAfterFiltering: Int = LLMSettings.default.ragTopKAfterFiltering,
        ragRelevanceThreshold: Double = LLMSettings.default.ragRelevanceThreshold,
        isMemoryEnabled: Bool = true,
        plannerInvariants: [String]
    ) {
        self.backend = backend
        self.model = model
        self.temperature = temperature
        self.windowSize = windowSize
        self.isRAGEnabled = isRAGEnabled
        self.ragChunkingStrategy = ragChunkingStrategy
        self.isRAGPostFilteringEnabled = isRAGPostFilteringEnabled
        self.ragTopKBeforeFiltering = ragTopKBeforeFiltering
        self.ragTopKAfterFiltering = ragTopKAfterFiltering
        self.ragRelevanceThreshold = ragRelevanceThreshold
        self.isMemoryEnabled = isMemoryEnabled
        self.plannerInvariants = plannerInvariants
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedBackend = try? container.decode(LLMBackendKind.self, forKey: .backend) {
            backend = decodedBackend
        } else {
            let rawBackend = try container.decodeIfPresent(String.self, forKey: .backend)
            backend = rawBackend.flatMap(LLMBackendKind.init(rawValue:)) ?? Self.default.backend
        }
        if let decodedModel = try? container.decode(LLMModel.self, forKey: .model) {
            model = decodedModel
        } else {
            let rawModel = try container.decodeIfPresent(String.self, forKey: .model)
            model = rawModel.flatMap(LLMModel.init(rawValue:)) ?? Self.default.model
        }
        temperature = try container.decode(Double.self, forKey: .temperature)
        windowSize = try container.decode(Int.self, forKey: .windowSize)
        isRAGEnabled = try container.decodeIfPresent(Bool.self, forKey: .isRAGEnabled) ?? Self.default.isRAGEnabled
        ragChunkingStrategy = try container.decodeIfPresent(ChunkingStrategyType.self, forKey: .ragChunkingStrategy)
            ?? Self.default.ragChunkingStrategy
        isRAGPostFilteringEnabled = try container.decodeIfPresent(Bool.self, forKey: .isRAGPostFilteringEnabled)
            ?? Self.default.isRAGPostFilteringEnabled
        ragTopKBeforeFiltering = try container.decodeIfPresent(Int.self, forKey: .ragTopKBeforeFiltering)
            ?? Self.default.ragTopKBeforeFiltering
        ragTopKAfterFiltering = try container.decodeIfPresent(Int.self, forKey: .ragTopKAfterFiltering)
            ?? Self.default.ragTopKAfterFiltering
        ragRelevanceThreshold = try container.decodeIfPresent(Double.self, forKey: .ragRelevanceThreshold)
            ?? Self.default.ragRelevanceThreshold
        isMemoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .isMemoryEnabled) ?? Self.default.isMemoryEnabled
        plannerInvariants = try container.decodeIfPresent([String].self, forKey: .plannerInvariants) ?? Self.default.plannerInvariants
    }
}

/// Метрика одного запроса в LLM.
struct RequestMetric: Identifiable, Codable, Equatable {
    let id: UUID
    let messageID: UUID
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
