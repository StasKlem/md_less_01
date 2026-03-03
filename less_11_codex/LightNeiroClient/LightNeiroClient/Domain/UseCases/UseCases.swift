import Foundation

/// Формирует unified memory context для конкретной ветки.
final class BuildMemoryContextUseCase: BuildMemoryContextUseCaseProtocol {
    private let shortTermRepository: ShortTermMemoryRepositoryProtocol
    private let workingMemoryRepository: WorkingMemoryRepositoryProtocol
    private let longTermMemoryRepository: LongTermMemoryRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol

    private let maxLongTermItems = 12

    init(
        shortTermRepository: ShortTermMemoryRepositoryProtocol,
        workingMemoryRepository: WorkingMemoryRepositoryProtocol,
        longTermMemoryRepository: LongTermMemoryRepositoryProtocol,
        messageRepository: MessageRepositoryProtocol
    ) {
        self.shortTermRepository = shortTermRepository
        self.workingMemoryRepository = workingMemoryRepository
        self.longTermMemoryRepository = longTermMemoryRepository
        self.messageRepository = messageRepository
    }

    func execute(
        sessionID: UUID,
        branchID: UUID,
        settings: LLMSettings
    ) async throws -> MemoryContext {
        let snapshot = try await shortTermRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID)
        let nonSystemMessages = try await fetchNonSystemMessages(branchID: branchID)
        let shortTermMessages = selectShortTermMessages(
            snapshot: snapshot,
            fallbackMessages: nonSystemMessages,
            strategy: settings.contextStrategy(for: branchID),
            windowSize: settings.windowSize
        )

        let workingMemory = try await workingMemoryRepository.fetchActive(sessionID: sessionID, branchID: branchID)
        let longTermMemory = try await prioritizedLongTermMemory(sessionID: sessionID)

        return MemoryContext(
            shortTermMessages: shortTermMessages,
            workingMemory: workingMemory,
            longTermMemory: longTermMemory
        )
    }

    private func fetchNonSystemMessages(branchID: UUID) async throws -> [ChatMessage] {
        let branchMessages = try await messageRepository.fetchMessages(branchID: branchID)
        return branchMessages.filter { $0.role != .system }
    }

    private func selectShortTermMessages(
        snapshot: ShortTermMemorySnapshot?,
        fallbackMessages: [ChatMessage],
        strategy: ContextStrategy,
        windowSize: Int
    ) -> [ChatMessage] {
        let sourceMessages = snapshot?.messages ?? fallbackMessages
        switch strategy {
        case .normal:
            return sourceMessages
        case .slidingWindow, .stickyFacts:
            return Array(sourceMessages.suffix(max(1, windowSize)))
        }
    }

    private func prioritizedLongTermMemory(sessionID: UUID) async throws -> [LongTermMemoryItem] {
        let items = try await longTermMemoryRepository.fetch(sessionID: sessionID, namespaces: nil)
        let namespacePriority: [LongTermMemoryNamespace: Int] = [
            .profile: 0,
            .decisions: 1,
            .knowledge: 2
        ]

        let sorted = items.sorted { lhs, rhs in
            let leftPriority = namespacePriority[lhs.namespace] ?? Int.max
            let rightPriority = namespacePriority[rhs.namespace] ?? Int.max
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        return Array(sorted.prefix(maxLongTermItems))
    }
}

final class FetchBranchesUseCase: FetchBranchesUseCaseProtocol {
    private let branchRepository: BranchRepositoryProtocol

    /// Создаёт use case получения веток сессии.
    init(branchRepository: BranchRepositoryProtocol) {
        self.branchRepository = branchRepository
    }

    /// Возвращает ветки сессии, отсортированные по времени создания.
    func execute(sessionID: UUID) async throws -> [ChatBranch] {
        let branches = try await branchRepository.fetchBranches(sessionID: sessionID)
        return branches.sorted { $0.createdAt < $1.createdAt }
    }
}

final class FetchMessagesUseCase: FetchMessagesUseCaseProtocol {
    private let messageRepository: MessageRepositoryProtocol

    /// Создаёт use case чтения сообщений ветки.
    init(messageRepository: MessageRepositoryProtocol) {
        self.messageRepository = messageRepository
    }

    /// Возвращает все сообщения указанной ветки.
    func execute(branchID: UUID) async throws -> [ChatMessage] {
        try await messageRepository.fetchMessages(branchID: branchID)
    }
}

