import Foundation

/// Контракт хранения состояния FSM планировщика отпуска.
protocol VacationPlanningStateRepositoryProtocol {
    /// Загружает snapshot планирования.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Snapshot планировщика или `nil`.
    func fetchSnapshot(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningSnapshot?

    /// Сохраняет snapshot планировщика.
    /// - Parameter snapshot: Snapshot для сохранения.
    func saveSnapshot(_ snapshot: VacationPlanningSnapshot) async throws
}

/// Контракт хранения финального плана отпуска.
protocol VacationPlanRepositoryProtocol {
    /// Загружает финальный план отпуска.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    /// - Returns: Финальный план или `nil`.
    func fetchFinalPlan(sessionID: UUID, branchID: UUID) async throws -> VacationPlan?

    /// Сохраняет финальный план.
    /// - Parameter plan: Финальный план для сохранения.
    func saveFinalPlan(_ plan: VacationPlan) async throws
}
