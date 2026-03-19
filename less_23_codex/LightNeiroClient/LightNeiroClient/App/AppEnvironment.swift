import Foundation

struct AppEnvironment {
    let session: ChatSession

    let sendMessageUseCase: SendMessageUseCaseProtocol
    let fetchMessagesUseCase: FetchMessagesUseCaseProtocol
    let applySettingsUseCase: ApplySettingsUseCaseProtocol
    let fetchSettingsUseCase: FetchSettingsUseCaseProtocol
    let collectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol
    let loadAPIKeyUseCase: LoadAPIKeyUseCaseProtocol
    let saveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol
    let startVacationPlanningUseCase: StartVacationPlanningUseCaseProtocol
    let handleVacationPlanningEventUseCase: HandleVacationPlanningEventUseCaseProtocol
    let getVacationPlanningStatusUseCase: GetVacationPlanningStatusUseCaseProtocol
    let finalizeVacationPlanUseCase: FinalizeVacationPlanUseCaseProtocol
    let fetchVacationPlannerMCPToolsUseCase: FetchVacationPlannerMCPToolsUseCaseProtocol
    let startMockTaskAgentUseCase: StartMockTaskAgentUseCaseProtocol
    let handleMockTaskAgentEventUseCase: HandleMockTaskAgentEventUseCaseProtocol
    let getMockTaskAgentStatusUseCase: GetMockTaskAgentStatusUseCaseProtocol
    let startCounterTaskAgentUseCase: StartCounterTaskAgentUseCaseProtocol
    let stopCounterTaskAgentUseCase: StopCounterTaskAgentUseCaseProtocol
    let configureCounterTaskAgentIntervalUseCase: ConfigureCounterTaskAgentIntervalUseCaseProtocol
    let tickCounterTaskAgentUseCase: TickCounterTaskAgentUseCaseProtocol
    let getCounterTaskAgentStatusUseCase: GetCounterTaskAgentStatusUseCaseProtocol
    let startHackerNewsTaskAgentUseCase: StartHackerNewsTaskAgentUseCaseProtocol
    let stopHackerNewsTaskAgentUseCase: StopHackerNewsTaskAgentUseCaseProtocol
    let getHackerNewsTaskAgentStatusUseCase: GetHackerNewsTaskAgentStatusUseCaseProtocol
    let ragUseCaseFacade: RAGUseCaseFacadeProtocol

    static func bootstrap() async -> AppEnvironment {
        AppLogger.shared.info("Начало bootstrap окружения приложения", category: "app.bootstrap")
        let sessionRepository = MockChatSessionRepository()
        let branchRepository = MockBranchRepository()
        let messageRepository = MockMessageRepository()
        let shortTermRepository = MockShortTermMemoryRepository()
        let workingMemoryRepository = MockWorkingMemoryRepository()
        let longTermMemoryRepository = FileLongTermMemoryRepository()
        let factsRepository = MockFactsRepository()
        let settingsRepository = UserDefaultsSettingsRepository()
        let metricsRepository = MockMetricsRepository()
        let vacationStateRepository = FileVacationPlanningStateRepository()
        let vacationPlanRepository = FileVacationPlanRepository()
        let mockTaskAgentStateRepository = FileMockTaskAgentStateRepository()
        let counterTaskAgentStateRepository = FileCounterTaskAgentStateRepository()
        let hackerNewsTaskAgentStateRepository = FileHackerNewsTaskAgentStateRepository()
        let apiKeyStore = KeychainAPIKeyStore()
        let mcpToolDiscoveryService = MCPToolDiscoveryService(
            hackerNewsTranslateEnvironmentProvider: { sessionID in
                let settings = (try? await settingsRepository.fetchSettings(sessionID: sessionID)) ?? .default
                var environmentOverrides: [String: String] = [
                    "HACKERNEWS_TRANSLATE_OPENAI_MODEL": settings.model.rawValue,
                    "HACKERNEWS_TRANSLATE_OPENAI_BASE_URL": Self.routerAICompatibleBaseURL(
                        endpoint: RouterAIConfiguration.default.endpoint
                    )
                ]
                if let apiKey = try? apiKeyStore.fetchAPIKey() {
                    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        environmentOverrides["HACKERNEWS_TRANSLATE_OPENAI_API_KEY"] = trimmed
                    }
                }
                return environmentOverrides
            }
        )
        let loadAPIKey = LoadAPIKeyUseCase(apiKeyStore: apiKeyStore)
        let saveAPIKey = SaveAPIKeyUseCase(apiKeyStore: apiKeyStore)
        let llmClient = RouterAILLMClient(
            configuration: RouterAIConfiguration(
                endpoint: RouterAIConfiguration.default.endpoint,
                timeoutInterval: RouterAIConfiguration.default.timeoutInterval,
                apiKeyProvider: {
                    try? apiKeyStore.fetchAPIKey()
                }
            )
        )

