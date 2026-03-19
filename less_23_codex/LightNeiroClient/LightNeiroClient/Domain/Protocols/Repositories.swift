import Foundation

/// Контракт репозитория сессий чата.
protocol ChatSessionRepositoryProtocol {
    /// Загружает все доступные сессии.
    /// - Returns: Список сессий.
    func fetchAllSessions() async throws -> [ChatSession]
    /// Ищет сессию по идентификатору.
    /// - Parameter id: Идентификатор сессии.
    /// - Returns: Найденная сессия или `nil`.
    func fetchSession(id: UUID) async throws -> ChatSession?
    /// Сохраняет новую или обновленную сессию.
    /// - Parameter session: Модель сессии для сохранения.
    func saveSession(_ session: ChatSession) async throws
}

/// Контракт репозитория веток и чекпоинтов.
protocol BranchRepositoryProtocol {
    /// Загружает ветки, относящиеся к сессии.
    /// - Parameter sessionID: Идентификатор сессии.
    /// - Returns: Список веток.
    func fetchBranches(sessionID: UUID) async throws -> [ChatBranch]
    /// Загружает чекпоинты конкретной ветки.
    /// - Parameter branchID: Идентификатор ветки.
    /// - Returns: Список чекпоинтов.
    func fetchCheckpoints(branchID: UUID) async throws -> [ChatCheckpoint]
    /// Сохраняет ветку.
    /// - Parameter branch: Ветка для сохранения.
    func saveBranch(_ branch: ChatBranch) async throws
    /// Сохраняет чекпоинт.
    /// - Parameter checkpoint: Чекпоинт для сохранения.
    func saveCheckpoint(_ checkpoint: ChatCheckpoint) async throws
}

/// Контракт репозитория сообщений чата.
protocol MessageRepositoryProtocol {
    /// Загружает все сообщения указанной ветки.
    /// - Parameter branchID: Идентификатор ветки.
    /// - Returns: Список сообщений.
    func fetchMessages(branchID: UUID) async throws -> [ChatMessage]
    /// Сохраняет сообщение.
    /// - Parameter message: Сообщение для сохранения.
    func saveMessage(_ message: ChatMessage) async throws
}

/// Контракт хранения short-term memory.
protocol ShortTermMemoryRepositoryProtocol {
    /// Загружает снимок short-term memory.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Снимок памяти или `nil`.
    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> ShortTermMemorySnapshot?
    /// Сохраняет снимок short-term memory.
    /// - Parameter snapshot: Снимок для сохранения.
    func saveSnapshot(_ snapshot: ShortTermMemorySnapshot) async throws
    /// Очищает short-term memory для указанной ветки.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    func clear(sessionID: UUID, branchID: UUID) async throws
}

/// Контракт хранения рабочей памяти.
protocol WorkingMemoryRepositoryProtocol {
    /// Загружает активные элементы рабочей памяти.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Активные элементы рабочей памяти.
    func fetchActive(sessionID: UUID, branchID: UUID) async throws -> [WorkingMemoryItem]
    /// Обновляет или добавляет элементы рабочей памяти.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - items: Элементы для upsert-операции.
    func upsert(sessionID: UUID, branchID: UUID, items: [WorkingMemoryItem]) async throws
    /// Помечает указанные ключи как resolved.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - keys: Ключи для резолва.
    func resolve(sessionID: UUID, branchID: UUID, keys: [String]) async throws
}

/// Контракт хранения long-term memory.
protocol LongTermMemoryRepositoryProtocol {
    /// Загружает элементы long-term memory с optional фильтрацией по namespace.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - namespaces: Список namespace для фильтрации или `nil`.
    /// - Returns: Список элементов long-term memory.
    func fetch(sessionID: UUID, namespaces: [LongTermMemoryNamespace]?) async throws -> [LongTermMemoryItem]
    /// Обновляет или добавляет элементы long-term memory.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - items: Элементы для сохранения.
    func upsert(sessionID: UUID, items: [LongTermMemoryItem]) async throws
    /// Удаляет элементы long-term memory по ключам.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - keys: Ключи для удаления.
    func delete(sessionID: UUID, keys: [String]) async throws
}

/// Контракт хранения sticky-фактов.
protocol FactsRepositoryProtocol {
    /// Загружает факты сессии.
    /// - Parameter sessionID: Идентификатор сессии.
    /// - Returns: Список фактов.
    func fetchFacts(sessionID: UUID) async throws -> [StickyFact]
    /// Обновляет или добавляет факты сессии.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - facts: Факты для сохранения.
    func upsertFacts(sessionID: UUID, facts: [StickyFact]) async throws
}

/// Контракт хранения пользовательских настроек LLM.
protocol SettingsRepositoryProtocol {
    /// Загружает настройки сессии.
    /// - Parameter sessionID: Идентификатор сессии.
    /// - Returns: Настройки модели.
    func fetchSettings(sessionID: UUID) async throws -> LLMSettings
    /// Сохраняет настройки сессии.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - settings: Настройки модели для сохранения.
    func saveSettings(sessionID: UUID, settings: LLMSettings) async throws
}

/// Контракт хранения метрик запросов.
protocol MetricsRepositoryProtocol {
    /// Добавляет метрику запроса.
    /// - Parameter metric: Метрика запроса.
    func appendMetric(_ metric: RequestMetric) async throws
    /// Загружает метрики сессии.
    /// - Parameter sessionID: Идентификатор сессии.
    /// - Returns: Список метрик.
    func fetchMetrics(sessionID: UUID) async throws -> [RequestMetric]
}

/// Контракт хранения признака готовности RAG-индекса.
protocol RAGIndexReadinessRepositoryProtocol {
    /// Возвращает `true`, если для стратегии зафиксирован готовый индекс.
    func isReady(for strategy: ChunkingStrategyType) -> Bool
    /// Помечает стратегию как имеющую готовый индекс.
    func markReady(for strategy: ChunkingStrategyType)
    /// Сбрасывает признаки готовности для всех стратегий.
    func clearAll()
}
