import Foundation

struct AppEnvironment {
    let sessionID: UUID
    let branchID: UUID

    let sendMessageUseCase: SendMessageUseCaseProtocol
    let fetchBranchesUseCase: FetchBranchesUseCaseProtocol
    let fetchMessagesUseCase: FetchMessagesUseCaseProtocol
    let cloneDialogToBranchUseCase: CloneDialogToBranchUseCaseProtocol
    let createBranchUseCase: CreateBranchUseCaseProtocol
    let addBranchCreatedSystemMessageUseCase: AddBranchCreatedSystemMessageUseCaseProtocol
    let applySettingsUseCase: ApplySettingsUseCaseProtocol
    let fetchSettingsUseCase: FetchSettingsUseCaseProtocol
    let collectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol
    let switchBranchUseCase: SwitchBranchUseCaseProtocol
    let loadAPIKeyUseCase: LoadAPIKeyUseCaseProtocol
    let saveAPIKeyUseCase: SaveAPIKeyUseCaseProtocol

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
        let fetchBranches = FetchBranchesUseCase(branchRepository: branchRepository)
        let fetchMessages = FetchMessagesUseCase(messageRepository: messageRepository)
        let cloneDialogToBranch = CloneDialogToBranchUseCase(messageRepository: messageRepository)
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
        let createBranch = CreateBranchUseCase(branchRepository: branchRepository)
        let addBranchCreatedSystemMessage = AddBranchCreatedSystemMessageUseCase(messageRepository: messageRepository)
        let applySettings = ApplySettingsUseCase(settingsRepository: settingsRepository)
        let fetchSettings = FetchSettingsUseCase(settingsRepository: settingsRepository)
        let collectMetrics = CollectSessionMetricsUseCase(metricsRepository: metricsRepository)
        let switchBranch = SwitchBranchUseCase(sessionRepository: sessionRepository)

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
        try? await settingsRepository.saveSettings(sessionID: sessionID, settings: .default)

        return AppEnvironment(
            sessionID: sessionID,
            branchID: branchID,
            sendMessageUseCase: sendMessage,
            fetchBranchesUseCase: fetchBranches,
            fetchMessagesUseCase: fetchMessages,
            cloneDialogToBranchUseCase: cloneDialogToBranch,
            createBranchUseCase: createBranch,
            addBranchCreatedSystemMessageUseCase: addBranchCreatedSystemMessage,
            applySettingsUseCase: applySettings,
            fetchSettingsUseCase: fetchSettings,
            collectSessionMetricsUseCase: collectMetrics,
            switchBranchUseCase: switchBranch,
            loadAPIKeyUseCase: loadAPIKey,
            saveAPIKeyUseCase: saveAPIKey
        )
    }
}
