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
