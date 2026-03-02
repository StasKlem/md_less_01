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
    private var activeBranchID: UUID
    private let collectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol

    init(
        sessionID: UUID,
        activeBranchID: UUID,
        collectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol
    ) {
        self.sessionID = sessionID
        self.activeBranchID = activeBranchID
        self.collectSessionMetricsUseCase = collectSessionMetricsUseCase
    }

    func switchActiveBranch(to branchID: UUID) {
        activeBranchID = branchID
    }

    func refresh() {
        Task { [weak self] in
            guard let self else { return }
            if let value = try? await self.collectSessionMetricsUseCase.execute(
                sessionID: self.sessionID,
                branchID: self.activeBranchID
            ) {
                self.snapshot = value
            }
        }
    }
}
