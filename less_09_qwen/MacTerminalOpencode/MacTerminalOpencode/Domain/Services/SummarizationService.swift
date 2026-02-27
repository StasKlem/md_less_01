//
//  SummarizationService.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

/// Service for generating and managing message summaries
final class SummarizationService: SummarizationServiceProtocol {
    
    private let apiClient: LLMAPIClientProtocol
    private let settings: LLMSettings
    private let summaryStorage: SummaryStorageProtocol
    
    /// Initializes the summarization service
    /// - Parameters:
    ///   - apiClient: API client for generating summaries
    ///   - settings: LLM settings for summary generation
    ///   - summaryStorage: Storage for persisting summaries
    init(
        apiClient: LLMAPIClientProtocol,
        settings: LLMSettings,
        summaryStorage: SummaryStorageProtocol
    ) {
        self.apiClient = apiClient
        self.settings = settings
        self.summaryStorage = summaryStorage
    }
    
    func getOrCreateSummary(for messages: [Message], promptTemplate: String) async -> String {
        // Check if we have a cached summary
        if let cachedSummary = summaryStorage.loadSummary() {
            return cachedSummary
        }
        
        // Generate new summary
        let summary = await generateSummary(for: messages, promptTemplate: promptTemplate)
        
        // Cache the summary
        summaryStorage.saveSummary(summary)
        
        return summary
    }
    
    func clearSummary() {
        summaryStorage.clearSummary()
    }
    
    private func generateSummary(for messages: [Message], promptTemplate: String) async -> String {
        guard !messages.isEmpty else { return "" }
        
        // Build the conversation text for summarization
        let conversationText = messages.map { message in
            "\(message.role.rawValue.capitalized): \(message.content)"
        }.joined(separator: "\n\n")
        
        // Create the summary prompt
        let summaryPrompt = "\(promptTemplate)\n\n\(conversationText)"
        
        // Create a single message for summary generation
        let summaryMessages: [[String: String]] = [
            [
                "role": "user",
                "content": summaryPrompt
            ]
        ]
        
        do {
            // Use non-streaming mode for summary generation
            let (response, _, _, _) = try await apiClient.sendMessage(
                messages: summaryMessages,
                settings: settings,
                apiKey: nil // Summary generation doesn't need API key validation
            )
            return response
        } catch {
            print("[SummarizationService] Failed to generate summary: \(error)")
            // Return conversation text as fallback
            return conversationText
        }
    }
}
