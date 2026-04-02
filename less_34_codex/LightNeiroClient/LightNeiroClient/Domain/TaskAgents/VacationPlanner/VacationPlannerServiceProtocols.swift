import Foundation

/// Результат извлечения слотов отпуска из пользовательского ввода.
struct VacationSlotsExtractionResult: Equatable {
    /// Извлеченные слоты отпуска.
    let slots: VacationSlots
    /// Ошибки валидации извлеченных данных.
    let validationErrors: [String]
}

/// Контракт сервиса извлечения слотов отпуска.
protocol VacationSlotExtractionServiceProtocol {
    /// Извлекает слоты из пользовательского текста с учетом текущего контекста.
    /// - Parameters:
    ///   - userText: Текст пользователя.
    ///   - current: Текущие слоты.
    /// - Returns: Извлеченные слоты и ошибки валидации.
    func extractSlots(from userText: String, current: VacationSlots) async throws -> VacationSlotsExtractionResult
}

/// Контракт сервиса генерации вариантов отпуска.
protocol VacationOptionGenerationServiceProtocol {
    /// Генерирует варианты отпуска на основе текущего контекста.
    /// - Parameter context: Контекст планирования.
    /// - Returns: Список вариантов отпуска.
    func generateOptions(context: VacationPlanningContext) async throws -> [VacationOption]
}

/// Контракт сервиса построения маршрута отпуска.
protocol VacationItineraryServiceProtocol {
    /// Формирует маршрут поездки на основе контекста планирования.
    /// - Parameter context: Контекст планирования.
    /// - Returns: Построенный маршрут.
    func generateItinerary(context: VacationPlanningContext) async throws -> VacationItinerary
}

/// Контракт сервиса оценки бюджета отпуска.
protocol VacationBudgetEstimatorProtocol {
    /// Рассчитывает бюджет поездки по контексту планирования.
    /// - Parameter context: Контекст планирования.
    /// - Returns: Детализированная структура бюджета.
    func estimateBudget(context: VacationPlanningContext) async throws -> VacationBudgetBreakdown
}

/// Контекст для генерации следующего вопроса анкеты.
struct QuestionnaireQuestionContext {
    /// Схема анкеты.
    let schema: QuestionnaireSchema
    /// Текущее состояние анкеты.
    let state: QuestionnaireState
    /// Последнее сообщение пользователя.
    let latestUserMessage: String?
    /// Настройки LLM.
    let settings: LLMSettings
}

/// Контракт сервиса генерации вопроса пользователю.
protocol QuestionGenerationServiceProtocol {
    /// Генерирует следующий вопрос анкеты.
    /// - Parameters:
    ///   - context: Контекст анкеты.
    ///   - targetField: Целевое поле, которое требуется уточнить.
    ///   - toneHints: Подсказки по тону ответа.
    /// - Returns: Подготовленный вопрос.
    func generateQuestion(
        context: QuestionnaireQuestionContext,
        targetField: QuestionnaireFieldDefinition?,
        toneHints: [String]
    ) async throws -> QuestionPrompt
}

/// Контракт сервиса извлечения структурированных полей из текста.
protocol AnswerExtractionServiceProtocol {
    /// Извлекает поля анкеты из пользовательского ввода.
    /// - Parameters:
    ///   - userText: Текст пользователя.
    ///   - schema: Схема анкеты.
    ///   - currentState: Текущее состояние анкеты.
    ///   - settings: Настройки LLM.
    /// - Returns: Извлеченные поля и предупреждения.
    func extractFields(
        userText: String,
        schema: QuestionnaireSchema,
        currentState: QuestionnaireState,
        settings: LLMSettings
    ) async throws -> QuestionnaireExtractionResult
}

/// Краткая информация о доступном MCP tool.
struct MCPToolSummary: Equatable {
    /// Имя MCP-инструмента.
    let name: String
    /// Описание MCP-инструмента.
    let description: String?
}

/// Контракт сервиса discovery MCP инструментов.
protocol MCPToolDiscoveryServiceProtocol {
    /// Получает список tools для MCP-сервера.
    /// - Parameter serverURL: URL/endpoint MCP-сервера.
    /// - Returns: Список доступных инструментов.
    func fetchTools(serverURL: URL) async throws -> [MCPToolSummary]
}

/// Контракт сервиса получения погоды через MCP.
protocol MCPWeatherServiceProtocol {
    /// Запрашивает текущую погоду в выбранном городе.
    /// - Parameters:
    ///   - serverURL: URL/endpoint MCP-сервера.
    ///   - city: Город для погодного запроса.
    ///   - units: Система единиц измерения.
    ///   - language: Язык описания погоды.
    /// - Returns: Текстовое описание текущей погоды.
    func fetchCurrentWeather(
        serverURL: URL,
        city: String,
        units: String,
        language: String?
    ) async throws -> String
}
