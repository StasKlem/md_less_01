//
//  BasicChatStrategy.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

final class BasicChatStrategy: ChatBehaviorStrategy {

    var summarizationService: SummarizationServiceProtocol?
    var summaryStorage: ConversationSummaryStorageProtocol?
    var settings: LLMSettings

    init(settings: LLMSettings) {
        self.settings = settings
    }

    func prepareMessages(
        session: ChatSession,
        systemPrompt: String
    ) async -> [[String: String]] {
        return await session.messagesForAPI()
    }

    func shouldCreateSummary(session: ChatSession) async -> Bool {
        return false
    }

    func createSummaryIfNeeded(
        session: ChatSession,
        metricsViewModel: MetricsViewModel?,
        keychainService: KeychainServiceProtocol?,
        onSummaryCreated: ((String) -> Void)?
    ) async {
    }

    func clearSession(session: ChatSession) async {
    }
}
