//
//  ChatBehaviorStrategy.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

protocol ChatBehaviorStrategy: AnyObject {
    var summarizationService: SummarizationServiceProtocol? { get set }
    var summaryStorage: ConversationSummaryStorageProtocol? { get set }
    var settings: LLMSettings { get set }

    func prepareMessages(
        session: any ChatSessionProtocol,
        systemPrompt: String
    ) async -> [[String: String]]

    func shouldCreateSummary(session: any ChatSessionProtocol) async -> Bool

    func createSummaryIfNeeded(
        session: any ChatSessionProtocol,
        metricsViewModel: MetricsViewModel?,
        keychainService: KeychainServiceProtocol?,
        onSummaryCreated: ((String) -> Void)?
    ) async

    func clearSession(session: any ChatSessionProtocol) async
}

protocol ChatBehaviorStrategyFactoryProtocol {
    func makeStrategy(
        for settings: LLMSettings,
        summarizationService: SummarizationServiceProtocol?,
        summaryStorage: ConversationSummaryStorageProtocol?
    ) -> ChatBehaviorStrategy
}

final class ChatBehaviorStrategyFactory: ChatBehaviorStrategyFactoryProtocol {
    func makeStrategy(
        for settings: LLMSettings,
        summarizationService: SummarizationServiceProtocol?,
        summaryStorage: ConversationSummaryStorageProtocol?
    ) -> ChatBehaviorStrategy {
        let strategy: ChatBehaviorStrategy

        switch settings.summarizationStrategy {
        case .none:
            strategy = BasicChatStrategy(settings: settings)
        case .keepLastMessages(let count):
            strategy = SummarizationChatStrategy(settings: settings, messagesToKeep: count)
        case .windowLastMessages(let count):
            strategy = WindowedContextChatStrategy(settings: settings, messagesToKeep: count)
        }

        strategy.summarizationService = summarizationService
        strategy.summaryStorage = summaryStorage

        return strategy
    }
}
