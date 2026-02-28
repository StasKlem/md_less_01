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
        session: any ChatSessionProtocol,
        systemPrompt: String
    ) async -> [[String: String]] {
        return await session.messagesForAPI(systemPrompt: systemPrompt, summarizationStrategy: .none)
    }

    func shouldCreateSummary(session: any ChatSessionProtocol) async -> Bool {
        return false
    }

    func createSummaryIfNeeded(
        session: any ChatSessionProtocol,
        metricsViewModel: MetricsViewModel?,
        keychainService: KeychainServiceProtocol?,
        onSummaryCreated: ((String) -> Void)?
    ) async {
    }

    func clearSession(session: any ChatSessionProtocol) async {
    }
}

final class WindowedContextChatStrategy: ChatBehaviorStrategy {

    var summarizationService: SummarizationServiceProtocol?
    var summaryStorage: ConversationSummaryStorageProtocol?
    var settings: LLMSettings

    private let messagesToKeep: Int

    init(settings: LLMSettings, messagesToKeep: Int = SummarizationStrategy.defaultCount) {
        self.settings = settings
        self.messagesToKeep = messagesToKeep
    }

    func prepareMessages(
        session: any ChatSessionProtocol,
        systemPrompt: String
    ) async -> [[String: String]] {
        var result: [[String: String]] = []

        if !systemPrompt.isEmpty {
            result.append(["role": "system", "content": systemPrompt])
        }

        let messages = await session.messages
            .filter { $0.error == nil && !$0.content.isEmpty }
            .filter { $0.role == .user || $0.role == .assistant }

        let window = Array(messages.suffix(messagesToKeep))
        result.append(contentsOf: window.map { ["role": $0.role.rawValue, "content": $0.content] })

        return result
    }

    func shouldCreateSummary(session: any ChatSessionProtocol) async -> Bool {
        false
    }

    func createSummaryIfNeeded(
        session: any ChatSessionProtocol,
        metricsViewModel: MetricsViewModel?,
        keychainService: KeychainServiceProtocol?,
        onSummaryCreated: ((String) -> Void)?
    ) async {
    }

    func clearSession(session: any ChatSessionProtocol) async {
    }
}
