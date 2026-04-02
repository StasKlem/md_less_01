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
struct ProjectGitBranchContext: Sendable {
    /// Текущая git-ветка или `nil`, если получить ее не удалось.
    let branch: String?
    /// Текст диагностики, если при получении ветки была ошибка или использован fallback.
    let diagnosticMessage: String?
}

/// Контекст со списком файлов проекта и диагностикой при проблемах получения.
struct ProjectFilesContext: Sendable {
    /// Относительные пути файлов проекта.
    let files: [String]
    /// Текст диагностики, если при получении списка файлов была ошибка или использован fallback.
    let diagnosticMessage: String?
}

/// Контекст со списком незакоммиченных изменений и unified diff.
struct ProjectUncommittedChangesContext: Sendable {
    /// Относительные пути файлов с незакоммиченными изменениями.
    let files: [String]
    /// Unified diff по рабочему дереву.
    let diff: String
    /// Текст диагностики, если при получении diff была ошибка или использован fallback.
    let diagnosticMessage: String?
}

protocol ProjectGitBranchServiceProtocol {
    /// Возвращает текущую git-ветку проекта.
    /// - Parameter serverURL: URL MCP-сервера.
    /// - Returns: Контекст с веткой и диагностикой.
    func fetchCurrentGitBranch(serverURL: URL) async throws -> ProjectGitBranchContext

    /// Возвращает список файлов проекта через MCP.
    /// - Parameter serverURL: URL MCP-сервера.
    /// - Returns: Контекст со списком файлов и диагностикой.
    func fetchProjectFiles(serverURL: URL) async throws -> ProjectFilesContext

    /// Возвращает список незакоммиченных файлов и unified diff через MCP.
    /// - Parameter serverURL: URL MCP-сервера.
    /// - Returns: Контекст со списком файлов, diff и диагностикой.
    func fetchUncommittedChanges(serverURL: URL) async throws -> ProjectUncommittedChangesContext
}
