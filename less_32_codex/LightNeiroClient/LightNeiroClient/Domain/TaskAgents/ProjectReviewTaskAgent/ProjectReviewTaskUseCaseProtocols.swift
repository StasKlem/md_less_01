import Foundation

/// Запускает review-task для незакоммиченных изменений.
protocol StartProjectReviewTaskUseCaseProtocol {
    /// Выполняет review-task для указанной сессии и ветки.
    /// - Parameters:
    ///   - sessionID: Идентификатор сессии.
    ///   - branchID: Идентификатор ветки.
    ///   - focus: Дополнительный фокус ревью, переданный пользователем после `/help`.
    /// - Returns: Итоговый snapshot и текст ревью.
    func execute(
        sessionID: UUID,
        branchID: UUID,
        focus: String?
    ) async -> ProjectReviewTaskTurnResult
}