        let buildMemoryContext = BuildMemoryContextUseCase(
            shortTermRepository: shortTermRepository,
            workingMemoryRepository: workingMemoryRepository,
            longTermMemoryRepository: longTermMemoryRepository,
            messageRepository: messageRepository
        )
        let updateShortTermMemory = UpdateShortTermMemoryUseCase(
            messageRepository: messageRepository,
            shortTermRepository: shortTermRepository
        )
        let updateWorkingMemory = UpdateWorkingMemoryUseCase(
            workingMemoryRepository: workingMemoryRepository
        )
        let updateLongTermMemory = UpdateLongTermMemoryUseCase(
            longTermRepository: longTermMemoryRepository,
            messageRepository: messageRepository,
            llmClient: llmClient,
            legacyFactsRepository: factsRepository
        )
        let ragUseCaseFacade = RAGModuleFactory.makeFacade(
            settings: RAGSettings(
                provider: .appLLM,
                embeddingModel: RAGSettings.defaultEmbeddingModel,
                embeddingDimension: RAGSettings.default.embeddingDimension,
                batchSize: RAGSettings.default.batchSize,
                normalizeEmbeddings: true
            ),
            embeddingProvider: AppLLMEmbeddingProvider(
                configuration: RouterAIConfiguration(
                    endpoint: RouterAIConfiguration.default.endpoint,
                    timeoutInterval: RouterAIConfiguration.default.timeoutInterval,
                    apiKeyProvider: {
                        try? apiKeyStore.fetchAPIKey()
                    }
                )
            )
        )
        let fetchMessages = FetchMessagesUseCase(messageRepository: messageRepository)
        let applySettings = ApplySettingsUseCase(settingsRepository: settingsRepository)
        let fetchSettings = FetchSettingsUseCase(settingsRepository: settingsRepository)
        let collectMetrics = CollectSessionMetricsUseCase(metricsRepository: metricsRepository)
        let vacationReducer = VacationPlannerReducer()
        let answerExtractionService = LLMAnswerExtractionService(llmClient: llmClient)
        let processUserAnswer = ProcessUserAnswerUseCase(
            answerExtractionService: answerExtractionService,
            confidenceThreshold: 0.7
        )
        let vacationOrchestrator = VacationPlanningOrchestrator(
            stateRepository: vacationStateRepository,
            planRepository: vacationPlanRepository,
            settingsRepository: settingsRepository,
            reducer: vacationReducer,
            processUserAnswerUseCase: processUserAnswer,
            questionGenerationService: LLMQuestionGenerationService(llmClient: llmClient),
            questionnaireSchema: VacationQuestionnaireSchemaAdapter.schema,
            optionGenerationService: MockVacationOptionGenerationService(),
            itineraryService: MockVacationItineraryService(),
            budgetEstimator: MockVacationBudgetEstimator(),
            mcpWeatherService: mcpToolDiscoveryService
        )
        let startVacationPlanning = StartVacationPlanningUseCase(orchestrator: vacationOrchestrator)
        let handleVacationPlanningEvent = HandleVacationPlanningEventUseCase(orchestrator: vacationOrchestrator)
        let getVacationPlanningStatus = GetVacationPlanningStatusUseCase(stateRepository: vacationStateRepository)
        let finalizeVacationPlan = FinalizeVacationPlanUseCase(
            stateRepository: vacationStateRepository,
            planRepository: vacationPlanRepository
        )
        let fetchVacationPlannerMCPTools = FetchVacationPlannerMCPToolsUseCase(
            toolDiscoveryService: mcpToolDiscoveryService
        )
        let mockTaskAgentOrchestrator = MockTaskAgentOrchestrator(
            stateRepository: mockTaskAgentStateRepository
        )
        let startMockTaskAgent = StartMockTaskAgentUseCase(orchestrator: mockTaskAgentOrchestrator)
        let handleMockTaskAgentEvent = HandleMockTaskAgentEventUseCase(orchestrator: mockTaskAgentOrchestrator)
        let getMockTaskAgentStatus = GetMockTaskAgentStatusUseCase(stateRepository: mockTaskAgentStateRepository)
        let counterTaskAgentOrchestrator = CounterTaskAgentOrchestrator(
            stateRepository: counterTaskAgentStateRepository
        )
        let startCounterTaskAgent = StartCounterTaskAgentUseCase(orchestrator: counterTaskAgentOrchestrator)
        let stopCounterTaskAgent = StopCounterTaskAgentUseCase(orchestrator: counterTaskAgentOrchestrator)
        let configureCounterTaskAgentInterval = ConfigureCounterTaskAgentIntervalUseCase(
            orchestrator: counterTaskAgentOrchestrator
        )
        let tickCounterTaskAgent = TickCounterTaskAgentUseCase(orchestrator: counterTaskAgentOrchestrator)
        let getCounterTaskAgentStatus = GetCounterTaskAgentStatusUseCase(stateRepository: counterTaskAgentStateRepository)
        let hackerNewsLLMSummaryService = HackerNewsLLMSummaryService(
            llmClient: llmClient,
            settingsRepository: settingsRepository
        )
        let hackerNewsTaskAgentOrchestrator = HackerNewsTaskAgentOrchestrator(
            stateRepository: hackerNewsTaskAgentStateRepository,
            mcpService: mcpToolDiscoveryService,
            llmSummaryService: hackerNewsLLMSummaryService
        )
        let startHackerNewsTaskAgent = StartHackerNewsTaskAgentUseCase(orchestrator: hackerNewsTaskAgentOrchestrator)
        let stopHackerNewsTaskAgent = StopHackerNewsTaskAgentUseCase(orchestrator: hackerNewsTaskAgentOrchestrator)
        let getHackerNewsTaskAgentStatus = GetHackerNewsTaskAgentStatusUseCase(
            stateRepository: hackerNewsTaskAgentStateRepository
        )
        let sessionID = UUID()
        let branchID = UUID()

