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

final class FetchVacationPlannerMCPToolsUseCase: FetchVacationPlannerMCPToolsUseCaseProtocol {
    private let toolDiscoveryService: MCPToolDiscoveryServiceProtocol
    private let endpointURL: URL

    init(
        toolDiscoveryService: MCPToolDiscoveryServiceProtocol,
        endpointURL: URL = URL(string: "stdio://open-weather")!
    ) {
        self.toolDiscoveryService = toolDiscoveryService
        self.endpointURL = endpointURL
    }

    func execute() async -> String {
        do {
            let tools = try await toolDiscoveryService.fetchTools(serverURL: endpointURL)
            return formatToolsMessage(tools)
        } catch {
            return "MCP open-weather: не удалось получить tools (\(error.localizedDescription))."
        }
    }

    private func formatToolsMessage(_ tools: [MCPToolSummary]) -> String {
        var lines: [String] = [
            "MCP open-weather подключен.",
            "Доступные tools:"
        ]

        if tools.isEmpty {
            lines.append("- список пуст")
            return lines.joined(separator: "\n")
        }

        for tool in tools {
            let description = tool.description?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if description.isEmpty {
                lines.append("- \(tool.name)")
            } else {
                lines.append("- \(tool.name): \(description)")
            }
        }
        return lines.joined(separator: "\n")
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
                    windowSize: 1,
                    isRAGEnabled: settings.isRAGEnabled,
                    ragChunkingStrategy: settings.ragChunkingStrategy,
                    isMemoryEnabled: settings.isMemoryEnabled,
                    plannerInvariants: settings.plannerInvariants
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
/// Обновления выполняются только если в `LLMSettings` включен `isMemoryEnabled`.
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
    private let ragUseCaseFacade: RAGUseCaseFacadeProtocol?
    private let ragDocumentsProvider: @Sendable () -> [URL]
    private let ragIndexState: RAGIndexState

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
    ///   - ragUseCaseFacade: фасад RAG-пайплайна (опционально).
    ///   - ragDocumentsProvider: провайдер списка документов для индексации RAG.
    ///   - initialIndexedRAGStrategy: стратегия, уже проиндексированная на этапе старта приложения.
    init(
        settingsRepository: SettingsRepositoryProtocol,
        messageRepository: MessageRepositoryProtocol,
        llmClient: LLMClientProtocol,
        buildMemoryContextUseCase: BuildMemoryContextUseCaseProtocol,
        updateShortTermMemoryUseCase: UpdateShortTermMemoryUseCaseProtocol,
        updateWorkingMemoryUseCase: UpdateWorkingMemoryUseCaseProtocol,
        updateLongTermMemoryUseCase: UpdateLongTermMemoryUseCaseProtocol,
        metricsRepository: MetricsRepositoryProtocol,
        ragUseCaseFacade: RAGUseCaseFacadeProtocol? = nil,
        ragDocumentsProvider: @escaping @Sendable () -> [URL] = { [] },
        initialIndexedRAGStrategy: ChunkingStrategyType? = nil
    ) {
        self.settingsRepository = settingsRepository
        self.messageRepository = messageRepository
        self.llmClient = llmClient
        self.buildMemoryContextUseCase = buildMemoryContextUseCase
        self.updateShortTermMemoryUseCase = updateShortTermMemoryUseCase
        self.updateWorkingMemoryUseCase = updateWorkingMemoryUseCase
        self.updateLongTermMemoryUseCase = updateLongTermMemoryUseCase
        self.metricsRepository = metricsRepository
        self.ragUseCaseFacade = ragUseCaseFacade
        self.ragDocumentsProvider = ragDocumentsProvider
        self.ragIndexState = RAGIndexState(initialStrategy: initialIndexedRAGStrategy)
    }

    /// Выполняет end-to-end обработку пользовательского сообщения.
    ///
/// Полный сценарий:
/// 1. Сохраняет входное сообщение пользователя.
/// 2. Загружает настройки сессии.
/// 3. Если включено сохранение в память, обновляет память после user-turn:
///    - short-term (strict),
///    - working (best-effort),
///    - long-term (best-effort).
/// 4. Строит `MemoryContext` и отправляет запрос в LLM.
/// 5. Сохраняет сообщение ассистента.
/// 6. Если включено сохранение в память, повторно обновляет short-term и working после assistant-turn.
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
        // 1) Фиксируем user-turn в истории ветки как первоисточник для всех следующих шагов.
        // Без этого память и контекст могли бы строиться по устаревшему состоянию диалога.
        let userMessage = ChatMessage(branchID: branchID, role: .user, content: userText)
        try await messageRepository.saveMessage(userMessage)

        // 2) Получаем актуальные настройки сессии (модель, лимиты, windowSize и т.д.),
        // которые будут использоваться и для памяти, и для вызова LLM.
        let settings = try await settingsRepository.fetchSettings(sessionID: sessionID)
        if settings.isMemoryEnabled {
            // 3) Обновляем short-term memory строго: это критичный слой для ближайшего контекста.
            // Если обновление прошло и вернулось событие записи памяти, сохраняем это событие в историю.
            if let event = try await updateShortTermMemoryUseCase.execute(sessionID: sessionID, branchID: branchID, windowSize: settings.windowSize) {
                try await appendMemoryEventMessage(branchID: branchID, event: event)
            }

            // 4) Обновляем working memory после сообщения пользователя.
            // Этот шаг best-effort: при сбое не прерываем основной сценарий ответа ассистента.
            let workingUserEvents = (try? await updateWorkingMemoryUseCase.execute(
                sessionID: sessionID,
                branchID: branchID,
                latestUserMessage: userText,
                latestAssistantMessage: nil
            )) ?? []
            // Даже если событий нет, метод безопасно обработает пустой массив.
            try await appendMemoryEventMessages(branchID: branchID, events: workingUserEvents)

            // 5) Пытаемся обновить long-term memory (устойчивые факты/выводы).
            // Это тоже best-effort, чтобы временные проблемы extraction-пайплайна не ломали чат.
            let longTermEvents = (try? await updateLongTermMemoryUseCase.execute(
                sessionID: sessionID,
                branchID: branchID,
                latestUserMessage: userText,
                settings: settings
            )) ?? []
            try await appendMemoryEventMessages(branchID: branchID, events: longTermEvents)
        }

        // 6) Собираем единый memory context из всех слоев памяти.
        // Этот контекст отправится в модель вместе с system prompt и настройками.
        let context = try await buildMemoryContextUseCase.execute(sessionID: sessionID, branchID: branchID, settings: settings)
        let ragContextBlock = await buildRAGContextIfEnabled(settings: settings, userText: userText)
        log(ragContextBlock)
        let systemPrompt = makeSystemPrompt(extraInstruction: assistantInstruction, ragContextBlock: ragContextBlock)
        let request = LLMRequest(
            systemPrompt: systemPrompt,
            shortTermMessages: context.shortTermMessages,
            workingMemory: context.workingMemory,
            longTermMemory: context.longTermMemory,
            settings: settings
        )
        // 7) Запрашиваем ответ у LLM. На этом этапе модель уже видит актуализированную память.
        let response = try await llmClient.send(request: request)

        // 8) Преобразуем ответ модели в доменную сущность сообщения ассистента
        // и сохраняем его в историю ветки.
        let assistantMessage = ChatMessage(
            branchID: branchID,
            role: .assistant,
            content: response.content,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            latencyMs: response.latencyMs
        )
        try await messageRepository.saveMessage(assistantMessage)

        if settings.isMemoryEnabled {
            // 9) После assistant-turn снова обновляем short-term memory,
            // чтобы следующий запрос видел завершенный обмен user+assistant.
            if let event = try await updateShortTermMemoryUseCase.execute(sessionID: sessionID, branchID: branchID, windowSize: settings.windowSize) {
                try await appendMemoryEventMessage(branchID: branchID, event: event)
            }

            // 10) Повторно обновляем working memory уже с текстом ассистента.
            // Это позволяет зафиксировать новые задачи, решения и ограничения из полного обмена.
            let workingAssistantEvents = (try? await updateWorkingMemoryUseCase.execute(
                sessionID: sessionID,
                branchID: branchID,
                latestUserMessage: userText,
                latestAssistantMessage: assistantMessage.content
            )) ?? []
            try await appendMemoryEventMessages(branchID: branchID, events: workingAssistantEvents)
        }

        // 11) Формируем метрику запроса для наблюдаемости:
        // latency, токены и временной интервал выполнения.
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

    private func makeSystemPrompt(extraInstruction: String?, ragContextBlock: String?) -> String {
        // Базовое поведение ассистента по умолчанию.
        let base = "You are a helpful assistant."

        var blocks: [String] = [base]

        if let extraInstruction {
            let trimmed = extraInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(trimmed)
            }
        }

        if let ragContextBlock {
            blocks.append(ragContextBlock)
        }

        return blocks.joined(separator: "\n\n")
    }

