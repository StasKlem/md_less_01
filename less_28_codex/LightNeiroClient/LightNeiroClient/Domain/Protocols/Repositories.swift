import Foundation

/// Контракт репозитория сообщений чата.
protocol MessageRepositoryProtocol {
    /// Загружает все сообщения глобального диалога.
    /// - Returns: Список сообщений.
    func fetchMessages() async throws -> [ChatMessage]
    /// Сохраняет сообщение.
    /// - Parameter message: Сообщение для сохранения.
    func saveMessage(_ message: ChatMessage) async throws
    /// Полностью очищает историю сообщений.
    func clearAll() async throws
}
extension MessageRepositoryProtocol {
    func clearAll() async throws {}
}

/// Контракт хранения short-term memory.
protocol ShortTermMemoryRepositoryProtocol {
    /// Загружает снимок short-term memory глобального диалога.
    func fetchSnapshot() async throws -> ShortTermMemorySnapshot?
    /// Сохраняет снимок short-term memory.
    /// - Parameter snapshot: Снимок для сохранения.
    func saveSnapshot(_ snapshot: ShortTermMemorySnapshot) async throws
    /// Очищает short-term memory.
    func clear() async throws
}

/// Контракт хранения рабочей памяти.
protocol WorkingMemoryRepositoryProtocol {
    /// Загружает активные элементы рабочей памяти глобального диалога.
    func fetchActive() async throws -> [WorkingMemoryItem]
    /// Обновляет или добавляет элементы рабочей памяти.
    /// - Parameter items: Элементы для upsert-операции.
    func upsert(items: [WorkingMemoryItem]) async throws
    /// Помечает указанные ключи как resolved.
    /// - Parameter keys: Ключи для резолва.
    func resolve(keys: [String]) async throws
    /// Полностью очищает рабочую память.
    func clearAll() async throws
}
extension WorkingMemoryRepositoryProtocol {
    func clearAll() async throws {}
}

/// Контракт хранения long-term memory.
protocol LongTermMemoryRepositoryProtocol {
    /// Загружает элементы long-term memory с optional фильтрацией по namespace.
    /// - Parameter namespaces: Список namespace для фильтрации или `nil`.
    /// - Returns: Список элементов long-term memory.
    func fetch(namespaces: [LongTermMemoryNamespace]?) async throws -> [LongTermMemoryItem]
    /// Обновляет или добавляет элементы long-term memory.
    /// - Parameter items: Элементы для сохранения.
    func upsert(items: [LongTermMemoryItem]) async throws
    /// Удаляет элементы long-term memory по ключам.
    /// - Parameter keys: Ключи для удаления.
    func delete(keys: [String]) async throws
    /// Полностью очищает long-term memory.
    func clearAll() async throws
}
extension LongTermMemoryRepositoryProtocol {
    func clearAll() async throws {}
}

/// Контракт хранения sticky-фактов.
protocol FactsRepositoryProtocol {
    /// Загружает sticky-факты.
    func fetchFacts() async throws -> [StickyFact]
    /// Обновляет или добавляет sticky-факты.
    func upsertFacts(facts: [StickyFact]) async throws
}

/// Контракт хранения пользовательских настроек LLM.
protocol SettingsRepositoryProtocol {
    /// Загружает настройки.
    /// - Returns: Настройки модели.
    func fetchSettings() async throws -> LLMSettings
    /// Сохраняет настройки.
    /// - Parameter settings: Настройки модели для сохранения.
    func saveSettings(settings: LLMSettings) async throws
}

/// Контракт хранения метрик запросов.
protocol MetricsRepositoryProtocol {
    /// Добавляет метрику запроса.
    /// - Parameter metric: Метрика запроса.
    func appendMetric(_ metric: RequestMetric) async throws
    /// Загружает все метрики.
    /// - Returns: Список метрик.
    func fetchMetrics() async throws -> [RequestMetric]
    /// Полностью очищает метрики.
    func clearAll() async throws
}
extension MetricsRepositoryProtocol {
    func clearAll() async throws {}
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
