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
        let messages = try await messageRepository.fetchMessages(branchID: branchID)

        switch settings.contextStrategy {
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

    init(factsRepository: FactsRepositoryProtocol) {
        self.factsRepository = factsRepository
    }

    func execute(sessionID: UUID, latestUserMessage: String) async throws {
        let trimmed = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = try await factsRepository.fetchFacts(sessionID: sessionID)
        let extracted = extractFacts(from: trimmed)
        let alwaysSaved = StickyFactCandidate(key: "last-user-message", value: trimmed, confidence: 0.5)

        let merged = mergeFacts(
            existing: existing,
            with: extracted + [alwaysSaved],
            sessionID: sessionID
        )
        try await factsRepository.upsertFacts(sessionID: sessionID, facts: merged)
    }

    private func extractFacts(from text: String) -> [StickyFactCandidate] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var candidates: [StickyFactCandidate] = []

        for line in lines {
            if let candidate = candidateFromExplicitKV(line: line) {
                candidates.append(candidate)
                continue
            }
            if let candidate = candidateFromSemanticLine(line: line) {
                candidates.append(candidate)
            }
        }

        return deduplicated(candidates)
    }

    private func candidateFromExplicitKV(line: String) -> StickyFactCandidate? {
        let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        let keyPart = normalize(parts[0])
        let valuePart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !valuePart.isEmpty else { return nil }
        guard let key = mapToFactKey(from: keyPart) else { return nil }

        return StickyFactCandidate(key: key, value: valuePart, confidence: 0.85)
    }

    private func candidateFromSemanticLine(line: String) -> StickyFactCandidate? {
        let normalized = normalize(line)

        if containsAny(normalized, ["мы решили", "решили ", "decision", "выбрали", "selected"]) {
            return StickyFactCandidate(key: "decisions", value: line, confidence: 0.65)
        }
        if containsAny(normalized, ["договор", "agreement", "согласовали", "agreed"]) {
            return StickyFactCandidate(key: "agreements", value: line, confidence: 0.65)
        }
        if containsAny(normalized, ["предпоч", "preference", "format", "style", "тон"]) {
            return StickyFactCandidate(key: "preferences", value: line, confidence: 0.6)
        }
        if containsAny(normalized, ["огранич", "constraint", "limit", "запрет", "требован"]) {
            return StickyFactCandidate(key: "constraints", value: line, confidence: 0.6)
        }
        if containsAny(normalized, ["цель", "goal", "objective", "задача"]) {
            return StickyFactCandidate(key: "goal", value: line, confidence: 0.6)
        }

        return nil
    }

    private func mapToFactKey(from normalizedKey: String) -> String? {
        if containsAny(normalizedKey, ["цель", "goal", "objective", "задача"]) {
            return "goal"
        }
        if containsAny(normalizedKey, ["огранич", "constraint", "limit", "запрет", "требован"]) {
            return "constraints"
        }
        if containsAny(normalizedKey, ["предпоч", "preference", "style", "format", "тон"]) {
            return "preferences"
        }
        if containsAny(normalizedKey, ["решени", "decision", "выбор", "выбрали"]) {
            return "decisions"
        }
        if containsAny(normalizedKey, ["договор", "agreement", "соглас"]) {
            return "agreements"
        }
        return nil
    }

    private func mergeFacts(existing: [StickyFact], with extracted: [StickyFactCandidate], sessionID: UUID) -> [StickyFact] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.key, $0) })
        let now = Date()

        for candidate in extracted {
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

    private func deduplicated(_ candidates: [StickyFactCandidate]) -> [StickyFactCandidate] {
        var map: [String: StickyFactCandidate] = [:]
        for candidate in candidates {
            map[candidate.key] = candidate
        }
        return Array(map.values)
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ text: String, _ tokens: [String]) -> Bool {
        tokens.contains { text.contains($0) }
    }
}

private struct StickyFactCandidate {
    let key: String
    let value: String
    let confidence: Double
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
        try await updateFactsUseCase.execute(sessionID: sessionID, latestUserMessage: userText)

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