    private func buildRAGContextIfEnabled(settings: LLMSettings, userText: String) async -> String? {
        guard settings.isRAGEnabled, let ragUseCaseFacade else { return nil }

        do {
            try await ensureRAGIndexIsReady(ragUseCaseFacade, strategy: settings.ragChunkingStrategy)
            if settings.isRAGPostFilteringEnabled {
                let topKBeforeFiltering = max(1, settings.ragTopKBeforeFiltering)
                let topKAfterFiltering = max(1, settings.ragTopKAfterFiltering)
                let normalizedThreshold = normalizedRAGThreshold(settings.ragRelevanceThreshold)
                let results = try await ragUseCaseFacade.search(query: userText, topK: topKBeforeFiltering)
                let filtered = results.filter { Double($0.score) >= normalizedThreshold }
                let finalResults = Array(filtered.prefix(topKAfterFiltering))
                logRAGPostFilteringStats(
                    total: results.count,
                    afterThreshold: filtered.count,
                    finalCount: finalResults.count,
                    threshold: normalizedThreshold,
                    topKBeforeFiltering: topKBeforeFiltering,
                    topKAfterFiltering: topKAfterFiltering
                )
                guard !finalResults.isEmpty else { return nil }
                return formatRAGContext(finalResults)
            }

            let legacyResults = try await ragUseCaseFacade.search(query: userText, topK: 4)
            guard !legacyResults.isEmpty else { return nil }
            return formatRAGContext(legacyResults)
        } catch {
#if DEBUG
            print("[RAG] Контекст не собран: \(error)")
#endif
            return nil
        }
    }

    private func normalizedRAGThreshold(_ threshold: Double) -> Double {
        min(1.0, max(0.0, threshold))
    }

    private func logRAGPostFilteringStats(
        total: Int,
        afterThreshold: Int,
        finalCount: Int,
        threshold: Double,
        topKBeforeFiltering: Int,
        topKAfterFiltering: Int
    ) {
        let removedByThreshold = max(0, total - afterThreshold)
        let removedByTopK = max(0, afterThreshold - finalCount)
        let totalRemoved = max(0, total - finalCount)
        print(
            "[RAG] Пост-фильтрация: total=\(total), threshold>=\(String(format: "%.2f", threshold)), " +
            "afterThreshold=\(afterThreshold), final=\(finalCount), removedByThreshold=\(removedByThreshold), " +
            "removedByTopK=\(removedByTopK), totalFilteredOut=\(totalRemoved), " +
            "topKBefore=\(topKBeforeFiltering), topKAfter=\(topKAfterFiltering)"
        )
    }

    private func ensureRAGIndexIsReady(
        _ ragUseCaseFacade: RAGUseCaseFacadeProtocol,
        strategy: ChunkingStrategyType
    ) async throws {
        if await ragIndexState.isReady(for: strategy) {
            return
        }

        let documents = ragDocumentsProvider()
        guard !documents.isEmpty else {
            return
        }

        _ = try await ragUseCaseFacade.index(documents: documents, strategy: strategy)
        await ragIndexState.markReady(for: strategy)
    }

