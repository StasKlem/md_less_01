import Foundation

final class ApplySettingsUseCase: ApplySettingsUseCaseProtocol {
    private let settingsRepository: SettingsRepositoryProtocol

    /// Создаёт use case сохранения настроек сессии.
    init(settingsRepository: SettingsRepositoryProtocol) {
        self.settingsRepository = settingsRepository
    }

    /// Сохраняет настройки модели и контекста.
    func execute(settings: LLMSettings) async throws {
        try await settingsRepository.saveSettings(settings: settings)
    }
}

final class FetchSettingsUseCase: FetchSettingsUseCaseProtocol {
    private let settingsRepository: SettingsRepositoryProtocol

    /// Создаёт use case загрузки настроек сессии.
    init(settingsRepository: SettingsRepositoryProtocol) {
        self.settingsRepository = settingsRepository
    }

    /// Возвращает актуальные настройки LLM.
    func execute() async throws -> LLMSettings {
        try await settingsRepository.fetchSettings()
    }
}

final class ResetRAGEmbeddingsUseCase: ResetRAGEmbeddingsUseCaseProtocol {
    private let ragUseCaseFacade: RAGUseCaseFacadeProtocol
    private let ragIndexReadinessRepository: RAGIndexReadinessRepositoryProtocol

    /// Создает use case очистки embeddings-индекса RAG.
    init(
        ragUseCaseFacade: RAGUseCaseFacadeProtocol,
        ragIndexReadinessRepository: RAGIndexReadinessRepositoryProtocol
    ) {
        self.ragUseCaseFacade = ragUseCaseFacade
        self.ragIndexReadinessRepository = ragIndexReadinessRepository
    }

    /// Полностью очищает текущее хранилище embeddings RAG.
    func execute() async throws {
        try await ragUseCaseFacade.resetIndex()
        ragIndexReadinessRepository.clearAll()
    }
}

final class CollectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol {
    private let metricsRepository: MetricsRepositoryProtocol

    /// Создаёт use case агрегирования метрик глобального диалога.
    init(metricsRepository: MetricsRepositoryProtocol) {
        self.metricsRepository = metricsRepository
    }

    /// Возвращает сводку метрик по всему диалогу.
    func execute() async throws -> SessionInfoSnapshot {
        let metrics = try await metricsRepository.fetchMetrics()
        let totalIn = metrics.reduce(0) { $0 + $1.inputTokens }
        let totalOut = metrics.reduce(0) { $0 + $1.outputTokens }
        let lastLatency = metrics.last?.latencyMs ?? 0

        return SessionInfoSnapshot(
            totalInputTokens: totalIn,
            totalOutputTokens: totalOut,
            totalRequests: metrics.count,
            lastLatencyMs: lastLatency
        )
    }
}

final class LoadAPIKeyUseCase: LoadAPIKeyUseCaseProtocol {
    private let apiKeyStore: APIKeyStoreProtocol

    /// Создаёт use case чтения API-ключа из безопасного хранилища.
    init(apiKeyStore: APIKeyStoreProtocol) {
        self.apiKeyStore = apiKeyStore
    }

    /// Читает API-ключ из Keychain.
    func execute() throws -> String? {
        try apiKeyStore.fetchAPIKey()
    }
}

final class SaveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol {
    private let apiKeyStore: APIKeyStoreProtocol

    /// Создаёт use case сохранения API-ключа в безопасное хранилище.
    init(apiKeyStore: APIKeyStoreProtocol) {
        self.apiKeyStore = apiKeyStore
    }

    /// Сохраняет API-ключ; если строка пустая после trim, удаляет ключ.
    func execute(apiKey: String) throws {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            try apiKeyStore.deleteAPIKey()
            return
        }
        try apiKeyStore.saveAPIKey(normalizedKey)
    }

    /// Явно удаляет API-ключ из Keychain.
    func delete() throws {
        try apiKeyStore.deleteAPIKey()
    }
}
