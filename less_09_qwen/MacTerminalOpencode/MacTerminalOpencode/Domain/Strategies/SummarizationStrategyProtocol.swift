//
//  SummarizationStrategyProtocol.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

/// Protocol defining a message summarization strategy
protocol SummarizationStrategyProtocol {
    /// Applies the summarization strategy to the given messages
    /// - Parameters:
    ///   - messages: Array of messages to process
    ///   - summaryPrompt: Prompt template for generating summary
    /// - Returns: Tuple containing processed messages and optional summary
    func apply(messages: [Message], summaryPrompt: String) async -> SummarizationResult
}

/// Result of applying a summarization strategy
struct SummarizationResult {
    /// Messages to be sent to the API (includes summary if applicable)
    let messagesForAPI: [[String: String]]
    /// Optional summary that was generated or used
    let summary: String?
    /// Number of messages that were summarized
    let summarizedCount: Int
}