    private func formatRAGContext(_ results: [SearchResult]) -> String {
        var lines: [String] = [
            "Use these retrieved context snippets if relevant to the user question:",
        ]

        for (index, result) in results.enumerated() {
            let source = URL(fileURLWithPath: result.chunk.source).lastPathComponent
            let section = result.chunk.section ?? "-"
            let text = result.chunk.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("[\(index + 1)] source=\(source) section=\(section) offset=\(result.chunk.offset) text=\(text)")
        }
        return lines.joined(separator: "\n")
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

private actor RAGIndexState {
    private var indexedStrategy: ChunkingStrategyType?

    init(initialStrategy: ChunkingStrategyType? = nil) {
        indexedStrategy = initialStrategy
    }

    func isReady(for strategy: ChunkingStrategyType) -> Bool {
        indexedStrategy == strategy
    }

    func markReady(for strategy: ChunkingStrategyType) {
        indexedStrategy = strategy
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

final class ResetRAGEmbeddingsUseCase: ResetRAGEmbeddingsUseCaseProtocol {
    private let ragUseCaseFacade: RAGUseCaseFacadeProtocol
    private let ragIndexReadinessRepository: RAGIndexReadinessRepositoryProtocol

    /// Создает use case очистки embeddings-индекса RAG.
    init(
        ragUseCaseFacade: RAGUseCaseFacadeProtocol,
        ragIndexReadinessRepository: RAGIndexReadinessRepositoryProtocol
    ) {
        self.ragUseCaseFacade = ragUseCaseFacade
        self.ragIndexReadinessRepository = ragIndexReadinessRepository
    }

    /// Полностью очищает текущее хранилище embeddings RAG.
    func execute() async throws {
        try await ragUseCaseFacade.resetIndex()
        ragIndexReadinessRepository.clearAll()
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

final class ProcessUserAnswerUseCase: ProcessUserAnswerUseCaseProtocol {
    private let answerExtractionService: AnswerExtractionServiceProtocol
    private let confidenceThreshold: Double

    init(
        answerExtractionService: AnswerExtractionServiceProtocol,
        confidenceThreshold: Double = 0.7
    ) {
        self.answerExtractionService = answerExtractionService
        self.confidenceThreshold = confidenceThreshold
    }

    func execute(
        schema: QuestionnaireSchema,
        currentState: QuestionnaireState,
        currentSlots: VacationSlots,
        userText: String,
        settings: LLMSettings,
        source: QuestionnaireAnswerSource
    ) async -> QuestionnaireProcessingResult {
        if source == .form {
            return processFormInput(
                schema: schema,
                currentState: currentState,
                currentSlots: currentSlots,
                userText: userText
            )
        }

        let extractionResult: QuestionnaireExtractionResult
        do {
            extractionResult = try await answerExtractionService.extractFields(
                userText: userText,
                schema: schema,
                currentState: currentState,
                settings: settings
            )
        } catch {
            return fallbackResult(
                schema: schema,
                state: refreshMissing(schema: schema, state: currentState),
                slots: currentSlots,
                warning: "Не удалось разобрать ответ автоматически. Уточним данные вручную.",
                fieldID: nil
            )
        }

        var nextState = currentState
        var answerUpdates: [String: QuestionnaireFieldAnswer] = [:]
        var validationErrors = extractionResult.warnings.map(\.message)
        let now = Date()
        var prioritizedFieldForClarification: String?

        for field in extractionResult.fields {
            guard let definition = schema.field(id: field.fieldID) else { continue }
            let isAmbiguous = extractionResult.warnings.contains {
                $0.fieldID == field.fieldID && $0.code == .ambiguous
            }
            if field.confidence < confidenceThreshold || isAmbiguous {
                if prioritizedFieldForClarification == nil {
                    prioritizedFieldForClarification = field.fieldID
                }
                validationErrors.append("Нужно уточнить поле \(field.fieldID): низкая уверенность.")
                continue
            }
            if validate(value: field.value, for: definition).isEmpty {
                answerUpdates[field.fieldID] = QuestionnaireFieldAnswer(
                    value: field.value,
                    confidence: field.confidence,
                    source: .llmExtraction,
                    updatedAt: now
                )
            } else {
                validationErrors.append("Поле \(field.fieldID) не прошло валидацию.")
                if prioritizedFieldForClarification == nil {
                    prioritizedFieldForClarification = field.fieldID
                }
            }
        }

        for (fieldID, answer) in answerUpdates {
            nextState.answers[fieldID] = answer
        }

        nextState = refreshMissing(schema: schema, state: nextState)
        let mergedSlots = VacationQuestionnaireSchemaAdapter.mergeSlots(current: currentSlots, updates: answerUpdates)

        if !nextState.missingHard.isEmpty {
            let nextField = prioritizedFieldForClarification ?? nextState.missingHard[0]
            return QuestionnaireProcessingResult(
                state: nextState,
                updatedSlots: mergedSlots,
                validationErrors: validationErrors,
                action: .askNextQuestion(
                    fieldID: nextField,
                    warning: validationErrors.isEmpty ? nil : validationErrors.joined(separator: " ")
                )
            )
        }
        if !nextState.missingSoft.isEmpty {
            return QuestionnaireProcessingResult(
                state: nextState,
                updatedSlots: mergedSlots,
                validationErrors: validationErrors,
                action: .warnSoftMissing(
                    message: "Критичные данные собраны. Можно продолжать, но полезно уточнить: \(nextState.missingSoft.joined(separator: ", ")).",
                    suggestedFieldID: nextState.missingSoft[0]
                )
            )
        }
        return QuestionnaireProcessingResult(
            state: nextState,
            updatedSlots: mergedSlots,
            validationErrors: validationErrors,
            action: .proceed
        )
    }

    private func fallbackResult(
        schema: QuestionnaireSchema,
        state: QuestionnaireState,
        slots: VacationSlots,
        warning: String,
        fieldID: String?
    ) -> QuestionnaireProcessingResult {
        let action: QuestionnaireNextAction
        if let fieldID = fieldID ?? state.missingHard.first ?? state.missingSoft.first {
            action = .askNextQuestion(fieldID: fieldID, warning: warning)
        } else {
            action = .warnSoftMissing(message: warning, suggestedFieldID: nil)
        }
        return QuestionnaireProcessingResult(
            state: state,
            updatedSlots: slots,
            validationErrors: [warning],
            action: action
        )
    }

    private func processFormInput(
        schema: QuestionnaireSchema,
        currentState: QuestionnaireState,
        currentSlots: VacationSlots,
        userText: String
    ) -> QuestionnaireProcessingResult {
        do {
            let data = Data(userText.utf8)
            let payload = try JSONDecoder().decode(FormInputPayload.self, from: data)
            let now = Date()
            var updates: [String: QuestionnaireFieldAnswer] = [:]
            for field in payload.fields {
                guard let definition = schema.field(id: field.fieldID) else { continue }
                guard validate(value: field.value, for: definition).isEmpty else { continue }
                updates[field.fieldID] = QuestionnaireFieldAnswer(
                    value: field.value,
                    confidence: 1.0,
                    source: .form,
                    updatedAt: now
                )
            }
            var next = currentState
            for (key, value) in updates {
                next.answers[key] = value
            }
            next = refreshMissing(schema: schema, state: next)
            let merged = VacationQuestionnaireSchemaAdapter.mergeSlots(current: currentSlots, updates: updates)
            if !next.missingHard.isEmpty {
                return QuestionnaireProcessingResult(
                    state: next,
                    updatedSlots: merged,
                    validationErrors: [],
                    action: .askNextQuestion(fieldID: next.missingHard[0], warning: nil)
                )
            }
            if !next.missingSoft.isEmpty {
                return QuestionnaireProcessingResult(
                    state: next,
                    updatedSlots: merged,
                    validationErrors: [],
                    action: .warnSoftMissing(
                        message: "Критичные данные собраны. Можно продолжать, но полезно уточнить: \(next.missingSoft.joined(separator: ", ")).",
                        suggestedFieldID: next.missingSoft[0]
                    )
                )
            }
            return QuestionnaireProcessingResult(
                state: next,
                updatedSlots: merged,
                validationErrors: [],
                action: .proceed
            )
        } catch {
            return fallbackResult(
                schema: schema,
                state: refreshMissing(schema: schema, state: currentState),
                slots: currentSlots,
                warning: "Не удалось применить данные формы. Проверьте заполнение полей.",
                fieldID: nil
            )
        }
    }

    private func refreshMissing(schema: QuestionnaireSchema, state: QuestionnaireState) -> QuestionnaireState {
        var next = state
        next.missingHard = schema.fields
            .filter { $0.requiredLevel == .hard && next.answers[$0.id] == nil }
            .map(\.id)
        next.missingSoft = schema.fields
            .filter { $0.requiredLevel == .soft && next.answers[$0.id] == nil }
            .map(\.id)
        return next
    }

    private func validate(value: QuestionnaireValue, for field: QuestionnaireFieldDefinition) -> [String] {
        var errors: [String] = []
        for rule in field.validators {
            switch rule {
            case .nonEmptyText:
                if case let .text(text) = value {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        errors.append(field.id)
                    }
                } else {
                    errors.append(field.id)
                }
            case .validDateRange:
                if case let .dateRange(range) = value {
                    if range.start > range.end {
                        errors.append(field.id)
                    }
                } else {
                    errors.append(field.id)
                }
            case .positiveMoneyAmount:
                if case let .money(money) = value {
                    if money.total <= 0 {
                        errors.append(field.id)
                    }
                } else {
                    errors.append(field.id)
                }
            case .positiveInteger:
                if case let .integer(number) = value {
                    if number < 1 {
                        errors.append(field.id)
                    }
                } else {
                    errors.append(field.id)
                }
            case .nonEmptyList:
                if case let .stringList(values) = value {
                    if values.isEmpty {
                        errors.append(field.id)
                    }
                } else {
                    errors.append(field.id)
                }
            }
        }
        return errors
    }
}

private struct FormInputPayload: Decodable {
    let fields: [FormInputField]
}

private struct FormInputField: Decodable {
    let fieldID: String
    let value: QuestionnaireValue
}

final class VacationPlannerReducer: VacationPlannerReducerProtocol {
    func reduce(
        snapshot: VacationPlanningSnapshot,
        event: VacationPlanningEvent
    ) -> VacationPlanningTransitionResult {
        let shouldValidateInvariants = snapshot.state == .validatingDestination
        if shouldValidateInvariants {
            let preViolations = VacationPlanningInvariantValidator.validate(
                state: snapshot.state,
                context: snapshot.context,
                snapshotUpdatedAt: snapshot.updatedAt
            )
            if !preViolations.isEmpty {
                return failedTransition(
                    context: snapshot.context,
                    reason: "Нарушение инварианта: \(preViolations.map(\.message).joined(separator: ", "))"
                )
            }
        }

        let transition: VacationPlanningTransitionResult
        switch (snapshot.state, event) {
        case (.idle, .started), (.failed, .started):
            transition = startTransition(snapshot: snapshot)
        case (.idle, .userMessage):
            transition = startTransition(snapshot: snapshot)
        case (_, let .errorOccurred(error)):
            transition = failedTransition(context: snapshot.context, reason: error.failureReason)
        case (.destinationRequest, let .userMessage(text, source)),
             (.failed, let .userMessage(text, source)):
            transition = userMessageTransition(snapshot: snapshot, text: text, source: source)
        case (.validatingDestination, .questionnaireProcessed(let result)):
            transition = questionnaireProcessedTransition(snapshot: snapshot, result: result)
        case (.awaitingPlanApproval, .planApproved):
            transition = planApprovalTransition(snapshot: snapshot)
        case (.awaitingPlanApproval, .revisionRequested(let comment)):
            transition = revisionTransition(context: snapshot.context, comment: comment)
        case (.generateResult, .optionsGenerated(let options)):
            transition = optionsGeneratedTransition(snapshot: snapshot, options: options)
        case (.generateResult, .itineraryGenerated(let itinerary)):
            var context = snapshot.context
            context.itinerary = itinerary
            context.itineraryBuiltAt = Date()
            transition = VacationPlanningTransitionResult(
                nextState: .generateResult,
                nextContext: context,
                effects: [.calculateBudget, .persistSnapshot]
            )
        case (.generateResult, .budgetCalculated(let budget)):
            transition = finalizeGeneratedPlanTransition(snapshot: snapshot, budget: budget)
        default:
            transition = blockedTransition(
                snapshot: snapshot,
                reason: "Переход запрещен: из состояния «\(snapshot.state.title)» нельзя выполнить «\(event.debugName)»."
            )
        }

        let now = Date()
        var validatedContext = transition.nextContext
        validatedContext.updatedAt = now
        if shouldValidateInvariants {
            let postViolations = VacationPlanningInvariantValidator.validate(
                state: transition.nextState,
                context: validatedContext,
                snapshotUpdatedAt: now
            )
            if !postViolations.isEmpty {
                return failedTransition(
                    context: validatedContext,
                    reason: "Нарушение инварианта: \(postViolations.map(\.message).joined(separator: ", "))"
                )
            }
        }

        return VacationPlanningTransitionResult(
            nextState: transition.nextState,
            nextContext: validatedContext,
            effects: transition.effects
        )
    }

    private func userMessageTransition(
        snapshot: VacationPlanningSnapshot,
        text: String,
        source: QuestionnaireAnswerSource
    ) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        context.lastUserMessage = text
        return VacationPlanningTransitionResult(
            nextState: .validatingDestination,
            nextContext: context,
            effects: [.processUserAnswer(text, source), .persistSnapshot]
        )
    }

    private func questionnaireProcessedTransition(
        snapshot: VacationPlanningSnapshot,
        result: QuestionnaireProcessingResult
    ) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        context.questionnaireState = result.state
        context.slots = result.updatedSlots
        context.lastValidationErrors = result.validationErrors

        guard isDestinationValid(in: context) else {
            let warning: String?
            switch result.action {
            case let .askNextQuestion(fieldID, message):
                warning = fieldID == VacationQuestionnaireSchemaAdapter.destinationFieldID
                    ? message
                    : "Не удалось подтвердить место назначения. Уточните направление."
            case let .warnSoftMissing(message, _):
                warning = message
            case .proceed:
                warning = "Не удалось подтвердить место назначения. Уточните направление."
            }
            return VacationPlanningTransitionResult(
                nextState: .destinationRequest,
                nextContext: context,
                effects: [.askQuestion(fieldID: VacationQuestionnaireSchemaAdapter.destinationFieldID, warning: warning), .persistSnapshot]
            )
        }

        context.lastValidationErrors = []
        return VacationPlanningTransitionResult(
            nextState: .awaitingPlanApproval,
            nextContext: context,
            effects: [.askUser(questionKey: .approval), .persistSnapshot]
        )
    }

    private func optionsGeneratedTransition(
        snapshot: VacationPlanningSnapshot,
        options: [VacationOption]
    ) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        context.options = options
        context.selectedOption = options.first
        if options.isEmpty {
            return VacationPlanningTransitionResult(
                nextState: .destinationRequest,
                nextContext: context,
                effects: [
                    .askQuestion(
                        fieldID: VacationQuestionnaireSchemaAdapter.destinationFieldID,
                        warning: "Не удалось подобрать варианты по текущему направлению. Уточните destination."
                    ),
                    .persistSnapshot,
                ]
            )
        }
        return VacationPlanningTransitionResult(
            nextState: .generateResult,
            nextContext: context,
            effects: [.generateItinerary, .persistSnapshot]
        )
    }

    private func planApprovalTransition(snapshot: VacationPlanningSnapshot) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        guard isDestinationValid(in: context) else {
            return blockedTransition(
                snapshot: snapshot,
                reason: "Нельзя утвердить план без валидного destination."
            )
        }
        context.planApprovedAt = Date()
        context.finalPlan = nil
        context.isFinalPlanLocked = false
        return VacationPlanningTransitionResult(
            nextState: .generateResult,
            nextContext: context,
            effects: [.generateDestinationOptions, .persistSnapshot]
        )
    }

    private func finalizeGeneratedPlanTransition(
        snapshot: VacationPlanningSnapshot,
        budget: VacationBudgetBreakdown
    ) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        guard let itinerary = context.itinerary else {
            return failedTransition(
                context: context,
                reason: "Нельзя собрать финальный план без маршрута."
            )
        }

        context.budgetBreakdown = budget
        context.budgetReviewedAt = Date()
        context.validationPassedAt = Date()
        context.finalPlan = VacationPlan(
            sessionID: snapshot.sessionID,
            branchID: snapshot.branchID,
            slots: context.slots,
            selectedOption: context.selectedOption,
            itinerary: itinerary,
            budget: budget,
            weatherSummary: nil,
            createdAt: Date()
        )
        context.isFinalPlanLocked = true
        return VacationPlanningTransitionResult(
            nextState: .idle,
            nextContext: context,
            effects: [.emitFinalPlan, .persistSnapshot]
        )
    }

