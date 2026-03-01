import Combine
import Foundation

final class SessionInfoViewModel {
    @Published private(set) var snapshot = SessionInfoSnapshot(
        totalInputTokens: 0,
        totalOutputTokens: 0,
        totalRequests: 0,
        lastLatencyMs: 0
    )

    private let sessionID: UUID
    private let collectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol

    init(sessionID: UUID, collectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol) {
        self.sessionID = sessionID
        self.collectSessionMetricsUseCase = collectSessionMetricsUseCase
    }

    func refresh() {
        Task { [weak self] in
            guard let self else { return }
            if let value = try? await self.collectSessionMetricsUseCase.execute(sessionID: self.sessionID) {
                self.snapshot = value
            }
        }
    }
}
