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

struct StartCounterTaskAgentUseCase: StartCounterTaskAgentUseCaseProtocol {
    private let orchestrator: CounterTaskAgentOrchestrator

    init(orchestrator: CounterTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval?) async throws -> CounterTaskAgentTurnResult {
        try await orchestrator.start(
            sessionID: sessionID,
            branchID: branchID,
            intervalSeconds: intervalSeconds
        )
    }
}

struct StopCounterTaskAgentUseCase: StopCounterTaskAgentUseCaseProtocol {
    private let orchestrator: CounterTaskAgentOrchestrator

    init(orchestrator: CounterTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentTurnResult {
        try await orchestrator.stop(sessionID: sessionID, branchID: branchID)
    }
}

struct ConfigureCounterTaskAgentIntervalUseCase: ConfigureCounterTaskAgentIntervalUseCaseProtocol {
    private let orchestrator: CounterTaskAgentOrchestrator

    init(orchestrator: CounterTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval) async throws -> CounterTaskAgentTurnResult {
        try await orchestrator.configureInterval(
            sessionID: sessionID,
            branchID: branchID,
            intervalSeconds: intervalSeconds
        )
    }
}

struct TickCounterTaskAgentUseCase: TickCounterTaskAgentUseCaseProtocol {
    private let orchestrator: CounterTaskAgentOrchestrator

    init(orchestrator: CounterTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentTurnResult {
        try await orchestrator.tick(sessionID: sessionID, branchID: branchID)
    }
}

struct GetCounterTaskAgentStatusUseCase: GetCounterTaskAgentStatusUseCaseProtocol {
    private let stateRepository: CounterTaskAgentStateRepositoryProtocol

    init(stateRepository: CounterTaskAgentStateRepositoryProtocol) {
        self.stateRepository = stateRepository
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentSnapshot {
        if let snapshot = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) {
            return snapshot
        }
        return CounterTaskAgentSnapshot(
            schemaVersion: CounterTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: .initial,
            updatedAt: Date()
        )
    }
}

struct CounterTaskAgentOrchestrator {
    private let stateRepository: CounterTaskAgentStateRepositoryProtocol

    init(stateRepository: CounterTaskAgentStateRepositoryProtocol) {
        self.stateRepository = stateRepository
    }

    func start(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval?) async throws -> CounterTaskAgentTurnResult {
        let baseSnapshot = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        let requestedInterval = intervalSeconds ?? baseSnapshot.context.intervalSeconds
        guard requestedInterval > 0 else {
            return CounterTaskAgentTurnResult(
                snapshot: baseSnapshot,
                systemMessages: ["Интервал должен быть больше 0 секунд."]
            )
        }

        let now = Date()
        let snapshot = CounterTaskAgentSnapshot(
            schemaVersion: CounterTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .running,
            context: CounterTaskAgentContext(
                nextNumber: 1,
                intervalSeconds: requestedInterval,
                updatedAt: now
            ),
            updatedAt: now
        )
        try await stateRepository.saveSnapshot(snapshot)
        let intervalText = Self.intervalText(requestedInterval)
        return CounterTaskAgentTurnResult(
            snapshot: snapshot,
            systemMessages: ["Counter Task Agent запущен. Интервал: \(intervalText) сек."]
        )
    }

    func stop(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentTurnResult {
        let current = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        let now = Date()
        let snapshot = CounterTaskAgentSnapshot(
            schemaVersion: CounterTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: CounterTaskAgentContext(
                nextNumber: 1,
                intervalSeconds: current.context.intervalSeconds,
                updatedAt: now
            ),
            updatedAt: now
        )
        try await stateRepository.saveSnapshot(snapshot)
        return CounterTaskAgentTurnResult(
            snapshot: snapshot,
            systemMessages: ["Counter Task Agent остановлен."]
        )
    }

    func configureInterval(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval) async throws -> CounterTaskAgentTurnResult {
        let current = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        guard intervalSeconds > 0 else {
            return CounterTaskAgentTurnResult(
                snapshot: current,
                systemMessages: ["Интервал должен быть больше 0 секунд."]
            )
        }

        let now = Date()
        let snapshot = CounterTaskAgentSnapshot(
            schemaVersion: CounterTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: current.state,
            context: CounterTaskAgentContext(
                nextNumber: current.context.nextNumber,
                intervalSeconds: intervalSeconds,
                updatedAt: now
            ),
            updatedAt: now
        )
        try await stateRepository.saveSnapshot(snapshot)
        let intervalText = Self.intervalText(intervalSeconds)
        return CounterTaskAgentTurnResult(
            snapshot: snapshot,
            systemMessages: ["Интервал Counter Task Agent обновлен: \(intervalText) сек."]
        )
    }

    func tick(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentTurnResult {
        let current = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        guard current.state == .running else {
            return CounterTaskAgentTurnResult(snapshot: current, systemMessages: [])
        }

        let number = current.context.nextNumber
        let now = Date()
        let snapshot = CounterTaskAgentSnapshot(
            schemaVersion: CounterTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .running,
            context: CounterTaskAgentContext(
                nextNumber: number + 1,
                intervalSeconds: current.context.intervalSeconds,
                updatedAt: now
            ),
            updatedAt: now
        )
        try await stateRepository.saveSnapshot(snapshot)
        return CounterTaskAgentTurnResult(
            snapshot: snapshot,
            systemMessages: ["#\(number)"]
        )
    }

    private func loadSnapshot(sessionID: UUID, branchID: UUID) async throws -> CounterTaskAgentSnapshot {
        if let snapshot = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) {
            return snapshot
        }
        return CounterTaskAgentSnapshot(
            schemaVersion: CounterTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: .initial,
            updatedAt: Date()
        )
    }

    private static func intervalText(_ interval: TimeInterval) -> String {
        if interval.rounded(.towardZero) == interval {
            return String(format: "%.0f", interval)
        }
        return String(format: "%.2f", interval)
    }
}
