import Combine
import Foundation

/// ViewModel панели агрегированных метрик по активной ветке.
final class SessionInfoViewModel {
    @Published private(set) var snapshot = SessionInfoSnapshot(
        totalInputTokens: 0,
        totalOutputTokens: 0,
        totalRequests: 0,
        lastLatencyMs: 0
    )

    private let session: ChatSession
    private let collectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol

    /// Создаёт ViewModel метрик для конкретной сессии и активной ветки.
    init(
        session: ChatSession,
        collectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol
    ) {
        self.session = session
        self.collectSessionMetricsUseCase = collectSessionMetricsUseCase
    }

    /// Запрашивает и публикует актуальный snapshot метрик для текущей ветки.
    func refresh() {
        Task { [weak self] in
            guard let self else { return }
            if let value = try? await self.collectSessionMetricsUseCase.execute(
                sessionID: self.session.id,
                branchID: self.session.activeBranchID
            ) {
                self.snapshot = value
            }
        }
    }
}
