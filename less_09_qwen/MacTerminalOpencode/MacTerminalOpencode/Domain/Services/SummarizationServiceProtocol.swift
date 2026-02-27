//
//  SummarizationServiceProtocol.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

/// Protocol for message summarization service
protocol SummarizationServiceProtocol {
    /// Generates or retrieves a summary for the given messages
    /// - Parameters:
    ///   - messages: Messages to summarize
    ///   - promptTemplate: Template for the summary prompt
    /// - Returns: Summary text
    func getOrCreateSummary(for messages: [Message], promptTemplate: String) async -> String
    
    /// Clears the cached summary
    func clearSummary()
}
