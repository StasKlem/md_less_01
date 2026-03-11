import Foundation

final class StartMockTaskAgentUseCase: StartMockTaskAgentUseCaseProtocol {
    private let orchestrator: MockTaskAgentOrchestrator

    init(orchestrator: MockTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> MockTaskAgentTurnResult {
        try await orchestrator.start(sessionID: sessionID, branchID: branchID)
    }
}

final class HandleMockTaskAgentEventUseCase: HandleMockTaskAgentEventUseCaseProtocol {
    private let orchestrator: MockTaskAgentOrchestrator

    init(orchestrator: MockTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID, userText: String) async throws -> MockTaskAgentTurnResult {
        try await orchestrator.handle(
            sessionID: sessionID,
            branchID: branchID,
            userText: userText
        )
    }
}

final class GetMockTaskAgentStatusUseCase: GetMockTaskAgentStatusUseCaseProtocol {
    private let stateRepository: MockTaskAgentStateRepositoryProtocol

    init(stateRepository: MockTaskAgentStateRepositoryProtocol) {
        self.stateRepository = stateRepository
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> MockTaskAgentSnapshot {
        if let snapshot = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) {
            return snapshot
        }
        return MockTaskAgentSnapshot(
            schemaVersion: MockTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: .initial,
            updatedAt: Date()
        )
    }
}

final class MockTaskAgentOrchestrator {
    private let stateRepository: MockTaskAgentStateRepositoryProtocol

    init(stateRepository: MockTaskAgentStateRepositoryProtocol) {
        self.stateRepository = stateRepository
    }

    func start(sessionID: UUID, branchID: UUID) async throws -> MockTaskAgentTurnResult {
        let snapshot = MockTaskAgentSnapshot(
            schemaVersion: MockTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .awaitingTask,
            context: MockTaskAgentContext(
                latestTask: nil,
                checklist: [],
                updatedAt: Date()
            ),
            updatedAt: Date()
        )
        try await stateRepository.saveSnapshot(snapshot)
        return MockTaskAgentTurnResult(
            snapshot: snapshot,
            agentMessages: [
                "Mock Task Agent запущен.",
                "Опишите задачу, и я соберу тестовый чек-лист выполнения."
            ]
        )
    }

    func handle(sessionID: UUID, branchID: UUID, userText: String) async throws -> MockTaskAgentTurnResult {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let snapshot = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
            return MockTaskAgentTurnResult(
                snapshot: snapshot,
                agentMessages: ["Пустой ввод. Опишите задачу текстом."]
            )
        }

        if trimmed.lowercased() == "reset" {
            return try await start(sessionID: sessionID, branchID: branchID)
        }

        let checklist = buildChecklist(for: trimmed)
        let now = Date()
        let snapshot = MockTaskAgentSnapshot(
            schemaVersion: MockTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .taskPrepared,
            context: MockTaskAgentContext(
                latestTask: trimmed,
                checklist: checklist,
                updatedAt: now
            ),
            updatedAt: now
        )
        try await stateRepository.saveSnapshot(snapshot)

        let formattedChecklist = checklist
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        return MockTaskAgentTurnResult(
            snapshot: snapshot,
            agentMessages: [
                "Черновик задачи: \(trimmed)",
                "Чек-лист:\n\(formattedChecklist)"
            ]
        )
    }

    private func loadSnapshot(sessionID: UUID, branchID: UUID) async throws -> MockTaskAgentSnapshot {
        if let snapshot = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) {
            return snapshot
        }
        return MockTaskAgentSnapshot(
            schemaVersion: MockTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: .initial,
            updatedAt: Date()
        )
    }

    private func buildChecklist(for task: String) -> [String] {
        [
            "Уточнить цель задачи: \(task)",
            "Определить ограничения и входные данные",
            "Сформировать минимальный план реализации",
            "Проверить результат и зафиксировать следующий шаг"
        ]
    }
}
