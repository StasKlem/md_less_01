import Foundation

struct AppEnvironment {
    let sessionID: UUID
    let branchID: UUID

    let sendMessageUseCase: SendMessageUseCaseProtocol
    let applySettingsUseCase: ApplySettingsUseCaseProtocol
    let collectSessionMetricsUseCase: CollectSessionMetricsUseCaseProtocol
    let switchBranchUseCase: SwitchBranchUseCaseProtocol

    static func bootstrap() async -> AppEnvironment {
        let sessionRepository = MockChatSessionRepository()
        let branchRepository = MockBranchRepository()
        let messageRepository = MockMessageRepository()
        let factsRepository = MockFactsRepository()
        let settingsRepository = MockSettingsRepository()
        let metricsRepository = MockMetricsRepository()
        let llmClient = MockLLMClient()

        let buildContext = BuildContextUseCase(
            factsRepository: factsRepository,
            messageRepository: messageRepository
        )
        let updateFacts = UpdateFactsUseCase(factsRepository: factsRepository)
        let sendMessage = SendMessageUseCase(
            settingsRepository: settingsRepository,
            messageRepository: messageRepository,
            llmClient: llmClient,
            buildContextUseCase: buildContext,
            updateFactsUseCase: updateFacts,
            metricsRepository: metricsRepository
        )
        let applySettings = ApplySettingsUseCase(settingsRepository: settingsRepository)
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
            applySettingsUseCase: applySettings,
            collectSessionMetricsUseCase: collectMetrics,
            switchBranchUseCase: switchBranch
        )
    }
}
