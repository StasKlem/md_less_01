import Foundation

/// Редьюсер FSM планировщика отпуска.
protocol VacationPlannerReducerProtocol {
    /// Вычисляет переход FSM для входного события.
    /// - Parameters:
    ///   - snapshot: Текущий снимок состояния планировщика.
    ///   - event: Входное событие.
    /// - Returns: Результат перехода в следующее состояние.
    func reduce(
        snapshot: VacationPlanningSnapshot,
        event: VacationPlanningEvent
    ) -> VacationPlanningTransitionResult
}

/// Запускает сценарий планирования отпуска.
protocol StartVacationPlanningUseCaseProtocol {
    /// Инициирует FSM планировщика в указанной сессии.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Результат шага агента.
    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningTurnResult
}

/// Обрабатывает пользовательские события в сценарии планирования отпуска.
protocol HandleVacationPlanningEventUseCaseProtocol {
    /// Отправляет пользовательский ввод в оркестратор планировщика.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - userText: Пользовательский ввод.
    ///   - source: Источник ответа (чат или форма).
    /// - Returns: Результат шага агента.
    func execute(
        sessionID: UUID,
        branchID: UUID,
        userText: String,
        source: QuestionnaireAnswerSource
    ) async throws -> VacationPlanningTurnResult
}

extension HandleVacationPlanningEventUseCaseProtocol {
    /// Упрощенный вызов для ответов из чата.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - userText: Пользовательский ввод.
    /// - Returns: Результат шага агента.
    func execute(
        sessionID: UUID,
        branchID: UUID,
        userText: String
    ) async throws -> VacationPlanningTurnResult {
        try await execute(
            sessionID: sessionID,
            branchID: branchID,
            userText: userText,
            source: .chat
        )
    }
}

/// Читает текущее состояние планировщика отпуска.
protocol GetVacationPlanningStatusUseCaseProtocol {
    /// Возвращает снимок состояния FSM для сессии и ветки.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Снимок состояния планировщика.
    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningSnapshot
}

/// Финализирует и сохраняет итоговый план отпуска.
protocol FinalizeVacationPlanUseCaseProtocol {
    /// Возвращает финальный план, если FSM завершен корректно.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Итоговый план отпуска.
    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlan
}

/// Получает список MCP tools, используемых планировщиком отпуска.
protocol FetchVacationPlannerMCPToolsUseCaseProtocol {
    /// Возвращает текстовое сообщение со списком доступных MCP tools.
    /// - Returns: Текст для показа в UI.
    func execute() async -> String
}
