import Foundation

/// Контракт хранения состояния мокового task-агента.
protocol MockTaskAgentStateRepositoryProtocol {
    /// Загружает snapshot мокового агента.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Snapshot мокового агента или `nil`.
    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> MockTaskAgentSnapshot?

    /// Сохраняет snapshot мокового агента.
    /// - Parameter snapshot: Snapshot для сохранения.
    func saveSnapshot(_ snapshot: MockTaskAgentSnapshot) async throws
}

/// Контракт хранения состояния task-агента-счетчика.
protocol CounterTaskAgentStateRepositoryProtocol {
    /// Загружает snapshot агента-счетчика.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Snapshot агента-счетчика или `nil`.
    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentSnapshot?

    /// Сохраняет snapshot агента-счетчика.
    /// - Parameter snapshot: Snapshot для сохранения.
    func saveSnapshot(_ snapshot: CounterTaskAgentSnapshot) async throws
}