    private func revisionTransition(
        context: VacationPlanningContext,
        comment: String
    ) -> VacationPlanningTransitionResult {
        var next = context
        next.revisionCount += 1
        next.isFinalPlanLocked = false
        next.finalPlan = nil
        next.planApprovedAt = nil
        next.executionCompletedAt = nil
        next.validationPassedAt = nil
        next.itinerary = nil
        next.itineraryBuiltAt = nil
        next.budgetBreakdown = nil
        next.budgetReviewedAt = nil
        next.options = []
        next.selectedOption = nil
        next.slots.destination = nil
        next.questionnaireState.answers.removeValue(forKey: VacationQuestionnaireSchemaAdapter.destinationFieldID)
        next.questionnaireState = refreshQuestionnaireState(next.questionnaireState, slots: next.slots)
        if !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.constraintsAppend(comment)
        }
        return VacationPlanningTransitionResult(
            nextState: .destinationRequest,
            nextContext: next,
            effects: [.askQuestion(fieldID: VacationQuestionnaireSchemaAdapter.destinationFieldID, warning: nil), .persistSnapshot]
        )
    }

    private func failedTransition(
        context: VacationPlanningContext,
        reason: String
    ) -> VacationPlanningTransitionResult {
        VacationPlanningTransitionResult(
            nextState: .failed(reason: reason),
            nextContext: context,
            effects: [.askUser(questionKey: .retryAfterError), .persistSnapshot]
        )
    }

    private func blockedTransition(
        snapshot: VacationPlanningSnapshot,
        reason: String
    ) -> VacationPlanningTransitionResult {
        let guidance: VacationQuestionKey
        switch snapshot.state {
        case .destinationRequest, .validatingDestination:
            guidance = .missingDestination
        case .awaitingPlanApproval:
            guidance = .approval
        case .generateResult:
            guidance = .retryAfterError
        default:
            guidance = .retryAfterError
        }
        return VacationPlanningTransitionResult(
            nextState: snapshot.state,
            nextContext: snapshot.context,
            effects: [.notifyUser(reason), .askUser(questionKey: guidance), .persistSnapshot]
        )
    }

    private func refreshQuestionnaireState(
        _ current: QuestionnaireState,
        slots: VacationSlots
    ) -> QuestionnaireState {
        var next = current
        if next.answers.isEmpty {
            next = VacationQuestionnaireSchemaAdapter.makeInitialState(from: slots)
        }
        next.missingHard = VacationQuestionnaireSchemaAdapter.schema.fields
            .filter { $0.requiredLevel == .hard && next.answers[$0.id] == nil }
            .map(\.id)
        next.missingSoft = VacationQuestionnaireSchemaAdapter.schema.fields
            .filter { $0.requiredLevel == .soft && next.answers[$0.id] == nil }
            .map(\.id)
        return next
    }

    private func startTransition(snapshot: VacationPlanningSnapshot) -> VacationPlanningTransitionResult {
        var context = snapshot.context
        context.lastValidationErrors = []
        context.planApprovedAt = nil
        context.executionCompletedAt = nil
        context.validationPassedAt = nil
        context.finalPlan = nil
        context.isFinalPlanLocked = false
        context.itinerary = nil
        context.itineraryBuiltAt = nil
        context.budgetBreakdown = nil
        context.budgetReviewedAt = nil
        context.options = []
        context.selectedOption = nil
        context.questionnaireState = refreshQuestionnaireState(context.questionnaireState, slots: context.slots)
        return VacationPlanningTransitionResult(
            nextState: .destinationRequest,
            nextContext: context,
            effects: [.askQuestion(fieldID: VacationQuestionnaireSchemaAdapter.destinationFieldID, warning: nil), .persistSnapshot]
        )
    }

    private func isDestinationValid(in context: VacationPlanningContext) -> Bool {
        guard let destination = context.slots.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty else {
            return false
        }
        return true
    }

    private func userInputInvariantViolations(for slots: VacationSlots) -> [(fieldID: String, message: String)] {
        var violations: [(fieldID: String, message: String)] = []
        if let range = slots.dateRange, range.start > range.end {
            violations.append((
                fieldID: VacationQuestionnaireSchemaAdapter.datesFieldID,
                message: "Дата начала поездки должна быть не позже даты окончания."
            ))
        }
        if let budget = slots.budget, budget.total <= 0 {
            violations.append((
                fieldID: VacationQuestionnaireSchemaAdapter.budgetFieldID,
                message: "Бюджет должен быть больше 0."
            ))
        }
        return violations
    }
}

