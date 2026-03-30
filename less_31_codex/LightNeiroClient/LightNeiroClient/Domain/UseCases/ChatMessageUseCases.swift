import Foundation

final class FetchMessagesUseCase: FetchMessagesUseCaseProtocol {
    private let messageRepository: MessageRepositoryProtocol

    /// Создаёт use case чтения сообщений ветки.
    init(messageRepository: MessageRepositoryProtocol) {
        self.messageRepository = messageRepository
    }

    /// Возвращает все сообщения указанной ветки.
    func execute() async throws -> [ChatMessage] {
        try await messageRepository.fetchMessages()
    }
}

final class ClearDialogUseCase: ClearDialogUseCaseProtocol {
    private let messageRepository: MessageRepositoryProtocol
    private let shortTermRepository: ShortTermMemoryRepositoryProtocol
    private let workingMemoryRepository: WorkingMemoryRepositoryProtocol
    private let longTermMemoryRepository: LongTermMemoryRepositoryProtocol
    private let metricsRepository: MetricsRepositoryProtocol

    /// Создаёт use case полной очистки диалога.
    init(
        messageRepository: MessageRepositoryProtocol,
        shortTermRepository: ShortTermMemoryRepositoryProtocol,
        workingMemoryRepository: WorkingMemoryRepositoryProtocol,
        longTermMemoryRepository: LongTermMemoryRepositoryProtocol,
        metricsRepository: MetricsRepositoryProtocol
    ) {
        self.messageRepository = messageRepository
        self.shortTermRepository = shortTermRepository
        self.workingMemoryRepository = workingMemoryRepository
        self.longTermMemoryRepository = longTermMemoryRepository
        self.metricsRepository = metricsRepository
    }

    /// Очищает сообщения, память и метрики глобального диалога.
    func execute() async throws {
        try await messageRepository.clearAll()
        try await shortTermRepository.clear()
        try await workingMemoryRepository.clearAll()
        try await longTermMemoryRepository.clearAll()
        try await metricsRepository.clearAll()
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
    private let ragCoordinator: SendMessageRAGCoordinating
    private let ragPayloadCodec: RAGPayloadCoding
    private let memoryEventAppender: MemoryEventAppending

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
        self.ragCoordinator = SendMessageRAGCoordinatorFactory.make(
            ragUseCaseFacade: ragUseCaseFacade,
            ragDocumentsProvider: ragDocumentsProvider,
            initialIndexedRAGStrategy: initialIndexedRAGStrategy
        )
        self.ragPayloadCodec = RAGPayloadCodecFactory.make()
        self.memoryEventAppender = MemoryEventAppenderFactory.make(messageRepository: messageRepository)
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
        userText: String,
        assistantInstruction: String?
    ) async throws -> ChatMessage {
        let userMessage = ChatMessage(role: .user, content: userText)
        try await messageRepository.saveMessage(userMessage)

        let settings = try await settingsRepository.fetchSettings()
        if settings.isMemoryEnabled {
            if let event = try await updateShortTermMemoryUseCase.execute(
                windowSize: settings.windowSize
            ) {
                try await memoryEventAppender.appendEvent(event: event)
            }

            let workingUserEvents = (try? await updateWorkingMemoryUseCase.execute(
                latestUserMessage: userText,
                latestAssistantMessage: nil
            )) ?? []
            try await memoryEventAppender.appendEvents(events: workingUserEvents)

            let longTermEvents = (try? await updateLongTermMemoryUseCase.execute(
                latestUserMessage: userText,
                settings: settings
            )) ?? []
            try await memoryEventAppender.appendEvents(events: longTermEvents)
        }

        let context = try await buildMemoryContextUseCase.execute(settings: settings)
        let ragDecision = await ragCoordinator.buildDecision(settings: settings, userText: userText)
        let systemPrompt = ragCoordinator.makeSystemPrompt(extraInstruction: assistantInstruction, ragDecision: ragDecision)

        let response: LLMResponse
        switch ragDecision {
        case .answerWithEvidence(let retrieval):
            let request = LLMRequest(
                systemPrompt: systemPrompt,
                shortTermMessages: context.shortTermMessages,
                workingMemory: context.workingMemory,
                longTermMemory: context.longTermMemory,
                settings: settings,
                taskState: context.taskState
            )
            let llmResponse = try await llmClient.send(request: request)
            let finalizedContent = try ragPayloadCodec.finalizeRAGResponseContent(
                rawContent: llmResponse.content,
                retrieval: retrieval
            )
            response = LLMResponse(
                content: finalizedContent,
                inputTokens: llmResponse.inputTokens,
                outputTokens: llmResponse.outputTokens,
                latencyMs: llmResponse.latencyMs
            )
        case .fallbackToLLM, .disabledOrUnavailable:
            let request = LLMRequest(
                systemPrompt: systemPrompt,
                shortTermMessages: context.shortTermMessages,
                workingMemory: context.workingMemory,
                longTermMemory: context.longTermMemory,
                settings: settings,
                taskState: context.taskState
            )
            response = try await llmClient.send(request: request)
        }

        let assistantMessage = ChatMessage(
            role: .assistant,
            content: response.content,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            latencyMs: response.latencyMs
        )
        try await messageRepository.saveMessage(assistantMessage)

        if settings.isMemoryEnabled {
            if let event = try await updateShortTermMemoryUseCase.execute(
                windowSize: settings.windowSize
            ) {
                try await memoryEventAppender.appendEvent(event: event)
            }

            let workingAssistantEvents = (try? await updateWorkingMemoryUseCase.execute(
                latestUserMessage: userText,
                latestAssistantMessage: assistantMessage.content
            )) ?? []
            try await memoryEventAppender.appendEvents(events: workingAssistantEvents)
        }

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
