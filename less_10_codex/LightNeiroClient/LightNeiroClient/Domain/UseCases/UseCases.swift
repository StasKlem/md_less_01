import Foundation

final class BuildContextUseCase: BuildContextUseCaseProtocol {
    private let factsRepository: FactsRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol

    init(factsRepository: FactsRepositoryProtocol, messageRepository: MessageRepositoryProtocol) {
        self.factsRepository = factsRepository
        self.messageRepository = messageRepository
    }

    func execute(
        sessionID: UUID,
        branchID: UUID,
        settings: LLMSettings
    ) async throws -> (facts: [StickyFact], messages: [ChatMessage]) {
        let facts = try await factsRepository.fetchFacts(sessionID: sessionID)
        let messages = try await messageRepository.fetchMessages(branchID: branchID)
        return (facts, Array(messages.suffix(settings.windowSize)))
    }
}

final class FetchBranchesUseCase: FetchBranchesUseCaseProtocol {
    private let branchRepository: BranchRepositoryProtocol

    init(branchRepository: BranchRepositoryProtocol) {
        self.branchRepository = branchRepository
    }

    func execute(sessionID: UUID) async throws -> [ChatBranch] {
        let branches = try await branchRepository.fetchBranches(sessionID: sessionID)
        return branches.sorted { $0.createdAt < $1.createdAt }
    }
}

final class FetchMessagesUseCase: FetchMessagesUseCaseProtocol {
    private let messageRepository: MessageRepositoryProtocol

    init(messageRepository: MessageRepositoryProtocol) {
        self.messageRepository = messageRepository
    }

    func execute(branchID: UUID) async throws -> [ChatMessage] {
        try await messageRepository.fetchMessages(branchID: branchID)
    }
}

final class CloneDialogToBranchUseCase: CloneDialogToBranchUseCaseProtocol {
    private let messageRepository: MessageRepositoryProtocol

    init(messageRepository: MessageRepositoryProtocol) {
        self.messageRepository = messageRepository
    }

    func execute(sourceBranchID: UUID, targetBranchID: UUID) async throws {
        let targetMessages = try await messageRepository.fetchMessages(branchID: targetBranchID)
        guard targetMessages.isEmpty else { return }

        let sourceMessages = try await messageRepository.fetchMessages(branchID: sourceBranchID)
        for message in sourceMessages {
            let clone = ChatMessage(
                branchID: targetBranchID,
                role: message.role,
                content: message.content,
                createdAt: message.createdAt,
                inputTokens: message.inputTokens,
                outputTokens: message.outputTokens,
                latencyMs: message.latencyMs
            )
            try await messageRepository.saveMessage(clone)
        }
    }
}

final class UpdateFactsUseCase: UpdateFactsUseCaseProtocol {
    private let factsRepository: FactsRepositoryProtocol

    init(factsRepository: FactsRepositoryProtocol) {
        self.factsRepository = factsRepository
    }

    func execute(sessionID: UUID, latestUserMessage: String) async throws {
        guard !latestUserMessage.isEmpty else { return }

        let existing = try await factsRepository.fetchFacts(sessionID: sessionID)
        let fact = StickyFact(
            id: UUID(),
            sessionID: sessionID,
            key: "last-user-message",
            value: latestUserMessage,
            confidence: 0.5,
            updatedAt: Date()
        )

        let next = existing.filter { $0.key != fact.key } + [fact]
        try await factsRepository.upsertFacts(sessionID: sessionID, facts: next)
    }
}

final class SendMessageUseCase: SendMessageUseCaseProtocol {
    private let settingsRepository: SettingsRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol
    private let llmClient: LLMClientProtocol
    private let buildContextUseCase: BuildContextUseCaseProtocol
    private let updateFactsUseCase: UpdateFactsUseCaseProtocol
    private let metricsRepository: MetricsRepositoryProtocol

    init(
        settingsRepository: SettingsRepositoryProtocol,
        messageRepository: MessageRepositoryProtocol,
        llmClient: LLMClientProtocol,
        buildContextUseCase: BuildContextUseCaseProtocol,
        updateFactsUseCase: UpdateFactsUseCaseProtocol,
        metricsRepository: MetricsRepositoryProtocol
    ) {
        self.settingsRepository = settingsRepository
        self.messageRepository = messageRepository
        self.llmClient = llmClient
        self.buildContextUseCase = buildContextUseCase
        self.updateFactsUseCase = updateFactsUseCase
        self.metricsRepository = metricsRepository
    }