final class StartVacationPlanningUseCase: StartVacationPlanningUseCaseProtocol {
    private let orchestrator: VacationPlanningOrchestrator

    init(orchestrator: VacationPlanningOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningTurnResult {
        try await orchestrator.process(
            sessionID: sessionID,
            branchID: branchID,
            initialEvent: .started
        )
    }
}

final class HandleVacationPlanningEventUseCase: HandleVacationPlanningEventUseCaseProtocol {
    private let orchestrator: VacationPlanningOrchestrator

    init(orchestrator: VacationPlanningOrchestrator) {
        self.orchestrator = orchestrator
    }

    func execute(
        sessionID: UUID,
        branchID: UUID,
        userText: String,
        source: QuestionnaireAnswerSource
    ) async throws -> VacationPlanningTurnResult {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "approve" {
            return try await orchestrator.process(sessionID: sessionID, branchID: branchID, initialEvent: .planApproved)
        }
        if trimmed.lowercased().hasPrefix("revise:") {
            let comment = String(trimmed.dropFirst("revise:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return try await orchestrator.process(
                sessionID: sessionID,
                branchID: branchID,
                initialEvent: .revisionRequested(comment: comment)
            )
        }
        return try await orchestrator.process(
            sessionID: sessionID,
            branchID: branchID,
            initialEvent: .userMessage(text: userText, source: source)
        )
    }
}

final class GetVacationPlanningStatusUseCase: GetVacationPlanningStatusUseCaseProtocol {
    private let stateRepository: VacationPlanningStateRepositoryProtocol

