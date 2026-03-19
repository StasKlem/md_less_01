import Foundation

struct StartHackerNewsTaskAgentUseCase: StartHackerNewsTaskAgentUseCaseProtocol {
    private let orchestrator: HackerNewsTaskAgentOrchestrator

    init(orchestrator: HackerNewsTaskAgentOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(
        sessionID: UUID,
        branchID: UUID,
        onSystemMessage: (@Sendable (String) async -> Void)?
    ) async throws -> HackerNewsTaskAgentTurnResult {
        try await orchestrator.start(
            sessionID: sessionID,
            branchID: branchID,
            onSystemMessage: onSystemMessage
        )
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
    private let mcpService: MCPHackerNewsServiceProtocol
    private let llmSummaryService: HackerNewsLLMSummaryServiceProtocol
    private let storyEndpointURL: URL
    private let translateEndpointURL: URL
    private let archiveEndpointURL: URL
    private let translationLanguage: String

    init(
        stateRepository: HackerNewsTaskAgentStateRepositoryProtocol,
        mcpService: MCPHackerNewsServiceProtocol,
        llmSummaryService: HackerNewsLLMSummaryServiceProtocol,
        storyEndpointURL: URL = URL(string: "stdio://hackernews")!,
        translateEndpointURL: URL = URL(string: "stdio://hackernews-translate")!,
        archiveEndpointURL: URL = URL(string: "stdio://hackernews-archive")!,
        translationLanguage: String = "ru"
    ) {
        self.stateRepository = stateRepository
        self.mcpService = mcpService
        self.llmSummaryService = llmSummaryService
        self.storyEndpointURL = storyEndpointURL
        self.translateEndpointURL = translateEndpointURL
        self.archiveEndpointURL = archiveEndpointURL
        self.translationLanguage = translationLanguage
    }

    func start(
        sessionID: UUID,
        branchID: UUID,
        onSystemMessage: (@Sendable (String) async -> Void)?
    ) async throws -> HackerNewsTaskAgentTurnResult {
        let baseSnapshot = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        let now = Date()
        let runningSnapshot = HackerNewsTaskAgentSnapshot(
            schemaVersion: HackerNewsTaskAgentSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .running,
            context: HackerNewsTaskAgentContext(
                nextRequestNumber: baseSnapshot.context.nextRequestNumber,
                requestCount: baseSnapshot.context.requestCount,
                intervalSeconds: baseSnapshot.context.intervalSeconds,
                llmSummaryEvery: max(1, baseSnapshot.context.llmSummaryEvery),
                recentStories: baseSnapshot.context.recentStories,
                updatedAt: now
            ),
            updatedAt: now
        )
        try await stateRepository.saveSnapshot(runningSnapshot)
        return try await executeSingleRun(from: runningSnapshot, onSystemMessage: onSystemMessage)
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

    private func executeSingleRun(
        from current: HackerNewsTaskAgentSnapshot,
        onSystemMessage: (@Sendable (String) async -> Void)?
    ) async throws -> HackerNewsTaskAgentTurnResult {
        let sessionID = current.sessionID
        let branchID = current.branchID
        let requestNumber = current.context.nextRequestNumber
        var systemMessages: [String] = []
        do {
            await Self.appendSystemMessage("Шаг 1/3: запрашиваю новость через MCP...", to: &systemMessages, onSystemMessage: onSystemMessage)
            let story: HackerNewsTaskAgentStory
            do {
                story = try await mcpService.fetchRandomStory(serverURL: storyEndpointURL)
            } catch {
                await Self.appendSystemMessage(
                    "Шаг 1/3: ошибка получения новости: \(error.localizedDescription)",
                    to: &systemMessages,
                    onSystemMessage: onSystemMessage
                )
                throw error
            }
            await Self.appendSystemMessage("Шаг 1/3: новость получена: \(story.shortSummary)", to: &systemMessages, onSystemMessage: onSystemMessage)

            await Self.appendSystemMessage("Шаг 2/3: запрашиваю перевод новости через MCP...", to: &systemMessages, onSystemMessage: onSystemMessage)
            let translatedStory: String
            do {
                translatedStory = try await mcpService.translateStory(
                    serverURL: translateEndpointURL,
                    sessionID: sessionID,
                    story: story.rawText,
                    language: translationLanguage
                )
            } catch {
                await Self.appendSystemMessage(
                    "Шаг 2/3: ошибка перевода: \(error.localizedDescription)",
                    to: &systemMessages,
                    onSystemMessage: onSystemMessage
                )
                throw error
            }
            let translationPreview = translatedStory
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(120)
            await Self.appendSystemMessage(
                "Шаг 2/3: перевод получен (\(translationLanguage)): \(translationPreview)",
                to: &systemMessages,
                onSystemMessage: onSystemMessage
            )

            let translatedArchiveRecord = HackerNewsTaskAgentTranslatedArticleRecord(
                sessionID: sessionID,
                branchID: branchID,
                requestNumber: requestNumber,
                fetchedAt: Date(),
                sourceStory: story,
                translatedText: translatedStory,
                translationLanguage: translationLanguage
            )

            await Self.appendSystemMessage("Шаг 3/3: сохраняю перевод через MCP...", to: &systemMessages, onSystemMessage: onSystemMessage)
            let archivePayload = try Self.makeArchivePayload(from: translatedArchiveRecord)
            let archiveResponse: String
            do {
                archiveResponse = try await mcpService.saveArchiveJSON(
                    serverURL: archiveEndpointURL,
                    json: archivePayload
                )
            } catch {
                await Self.appendSystemMessage(
                    "Шаг 3/3: ошибка сохранения: \(error.localizedDescription)",
                    to: &systemMessages,
                    onSystemMessage: onSystemMessage
                )
                throw error
            }
            await Self.appendSystemMessage("Шаг 3/3: перевод сохранен: \(archiveResponse)", to: &systemMessages, onSystemMessage: onSystemMessage)

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
                state: .idle,
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

            let completedMessage = "Hacker News Task Agent выполнен один раз."
            systemMessages.insert(completedMessage, at: 0)
            await onSystemMessage?(completedMessage)

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
            var failedMessages = systemMessages
            let failedPrefix = "Hacker News Task Agent завершился с ошибкой."
            failedMessages.insert(failedPrefix, at: 0)
            await onSystemMessage?(failedPrefix)
            let failedDetail = "Ошибка запроса Hacker News: \(error.localizedDescription)"
            failedMessages.append(failedDetail)
            await onSystemMessage?(failedDetail)
            return HackerNewsTaskAgentTurnResult(
                snapshot: failedSnapshot,
                systemMessages: failedMessages
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

    private static func makeArchivePayload(from record: HackerNewsTaskAgentTranslatedArticleRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        guard let json = String(data: data, encoding: .utf8) else {
            throw HackerNewsTaskAgentArchivePayloadError.encodingFailed
        }
        return json
    }

    private static func appendSystemMessage(
        _ message: String,
        to messages: inout [String],
        onSystemMessage: (@Sendable (String) async -> Void)?
    ) async {
        messages.append(message)
        await onSystemMessage?(message)
    }
}

private struct HackerNewsTaskAgentTranslatedArticleRecord: Codable {
    let sessionID: UUID
    let branchID: UUID
    let requestNumber: Int
    let fetchedAt: Date
    let sourceStory: HackerNewsTaskAgentStory
    let translatedText: String
    let translationLanguage: String
}

private enum HackerNewsTaskAgentArchivePayloadError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Не удалось закодировать JSON для архивации перевода."
        }
    }
}
