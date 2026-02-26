//
//  SummarizationService.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

protocol SummarizationServiceProtocol {
    func createSummary(messages: [Message], settings: LLMSettings, apiKey: String?) async throws -> (summary: String, promptTokens: Int, completionTokens: Int)
}

final class SummarizationService: SummarizationServiceProtocol {

    private let apiClient: LLMAPIClientProtocol

    init(apiClient: LLMAPIClientProtocol) {
        self.apiClient = apiClient
    }

    func createSummary(messages: [Message], settings: LLMSettings, apiKey: String?) async throws -> (summary: String, promptTokens: Int, completionTokens: Int) {
        let conversationText = buildConversationText(from: messages)

        var messagesForSummary: [[String: String]] = []
        messagesForSummary.append([
            "role": "system",
            "content": settings.summarizationPrompt
        ])
        messagesForSummary.append([
            "role": "user",
            "content": conversationText
        ])

        var summarySettings = settings
        summarySettings.enableStreaming = false

        let (content, promptTokens, completionTokens, _) = try await apiClient.sendMessage(
            messages: messagesForSummary,
            settings: summarySettings,
            apiKey: apiKey
        )

        return (content, promptTokens, completionTokens)
    }

    private func buildConversationText(from messages: [Message]) -> String {
        var text = "Диалог:\n"

        for message in messages {
            let roleName: String
            switch message.role {
            case .user:
                roleName = "Пользователь"
            case .assistant:
                roleName = "Ассистент"
            case .system:
                roleName = "Система"
            }

            text += "\n\(roleName): \(message.content)\n"
        }

        return text
    }
}