    init(stateRepository: VacationPlanningStateRepositoryProtocol) {
        self.stateRepository = stateRepository
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningSnapshot {
        if let snapshot = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) {
            return snapshot
        }
        return VacationPlanningSnapshot(
            schemaVersion: VacationPlanningSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: .initial,
            updatedAt: Date()
        )
    }
}

final class FinalizeVacationPlanUseCase: FinalizeVacationPlanUseCaseProtocol {
    private let stateRepository: VacationPlanningStateRepositoryProtocol
    private let planRepository: VacationPlanRepositoryProtocol

    init(
        stateRepository: VacationPlanningStateRepositoryProtocol,
        planRepository: VacationPlanRepositoryProtocol
    ) {
        self.stateRepository = stateRepository
        self.planRepository = planRepository
    }

    func execute(sessionID: UUID, branchID: UUID) async throws -> VacationPlan {
        if let persisted = try await planRepository.fetchFinalPlan(sessionID: sessionID, branchID: branchID) {
            return persisted
        }
        guard let snapshot = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) else {
            throw VacationPlanningError.serviceFailure("Снимок планирования отсутствует.")
        }
        guard case .idle = snapshot.state,
              snapshot.context.isFinalPlanLocked,
              let plan = snapshot.context.finalPlan else {
            throw VacationPlanningError.invalidTransition("Финальный план недоступен: дождитесь завершения состояния generateResult.")
        }
        try await planRepository.saveFinalPlan(plan)
        return plan
    }
}

final class VacationPlanningOrchestrator {
    private let stateRepository: VacationPlanningStateRepositoryProtocol
    private let planRepository: VacationPlanRepositoryProtocol
    private let settingsRepository: SettingsRepositoryProtocol
    private let reducer: VacationPlannerReducerProtocol
    private let processUserAnswerUseCase: ProcessUserAnswerUseCaseProtocol
    private let questionGenerationService: QuestionGenerationServiceProtocol
    private let questionnaireSchema: QuestionnaireSchema
    private let optionGenerationService: VacationOptionGenerationServiceProtocol
    private let itineraryService: VacationItineraryServiceProtocol
    private let budgetEstimator: VacationBudgetEstimatorProtocol
    private let mcpWeatherService: MCPWeatherServiceProtocol?
    private let mcpWeatherEndpointURL: URL

