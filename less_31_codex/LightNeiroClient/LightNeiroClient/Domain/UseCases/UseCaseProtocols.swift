import Foundation

/// Отправляет пользовательское сообщение в LLM-пайплайн и возвращает итоговый ответ ассистента.
protocol SendMessageUseCaseProtocol {
    /// Выполняет полный цикл отправки сообщения и генерации ответа.
    /// - Parameters:
    ///   - userText: Текст пользовательского сообщения.
    ///   - assistantInstruction: Дополнительная системная инструкция для ассистента.
    /// - Returns: Сообщение ассистента, сохраненное в истории.
    func execute(
        userText: String,
        assistantInstruction: String?
    ) async throws -> ChatMessage
}

extension SendMessageUseCaseProtocol {
    /// Упрощенный вызов без дополнительной инструкции ассистенту.
    /// - Parameters:
    ///   - userText: Текст пользовательского сообщения.
    /// - Returns: Сообщение ассистента, сохраненное в истории.
    func execute(userText: String) async throws -> ChatMessage {
        try await execute(
            userText: userText,
            assistantInstruction: nil
        )
    }
}

/// Собирает контекст памяти для очередного запроса в LLM.
protocol BuildMemoryContextUseCaseProtocol {
    /// Формирует короткую, рабочую и долговременную память в единую структуру.
    /// - Parameters:
    ///   - settings: Текущие настройки модели.
    /// - Returns: Сформированный memory context.
    func execute(settings: LLMSettings) async throws -> MemoryContext
}

/// Читает историю сообщений выбранной ветки.
protocol FetchMessagesUseCaseProtocol {
    /// Возвращает сообщения глобального диалога в порядке хранения.
    /// - Returns: Массив сообщений.
    func execute() async throws -> [ChatMessage]
}

/// Очищает историю глобального диалога и связанные слои памяти.
protocol ClearDialogUseCaseProtocol {
    /// Выполняет полную очистку диалога.
    func execute() async throws
}

/// Обновляет short-term memory на основе последних сообщений.
protocol UpdateShortTermMemoryUseCaseProtocol {
    /// Пересчитывает окно short-term memory и возвращает событие записи при изменениях.
    /// - Parameters:
    ///   - windowSize: Размер окна последних сообщений.
    /// - Returns: Событие записи памяти или `nil`, если изменений нет.
    func execute(windowSize: Int) async throws -> MemoryWriteEvent?
}

/// Обновляет рабочую память на основе последнего обмена сообщениями.
protocol UpdateWorkingMemoryUseCaseProtocol {
    /// Выделяет и сохраняет рабочие факты, а также резолвит закрытые элементы.
    /// - Parameters:
    ///   - latestUserMessage: Последнее сообщение пользователя.
    ///   - latestAssistantMessage: Последний ответ ассистента.
    /// - Returns: Список событий записи в память.
    func execute(
        latestUserMessage: String,
        latestAssistantMessage: String?
    ) async throws -> [MemoryWriteEvent]
}

/// Обновляет long-term memory на основе контекста и последнего пользовательского ввода.
protocol UpdateLongTermMemoryUseCaseProtocol {
    /// Извлекает долговременные факты и сохраняет их в репозиторий.
    /// - Parameters:
    ///   - latestUserMessage: Последнее сообщение пользователя.
    ///   - settings: Текущие настройки модели.
    /// - Returns: Список событий записи в память.
    func execute(latestUserMessage: String, settings: LLMSettings) async throws -> [MemoryWriteEvent]
}

/// Применяет настройки модели к текущей сессии.
protocol ApplySettingsUseCaseProtocol {
    /// Сохраняет обновленные настройки сессии.
    /// - Parameters:
    ///   - settings: Новые настройки LLM.
    func execute(settings: LLMSettings) async throws
}

/// Загружает настройки модели для сессии.
protocol FetchSettingsUseCaseProtocol {
    /// Возвращает актуальные настройки LLM.
    /// - Returns: Настройки модели.
    func execute() async throws -> LLMSettings
}

/// Очищает хранилище embeddings RAG.
protocol ResetRAGEmbeddingsUseCaseProtocol {
    /// Удаляет все векторные записи embeddings из RAG-индекса.
    func execute() async throws
}

/// Собирает агрегированную статистику по сессии.
protocol CollectSessionMetricsUseCaseProtocol {
    /// Возвращает snapshot метрик глобального диалога.
    /// - Returns: Снимок метрик сессии.
    func execute() async throws -> SessionInfoSnapshot
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
