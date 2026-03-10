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

    static func bootstrap() async -> AppEnvironment {
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
        let mcpToolDiscoveryService = MCPToolDiscoveryService()
        let apiKeyStore = KeychainAPIKeyStore()
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
        let fetchMessages = FetchMessagesUseCase(messageRepository: messageRepository)
        let sendMessage = SendMessageUseCase(
            settingsRepository: settingsRepository,
            messageRepository: messageRepository,
            llmClient: llmClient,
            buildMemoryContextUseCase: buildMemoryContext,
            updateShortTermMemoryUseCase: updateShortTermMemory,
            updateWorkingMemoryUseCase: updateWorkingMemory,
            updateLongTermMemoryUseCase: updateLongTermMemory,
            metricsRepository: metricsRepository
        )
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
            budgetEstimator: MockVacationBudgetEstimator()
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
            fetchVacationPlannerMCPToolsUseCase: fetchVacationPlannerMCPTools
        )
    }
}
