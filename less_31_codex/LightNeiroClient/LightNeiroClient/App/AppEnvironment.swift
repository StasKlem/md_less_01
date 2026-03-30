import Foundation

struct AppEnvironment {
    let session: ChatSession

    let sendMessageUseCase: SendMessageUseCaseProtocol
    let fetchMessagesUseCase: FetchMessagesUseCaseProtocol
    let clearDialogUseCase: ClearDialogUseCaseProtocol
    let applySettingsUseCase: ApplySettingsUseCaseProtocol
    let fetchSettingsUseCase: FetchSettingsUseCaseProtocol
    let resetRAGEmbeddingsUseCase: ResetRAGEmbeddingsUseCaseProtocol
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
    let projectHelpUseCase: ProjectHelpUseCaseProtocol
    let ragUseCaseFacade: RAGUseCaseFacadeProtocol
    private static let globalSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    private static let globalBranchID = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()

    static func bootstrap() async -> AppEnvironment {
        AppLogger.shared.info("Начало bootstrap окружения приложения", category: "app.bootstrap")
        let messageRepository = FileMessageRepository()
        let shortTermRepository = FileShortTermMemoryRepository()
        let workingMemoryRepository = FileWorkingMemoryRepository()
        let longTermMemoryRepository = FileLongTermMemoryRepository()
        let factsRepository = FileFactsRepository()
        let settingsRepository = UserDefaultsSettingsRepository()
        let ragIndexReadinessRepository = UserDefaultsRAGIndexReadinessRepository()
        let metricsRepository = FileMetricsRepository()
        let vacationStateRepository = FileVacationPlanningStateRepository()
        let vacationPlanRepository = FileVacationPlanRepository()
        let mockTaskAgentStateRepository = FileMockTaskAgentStateRepository()
        let counterTaskAgentStateRepository = FileCounterTaskAgentStateRepository()
        let hackerNewsTaskAgentStateRepository = FileHackerNewsTaskAgentStateRepository()
        let apiKeyStore = KeychainAPIKeyStore()
        let httpClient = makeHTTPClient()
        let llmConfigurationProvider: @Sendable () async -> RouterAIConfiguration = {
            let settings = (try? await settingsRepository.fetchSettings()) ?? .default
            let apiKey = try? apiKeyStore.fetchAPIKey()
            return Self.llmConfiguration(for: settings, apiKey: apiKey)
        }
        let mcpToolDiscoveryService = MCPToolDiscoveryService(
            hackerNewsTranslateEnvironmentProvider: { _ in
                let settings = (try? await settingsRepository.fetchSettings()) ?? .default
                let configuration = await llmConfigurationProvider()
                var environmentOverrides: [String: String] = [
                    "HACKERNEWS_TRANSLATE_OPENAI_MODEL": settings.model.rawValue,
                    "HACKERNEWS_TRANSLATE_OPENAI_BASE_URL": Self.routerAICompatibleBaseURL(
                        endpoint: configuration.endpoint
                    )
                ]
                if Self.requiresAPIKey(for: configuration.endpoint),
                   let apiKey = try? apiKeyStore.fetchAPIKey() {
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
            httpClient: httpClient,
            configurationProvider: {
                let settings = (try? await settingsRepository.fetchSettings()) ?? .default
                let apiKey = try? apiKeyStore.fetchAPIKey()
                return Self.llmConfiguration(for: settings, apiKey: apiKey)
            }
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
                httpClient: httpClient,
                configurationProvider: {
                    let settings = (try? await settingsRepository.fetchSettings()) ?? .default
                    let apiKey = try? apiKeyStore.fetchAPIKey()
                    return Self.llmConfiguration(for: settings, apiKey: apiKey)
                }
            )
        )
        let fetchMessages = FetchMessagesUseCase(messageRepository: messageRepository)
        let clearDialog = ClearDialogUseCase(
            messageRepository: messageRepository,
            shortTermRepository: shortTermRepository,
            workingMemoryRepository: workingMemoryRepository,
            longTermMemoryRepository: longTermMemoryRepository,
            metricsRepository: metricsRepository
        )
        let applySettings = ApplySettingsUseCase(settingsRepository: settingsRepository)
        let fetchSettings = FetchSettingsUseCase(settingsRepository: settingsRepository)
        let resetRAGEmbeddings = ResetRAGEmbeddingsUseCase(
            ragUseCaseFacade: ragUseCaseFacade,
            ragIndexReadinessRepository: ragIndexReadinessRepository
        )
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
        let rootSession = ChatSession(
            id: Self.globalSessionID,
            title: "New Chat",
            activeBranchID: Self.globalBranchID,
            createdAt: Date()
        )
        let initialSettings = (try? await settingsRepository.fetchSettings()) ?? .default
        try? await settingsRepository.saveSettings(settings: initialSettings)
        let ragDocuments = defaultRAGDocumentURLs()
        let startupIndexedRAGStrategy = await preloadRAGIndexOnStartup(
            ragUseCaseFacade: ragUseCaseFacade,
            settings: initialSettings,
            documents: ragDocuments,
            ragIndexReadinessRepository: ragIndexReadinessRepository
        )
        let projectHelpUseCase = ProjectHelpUseCase(
            settingsRepository: settingsRepository,
            llmClient: llmClient,
            ragUseCaseFacade: ragUseCaseFacade,
            projectContextService: mcpToolDiscoveryService,
            ragDocumentsProvider: {
                ragDocuments
            },
            initialIndexedRAGStrategy: startupIndexedRAGStrategy
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
            clearDialogUseCase: clearDialog,
            applySettingsUseCase: applySettings,
            fetchSettingsUseCase: fetchSettings,
            resetRAGEmbeddingsUseCase: resetRAGEmbeddings,
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
            projectHelpUseCase: projectHelpUseCase,
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

    private static func llmConfiguration(for settings: LLMSettings, apiKey: String?) -> RouterAIConfiguration {
        RouterAIConfiguration(
            endpoint: settings.backend.endpoint,
            timeoutInterval: RouterAIConfiguration.default.timeoutInterval,
            apiKeyProvider: {
                apiKey
            }
        )
    }

    private static func requiresAPIKey(for endpoint: URL) -> Bool {
        guard let host = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)?.host?.lowercased() else {
            return true
        }
        return host != "localhost" && host != "127.0.0.1" && host != "::1"
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
        documents: [URL],
        ragIndexReadinessRepository: RAGIndexReadinessRepositoryProtocol
    ) async -> ChunkingStrategyType? {
        guard !documents.isEmpty else {
            AppLogger.shared.info(
                "Пропуск стартовой индексации RAG: документы не найдены",
                category: "app.bootstrap.rag"
            )
            return nil
        }

        if isPersistedRAGIndexAvailable(
            for: settings.ragChunkingStrategy,
            ragIndexReadinessRepository: ragIndexReadinessRepository
        ) {
            AppLogger.shared.info(
                "Пропуск стартовой индексации RAG: используется сохраненный индекс, strategy=\(settings.ragChunkingStrategy.rawValue)",
                category: "app.bootstrap.rag"
            )
            return settings.ragChunkingStrategy
        }

        do {
            let summary = try await ragUseCaseFacade.index(documents: documents, strategy: settings.ragChunkingStrategy)
            ragIndexReadinessRepository.markReady(for: settings.ragChunkingStrategy)
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

    private static func isPersistedRAGIndexAvailable(
        for strategy: ChunkingStrategyType,
        ragIndexReadinessRepository: RAGIndexReadinessRepositoryProtocol
    ) -> Bool {
        guard ragIndexReadinessRepository.isReady(for: strategy) else {
            return false
        }
        let databaseURL = SQLiteVSSVectorStore.defaultDatabaseURL()
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return false
        }
        let size = (try? databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
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