final class CloneDialogToBranchUseCase: CloneDialogToBranchUseCaseProtocol {
    private let messageRepository: MessageRepositoryProtocol

    /// Создаёт use case клонирования диалога между ветками.
    init(messageRepository: MessageRepositoryProtocol) {
        self.messageRepository = messageRepository
    }

    /// Клонирует сообщения из source-ветки в target-ветку, если target ещё пустая.
    func execute(sourceBranchID: UUID, targetBranchID: UUID) async throws {
        let targetMessages = try await messageRepository.fetchMessages(branchID: targetBranchID)
        // Защитное условие: если в целевой ветке уже есть сообщения, клон не делаем.
        // Это предотвращает дубли и сохраняет идемпотентность операции.
        guard targetMessages.isEmpty else { return }

        let sourceMessages = try await messageRepository.fetchMessages(branchID: sourceBranchID)
        for message in sourceMessages {
            // Клонируем содержимое и метаданные в новую ветку, чтобы стартовая история совпадала.
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

final class UpdateShortTermMemoryUseCase: UpdateShortTermMemoryUseCaseProtocol {
    private let messageRepository: MessageRepositoryProtocol
    private let shortTermRepository: ShortTermMemoryRepositoryProtocol

    init(
        messageRepository: MessageRepositoryProtocol,
        shortTermRepository: ShortTermMemoryRepositoryProtocol
    ) {
        self.messageRepository = messageRepository
        self.shortTermRepository = shortTermRepository
    }

    func execute(sessionID: UUID, branchID: UUID, windowSize: Int) async throws {
        let allMessages = try await messageRepository.fetchMessages(branchID: branchID)
            .filter { $0.role != .system }

        let snapshot = ShortTermMemorySnapshot(
            sessionID: sessionID,
            branchID: branchID,
            messages: Array(allMessages.suffix(max(1, windowSize))),
            windowSize: max(1, windowSize),
            updatedAt: Date()
        )
        try await shortTermRepository.saveSnapshot(snapshot)
    }
}

final class UpdateWorkingMemoryUseCase: UpdateWorkingMemoryUseCaseProtocol {
    private let workingMemoryRepository: WorkingMemoryRepositoryProtocol

    init(workingMemoryRepository: WorkingMemoryRepositoryProtocol) {
        self.workingMemoryRepository = workingMemoryRepository
    }

    func execute(
        sessionID: UUID,
        branchID: UUID,
        latestUserMessage: String,
        latestAssistantMessage: String?
    ) async throws {
        let userText = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        let active = try await workingMemoryRepository.fetchActive(sessionID: sessionID, branchID: branchID)
        let extracted = extractCandidates(from: userText, assistantText: latestAssistantMessage ?? "")
        let merged = merge(active: active, with: extracted, sessionID: sessionID, branchID: branchID)
        if !merged.isEmpty {
            try await workingMemoryRepository.upsert(sessionID: sessionID, branchID: branchID, items: merged)
        }

        let resolvedKeys = resolveKeys(from: userText, assistantText: latestAssistantMessage ?? "")
        if !resolvedKeys.isEmpty {
            try await workingMemoryRepository.resolve(sessionID: sessionID, branchID: branchID, keys: resolvedKeys)
        }
    }

    private func extractCandidates(from userText: String, assistantText: String) -> [WorkingMemoryCandidate] {
        let normalized = userText.lowercased()
        var result: [WorkingMemoryCandidate] = []

        if let value = extractValue(in: userText, prefixes: ["goal:", "цель:"]) {
            result.append(.init(key: "task.goal", value: value, confidence: 0.9))
        } else if normalized.contains("need to") || normalized.contains("нужно") {
            result.append(.init(key: "task.goal", value: userText, confidence: 0.75))
        }

        if let value = extractValue(in: userText, prefixes: ["constraint:", "ограничение:"]) {
            result.append(.init(key: "task.constraints", value: value, confidence: 0.85))
        }

        if let value = extractValue(in: userText, prefixes: ["step:", "шаг:"]) {
            result.append(.init(key: "task.current_step", value: value, confidence: 0.8))
        }

        if userText.contains("?") {
            result.append(.init(key: "task.open_question", value: userText, confidence: 0.75))
        }

        if let value = extractValue(in: assistantText, prefixes: ["decision:", "решение:"]) {
            result.append(.init(key: "task.decision", value: value, confidence: 0.8))
        }

        return result
    }

    private func merge(
        active: [WorkingMemoryItem],
        with candidates: [WorkingMemoryCandidate],
        sessionID: UUID,
        branchID: UUID
    ) -> [WorkingMemoryItem] {
        var map = Dictionary(uniqueKeysWithValues: active.map { ($0.key, $0) })
        let now = Date()
        let taskID = branchID.uuidString

        for candidate in candidates {
            let trimmedValue = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }

            let current = map[candidate.key]
            map[candidate.key] = WorkingMemoryItem(
                id: current?.id ?? UUID(),
                sessionID: sessionID,
                branchID: branchID,
                taskID: taskID,
                key: candidate.key,
                value: trimmedValue,
                status: .active,
                confidence: candidate.confidence,
                updatedAt: now
            )
        }

        return map.values.sorted { $0.key < $1.key }
    }

    private func resolveKeys(from userText: String, assistantText: String) -> [String] {
        let markerSet = ["done", "completed", "resolved", "выполнено", "закрыто", "решено"]
        let combined = "\(userText.lowercased()) \(assistantText.lowercased())"
        let hasCompletionMarker = markerSet.contains { combined.contains($0) }
        guard hasCompletionMarker else { return [] }
        return ["task.current_step", "task.open_question"]
    }

    private func extractValue(in text: String, prefixes: [String]) -> String? {
        let lines = text.split(separator: "\n").map(String.init)
        for line in lines {
            let lowercasedLine = line.lowercased()
            for prefix in prefixes where lowercasedLine.hasPrefix(prefix) {
                let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
}

final class UpdateLongTermMemoryUseCase: UpdateLongTermMemoryUseCaseProtocol {
    private let longTermRepository: LongTermMemoryRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol
    private let llmClient: LLMClientProtocol
    private let legacyFactsRepository: FactsRepositoryProtocol?
    private let decoder = JSONDecoder()
    private let threshold = 0.7

    init(
        longTermRepository: LongTermMemoryRepositoryProtocol,
        messageRepository: MessageRepositoryProtocol,
        llmClient: LLMClientProtocol,
        legacyFactsRepository: FactsRepositoryProtocol?
    ) {
        self.longTermRepository = longTermRepository
        self.messageRepository = messageRepository
        self.llmClient = llmClient
        self.legacyFactsRepository = legacyFactsRepository
    }

    func execute(sessionID: UUID, branchID: UUID, latestUserMessage: String, settings: LLMSettings) async throws {
        let trimmed = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try await migrateStickyFactsIfNeeded(sessionID: sessionID)
        let existing = try await longTermRepository.fetch(sessionID: sessionID, namespaces: nil)
        let extractionMessages = try await buildExtractionMessages(branchID: branchID, latestUserMessage: trimmed)
        let extracted = try await extractMemoryUsingLLM(messages: extractionMessages, settings: settings)
        let merged = mergeMemory(existing: existing, with: extracted, sessionID: sessionID)
        if !merged.isEmpty {
            try await longTermRepository.upsert(sessionID: sessionID, items: merged)
        }
    }

    private func extractMemoryUsingLLM(messages: [ChatMessage], settings: LLMSettings) async throws -> [LongTermMemoryCandidate] {
        let response = try await llmClient.send(
            request: LLMRequest(
                systemPrompt: """
                You extract durable long-term memory.
                Return strict JSON object with optional keys:
                profile, decisions, knowledge.
                Each value must be a short string.
                Exclude volatile or turn-local details.
                """,
                shortTermMessages: messages,
                workingMemory: [],
                longTermMemory: [],
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
        let decoded = try decoder.decode(LLMLongTermExtractionResult.self, from: data)
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

    private func mergeMemory(
        existing: [LongTermMemoryItem],
        with extracted: [LongTermMemoryCandidate],
        sessionID: UUID
    ) -> [LongTermMemoryItem] {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ("\($0.namespace.rawValue)|\($0.key)", $0) })
        let now = Date()

        for candidate in extracted where candidate.confidence >= threshold {
            let value = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let mapKey = "\(candidate.namespace.rawValue)|\(candidate.key)"

            let current = map[mapKey]
            map[mapKey] = LongTermMemoryItem(
                id: current?.id ?? UUID(),
                sessionID: sessionID,
                namespace: candidate.namespace,
                key: candidate.key,
                value: value,
                confidence: candidate.confidence,
                source: candidate.source,
                updatedAt: now
            )
        }

        return map.values.sorted {
            if $0.namespace != $1.namespace {
                return $0.namespace.rawValue < $1.namespace.rawValue
            }
            return $0.key < $1.key
        }
    }

    private func migrateStickyFactsIfNeeded(sessionID: UUID) async throws {
        guard let legacyFactsRepository else { return }
        let existing = try await longTermRepository.fetch(sessionID: sessionID, namespaces: nil)
        guard existing.isEmpty else { return }

        let stickyFacts = try await legacyFactsRepository.fetchFacts(sessionID: sessionID)
        guard !stickyFacts.isEmpty else { return }

        let converted = stickyFacts.map(LongTermMemoryItem.init(stickyFact:))
        try await longTermRepository.upsert(sessionID: sessionID, items: converted)
    }
}

private struct WorkingMemoryCandidate {
    let key: String
    let value: String
    let confidence: Double
}

private struct LongTermMemoryCandidate {
    let namespace: LongTermMemoryNamespace
    let key: String
    let value: String
    let confidence: Double
    let source: String
}

private struct LLMLongTermExtractionResult: Decodable {
    let profile: String?
    let decisions: String?
    let knowledge: String?

    var candidates: [LongTermMemoryCandidate] {
        var result: [LongTermMemoryCandidate] = []
        if let profile, !profile.isEmpty {
            result.append(.init(namespace: .profile, key: "summary", value: profile, confidence: 0.8, source: "llm-extraction"))
        }
        if let decisions, !decisions.isEmpty {
            result.append(.init(namespace: .decisions, key: "latest", value: decisions, confidence: 0.8, source: "llm-extraction"))
        }
        if let knowledge, !knowledge.isEmpty {
            result.append(.init(namespace: .knowledge, key: "summary", value: knowledge, confidence: 0.75, source: "llm-extraction"))
        }
        return result
    }
}

final class SendMessageUseCase: SendMessageUseCaseProtocol {
    private let settingsRepository: SettingsRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol
    private let llmClient: LLMClientProtocol
    private let buildMemoryContextUseCase: BuildMemoryContextUseCaseProtocol
    private let updateShortTermMemoryUseCase: UpdateShortTermMemoryUseCaseProtocol
    private let updateWorkingMemoryUseCase: UpdateWorkingMemoryUseCaseProtocol
    private let updateLongTermMemoryUseCase: UpdateLongTermMemoryUseCaseProtocol
    private let metricsRepository: MetricsRepositoryProtocol

    init(
        settingsRepository: SettingsRepositoryProtocol,
        messageRepository: MessageRepositoryProtocol,
        llmClient: LLMClientProtocol,
        buildMemoryContextUseCase: BuildMemoryContextUseCaseProtocol,
        updateShortTermMemoryUseCase: UpdateShortTermMemoryUseCaseProtocol,
        updateWorkingMemoryUseCase: UpdateWorkingMemoryUseCaseProtocol,
        updateLongTermMemoryUseCase: UpdateLongTermMemoryUseCaseProtocol,
        metricsRepository: MetricsRepositoryProtocol
    ) {
        self.settingsRepository = settingsRepository
        self.messageRepository = messageRepository
        self.llmClient = llmClient
        self.buildMemoryContextUseCase = buildMemoryContextUseCase
        self.updateShortTermMemoryUseCase = updateShortTermMemoryUseCase
        self.updateWorkingMemoryUseCase = updateWorkingMemoryUseCase
        self.updateLongTermMemoryUseCase = updateLongTermMemoryUseCase
        self.metricsRepository = metricsRepository
    }

    func execute(sessionID: UUID, branchID: UUID, userText: String) async throws -> ChatMessage {
        let userMessage = ChatMessage(branchID: branchID, role: .user, content: userText)
        try await messageRepository.saveMessage(userMessage)

        let settings = try await settingsRepository.fetchSettings(sessionID: sessionID)
        try await updateShortTermMemoryUseCase.execute(sessionID: sessionID, branchID: branchID, windowSize: settings.windowSize)
        try? await updateWorkingMemoryUseCase.execute(
            sessionID: sessionID,
            branchID: branchID,
            latestUserMessage: userText,
            latestAssistantMessage: nil
        )
        try? await updateLongTermMemoryUseCase.execute(
            sessionID: sessionID,
            branchID: branchID,
            latestUserMessage: userText,
            settings: settings
        )

        let context = try await buildMemoryContextUseCase.execute(sessionID: sessionID, branchID: branchID, settings: settings)
        let request = LLMRequest(
            systemPrompt: "You are a helpful assistant.",
            shortTermMessages: context.shortTermMessages,
            workingMemory: context.workingMemory,
            longTermMemory: context.longTermMemory,
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

        try await updateShortTermMemoryUseCase.execute(sessionID: sessionID, branchID: branchID, windowSize: settings.windowSize)
        try? await updateWorkingMemoryUseCase.execute(
            sessionID: sessionID,
            branchID: branchID,
            latestUserMessage: userText,
            latestAssistantMessage: assistantMessage.content
        )

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

    /// Создаёт use case добавления checkpoint к ветке.
    init(branchRepository: BranchRepositoryProtocol) {
        self.branchRepository = branchRepository
    }

    /// Создаёт checkpoint для выбранного сообщения ветки.
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

    /// Создаёт use case создания новой ветки.
    init(branchRepository: BranchRepositoryProtocol) {
        self.branchRepository = branchRepository
    }

    /// Создаёт новую ветку в рамках сессии.
    func execute(sessionID: UUID, parentCheckpointID: UUID?, name: String) async throws -> ChatBranch {
        // Создание ветки не переключает сессию автоматически:
        // переключение выполняется отдельным use case (SwitchBranchUseCase).
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

    /// Создаёт use case записи системного сообщения о создании ветки.
    init(messageRepository: MessageRepositoryProtocol) {
        self.messageRepository = messageRepository
    }

    /// Добавляет в ветку служебное сообщение о её происхождении.
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

    /// Создаёт use case переключения активной ветки сессии.
    init(sessionRepository: ChatSessionRepositoryProtocol) {
        self.sessionRepository = sessionRepository
    }

    /// Переключает активную ветку в сессии и возвращает обновлённую сессию.
    func execute(sessionID: UUID, targetBranchID: UUID) async throws -> ChatSession {
        // Переключение ветки — это изменение только activeBranchID у сессии.
        // Отдельной проверки "существует ли branchID" здесь нет:
        // валидацию должен обеспечивать вызывающий слой (обычно ViewModel/репозиторий).
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

    /// Создаёт use case сохранения настроек сессии.
    init(settingsRepository: SettingsRepositoryProtocol) {
        self.settingsRepository = settingsRepository
    }

    /// Сохраняет настройки модели и контекста для сессии.
    func execute(sessionID: UUID, settings: LLMSettings) async throws {
        try await settingsRepository.saveSettings(sessionID: sessionID, settings: settings)
    }
}

final class FetchSettingsUseCase: FetchSettingsUseCaseProtocol {
    private let settingsRepository: SettingsRepositoryProtocol

    /// Создаёт use case загрузки настроек сессии.
    init(settingsRepository: SettingsRepositoryProtocol) {
        self.settingsRepository = settingsRepository
    }

    /// Возвращает актуальные настройки LLM для сессии.
    func execute(sessionID: UUID) async throws -> LLMSettings {
        try await settingsRepository.fetchSettings(sessionID: sessionID)
    }
}

final class CollectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol {
    private let metricsRepository: MetricsRepositoryProtocol

    /// Создаёт use case агрегирования метрик ветки.
    init(metricsRepository: MetricsRepositoryProtocol) {
        self.metricsRepository = metricsRepository
    }

    /// Возвращает сводку метрик по выбранной ветке текущей сессии.
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

    /// Создаёт use case чтения API-ключа из безопасного хранилища.
    init(apiKeyStore: APIKeyStoreProtocol) {
        self.apiKeyStore = apiKeyStore
    }

    /// Читает API-ключ из Keychain.
    func execute() throws -> String? {
        try apiKeyStore.fetchAPIKey()
    }
}

final class SaveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol {
    private let apiKeyStore: APIKeyStoreProtocol

    /// Создаёт use case сохранения API-ключа в безопасное хранилище.
    init(apiKeyStore: APIKeyStoreProtocol) {
        self.apiKeyStore = apiKeyStore
    }

    /// Сохраняет API-ключ; если строка пустая после trim, удаляет ключ.
    func execute(apiKey: String) throws {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            try apiKeyStore.deleteAPIKey()
            return
        }
        try apiKeyStore.saveAPIKey(normalizedKey)
    }

    /// Явно удаляет API-ключ из Keychain.
    func delete() throws {
        try apiKeyStore.deleteAPIKey()
    }
}
