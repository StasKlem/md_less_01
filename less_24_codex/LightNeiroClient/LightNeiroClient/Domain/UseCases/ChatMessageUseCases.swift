import Foundation

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
        let ragDecision = await buildRAGDecision(settings: settings, userText: userText)
        let systemPrompt = makeSystemPrompt(extraInstruction: assistantInstruction, ragDecision: ragDecision)

        let response: LLMResponse
        switch ragDecision {
        case .needsClarification:
            response = LLMResponse(
                content: makeNeedsClarificationPayloadJSON(),
                inputTokens: 0,
                outputTokens: 0,
                latencyMs: 0
            )
        case .answerWithEvidence(let retrieval):
            let request = LLMRequest(
                systemPrompt: systemPrompt,
                shortTermMessages: context.shortTermMessages,
                workingMemory: context.workingMemory,
                longTermMemory: context.longTermMemory,
                settings: settings
            )
            // 7) Запрашиваем ответ у LLM. На этом этапе модель уже видит актуализированную память.
            let llmResponse = try await llmClient.send(request: request)
            let finalizedContent = finalizeRAGResponseContent(rawContent: llmResponse.content, retrieval: retrieval)
            response = LLMResponse(
                content: finalizedContent,
                inputTokens: llmResponse.inputTokens,
                outputTokens: llmResponse.outputTokens,
                latencyMs: llmResponse.latencyMs
            )
        case .disabledOrUnavailable:
            if settings.isRAGEnabled {
                response = LLMResponse(
                    content: makeNeedsClarificationPayloadJSON(),
                    inputTokens: 0,
                    outputTokens: 0,
                    latencyMs: 0
                )
            } else {
                let request = LLMRequest(
                    systemPrompt: systemPrompt,
                    shortTermMessages: context.shortTermMessages,
                    workingMemory: context.workingMemory,
                    longTermMemory: context.longTermMemory,
                    settings: settings
                )
                response = try await llmClient.send(request: request)
            }
        }

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

    private func makeSystemPrompt(extraInstruction: String?, ragDecision: RAGDecision) -> String {
        // Базовое поведение ассистента по умолчанию.
        let base = "You are a helpful assistant."

        var blocks: [String] = [base]

        if let extraInstruction {
            let trimmed = extraInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(trimmed)
            }
        }

        if case .answerWithEvidence(let retrieval) = ragDecision {
            blocks.append(ragJSONContractBlock())
            blocks.append(formatRAGEvidenceBlock(retrieval))
        }

        return blocks.joined(separator: "\n\n")
    }

    private func buildRAGDecision(settings: LLMSettings, userText: String) async -> RAGDecision {
        guard settings.isRAGEnabled, let ragUseCaseFacade else { return .disabledOrUnavailable }

        do {
            try await ensureRAGIndexIsReady(ragUseCaseFacade, strategy: settings.ragChunkingStrategy)
            let normalizedThreshold = normalizedRAGThreshold(settings.ragRelevanceThreshold)
            if settings.isRAGPostFilteringEnabled {
                let topKBeforeFiltering = max(1, settings.ragTopKBeforeFiltering)
                let topKAfterFiltering = max(1, settings.ragTopKAfterFiltering)
                let results = try await ragUseCaseFacade.search(query: userText, topK: topKBeforeFiltering)
                let maxScore = Double(results.map(\.score).max() ?? 0)
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
                guard !finalResults.isEmpty, maxScore >= normalizedThreshold else {
                    return .needsClarification
                }
                return .answerWithEvidence(retrieval: finalResults)
            }

            let legacyResults = try await ragUseCaseFacade.search(query: userText, topK: 4)
            let maxScore = Double(legacyResults.map(\.score).max() ?? 0)
            guard !legacyResults.isEmpty, maxScore >= normalizedThreshold else {
                return .needsClarification
            }
            return .answerWithEvidence(retrieval: legacyResults)
        } catch {
#if DEBUG
            print("[RAG] Контекст не собран: \(error)")
#endif
            return .disabledOrUnavailable
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

    private func formatRAGEvidenceBlock(_ results: [SearchResult]) -> String {
        var lines: [String] = [
            "RAG_EVIDENCE:",
        ]

        for (index, result) in results.enumerated() {
            let source = result.chunk.source
            let section = result.chunk.section ?? "null"
            let text = result.chunk.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("[\(index + 1)] chunk_id=\(result.chunk.id.uuidString) source=\(source) section=\(section) text=\(text)")
        }
        return lines.joined(separator: "\n")
    }

    private func ragJSONContractBlock() -> String {
        """
        Верни ТОЛЬКО валидный JSON без markdown и без пояснений.
        Схема JSON:
        {
          "answer": "string",
          "sources": [
            { "source": "string", "section": "string|null", "chunk_id": "string" }
          ],
          "quotes": [
            { "chunk_id": "string", "source": "string", "section": "string|null", "text": "string" }
          ]
        }
        Правила:
        - Используй только фрагменты из блока RAG_EVIDENCE.
        - Для каждого элемента quotes chunk_id обязан существовать в sources.
        - Для ответа по данным RAG массивы sources и quotes должны быть непустыми.
        - Не добавляй дополнительные поля.
        """
    }

    private func makeNeedsClarificationPayloadJSON() -> String {
        let payload = RAGResponsePayload(
            answer: "не знаю. Пожалуйста, уточните вопрос.",
            sources: [],
            quotes: []
        )
        return encodeRAGPayload(payload)
    }

    private func finalizeRAGResponseContent(rawContent: String, retrieval: [SearchResult]) -> String {
        if let decoded = decodeRAGPayload(from: rawContent), isValidRAGPayload(decoded, requireEvidence: true) {
            return encodeRAGPayload(decoded)
        }

        // Детерминированный ремонт ответа по retrieval, чтобы соблюсти контракт без повторного вызова LLM.
        let repaired = repairRAGPayload(from: rawContent, retrieval: retrieval)
        return encodeRAGPayload(repaired)
    }

    private func decodeRAGPayload(from rawContent: String) -> RAGResponsePayload? {
        let cleaned = rawContent
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(RAGResponsePayload.self, from: data)
    }

    private func isValidRAGPayload(_ payload: RAGResponsePayload, requireEvidence: Bool) -> Bool {
        guard !payload.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if !requireEvidence {
            return true
        }

        guard !payload.sources.isEmpty, !payload.quotes.isEmpty else {
            return false
        }

        let sourceChunkIDs = Set(payload.sources.map(\.chunkID))
        guard !sourceChunkIDs.isEmpty else {
            return false
        }

        for source in payload.sources {
            if source.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            if source.chunkID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
        }

        for quote in payload.quotes {
            if quote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            if !sourceChunkIDs.contains(quote.chunkID) {
                return false
            }
        }

        return true
    }

    private func repairRAGPayload(from rawContent: String, retrieval: [SearchResult]) -> RAGResponsePayload {
        var seenChunkIDs = Set<String>()
        var sources: [RAGSourceItem] = []

        for result in retrieval {
            let chunkID = result.chunk.id.uuidString
            guard seenChunkIDs.insert(chunkID).inserted else { continue }
            sources.append(
                RAGSourceItem(
                    source: result.chunk.source,
                    section: result.chunk.section,
                    chunkID: chunkID
                )
            )
        }

        let quotes: [RAGQuoteItem] = retrieval.prefix(3).map { result in
            RAGQuoteItem(
                chunkID: result.chunk.id.uuidString,
                source: result.chunk.source,
                section: result.chunk.section,
                text: normalizedQuoteText(result.chunk.content)
            )
        }

        let fallbackAnswer = makeFallbackRAGAnswer(rawContent: rawContent, quotes: quotes)
        return RAGResponsePayload(
            answer: fallbackAnswer,
            sources: sources,
            quotes: quotes
        )
    }

    private func makeFallbackRAGAnswer(rawContent: String, quotes: [RAGQuoteItem]) -> String {
        let candidate = rawContent
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !candidate.isEmpty, !candidate.hasPrefix("{"), !candidate.hasPrefix("[") {
            return String(candidate.prefix(280))
        }

        guard let firstQuote = quotes.first?.text, !firstQuote.isEmpty else {
            return "Ответ сформирован на основе найденных источников."
        }
        return "Согласно найденным источникам: \(String(firstQuote.prefix(240)))"
    }

    private func normalizedQuoteText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func encodeRAGPayload(_ payload: RAGResponsePayload) -> String {
        let encoder = JSONEncoder()
        if #available(macOS 10.13, *) {
            encoder.outputFormatting = [.sortedKeys]
        }

        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"answer":"не знаю. Пожалуйста, уточните вопрос.","sources":[],"quotes":[]}"#
        }
        return json
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

private enum RAGDecision {
    case answerWithEvidence(retrieval: [SearchResult])
    case needsClarification
    case disabledOrUnavailable
}

private struct RAGResponsePayload: Codable, Equatable {
    let answer: String
    let sources: [RAGSourceItem]
    let quotes: [RAGQuoteItem]
}

private struct RAGSourceItem: Codable, Equatable {
    let source: String
    let section: String?
    let chunkID: String

    private enum CodingKeys: String, CodingKey {
        case source
        case section
        case chunkID = "chunk_id"
    }
}

private struct RAGQuoteItem: Codable, Equatable {
    let chunkID: String
    let source: String
    let section: String?
    let text: String

    private enum CodingKeys: String, CodingKey {
        case chunkID = "chunk_id"
        case source
        case section
        case text
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
