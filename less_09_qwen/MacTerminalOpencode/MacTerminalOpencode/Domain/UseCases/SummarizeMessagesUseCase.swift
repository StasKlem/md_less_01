//
//  SummarizeMessagesUseCase.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

/// Use case for summarizing chat messages
protocol SummarizeMessagesUseCaseProtocol {
    /// Summarizes messages according to the configured strategy
    /// - Parameters:
    ///   - messages: Messages to summarize
    ///   - strategy: Summarization strategy to apply
    ///   - summaryPrompt: Prompt template for summary generation
    /// - Returns: Summarization result
    func execute(
        messages: [Message],
        strategy: SummarizationStrategy,
        summaryPrompt: String
    ) async -> SummarizationResult
}

/// Implementation of SummarizeMessagesUseCaseProtocol
final class SummarizeMessagesUseCase: SummarizeMessagesUseCaseProtocol {
    
    private let summaryStorage: SummaryStorageProtocol
    private let apiClient: LLMAPIClientProtocol
    private let settings: LLMSettings
    
    init(
        summaryStorage: SummaryStorageProtocol,
        apiClient: LLMAPIClientProtocol,
        settings: LLMSettings
    ) {
        self.summaryStorage = summaryStorage
        self.apiClient = apiClient
        self.settings = settings
    }
    
    func execute(
        messages: [Message],
        strategy: SummarizationStrategy,
        summaryPrompt: String
    ) async -> SummarizationResult {
        switch strategy {
        case .none:
            let strategyImpl = NoSummarizationStrategy()
            return await strategyImpl.apply(messages: messages, summaryPrompt: summaryPrompt)
            
        case .keepLastMessages(let count):
            let summaryService = SummarizationService(
                apiClient: apiClient,
                settings: settings,
                summaryStorage: summaryStorage
            )
            let strategyImpl = KeepLastMessagesStrategy(
                lastN: count,
                summaryService: summaryService
            )
            return await strategyImpl.apply(messages: messages, summaryPrompt: summaryPrompt)
        }
    }
}
