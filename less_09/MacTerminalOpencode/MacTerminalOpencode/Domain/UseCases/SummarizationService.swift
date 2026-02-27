//
//  SummarizationService.swift
//  MacTerminalOpencode
//
//  Created by Stas Klem on 26.02.2026.
//

import Foundation

protocol SummarizationServiceProtocol {
    func createSummary(
        messagesToSummarize: [Message],
        previousSummary: String?,
        newMessage: String,
        settings: LLMSettings,
        apiKey: String?
    ) async throws -> (summary: String, promptTokens: Int, completionTokens: Int)
}

final class SummarizationService: SummarizationServiceProtocol {

    private let apiClient: LLMAPIClientProtocol

    init(apiClient: LLMAPIClientProtocol) {
        self.apiClient = apiClient
    }

    /// Создаёт summary:
    /// - Если нет предыдущего summary: отправляем все сообщения из диалога (user + assistant)
    /// - Если есть предыдущее summary: отправляем предыдущее summary + новое сообщение
    func createSummary(
        messagesToSummarize: [Message],
        previousSummary: String?,
        newMessage: String,
        settings: LLMSettings,
        apiKey: String?
    ) async throws -> (summary: String, promptTokens: Int, completionTokens: Int) {

        var messagesForSummary: [[String: String]] = []

        // 1. System prompt с инструкцией для суммаризации
        messagesForSummary.append([
            "role": "system",
            "content": settings.summarizationPrompt
        ])

        // 2. Формируем user message
        var userContent = ""

        if let previousSummary = previousSummary, !previousSummary.isEmpty {
            // Есть предыдущая суммаризация - добавляем её + новое сообщение
            userContent = "Предыдущее резюме: \(previousSummary)\n\nНовое сообщение для добавления в резюме: \(newMessage)"
            print("[SummarizationService] Using previous summary + new message")
        } else {
            // Нет предыдущей суммаризации - отправляем все сообщения
            userContent = buildConversationText(from: messagesToSummarize)
            if !newMessage.isEmpty {
                userContent += "\n\nНовое сообщение для добавления в резюме: \(newMessage)"
            }
            print("[SummarizationService] No previous summary - using all \(messagesToSummarize.count) messages")
        }

        messagesForSummary.append([
            "role": "user",
            "content": userContent
        ])

        print("[SummarizationService] Creating summary with format:")
        print("  - Previous summary: \(previousSummary != nil ? "yes" : "no")")
        print("  - Messages to summarize: \(messagesToSummarize.count)")
        print("  - New message: \(newMessage.prefix(50))...")

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