        let rootSession = ChatSession(
            id: sessionID,
            title: "New Chat",
            activeBranchID: branchID,
            createdAt: Date()
        )
        let rootBranch = ChatBranch(
            id: branchID,
            sessionID: sessionID,
            parentCheckpointID: nil,
            name: "main",
            createdAt: Date()
        )

        try? await sessionRepository.saveSession(rootSession)
        try? await branchRepository.saveBranch(rootBranch)
        let initialSettings = (try? await settingsRepository.fetchSettings(sessionID: sessionID)) ?? .default
        try? await settingsRepository.saveSettings(sessionID: sessionID, settings: initialSettings)
        let ragDocuments = defaultRAGDocumentURLs()
        let startupIndexedRAGStrategy = await preloadRAGIndexOnStartup(
            ragUseCaseFacade: ragUseCaseFacade,
            settings: initialSettings,
            documents: ragDocuments
        )
        let sendMessage = SendMessageUseCase(
            settingsRepository: settingsRepository,
            messageRepository: messageRepository,
            llmClient: llmClient,
            buildMemoryContextUseCase: buildMemoryContext,
            updateShortTermMemoryUseCase: updateShortTermMemory,
            updateWorkingMemoryUseCase: updateWorkingMemory,
            updateLongTermMemoryUseCase: updateLongTermMemory,
            metricsRepository: metricsRepository,
            ragUseCaseFacade: ragUseCaseFacade,
            ragDocumentsProvider: {
                ragDocuments
            },
            initialIndexedRAGStrategy: startupIndexedRAGStrategy
        )

