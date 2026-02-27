//
//  KeepLastMessagesStrategy.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

/// Strategy that keeps the last N messages as-is
/// Older messages are replaced with a summary
/// The summary is stored separately and prepended to the request
final class KeepLastMessagesStrategy: SummarizationStrategyProtocol {
    
    private let lastN: Int
    private let summaryService: SummarizationServiceProtocol
    
    /// Initializes the strategy
    /// - Parameters:
    ///   - lastN: Number of recent messages to keep without summarization
    ///   - summaryService: Service for generating summaries
    init(lastN: Int, summaryService: SummarizationServiceProtocol) {
        self.lastN = max(1, lastN)
        self.summaryService = summaryService
    }
    
    func apply(messages: [Message], summaryPrompt: String) async -> SummarizationResult {
        // If we have fewer or equal messages than the limit, no summarization needed
        guard messages.count > lastN else {
            let messagesForAPI: [[String: String]] = messages.compactMap { message in
                guard message.error == nil else { return nil }
                return [
                    "role": message.role.rawValue,
                    "content": message.content
                ]
            }

            return SummarizationResult(
                messagesForAPI: messagesForAPI,
                summary: nil,
                summarizedCount: 0
            )
        }
        
        // Calculate how many messages need to be summarized
        let messagesToSummarizeCount = messages.count - lastN
        
        // Get messages that need summarization
        let messagesToSummarize = Array(messages.prefix(messagesToSummarizeCount))
        
        // Get the last N messages to keep as-is
        let recentMessages = Array(messages.suffix(lastN))
        
        // Generate or retrieve summary for old messages
        let summary = await summaryService.getOrCreateSummary(
            for: messagesToSummarize,
            promptTemplate: summaryPrompt
        )
        
        // Build final messages array with summary as system context
        var messagesForAPI: [[String: String]] = []
        
        // Add summary as a system message at the beginning
        if !summary.isEmpty {
            messagesForAPI.append([
                "role": "system",
                "content": summary
            ])
        }
        
        // Add recent messages
        for message in recentMessages {
            guard message.error == nil else { continue }
            messagesForAPI.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }
        
        return SummarizationResult(
            messagesForAPI: messagesForAPI,
            summary: summary.isEmpty ? nil : summary,
            summarizedCount: messagesToSummarizeCount
        )
    }
}
