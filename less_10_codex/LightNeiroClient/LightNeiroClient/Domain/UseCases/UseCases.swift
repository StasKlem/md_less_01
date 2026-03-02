import Foundation

/// Формирует контекст, который будет отправлен в LLM для конкретной ветки диалога.
/// Ключевой момент: стратегия контекста может отличаться между ветками одной сессии.
final class BuildContextUseCase: BuildContextUseCaseProtocol {
    private let factsRepository: FactsRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol

    /// Создаёт use case сборки контекста.
    init(factsRepository: FactsRepositoryProtocol, messageRepository: MessageRepositoryProtocol) {
        self.factsRepository = factsRepository
        self.messageRepository = messageRepository
    }

    /// Собирает набор `facts` и `messages` согласно стратегии активной ветки.
    func execute(
        sessionID: UUID,
        branchID: UUID,
        settings: LLMSettings
    ) async throws -> (facts: [StickyFact], messages: [ChatMessage]) {
        // Берем сообщения только активной ветки, чтобы не смешивать параллельные ветки.
        let branchMessages = try await messageRepository.fetchMessages(branchID: branchID)
        // System-сообщения служебные (например, "создана ветка..."), в prompt их не передаем.
        let messages = branchMessages.filter { $0.role != .system }
        let strategy = settings.contextStrategy(for: branchID)

        switch strategy {
        case .normal:
            // Полная история ветки: максимальная полнота, но выше расход токенов.
            return ([], messages)
        case .slidingWindow:
            // Скользящее окно: ограничиваем контекст последними N сообщениями.
            return ([], Array(messages.suffix(settings.windowSize)))
        case .stickyFacts:
            // Комбинированный режим: короткое окно + долговременная "память" в facts.
            let facts = try await factsRepository.fetchFacts(sessionID: sessionID)
            return (facts, Array(messages.suffix(settings.windowSize)))
        }
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

final class UpdateFactsUseCase: UpdateFactsUseCaseProtocol {
    private let factsRepository: FactsRepositoryProtocol
    private let messageRepository: MessageRepositoryProtocol
    private let llmClient: LLMClientProtocol
    private let decoder = JSONDecoder()

    /// Создаёт use case обновления sticky facts по последнему сообщению.
    init(
        factsRepository: FactsRepositoryProtocol,
        messageRepository: MessageRepositoryProtocol,
        llmClient: LLMClientProtocol
    ) {
        self.factsRepository = factsRepository
        self.messageRepository = messageRepository
        self.llmClient = llmClient
    }

    /// Извлекает и обновляет устойчивые факты сессии на основе контекста ветки.
    func execute(sessionID: UUID, branchID: UUID, latestUserMessage: String, settings: LLMSettings) async throws {
        let trimmed = latestUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        // Пустой ввод не несет фактической ценности для "долгой памяти".
        guard !trimmed.isEmpty else { return }

        // Sticky facts хранятся на уровне сессии, а не ветки:
        // это общая "память" для всех веток одного диалога.
        let existing = try await factsRepository.fetchFacts(sessionID: sessionID)
        // В экстракцию отправляем минимальный, но информативный срез:
        // последний ответ ассистента + новое сообщение пользователя.
        let extractionMessages = try await buildExtractionMessages(branchID: branchID, latestUserMessage: trimmed)
        let extracted = try await extractFactsUsingLLM(messages: extractionMessages, settings: settings)
        let merged = mergeFacts(existing: existing, with: extracted, sessionID: sessionID, lastUserMessage: trimmed)
        try await factsRepository.upsertFacts(sessionID: sessionID, facts: merged)
    }

    /// Вызывает LLM в режиме извлечения памяти и декодирует JSON-результат.
    private func extractFactsUsingLLM(messages: [ChatMessage], settings: LLMSettings) async throws -> [StickyFactCandidate] {
        // Для извлечения фактов принудительно используем "детерминированный" запрос:
        // температура = 0, минимальное окно, без подмешивания существующих facts.
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

    /// Формирует минимальный диалог для extraction-запроса.
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
            // Явный fallback помогает поддерживать стабильный формат запроса к LLM.
            assistantContent = "No previous assistant response."
        }

        return [
            ChatMessage(branchID: branchID, role: .assistant, content: assistantContent),
            ChatMessage(branchID: branchID, role: .user, content: latestUserMessage)
        ]
    }

    /// Достаёт JSON-объект из произвольного текстового ответа модели.
    private func extractJSONObject(from text: String) -> String {
        // Провайдер может вернуть JSON с поясняющим текстом.
        // Извлекаем первую "рамку" объекта и декодируем только ее.
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return "{}"
        }
        return String(text[start...end])
    }

    /// Мержит существующие и новые факты в единый набор, обновляя значения по ключам.
    private func mergeFacts(
        existing: [StickyFact],
        with extracted: [StickyFactCandidate],
        sessionID: UUID,
        lastUserMessage: String
    ) -> [StickyFact] {
        // Источник истины по каждому ключу один: последняя версия в словаре.
        var map = Dictionary(uniqueKeysWithValues: existing.map { ($0.key, $0) })
        let now = Date()

        // last-user-message обновляем всегда, даже если LLM не вернула новых структурных фактов.
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

    /// Создаёт use case отправки сообщения пользователем и получения ответа ассистента.
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

    /// Выполняет полный цикл запроса: сохранение user-сообщения, сбор контекста,
    /// вызов LLM, сохранение ответа и метрик.
    func execute(sessionID: UUID, branchID: UUID, userText: String) async throws -> ChatMessage {
        // 1) Сохраняем пользовательское сообщение сразу, чтобы история ветки была консистентной
        // даже если downstream-запрос в LLM завершится ошибкой.
        let userMessage = ChatMessage(branchID: branchID, role: .user, content: userText)
        try await messageRepository.saveMessage(userMessage)

        // 2) Загружаем настройки сессии и определяем стратегию для текущей ветки.
        let settings = try await settingsRepository.fetchSettings(sessionID: sessionID)
        if settings.contextStrategy(for: branchID) == .stickyFacts {
            // Обновление фактов не должно блокировать основной ответ ассистента.
            // Если экстракция памяти не удалась, продолжаем выполнять запрос к LLM.
            try? await updateFactsUseCase.execute(
                sessionID: sessionID,
                branchID: branchID,
                latestUserMessage: userText,
                settings: settings
            )
        }

        // 3) Формируем контекст по branch-aware стратегии (normal/slidingWindow/stickyFacts).
        let context = try await buildContextUseCase.execute(sessionID: sessionID, branchID: branchID, settings: settings)

        // 4) Выполняем основной запрос в LLM.
        let request = LLMRequest(
            systemPrompt: "You are a helpful assistant.",
            facts: context.facts,
            messages: context.messages,
            settings: settings
        )
        let response = try await llmClient.send(request: request)

        // 5) Сохраняем ответ ассистента в ту же ветку.
        let assistantMessage = ChatMessage(
            branchID: branchID,
            role: .assistant,
            content: response.content,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            latencyMs: response.latencyMs
        )
        try await messageRepository.saveMessage(assistantMessage)

        // 6) Пишем метрики запроса по ветке для блока Session Info.
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
