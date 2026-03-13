import Foundation

/// Отправляет пользовательское сообщение в LLM-пайплайн и возвращает итоговый ответ ассистента.
protocol SendMessageUseCaseProtocol {
    /// Выполняет полный цикл отправки сообщения и генерации ответа.
    /// - Parameters:
    ///   - sessionID: Идентификатор чат-сессии.
    ///   - branchID: Идентификатор активной ветки диалога.
    ///   - userText: Текст пользовательского сообщения.
    ///   - assistantInstruction: Дополнительная системная инструкция для ассистента.
    /// - Returns: Сообщение ассистента, сохраненное в истории.
    func execute(
        sessionID: UUID,
        branchID: UUID,
        userText: String,
        assistantInstruction: String?
    ) async throws -> ChatMessage
}

extension SendMessageUseCaseProtocol {
    /// Упрощенный вызов без дополнительной инструкции ассистенту.
    /// - Parameters:
    ///   - sessionID: Идентификатор чат-сессии.
    ///   - branchID: Идентификатор активной ветки диалога.
    ///   - userText: Текст пользовательского сообщения.
    /// - Returns: Сообщение ассистента, сохраненное в истории.
    func execute(sessionID: UUID, branchID: UUID, userText: String) async throws -> ChatMessage {
        try await execute(
            sessionID: sessionID,
            branchID: branchID,
            userText: userText,
            assistantInstruction: nil
        )
    }
}

/// Собирает контекст памяти для очередного запроса в LLM.
protocol BuildMemoryContextUseCaseProtocol {
    /// Формирует короткую, рабочую и долговременную память в единую структуру.
    /// - Parameters:
    ///   - sessionID: Идентификатор чат-сессии.
    ///   - branchID: Идентификатор активной ветки диалога.
    ///   - settings: Текущие настройки модели.
    /// - Returns: Сформированный memory context.
    func execute(sessionID: UUID, branchID: UUID, settings: LLMSettings) async throws -> MemoryContext
}

/// Читает историю сообщений выбранной ветки.
protocol FetchMessagesUseCaseProtocol {
    /// Возвращает сообщения ветки в порядке хранения.
    /// - Parameter branchID: Идентификатор ветки.
    /// - Returns: Массив сообщений.
    func execute(branchID: UUID) async throws -> [ChatMessage]
}

/// Обновляет short-term memory на основе последних сообщений.
protocol UpdateShortTermMemoryUseCaseProtocol {
    /// Пересчитывает окно short-term memory и возвращает событие записи при изменениях.
    /// - Parameters:
    ///   - sessionID: Идентификатор чат-сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - windowSize: Размер окна последних сообщений.
    /// - Returns: Событие записи памяти или `nil`, если изменений нет.
    func execute(sessionID: UUID, branchID: UUID, windowSize: Int) async throws -> MemoryWriteEvent?
}

/// Обновляет рабочую память на основе последнего обмена сообщениями.
protocol UpdateWorkingMemoryUseCaseProtocol {
    /// Выделяет и сохраняет рабочие факты, а также резолвит закрытые элементы.
    /// - Parameters:
    ///   - sessionID: Идентификатор чат-сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - latestUserMessage: Последнее сообщение пользователя.
    ///   - latestAssistantMessage: Последний ответ ассистента.
    /// - Returns: Список событий записи в память.
    func execute(
        sessionID: UUID,
        branchID: UUID,
        latestUserMessage: String,
        latestAssistantMessage: String?
    ) async throws -> [MemoryWriteEvent]
}

/// Обновляет long-term memory на основе контекста и последнего пользовательского ввода.
protocol UpdateLongTermMemoryUseCaseProtocol {
    /// Извлекает долговременные факты и сохраняет их в репозиторий.
    /// - Parameters:
    ///   - sessionID: Идентификатор чат-сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - latestUserMessage: Последнее сообщение пользователя.
    ///   - settings: Текущие настройки модели.
    /// - Returns: Список событий записи в память.
    func execute(sessionID: UUID, branchID: UUID, latestUserMessage: String, settings: LLMSettings) async throws -> [MemoryWriteEvent]
}

/// Применяет настройки модели к текущей сессии.
protocol ApplySettingsUseCaseProtocol {
    /// Сохраняет обновленные настройки сессии.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - settings: Новые настройки LLM.
    func execute(sessionID: UUID, settings: LLMSettings) async throws
}

/// Загружает настройки модели для сессии.
protocol FetchSettingsUseCaseProtocol {
    /// Возвращает актуальные настройки LLM.
    /// - Parameter sessionID: Идентификатор сессии.
    /// - Returns: Настройки модели.
    func execute(sessionID: UUID) async throws -> LLMSettings
}

/// Собирает агрегированную статистику по сессии.
protocol CollectSessionMetricsUseCaseProtocol {
    /// Возвращает snapshot метрик по выбранной ветке.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Снимок метрик сессии.
    func execute(sessionID: UUID, branchID: UUID) async throws -> SessionInfoSnapshot
}

/// Загружает API key из защищенного хранилища.
protocol LoadAPIKeyUseCaseProtocol {
    /// Возвращает сохраненный API key, если он существует.
    /// - Returns: API key или `nil`.
    func execute() throws -> String?
}

/// Сохраняет или удаляет API key в защищенном хранилище.
protocol SaveAPIKeyUseCaseProtocol {
    /// Сохраняет API key.
    /// - Parameter apiKey: Ключ доступа к API.
    func execute(apiKey: String) throws
    /// Удаляет API key.
    func delete() throws
}

/// Обрабатывает ответ пользователя относительно схемы анкеты.
protocol ProcessUserAnswerUseCaseProtocol {
    /// Извлекает поля анкеты, валидирует и формирует следующий шаг.
    /// - Parameters:
    ///   - schema: Схема анкеты.
    ///   - currentState: Текущее состояние анкеты.
    ///   - currentSlots: Текущие слоты планирования.
    ///   - userText: Пользовательский ввод.
    ///   - settings: Настройки LLM.
    ///   - source: Источник ответа.
    /// - Returns: Результат обработки анкеты.
    func execute(
        schema: QuestionnaireSchema,
        currentState: QuestionnaireState,
        currentSlots: VacationSlots,
        userText: String,
        settings: LLMSettings,
        source: QuestionnaireAnswerSource
    ) async -> QuestionnaireProcessingResult
}