    init(
        stateRepository: VacationPlanningStateRepositoryProtocol,
        planRepository: VacationPlanRepositoryProtocol,
        settingsRepository: SettingsRepositoryProtocol,
        reducer: VacationPlannerReducerProtocol,
        processUserAnswerUseCase: ProcessUserAnswerUseCaseProtocol,
        questionGenerationService: QuestionGenerationServiceProtocol,
        questionnaireSchema: QuestionnaireSchema,
        optionGenerationService: VacationOptionGenerationServiceProtocol,
        itineraryService: VacationItineraryServiceProtocol,
        budgetEstimator: VacationBudgetEstimatorProtocol,
        mcpWeatherService: MCPWeatherServiceProtocol? = nil,
        mcpWeatherEndpointURL: URL = URL(string: "stdio://open-weather")!
    ) {
        self.stateRepository = stateRepository
        self.planRepository = planRepository
        self.settingsRepository = settingsRepository
        self.reducer = reducer
        self.processUserAnswerUseCase = processUserAnswerUseCase
        self.questionGenerationService = questionGenerationService
        self.questionnaireSchema = questionnaireSchema
        self.optionGenerationService = optionGenerationService
        self.itineraryService = itineraryService
        self.budgetEstimator = budgetEstimator
        self.mcpWeatherService = mcpWeatherService
        self.mcpWeatherEndpointURL = mcpWeatherEndpointURL
    }

    func process(
        sessionID: UUID,
        branchID: UUID,
        initialEvent: VacationPlanningEvent
    ) async throws -> VacationPlanningTurnResult {
        var snapshot = try await loadSnapshot(sessionID: sessionID, branchID: branchID)
        let settings = (try? await settingsRepository.fetchSettings(sessionID: sessionID)) ?? .default
        var queue: [VacationPlanningEvent] = [initialEvent]
        var messages: [String] = []

        while !queue.isEmpty {
            let event = queue.removeFirst()
            let transition = reducer.reduce(snapshot: snapshot, event: event)
            snapshot = rebuildSnapshot(from: transition, previous: snapshot)

            let execution = try await executeEffects(transition.effects, snapshot: snapshot, settings: settings)
            messages.append(contentsOf: execution.messages)
            queue.append(contentsOf: execution.events)

        }

        try await stateRepository.saveSnapshot(snapshot)
        return VacationPlanningTurnResult(snapshot: snapshot, agentMessages: messages)
    }

    private func loadSnapshot(sessionID: UUID, branchID: UUID) async throws -> VacationPlanningSnapshot {
        if let existing = try await stateRepository.fetchSnapshot(sessionID: sessionID, branchID: branchID) {
            return existing
        }
        return VacationPlanningSnapshot(
            schemaVersion: VacationPlanningSnapshot.schemaVersionCurrent,
            sessionID: sessionID,
            branchID: branchID,
            state: .idle,
            context: .initial,
            updatedAt: Date()
        )
    }

    private func rebuildSnapshot(
        from transition: VacationPlanningTransitionResult,
        previous: VacationPlanningSnapshot
    ) -> VacationPlanningSnapshot {
        let now = Date()
        var context = transition.nextContext
        context.updatedAt = now
        if context.createdAt > now {
            context.createdAt = now
        }
        return VacationPlanningSnapshot(
            schemaVersion: VacationPlanningSnapshot.schemaVersionCurrent,
            sessionID: previous.sessionID,
            branchID: previous.branchID,
            state: transition.nextState,
            context: context,
            updatedAt: now
        )
    }

    private func executeEffects(
        _ effects: [VacationEffect],
        snapshot: VacationPlanningSnapshot,
        settings: LLMSettings
    ) async throws -> (events: [VacationPlanningEvent], messages: [String]) {
        var resultingEvents: [VacationPlanningEvent] = []
        var messages: [String] = []

        for effect in effects {
            switch effect {
            case let .notifyUser(message):
                messages.append(message)
            case let .askUser(questionKey):
                if questionKey == .approval {
                    messages.append(approvalQuestionText(context: snapshot.context))
                } else {
                    messages.append(questionText(for: questionKey))
                }
            case let .askQuestion(fieldID, warning):
                let prompt = await buildQuestionPrompt(fieldID: fieldID, snapshot: snapshot, settings: settings)
                if let warning, !warning.isEmpty {
                    messages.append(warning)
                }
                messages.append(prompt.text)
            case let .processUserAnswer(text, source):
                let result = await processUserAnswerUseCase.execute(
                    schema: questionnaireSchema,
                    currentState: snapshot.context.questionnaireState,
                    currentSlots: snapshot.context.slots,
                    userText: text,
                    settings: settings,
                    source: source
                )
                resultingEvents.append(.questionnaireProcessed(result))
            case .generateDestinationOptions:
                let options = try await optionGenerationService.generateOptions(context: snapshot.context)
                resultingEvents.append(.optionsGenerated(options))
            case .generateItinerary:
                let itinerary = try await itineraryService.generateItinerary(context: snapshot.context)
                resultingEvents.append(.itineraryGenerated(itinerary))
            case .calculateBudget:
                let budget = try await budgetEstimator.estimateBudget(context: snapshot.context)
                resultingEvents.append(.budgetCalculated(budget))
            case .persistSnapshot:
                try await stateRepository.saveSnapshot(snapshot)
            case .emitFinalPlan:
                if let plan = snapshot.context.finalPlan {
                    if let weatherRequestMessage = mcpWeatherRequestMessage(for: plan) {
                        messages.append(weatherRequestMessage)
                    }
                    let weatherEnrichedPlan = await enrichPlanWithWeather(plan)
                    try await planRepository.saveFinalPlan(weatherEnrichedPlan)
                    messages.append("План отпуска готов и сохранен.")
                    messages.append(finalPlanMessage(weatherEnrichedPlan))
                } else {
                    throw VacationPlanningError.serviceFailure("Невозможно опубликовать итоговый план без завершенного контекста.")
                }
            }
        }

        return (resultingEvents, messages)
    }

    private func buildQuestionPrompt(
        fieldID: String?,
        snapshot: VacationPlanningSnapshot,
        settings: LLMSettings
    ) async -> QuestionPrompt {
        let state = snapshot.context.questionnaireState
        let nextFieldID = fieldID ?? state.missingHard.first ?? state.missingSoft.first
        let target = nextFieldID.flatMap { questionnaireSchema.field(id: $0) }
        do {
            return try await questionGenerationService.generateQuestion(
                context: QuestionnaireQuestionContext(
                    schema: questionnaireSchema,
                    state: state,
                    latestUserMessage: snapshot.context.lastUserMessage,
                    settings: settings
                ),
                targetField: target,
                toneHints: ["neutral", "short"]
            )
        } catch {
            return QuestionPrompt(
                fieldID: target?.id,
                text: target?.fallbackQuestion ?? "Уточните, пожалуйста, недостающие детали поездки.",
                suggestions: [],
                isFallback: true
            )
        }
    }

