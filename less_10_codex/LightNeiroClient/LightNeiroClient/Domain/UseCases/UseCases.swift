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
        let branchMessages = try await messageRepository.fetchMessages(branchID: branchID)
        let messages = branchMessages.filter { $0.role != .system }
        let strategy = settings.contextStrategy(for: branchID)

        switch strategy {
        case .normal:
            return ([], messages)
        case .slidingWindow:
            return ([], Array(messages.suffix(settings.windowSize)))
        case .stickyFacts:
            let facts = try await factsRepository.fetchFacts(sessionID: sessionID)
            return (facts, Array(messages.suffix(settings.windowSize)))
        }
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
    private let messageRepository: MessageRepositoryProtocol
    private let llmClient: LLMClientProtocol
    private let decoder = JSONDecoder()

    init(
        factsRepository: FactsRepositoryProtocol,
        messageRepository: MessageRepositoryProtocol,
        llmClient: LLMClientProtocol
    ) {
        self.factsRepository = factsRepository
        self.messageRepository = messageRepository
        self.llmClient = llmClient
    }

    func execute(sessionID: UUID, branchID: UUID, latestUserMessage: String, settings: LLMSettings) async throws {
        let trimmed = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = try await factsRepository.fetchFacts(sessionID: sessionID)
        let extractionMessages = try await buildExtractionMessages(branchID: branchID, latestUserMessage: trimmed)
        let extracted = try await extractFactsUsingLLM(messages: extractionMessages, settings: settings)
        let merged = mergeFacts(existing: existing, with: extracted, sessionID: sessionID, lastUserMessage: trimmed)
        try await factsRepository.upsertFacts(sessionID: sessionID, facts: merged)
    }

    private func extractFactsUsingLLM(messages: [ChatMessage], settings: LLMSettings) async throws -> [StickyFactCandidate] {
        let response = try await llmClient.send(
            request: LLMRequest(
                systemPrompt: """
                You extract structured memory for chat context.
                Analyze only durable and important facts from the conversation.
                Output strict JSON object only.
                Allowed keys: goal, constraints, preferences, decisions, agreements.
                Values must be short strings.
                Omit keys with no new info.
                """,
                facts: [],
                messages: messages,
                settings: LLMSettings(
                    model: settings.model,
                    contextStrategy: .normal,
                    temperature: 0.0,
                    windowSize: 1,
                    contextStrategyByBranch: [:]
                )
            )
        )

        let payload = extractJSONObject(from: response.content)
        guard let data = payload.data(using: String.Encoding.utf8) else { return [] }
        let decoded = try decoder.decode(LLMFactExtractionResult.self, from: data)
        return decoded.candidates
    }

    private func buildExtractionMessages(branchID: UUID, latestUserMessage: String) async throws -> [ChatMessage] {
        let history = try await messageRepository.fetchMessages(branchID: branchID)
        let assistantReply = history
            .last(where: { $0.role == .assistant })?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let assistantContent: String
        if let assistantReply, !assistantReply.isEmpty {
            assistantContent = assistantReply
        } else {
            assistantContent = "No previous assistant response."
        }

        return [
            ChatMessage(branchID: branchID, role: .assistant, content: assistantContent),
            ChatMessage(branchID: branchID, role: .user, content: latestUserMessage)
        ]
    }

    private func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return "{}"
        }
        return String(text[start...end])
    }

    private func mergeFacts(
        existing: [StickyFact],
        with extracted: [StickyFactCandidate],
        sessionID: UUID,
        lastUserMessage: String
    ) -> [StickyFact] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.key, $0) })
        let now = Date()

        let candidates = extracted + [StickyFactCandidate(key: "last-user-message", value: lastUserMessage, confidence: 0.5)]

        for candidate in candidates {
            let value = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            let current = map[candidate.key]
            map[candidate.key] = StickyFact(
                id: current?.id ?? UUID(),
                sessionID: sessionID,
                key: candidate.key,
                value: value,
                confidence: candidate.confidence,
                updatedAt: now
            )
        }

        return map.values.sorted { $0.key < $1.key }
    }
}

private struct StickyFactCandidate {
    let key: String
    let value: String
    let confidence: Double
}

private struct LLMFactExtractionResult: Decodable {
    let goal: String?
    let constraints: String?
    let preferences: String?
    let decisions: String?
    let agreements: String?

    var candidates: [StickyFactCandidate] {
        var result: [StickyFactCandidate] = []

        if let goal, !goal.isEmpty {
            result.append(.init(key: "goal", value: goal, confidence: 0.8))
        }
        if let constraints, !constraints.isEmpty {
            result.append(.init(key: "constraints", value: constraints, confidence: 0.8))
        }
        if let preferences, !preferences.isEmpty {
            result.append(.init(key: "preferences", value: preferences, confidence: 0.75))
        }
        if let decisions, !decisions.isEmpty {
            result.append(.init(key: "decisions", value: decisions, confidence: 0.75))
        }
        if let agreements, !agreements.isEmpty {
            result.append(.init(key: "agreements", value: agreements, confidence: 0.75))
        }

        return result
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
        if settings.contextStrategy(for: branchID) == .stickyFacts {
            // Fact extraction should not block the main assistant response path.
            try? await updateFactsUseCase.execute(
                sessionID: sessionID,
                branchID: branchID,
                latestUserMessage: userText,
                settings: settings
            )
        }

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

        let metric = RequestMetric(
            id: UUID(),
            messageID: assistantMessage.id,
            branchID: branchID,
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

final class AddBranchCreatedSystemMessageUseCase: AddBranchCreatedSystemMessageUseCaseProtocol {
    private let messageRepository: MessageRepositoryProtocol

    init(messageRepository: MessageRepositoryProtocol) {
        self.messageRepository = messageRepository
    }

    func execute(branchID: UUID, sourceBranchName: String) async throws {
        let message = ChatMessage(
            branchID: branchID,
            role: .system,
            content: "создана ветка от [\(sourceBranchName)]"
        )
        try await messageRepository.saveMessage(message)
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

final class FetchSettingsUseCase: FetchSettingsUseCaseProtocol {
    private let settingsRepository: SettingsRepositoryProtocol

    init(settingsRepository: SettingsRepositoryProtocol) {
        self.settingsRepository = settingsRepository
    }

    func execute(sessionID: UUID) async throws -> LLMSettings {
        try await settingsRepository.fetchSettings(sessionID: sessionID)
    }
}

final class CollectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol {
    private let metricsRepository: MetricsRepositoryProtocol

    init(metricsRepository: MetricsRepositoryProtocol) {
        self.metricsRepository = metricsRepository
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> SessionInfoSnapshot {
        let metrics = try await metricsRepository.fetchMetrics(sessionID: sessionID)
        let branchMetrics = metrics.filter { $0.branchID == branchID }
        let totalIn = branchMetrics.reduce(0) { $0 + $1.inputTokens }
        let totalOut = branchMetrics.reduce(0) { $0 + $1.outputTokens }
        let lastLatency = branchMetrics.last?.latencyMs ?? 0

        return SessionInfoSnapshot(
            totalInputTokens: totalIn,
            totalOutputTokens: totalOut,
            totalRequests: branchMetrics.count,
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
