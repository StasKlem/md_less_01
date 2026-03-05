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
        windowSize: Int
    ) -> [ChatMessage] {
        let sourceMessages = snapshot?.messages ?? fallbackMessages
        return Array(sourceMessages.suffix(max(1, windowSize)))
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

    func execute(sessionID: UUID, branchID: UUID, windowSize: Int) async throws -> MemoryWriteEvent? {
        let previous = try await shortTermRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID)
        let allMessages = try await messageRepository.fetchMessages(branchID: branchID)
            .filter { $0.role != .system }

        let normalizedWindowSize = max(1, windowSize)
        let currentMessages = Array(allMessages.suffix(normalizedWindowSize))
        let snapshot = ShortTermMemorySnapshot(
            sessionID: sessionID,
            branchID: branchID,
            messages: currentMessages,
            windowSize: normalizedWindowSize,
            updatedAt: Date()
        )
        try await shortTermRepository.saveSnapshot(snapshot)

        let oldMessageIDs = previous?.messages.map(\.id) ?? []
        let newMessageIDs = currentMessages.map(\.id)
        guard oldMessageIDs != newMessageIDs else { return nil }

        let oldIDSet = Set(oldMessageIDs)
        let addedMessages = currentMessages.filter { !oldIDSet.contains($0.id) }
        let detailsSource = addedMessages.isEmpty ? currentMessages : addedMessages
        let details = detailsSource
            .map { message in
                "\(message.role.rawValue): \(normalizeMemoryText(message.content))"
            }
            .joined(separator: " | ")

        return MemoryWriteEvent(
            layer: .shortTerm,
            details: "сохранено: \(details)"
        )
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
    ) async throws -> [MemoryWriteEvent] {
        let userText = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return [] }

        let active = try await workingMemoryRepository.fetchActive(sessionID: sessionID, branchID: branchID)
        let extracted = extractCandidates(from: userText, assistantText: latestAssistantMessage ?? "")
        let mergeResult = merge(active: active, with: extracted, sessionID: sessionID, branchID: branchID)
        let merged = mergeResult.items
        if !merged.isEmpty {
            try await workingMemoryRepository.upsert(sessionID: sessionID, branchID: branchID, items: merged)
        }

        let resolvedKeys = resolveKeys(from: userText, assistantText: latestAssistantMessage ?? "")
        if !resolvedKeys.isEmpty {
            try await workingMemoryRepository.resolve(sessionID: sessionID, branchID: branchID, keys: resolvedKeys)
        }

        guard !mergeResult.changedEntries.isEmpty else { return [] }
        let entries = mergeResult.changedEntries.sorted().joined(separator: " | ")
        return [MemoryWriteEvent(layer: .working, details: "сохранено: \(entries)")]
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
    ) -> (items: [WorkingMemoryItem], changedEntries: [String]) {
        var map = Dictionary(uniqueKeysWithValues: active.map { ($0.key, $0) })
        let now = Date()
        let taskID = branchID.uuidString
        var changedEntries: [String] = []

        for candidate in candidates {
            let trimmedValue = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }

            let current = map[candidate.key]
            if current?.value != trimmedValue || current?.status != .active {
                changedEntries.append("\(candidate.key)=\(normalizeMemoryText(trimmedValue))")
            }
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

        return (map.values.sorted { $0.key < $1.key }, Array(Set(changedEntries)))
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

    func execute(sessionID: UUID, branchID: UUID, latestUserMessage: String, settings: LLMSettings) async throws -> [MemoryWriteEvent] {
        let trimmed = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        try await migrateStickyFactsIfNeeded(sessionID: sessionID)
        let existing = try await longTermRepository.fetch(sessionID: sessionID, namespaces: nil)
        let extractionMessages = try await buildExtractionMessages(branchID: branchID, latestUserMessage: trimmed)
        let extracted = try await extractMemoryUsingLLM(messages: extractionMessages, settings: settings)
        let mergeResult = mergeMemory(existing: existing, with: extracted, sessionID: sessionID)
        let merged = mergeResult.items
        if !merged.isEmpty {
            try await longTermRepository.upsert(sessionID: sessionID, items: merged)
        }
        guard !mergeResult.changedEntries.isEmpty else { return [] }
        let entries = mergeResult.changedEntries.sorted().joined(separator: " | ")
        return [MemoryWriteEvent(layer: .longTerm, details: "сохранено: \(entries)")]
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
                    temperature: 0.0,
                    windowSize: 1
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
    ) -> (items: [LongTermMemoryItem], changedEntries: [String]) {
        var map = Dictionary(uniqueKeysWithValues: existing.map { ("\($0.namespace.rawValue)|\($0.key)", $0) })
        let now = Date()
        var changedEntries: [String] = []

        for candidate in extracted where candidate.confidence >= threshold {
            let value = candidate.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let mapKey = "\(candidate.namespace.rawValue)|\(candidate.key)"

            let current = map[mapKey]
            if current?.value != value {
                changedEntries.append("\(candidate.namespace.rawValue).\(candidate.key)=\(normalizeMemoryText(value))")
            }
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

        let sorted = map.values.sorted {
            if $0.namespace != $1.namespace {
                return $0.namespace.rawValue < $1.namespace.rawValue
            }
            return $0.key < $1.key
        }
        return (sorted, Array(Set(changedEntries)))
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

/// Оркеструет полный цикл обработки пользовательского сообщения в рамках ветки диалога.
///
/// Назначение:
/// - принять входной `userText`;
/// - сохранить сообщение пользователя;
/// - обновить все релевантные слои памяти;
/// - сформировать запрос в LLM на основе актуального memory context;
/// - сохранить ответ ассистента и технические метрики запроса.
///
/// Порядок обновления памяти фиксированный и важен для консистентности:
/// 1. `short-term` — слайдинг-окно последних сообщений (учитывает `windowSize` из настроек).
/// 2. `working` — оперативные рабочие факты/цели/ограничения из текущего контекста.
/// 3. `long-term` — устойчивые знания, извлеченные через LLM.
///
/// После получения ответа ассистента `short-term` и `working` обновляются повторно,
/// чтобы в следующем ходу модель получила уже завершенное состояние текущего обмена.
///
/// Важно:
/// - обновление short-term выполняется строго (`throws`);
/// - обновления working/long-term выполняются в best-effort режиме (`try?`),
///   чтобы деградация отдельных memory-адаптеров не блокировала основной ответ ассистента.
final class SendMessageUseCase: SendMessageUseCaseProtocol {
    private let settingsRepository: SettingsRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol
    private let llmClient: LLMClientProtocol
    private let buildMemoryContextUseCase: BuildMemoryContextUseCaseProtocol
    private let updateShortTermMemoryUseCase: UpdateShortTermMemoryUseCaseProtocol
    private let updateWorkingMemoryUseCase: UpdateWorkingMemoryUseCaseProtocol
    private let updateLongTermMemoryUseCase: UpdateLongTermMemoryUseCaseProtocol
    private let metricsRepository: MetricsRepositoryProtocol

    /// Создает use case отправки сообщения и внедряет все необходимые зависимости.
    ///
    /// - Parameters:
    ///   - settingsRepository: источник LLM-настроек сессии.
    ///   - messageRepository: хранилище сообщений ветки.
    ///   - llmClient: клиент модели для генерации ответа.
    ///   - buildMemoryContextUseCase: сборщик финального memory context перед вызовом LLM.
    ///   - updateShortTermMemoryUseCase: обновление краткосрочного слоя памяти.
    ///   - updateWorkingMemoryUseCase: обновление рабочего слоя памяти.
    ///   - updateLongTermMemoryUseCase: обновление долговременного слоя памяти.
    ///   - metricsRepository: хранилище телеметрии запроса/ответа модели.
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

    /// Выполняет end-to-end обработку пользовательского сообщения.
    ///
    /// Полный сценарий:
    /// 1. Сохраняет входное сообщение пользователя.
    /// 2. Загружает настройки сессии.
    /// 3. Обновляет память после user-turn:
    ///    - short-term (strict),
    ///    - working (best-effort),
    ///    - long-term (best-effort).
    /// 4. Строит `MemoryContext` и отправляет запрос в LLM.
    /// 5. Сохраняет сообщение ассистента.
    /// 6. Повторно обновляет short-term и working после assistant-turn.
    /// 7. Сохраняет метрику запроса (latency/tokens).
    ///
    /// Ошибки:
    /// - любые ошибки критичных этапов (`saveMessage`, `fetchSettings`, `send`, `appendMetric`)
    ///   пробрасываются наружу;
    /// - ошибки working/long-term update подавляются локально, чтобы не сорвать основной поток ответа.
    ///
    /// - Parameters:
    ///   - sessionID: идентификатор текущей сессии.
    ///   - branchID: идентификатор активной ветки.
    ///   - userText: текст сообщения пользователя.
    /// - Returns: сохраненное сообщение ассистента.
    func execute(
        sessionID: UUID,
        branchID: UUID,
        userText: String,
        assistantInstruction: String?
    ) async throws -> ChatMessage {
        let userMessage = ChatMessage(branchID: branchID, role: .user, content: userText)
        try await messageRepository.saveMessage(userMessage)

        let settings = try await settingsRepository.fetchSettings(sessionID: sessionID)
        if let event = try await updateShortTermMemoryUseCase.execute(sessionID: sessionID, branchID: branchID, windowSize: settings.windowSize) {
            try await appendMemoryEventMessage(branchID: branchID, event: event)
        }
        let workingUserEvents = (try? await updateWorkingMemoryUseCase.execute(
            sessionID: sessionID,
            branchID: branchID,
            latestUserMessage: userText,
            latestAssistantMessage: nil
        )) ?? []
        try await appendMemoryEventMessages(branchID: branchID, events: workingUserEvents)

        let longTermEvents = (try? await updateLongTermMemoryUseCase.execute(
            sessionID: sessionID,
            branchID: branchID,
            latestUserMessage: userText,
            settings: settings
        )) ?? []
        try await appendMemoryEventMessages(branchID: branchID, events: longTermEvents)

        let context = try await buildMemoryContextUseCase.execute(sessionID: sessionID, branchID: branchID, settings: settings)
        let systemPrompt = makeSystemPrompt(extraInstruction: assistantInstruction)
        let request = LLMRequest(
            systemPrompt: systemPrompt,
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

        if let event = try await updateShortTermMemoryUseCase.execute(sessionID: sessionID, branchID: branchID, windowSize: settings.windowSize) {
            try await appendMemoryEventMessage(branchID: branchID, event: event)
        }
        let workingAssistantEvents = (try? await updateWorkingMemoryUseCase.execute(
            sessionID: sessionID,
            branchID: branchID,
            latestUserMessage: userText,
            latestAssistantMessage: assistantMessage.content
        )) ?? []
        try await appendMemoryEventMessages(branchID: branchID, events: workingAssistantEvents)

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

    private func makeSystemPrompt(extraInstruction: String?) -> String {
        let base = "You are a helpful assistant."
        guard let extraInstruction else { return base }
        let trimmed = extraInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return "\(base)\n\n\(trimmed)"
    }

    /// Добавляет системные сообщения о событиях записи памяти.
    ///
    /// Каждый `MemoryWriteEvent` превращается в отдельное системное сообщение,
    /// чтобы история ветки содержала трассировку изменений памяти.
    ///
    /// - Parameters:
    ///   - branchID: идентификатор ветки, куда пишутся системные сообщения.
    ///   - events: список событий записи в память.
    private func appendMemoryEventMessages(branchID: UUID, events: [MemoryWriteEvent]) async throws {
        for event in events {
            try await appendMemoryEventMessage(branchID: branchID, event: event)
        }
    }

    /// Добавляет одно системное сообщение о записи в конкретный слой памяти.
    ///
    /// Формат сообщения: `Память [<слой>] сохранено: ...`
    ///
    /// - Parameters:
    ///   - branchID: идентификатор ветки.
    ///   - event: событие записи памяти с деталями.
    private func appendMemoryEventMessage(branchID: UUID, event: MemoryWriteEvent) async throws {
        let systemMessage = ChatMessage(
            branchID: branchID,
            role: .system,
            content: "Память [\(event.layer.rawValue)] \(event.details)"
        )
        try await messageRepository.saveMessage(systemMessage)
    }
}

private func normalizeMemoryText(_ text: String, maxLength: Int = 120) -> String {
    let flattened = text
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard flattened.count > maxLength else { return flattened }
    return String(flattened.prefix(maxLength)) + "..."
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
