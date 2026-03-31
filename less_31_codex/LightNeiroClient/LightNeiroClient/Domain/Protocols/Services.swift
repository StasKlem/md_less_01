import Foundation

/// Модель запроса к LLM-клиенту.
struct LLMRequest {
    /// Системный промпт для модели.
    let systemPrompt: String
    /// Структурированная память задачи с целью, уточнениями и ограничениями.
    let taskState: TaskStateMemory?
    /// Короткий контекст переписки.
    let shortTermMessages: [ChatMessage]
    /// Текущие элементы рабочей памяти.
    let workingMemory: [WorkingMemoryItem]
    /// Долговременные элементы памяти.
    let longTermMemory: [LongTermMemoryItem]
    /// Настройки модели.
    let settings: LLMSettings

    init(
        systemPrompt: String,
        shortTermMessages: [ChatMessage],
        workingMemory: [WorkingMemoryItem],
        longTermMemory: [LongTermMemoryItem],
        settings: LLMSettings,
        taskState: TaskStateMemory? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.taskState = taskState
        self.shortTermMessages = shortTermMessages
        self.workingMemory = workingMemory
        self.longTermMemory = longTermMemory
        self.settings = settings
    }
}

/// Модель ответа от LLM-клиента.
struct LLMResponse {
    /// Текст ответа модели.
    let content: String
    /// Количество токенов во входе.
    let inputTokens: Int
    /// Количество токенов в выходе.
    let outputTokens: Int
    /// Полная задержка запроса в миллисекундах.
    let latencyMs: Int
}

/// Контракт клиента для отправки запросов в LLM-провайдер.
protocol LLMClientProtocol {
    /// Отправляет запрос в LLM и возвращает результат генерации.
    /// - Parameter request: Подготовленный запрос.
    /// - Returns: Ответ модели с метаданными токенов и задержки.
    func send(request: LLMRequest) async throws -> LLMResponse
}

/// Контракт сборщика memory context.
protocol ContextBuilderProtocol {
    /// Формирует контекст памяти по сессии и ветке.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - settings: Текущие настройки модели.
    /// - Returns: Сформированный memory context.
    func buildContext(
        sessionID: UUID,
        branchID: UUID,
        settings: LLMSettings
    ) async throws -> MemoryContext
}

/// Контракт защищенного хранилища API ключа.
protocol APIKeyStoreProtocol {
    /// Загружает API key из защищенного хранилища.
    /// - Returns: API key или `nil`, если ключ не сохранен.
    nonisolated func fetchAPIKey() throws -> String?
    /// Сохраняет API key в защищенном хранилище.
    /// - Parameter apiKey: Ключ доступа к API.
    nonisolated func saveAPIKey(_ apiKey: String) throws
    /// Удаляет API key из защищенного хранилища.
    nonisolated func deleteAPIKey() throws
}

/// Контракт сервиса получения контекста проекта через MCP.
protocol ProjectGitBranchServiceProtocol {
    /// Возвращает текущую git-ветку проекта.
    /// - Parameter serverURL: URL MCP-сервера.
    /// - Returns: Имя текущей ветки.
    func fetchCurrentGitBranch(serverURL: URL) async throws -> String

    /// Возвращает список файлов проекта через MCP.
    /// - Parameter serverURL: URL MCP-сервера.
    /// - Returns: Список относительных путей файлов проекта.
    func fetchProjectFiles(serverURL: URL) async throws -> [String]
}
