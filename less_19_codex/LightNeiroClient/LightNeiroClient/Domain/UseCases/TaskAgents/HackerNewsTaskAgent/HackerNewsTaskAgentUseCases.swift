import Foundation

struct StartHackerNewsTaskAgentUseCase: StartHackerNewsTaskAgentUseCaseProtocol {
    private let orchestrator: HackerNewsTaskAgentOrchestrator

    init(orchestrator: HackerNewsTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval?) async throws -> HackerNewsTaskAgentTurnResult {
        try await orchestrator.start(sessionID: sessionID, branchID: branchID, intervalSeconds: intervalSeconds)
    }
}

struct StopHackerNewsTaskAgentUseCase: StopHackerNewsTaskAgentUseCaseProtocol {
    private let orchestrator: HackerNewsTaskAgentOrchestrator

    init(orchestrator: HackerNewsTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentTurnResult {
        try await orchestrator.stop(sessionID: sessionID, branchID: branchID)
    }
}

struct ConfigureHackerNewsTaskAgentIntervalUseCase: ConfigureHackerNewsTaskAgentIntervalUseCaseProtocol {
    private let orchestrator: HackerNewsTaskAgentOrchestrator

    init(orchestrator: HackerNewsTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval) async throws -> HackerNewsTaskAgentTurnResult {
        try await orchestrator.configureInterval(
            sessionID: sessionID,
            branchID: branchID,
            intervalSeconds: intervalSeconds
        )
    }
}

struct TickHackerNewsTaskAgentUseCase: TickHackerNewsTaskAgentUseCaseProtocol {
    private let orchestrator: HackerNewsTaskAgentOrchestrator

    init(orchestrator: HackerNewsTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentTurnResult {
        try await orchestrator.tick(sessionID: sessionID, branchID: branchID)
    }
}

struct GetHackerNewsTaskAgentStatusUseCase: GetHackerNewsTaskAgentStatusUseCaseProtocol {
    private let stateRepository: HackerNewsTaskAgentStateRepositoryProtocol

    init(stateRepository: HackerNewsTaskAgentStateRepositoryProtocol) {
        self.stateRepository = stateRepository
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentSnapshot {
        if let snapshot = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) {
            return snapshot
        }
        return HackerNewsTaskAgentSnapshot(
            schemaVersion: HackerNewsTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: .initial,
            updatedAt: Date()
        )
    }
}

struct HackerNewsTaskAgentOrchestrator {
    private let stateRepository: HackerNewsTaskAgentStateRepositoryProtocol
    private let articleArchiveRepository: HackerNewsArticleArchiveRepositoryProtocol
    private let mcpService: MCPHackerNewsServiceProtocol
    private let llmSummaryService: HackerNewsLLMSummaryServiceProtocol
    private let endpointURL: URL

    init(
        stateRepository: HackerNewsTaskAgentStateRepositoryProtocol,
        articleArchiveRepository: HackerNewsArticleArchiveRepositoryProtocol,
        mcpService: MCPHackerNewsServiceProtocol,
        llmSummaryService: HackerNewsLLMSummaryServiceProtocol,
        endpointURL: URL = URL(string: "stdio://hackernews")!
    ) {
        self.stateRepository = stateRepository
        self.articleArchiveRepository = articleArchiveRepository
        self.mcpService = mcpService
        self.llmSummaryService = llmSummaryService
        self.endpointURL = endpointURL
    }

    func start(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval?) async throws -> HackerNewsTaskAgentTurnResult {
        let baseSnapshot = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        let requestedInterval = intervalSeconds ?? baseSnapshot.context.intervalSeconds
        guard requestedInterval > 0 else {
            return HackerNewsTaskAgentTurnResult(
                snapshot: baseSnapshot,
                systemMessages: ["Интервал должен быть больше 0 секунд."]
            )
        }

        let now = Date()
        let snapshot = HackerNewsTaskAgentSnapshot(
            schemaVersion: HackerNewsTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .running,
            context: HackerNewsTaskAgentContext(
                nextRequestNumber: 1,
                requestCount: 0,
                intervalSeconds: requestedInterval,
                llmSummaryEvery: max(1, baseSnapshot.context.llmSummaryEvery),
                recentStories: [],
                updatedAt: now
            ),
            updatedAt: now
        )
        try await stateRepository.saveSnapshot(snapshot)

        return HackerNewsTaskAgentTurnResult(
            snapshot: snapshot,
            systemMessages: [
                "Hacker News Task Agent запущен. Интервал: \(Self.intervalText(requestedInterval)) сек.",
                "Каждый запрос сохраняется в JSON. Каждые \(snapshot.context.llmSummaryEvery) запросов будет LLM-сводка."
            ]
        )
    }

