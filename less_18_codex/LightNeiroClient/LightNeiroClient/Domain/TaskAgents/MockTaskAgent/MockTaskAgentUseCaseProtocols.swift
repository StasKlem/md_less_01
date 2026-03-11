import Foundation

/// Запускает моковый task-агент.
protocol StartMockTaskAgentUseCaseProtocol {
    /// Инициирует моковый агент для сессии и ветки.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Результат шага агента.
    func execute(sessionID: UUID, branchID: UUID) async throws -> MockTaskAgentTurnResult
}

/// Обрабатывает пользовательский ввод в моковом task-агенте.
protocol HandleMockTaskAgentEventUseCaseProtocol {
    /// Передает текст пользователя в моковый агент.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - userText: Пользовательский текст.
    /// - Returns: Результат шага агента.
    func execute(sessionID: UUID, branchID: UUID, userText: String) async throws -> MockTaskAgentTurnResult
}

/// Загружает текущее состояние мокового task-агента.
protocol GetMockTaskAgentStatusUseCaseProtocol {
    /// Возвращает сохраненный snapshot мокового агента или значение по умолчанию.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Snapshot текущего состояния.
    func execute(sessionID: UUID, branchID: UUID) async throws -> MockTaskAgentSnapshot
}

/// Запускает task-агент-счетчик.
protocol StartCounterTaskAgentUseCaseProtocol {
    /// Инициирует агент для сессии и ветки.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - intervalSeconds: Интервал отправки сообщений в секундах.
    /// - Returns: Результат шага агента.
    func execute(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval?) async throws -> CounterTaskAgentTurnResult
}

/// Останавливает task-агент-счетчик.
protocol StopCounterTaskAgentUseCaseProtocol {
    /// Переводит агент в idle.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Результат шага агента.
    func execute(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentTurnResult
}

/// Изменяет интервал task-агента-счетчика.
protocol ConfigureCounterTaskAgentIntervalUseCaseProtocol {
    /// Устанавливает новый интервал отправки.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - intervalSeconds: Интервал в секундах.
    /// - Returns: Результат шага агента.
    func execute(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval) async throws -> CounterTaskAgentTurnResult
}

/// Выполняет тик task-агента-счетчика.
protocol TickCounterTaskAgentUseCaseProtocol {
    /// Инкрементирует счетчик и возвращает системное сообщение с номером.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Результат шага агента.
    func execute(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentTurnResult
}

/// Загружает текущее состояние task-агента-счетчика.
protocol GetCounterTaskAgentStatusUseCaseProtocol {
    /// Возвращает snapshot агента или значение по умолчанию.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Snapshot текущего состояния.
    func execute(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentSnapshot
}