    func execute(sessionID: UUID, branchID: UUID, userText: String) async throws -> ChatMessage {
        let userMessage = ChatMessage(branchID: branchID, role: .user, content: userText)
        try await messageRepository.saveMessage(userMessage)

        let settings = try await settingsRepository.fetchSettings(sessionID: sessionID)
        let context = try await buildContextUseCase.execute(sessionID: sessionID, branchID: branchID, settings: settings)

        let request = LLMRequest(
            systemPrompt: "You are a helpful assistant.",
            facts: context.facts,
            messages: context.messages,
            settings: settings
        )
        let response = try await llmClient.send(request: request)

        let assistantMessage = ChatMessage(
            branchID: branchID,
            role: .assistant,
            content: response.content,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            latencyMs: response.latencyMs
        )
        try await messageRepository.saveMessage(assistantMessage)
        try await updateFactsUseCase.execute(sessionID: sessionID, latestUserMessage: userText)

        let metric = RequestMetric(
            id: UUID(),
            messageID: assistantMessage.id,
            startedAt: Date().addingTimeInterval(-Double(response.latencyMs) / 1000.0),
            endedAt: Date(),
            latencyMs: response.latencyMs,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens
        )
        try await metricsRepository.appendMetric(metric)

        return assistantMessage
    }
}

final class CreateCheckpointUseCase: CreateCheckpointUseCaseProtocol {
    private let branchRepository: BranchRepositoryProtocol

    init(branchRepository: BranchRepositoryProtocol) {
        self.branchRepository = branchRepository
    }

    func execute(branchID: UUID, messageID: UUID, name: String) async throws -> ChatCheckpoint {
        let checkpoint = ChatCheckpoint(
            id: UUID(),
            branchID: branchID,
            messageID: messageID,
            name: name,
            createdAt: Date()
        )
        try await branchRepository.saveCheckpoint(checkpoint)
        return checkpoint
    }
}

final class CreateBranchUseCase: CreateBranchUseCaseProtocol {
    private let branchRepository: BranchRepositoryProtocol

    init(branchRepository: BranchRepositoryProtocol) {
        self.branchRepository = branchRepository
    }

    func execute(sessionID: UUID, parentCheckpointID: UUID?, name: String) async throws -> ChatBranch {
        let branch = ChatBranch(
            id: UUID(),
            sessionID: sessionID,
            parentCheckpointID: parentCheckpointID,
            name: name,
            createdAt: Date()
        )
        try await branchRepository.saveBranch(branch)
        return branch
    }
}

final class SwitchBranchUseCase: SwitchBranchUseCaseProtocol {
    private let sessionRepository: ChatSessionRepositoryProtocol

    init(sessionRepository: ChatSessionRepositoryProtocol) {
        self.sessionRepository = sessionRepository
    }

    func execute(sessionID: UUID, targetBranchID: UUID) async throws -> ChatSession {
        guard var session = try await sessionRepository.fetchSession(id: sessionID) else {
            throw NSError(domain: "SwitchBranchUseCase", code: 404)
        }
        session.activeBranchID = targetBranchID
        try await sessionRepository.saveSession(session)
        return session
    }
}

final class ApplySettingsUseCase: ApplySettingsUseCaseProtocol {
    private let settingsRepository: SettingsRepositoryProtocol

    init(settingsRepository: SettingsRepositoryProtocol) {
        self.settingsRepository = settingsRepository
    }

    func execute(sessionID: UUID, settings: LLMSettings) async throws {
        try await settingsRepository.saveSettings(sessionID: sessionID, settings: settings)
    }
}

final class CollectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol {
    private let metricsRepository: MetricsRepositoryProtocol

    init(metricsRepository: MetricsRepositoryProtocol) {
        self.metricsRepository = metricsRepository
    }

    func execute(sessionID: UUID) async throws -> SessionInfoSnapshot {
        let metrics = try await metricsRepository.fetchMetrics(sessionID: sessionID)
        let totalIn = metrics.reduce(0) { $0 + $1.inputTokens }
        let totalOut = metrics.reduce(0) { $0 + $1.outputTokens }
        let lastLatency = metrics.last?.latencyMs ?? 0

        return SessionInfoSnapshot(
            totalInputTokens: totalIn,
            totalOutputTokens: totalOut,
            totalRequests: metrics.count,
            lastLatencyMs: lastLatency
        )
    }
}

final class LoadAPIKeyUseCase: LoadAPIKeyUseCaseProtocol {
    private let apiKeyStore: APIKeyStoreProtocol

    init(apiKeyStore: APIKeyStoreProtocol) {
        self.apiKeyStore = apiKeyStore
    }

    func execute() throws -> String? {
        try apiKeyStore.fetchAPIKey()
    }
}

final class SaveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol {
    private let apiKeyStore: APIKeyStoreProtocol

    init(apiKeyStore: APIKeyStoreProtocol) {
        self.apiKeyStore = apiKeyStore
    }

    func execute(apiKey: String) throws {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            try apiKeyStore.deleteAPIKey()
            return
        }
        try apiKeyStore.saveAPIKey(normalizedKey)
    }

    func delete() throws {
        try apiKeyStore.deleteAPIKey()
    }
}