        AppLogger.shared.info("Bootstrap окружения приложения завершен", category: "app.bootstrap")
        return AppEnvironment(
            session: rootSession,
            sendMessageUseCase: sendMessage,
            fetchMessagesUseCase: fetchMessages,
            applySettingsUseCase: applySettings,
            fetchSettingsUseCase: fetchSettings,
            collectSessionMetricsUseCase: collectMetrics,
            loadAPIKeyUseCase: loadAPIKey,
            saveAPIKeyUseCase: saveAPIKey,
            startVacationPlanningUseCase: startVacationPlanning,
            handleVacationPlanningEventUseCase: handleVacationPlanningEvent,
            getVacationPlanningStatusUseCase: getVacationPlanningStatus,
            finalizeVacationPlanUseCase: finalizeVacationPlan,
            fetchVacationPlannerMCPToolsUseCase: fetchVacationPlannerMCPTools,
            startMockTaskAgentUseCase: startMockTaskAgent,
            handleMockTaskAgentEventUseCase: handleMockTaskAgentEvent,
            getMockTaskAgentStatusUseCase: getMockTaskAgentStatus,
            startCounterTaskAgentUseCase: startCounterTaskAgent,
            stopCounterTaskAgentUseCase: stopCounterTaskAgent,
            configureCounterTaskAgentIntervalUseCase: configureCounterTaskAgentInterval,
            tickCounterTaskAgentUseCase: tickCounterTaskAgent,
            getCounterTaskAgentStatusUseCase: getCounterTaskAgentStatus,
            startHackerNewsTaskAgentUseCase: startHackerNewsTaskAgent,
            stopHackerNewsTaskAgentUseCase: stopHackerNewsTaskAgent,
            getHackerNewsTaskAgentStatusUseCase: getHackerNewsTaskAgentStatus,
            ragUseCaseFacade: ragUseCaseFacade
        )
    }

    private static func routerAICompatibleBaseURL(endpoint: URL) -> String {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        let completionSuffix = "/chat/completions"
        if let path = components?.path, path.hasSuffix(completionSuffix) {
            let trimmedPath = String(path.dropLast(completionSuffix.count))
            components?.path = trimmedPath.isEmpty ? "/" : trimmedPath
        }
        return components?.url?.absoluteString ?? "https://api.openai.com/v1"
    }

    private static func defaultRAGDocumentURLs() -> [URL] {
        for baseDirectory in ragBaseDirectoryCandidates() {
            let urls = RAGModuleFactory.defaultDocumentURLs(baseDirectory: baseDirectory)
            if !urls.isEmpty {
                return urls
            }
        }
        return []
    }

    private static func preloadRAGIndexOnStartup(
        ragUseCaseFacade: RAGUseCaseFacadeProtocol,
        settings: LLMSettings,
        documents: [URL]
    ) async -> ChunkingStrategyType? {
        guard !documents.isEmpty else {
            AppLogger.shared.info(
                "Пропуск стартовой индексации RAG: документы не найдены",
                category: "app.bootstrap.rag"
            )
            return nil
        }

        if isPersistedRAGIndexAvailable(for: settings.ragChunkingStrategy) {
            AppLogger.shared.info(
                "Пропуск стартовой индексации RAG: используется сохраненный индекс, strategy=\(settings.ragChunkingStrategy.rawValue)",
                category: "app.bootstrap.rag"
            )
            return settings.ragChunkingStrategy
        }

        do {
            let summary = try await ragUseCaseFacade.index(documents: documents, strategy: settings.ragChunkingStrategy)
            markPersistedRAGIndexReady(for: settings.ragChunkingStrategy)
            AppLogger.shared.info(
                "Стартовая индексация RAG завершена: documents=\(summary.documentCount), chunks=\(summary.chunkCount), strategy=\(settings.ragChunkingStrategy.rawValue)",
                category: "app.bootstrap.rag"
            )
            return settings.ragChunkingStrategy
        } catch {
            AppLogger.shared.warning(
                "Стартовая индексация RAG завершилась с ошибкой: \(error)",
                category: "app.bootstrap.rag"
            )
            return nil
        }
    }

    private static func ragIndexReadyDefaultsKey(for strategy: ChunkingStrategyType) -> String {
        "rag.index.ready.\(strategy.rawValue)"
    }

    private static func isPersistedRAGIndexAvailable(for strategy: ChunkingStrategyType) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ragIndexReadyDefaultsKey(for: strategy)) else {
            return false
        }
        let databaseURL = SQLiteVSSVectorStore.defaultDatabaseURL()
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return false
        }
        let size = (try? databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
    }

    private static func markPersistedRAGIndexReady(for strategy: ChunkingStrategyType) {
        UserDefaults.standard.set(true, forKey: ragIndexReadyDefaultsKey(for: strategy))
    }

    private static func ragBaseDirectoryCandidates() -> [URL] {
        var candidates: [URL] = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        ]

        // Works reliably when app is launched from Xcode: use compile-time source path.
        let sourceFileURL = URL(fileURLWithPath: #filePath, isDirectory: false)
        let repoRootFromSource = sourceFileURL
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // LightNeiroClient (app sources)
            .deletingLastPathComponent() // LightNeiroClient (xcodeproj folder)
            .deletingLastPathComponent() // repo root
        candidates.append(repoRootFromSource)

        // Fallback for rare launch contexts where currentDirectoryPath points inside project.
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .deletingLastPathComponent()
        )

        var unique: [URL] = []
        var seen = Set<String>()
        for candidate in candidates {
            let path = candidate.standardizedFileURL.path
            if !seen.contains(path) {
                seen.insert(path)
                unique.append(candidate)
            }
        }
        return unique
    }
}