    private func questionText(for key: VacationQuestionKey) -> String {
        switch key {
        case .provideBasics:
            return "Укажите место назначения для планирования отдыха."
        case .missingDestination:
            return "Уточните место назначения, чтобы продолжить."
        case .missingDates:
            return "Сейчас важно только место назначения. Укажите destination."
        case .missingBudget:
            return "Бюджет будет рассчитан после подтверждения destination."
        case .approval:
            return "Подтвердите destination: `approve` или запросите изменение `revise: ...`."
        case .executeApprovedPlan:
            return "Генерирую финальный план отдыха."
        case .validateBeforeFinal:
            return "План готовится, подождите."
        case .finalizeReady:
            return "Финальный план готов."
        case .retryAfterError:
            return "Этот шаг недоступен в текущем состоянии. Следуйте допустимым переходам FSM."
        }
    }

    private func approvalQuestionText(context: VacationPlanningContext) -> String {
        var lines: [String] = ["Проверьте собранные данные перед подтверждением плана:"]

        if let destination = context.slots.destination?.trimmingCharacters(in: .whitespacesAndNewlines), !destination.isEmpty {
            lines.append("- destination: \(destination)")
        }
        if let range = context.slots.dateRange {
            lines.append("- dates: \(format(date: range.start)) — \(format(date: range.end))")
        }
        if let budget = context.slots.budget {
            lines.append("- budget: \(budget.total) \(budget.currency)")
        }

        lines.append("- travelers: \(context.slots.travelerCount)")

        if let travelStyle = context.slots.travelStyle?.trimmingCharacters(in: .whitespacesAndNewlines), !travelStyle.isEmpty {
            lines.append("- travel_style: \(travelStyle)")
        }
        if !context.slots.interests.isEmpty {
            lines.append("- interests: \(context.slots.interests.joined(separator: ", "))")
        }
        if !context.slots.constraints.isEmpty {
            lines.append("- constraints: \(context.slots.constraints.joined(separator: ", "))")
        }

        lines.append("Подтвердите план: `approve` или запросите изменение `revise: ...`.")
        return lines.joined(separator: "\n")
    }

    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func finalPlanMessage(_ plan: VacationPlan) -> String {
        var lines: [String] = ["Финальный план отпуска:"]

        if let destination = plan.slots.destination?.trimmingCharacters(in: .whitespacesAndNewlines), !destination.isEmpty {
            lines.append("- destination: \(destination)")
        }
        if let range = plan.slots.dateRange {
            lines.append("- dates: \(format(date: range.start)) — \(format(date: range.end))")
        }
        if let selectedOption = plan.selectedOption {
            lines.append("- option: \(selectedOption.title)")
        }
        lines.append("- budget total: \(plan.budget.total) \(plan.budget.currency)")

        if let weatherSummary = plan.weatherSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !weatherSummary.isEmpty
        {
            lines.append("Погода (MCP):")
            weatherSummary
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
                .forEach { lines.append("  \($0)") }
        }

        if !plan.itinerary.days.isEmpty {
            lines.append("Маршрут:")
            for day in plan.itinerary.days {
                let activities = day.activities.joined(separator: ", ")
                lines.append("  День \(day.dayIndex): \(day.title) (\(activities))")
            }
        }
        if !plan.itinerary.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Заметки: \(plan.itinerary.notes)")
        }

        return lines.joined(separator: "\n")
    }

    private func enrichPlanWithWeather(_ plan: VacationPlan) async -> VacationPlan {
        guard let service = mcpWeatherService,
              let destination = plan.slots.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty else {
            return plan
        }

        let weatherSummary: String
        do {
            weatherSummary = try await service.fetchCurrentWeather(
                serverURL: mcpWeatherEndpointURL,
                city: destination,
                units: "metric",
                language: "ru"
            )
        } catch {
            weatherSummary = "Не удалось получить погоду через MCP (\(error.localizedDescription))."
        }

        let normalizedSummary = weatherSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSummary.isEmpty else { return plan }

        return VacationPlan(
            sessionID: plan.sessionID,
            branchID: plan.branchID,
            slots: plan.slots,
            selectedOption: plan.selectedOption,
            itinerary: plan.itinerary,
            budget: plan.budget,
            weatherSummary: normalizedSummary,
            createdAt: plan.createdAt
        )
    }

    private func mcpWeatherRequestMessage(for plan: VacationPlan) -> String? {
        guard mcpWeatherService != nil,
              let destination = plan.slots.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
              !destination.isEmpty else {
            return nil
        }
        return "MCP open-weather: запрашиваю актуальную погоду для \(destination)."
    }
}

private extension VacationPlanningContext {
    mutating func constraintsAppend(_ comment: String) {
        let normalized = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let nextConstraints = slots.constraints.mergingUnique(with: [normalized])
        slots = VacationSlots(
            destination: slots.destination,
            dateRange: slots.dateRange,
            budget: slots.budget,
            travelerCount: slots.travelerCount,
            travelStyle: slots.travelStyle,
            interests: slots.interests,
            constraints: nextConstraints
        )
    }
}

private extension VacationPlanningEvent {
    var debugName: String {
        switch self {
        case .started:
            return "запуск"
        case .userMessage:
            return "сообщениеПользователя"
        case .questionnaireProcessed:
            return "анкетаОбработана"
        case .optionsGenerated:
            return "вариантыСгенерированы"
        case .itineraryGenerated:
            return "маршрутСгенерирован"
        case .budgetCalculated:
            return "бюджетРассчитан"
        case .planApproved:
            return "планУтвержден"
        case .executionCompleted:
            return "реализацияЗавершена"
        case .validationPassed:
            return "валидацияУспешна"
        case .validationFailed:
            return "валидацияПровалена"
        case .finalizeRequested:
            return "финализацияЗапрошена"
        case .revisionRequested:
            return "запрошенаПравка"
        case .errorOccurred:
            return "ошибка"
        }
    }
}

private extension VacationPlanningError {
    var failureReason: String {
        switch self {
        case let .invariantViolation(violations):
            return violations.map(\.message).joined(separator: ", ")
        case let .invalidTransition(message):
            return message
        case let .serviceFailure(message):
            return message
        }
    }
}