    func stop(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentTurnResult {
        let current = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        let now = Date()
        let snapshot = HackerNewsTaskAgentSnapshot(
            schemaVersion: HackerNewsTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: HackerNewsTaskAgentContext(
                nextRequestNumber: current.context.nextRequestNumber,
                requestCount: current.context.requestCount,
                intervalSeconds: current.context.intervalSeconds,
                llmSummaryEvery: current.context.llmSummaryEvery,
                recentStories: current.context.recentStories,
                updatedAt: now
            ),
            updatedAt: now
        )
        try await stateRepository.saveSnapshot(snapshot)

        return HackerNewsTaskAgentTurnResult(
            snapshot: snapshot,
            systemMessages: ["Hacker News Task Agent остановлен."]
        )
    }

    func configureInterval(sessionID: UUID, branchID: UUID, intervalSeconds: TimeInterval) async throws -> HackerNewsTaskAgentTurnResult {
        let current = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        guard intervalSeconds > 0 else {
            return HackerNewsTaskAgentTurnResult(
                snapshot: current,
                systemMessages: ["Интервал должен быть больше 0 секунд."]
            )
        }

        let now = Date()
        let snapshot = HackerNewsTaskAgentSnapshot(
            schemaVersion: HackerNewsTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: current.state,
            context: HackerNewsTaskAgentContext(
                nextRequestNumber: current.context.nextRequestNumber,
                requestCount: current.context.requestCount,
                intervalSeconds: intervalSeconds,
                llmSummaryEvery: current.context.llmSummaryEvery,
                recentStories: current.context.recentStories,
                updatedAt: now
            ),
            updatedAt: now
        )
        try await stateRepository.saveSnapshot(snapshot)

        return HackerNewsTaskAgentTurnResult(
            snapshot: snapshot,
            systemMessages: ["Интервал Hacker News Task Agent обновлен: \(Self.intervalText(intervalSeconds)) сек."]
        )
    }

    func tick(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentTurnResult {
        let current = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        guard current.state == .running else {
            return HackerNewsTaskAgentTurnResult(snapshot: current, systemMessages: [])
        }

        let requestNumber = current.context.nextRequestNumber
        do {
            let story = try await mcpService.fetchRandomStory(serverURL: endpointURL)
            let record = HackerNewsTaskAgentArticleRecord(
                sessionID: sessionID,
                branchID: branchID,
                requestNumber: requestNumber,
                fetchedAt: Date(),
                story: story
            )
            let fileURL = try await articleArchiveRepository.saveArticle(record)

            var recentStories = current.context.recentStories
            recentStories.append(
                HackerNewsTaskAgentStoryDigest(
                    requestNumber: requestNumber,
                    title: story.title,
                    author: story.author,
                    url: story.url
                )
            )
            if recentStories.count > current.context.llmSummaryEvery {
                recentStories = Array(recentStories.suffix(current.context.llmSummaryEvery))
            }

            let now = Date()
            let updatedRequestCount = current.context.requestCount + 1
            let snapshot = HackerNewsTaskAgentSnapshot(
                schemaVersion: HackerNewsTaskAgentSnapshot.schemaVersionCurrent,
                sessionID: sessionID,
                branchID: branchID,
                state: .running,
                context: HackerNewsTaskAgentContext(
                    nextRequestNumber: requestNumber + 1,
                    requestCount: updatedRequestCount,
                    intervalSeconds: current.context.intervalSeconds,
                    llmSummaryEvery: current.context.llmSummaryEvery,
                    recentStories: recentStories,
                    updatedAt: now
                ),
                updatedAt: now
            )
            try await stateRepository.saveSnapshot(snapshot)

            var systemMessages = [
                "HN #\(requestNumber): \(story.shortSummary)",
                "JSON сохранен: \(fileURL.path)"
            ]

            if updatedRequestCount % snapshot.context.llmSummaryEvery == 0 {
                do {
                    let llmSummary = try await llmSummaryService.summarize(
                        sessionID: sessionID,
                        recentStories: recentStories
                    )
                    systemMessages.append("LLM-сводка (последние \(snapshot.context.llmSummaryEvery) статей): \(llmSummary)")
                } catch {
                    systemMessages.append("LLM-сводка недоступна: \(error.localizedDescription)")
                }
            }

            return HackerNewsTaskAgentTurnResult(snapshot: snapshot, systemMessages: systemMessages)
        } catch {
            let now = Date()
            let failedSnapshot = HackerNewsTaskAgentSnapshot(
                schemaVersion: HackerNewsTaskAgentSnapshot.schemaVersionCurrent,
                sessionID: sessionID,
                branchID: branchID,
                state: .failed(reason: error.localizedDescription),
                context: HackerNewsTaskAgentContext(
                    nextRequestNumber: current.context.nextRequestNumber,
                    requestCount: current.context.requestCount,
                    intervalSeconds: current.context.intervalSeconds,
                    llmSummaryEvery: current.context.llmSummaryEvery,
                    recentStories: current.context.recentStories,
                    updatedAt: now
                ),
                updatedAt: now
            )
            try await stateRepository.saveSnapshot(failedSnapshot)
            return HackerNewsTaskAgentTurnResult(
                snapshot: failedSnapshot,
                systemMessages: ["Ошибка запроса Hacker News: \(error.localizedDescription)"]
            )
        }
    }

    private func loadSnapshot(sessionID: UUID, branchID: UUID) async throws -> HackerNewsTaskAgentSnapshot {
        if let snapshot = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) {
            return snapshot
        }
        return HackerNewsTaskAgentSnapshot(
            schemaVersion: HackerNewsTaskAgentSnapshot.schemaVersionCurrent,
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
