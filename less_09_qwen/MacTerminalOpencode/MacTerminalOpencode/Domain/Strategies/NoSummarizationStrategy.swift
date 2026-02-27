//
//  NoSummarizationStrategy.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

/// Strategy that does not perform any summarization
/// All messages are kept as-is and sent to the API
final class NoSummarizationStrategy: SummarizationStrategyProtocol {
    
    func apply(messages: [Message], summaryPrompt: String) async -> SummarizationResult {
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
}
