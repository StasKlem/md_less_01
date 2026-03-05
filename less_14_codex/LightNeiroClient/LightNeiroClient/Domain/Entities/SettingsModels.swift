import Foundation

/// Список поддерживаемых LLM-моделей.
enum LLMModel: String, CaseIterable, Codable {
    case deepseekV32 = "deepseek/deepseek-v3.2"
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
}

/// Способ формирования контекста для запроса к модели.
enum ContextStrategy: String, CaseIterable, Codable {
    // Полный контекст ветки (без system-сообщений).
    case normal
    // Последние N сообщений ветки.
    case slidingWindow
    // Последние N сообщений + sticky facts на уровне сессии.
    case stickyFacts
}

/// Режим пользовательского префикса, который добавляется к каждому сообщению.
enum UserPromptProfile: String, CaseIterable, Codable {
    case auto
    case profile1
    case profile2
    case profile3

    var title: String {
        switch self {
        case .auto:
            return "авто"
        case .profile1:
            return "профиль 1"
        case .profile2:
            return "профиль 2"
        case .profile3:
            return "профиль 3"
        }
    }
}

/// Набор текстов профилей и активный профиль для префикса пользовательского сообщения.
struct UserPromptProfiles: Equatable {
    var selectedProfile: UserPromptProfile
    private(set) var textByProfile: [UserPromptProfile: String]

    static let `default` = UserPromptProfiles(
        selectedProfile: .auto,
        textByProfile: Dictionary(uniqueKeysWithValues: UserPromptProfile.allCases.map { ($0, "") })
    )

    init(selectedProfile: UserPromptProfile, textByProfile: [UserPromptProfile: String]) {
        self.selectedProfile = selectedProfile
        var merged = Dictionary(uniqueKeysWithValues: UserPromptProfile.allCases.map { ($0, "") })
        for (profile, text) in textByProfile {
            merged[profile] = text
        }
        self.textByProfile = merged
    }

    func text(for profile: UserPromptProfile) -> String {
        textByProfile[profile] ?? ""
    }

    mutating func setText(_ text: String, for profile: UserPromptProfile) {
        textByProfile[profile] = text
    }
}

/// Пользовательские настройки LLM и стратегии контекста на уровне сессии.
struct LLMSettings: Codable, Equatable {
    var model: LLMModel
    var contextStrategy: ContextStrategy
    var temperature: Double
    var windowSize: Int
    var contextStrategyByBranch: [UUID: ContextStrategy]
    var agentFlowSettings: AgentFlowSettings

    /// Значения настроек по умолчанию для новой сессии.
    static let `default` = LLMSettings(
        model: .deepseekV32,
        contextStrategy: .normal,
        temperature: 0.4,
        windowSize: 3,
        contextStrategyByBranch: [:],
        agentFlowSettings: .default
    )

    private enum CodingKeys: String, CodingKey {
        case model
        case contextStrategy
        case temperature
        case windowSize
        case contextStrategyByBranch
        case agentFlowSettings
    }

    init(
        model: LLMModel,
        contextStrategy: ContextStrategy,
        temperature: Double,
        windowSize: Int,
        contextStrategyByBranch: [UUID: ContextStrategy],
        agentFlowSettings: AgentFlowSettings
    ) {
        self.model = model
        self.contextStrategy = contextStrategy
        self.temperature = temperature
        self.windowSize = windowSize
        self.contextStrategyByBranch = contextStrategyByBranch
        self.agentFlowSettings = agentFlowSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(LLMModel.self, forKey: .model)
        contextStrategy = try container.decode(ContextStrategy.self, forKey: .contextStrategy)
        temperature = try container.decode(Double.self, forKey: .temperature)
        windowSize = try container.decode(Int.self, forKey: .windowSize)
        contextStrategyByBranch = try container.decodeIfPresent([UUID: ContextStrategy].self, forKey: .contextStrategyByBranch) ?? [:]
        agentFlowSettings = try container.decodeIfPresent(AgentFlowSettings.self, forKey: .agentFlowSettings) ?? .default
    }

    /// Возвращает стратегию для указанной ветки с fallback на общее значение.
    func contextStrategy(for branchID: UUID) -> ContextStrategy {
        // Если для ветки нет явной настройки, используем общее значение.
        contextStrategyByBranch[branchID] ?? contextStrategy
    }

    /// Устанавливает стратегию для указанной ветки и синхронизирует текущее значение UI.
    mutating func setContextStrategy(_ strategy: ContextStrategy, for branchID: UUID) {
        // Сохраняем стратегию отдельно для активной ветки.
        contextStrategyByBranch[branchID] = strategy
        // И синхронно обновляем "текущее" поле для корректного отображения в UI.
        contextStrategy = strategy
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
