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

        // 2. Если есть предыдущее summary - используем его + добавляем его
        //    Если нет - отправляем ВСЕ сообщения из диалога
        if let previousSummary = previousSummary, !previousSummary.isEmpty {
            messagesForSummary.append([
                "role": "system",
                "content": previousSummary
            ])
            messagesForSummary.append([
                "role": "user",
                "content": newMessage
            ])
            print("[SummarizationService] Using previous summary + new message")
        } else {
            // Нет предыдущего summary - отправляем ВСЕ сообщения (user + assistant)
            for message in messagesToSummarize {
                messagesForSummary.append([
                    "role": message.role.rawValue,
                    "content": message.content
                ])
            }
            // Добавляем новое сообщение
            messagesForSummary.append([
                "role": "user",
                "content": newMessage
            ])
            print("[SummarizationService] No previous summary - using all \(messagesToSummarize.count) messages")
        }

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
}
