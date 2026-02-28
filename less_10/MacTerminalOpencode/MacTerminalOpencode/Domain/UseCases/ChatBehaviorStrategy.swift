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
        session: ChatSession,
        systemPrompt: String
    ) async -> [[String: String]]

    func shouldCreateSummary(session: ChatSession) async -> Bool

    func createSummaryIfNeeded(
        session: ChatSession,
        metricsViewModel: MetricsViewModel?,
        keychainService: KeychainServiceProtocol?,
        onSummaryCreated: ((String) -> Void)?
    ) async

    func clearSession(session: ChatSession) async
}
